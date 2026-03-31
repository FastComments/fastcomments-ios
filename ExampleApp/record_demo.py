#!/usr/bin/env python3
"""
Demo video recording orchestrator for FastComments iOS.

Builds the test suite, then records each demo segment by running XCUITests
while capturing simulator video via `xcrun simctl io recordVideo`.

Usage:
    python3 record_demo.py                      # Record all segments
    python3 record_demo.py --segment 01         # Record one segment (name prefix match)
    python3 record_demo.py --skip-build          # Skip initial build
    python3 record_demo.py --sim-a ID --sim-b ID # Custom simulator UDIDs
"""

import argparse
import glob
import http.server
import json
import os
import signal
import subprocess
import sys
import threading
import time
from collections import defaultdict

# Default simulator UDIDs — same as run_dual_sim_tests.py
DEFAULT_SIM_A = "E4683E5D-8489-468D-8CA4-6985AD94B572"
DEFAULT_SIM_B = "DB94C97C-1CDF-4016-84E7-BF84A1ACF84F"

SYNC_PORT = 9999
PROJECT = "FastCommentsExample.xcodeproj"
SCHEME = "FastCommentsExample"

SEGMENTS = [
    {
        "name": "01_beautiful_comments",
        "type": "single",
        "test": "FastCommentsUITests/DemoSingleSim_UITests/testSegment1_BeautifulComments",
    },
    {
        "name": "02_rich_interactions",
        "type": "single",
        "test": "FastCommentsUITests/DemoSingleSim_UITests/testSegment2_RichInteractions",
    },
    {
        "name": "03_live_sync",
        "type": "dual",
        "testA": "FastCommentsUITests/DemoUserA_UITests/testSegment3_LiveSync",
        "testB": "FastCommentsUITests/DemoUserB_UITests/testSegment3_LiveSync",
    },
    {
        "name": "04_live_chat",
        "type": "single",
        "test": "FastCommentsUITests/DemoSingleSim_UITests/testSegment4_LiveChat",
    },
    {
        "name": "05_social_feed",
        "type": "single",
        "test": "FastCommentsUITests/DemoSingleSim_UITests/testSegment5_SocialFeed",
    },
    {
        "name": "06a_theme_flat",
        "type": "single",
        "test": "FastCommentsUITests/DemoSingleSim_UITests/testSegment6a_ThemeFlat",
    },
    {
        "name": "06b_theme_card",
        "type": "single",
        "test": "FastCommentsUITests/DemoSingleSim_UITests/testSegment6b_ThemeCard",
    },
    {
        "name": "06c_theme_bubble",
        "type": "single",
        "test": "FastCommentsUITests/DemoSingleSim_UITests/testSegment6c_ThemeBubble",
    },
]


# ---------------------------------------------------------------------------
# Sync Server (reused from run_dual_sim_tests.py for dual-sim segment)
# ---------------------------------------------------------------------------

class SyncServer:
    """Tiny HTTP server for test coordination between two simulator processes."""

    def __init__(self, port):
        self.port = port
        self.ready = defaultdict(dict)
        self.data = {}
        self.waiters = defaultdict(list)
        self.lock = threading.Lock()
        self.server = None

    def start(self):
        handler = self._make_handler()
        self.server = http.server.HTTPServer(("", self.port), handler)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        print(f"[sync] Server started on port {self.port}")

    def stop(self):
        if self.server:
            self.server.shutdown()
            print("[sync] Server stopped")

    def _make_handler(self):
        sync = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, fmt, *args):
                pass  # Suppress request logs

            def do_POST(self):
                path = self.path.split("?")[0]
                params = dict(
                    p.split("=") for p in self.path.split("?")[1].split("&")
                ) if "?" in self.path else {}

                if path == "/ready":
                    role = params.get("role", "")
                    round_id = params.get("round", "default")
                    with sync.lock:
                        sync.ready[round_id][role] = True
                        key = (round_id, role)
                        for evt in sync.waiters.get(key, []):
                            evt.set()
                        sync.waiters[key] = []
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b'{"ok":true}')

                elif path == "/data":
                    round_id = params.get("round", "default")
                    length = int(self.headers.get("Content-Length", 0))
                    body = self.rfile.read(length) if length else b"{}"
                    with sync.lock:
                        sync.data[round_id] = json.loads(body)
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b'{"ok":true}')

                else:
                    self.send_response(404)
                    self.end_headers()

            def do_GET(self):
                path = self.path.split("?")[0]
                params = dict(
                    p.split("=") for p in self.path.split("?")[1].split("&")
                ) if "?" in self.path else {}

                if path == "/wait":
                    wait_for = params.get("waitFor", "")
                    round_id = params.get("round", "default")
                    timeout = float(params.get("timeout", "120"))

                    evt = threading.Event()
                    with sync.lock:
                        if sync.ready.get(round_id, {}).get(wait_for):
                            evt.set()
                        else:
                            sync.waiters[(round_id, wait_for)].append(evt)

                    ok = evt.wait(timeout=timeout)
                    self.send_response(200 if ok else 408)
                    self.end_headers()
                    self.wfile.write(json.dumps({"ok": ok}).encode())

                elif path == "/data":
                    round_id = params.get("round", "default")
                    with sync.lock:
                        d = sync.data.get(round_id, {})
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(json.dumps(d).encode())

                elif path == "/health":
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b'{"ok":true}')

                else:
                    self.send_response(404)
                    self.end_headers()

        return Handler


