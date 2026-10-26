# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 the maschine-mk1-macos contributors
"""Minimal stand-in for the parts of GLib that mk1_midi uses.

On macOS there is no session D-Bus and PyGObject is awkward to install, so
mk1_midi runs on this small main loop instead. Semantics follow GLib where it
matters: a source keeps running while its callback returns True, idle and
timeout callbacks run on the loop's thread, and they may be added from any
thread.
"""
import collections
import heapq
import itertools
import signal
import sys
import threading
import time
import traceback

SOURCE_REMOVE = False
SOURCE_CONTINUE = True
PRIORITY_DEFAULT = 0
_MAX_WAIT = 0.25            # seconds; also bounds signal latency


class _Loop:
    def __init__(self):
        self._cond = threading.Condition(threading.Lock())
        self._heap = []             # (due, seq, source id)
        self._sources = {}          # id -> (interval, fn, args)
        self._ids = itertools.count(1)
        self._seq = itertools.count()
        self._signals = collections.deque()
        self._running = False

    def add(self, interval, fn, args):
        with self._cond:
            sid = next(self._ids)
            self._sources[sid] = (interval, fn, args)
            heapq.heappush(self._heap, (time.monotonic() + interval, next(self._seq), sid))
            self._cond.notify()
            return sid

    def remove(self, sid):
        with self._cond:
            return self._sources.pop(sid, None) is not None

    def signal_fired(self, fn):
        # Runs inside a Python signal handler: no locks here, just queue it.
        self._signals.append(fn)

    def _call(self, fn, args):
        try:
            return fn(*args)
        except Exception:
            traceback.print_exc(file=sys.stderr)
            return SOURCE_REMOVE

    def run(self):
        self._running = True
        while self._running:
            while self._signals:
                self._call(self._signals.popleft(), ())
            job = None
            with self._cond:
                while self._heap and self._heap[0][2] not in self._sources:
                    heapq.heappop(self._heap)           # removed sources
                now = time.monotonic()
                if self._heap and self._heap[0][0] <= now:
                    due, _, sid = heapq.heappop(self._heap)
                    interval, fn, args = self._sources[sid]
                    job = (due, sid, interval, fn, args)
                else:
                    wait = _MAX_WAIT
                    if self._heap:
                        wait = min(wait, self._heap[0][0] - now)
                    self._cond.wait(max(wait, 0))
            if job is None:
                continue
            due, sid, interval, fn, args = job
            keep = self._call(fn, args)
            with self._cond:
                if sid in self._sources:
                    if keep:
                        nxt = max(due + interval, time.monotonic())
                        heapq.heappush(self._heap, (nxt, next(self._seq), sid))
                    else:
                        del self._sources[sid]

    def quit(self):
        with self._cond:
            self._running = False
            self._cond.notify()


_loop = _Loop()


class GLib:
    SOURCE_REMOVE = SOURCE_REMOVE
    SOURCE_CONTINUE = SOURCE_CONTINUE
    PRIORITY_DEFAULT = PRIORITY_DEFAULT

    class MainLoop:
        def run(self):
            _loop.run()

        def quit(self):
            _loop.quit()

    @staticmethod
    def timeout_add(ms, fn, *args):
        return _loop.add(max(ms, 0) / 1000, fn, args)

    @staticmethod
    def timeout_add_seconds(seconds, fn, *args):
        return _loop.add(max(seconds, 0), fn, args)

    @staticmethod
    def idle_add(fn, *args):
        return _loop.add(0, fn, args)

    @staticmethod
    def source_remove(sid):
        return _loop.remove(sid)


def unix_signal_add(_priority, sig, fn):
    signal.signal(sig, lambda *_: _loop.signal_fired(fn))
