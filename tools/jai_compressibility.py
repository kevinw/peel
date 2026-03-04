#!/usr/bin/env python3
"""Measure per-file compressibility for .jai source files.

Metric: zip_compressed_bytes / on_disk_bytes
"""

from __future__ import annotations

import argparse
import io
from dataclasses import dataclass
from pathlib import Path
import zipfile


@dataclass
class FileMetric:
    path: Path
    raw_bytes: int
    compressed_bytes: int

    @property
    def ratio(self) -> float:
        if self.raw_bytes == 0:
            return 0.0
        return self.compressed_bytes / self.raw_bytes


def zip_compressed_size(path: Path, level: int) -> int:
    # Write one file into an in-memory zip and read the entry's compressed size.
    # This gives a straightforward "zipped bytes" measure per file.
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, mode="w", compression=zipfile.ZIP_DEFLATED, compresslevel=level) as zf:
        zf.writestr(path.name, path.read_bytes())
        info = zf.getinfo(path.name)
        return info.compress_size


def normalize_pattern(pattern: str) -> str:
    return pattern.strip().strip("/")


def should_exclude(path: Path, root: Path, exclude_patterns: list[str]) -> bool:
    rel = path.relative_to(root)
    rel_str = rel.as_posix()
    rel_parts = rel.parts
    for pattern in exclude_patterns:
        p = normalize_pattern(pattern)
        if not p:
            continue

        # Single-segment patterns (e.g. ".build") match any path component.
        if "/" not in p:
            if p in rel_parts:
                return True
            continue

        # Multi-segment patterns match relative path prefixes.
        if rel_str == p or rel_str.startswith(p + "/"):
            return True
    return False


def collect_metrics(root: Path, level: int, exclude_patterns: list[str]) -> list[FileMetric]:
    metrics: list[FileMetric] = []
    for path in root.rglob("*.jai"):
        if not path.is_file():
            continue
        if should_exclude(path, root, exclude_patterns):
            continue

        raw_bytes = path.stat().st_size
        compressed_bytes = zip_compressed_size(path, level)
        metrics.append(FileMetric(path=path, raw_bytes=raw_bytes, compressed_bytes=compressed_bytes))
    return metrics


def print_section(title: str, rows: list[FileMetric], root: Path) -> None:
    print(title)
    print("ratio    compressed  raw        file")
    for row in rows:
        rel = row.path.relative_to(root)
        print(f"{row.ratio:0.4f}   {row.compressed_bytes:10d}  {row.raw_bytes:10d}  {rel}")
    print()


def main() -> int:
    parser = argparse.ArgumentParser(description="Compute zip compressibility ratios for .jai files")
    parser.add_argument("root", nargs="?", default=".", help="root directory to scan (default: current dir)")
    parser.add_argument("-n", "--count", type=int, default=15, help="rows to show for each section")
    parser.add_argument(
        "--level",
        type=int,
        default=9,
        choices=range(0, 10),
        metavar="0-9",
        help="zip compression level (default: 9)",
    )
    parser.add_argument(
        "--exclude",
        action="append",
        default=[".build"],
        help="relative path prefix to exclude (repeatable, default: .build)",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    metrics = collect_metrics(root, args.level, args.exclude)

    if not metrics:
        print("No .jai files found.")
        return 0

    by_ratio = sorted(metrics, key=lambda m: m.ratio)

    n = max(1, args.count)
    lightest = by_ratio[:n]
    heaviest = by_ratio[-n:][::-1]

    total_raw = sum(m.raw_bytes for m in metrics)
    total_compressed = sum(m.compressed_bytes for m in metrics)
    weighted_ratio = (total_compressed / total_raw) if total_raw else 0.0

    print(f"Scanned {len(metrics)} files under {root}")
    if args.exclude:
        excludes = ", ".join(args.exclude)
        print(f"Excluded prefixes: {excludes}")
    print(f"Overall weighted ratio: {weighted_ratio:0.4f} ({total_compressed} / {total_raw})")
    print()

    print_section(f"Lightest ratios (most compressible) - top {n}", lightest, root)
    print_section(f"Heaviest ratios (least compressible) - top {n}", heaviest, root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
