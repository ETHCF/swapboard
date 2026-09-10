#!/usr/bin/env python3
"""Compare two forge gas snapshot files and print a markdown table.

Usage:
  compare_gas_snapshots.py <a> <b> [snapshots_dir]

<a>/<b> may be:
  - a path to a .gas-snapshot file
  - a date prefix (YYYY-MM-DD) resolved under snapshots_dir as YYYY-MM-DD.gas-snapshot
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

LINE_RE = re.compile(
    r"^(?P<name>.+?)\s*\(gas:\s*(?P<gas>\d+)\)\s*$"
)


def resolve(arg: str, snapshots_dir: Path) -> Path:
    path = Path(arg)
    if path.is_file():
        return path

    dated = snapshots_dir / f"{arg}.gas-snapshot"
    if dated.is_file():
        return dated

    # Allow bare YYYY-MM-DD without repeating suffix when passed with .gas-snapshot
    if arg.endswith(".gas-snapshot"):
        dated = snapshots_dir / Path(arg).name
        if dated.is_file():
            return dated

    raise FileNotFoundError(
        f"Snapshot not found: {arg!r} (tried {path} and {dated})"
    )


def parse(path: Path) -> dict[str, int]:
    rows: dict[str, int] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line:
            continue
        match = LINE_RE.match(line)
        if not match:
            raise ValueError(f"Unrecognized snapshot line in {path}: {raw!r}")
        rows[match.group("name")] = int(match.group("gas"))
    return rows


def fmt_int(n: int) -> str:
    return f"{n:,}"


def fmt_delta(n: int) -> str:
    if n > 0:
        return f"+{n:,}"
    return f"{n:,}"


def fmt_pct(old: int | None, new: int | None, delta: int | None) -> str:
    if old is None or new is None or delta is None or old == 0:
        return "—"
    return f"{(delta / old) * 100:+.2f}%"


def main() -> int:
    if len(sys.argv) < 3:
        print(
            "Usage: compare_gas_snapshots.py <a> <b> [snapshots_dir]",
            file=sys.stderr,
        )
        return 2

    snapshots_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else Path("gas-snapshots")
    path_a = resolve(sys.argv[1], snapshots_dir)
    path_b = resolve(sys.argv[2], snapshots_dir)
    snap_a = parse(path_a)
    snap_b = parse(path_b)

    names = sorted(set(snap_a) | set(snap_b))
    label_a = path_a.name
    label_b = path_b.name

    print(f"Comparing `{label_a}` → `{label_b}`")
    print()
    print(f"| Test | {label_a} | {label_b} | Δ gas | Δ % |")
    print("| --- | ---: | ---: | ---: | ---: |")

    total_a = 0
    total_b = 0
    for name in names:
        a = snap_a.get(name)
        b = snap_b.get(name)
        if a is not None:
            total_a += a
        if b is not None:
            total_b += b

        if a is None:
            print(f"| `{name}` | — | {fmt_int(b)} | added | — |")
            continue
        if b is None:
            print(f"| `{name}` | {fmt_int(a)} | — | removed | — |")
            continue

        delta = b - a
        print(
            f"| `{name}` | {fmt_int(a)} | {fmt_int(b)} | "
            f"{fmt_delta(delta)} | {fmt_pct(a, b, delta)} |"
        )

    total_delta = total_b - total_a
    print(
        f"| **Total (shared+unique)** | {fmt_int(total_a)} | {fmt_int(total_b)} | "
        f"{fmt_delta(total_delta)} | {fmt_pct(total_a, total_b, total_delta)} |"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, ValueError) as err:
        print(err, file=sys.stderr)
        raise SystemExit(1) from err