# ---------------------------------------------------------------------------
# Recording helpers
# ---------------------------------------------------------------------------

def start_recording(sim_id, output_path):
    """Start recording a simulator. Returns the Popen process."""
    # Must use absolute path — simctl in its own session may resolve relative paths
    # from a different CWD, causing SimRenderServer error 2.
    abs_path = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(abs_path), exist_ok=True)
    # start_new_session=True is required — simctl recordVideo needs its own session
    # for proper SIGINT handling.
    proc = subprocess.Popen(
        ["xcrun", "simctl", "io", sim_id, "recordVideo", "--codec=h264", "--force", abs_path],
        start_new_session=True,
    )
    # Give simctl a moment to initialize recording
    time.sleep(1)
    return proc


def stop_recording(proc, timeout=10):
    """Gracefully stop a recording process and wait for finalization."""
    if proc.poll() is not None:
        return
    os.kill(proc.pid, signal.SIGINT)
    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        print("  [warn] Recording process didn't finalize in time, killing")
        proc.kill()
        proc.wait()


def run_xcodebuild_test(sim_id, test_filter, role=None):
    """Run xcodebuild test-without-building on a specific simulator."""
    if role:
        config = {"FC_SYNC_URL": f"http://localhost:{SYNC_PORT}", "FC_ROLE": role}
        with open(f"/tmp/fc-uitest-{role}.json", "w") as f:
            json.dump(config, f)

    cmd = [
        "xcodebuild", "test-without-building",
        "-project", PROJECT,
        "-scheme", SCHEME,
        "-destination", f"id={sim_id}",
        "-only-testing", test_filter,
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return proc


def stream_and_wait(proc, prefix="test"):
    """Stream xcodebuild output and wait for completion."""
    for line in iter(proc.stdout.readline, b""):
        text = line.decode("utf-8", errors="replace").rstrip()
        if "Test Case" in text or "error:" in text or "Executed" in text or "** TEST" in text:
            print(f"  [{prefix}] {text}")
    return proc.wait()


# ---------------------------------------------------------------------------
# Segment recording
# ---------------------------------------------------------------------------

def record_single_segment(segment, sim_id):
    """Record a single-simulator segment."""
    name = segment["name"]
    output = f"segments/{name}.mov"
    print(f"\n{'='*60}")
    print(f"Recording: {name}")
    print(f"{'='*60}")

    # Start recording immediately, trim the beginning in post-production
    rec = start_recording(sim_id, output)

    # Run the test
    proc = run_xcodebuild_test(sim_id, segment["test"])
    rc = stream_and_wait(proc, name)

    # Stop recording and wait for finalization
    stop_recording(rec)

    if rc != 0:
        print(f"  [WARN] Test exited with code {rc}")
    else:
        print(f"  [OK] Recorded: {output}")
    return rc


def record_dual_segment(segment, sim_a, sim_b):
    """Record a dual-simulator segment with sync server coordination."""
    name = segment["name"]
    output_a = f"segments/{name}_left.mov"
    output_b = f"segments/{name}_right.mov"
    print(f"\n{'='*60}")
    print(f"Recording (dual): {name}")
    print(f"{'='*60}")

    # Kill any existing sync server on the port
    subprocess.run(
        ["lsof", "-ti", f":{SYNC_PORT}"],
        capture_output=True
    )

    # Start sync server
    sync = SyncServer(SYNC_PORT)
    sync.start()

    try:
        # Start recording both simulators
        rec_a = start_recording(sim_a, output_a)
        rec_b = start_recording(sim_b, output_b)

        # Run both tests in parallel
        proc_a = run_xcodebuild_test(sim_a, segment["testA"], role="userA")
        proc_b = run_xcodebuild_test(sim_b, segment["testB"], role="userB")

        # Stream output from both
        thread_a = threading.Thread(
            target=stream_and_wait, args=(proc_a, "Alice"), daemon=True
        )
        thread_b = threading.Thread(
            target=stream_and_wait, args=(proc_b, "Bob"), daemon=True
        )
        thread_a.start()
        thread_b.start()

        # Wait for both tests to complete
        thread_a.join(timeout=180)
        thread_b.join(timeout=180)

        rc_a = proc_a.returncode or 0
        rc_b = proc_b.returncode or 0

        # Stop recordings
        stop_recording(rec_a)
        stop_recording(rec_b)

        if rc_a != 0 or rc_b != 0:
            print(f"  [WARN] Test exit codes: A={rc_a}, B={rc_b}")
        else:
            print(f"  [OK] Recorded: {output_a}, {output_b}")

        return max(rc_a, rc_b)

    finally:
        sync.stop()


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def build_for_testing(sim_id):
    """Build the test bundle once for all segments."""
    print("Building for testing...")
    cmd = [
        "xcodebuild", "build-for-testing",
        "-project", PROJECT,
        "-scheme", SCHEME,
        "-destination", f"id={sim_id}",
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    for line in iter(proc.stdout.readline, b""):
        text = line.decode("utf-8", errors="replace").rstrip()
        if "BUILD" in text or "error:" in text:
            print(f"  [build] {text}")
    rc = proc.wait()
    if rc != 0:
        print("BUILD FAILED")
        sys.exit(1)
    print("Build succeeded.\n")


def check_xctestrun_exists():
    """Verify that a .xctestrun file exists (required for test-without-building)."""
    derived = os.path.expanduser(
        "~/Library/Developer/Xcode/DerivedData"
    )
    matches = glob.glob(f"{derived}/FastCommentsExample-*/Build/Products/*.xctestrun")
    if not matches:
        print("ERROR: No .xctestrun file found. Run without --skip-build first.")
        sys.exit(1)
    print(f"Found xctestrun: {os.path.basename(matches[0])}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Record FastComments demo video segments")
    parser.add_argument("--sim-a", default=DEFAULT_SIM_A, help="Simulator A UUID")
    parser.add_argument("--sim-b", default=DEFAULT_SIM_B, help="Simulator B UUID")
    parser.add_argument("--segment", help="Record only segments matching this prefix")
    parser.add_argument("--skip-build", action="store_true", help="Skip initial build")
    args = parser.parse_args()

    os.makedirs("segments", exist_ok=True)

    # Build or verify
    if args.skip_build:
        check_xctestrun_exists()
    else:
        build_for_testing(args.sim_a)

    # Filter segments if requested
    segments = SEGMENTS
    if args.segment:
        segments = [s for s in SEGMENTS if s["name"].startswith(args.segment)]
        if not segments:
            print(f"No segments matching '{args.segment}'")
            print("Available:", ", ".join(s["name"] for s in SEGMENTS))
            sys.exit(1)

    # Record each segment
    results = {}
    for segment in segments:
        if segment["type"] == "single":
            rc = record_single_segment(segment, args.sim_a)
        elif segment["type"] == "dual":
            rc = record_dual_segment(segment, args.sim_a, args.sim_b)
        else:
            print(f"Unknown segment type: {segment['type']}")
            continue
        results[segment["name"]] = rc

    # Summary
    print(f"\n{'='*60}")
    print("RECORDING SUMMARY")
    print(f"{'='*60}")
    for name, rc in results.items():
        status = "OK" if rc == 0 else f"WARN (exit {rc})"
        print(f"  {name}: {status}")

    segment_files = [f for f in os.listdir("segments") if f.endswith(".mov")]
    print(f"\nRecorded {len(segment_files)} files in segments/")
    print("Next step: run ./assemble_demo.sh to produce the final video")


if __name__ == "__main__":
    main()
