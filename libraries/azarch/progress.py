"""Weighted, pinned-to-bottom progress bar.

Ported from the bash bar in the old compile.sh but simplified: because the whole
build now runs in ONE python process, we don't need the CR->LF log-tailing reader
subshell the bash version used to scrape pacman/mkarchiso progress out of a shared
PTY. Instead the long steps (package cache, mkarchiso) call ``bar.sub(permille)``
directly from the same process that parses their live output line-by-line
(see steps.py), which is both simpler and race-free.

Layout: ``[####----]  50%  Label`` pinned to the last terminal row via a DECSTBM
scroll region, so build output scrolls in the rows above it. On a non-TTY (piped
to a file / docker logs without -t) it degrades to plain milestone lines, so no
escape codes leak into logs.
"""

from __future__ import annotations

import os
import shutil
import sys


class ProgressBar:
    def __init__(self, weights: list[int], tty: bool | None = None):
        # weights[i] is the weight of step i (1-indexed; index 0 unused).
        self.weights = weights
        self.total_steps = len(weights) - 1
        self.total_weight = sum(weights)
        self.accum = [0] * len(weights)
        acc = 0
        for i in range(1, len(weights)):
            acc += weights[i]
            self.accum[i] = acc
        self.current = 0
        self.label = ""
        self.done_weight = 0
        self.cur_weight = 0
        self.subfrac = 0  # 0..1000 within the current step
        if tty is None:
            tty = sys.stdout.isatty()
        self.tty = tty
        self._armed = False
        self._armed_rows = None  # terminal height the scroll region was last armed to
        self._base_label = ""    # current step's label, prefixed onto phase() sub-labels

    # -- geometry ------------------------------------------------------------
    def _size(self) -> tuple[int, int]:
        try:
            cols, rows = shutil.get_terminal_size((80, 24))
        except Exception:
            cols, rows = 80, 24
        return cols, rows

    def _layout(self, cols: int) -> str:
        eff = self.done_weight * 1000 + self.cur_weight * min(max(self.subfrac, 0), 1000)
        pct = min(eff // 10 // self.total_weight, 100) if self.total_weight else 0
        pctstr = f" {pct:3d}% "
        fixed = len(pctstr)
        avail = cols - fixed
        barw = max(8, avail * 55 // 100)
        if barw > avail:
            barw = avail
        barw = max(barw, 0)
        filled = (eff * barw // (1000 * self.total_weight)) if self.total_weight else 0
        filled = min(max(filled, 0), barw)
        bar = "█" * filled + "░" * (barw - filled)
        budget = cols - fixed - barw - 1
        label = self.label
        if budget <= 0:
            label = ""
        elif len(label) > budget:
            label = (label[: budget - 1] + "…") if budget >= 2 else label[:budget]
        sep = " " if label else ""
        width = barw + len(pctstr) + (1 + len(label) if label else 0)
        pad = max((cols - width) // 2, 0)
        return " " * pad + f"\033[36m{bar}\033[0m\033[1m{pctstr}\033[0m{sep}{label}"

    # -- pinning -------------------------------------------------------------
    def _arm(self) -> None:
        if not self.tty:
            return
        _, rows = self._size()
        # Set the DECSTBM scroll region to rows 1..rows-1, reserving the last row for
        # the pinned bar. Setting the region homes the cursor (a DECSTBM side effect),
        # which would make the next scrolling write land at the TOP; immediately place
        # the cursor at the bottom of the region so build output appends above the bar.
        sys.stdout.write(f"\033[1;{rows - 1}r\033[{rows - 1};1H")
        sys.stdout.flush()
        self._armed = True
        self._armed_rows = rows

    def draw(self) -> None:
        if not self.tty:
            return
        cols, rows = self._size()
        # If the terminal was resized since the region was armed, the old scroll region
        # and bar row are stale -- the bar would paint on the wrong row and unstick. The
        # giant steps drive many draw()s over a long span, so a resize mid-step is likely;
        # re-arm to the new height before painting. (\033[u below restores to a saved
        # position that re-arming would clobber, so re-arm BEFORE saving the cursor.)
        if getattr(self, "_armed_rows", None) != rows:
            self._arm()
        line = self._layout(cols)
        # save cursor, jump to last row, clear, paint, restore cursor
        sys.stdout.write(f"\033[s\033[{rows};1H\033[K{line}\033[u")
        sys.stdout.flush()

    def init(self) -> None:
        if self.tty:
            self._arm()
            self.draw()

    # -- step / sub ----------------------------------------------------------
    def step(self, label: str) -> None:
        self.current += 1
        self.label = label
        self.done_weight = self.accum[self.current - 1]
        self.cur_weight = self.weights[self.current]
        self.subfrac = 0
        self._base_label = label  # phase() prefixes sub-phase labels with this
        self._arm()
        # milestone line (scrolls; captured in logs)
        sys.stdout.write(f"\n[ {self.current:2d}/{self.total_steps} ] {label}\n")
        sys.stdout.flush()
        self.draw()

    def sub(self, permille: int) -> None:
        """Set intra-step progress (0..1000) and repaint. Monotonic within a step."""
        permille = min(max(permille, 0), 1000)
        if permille > self.subfrac:
            self.subfrac = permille
            self.draw()

    def phase(self, sublabel: str) -> None:
        """Update the pinned bar's label to a sub-phase of the current step WITHOUT
        advancing the step counter, and drop a scrolling milestone line. Lets the two
        giant steps (package cache, mkarchiso) narrate their internal phases so the
        bar reports fine-grained progress instead of one static label for minutes."""
        text = f"{self._base_label} › {sublabel}" if getattr(self, "_base_label", "") else sublabel
        self.label = text
        sys.stdout.write(f"    -> {sublabel}\n")
        sys.stdout.flush()
        self.draw()

    def sub_done(self) -> None:
        """Snap the current step to 100% of its slice."""
        self.subfrac = 1000
        self.draw()

    # -- teardown ------------------------------------------------------------
    def finalize(self) -> None:
        """Print a permanent full bar as a scrolled line (the 'done' state)."""
        self.subfrac = 1000
        if self.tty:
            sys.stdout.write("\033[r")  # unpin
            cols, _ = self._size()
            sys.stdout.write("\r\033[K" + self._layout(cols) + "\n")
        else:
            eff = self.done_weight * 1000 + self.cur_weight * 1000
            pct = min(eff // 10 // self.total_weight, 100)
            barw = 40
            filled = min(eff * barw // (1000 * self.total_weight), barw)
            bar = "#" * filled + "." * (barw - filled)
            sys.stdout.write(f"[{bar}] {pct:3d}%  {self.label}\n")
        sys.stdout.flush()

    def cleanup(self) -> None:
        """Restore the terminal on any exit (unpin scroll region, clear bar line)."""
        if self.tty:
            try:
                sys.stdout.write("\r\033[K\033[r\033[0m")
                sys.stdout.flush()
            except Exception:
                pass
