#!/usr/bin/env python3
"""Flatten a repository-root-relative file list for Icarus Verilog."""

from __future__ import annotations

import argparse
from pathlib import Path


def expand(root: Path, filelist: str, seen: set[Path]) -> list[str]:
    path = (root / filelist).resolve()
    if path in seen:
        return []
    if not path.is_file():
        raise FileNotFoundError(f"filelist does not exist: {path}")
    seen.add(path)

    arguments: list[str] = []
    for line_number, raw_line in enumerate(path.read_text().splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        if line.startswith("+incdir+"):
            include_path = (root / line[8:]).resolve()
            if not include_path.is_dir():
                raise FileNotFoundError(f"include directory does not exist: {include_path}")
            arguments.extend(("-I", include_path.relative_to(root).as_posix()))
        elif line.startswith("+define+"):
            arguments.append("-D" + line[8:])
        elif line.startswith("-s "):
            arguments.extend(("-s", line[3:].strip()))
        elif line.startswith("-f "):
            arguments.extend(expand(root, line[3:].strip(), seen))
        elif line.endswith((".v", ".sv")):
            source = (root / line).resolve()
            if not source.is_file():
                raise FileNotFoundError(f"source does not exist: {source}")
            arguments.append(source.relative_to(root).as_posix())
        else:
            raise ValueError(f"unsupported entry {path}:{line_number}: {line}")
    return arguments


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("filelist")
    args = parser.parse_args()
    root = args.root.resolve()
    for argument in expand(root, args.filelist, set()):
        print(argument)


if __name__ == "__main__":
    main()
