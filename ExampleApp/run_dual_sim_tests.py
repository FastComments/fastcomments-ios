#!/usr/bin/env python3
"""
Dual-simulator XCUITest orchestrator for FastComments iOS.

Boots two simulators, starts a local sync server, and runs UserA/UserB
test files in parallel on separate simulators. Tests coordinate via
the sync server at localhost:9999.

Usage:
    python3 run_dual_sim_tests.py [--sim-a ID] [--sim-b ID] [--suite SUITE] [--record DIR]

--record DIR saves a screen recording of each simulator per suite, plus the screenshots the tests attach, into DIR.
The tests hold each state on screen for a moment while recording, so the videos can be reviewed.
"""

import argparse
import http.server
import json
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time
from collections import defaultdict

# Default simulator UDIDs (from `xcrun simctl list devices booted`)
DEFAULT_SIM_A = "E4683E5D-8489-468D-8CA4-6985AD94B572"
DEFAULT_SIM_B = "DB94C97C-1CDF-4016-84E7-BF84A1ACF84F"

SYNC_PORT = 9999
PROJECT = "FastCommentsExample.xcodeproj"
SCHEME = "FastCommentsExample"

DUAL_SUITES = {
    "live-events": ("LiveEventUserA_UITests", "LiveEventUserB_UITests"),
    "feed":        ("FeedUserA_UITests",       "FeedUserB_UITests"),
    "polls":       ("PollUserA_UITests",       "PollUserB_UITests"),
}


class SyncServer:
    """Tiny HTTP server for test coordination between two simulator processes."""

    def __init__(self, port):
        self.port = port
        self.ready = defaultdict(dict)      # round -> {role: True}
        self.data = {}                       # round -> json data
        self.waiters = defaultdict(list)     # (round, role) -> [event]
        self.lock = threading.Lock()
        self.server = None

    def start(self):
        handler = self._make_handler()
        self.server = http.server.ThreadingHTTPServer(("", self.port), handler)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        print(f"[sync] Server started on port {self.port}")

    def stop(self):
        if self.server:
            self.server.shutdown()

    def reset(self):
        """Clear all state between test suites."""
        with self.lock:
            self.ready = defaultdict(dict)
            self.data = {}
            self.waiters = defaultdict(list)

    def _make_handler(self):
        sync = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                print(f"[sync] {args[0]}")

            def do_POST(self):
                path = self.path.split("?")[0]
                params = dict(p.split("=") for p in self.path.split("?")[1].split("&")) if "?" in self.path else {}

                if path == "/ready":
                    role = params.get("role", "")
                    round_id = params.get("round", "default")
                    with sync.lock:
                        sync.ready[round_id][role] = True
                        # Wake up anyone waiting for this role
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
                params = dict(p.split("=") for p in self.path.split("?")[1].split("&")) if "?" in self.path else {}

                if path == "/wait":
                    wait_for = params.get("waitFor", "")
                    round_id = params.get("round", "default")
                    timeout = float(params.get("timeout", "60"))

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


