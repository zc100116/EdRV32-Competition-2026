"""Generate the fixed 640x384 YOLOv8n convolution execution program.

The output is an address manifest and a Verilog-2001 command ROM. No model
weights are generated here. DFL/box decode, model quantization and camera
ingest are separate development steps.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE_YAML = ROOT / "thirdparty/ultralytics/ultralytics/cfg/models/v8/yolov8.yaml"
MANIFEST = ROOT / "out/board/yolo_v8n_fixed_plan.json"
PROGRAM = ROOT / "rtl/vision/yolo/edrv32_yolo_v8n_program.v"
MODEL_BASE = 0x0010_0000
ACT_BASE = 0x0200_0000
INPUT_WIDTH = 640
INPUT_HEIGHT = 384


def align(value: int, boundary: int = 4096) -> int:
    return (value + boundary - 1) & -boundary


def check_model_definition() -> str:
    source = SOURCE_YAML.read_text(encoding="utf-8")
    rows = [re.sub(r"\s+", "", line.split("#", 1)[0])
            for line in source.splitlines() if re.match(r"\s*-\s*\[", line)]
    expected = [
        "-[-1,1,Conv,[64,3,2]]", "-[-1,1,Conv,[128,3,2]]",
        "-[-1,3,C2f,[128,True]]", "-[-1,1,Conv,[256,3,2]]",
        "-[-1,6,C2f,[256,True]]", "-[-1,1,Conv,[512,3,2]]",
        "-[-1,6,C2f,[512,True]]", "-[-1,1,Conv,[1024,3,2]]",
        "-[-1,3,C2f,[1024,True]]", "-[-1,1,SPPF,[1024,5]]",
        '-[-1,1,nn.Upsample,[None,2,"nearest"]]',
        "-[[-1,6],1,Concat,[1]]", "-[-1,3,C2f,[512]]",
        '-[-1,1,nn.Upsample,[None,2,"nearest"]]',
        "-[[-1,4],1,Concat,[1]]", "-[-1,3,C2f,[256]]",
        "-[-1,1,Conv,[256,3,2]]", "-[[-1,12],1,Concat,[1]]",
        "-[-1,3,C2f,[512]]", "-[-1,1,Conv,[512,3,2]]",
        "-[[-1,9],1,Concat,[1]]", "-[-1,3,C2f,[1024]]",
        "-[[15,18,21],1,Detect,[nc]]",
    ]
    if rows != expected or "n: [0.33, 0.25, 1024]" not in source:
        raise ValueError("local Ultralytics YOLOv8n graph differs from the fixed plan")
    return hashlib.sha256(source.encode()).hexdigest()


@dataclass(frozen=True)
class Tensor:
    name: str
    width: int
    height: int
    channels: int
    base: int

    @property
    def plane_stride(self) -> int:
        assert self.width % 2 == 0 and self.channels % 16 == 0
        return self.width * self.height * 16

    @property
    def size(self) -> int:
        return self.channels // 16 * self.plane_stride


@dataclass
class Command:
    name: str
    layer: int
    kind: str
    source: str
    dest: str
    aux: str = ""
    model_key: str = ""
    weight_base: int = 0
    weight_bytes: int = 0
    weight_block_stride: int = 0
    quant_base: int = 0
    quant_bytes: int = 0
    input_base: int = 0
    aux_base: int = 0
    output_base: int = 0
    input_plane_stride: int = 0
    output_plane_stride: int = 0
    input_width: int = 0
    input_height: int = 0
    output_width_pairs: int = 0
    output_height: int = 0
    cin_blocks: int = 0
    output_blocks: int = 0
    cache_bank_stride: int = 0
    cache_row_stride: int = 0
    tile_pairs: int = 0
    kernel3: int = 0
    stride2: int = 0
    last_c16_only: int = 0
    beat_count: int = 0
    residual_zero_point: int = 0
    lut_enable: int = 0


FIELDS = [
    ("cmd_op", 2, "op"),
    ("cmd_input_base", 32, "input_base"),
    ("cmd_aux_base", 32, "aux_base"),
    ("cmd_output_base", 32, "output_base"),
    ("cmd_input_plane_stride", 32, "input_plane_stride"),
    ("cmd_output_plane_stride", 32, "output_plane_stride"),
    ("cmd_weight_base", 32, "weight_base"),
    ("cmd_weight_block_stride", 32, "weight_block_stride"),
    ("cmd_input_width", 11, "input_width"),
    ("cmd_input_height", 16, "input_height"),
    ("cmd_output_width_pairs", 10, "output_width_pairs"),
    ("cmd_output_height", 16, "output_height"),
    ("cmd_cin_blocks", 6, "cin_blocks"),
    ("cmd_output_blocks", 5, "output_blocks"),
    ("cmd_cache_bank_stride", 9, "cache_bank_stride"),
    ("cmd_cache_row_stride", 10, "cache_row_stride"),
    ("cmd_tile_pairs", 10, "tile_pairs"),
    ("cmd_kernel3", 1, "kernel3"),
    ("cmd_stride2", 1, "stride2"),
    ("cmd_last_c16_only", 1, "last_c16_only"),
    ("cmd_beat_count", 16, "beat_count"),
    ("cmd_residual_zero_point", 8, "residual_zero_point"),
    ("cmd_lut_enable", 1, "lut_enable"),
    ("cfg_base", 32, "quant_base"),
    ("layer_id", 5, "layer"),
]
OP_CODE = {"conv": 0, "add": 1, "pool": 2, "up": 3}


class Planner:
    def __init__(self) -> None:
        self.cursor = ACT_BASE
        self.tensors: dict[str, Tensor] = {}
        self.commands: list[Command] = []
        self.weight_cursor = MODEL_BASE
        self.workspace_base = 0
        self.temp_base = 0

    def reserve(self, name: str, width: int, height: int,
                channels: int) -> Tensor:
        self.cursor = align(self.cursor)
        tensor = Tensor(name, width, height, channels, self.cursor)
        self.tensors[name] = tensor
        self.cursor += tensor.size
        return tensor

    def reserve_group(self, members: list[tuple[str, int, int, int]]) -> None:
        self.cursor = align(self.cursor)
        for name, width, height, channels in members:
            tensor = Tensor(name, width, height, channels, self.cursor)
            self.tensors[name] = tensor
            self.cursor += tensor.size

    def alias(self, name: str, first: str, second: str) -> Tensor:
        left, right = self.tensors[first], self.tensors[second]
        assert (left.width, left.height) == (right.width, right.height)
        assert left.base + left.size == right.base
        tensor = Tensor(name, left.width, left.height,
                        left.channels + right.channels, left.base)
        self.tensors[name] = tensor
        return tensor

    def view(self, name: str, base: int, source: Tensor,
             channels: int) -> Tensor:
        return Tensor(name, source.width, source.height, channels, base)

    def conv(self, name: str, layer: int, source: Tensor,
             dest: Tensor, kernel: int, stride: int, model_key: str,
             activation: bool = True) -> None:
        assert kernel in (1, 3) and stride in (1, 2)
        assert (dest.width, dest.height) == (
            source.width // stride, source.height // stride)
        cin_blocks = source.channels // 16
        output_blocks = (dest.channels + 31) // 32
        k_count = 2 * cin_blocks * kernel * kernel
        bank_stride = source.width // 4
        row_stride = cin_blocks * bank_stride
        tile_pairs = min(4, 1024 // k_count, dest.width // 2)
        assert 0 < k_count <= 512 and 0 < tile_pairs
        assert row_stride <= 1024 and (kernel == 1 or row_stride * 5 <= 1024)
        assert bank_stride <= 511 and output_blocks <= 31
        block_stride = k_count * 256
        command = Command(
            name=name, layer=layer, kind="conv", source=source.name,
            dest=dest.name, model_key=model_key,
            weight_base=self.weight_cursor,
            weight_bytes=output_blocks * block_stride,
            weight_block_stride=block_stride,
            quant_bytes=output_blocks * 512,
            input_base=source.base, output_base=dest.base,
            input_plane_stride=source.plane_stride,
            output_plane_stride=dest.plane_stride,
            input_width=source.width, input_height=source.height,
            output_width_pairs=dest.width // 2,
            output_height=dest.height, cin_blocks=cin_blocks,
            output_blocks=output_blocks,
            cache_bank_stride=bank_stride,
            cache_row_stride=row_stride, tile_pairs=tile_pairs,
            kernel3=int(kernel == 3), stride2=int(stride == 2),
            last_c16_only=int(dest.channels % 32 == 16),
            lut_enable=int(activation),
        )
        self.commands.append(command)
        self.weight_cursor += command.weight_bytes

    def add(self, name: str, layer: int, a: Tensor,
            b: Tensor, dest: Tensor) -> None:
        assert (a.width, a.height, a.channels) == (
            b.width, b.height, b.channels) == (
            dest.width, dest.height, dest.channels)
        beats = a.size // 32
        assert 0 < beats <= 65535
        self.commands.append(Command(
            name=name, layer=layer, kind="add", source=a.name,
            dest=dest.name, aux=b.name,
            input_base=a.base, aux_base=b.base, output_base=dest.base,
            beat_count=beats,
        ))

    def pool(self, name: str, layer: int,
             source: Tensor, dest: Tensor) -> None:
        assert (source.width, source.height, source.channels) == (
            dest.width, dest.height, dest.channels)
        assert source.width <= 20 and source.height <= 12
        self.commands.append(Command(
            name=name, layer=layer, kind="pool", source=source.name,
            dest=dest.name, input_base=source.base, output_base=dest.base,
            input_plane_stride=source.plane_stride,
            output_plane_stride=dest.plane_stride,
            input_width=source.width, input_height=source.height,
            cin_blocks=source.channels // 16,
        ))

    def up(self, name: str, layer: int,
           source: Tensor, dest: Tensor) -> None:
        assert (dest.width, dest.height, dest.channels) == (
            source.width * 2, source.height * 2, source.channels)
        assert source.width <= 40 and source.height <= 24
        self.commands.append(Command(
            name=name, layer=layer, kind="up", source=source.name,
            dest=dest.name, input_base=source.base, output_base=dest.base,
            input_plane_stride=source.plane_stride,
            output_plane_stride=dest.plane_stride,
            input_width=source.width, input_height=source.height,
            cin_blocks=source.channels // 16,
        ))

    def c2f(self, layer: int, source: Tensor, dest: Tensor,
            hidden: int, repeats: int, shortcut: bool) -> None:
        assert repeats in (1, 2)
        stride = source.plane_stride
        workspace = self.view(f"L{layer}.workspace", self.workspace_base,
                              source, (2 + repeats) * hidden)
        temp = self.view(f"L{layer}.temp", self.temp_base, source, hidden)

        def group(index: int) -> Tensor:
            return self.view(f"L{layer}.g{index}",
                             self.workspace_base + index * hidden // 16 * stride,
                             source, hidden)

        split = self.view(f"L{layer}.split", self.workspace_base,
                          source, 2 * hidden)
        self.conv(f"L{layer}.split", layer, source, split,
                  1, 1, f"model.{layer}.cv1")
        for index in range(repeats):
            prefix = f"model.{layer}.m.{index}"
            self.conv(f"L{layer}.b{index}.cv1", layer, group(index + 1),
                      temp, 3, 1, f"{prefix}.cv1")
            self.conv(f"L{layer}.b{index}.cv2", layer, temp,
                      group(index + 2), 3, 1, f"{prefix}.cv2")
            if shortcut:
                self.add(f"L{layer}.b{index}.add", layer,
                         group(index + 1), group(index + 2), group(index + 2))
        self.conv(f"L{layer}.fuse", layer, workspace, dest,
                  1, 1, f"model.{layer}.cv2")

    def sppf(self, source: Tensor, dest: Tensor) -> None:
        group_stride = source.plane_stride * 8
        groups = [self.view(f"L9.g{index}",
                            self.workspace_base + index * group_stride,
                            source, 128) for index in range(4)]
        workspace = self.view("L9.workspace", self.workspace_base,
                              source, 512)
        self.conv("L9.cv1", 9, source, groups[0], 1, 1, "model.9.cv1")
        for index in range(3):
            self.pool(f"L9.pool{index}", 9, groups[index], groups[index + 1])
        self.conv("L9.cv2", 9, workspace, dest, 1, 1, "model.9.cv2")

    def detect(self, scale: int, source: Tensor,
               box: Tensor, cls: Tensor) -> None:
        assert scale in (0, 1, 2)
        assert box.channels == 64 and cls.channels == 80
        box0 = self.view(f"D{scale}.box0", self.head0_base, source, 64)
        box1 = self.view(f"D{scale}.box1", self.head1_base, source, 64)
        cls0 = self.view(f"D{scale}.cls0", self.head0_base, source, 80)
        cls1 = self.view(f"D{scale}.cls1", self.head1_base, source, 80)
        prefix = f"model.22.cv2.{scale}"
        self.conv(f"D{scale}.box.cv0", 22, source, box0, 3, 1,
                  f"{prefix}.0")
        self.conv(f"D{scale}.box.cv1", 22, box0, box1, 3, 1,
                  f"{prefix}.1")
        self.conv(f"D{scale}.box.out", 22, box1, box, 1, 1,
                  f"{prefix}.2", activation=False)
        prefix = f"model.22.cv3.{scale}"
        self.conv(f"D{scale}.cls.cv0", 22, source, cls0, 3, 1,
                  f"{prefix}.0")
        self.conv(f"D{scale}.cls.cv1", 22, cls0, cls1, 3, 1,
                  f"{prefix}.1")
        self.conv(f"D{scale}.cls.out", 22, cls1, cls, 1, 1,
                  f"{prefix}.2", activation=False)

    def finish(self) -> dict:
        quant_cursor = align(self.weight_cursor)
        for command in self.commands:
            if command.kind == "conv":
                command.quant_base = quant_cursor
                quant_cursor += command.quant_bytes
        for index, command in enumerate(self.commands):
            assert command.layer < 23
            for port, width, attr in FIELDS:
                value = (OP_CODE[command.kind] if attr == "op"
                         else getattr(command, attr))
                if not 0 <= value < (1 << width):
                    raise ValueError(f"command {index} {port} overflows")
        assert len(self.commands) == 74
        assert quant_cursor - MODEL_BASE < MAX_IMAGE_BYTES
        assert self.workspace_base >= self.cursor_persistent
        assert self.temp_base >= self.workspace_base + 737280
        return {
            "format": "edrv32-yolov8n-fixed-plan-v1",
            "input_shape": [INPUT_HEIGHT, INPUT_WIDTH, 3],
            "yaml_sha256": check_model_definition(),
            "model_base": MODEL_BASE,
            "weight_bytes": self.weight_cursor - MODEL_BASE,
            "quant_offset": align(self.weight_cursor) - MODEL_BASE,
            "image_bytes": align(quant_cursor) - MODEL_BASE,
            "activation_base": ACT_BASE,
            "activation_end": self.head1_base + 307200,
            "scratch_workspace_base": self.workspace_base,
            "scratch_temp_base": self.temp_base,
            "scratch_head0_base": self.head0_base,
            "scratch_head1_base": self.head1_base,
            "tensors": {name: asdict(tensor) | {
                "plane_stride": tensor.plane_stride, "bytes": tensor.size}
                for name, tensor in self.tensors.items()},
            "commands": [asdict(command) | {"index": index,
                         "op": OP_CODE[command.kind]}
                         for index, command in enumerate(self.commands)],
        }


MAX_IMAGE_BYTES = 65535 * 1024


def build_plan() -> dict:
    check_model_definition()
    plan = Planner()
    t = plan.tensors
    # Reserve consumers' concat surfaces in channel order before producers run.
    plan.reserve_group([("L10", 40, 24, 256), ("L6", 40, 24, 128)])
    plan.reserve_group([("L13", 80, 48, 128), ("L4", 80, 48, 64)])
    plan.reserve_group([("L16", 40, 24, 64), ("L12", 40, 24, 128)])
    plan.reserve_group([("L19", 20, 12, 128), ("L9", 20, 12, 256)])
    for name, width, height, channels in [
        ("input", 640, 384, 16), ("L0", 320, 192, 16),
        ("L1", 160, 96, 32), ("L2", 160, 96, 32),
        ("L3", 80, 48, 64), ("L5", 40, 24, 128),
        ("L7", 20, 12, 256), ("L8", 20, 12, 256),
        ("L15", 80, 48, 64), ("L18", 40, 24, 128),
        ("L21", 20, 12, 256),
    ]:
        plan.reserve(name, width, height, channels)
    for scale, width, height in [(0, 80, 48), (1, 40, 24), (2, 20, 12)]:
        plan.reserve_group([(f"D{scale}.box", width, height, 64),
                            (f"D{scale}.cls", width, height, 80)])
        plan.alias(f"D{scale}.logits", f"D{scale}.box", f"D{scale}.cls")
    plan.alias("L11", "L10", "L6")
    plan.alias("L14", "L13", "L4")
    plan.alias("L17", "L16", "L12")
    plan.alias("L20", "L19", "L9")
    plan.cursor_persistent = align(plan.cursor)
    plan.workspace_base = plan.cursor_persistent
    plan.temp_base = align(plan.workspace_base + 737280)
    plan.head0_base = align(plan.temp_base + 245760)
    plan.head1_base = align(plan.head0_base + 307200)

    plan.conv("L0", 0, t["input"], t["L0"], 3, 2, "model.0")
    plan.conv("L1", 1, t["L0"], t["L1"], 3, 2, "model.1")
    plan.c2f(2, t["L1"], t["L2"], 16, 1, True)
    plan.conv("L3", 3, t["L2"], t["L3"], 3, 2, "model.3")
    plan.c2f(4, t["L3"], t["L4"], 32, 2, True)
    plan.conv("L5", 5, t["L4"], t["L5"], 3, 2, "model.5")
    plan.c2f(6, t["L5"], t["L6"], 64, 2, True)
    plan.conv("L7", 7, t["L6"], t["L7"], 3, 2, "model.7")
    plan.c2f(8, t["L7"], t["L8"], 128, 1, True)
    plan.sppf(t["L8"], t["L9"])
    plan.up("L10", 10, t["L9"], t["L10"])
    plan.c2f(12, t["L11"], t["L12"], 64, 1, False)
    plan.up("L13", 13, t["L12"], t["L13"])
    plan.c2f(15, t["L14"], t["L15"], 32, 1, False)
    plan.conv("L16", 16, t["L15"], t["L16"], 3, 2, "model.16")
    plan.c2f(18, t["L17"], t["L18"], 64, 1, False)
    plan.conv("L19", 19, t["L18"], t["L19"], 3, 2, "model.19")
    plan.c2f(21, t["L20"], t["L21"], 128, 1, False)
    plan.detect(0, t["L15"], t["D0.box"], t["D0.cls"])
    plan.detect(1, t["L18"], t["D1.box"], t["D1.cls"])
    plan.detect(2, t["L21"], t["D2.box"], t["D2.cls"])
    return plan.finish()


def render_program(manifest: dict) -> str:
    commands = manifest["commands"]
    lines = [
        "// ============================================================================",
        "// File        : edrv32_yolo_v8n_program.v",
        "// Description : Generated fixed YOLOv8n 640x384 convolution program.",
        "// Notes       : Regenerate with scripts/yolo_v8n_fixed_plan.py.",
        "//               One command is issued only after the previous one completes.",
        "// ============================================================================",
        "",
        "module edrv32_yolo_v8n_program (",
        "    input  wire        clk_i,",
        "    input  wire        rst_n_i,",
        "    input  wire        start_i,",
        "    output wire        start_ready_o,",
        "    output wire        busy_o,",
        "    output wire        done_o,",
        "    output wire        error_o,",
        "    output wire [6:0]  step_o,",
        "    output wire        cmd_valid_o,",
        "    input  wire        cmd_ready_i,",
        "    input  wire        cmd_done_i,",
        "    input  wire        cmd_error_i,",
        "    input  wire        abort_i,",
    ]
    for index, (port, width, _) in enumerate(FIELDS):
        comma = "," if index != len(FIELDS) - 1 else ""
        bits = f"[{width-1}:0] " if width > 1 else ""
        lines.append(f"    output wire {bits:>8}{port}_o{comma}")
    lines += [
        ");", "",
        "    localparam [1:0] S_IDLE = 2'd0;",
        "    localparam [1:0] S_ISSUE = 2'd1;",
        "    localparam [1:0] S_WAIT = 2'd2;",
        "    reg [1:0] state_r;",
        "    reg [6:0] step_r;",
        "    reg done_r;",
        "    reg error_r;",
    ]
    for port, width, _ in FIELDS:
        bits = f"[{width-1}:0] " if width > 1 else ""
        lines.append(f"    reg {bits}{port}_w;")
    lines += [
        "", "    assign start_ready_o = state_r == S_IDLE;",
        "    assign busy_o = state_r != S_IDLE;",
        "    assign done_o = done_r;",
        "    assign error_o = error_r;",
        "    assign step_o = step_r;",
        "    assign cmd_valid_o = state_r == S_ISSUE;",
    ]
    for port, _, _ in FIELDS:
        lines.append(f"    assign {port}_o = {port}_w;")
    lines += ["", "    always @(*) begin"]
    for port, width, _ in FIELDS:
        lines.append(f"        {port}_w = {width}'d0;")
    lines += ["        case (step_r)"]
    for command in commands:
        lines.append(f"            // {command['name']}: {command['source']} -> {command['dest']}")
        lines.append(f"            7'd{command['index']}: begin")
        for port, width, attr in FIELDS:
            value = command[attr]
            if value:
                literal = (f"32'h{value:08x}" if width == 32 else
                           f"{width}'d{value}")
                lines.append(f"                {port}_w = {literal};")
        lines.append("            end")
    lines += [
        "            default: begin end",
        "        endcase",
        "    end", "",
        "    always @(posedge clk_i or negedge rst_n_i) begin",
        "        if (!rst_n_i) begin",
        "            state_r <= S_IDLE;",
        "            step_r <= 7'd0;",
        "            done_r <= 1'b0;",
        "            error_r <= 1'b0;",
        "        end else begin",
        "            done_r <= 1'b0;",
        "            if (abort_i && state_r != S_IDLE) begin",
        "                error_r <= 1'b1;",
        "                done_r <= 1'b1;",
        "                state_r <= S_IDLE;",
        "            end else case (state_r)",
        "                S_IDLE: if (start_i) begin",
        "                    step_r <= 7'd0;",
        "                    error_r <= 1'b0;",
        "                    state_r <= S_ISSUE;",
        "                end",
        "                S_ISSUE: if (cmd_ready_i)",
        "                    state_r <= S_WAIT;",
        "                S_WAIT: if (cmd_done_i) begin",
        "                    if (cmd_error_i || step_r == 7'd73) begin",
        "                        error_r <= cmd_error_i;",
        "                        done_r <= 1'b1;",
        "                        state_r <= S_IDLE;",
        "                    end else begin",
        "                        step_r <= step_r + 7'd1;",
        "                        state_r <= S_ISSUE;",
        "                    end",
        "                end",
        "                default: state_r <= S_IDLE;",
        "            endcase",
        "        end",
        "    end",
        "endmodule", "",
    ]
    return "\n".join(lines)


def main() -> None:
    manifest = build_plan()
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    PROGRAM.write_text(render_program(manifest), encoding="utf-8")
    print(f"commands={len(manifest['commands'])} tensors={len(manifest['tensors'])}")
    print(f"weight_bytes={manifest['weight_bytes']} image_bytes={manifest['image_bytes']}")
    print(f"activation_end=0x{manifest['activation_end']:08x}")
    print(f"manifest={MANIFEST}")
    print(f"program={PROGRAM}")


if __name__ == "__main__":
    main()
