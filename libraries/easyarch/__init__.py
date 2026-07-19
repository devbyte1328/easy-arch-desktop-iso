"""Easy Arch Linux ISO build system.

The whole build lives here as Python. `easyarch.build` is the entrypoint
(invoked by the thin ``compile.sh`` shim after it sets up the PTY + sudo).

Design: every artifact baked into the ISO is authored as a Python string in
``easyarch.config.*`` and written into the archiso profile tree by
``easyarch.steps``. Only genuinely-large verbatim upstream files and the
user-facing package list live as data files under ``libraries/data/``.
"""

__all__ = ["build"]