def build_for_testing(sim_id):
    """Build once up front. Two concurrent builds fail on Xcode's locked build database."""
    print("[build] Building for testing...")
    result = subprocess.run(
        [
            "xcodebuild", "build-for-testing",
            "-project", PROJECT,
            "-scheme", SCHEME,
            "-destination", f"id={sim_id}",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode != 0:
        output = result.stdout.decode("utf-8", errors="replace")
        print("\n".join(line for line in output.splitlines() if "error:" in line))
        print("[build] FAILED")
        return False
    return True


def run_xcodebuild(sim_id, role, test_filter, result_bundle, recording_hold=None):
    """Run xcodebuild test on a specific simulator."""
    # Write config file keyed by test filter (UserA or UserB tests read the right one)
    config = {
        "FC_SYNC_URL": f"http://localhost:{SYNC_PORT}",
        "FC_ROLE": role,
    }
    if recording_hold:
        config["FC_RECORDING_HOLD"] = str(recording_hold)
    # Use a single shared config file — both processes can read it since each
    # test class knows its own role from the file name (UserA/UserB)
    with open(f"/tmp/fc-uitest-{role}.json", "w") as f:
        json.dump(config, f)

    cmd = [
        "xcodebuild", "test-without-building",
        "-project", PROJECT,
        "-scheme", SCHEME,
        "-destination", f"id={sim_id}",
        "-only-testing", test_filter,
        # Both roles start in the same second, and Xcode's default bundle name only has a timestamp in it.
        "-resultBundlePath", result_bundle,
    ]

    print(f"[{role}] Starting on simulator {sim_id[:8]}...")
    print(f"[{role}] Filter: {test_filter}")

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return proc


def stream_output(proc, prefix):
    """Stream process output with a prefix."""
    for line in iter(proc.stdout.readline, b""):
        text = line.decode("utf-8", errors="replace").rstrip()
        if "Test Case" in text or "error:" in text or "Executed" in text:
            print(f"[{prefix}] {text}")


def start_recording(sim_id, path):
    return subprocess.Popen(
        ["xcrun", "simctl", "io", sim_id, "recordVideo", "--codec", "h264", "--force", path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def stop_recording(proc):
    # simctl only finishes writing the file on SIGINT.
    proc.send_signal(signal.SIGINT)
    proc.wait(timeout=30)


def export_screenshots(result_bundle, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    subprocess.run(
        ["xcrun", "xcresulttool", "export", "attachments", "--path", result_bundle, "--output-path", output_dir],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def run_dual_suite(sim_a, sim_b, suite_name, class_a, class_b, sync, record_dir=None):
    """Run a single dual-simulator test suite. Returns True if both pass."""
    print(f"\n{'='*60}")
    print(f"Running suite: {suite_name}")
    print(f"{'='*60}")

    sync.reset()

    # Both roles start in the same second, and Xcode's default bundle name only has a timestamp in it.
    if record_dir:
        suite_dir = os.path.join(record_dir, suite_name)
        os.makedirs(suite_dir, exist_ok=True)
        bundle_a = os.path.join(suite_dir, "userA.xcresult")
        bundle_b = os.path.join(suite_dir, "userB.xcresult")
        for bundle in (bundle_a, bundle_b):
            subprocess.run(["rm", "-rf", bundle])
        recorders = [
            start_recording(sim_a, os.path.join(suite_dir, "userA.mp4")),
            start_recording(sim_b, os.path.join(suite_dir, "userB.mp4")),
        ]
    else:
        bundle_a = tempfile.mkdtemp(prefix="fc-uitest-userA-") + "/result.xcresult"
        bundle_b = tempfile.mkdtemp(prefix="fc-uitest-userB-") + "/result.xcresult"
        recorders = []

    hold = 1.5 if record_dir else None
    proc_a = run_xcodebuild(sim_a, "userA", f"FastCommentsUITests/{class_a}", bundle_a, hold)
    proc_b = run_xcodebuild(sim_b, "userB", f"FastCommentsUITests/{class_b}", bundle_b, hold)

    thread_a = threading.Thread(target=stream_output, args=(proc_a, f"{suite_name}/UserA"), daemon=True)
    thread_b = threading.Thread(target=stream_output, args=(proc_b, f"{suite_name}/UserB"), daemon=True)
    thread_a.start()
    thread_b.start()

    rc_a = proc_a.wait()
    rc_b = proc_b.wait()

    thread_a.join(timeout=5)
    thread_b.join(timeout=5)

    for recorder in recorders:
        stop_recording(recorder)
    if record_dir:
        export_screenshots(bundle_a, os.path.join(suite_dir, "screenshots-userA"))
        export_screenshots(bundle_b, os.path.join(suite_dir, "screenshots-userB"))
        print(f"[{suite_name}] Recordings and screenshots saved to {suite_dir}")

    passed = rc_a == 0 and rc_b == 0
    status = "PASSED" if passed else "FAILED"
    print(f"[{suite_name}] UserA exit: {rc_a}, UserB exit: {rc_b} — {status}")
    return passed


def main():
    parser = argparse.ArgumentParser(description="Run dual-simulator XCUITests")
    parser.add_argument("--sim-a", default=DEFAULT_SIM_A, help="Simulator A UUID")
    parser.add_argument("--sim-b", default=DEFAULT_SIM_B, help="Simulator B UUID")
    parser.add_argument(
        "--suite",
        default="all",
        choices=list(DUAL_SUITES.keys()) + ["all"],
        help="Which test suite to run (default: all)",
    )
    parser.add_argument("--record", metavar="DIR", help="Save screen recordings and screenshots for review into DIR")
    args = parser.parse_args()
    record_dir = os.path.abspath(args.record) if args.record else None

    if not build_for_testing(args.sim_a):
        sys.exit(1)

    # Start sync server
    sync = SyncServer(SYNC_PORT)
    sync.start()

    try:
        suites_to_run = DUAL_SUITES if args.suite == "all" else {args.suite: DUAL_SUITES[args.suite]}
        results = {}

        for suite_name, (class_a, class_b) in suites_to_run.items():
            passed = run_dual_suite(args.sim_a, args.sim_b, suite_name, class_a, class_b, sync, record_dir)
            results[suite_name] = passed

        print(f"\n{'='*60}")
        print("RESULTS:")
        all_passed = True
        for suite_name, passed in results.items():
            status = "PASSED" if passed else "FAILED"
            print(f"  {suite_name}: {status}")
            if not passed:
                all_passed = False

        if all_passed:
            print("ALL DUAL-SIM TESTS PASSED")
        else:
            print("SOME TESTS FAILED")
        print(f"{'='*60}")

        sys.exit(0 if all_passed else 1)

    finally:
        sync.stop()


if __name__ == "__main__":
    main()
