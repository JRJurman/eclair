#!/usr/bin/env python3
"""
eclair - web test harness server

Serves examples/web/eclair-web.html and dist/ over http, because browsers refuse to
fetch a .wasm from file://. The counterpart to eclair-tk.py - same invocation,
same job, the other platform.

    python3 examples/web/eclair-web.py [port] [--lan]

--lan binds every interface and prints the address to reach this machine from a
phone, which is what the Android and iOS rows of the test matrix need.

Build dist/eclair.js first with scripts/build-web.sh. This never builds; that
stays the build script's job, as it is for the Tk harness.
"""

import functools
import http.server
import os
import socket
import sys
import webbrowser

DEFAULT_PORT = 8000
PAGE = "examples/web/eclair-web.html"

# Python reads the system mime database, which on plenty of machines has no
# entry for .wasm - and WebAssembly.instantiateStreaming() refuses anything that
# is not application/wasm. Emscripten falls back to a non-streaming instantiation
# and still runs, but it logs a warning that reads exactly like a real failure.
http.server.SimpleHTTPRequestHandler.extensions_map[".wasm"] = "application/wasm"


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # dist/eclair.js and dist/eclair.wasm get rebuilt constantly while a
        # backend is being written, and a cached copy is the most common reason
        # a change appears not to have taken.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def lan_address():
    """Best-effort address for this machine on the local network. Connecting a
    UDP socket sends nothing - it only asks the routing table which interface
    would be used to get out."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except OSError:
        return None


def main():
    args = sys.argv[1:]
    lan = "--lan" in args
    ports = [a for a in args if not a.startswith("-")]
    port = int(ports[0]) if ports else DEFAULT_PORT

    # the repository root - two levels up from examples/web/ - so that the page
    # and dist/ are both under the served tree no matter which directory this
    # was started from
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    if not os.path.exists(os.path.join(root, "dist", "eclair.js")):
        print("note: dist/eclair.js is missing - build it with scripts/build-web.sh")
        print("      the server stays up, so you can build and reload")

    handler = functools.partial(Handler, directory=root)
    host = "" if lan else "127.0.0.1"
    url = f"http://localhost:{port}/{PAGE}"

    try:
        httpd = http.server.ThreadingHTTPServer((host, port), handler)
    except OSError as e:
        raise SystemExit(f"could not listen on port {port}: {e}\n"
                         f"pass another one, for example: {sys.argv[0]} 8080")

    print(f"eclair test harness: {url}")

    if lan:
        address = lan_address()
        if address:
            print(f"from another device:  http://{address}:{port}/{PAGE}")
        else:
            print("could not work out this machine's address on the network")

    print("ctrl-c to stop")
    webbrowser.open(url)

    with httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print()


if __name__ == "__main__":
    main()
