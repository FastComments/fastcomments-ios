#!/usr/bin/env python3
"""
Dual-simulator XCUITest orchestrator for FastComments iOS.

Boots two simulators, starts a local sync server, and runs UserA/UserB
test files in parallel on separate simulators. Tests coordinate via
the sync server at localhost:9999.

Usage:
    python3 run_dual_sim_tests.py [--sim-a ID] [--sim-b ID]
"""

import argparse
import http.server
import json
import subprocess
import sys
import threading
import time
from collections import defaultdict

# Default simulator UDIDs (from `xcrun simctl list devices booted`)
DEFAULT_SIM_A = "E4683E5D-8489-468D-8CA4-6985AD94B572"
DEFAULT_SIM_B = "DB94C97C-1CDF-4016-84E7-BF84A1ACF84F"

SYNC_PORT = 9999
PROJECT = "FastCommentsExample.xcodeproj"
SCHEME = "FastCommentsExample"


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
        self.server = http.server.HTTPServer(("", self.port), handler)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        print(f"[sync] Server started on port {self.port}")

    def stop(self):
        if self.server:
            self.server.shutdown()

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


def run_xcodebuild(sim_id, role, test_filter):
    """Run xcodebuild test on a specific simulator."""
    # Write config file keyed by test filter (UserA or UserB tests read the right one)
    config = {
        "FC_SYNC_URL": f"http://localhost:{SYNC_PORT}",
        "FC_ROLE": role,
    }
    # Use a single shared config file — both processes can read it since each
    # test class knows its own role from the file name (UserA/UserB)
    with open(f"/tmp/fc-uitest-{role}.json", "w") as f:
        json.dump(config, f)

    cmd = [
        "xcodebuild", "test",
        "-project", PROJECT,
        "-scheme", SCHEME,
        "-destination", f"id={sim_id}",
        "-only-testing", test_filter,
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


def main():
    parser = argparse.ArgumentParser(description="Run dual-simulator XCUITests")
    parser.add_argument("--sim-a", default=DEFAULT_SIM_A, help="Simulator A UUID")
    parser.add_argument("--sim-b", default=DEFAULT_SIM_B, help="Simulator B UUID")
    args = parser.parse_args()

    # Start sync server
    sync = SyncServer(SYNC_PORT)
    sync.start()

    try:
        # Run UserA and UserB tests in parallel
        proc_a = run_xcodebuild(
            args.sim_a, "userA",
            "FastCommentsUITests/LiveEventUserA_UITests",
        )
        proc_b = run_xcodebuild(
            args.sim_b, "userB",
            "FastCommentsUITests/LiveEventUserB_UITests",
        )

        # Stream output from both
        thread_a = threading.Thread(target=stream_output, args=(proc_a, "UserA"), daemon=True)
        thread_b = threading.Thread(target=stream_output, args=(proc_b, "UserB"), daemon=True)
        thread_a.start()
        thread_b.start()

        # Wait for both to finish
        rc_a = proc_a.wait()
        rc_b = proc_b.wait()

        thread_a.join(timeout=5)
        thread_b.join(timeout=5)

        print(f"\n{'='*60}")
        print(f"User A exit code: {rc_a}")
        print(f"User B exit code: {rc_b}")
        if rc_a == 0 and rc_b == 0:
            print("ALL DUAL-SIM TESTS PASSED")
        else:
            print("SOME TESTS FAILED")
        print(f"{'='*60}")

        sys.exit(0 if rc_a == 0 and rc_b == 0 else 1)

    finally:
        sync.stop()


if __name__ == "__main__":
    main()
