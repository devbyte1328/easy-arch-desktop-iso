"""`compile.sh --estimate-full-compile`: predict how long a FULL from-source
compile would take on THIS machine, without building anything.

--full-compile compiles Az'arch's own packages entirely from source; the runtime
is dominated by the LibreWolf/Firefox build (a huge C++/Rust codebase). That
compile is almost perfectly parallel, so wall-clock scales inversely with usable
core count, with RAM as a hard floor (Firefox linking -- even with LTO off in our
recipe -- wants a lot of memory; a RAM-starved machine swaps and slows sharply).

This is a HEURISTIC, not a benchmark: it reads core count, CPU model/clock, and
total RAM and prints a rough range. It never touches the network, never needs
sudo, and never starts a build. The numbers are anchored on observed LibreWolf/
Firefox build times and deliberately reported as a range with a clear caveat.
"""

from __future__ import annotations

import os
from pathlib import Path

# Anchor: a from-source LibreWolf/Firefox build (plus our calamares build) takes
# roughly 2 core-hours-per-effective-core on a modern strong x86_64 core, i.e. a
# fast 8-core machine lands around ~2h. We model wall-clock as BASE_CORE_HOURS of
# serial work spread across effective cores, then widen to a range for the many
# machine-specific factors (clock, memory bandwidth, disk, thermal throttling).
BASE_CORE_HOURS = 16.0        # total single-core-equivalent hours of compile work
MIN_RAM_GB_COMFORTABLE = 16.0  # below this, Firefox link/codegen pressures memory


def _cores() -> int:
    # Prefer the count actually usable by this process (respects cgroup/affinity
    # limits, e.g. inside Docker), fall back to the machine total.
    try:
        return len(os.sched_getaffinity(0))  # type: ignore[attr-defined]
    except (AttributeError, OSError):
        return os.cpu_count() or 1


def _cpu_model_and_mhz() -> tuple[str, float]:
    model, mhz = "unknown CPU", 0.0
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name") and model == "unknown CPU":
                model = line.split(":", 1)[1].strip()
            elif line.startswith("cpu MHz") and mhz == 0.0:
                try:
                    mhz = float(line.split(":", 1)[1].strip())
                except ValueError:
                    pass
    except OSError:
        pass
    return model, mhz


def _total_ram_gb() -> float:
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemTotal:"):
                kb = float(line.split()[1])
                return kb / (1024.0 * 1024.0)
    except (OSError, ValueError, IndexError):
        pass
    return 0.0


def _fmt_hours(h: float) -> str:
    if h < 1.0:
        return f"{round(h * 60)} min"
    hh = int(h)
    mm = round((h - hh) * 60)
    if mm == 0:
        return f"{hh}h"
    return f"{hh}h {mm}m"


def estimate() -> dict:
    cores = _cores()
    model, mhz = _cpu_model_and_mhz()
    ram = _total_ram_gb()

    # Effective parallelism: compilation scales well but not perfectly (I/O, link
    # serialization, Amdahl). Model diminishing returns past ~8 cores.
    eff_cores = cores if cores <= 8 else 8 + (cores - 8) * 0.6
    wall_hours = BASE_CORE_HOURS / max(eff_cores, 1.0)

    # RAM penalty: below the comfortable floor, expect swapping/back-pressure.
    if ram and ram < MIN_RAM_GB_COMFORTABLE:
        wall_hours *= 1.0 + (MIN_RAM_GB_COMFORTABLE - ram) / MIN_RAM_GB_COMFORTABLE

    low = wall_hours * 0.7
    high = wall_hours * 1.5
    return {
        "cores": cores, "model": model, "mhz": mhz, "ram_gb": ram,
        "low_hours": low, "high_hours": high,
        "ram_warning": bool(ram and ram < MIN_RAM_GB_COMFORTABLE),
    }


def run() -> int:
    """Print the estimate and return an exit code. No build, no network, no sudo."""
    e = estimate()
    clock = f" @ {e['mhz'] / 1000:.1f} GHz" if e["mhz"] else ""
    ram = f"{e['ram_gb']:.1f} GB" if e["ram_gb"] else "unknown"
    print("[*] --estimate-full-compile: estimating a FULL from-source build "
          "(nothing is compiled).")
    print(f"    CPU : {e['model']}{clock}  ({e['cores']} usable cores)")
    print(f"    RAM : {ram}")
    print(f"    Est.: roughly {_fmt_hours(e['low_hours'])} to "
          f"{_fmt_hours(e['high_hours'])} for `compile.sh --full-compile`.")
    if e["ram_warning"]:
        print(f"    [!] Under {MIN_RAM_GB_COMFORTABLE:.0f} GB RAM: the Firefox "
              "compile may swap and run notably slower than the range above.")
    print("    (Rough heuristic from CPU cores + RAM. The default `compile.sh` "
          "grabs verified binaries and finishes in minutes, not hours.)")
    return 0
