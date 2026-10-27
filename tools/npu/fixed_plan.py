"""fixed_plan.py — NPU spec 2.1, 2.5, 4.1: fixed 640×384 YOLOv8n graph.

Reserve concatenated surfaces before producers and reuse C2f/SPPF/head scratch.
The six logical adds are retained for calibration, then fused during encoding.
Clock domain: offline host tool.
"""

from dataclasses import asdict, dataclass

from format import BASES, Descriptor, align

MODEL_BASE = BASES["MODEL_BASE"]
ACT_BASE = BASES["WORK_BASE"]
INPUT_WIDTH = 640
INPUT_HEIGHT = 384


@dataclass(frozen=True)
class Tensor:
    name: str
    width: int
    height: int
    channels: int
    base: int

    @property
    def plane_stride(self) -> int:
        return align(self.width * self.height * 16)

    @property
    def size(self) -> int:
        return self.channels // 16 * self.plane_stride


class Planner:
    def __init__(self) -> None:
        self.cursor = ACT_BASE
        self.tensors = {}
        self.commands = []
        self.weight_cursor = MODEL_BASE

    def reserve(self, name, width, height, channels):
        self.cursor = align(self.cursor)
        tensor = Tensor(name, width, height, channels, self.cursor)
        self.tensors[name] = tensor
        self.cursor += tensor.size
        return tensor

    def reserve_group(self, members):
        for member in members:
            self.reserve(*member)

    def alias(self, name, first, second):
        left, right = self.tensors[first], self.tensors[second]
        tensor = Tensor(name, left.width, left.height,
                        left.channels + right.channels, left.base)
        self.tensors[name] = tensor
        return tensor

    def view(self, name, base, source, channels):
        return Tensor(name, source.width, source.height, channels, base)

    def conv(self, name, layer, source, dest, kernel, stride, model_key, activation=True):
        desc = Descriptor(k3=kernel == 3, in_c4=layer == 0,
                          half_tail=dest.channels % 32 == 16,
                          cin_blocks=source.channels // 16,
                          cout_blocks=(dest.channels + 31) // 32)
        self.commands.append(dict(
            name=name, layer=layer, kind="conv", source=source.name, dest=dest.name,
            model_key=model_key, weight_base=self.weight_cursor,
            weight_bytes=desc.weight_bytes, weight_block_stride=desc.weight_block_bytes,
            quant_bytes=desc.cout_blocks * 512, input_base=source.base,
            output_base=dest.base, input_plane_stride=source.plane_stride,
            output_plane_stride=dest.plane_stride, input_width=source.width,
            input_height=source.height, output_width_pairs=dest.width // 2,
            output_height=dest.height, cin_blocks=desc.cin_blocks,
            output_blocks=desc.cout_blocks, kernel3=int(kernel == 3),
            stride2=int(stride == 2), last_c16_only=int(desc.half_tail),
            lut_enable=int(activation)))
        self.weight_cursor += desc.weight_bytes

    def add(self, name, layer, a, b, dest):
        self.commands.append(dict(name=name, layer=layer, kind="add",
                                  input_base=a.base, aux_base=b.base,
                                  output_base=dest.base, beat_count=a.size // 32))

    def movement(self, kind, name, layer, source, dest):
        self.commands.append(dict(
            name=name, layer=layer, kind=kind, source=source.name, dest=dest.name,
            input_base=source.base, output_base=dest.base,
            input_plane_stride=source.plane_stride, output_plane_stride=dest.plane_stride,
            input_width=source.width, input_height=source.height,
            output_width_pairs=dest.width // 2, output_height=dest.height,
            cin_blocks=source.channels // 16))

    def pool(self, name, layer, source, dest):
        self.movement("pool", name, layer, source, dest)

    def up(self, name, layer, source, dest):
        self.movement("up", name, layer, source, dest)

    def c2f(self, layer: int, source: Tensor, dest: Tensor,
            hidden: int, repeats: int, shortcut: bool) -> None:
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


    def finish(self):
        quant_cursor = align(self.weight_cursor)
        for index, command in enumerate(self.commands):
            command["index"] = index
            if command["kind"] == "conv":
                command["quant_base"] = quant_cursor
                quant_cursor += command["quant_bytes"]
        return {
            "model_base": MODEL_BASE,
            "weight_bytes": self.weight_cursor - MODEL_BASE,
            "image_bytes": align(quant_cursor) - MODEL_BASE,
            "work_bytes": self.head1_base + 307200 - ACT_BASE,
            "tensors": {name: asdict(tensor) | {
                "plane_stride": tensor.plane_stride, "bytes": tensor.size}
                for name, tensor in self.tensors.items()},
            "commands": self.commands,
        }


def build_plan() -> dict:
    plan = Planner()
    t = plan.tensors
    # Reserve consumers' concat surfaces in channel order before producers run.
    plan.reserve_group([("L10", 40, 24, 256), ("L6", 40, 24, 128)])
    plan.reserve_group([("L13", 80, 48, 128), ("L4", 80, 48, 64)])
    plan.reserve_group([("L16", 40, 24, 64), ("L12", 40, 24, 128)])
    plan.reserve_group([("L19", 20, 12, 128), ("L9", 20, 12, 256)])
    for name, width, height, channels in [
        ("L0", 320, 192, 16),
        ("L1", 160, 96, 32), ("L2", 160, 96, 32),
        ("L3", 80, 48, 64), ("L5", 40, 24, 128),
        ("L7", 20, 12, 256), ("L8", 20, 12, 256),
        ("L15", 80, 48, 64), ("L18", 40, 24, 128),
        ("L21", 20, 12, 256),
    ]:
        plan.reserve(name, width, height, channels)
    work_cursor = plan.cursor
    plan.cursor = BASES["OUTPUT_BASE"]
    for scale, width, height in [(0, 80, 48), (1, 40, 24), (2, 20, 12)]:
        plan.reserve_group([(f"D{scale}.box", width, height, 64),
                            (f"D{scale}.cls", width, height, 80)])
        plan.alias(f"D{scale}.logits", f"D{scale}.box", f"D{scale}.cls")
    plan.alias("L11", "L10", "L6")
    plan.alias("L14", "L13", "L4")
    plan.alias("L17", "L16", "L12")
    plan.alias("L20", "L19", "L9")
    plan.cursor = work_cursor
    t["input"] = Tensor("input", 640, 384, 16, BASES["INPUT_BASE"])
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


def port(address: int) -> tuple[int, int]:
    for selector, name in reversed(list(enumerate(
            ("MODEL_BASE", "WORK_BASE", "INPUT_BASE", "OUTPUT_BASE")))):
        if address >= BASES[name]:
            return selector, address - BASES[name]


def convolution_descriptor(command: dict, zero_point: int = 0) -> Descriptor:
    in_sel, in_offset = port(command["input_base"])
    out_sel, out_offset = port(command["output_base"])
    return Descriptor(
        k3=bool(command["kernel3"]), s2=bool(command["stride2"]),
        lut_en=bool(command["lut_enable"]), in_c4=command["layer"] == 0,
        half_tail=bool(command["last_c16_only"]),
        in_sel=in_sel, in_offset=in_offset,
        in_plane_stride=0 if command["layer"] == 0 else command["input_plane_stride"],
        out_sel=out_sel, out_offset=out_offset,
        out_plane_stride=command["output_plane_stride"],
        weight_offset=command["weight_base"] - MODEL_BASE,
        quant_offset=command["quant_base"] - MODEL_BASE,
        in_w=command["input_width"], in_h=command["input_height"],
        out_w=command["output_width_pairs"] * 2, out_h=command["output_height"],
        cin_blocks=command["cin_blocks"], cout_blocks=command["output_blocks"],
        out_zp=zero_point)


def descriptors(plan: dict, rows: list[dict]) -> list[Descriptor]:
    zero_points = {row["index"]: row["output_zero_point"] for row in rows}
    result = []
    for command in plan["commands"]:
        kind = command["kind"]
        if kind == "conv":
            result.append(convolution_descriptor(command, zero_points[command["index"]]))
        elif kind == "add":
            # The preceding cv2 already targets the add destination; a is the residual.
            result[-1].res_en = True
            result[-1].res_sel, result[-1].res_offset = port(command["input_base"])
        else:
            in_sel, in_offset = port(command["input_base"])
            out_sel, out_offset = port(command["output_base"])
            result.append(Descriptor(
                op={"pool": 1, "up": 2}[kind], in_sel=in_sel, in_offset=in_offset,
                in_plane_stride=command["input_plane_stride"], out_sel=out_sel,
                out_offset=out_offset, out_plane_stride=command["output_plane_stride"],
                in_w=command["input_width"], in_h=command["input_height"],
                out_w=command["output_width_pairs"] * 2, out_h=command["output_height"],
                cin_blocks=command["cin_blocks"], cout_blocks=0))
    return result
