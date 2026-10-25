"""Compare a packed candidate model with the fused YOLOv8n, command by command.

This is a host arithmetic check. It uses the ROM's packed weights, quantization
records, saturation, LUTs and C16 memory aliases. CPU convolution uses float32
for integer operands; the largest observed accumulator is reported so any loss
of integer precision remains visible.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct

import numpy as np
import torch
import torch.nn.functional as functional
from ultralytics import YOLO
from ultralytics.utils.nms import non_max_suppression

from yolo_v8n_checkpoint_audit import resolve_conv
from yolo_v8n_quantize import PLAN_PATH, DEFAULT_WEIGHTS, DEFAULT_OUTPUT, prepare_image
from yolo_v8n_weight_layout import unpack_int8


def references(network: torch.nn.Module, source: torch.Tensor,
               commands: list[dict]) -> tuple[dict[int, torch.Tensor], torch.Tensor]:
    result = {}
    hooks = []
    pool_indices = iter(command["index"] for command in commands
                        if command["kind"] == "pool")

    def save(index: int):
        def capture(_module, _inputs, output):
            result[index] = output.detach()
        return capture

    def save_pool(_module, _inputs, output):
        result[next(pool_indices)] = output.detach()

    for command in commands:
        index, kind = command["index"], command["kind"]
        if kind == "conv":
            hooks.append(resolve_conv(network, command["model_key"])
                         .register_forward_hook(save(index)))
        elif kind == "add":
            name = command["name"]
            layer = int(name.split(".")[0][1:])
            bottleneck = int(name.split(".")[1][1:])
            hooks.append(network.model[layer].m[bottleneck]
                         .register_forward_hook(save(index)))
        elif kind == "up":
            hooks.append(network.model[command["layer"]]
                         .register_forward_hook(save(index)))
    hooks.append(network.model[9].m.register_forward_hook(save_pool))
    try:
        with torch.inference_mode():
            prediction = network(source)[0]
    finally:
        for hook in hooks:
            hook.remove()
    if len(result) != len(commands):
        raise AssertionError(f"reference count {len(result)} != {len(commands)}")
    return result, prediction


def check(weights: Path, candidate: Path, image_path: Path,
          network: torch.nn.Module | None = None,
          all_detections: bool = False,
          dump_logits: Path | None = None) -> dict:
    plan = json.loads(PLAN_PATH.read_text(encoding="utf-8"))
    report = json.loads(candidate.with_suffix(".json").read_text(encoding="utf-8"))
    image = candidate.read_bytes()
    if len(image) != plan["image_bytes"]:
        raise ValueError("candidate image size differs from ROM plan")
    rows = {row["index"]: row for row in report["convolutions"]}
    if network is None:
        network = YOLO(str(weights)).model.eval().fuse(verbose=False)
    source = prepare_image(image_path)
    target, float_prediction = references(network, source, plan["commands"])
    store: dict[int, tuple[torch.Tensor, float, int]] = {}
    input_info = plan["tensors"]["input"]
    input_q = torch.zeros((1, 16, 384, 640), dtype=torch.int8)
    input_q[:, :3] = torch.round(source * 127.0).to(torch.int8)
    store[input_info["base"]] = input_q, 1.0 / 127.0, 0
    layer_checks = []
    maximum_accum = 0

    def read(command: dict, base_key: str, count: int,
             stride: int) -> tuple[torch.Tensor, list[float]]:
        planes = [store[command[base_key] + plane * stride]
                  for plane in range(count)]
        return torch.cat([plane[0] for plane in planes], dim=1), [
            plane[1] for plane in planes]

    def write(command: dict, value: torch.Tensor, scale: float,
              stride: int, zero_point: int = 0) -> None:
        assert value.shape[1] % 16 == 0
        for plane in range(value.shape[1] // 16):
            store[command["output_base"] + plane * stride] = (
                value[:, plane * 16:(plane + 1) * 16].to(torch.int8),
                scale, zero_point)

    for command in plan["commands"]:
        index, kind = command["index"], command["kind"]
        if kind == "conv":
            input_q, input_scales = read(
                command, "input_base", command["cin_blocks"],
                command["input_plane_stride"])
            expected = rows[index]["input_scales"]
            if not np.allclose(input_scales, expected, atol=1e-12, rtol=1e-6):
                raise AssertionError(f"{command['name']}: input scale alias mismatch")
            w_start = command["weight_base"] - plan["model_base"]
            w_end = w_start + command["weight_bytes"]
            weight = unpack_int8(image[w_start:w_end], command)
            actual_cout = command["output_blocks"] * 32 - (
                16 if command["last_c16_only"] else 0)
            qweight = torch.from_numpy(weight[:actual_cout].copy()).to(torch.float32)
            accumulated = functional.conv2d(
                input_q.to(torch.float32), qweight,
                stride=2 if command["stride2"] else 1,
                padding=1 if command["kernel3"] else 0)
            maximum_accum = max(maximum_accum, int(accumulated.abs().max()))
            params_start = command["quant_base"] - plan["model_base"]
            params = image[params_start:params_start + command["quant_bytes"]]
            records = [struct.unpack_from("<ihBB", params,
                       (channel // 32) * 512 + (channel % 32) * 8)
                       for channel in range(actual_cout)]
            bias, multiplier, shift, zero = (
                torch.tensor([record[field] for record in records],
                             dtype=torch.int64).view(1, actual_cout, 1, 1)
                for field in range(4))
            zero = torch.where(zero > 127, zero - 256, zero)
            rounded = torch.bitwise_right_shift(
                (accumulated.round().to(torch.int64) + bias) * multiplier +
                torch.where(shift > 0, torch.bitwise_left_shift(
                    torch.ones_like(shift), (shift - 1).clamp(min=0)), 0),
                shift)
            pre = (rounded + zero).clamp(-128, 127).to(torch.int16)
            if command["lut_enable"]:
                mapped = []
                for block in range(command["output_blocks"]):
                    lut = np.frombuffer(params, dtype=np.int8,
                                        count=256, offset=block * 512 + 256)
                    table = torch.from_numpy(lut.copy())
                    part = pre[:, block * 32:(block + 1) * 32]
                    mapped.append(table[(part & 255).to(torch.long)])
                output_q = torch.cat(mapped, dim=1)
            else:
                output_q = pre.to(torch.int8)
            write(command, output_q, rows[index]["output_scale"],
                  command["output_plane_stride"],
                  rows[index]["output_zero_point"])
        elif kind == "add":
            geometry = plan["tensors"][f"L{command['layer']}"]
            stride = geometry["plane_stride"]
            count = command["beat_count"] * 32 // stride
            a, ascale = read(command, "input_base", count, stride)
            b, bscale = read(command, "aux_base", count, stride)
            if not np.allclose(ascale, bscale, atol=1e-12, rtol=1e-6):
                raise AssertionError(f"{command['name']}: residual scale mismatch")
            output_q = (a.to(torch.int16) + b.to(torch.int16)).clamp(-128, 127)
            write(command, output_q, ascale[0], stride)
        elif kind in ("pool", "up"):
            source_q, scales = read(command, "input_base",
                                    command["cin_blocks"],
                                    command["input_plane_stride"])
            if len(set(scales)) != 1:
                raise AssertionError(f"{command['name']}: mixed scales")
            if kind == "pool":
                output_q = functional.max_pool2d(
                    source_q.to(torch.float32), 5, 1, 2).to(torch.int8)
            else:
                output_q = source_q.repeat_interleave(2, 2)
                output_q = output_q.repeat_interleave(2, 3)
            write(command, output_q, scales[0],
                  command["output_plane_stride"])
        else:
            raise ValueError(kind)

        reference = target[index]
        if reference.shape[1] != output_q.shape[1]:
            raise AssertionError(f"{command['name']}: output shape mismatch")
        output_scale = store[command["output_base"]][1]
        output_zero = store[command["output_base"]][2]
        difference = ((output_q.to(torch.float32) - output_zero) *
                      output_scale - reference).abs()
        layer_checks.append({"index": index, "name": command["name"],
                             "kind": kind, "mae": float(difference.mean()),
                             "max_abs_error": float(difference.max()),
                             "reference_max": float(reference.abs().max()),
                             "saturation_fraction": float(
                                 ((output_q == -128) | (output_q == 127))
                                 .to(torch.float32).mean())})
    def head_tensor(name: str) -> torch.Tensor:
        info = plan["tensors"][name]
        planes = [store[info["base"] + plane * info["plane_stride"]]
                  for plane in range(info["channels"] // 16)]
        return torch.cat([(q.to(torch.float32) - zero) * scale
                          for q, scale, zero in planes], dim=1)

    boxes = torch.cat([head_tensor(f"D{scale}.box").flatten(2)
                       for scale in range(3)], dim=2)
    scores = torch.cat([head_tensor(f"D{scale}.cls").flatten(2)
                        for scale in range(3)], dim=2)
    feats = [target[index] for index in (45, 50, 55)]
    with torch.inference_mode():
        quant_prediction = network.model[22]._inference(
            {"boxes": boxes, "scores": scores, "feats": feats})
    score_error = (quant_prediction[:, 4:] - float_prediction[:, 4:]).abs()

    def detections(prediction: torch.Tensor, threshold: float,
                   limit: int | None) -> list[dict]:
        rows = non_max_suppression(prediction.clone(), conf_thres=threshold,
                                   iou_thres=0.7, nc=80)[0]
        if limit is not None:
            rows = rows[:limit]
        return [{"class": int(row[5]), "confidence": float(row[4]),
                 "xyxy": [float(value) for value in row[:4]]}
                for row in rows]

    result = {"image": str(image_path.resolve()),
            "max_abs_accumulator": maximum_accum,
            "float32_exact_integer_limit": 1 << 24,
            "layer_checks": layer_checks,
            "score_mae": float(score_error.mean()),
            "score_max_abs_error": float(score_error.max()),
            "quant_candidates_at_025": int(
                (quant_prediction[:, 4:].amax(dim=1) >= 0.25).sum()),
            "float_detections_top20": detections(float_prediction, 0.25, 20),
            "quant_detections_top20": detections(quant_prediction, 0.25, 20)}
    if all_detections:
        result["float_detections"] = detections(float_prediction, 0.001, None)
        result["quant_detections"] = detections(quant_prediction, 0.001, None)
    result["float_detection_count_top20"] = len(result["float_detections_top20"])
    result["quant_detection_count_top20"] = len(result["quant_detections_top20"])
    if dump_logits is not None:
        names = [f"D{scale}.{branch}" for scale in range(3)
                 for branch in ("box", "cls")]
        first = min(plan["tensors"][name]["base"] for name in names)
        end = max(plan["tensors"][name]["base"] +
                  plan["tensors"][name]["bytes"] for name in names)
        physical = bytearray(end - first)
        for name in names:
            info = plan["tensors"][name]
            for plane in range(info["channels"] // 16):
                address = info["base"] + plane * info["plane_stride"]
                q, _scale, _zero = store[address]
                packed = q[0].permute(1, 2, 0).contiguous().numpy().tobytes()
                offset = address - first
                physical[offset:offset + len(packed)] = packed
        dump_logits.parent.mkdir(parents=True, exist_ok=True)
        dump_logits.write_bytes(physical)
        result["dump_logits_base"] = first
        result["dump_logits_bytes"] = len(physical)
        result["dump_logits_file"] = str(dump_logits.resolve())
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--weights", type=Path, default=DEFAULT_WEIGHTS)
    parser.add_argument("--candidate", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--dump-logits", type=Path)
    args = parser.parse_args()
    result = check(args.weights, args.candidate, args.image,
                   dump_logits=args.dump_logits)
    output = args.candidate.with_name(
        args.candidate.stem + "_validation_" + args.image.stem + ".json")
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    for row in result["layer_checks"]:
        print(f"{row['index']:02d} {row['name']:<22} "
              f"MAE={row['mae']:.4f} max={row['max_abs_error']:.3f} "
              f"sat={row['saturation_fraction']:.4f}")
    print(f"max accumulator: {result['max_abs_accumulator']}")
    print(f"score MAE: {result['score_mae']:.6f}")
    print("float top detections:", result["float_detections_top20"][:5])
    print("INT8 top detections:", result["quant_detections_top20"][:5])
    print(f"validation report: {output}")


if __name__ == "__main__":
    main()
