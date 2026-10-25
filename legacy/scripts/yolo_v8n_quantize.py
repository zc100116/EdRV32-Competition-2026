"""Calibrate and pack a candidate INT8 YOLOv8n image for the FPGA.

Input images must match the intended camera scenes. This exporter implements
the fixed ROM's symmetric INT8 arithmetic, zero-copy concat, residual scale
sharing and 512-byte quantization records. An exported candidate still needs
layerwise and detection-accuracy validation before board inference.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import zlib

import cv2
import numpy as np
import torch
import torch.nn.functional as functional
from ultralytics import YOLO

from yolo_v8n_checkpoint_audit import resolve_conv
from yolo_v8n_weight_layout import pack_int8


ROOT = Path(__file__).resolve().parents[1]
PLAN_PATH = ROOT / "out/board/yolo_v8n_fixed_plan.json"
DEFAULT_WEIGHTS = ROOT / "out/models/yolov8n.pt"
DEFAULT_OUTPUT = ROOT / "out/models/yolov8n_int8_candidate.bin"
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".bmp"}


def prepare_image(path: Path) -> torch.Tensor:
    """RGB /255 with centered 114 padding and fixed 384x640 geometry."""
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError(f"cannot read calibration image: {path}")
    height, width = image.shape[:2]
    ratio = min(640 / width, 384 / height)
    resized_width = round(width * ratio)
    resized_height = round(height * ratio)
    if (resized_width, resized_height) != (width, height):
        image = cv2.resize(image, (resized_width, resized_height),
                           interpolation=cv2.INTER_LINEAR)
    dw, dh = 640 - resized_width, 384 - resized_height
    left, top = dw // 2, dh // 2
    image = cv2.copyMakeBorder(image, top, dh - top, left, dw - left,
                               cv2.BORDER_CONSTANT, value=(114, 114, 114))
    rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    tensor = torch.from_numpy(np.ascontiguousarray(rgb.transpose(2, 0, 1)))
    return tensor.unsqueeze(0).to(torch.float32) / 255.0


def calibration_images(directory: Path, limit: int) -> list[Path]:
    if directory.is_file():
        return [directory]
    images = sorted(path for path in directory.rglob("*")
                    if path.suffix.lower() in IMAGE_SUFFIXES)
    if not images:
        raise ValueError(f"no calibration images in {directory}")
    return images[:limit]


def collect_ranges(network: torch.nn.Module, commands: list[dict],
                   images: list[Path], percentile: float
                   ) -> tuple[dict, dict, dict, dict, dict]:
    pre_samples: dict[int, list[float]] = {}
    post_samples: dict[int, list[float]] = {}
    add_samples: dict[int, list[float]] = {}
    linear_min_samples: dict[int, list[float]] = {}
    linear_max_samples: dict[int, list[float]] = {}
    hooks = []

    def update(destination: dict, index: int, output: torch.Tensor) -> None:
        value = float(output.detach().abs().max().item())
        destination.setdefault(index, []).append(value)

    for command in commands:
        index = command["index"]
        if command["kind"] == "conv":
            module = resolve_conv(network, command["model_key"])
            if hasattr(module, "conv"):
                hooks.append(module.conv.register_forward_hook(
                    lambda _m, _i, o, key=index: update(pre_samples, key, o)))
                hooks.append(module.register_forward_hook(
                    lambda _m, _i, o, key=index: update(post_samples, key, o)))
            else:
                def capture_linear(_module: torch.nn.Module, _inputs: tuple,
                                   output: torch.Tensor, key: int = index) -> None:
                    update(pre_samples, key, output)
                    update(post_samples, key, output)
                    linear_min_samples.setdefault(key, []).append(
                        float(output.min()))
                    linear_max_samples.setdefault(key, []).append(
                        float(output.max()))
                hooks.append(module.register_forward_hook(capture_linear))
        elif command["kind"] == "add":
            match = re.fullmatch(r"L(\d+)\.b(\d+)\.add", command["name"])
            if not match:
                raise ValueError(f"unexpected shortcut: {command['name']}")
            layer, bottleneck = map(int, match.groups())
            module = network.model[layer].m[bottleneck]
            hooks.append(module.register_forward_hook(
                lambda _m, _i, o, key=index: update(add_samples, key, o)))
    try:
        with torch.inference_mode():
            for path in images:
                network(prepare_image(path))
    finally:
        for hook in hooks:
            hook.remove()
    missing = [command["name"] for command in commands
               if command["kind"] == "conv" and
               (command["index"] not in pre_samples or
                command["index"] not in post_samples)]
    if missing or len(add_samples) != 6:
        raise ValueError(f"calibration hooks missed: {missing}; adds={len(add_samples)}")
    pre_max = {key: float(np.percentile(values, percentile))
               for key, values in pre_samples.items()}
    post_max = {key: float(np.percentile(values, percentile))
                for key, values in post_samples.items()}
    add_max = {key: float(np.percentile(values, percentile))
               for key, values in add_samples.items()}
    linear_min = {key: float(np.percentile(values, 100.0 - percentile))
                  for key, values in linear_min_samples.items()}
    linear_max = {key: float(np.percentile(values, percentile))
                  for key, values in linear_max_samples.items()}
    return pre_max, post_max, add_max, linear_min, linear_max


class ScaleFlow:
    """Track the producer and required scale of every live C16 DDR plane."""

    def __init__(self, plan: dict, post_max: dict[int, float],
                 add_max: dict[int, float], margin: float) -> None:
        self.plan = plan
        self.post_max = post_max
        self.add_max = add_max
        self.margin = margin
        self.parent: dict[int, int] = {-1: -1}
        self.group_max: dict[int, float] = {-1: 1.0 / 127.0}
        self.owner: dict[int, int] = {}
        self.sources: dict[int, list[int]] = {}
        source = plan["tensors"]["input"]
        for plane in range(source["channels"] // 16):
            self.owner[source["base"] + plane * source["plane_stride"]] = -1

    def find(self, item: int) -> int:
        while self.parent[item] != item:
            item = self.parent[item]
        return item

    def union(self, left: int, right: int, extra: float) -> None:
        a, b = self.find(left), self.find(right)
        if a != b:
            self.parent[b] = a
            self.group_max[a] = max(self.group_max[a], self.group_max[b])
        self.group_max[a] = max(self.group_max[a], extra)

    def scale(self, producer: int) -> float:
        if producer == -1:
            return 1.0 / 127.0
        return self.group_max[self.find(producer)] * self.margin

    def read(self, base: int, stride: int, planes: int) -> list[int]:
        addresses = [base + plane * stride for plane in range(planes)]
        try:
            return [self.owner[address] for address in addresses]
        except KeyError as exc:
            raise ValueError(f"uninitialized DDR plane 0x{exc.args[0]:08x}") from exc

    def write(self, base: int, stride: int, sources: list[int]) -> None:
        for plane, producer in enumerate(sources):
            self.owner[base + plane * stride] = producer

    def build(self) -> None:
        for command in self.plan["commands"]:
            index = command["index"]
            kind = command["kind"]
            if kind == "conv":
                inputs = self.read(command["input_base"],
                                   command["input_plane_stride"],
                                   command["cin_blocks"])
                self.sources[index] = inputs
                self.parent[index] = index
                self.group_max[index] = max(self.post_max[index] / 127.0,
                                            1e-12)
                planes = command["output_blocks"] * 2 - (
                    1 if command["last_c16_only"] else 0)
                self.write(command["output_base"],
                           command["output_plane_stride"],
                           [index] * planes)
            elif kind in ("pool", "up"):
                planes = command["cin_blocks"]
                sources = self.read(command["input_base"],
                                    command["input_plane_stride"], planes)
                self.write(command["output_base"],
                           command["output_plane_stride"], sources)
            elif kind == "add":
                geometry = self.plan["tensors"][f"L{command['layer']}"]
                stride = geometry["plane_stride"]
                planes = command["beat_count"] * 32 // stride
                a = self.read(command["input_base"], stride, planes)
                b = self.read(command["aux_base"], stride, planes)
                for left, right in zip(a, b, strict=True):
                    self.union(left, right,
                               max(self.add_max[index] / 127.0, 1e-12))
                self.write(command["output_base"], stride, a)
        for name in ("D0.logits", "D1.logits", "D2.logits"):
            tensor = self.plan["tensors"][name]
            self.read(tensor["base"], tensor["plane_stride"],
                      tensor["channels"] // 16)


def choose_multiplier(ratio: float) -> tuple[int, int]:
    if not math.isfinite(ratio) or ratio <= 0 or ratio > 32767:
        raise ValueError(f"unrepresentable requantization ratio {ratio}")
    shift = min(47, max(0, math.floor(math.log2(32767.0 / ratio))))
    multiplier = round(ratio * (1 << shift))
    while multiplier > 32767 and shift > 0:
        shift -= 1
        multiplier = round(ratio * (1 << shift))
    if multiplier < 1 or multiplier > 32767:
        raise ValueError(f"unrepresentable requantization ratio {ratio}")
    return multiplier, shift


def make_lut(pre_scale: float, post_scale: float) -> bytes:
    q = np.arange(256, dtype=np.uint8).view(np.int8).astype(np.float64)
    value = q * pre_scale
    silu = value / (1.0 + np.exp(-value))
    mapped = np.clip(np.rint(silu / post_scale), -128, 127).astype(np.int8)
    return mapped.view(np.uint8).tobytes()


def quantize_conv(weight: np.ndarray, bias: np.ndarray,
                  input_scales: np.ndarray, pre_scale: float,
                  output_scale: float, output_zero_point: int,
                  command: dict) -> tuple[bytes, bytes, dict]:
    cout, cin, _, _ = weight.shape
    if len(input_scales) != cin:
        raise ValueError(f"{command['name']}: input scale count mismatch")
    effective = weight.astype(np.float64) * input_scales[None, :, None, None]
    max_abs = np.max(np.abs(effective), axis=(1, 2, 3))
    weight_scale = np.maximum(max_abs / 127.0, 1e-12)
    quantized = np.clip(
        np.rint(effective / weight_scale[:, None, None, None]),
        -127, 127,
    ).astype(np.int8)
    packed_weight = pack_int8(quantized, command)
    bias_int = np.rint(bias.astype(np.float64) / weight_scale)
    if np.any(np.abs(bias_int) > 2147483647):
        raise ValueError(f"{command['name']}: bias overflows INT32")
    parameters = bytearray(command["quant_bytes"])
    max_ratio_error = 0.0
    for channel in range(cout):
        ratio = float(weight_scale[channel] / pre_scale)
        multiplier, shift = choose_multiplier(ratio)
        realized = multiplier / (1 << shift)
        max_ratio_error = max(max_ratio_error,
                              abs(realized / ratio - 1.0))
        block, within = divmod(channel, 32)
        offset = block * 512 + within * 8
        struct.pack_into("<ihBB", parameters, offset,
                         int(bias_int[channel]), multiplier, shift,
                         output_zero_point & 255)
    if command["lut_enable"]:
        lut = make_lut(pre_scale, output_scale)
        for block in range(command["output_blocks"]):
            offset = block * 512 + 256
            parameters[offset:offset + 256] = lut
    metrics = {
        "pre_scale": pre_scale,
        "output_scale": output_scale,
        "output_zero_point": output_zero_point,
        "weight_scale_min": float(weight_scale.min()),
        "weight_scale_max": float(weight_scale.max()),
        "requant_ratio_max_rel_error": max_ratio_error,
    }
    return packed_weight, bytes(parameters), metrics


def verify_first_layer(network: torch.nn.Module, image: Path,
                       weight_bytes: bytes, params: bytes,
                       command: dict, pre_scale: float,
                       output_scale: float) -> dict:
    source = prepare_image(image)
    quant_input = torch.round(source * 127.0).to(torch.float32)
    from yolo_v8n_weight_layout import unpack_int8
    weights = unpack_int8(weight_bytes, command)[:16, :3]
    qweight = torch.from_numpy(weights.copy().astype(np.float32))
    accum = functional.conv2d(quant_input, qweight, stride=2, padding=1)
    values = []
    for channel in range(16):
        bias, multiplier, shift, _zero = struct.unpack_from(
            "<ihBB", params, (channel // 32) * 512 + (channel % 32) * 8)
        integer = accum[:, channel].to(torch.int64) + bias
        product = integer * multiplier
        rounded = (product + ((1 << (shift - 1)) if shift else 0)) >> shift
        values.append(rounded.clamp(-128, 127).to(torch.int64))
    pre = torch.stack(values, dim=1)
    lut = torch.from_numpy(np.frombuffer(params[256:512],
                                          dtype=np.uint8).copy().astype(np.int16))
    lut = torch.where(lut > 127, lut - 256, lut).to(torch.float32)
    quant_output = lut[(pre & 255).to(torch.long)] * output_scale
    with torch.inference_mode():
        reference = network.model[0](source)
    difference = (quant_output - reference).abs()
    return {
        "first_layer_mae": float(difference.mean()),
        "first_layer_max_abs_error": float(difference.max()),
        "first_layer_reference_max": float(reference.abs().max()),
        "first_layer_pre_saturation_fraction": float(
            ((pre == -128) | (pre == 127)).to(torch.float32).mean()),
        "pre_scale": pre_scale,
    }


def export(weights: Path, images: list[Path], output: Path,
           margin: float, percentile: float) -> dict:
    plan = json.loads(PLAN_PATH.read_text(encoding="utf-8"))
    network = YOLO(str(weights)).model.eval().fuse(verbose=False)
    pre_max, post_max, add_max, linear_min, linear_max = collect_ranges(
        network, plan["commands"], images, percentile)
    flow = ScaleFlow(plan, post_max, add_max, margin)
    flow.build()
    image = bytearray(plan["image_bytes"])
    rows = []
    first_weight = first_params = None
    first_pre = first_post = 0.0
    for command in plan["commands"]:
        if command["kind"] != "conv":
            continue
        module = resolve_conv(network, command["model_key"])
        convolution = module.conv if hasattr(module, "conv") else module
        weight = convolution.weight.detach().cpu().numpy()
        bias = convolution.bias.detach().cpu().numpy()
        owner_scales = [flow.scale(owner) for owner in flow.sources[command["index"]]]
        input_scales = np.repeat(owner_scales, 16)[:weight.shape[1]]
        if command["lut_enable"]:
            pre_scale = max(pre_max[command["index"]] / 127.0 * margin, 1e-12)
            post_scale = flow.scale(command["index"])
            zero_point = 0
        else:
            lower = linear_min[command["index"]]
            upper = linear_max[command["index"]]
            center = (lower + upper) / 2.0
            half_range = max((upper - lower) * margin / 2.0, 1e-12)
            pre_scale = 2.0 * half_range / 255.0
            post_scale = pre_scale
            zero_point = int(np.clip(round(-128.0 -
                                           (center - half_range) / pre_scale),
                                     -128, 127))
        packed_weight, params, metrics = quantize_conv(
            weight, bias, input_scales, pre_scale, post_scale,
            zero_point, command)
        weight_offset = command["weight_base"] - plan["model_base"]
        quant_offset = command["quant_base"] - plan["model_base"]
        image[weight_offset:weight_offset + len(packed_weight)] = packed_weight
        image[quant_offset:quant_offset + len(params)] = params
        rows.append({"index": command["index"], "name": command["name"],
                     "input_scales": owner_scales, **metrics})
        if command["index"] == 0:
            first_weight, first_params = packed_weight, params
            first_pre, first_post = pre_scale, post_scale
    if first_weight is None or first_params is None:
        raise AssertionError("first convolution missing")
    first_check = verify_first_layer(network, images[0], first_weight,
                                     first_params, plan["commands"][0],
                                     first_pre, first_post)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(image)
    report = {
        "status": "candidate_not_accuracy_validated",
        "checkpoint_sha256": hashlib.sha256(weights.read_bytes()).hexdigest(),
        "plan_sha256": hashlib.sha256(PLAN_PATH.read_bytes()).hexdigest(),
        "calibration_images": [str(path.resolve()) for path in images],
        "calibration_percentile_per_image_max": percentile,
        "calibration_margin": margin,
        "image_bytes": len(image),
        "image_sha256": hashlib.sha256(image).hexdigest(),
        "image_crc32": f"0x{zlib.crc32(image):08X}",
        "model_base": plan["model_base"],
        "first_layer_check": first_check,
        "convolutions": rows,
    }
    output.with_suffix(".json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--images", type=Path, required=True,
                        help="image directory or one image for a smoke run")
    parser.add_argument("--weights", type=Path, default=DEFAULT_WEIGHTS)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--limit", type=int, default=256)
    parser.add_argument("--margin", type=float, default=1.05)
    parser.add_argument("--percentile", type=float, default=100.0,
                        help="percentile of per-image layer extrema (0..100]")
    args = parser.parse_args()
    if args.limit < 1 or args.margin < 1.0 or not 0 < args.percentile <= 100:
        parser.error("limit > 0, margin >= 1 and 0 < percentile <= 100 required")
    images = calibration_images(args.images, args.limit)
    report = export(args.weights, images, args.output,
                    args.margin, args.percentile)
    print(f"calibrated with {len(images)} images")
    print(f"candidate image: {args.output.resolve()} ({report['image_bytes']} bytes)")
    print(f"first-layer check: {report['first_layer_check']}")
    print("Run layerwise and detection-accuracy checks before board inference.")


if __name__ == "__main__":
    main()
