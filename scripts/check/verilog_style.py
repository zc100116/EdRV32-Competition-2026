#!/usr/bin/env python3
"""Check and mechanically normalize the hand-maintained Verilog source tree.

The formatter deliberately handles only transformations that cannot change HDL
semantics: splitting declarations and named parameter/port connections onto one
item per line.  Logical line wrapping and comments remain a designer decision.
Generated vendor IP below an ``ip`` directory is never modified.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RTL_ROOTS = (ROOT / "rtl" / "com", ROOT / "rtl" / "cpu", ROOT / "rtl" / "soc")
DECLARATION_RE = re.compile(
    r"^(?P<indent>\s*)(?P<kind>wire|reg|logic)"
    r"(?P<width>\s+\[[^\]]+\])?\s+(?P<body>[^;]+);(?P<comment>\s*//.*)?$"
)
ONE_LINE_INSTANCE_RE = re.compile(
    r"^(?P<indent>\s*)(?P<head>[A-Za-z_$][\w$]*\s+"
    r"[A-Za-z_$][\w$]*)\s*\(\s*(?P<ports>\.[^;]+)\);\s*$"
)
REDUNDANT_DIRECTION_RE = re.compile(r"\b(?:in|out)_[A-Za-z_$][\w$]*_[io]\b")
REDUNDANT_DIRECTION_CAPTURE_RE = re.compile(
    r"\b(?:in|out)_(?P<semantic>[A-Za-z_$][\w$]*_[io])\b"
)
SHORT_PREDICTION_RE = re.compile(r"pred_(?:taken|target)")
LEGACY_MEMORY_STAGE_RE = re.compile(r"(?<![di])mem_(?:req|resp)_")


def source_files() -> list[Path]:
    """Return hand-maintained Verilog files in stable path order."""

    files: list[Path] = []
    for source_root in RTL_ROOTS:
        for path in source_root.rglob("*.v"):
            if "ip" not in {part.lower() for part in path.parts}:
                files.append(path)
    return sorted(files)


def interface_consumer_files() -> list[Path]:
    """Return active RTL and rewrite testbenches that consume its ports."""

    files = set(source_files())
    for suffix in ("*.v", "*.sv"):
        files.update((ROOT / "sim" / "cases" / "cpu-rewrite").rglob(suffix))
    return sorted(files)


def rename_direction_prefixes(path: Path) -> bool:
    """Remove redundant in_/out_ words while retaining the _i/_o suffix."""

    original = path.read_text(encoding="utf-8")
    if (ROOT / "sim") in path.parents:
        # Testbench-local signal names describe stimulus/observations and are
        # not module ports. Rename only the named port keys they connect to.
        renamed = re.sub(
            r"\.(?:in|out)_(?P<semantic>[A-Za-z_$][\w$]*_[io])(?=\s*\()",
            lambda match: "." + match.group("semantic"),
            original,
        )
    else:
        renamed = REDUNDANT_DIRECTION_CAPTURE_RE.sub(
            lambda match: match.group("semantic"),
            original,
        )

    # FENCE and FENCE.I otherwise become fence_i and fence_i_i.  Keep the
    # architectural instruction name legible while the final suffix continues
    # to express module direction.
    renamed = re.sub(r"\bfence_i_i\b", "fencei_i", renamed)
    renamed = re.sub(r"\bfence_i_o\b", "fencei_o", renamed)
    renamed = re.sub(r"\bfence_i_(?=[A-Za-z0-9_$])", "fencei_", renamed)
    renamed = re.sub(r"(?<=[A-Za-z0-9_$])_fence_i_", "_fencei_", renamed)

    if renamed == original:
        return False
    path.write_text(renamed, encoding="utf-8", newline="\n")
    return True


def split_top_level_commas(text: str) -> list[str]:
    """Split a declaration or connection list without entering expressions."""

    parts: list[str] = []
    start = 0
    round_depth = 0
    square_depth = 0
    brace_depth = 0
    in_string = False
    escaped = False

    for index, char in enumerate(text):
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue

        if char == '"':
            in_string = True
        elif char == "(":
            round_depth += 1
        elif char == ")":
            round_depth -= 1
        elif char == "[":
            square_depth += 1
        elif char == "]":
            square_depth -= 1
        elif char == "{":
            brace_depth += 1
        elif char == "}":
            brace_depth -= 1
        elif char == "," and round_depth == square_depth == brace_depth == 0:
            parts.append(text[start:index].strip())
            start = index + 1

    parts.append(text[start:].strip())
    return parts


def split_named_connections(text: str) -> list[str]:
    """Split ``.name(expression)`` items at their top-level commas."""

    return split_top_level_commas(text)


def format_line(line: str) -> list[str]:
    """Apply the supported whitespace-only transformations to one source line."""

    instance_match = ONE_LINE_INSTANCE_RE.match(line)
    if instance_match:
        ports = split_named_connections(instance_match.group("ports"))
        if len(ports) > 1:
            indent = instance_match.group("indent")
            result = [f"{indent}{instance_match.group('head')} ("]
            result.extend(f"{indent}    {port}{',' if i + 1 < len(ports) else ''}"
                          for i, port in enumerate(ports))
            result.append(f"{indent});")
            return result

    declaration_match = DECLARATION_RE.match(line)
    if declaration_match:
        names = split_top_level_commas(declaration_match.group("body"))
        if len(names) > 1:
            indent = declaration_match.group("indent")
            kind = declaration_match.group("kind")
            width = declaration_match.group("width") or ""
            comment = declaration_match.group("comment") or ""
            return [
                f"{indent}{kind}{width} {name};{comment if i == 0 else ''}"
                for i, name in enumerate(names)
            ]

    if re.search(r"\),\s+(?=\.[A-Za-z_$])", line):
        indent = re.match(r"^\s*", line).group(0)
        return re.sub(
            r"\),\s+(?=\.[A-Za-z_$])",
            "),\n" + indent,
            line,
        ).splitlines()

    return [line.rstrip()]


def format_file(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    had_final_newline = original.endswith("\n")
    formatted_lines: list[str] = []
    for line in original.splitlines():
        formatted_lines.extend(format_line(line))
    formatted = "\n".join(formatted_lines)
    if had_final_newline:
        formatted += "\n"
    if formatted == original:
        return False
    path.write_text(formatted, encoding="utf-8", newline="\n")
    return True


def declaration_has_multiple_names(line: str) -> bool:
    match = DECLARATION_RE.match(line)
    return bool(match and len(split_top_level_commas(match.group("body"))) > 1)


def named_connections_share_line(line: str) -> bool:
    return len(re.findall(r"\.[A-Za-z_$][\w$]*\s*\(", line)) > 1


def check_file(path: Path) -> list[str]:
    issues: list[str] = []
    relative = path.relative_to(ROOT).as_posix()
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if declaration_has_multiple_names(line):
            issues.append(f"{relative}:{line_number}: multiple signal declarations")
        if named_connections_share_line(line):
            issues.append(f"{relative}:{line_number}: multiple named connections")
        if REDUNDANT_DIRECTION_RE.search(line):
            issues.append(f"{relative}:{line_number}: redundant in_/out_ direction prefix")
        if SHORT_PREDICTION_RE.search(line):
            issues.append(
                f"{relative}:{line_number}: use predicted_taken/predicted_target"
            )
        if LEGACY_MEMORY_STAGE_RE.search(line):
            issues.append(
                f"{relative}:{line_number}: use the official MEM1/MEM2 stage name"
            )
        if len(line) > 100 and not line.lstrip().startswith("//"):
            issues.append(f"{relative}:{line_number}: code line exceeds 100 columns")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--fix",
        action="store_true",
        help="split declarations and named connections before checking",
    )
    parser.add_argument(
        "--rename-direction-prefixes",
        action="store_true",
        help="remove redundant in_/out_ prefixes in RTL and testbench files",
    )
    args = parser.parse_args()

    files = source_files()
    if args.rename_direction_prefixes:
        changed = sum(rename_direction_prefixes(path)
                      for path in interface_consumer_files())
        print(f"renamed interfaces in {changed} RTL/testbench files")
    if args.fix:
        changed = sum(format_file(path) for path in files)
        print(f"formatted {changed} of {len(files)} hand-maintained Verilog files")

    issues = [issue for path in files for issue in check_file(path)]
    if issues:
        print("\n".join(issues))
        print(f"FAIL: {len(issues)} style issue(s)")
        return 1

    print(f"PASS: {len(files)} hand-maintained Verilog files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
