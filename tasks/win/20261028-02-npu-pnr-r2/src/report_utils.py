"""Collect the completed Windows PDS reports and the separate timing exports.

Run with Python 3 from the checkout. Raw implementation databases and full logs
stay in the FPGA projects; all W:/E: lines and stage timings are retained here.
"""
from pathlib import Path
import re


REPO = Path(__file__).resolve().parents[4]
TASK = REPO / "tasks/win/20261028-02-npu-pnr-r2"
BUILD = REPO / "build/win/20261028-02-npu-pnr-r2"
STAGES = ("compile", "synthesize", "device_map", "place_route", "report_timing")


def read(path):
    return path.read_text(encoding="utf-8", errors="replace")


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8")


def section(text, title):
    tail = text.split(title, 1)[1]
    # A table has a top border, header separator, and bottom border.
    borders = list(re.finditer(r"^\+[-]+\+\s*$", tail, re.M))
    return title + tail[:borders[2].end()]


def paths(text, source):
    result = []
    for block in re.split(r"(?=^Startpoint\s*:)", text, flags=re.M)[1:]:
        def field(key):
            return re.search(r"^" + key + r"\s*:\s*(.*)", block, re.M)[1].strip()
        path_type = field("Path Type")
        cls = field("Path Class")
        slack = (None if cls == "combinational timing path" else
                 float(re.search(r"^\s*Slack \([^)]*\)\s+(-?[\d.]+)", block, re.M)[1]))
        result.append({
            "start": field("Startpoint"), "end": field("Endpoint"),
            "group": field("Path Group"), "type": path_type,
            "corner": re.search(r"\((slow|fast) corner\)", path_type)[1],
            "class": cls, "slack": slack,
            "levels": int(re.search(r"Logic Levels:\s*(\d+)", block)[1]),
            "block": block.rstrip(), "source": source,
        })
    return result


def index_text(records):
    lines = ["source\tcorner\tclock\ttype\tclass\tslack_ns\tlogic_levels\tstartpoint\tendpoint"]
    for p in records:
        lines.append("\t".join(str(v) for v in (
            p["source"], p["corner"], p["group"], p["type"], p["class"],
            "N/A (unconstrained)" if p["slack"] is None else f'{p["slack"]:.3f}',
            p["levels"], p["start"], p["end"])))
    return "\n".join(lines)


def select(records, direction, corner, cls="sequential timing path"):
    return [p for p in records if p["type"].startswith(direction)
            and p["corner"] == corner and p["class"] == cls]


def hierarchy(text):
    table = section(text, "Device Utilization Summary Of Each Module:")
    entries, stack = [], []
    for line in table.splitlines():
        cols = [c.rstrip() for c in line.split("|")[1:]]
        if not cols or not cols[1:6] or not cols[1].strip().isdigit():
            continue
        label = cols[0]
        m = re.match(r"(\s*)\+\s*(\S+)", label)
        if m:
            depth = (len(m[1]) + 1) // 2
            name = m[2]
            stack = stack[:depth] + [name]
        else:
            depth, stack = 0, [label.strip()]
        entries.append({"depth": depth, "path": "/".join(stack),
                        "name": stack[-1], "values": [
                            float(c.strip()) if "." in c else int(c.strip())
                            for c in cols[1:6]]})
    return table, entries


def warning_category(line):
    m = re.match(r"[WE]:\s*([A-Za-z]+-\d+):", line)
    if m:
        return m[1]
    if "Loop was found during constant probe" in line:
        return "ConstantProbeLoop"
    if "fanout" in line.lower():
        return "Uncoded fanout warning"
    return "Uncoded warning"
