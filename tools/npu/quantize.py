"""quantize.py — NPU spec 2.3, 2.5, 4.2–4.3: calibrate and quantize YOLOv8n.

Use the first 96 sorted COCO128 images, percentile 95, margin 1.05.
Preserve per-plane concat scales and shared residual scales from the old flow.
Clock domain: offline host tool.
"""

import json
import math
from pathlib import Path
import re
import struct

import cv2
import numpy as np
import torch
from ultralytics import YOLO

from checkpoint_audit import audit, resolve_conv
from fixed_plan import convolution_descriptor
from format import model_with_post_tables, pack_weights

ROOT = Path(__file__).resolve().parents[2]
DATA = Path.home() / ".local/share/edrv32/npu"
DEFAULT_WEIGHTS = DATA / "yolov8n.pt"
CACHE = ROOT / "build/npu/quantized"
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
        return [self.owner[address] for address in addresses]

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
    effective = weight.astype(np.float64) * input_scales[None, :, None, None]
    max_abs = np.max(np.abs(effective), axis=(1, 2, 3))
    weight_scale = np.maximum(max_abs / 127.0, 1e-12)
    quantized = np.clip(
        np.rint(effective / weight_scale[:, None, None, None]),
        -127, 127,
    ).astype(np.int8)
    packed_weight = pack_weights(quantized, convolution_descriptor(command))
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
                         0)
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


def calibrate(plan: dict) -> tuple[bytes, list[dict]]:
    # Calibration results depend on the torch thread count (float reduction order);
    # one thread makes every rebuild of the model image byte-identical.
    torch.set_num_threads(1)
    images = calibration_images(DATA / "coco128/images/train2017", 96)
    network = YOLO(str(DEFAULT_WEIGHTS)).model.eval().fuse(verbose=False)
    checked = audit(network, plan)
    print(f"checkpoint: {checked['conv_count']} fused convolutions, output shapes checked")
    pre_max, post_max, add_max, linear_min, linear_max = collect_ranges(
        network, plan["commands"], images, 95.0)
    flow = ScaleFlow(plan, post_max, add_max, 1.05)
    flow.build()
    image = bytearray(plan["image_bytes"])
    rows = []
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
            pre_scale = max(pre_max[command["index"]] / 127.0 * 1.05, 1e-12)
            post_scale = flow.scale(command["index"])
            zero_point = 0
        else:
            lower = linear_min[command["index"]]
            upper = linear_max[command["index"]]
            center = (lower + upper) / 2.0
            half_range = max((upper - lower) * 1.05 / 2.0, 1e-12)
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
    image = model_with_post_tables(image, rows, plan)
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE / "model.bin").write_bytes(image)
    (CACHE / "quantization.json").write_text(json.dumps({
        "calibration_images": [str(path) for path in images],
        "percentile": 95, "margin": 1.05,
        "torch_version": torch.__version__, "convolutions": rows,
    }, indent=2) + "\n", encoding="utf-8")
    return bytes(image), rows


def load_quantized(plan: dict) -> tuple[bytes, list[dict]]:
    if (CACHE / "model.bin").exists():
        rows = json.loads((CACHE / "quantization.json").read_text())["convolutions"]
        image = model_with_post_tables((CACHE / "model.bin").read_bytes(), rows, plan)
        (CACHE / "model.bin").write_bytes(image)
        return image, rows
    return calibrate(plan)
