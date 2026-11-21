"""gen_case.py — NPU spec 2.1–2.3, 4.1–4.3: generate OP-01..OP-12 inputs.

Generate random operator images or 4–8 descriptor chains, including concat.
Reference outputs belong to the independent reference model, not this tool.
Clock domain: offline host tool.
"""

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from format import (BASES, REGIONS, Descriptor, align, pack_c4, pack_c16,
                    pack_quant, pack_weights, write_case)


@dataclass
class Surface:
    selector: int
    offset: int
    width: int
    height: int
    channels: int
    plane_stride: int
    c4: bool = False
    base: int = 0

    @property
    def address(self):
        return self.base + self.offset

    @property
    def size(self):
        if self.c4:
            return self.width * self.height * 4
        return self.channels // 16 * self.plane_stride


class Case:
    def __init__(self, args, bases=None):
        self.args = args
        self.bases = BASES | (bases or {})
        self.rng = np.random.default_rng(args.seed)
        # Feature surfaces in MODEL use a separate arena from weights/parameters.
        self.cursors = [0x00800000 + args.offset, args.offset, args.offset, args.offset]
        self.model_cursor = 0
        self.segments = {region: [] for region in REGIONS}
        self.descriptors = []

    def surface(self, selector, width, height, channels, c4=False,
                offset=None, plane_stride=None):
        stride = 0 if c4 else align(width * height * 16) + self.args.plane_pad
        if plane_stride is not None:
            stride = plane_stride
        if offset is None:
            offset = self.cursors[selector]
        base = self.bases[f"{REGIONS[selector].upper()}_BASE"]
        tensor = Surface(selector, offset, width, height, channels, stride, c4, base)
        self.cursors[selector] = max(self.cursors[selector], offset + align(tensor.size))
        return tensor

    def initialize(self, tensor, negative=False):
        high = 0 if negative else 128
        data = self.rng.integers(-128, high, (tensor.channels, tensor.height, tensor.width),
                                 dtype=np.int8)
        if tensor.c4:
            packed = pack_c4(data.transpose(1, 2, 0))
        else:
            packed = pack_c16(data, tensor.plane_stride)
        self.segments[REGIONS[tensor.selector]].append((tensor.address, packed))

    def parameters(self, desc, channels, quant):
        bias = self.rng.integers(-8192, 8192, channels, dtype=np.int32)
        mult = self.rng.integers(-32768, 32768, channels, dtype=np.int32)
        shift = self.rng.integers(0, 48, channels, dtype=np.uint8)
        mult[0] = -32768
        shift[:2] = [0, 47]
        if self.args.quant_boundaries:
            # OP-08 exercises the extreme signed operands and rounding endpoints.
            bias[:4] = [-2147483648, 2147483647, 0, 1]
            mult[:4] = [-32768, 32767, 0, -1]
            shift[:4] = [0, 47, 1, 46]
        if quant != "random":
            for field, values in (("bias", bias), ("mult", mult), ("shift", shift)):
                selected = quant.get(field, "random")
                if selected != "random":
                    values[:] = selected
            if quant.get("out_zp", "random") != "random":
                desc.out_zp = quant["out_zp"]
        lut = self.rng.integers(-128, 128, 256, dtype=np.int8).tobytes()
        return pack_quant(bias, mult, shift, desc.cout_blocks, lut)

    def operator(self, op, source, dest, kernel=1, stride=1, lut=False, residual=False,
                 res_sel=None, quant="random", weights="random", residual_source=None,
                 half_tail=None):
        desc = Descriptor(
            op=op, k3=op == 0 and kernel == 3, s2=op == 0 and stride == 2,
            lut_en=lut, res_en=residual, in_c4=source.c4,
            half_tail=op == 0 and dest.channels % 32 == 16,
            in_sel=source.selector, in_offset=source.offset,
            in_plane_stride=source.plane_stride, out_sel=dest.selector,
            out_offset=dest.offset, out_plane_stride=dest.plane_stride,
            in_w=source.width, in_h=source.height, out_w=dest.width, out_h=dest.height,
            cin_blocks=1 if source.c4 else source.channels // 16,
            cout_blocks=(dest.channels + 31) // 32 if op == 0 else 0,
            out_zp=int(self.rng.integers(-128, 128)) if op == 0 else 0)
        if half_tail is not None:
            desc.half_tail = half_tail
        if op == 0:
            desc.weight_offset = self.model_cursor
            weight = self.rng.integers(-128, 128,
                                       (dest.channels, source.channels, kernel, kernel),
                                       dtype=np.int8)
            if weights != "random":
                weight.fill({"max": 127, "min": -128}[weights])
            packed_weight = pack_weights(weight, desc)
            desc.quant_offset = desc.weight_offset + len(packed_weight)
            packed_quant = self.parameters(desc, dest.channels, quant)
            self.segments["model"].append((self.bases["MODEL_BASE"] + desc.weight_offset,
                                           packed_weight + packed_quant))
            self.model_cursor = desc.quant_offset + len(packed_quant)
        if residual:
            res = residual_source
            if res is None:
                res = self.surface(res_sel, dest.width, dest.height, dest.channels)
                self.initialize(res)
            desc.res_sel, desc.res_offset = res.selector, res.offset
        self.descriptors.append(desc)
        return dest

    def run(self):
        a = self.args
        source = self.surface(a.in_sel, a.width, a.height, 3 if a.in_c4 else a.cin, a.in_c4)
        self.initialize(source, a.negative_input)
        if a.op == "chain":
            output = self.chain(source)
        else:
            op = {"conv": 0, "pool": 1, "upsample": 2}[a.op]
            if op == 0:
                width = (source.width + a.stride - 1) // a.stride
                height = (source.height + a.stride - 1) // a.stride
                channels = a.cout
            else:
                width = source.width * (2 if op == 2 else 1)
                height = source.height * (2 if op == 2 else 1)
                channels = source.channels
            output = self.surface(a.out_sel, width, height, channels)
            self.operator(op, source, output, a.kernel, a.stride, a.lut, a.res, a.res_sel)
        write_case(a.out, self.descriptors, self.segments,
                   [("output", output.address, output.size)], self.bases)
        print(f"descriptors={len(self.descriptors)} seed={a.seed} out={a.out}")

    def chain(self, source):
        a = self.args
        length = a.length or int(self.rng.integers(4, 9))
        if a.concat:
            stride = 2 if source.c4 else 1
            joined = self.surface(a.out_sel, source.width // stride,
                                  (source.height + stride - 1) // stride, a.cout * 2)
            first = Surface(joined.selector, joined.offset, joined.width, joined.height,
                            a.cout, joined.plane_stride, base=joined.base)
            second = Surface(joined.selector, joined.offset + first.size,
                             joined.width, joined.height, a.cout, joined.plane_stride,
                             base=joined.base)
            self.operator(0, source, first, a.kernel, stride, a.lut, a.res, a.res_sel)
            self.operator(0, source, second, a.kernel, stride, a.lut, a.res, a.res_sel)
            dest = self.surface(int(self.rng.integers(4)), joined.width, joined.height, a.cout)
            source = self.operator(0, joined, dest, 1, 1, a.lut)
        while len(self.descriptors) < length:
            options = [0]
            if not source.c4:
                if source.width <= 20 and source.height <= 12:
                    options.append(1)
                if source.width <= 40:
                    options.append(2)
            op = int(self.rng.choice(options))
            selector = int(self.rng.integers(4))
            if op == 0:
                kernel = 3 if source.c4 else int(self.rng.choice([1, 3]))
                stride = 2 if source.c4 else (
                    int(self.rng.choice([1, 2])) if source.width % 8 == 0 else 1)
                width = (source.width + stride - 1) // stride
                height = (source.height + stride - 1) // stride
                channels = int(self.rng.choice([16, 32, 48, 80]))
                dest = self.surface(selector, width, height, channels)
                source = self.operator(0, source, dest, kernel, stride,
                                       bool(self.rng.integers(2)), bool(self.rng.integers(2)),
                                       int(self.rng.integers(4)))
            else:
                scale = 2 if op == 2 else 1
                dest = self.surface(selector, source.width * scale,
                                    source.height * scale, source.channels)
                source = self.operator(op, source, dest)
        return source


def number(value):
    return int(value, 0) if isinstance(value, str) else int(value)


def configured(case, layers):
    """Resolve declared graph surfaces first, then allocate the model parameters."""
    outputs = []
    scheduled = []
    model_end = 0
    for index, layer in enumerate(layers):
        origin = layer.get("in_from", "input" if index == 0 else index - 1)
        if origin == "input":
            prior = None
        elif isinstance(origin, list):
            parts = [outputs[item] for item in origin]
            first = parts[0]
            prior = Surface(first.selector, first.offset, first.width, first.height,
                            sum(part.channels for part in parts), first.plane_stride,
                            base=first.base)
        else:
            prior = outputs[origin]
        c4 = layer.get("in_c4", False)
        width = layer.get("in_w", prior.width if prior else 8)
        height = layer.get("in_h", prior.height if prior else 6)
        cin = layer.get("cin", prior.channels if prior else (3 if c4 else 16))
        in_selector = REGIONS.index(layer.get("in_sel", REGIONS[prior.selector]
                                             if prior else "input"))
        source = case.surface(
            in_selector, width, height, cin, c4,
            number(layer["in_offset"]) if "in_offset" in layer else (
                prior.offset if prior else None),
            number(layer["in_plane_stride"]) if "in_plane_stride" in layer else (
                prior.plane_stride if prior else None))
        if prior is None:
            case.initialize(source)
        op = {"conv": 0, "pool": 1, "upsample": 2}[layer["op"]]
        kernel, stride = layer.get("k", 1), layer.get("s", 1)
        if op == 0:
            out_w, out_h = (width + stride - 1) // stride, (height + stride - 1) // stride
            cout = layer.get("cout", 32)
        else:
            scale = 2 if op == 2 else 1
            out_w, out_h, cout = width * scale, height * scale, cin
        out_selector = REGIONS.index(layer.get("out_sel", "work"))
        dest = case.surface(
            out_selector, out_w, out_h, cout,
            offset=number(layer["out_offset"]) if "out_offset" in layer else None,
            plane_stride=number(layer["out_plane_stride"])
            if "out_plane_stride" in layer else None)
        residual = None
        if layer.get("res", False):
            res_from = layer.get("res_from")
            prior_res = outputs[res_from] if res_from is not None else None
            res_selector = REGIONS.index(layer.get("res_sel", REGIONS[prior_res.selector]
                                                  if prior_res else "work"))
            residual = case.surface(
                res_selector, out_w, out_h, cout,
                offset=number(layer["res_offset"]) if "res_offset" in layer else (
                    prior_res.offset if prior_res else None),
                plane_stride=dest.plane_stride)
            if prior_res is None:
                case.initialize(residual)
        for surface in (source, dest, residual):
            if surface is not None and surface.selector == 0:
                model_end = max(model_end, surface.offset + surface.size)
        scheduled.append((layer, op, source, dest, residual, kernel, stride))
        outputs.append(dest)
    case.model_cursor = align(model_end)
    for layer, op, source, dest, residual, kernel, stride in scheduled:
        case.operator(op, source, dest, kernel, stride, layer.get("lut", False),
                      layer.get("res", False), quant=layer.get("quant", "random"),
                      weights=layer.get("weights", "random"), residual_source=residual,
                      half_tail=layer.get("half_tail"))
    last = outputs[-1]
    write_case(case.args.out, case.descriptors, case.segments,
               [("output", last.address, last.size)], case.bases)
    print(f"descriptors={len(case.descriptors)} seed={case.args.seed} out={case.args.out}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--op", choices=["conv", "pool", "upsample", "chain"])
    mode.add_argument("--config", type=Path, help="explicit layer graph; see README")
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--width", type=int, default=8)
    parser.add_argument("--height", type=int, default=6)
    parser.add_argument("--cin", type=int, default=16, help="C16 channels; C4 always uses RGB")
    parser.add_argument("--cout", type=int, default=32,
                        help="C16 channels; 16 mod 32 sets HALF_TAIL")
    parser.add_argument("--kernel", type=int, choices=[1, 3], default=1)
    parser.add_argument("--stride", type=int, choices=[1, 2], default=1)
    parser.add_argument("--in-c4", action="store_true")
    parser.add_argument("--lut", action="store_true")
    parser.add_argument("--res", action="store_true")
    for port in ("in", "out", "res"):
        parser.add_argument(f"--{port}-sel", choices=REGIONS,
                            default={"in": "input", "out": "output", "res": "work"}[port])
    parser.add_argument("--offset", type=lambda value: int(value, 0), default=32)
    parser.add_argument("--plane-pad", type=int, default=0, help="extra bytes per C16 plane")
    parser.add_argument("--negative-input", action="store_true", help="all-negative POOL input")
    parser.add_argument("--quant-boundaries", action="store_true")
    parser.add_argument("--concat", action="store_true", help="start a chain with zero-copy concat")
    parser.add_argument("--length", type=int, choices=range(4, 9))
    args = parser.parse_args()
    if args.config:
        config = json.loads(args.config.read_text())
        bases = {key: number(value) for key, value in config.get("bases", {}).items()}
        case = Case(args, bases)
        configured(case, config["layers"])
        return
    if args.width <= 0 or args.height <= 0 or args.width % 2:
        parser.error("spec 2.2: positive dimensions and even width required")
    if args.cin <= 0 or args.cin % 16 or args.cout <= 0 or args.cout % 16:
        parser.error("spec 2.2: --cin/--cout must be positive multiples of 16")
    if args.offset < 0 or args.offset % 32 or args.plane_pad < 0 or args.plane_pad % 32:
        parser.error("spec 4.1: offsets and plane padding must be nonnegative multiples of 32")
    if args.op in ("conv", "chain") and args.width % 4:
        parser.error("spec 2.2: CONV input width must be a multiple of 4")
    if args.in_c4 and (args.op not in ("conv", "chain") or args.width % 8 or
                       args.kernel != 3 or args.stride != 2):
        parser.error("spec 2.2/5.1: C4 needs K3 S2, width divisible by 8")
    if args.op == "pool" and (args.width > 20 or args.height > 12):
        parser.error("spec 5.3: POOL maximum input is 20x12")
    if args.op == "upsample" and args.width > 40:
        parser.error("spec 5.3: UPSAMPLE maximum input width is 40")
    for port in ("in", "out", "res"):
        setattr(args, f"{port}_sel", REGIONS.index(getattr(args, f"{port}_sel")))
    Case(args).run()


if __name__ == "__main__":
    main()
