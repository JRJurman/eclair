#!/usr/bin/env python3
"""
eclair - cross-platform test application

This is a simple windowed application to expose and validate the different
controls the API offers.

When ECLAIR_SELFTEST=1 is included, the window immediately closes (used for
debugging).
"""

import ctypes
import os
import platform
import sys
import tkinter as tk
from tkinter import ttk

LIB_NAMES = {
    "Darwin":  "libeclair.dylib",
    "Linux":   "libeclair.so",
    "Windows": "eclair.dll",
}

ROUTES = [
    ("off",                   0),
    ("screen reader only",    1),
    ("prefer screen reader",  2),
    ("synthesizer only",      3),
]

OUTPUTS = {0: "NONE", 1: "SCREEN_READER", 2: "SYNTHESIZER"}


def load_eclair():
    name = LIB_NAMES[platform.system()]
    here = os.path.dirname(os.path.abspath(__file__))
    for path in (os.path.join(here, "..", "dist", name),
                 os.path.join(here, name), name):
        try:
            lib = ctypes.CDLL(path)
            break
        except OSError:
            continue
    else:
        raise SystemExit(f"could not find {name} - build it first, see scripts/")

    lib.eclair_init.restype           = ctypes.c_int
    lib.eclair_shutdown.restype       = None
    lib.eclair_speak.argtypes         = [ctypes.c_char_p, ctypes.c_bool]
    lib.eclair_speak.restype          = ctypes.c_int
    lib.eclair_stop.restype           = ctypes.c_int
    lib.eclair_set_route.argtypes     = [ctypes.c_int]
    lib.eclair_set_rate.argtypes      = [ctypes.c_float]
    lib.eclair_set_volume.argtypes    = [ctypes.c_float]
    lib.eclair_current_output.restype = ctypes.c_int
    lib.eclair_backend_name.restype   = ctypes.c_char_p
    lib.eclair_error_string.argtypes  = [ctypes.c_int]
    lib.eclair_error_string.restype   = ctypes.c_char_p
    return lib


class App(ttk.Frame):
    def __init__(self, root, lib):
        super().__init__(root, padding=12)
        self.lib = lib
        self.grid(sticky="nsew")
        root.columnconfigure(0, weight=1)
        self.columnconfigure(1, weight=1)

        r = 0
        ttk.Label(self, text="Text").grid(row=r, column=0, sticky="w")
        self.text = tk.StringVar(value="The quick brown fox jumps over the lazy dog.")
        ttk.Entry(self, textvariable=self.text).grid(row=r, column=1, sticky="ew", pady=4)

        r += 1
        btns = ttk.Frame(self)
        btns.grid(row=r, column=1, sticky="w", pady=4)
        ttk.Button(btns, text="Speak", command=lambda: self.speak(False)).pack(side="left")
        ttk.Button(btns, text="Speak (interrupt)", command=lambda: self.speak(True)).pack(side="left", padx=4)
        ttk.Button(btns, text="Stop", command=self.stop).pack(side="left")

        r += 1
        ttk.Label(self, text="Route").grid(row=r, column=0, sticky="w")
        self.route = ttk.Combobox(self, state="readonly", values=[n for n, _ in ROUTES])
        self.route.current(2)
        self.route.bind("<<ComboboxSelected>>", self.on_route)
        self.route.grid(row=r, column=1, sticky="ew", pady=4)

        r += 1
        self.rate_lbl = ttk.Label(self, text="Rate 0.50")
        self.rate_lbl.grid(row=r, column=0, sticky="w")
        ttk.Scale(self, from_=0.0, to=1.0, value=0.5,
                  command=self.on_rate).grid(row=r, column=1, sticky="ew", pady=4)

        r += 1
        self.vol_lbl = ttk.Label(self, text="Volume 1.00")
        self.vol_lbl.grid(row=r, column=0, sticky="w")
        ttk.Scale(self, from_=0.0, to=1.0, value=1.0,
                  command=self.on_volume).grid(row=r, column=1, sticky="ew", pady=4)

        r += 1
        ttk.Separator(self).grid(row=r, column=0, columnspan=2, sticky="ew", pady=8)

        r += 1
        self.status = ttk.Label(self, text="", foreground="#666")
        self.status.grid(row=r, column=0, columnspan=2, sticky="w")

        r += 1
        self.result = ttk.Label(self, text="")
        self.result.grid(row=r, column=0, columnspan=2, sticky="w")

        self.poll()

    def err(self, code):
        return self.lib.eclair_error_string(code).decode()

    def speak(self, interrupt):
        code = self.lib.eclair_speak(self.text.get().encode("utf-8"), interrupt)
        self.result.config(text=f"speak -> {self.err(code)}")

    def stop(self):
        self.result.config(text=f"stop -> {self.err(self.lib.eclair_stop())}")

    def on_route(self, _evt):
        self.lib.eclair_set_route(ROUTES[self.route.current()][1])

    def on_rate(self, value):
        v = float(value)
        self.rate_lbl.config(text=f"Rate {v:.2f}")
        self.lib.eclair_set_rate(ctypes.c_float(v))

    def on_volume(self, value):
        v = float(value)
        self.vol_lbl.config(text=f"Volume {v:.2f}")
        self.lib.eclair_set_volume(ctypes.c_float(v))

    def poll(self):
        """Re-read routing every 500ms - eclair.h says a screen reader can start
        or stop at any time, so this is the contract made visible."""
        out = OUTPUTS.get(self.lib.eclair_current_output(), "?")
        name = self.lib.eclair_backend_name()
        self.status.config(text=f"output = {out}    backend = {name.decode() if name else '(none)'}")
        self.after(500, self.poll)


def check_tk(root):
    """Apple ships Tk 8.5.9 (2010), whose Aqua renderer is broken on macOS 11+:
    widgets are created and hit-test correctly but never paint. Fail loudly
    rather than presenting an empty window."""
    patch = root.tk.call("info", "patchlevel")
    if tuple(int(n) for n in patch.split(".")[:2]) < (8, 6):
        raise SystemExit(
            f"Tk {patch} is too old to render on this platform.\n"
            f"Use a Python linked against Tk 8.6 or newer, for example:\n"
            f"  /opt/homebrew/bin/python3.13 {sys.argv[0]}")


def main():
    lib = load_eclair()
    code = lib.eclair_init()
    root = tk.Tk()
    check_tk(root)
    root.title("eclair test harness")
    root.minsize(520, 0)
    app = App(root, lib)
    app.result.config(text=f"init -> {app.err(code)}")
    if os.environ.get("ECLAIR_SELFTEST"):
        root.after(400, root.destroy)
    try:
        root.mainloop()
    finally:
        lib.eclair_shutdown()


if __name__ == "__main__":
    main()
