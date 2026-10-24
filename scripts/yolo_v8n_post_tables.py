"""Generate fixed YOLOv8n INT8 DFL-exp and class-sigmoid lookup ROMs.

The table is coupled to one exported model image. Regenerate it whenever the
Detect output quantization changes, then rebuild the FPGA bitstream.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import zlib


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MODEL = ROOT / "out/models/yolov8n_int8_coco96_p95.bin"
OUTPUT = ROOT / "rtl/vision/yolo/edrv32_yolo_v8n_post_lut.v"
PARAMS = ROOT / "rtl/include/edrv32_yolo_v8n_post_model.vh"


def generate(model: Path, output: Path) -> dict:
    report = json.loads(model.with_suffix(".json").read_text(encoding="utf-8"))
    image_hash = hashlib.sha256(model.read_bytes()).hexdigest()
    if image_hash != report["image_sha256"]:
        raise ValueError("model image differs from its quantization report")
    rows = {row["name"]: row for row in report["convolutions"]}
    scale_rows = [(rows[f"D{i}.box.out"], rows[f"D{i}.cls.out"])
                  for i in range(3)]
    lines = [
        "// ============================================================================",
        "// File        : edrv32_yolo_v8n_post_lut.v",
        "// Description : Model-specific DFL exp and class sigmoid lookup ROMs.",
        f"// Notes       : Model SHA256 {image_hash}",
        "//               Regenerate with scripts/yolo_v8n_post_tables.py.",
        "// ============================================================================",
        "",
        "module edrv32_yolo_v8n_post_lut (",
        "    input  wire [1:0]  scale_i,",
        "    input  wire [7:0]  diff_i,",
        "    input  wire [7:0]  cls_code_i,",
        "    output wire [15:0] exp_o,",
        "    output wire [15:0] confidence_o",
        ");",
        "    reg [15:0] exp_r;",
        "    reg [15:0] confidence_r;",
        "    assign exp_o = exp_r;",
        "    assign confidence_o = confidence_r;",
        "",
        "    always @(*) begin",
        "        exp_r = 16'd0;",
        "        case ({scale_i, diff_i})",
    ]
    for scale, (box, _) in enumerate(scale_rows):
        for diff in range(256):
            value = round(math.exp(-diff * box["output_scale"]) * 65535)
            lines.append(f"            10'h{(scale << 8) | diff:03x}: exp_r = 16'd{value};")
    lines += [
        "            default: exp_r = 16'd0;",
        "        endcase",
        "        confidence_r = 16'd0;",
        "        case ({scale_i, cls_code_i})",
    ]
    for scale, (_, cls) in enumerate(scale_rows):
        for code in range(256):
            signed_code = code if code < 128 else code - 256
            logit = (signed_code - cls["output_zero_point"]) * cls["output_scale"]
            value = round(32768 / (1.0 + math.exp(-logit)))
            lines.append(
                f"            10'h{(scale << 8) | code:03x}: confidence_r = 16'd{value};")
    lines += [
        "            default: confidence_r = 16'd0;",
        "        endcase",
        "    end",
        "endmodule",
        "",
    ]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")
    model_crc = zlib.crc32(model.read_bytes())
    PARAMS.parent.mkdir(parents=True, exist_ok=True)
    PARAMS.write_text(
        "// Generated with scripts/yolo_v8n_post_tables.py.\n"
        "`ifndef EDRV32_YOLO_V8N_POST_MODEL_VH\n"
        "`define EDRV32_YOLO_V8N_POST_MODEL_VH\n"
        f"`define EDRV32_YOLO_V8N_MODEL_CRC32 32'h{model_crc:08x}\n"
        "`endif\n",
        encoding="utf-8",
    )
    return {
        "model_sha256": image_hash,
        "model_crc32": f"0x{model_crc:08X}",
        "box_scales": [box["output_scale"] for box, _ in scale_rows],
        "class_scales": [cls["output_scale"] for _, cls in scale_rows],
        "class_zero_points": [cls["output_zero_point"] for _, cls in scale_rows],
        "exp_entries": 768,
        "confidence_entries": 768,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    result = generate(args.model, args.output)
    print(json.dumps(result, indent=2))
    print(f"generated: {args.output.resolve()}")


if __name__ == "__main__":
    main()
