"""tl04_compare.py — npu-testplan TL-04; npu-spec 2.1–2.5, 4.1–4.3.

Compare all compiled descriptors and decoded detections with copied legacy arithmetic.
Clock domain: offline host tool.
"""

import argparse
import importlib
import json
from pathlib import Path
import shutil
import sys
from time import perf_counter

import numpy as np
import torch
from ultralytics import YOLO

import compile_yolo
from fixed_plan import build_plan, convolution_descriptor
from format import pack_weights
import quantize
from ref import npu_ref

ROOT = Path(__file__).resolve().parents[2]
DATA = Path.home() / ".local/share/edrv32/npu"
CANDIDATE = "yolov8n_int8_coco96_p95"
DEFAULT_IMAGES = [DATA / f"coco128/images/train2017/{number:012d}.jpg"
                  for number in (9, 529, 650)]


def stage_legacy(source, destination):
    """Run copies in build/, adding an observation hook and extracting postprocessing."""
    scripts = destination / "scripts"
    scripts.mkdir(parents=True, exist_ok=True)
    for name in ("validate_quant", "quantize", "checkpoint_audit", "weight_layout", "eval_quant"):
        filename = f"yolo_v8n_{name}.py"
        shutil.copyfile(ROOT / "legacy/scripts" / filename, scripts / filename)
    for relative in ("out/board/yolo_v8n_fixed_plan.json",
                     f"out/models/{CANDIDATE}.bin", f"out/models/{CANDIDATE}.json"):
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / relative, target)

    path = scripts / "yolo_v8n_validate_quant.py"
    original = path.read_text()
    observed = original.replace(
        "dump_logits: Path | None = None) -> dict:",
        "dump_logits: Path | None = None, after_command=None) -> dict:")
    observed = observed.replace(
        "        reference = target[index]\n",
        "        if after_command is not None:\n"
        "            after_command(index, output_q.to(torch.int8))\n\n"
        "        reference = target[index]\n")
    # Use the old DFL/decode/NMS statements verbatim, with reference heads as input.
    decode = original[original.index("    boxes = torch.cat("):
                      original.index("    score_error = ")]
    nms = original[original.index("    def detections("):
                   original.index("    result = {\"image\"")]
    helper = ("\n\ndef tl04_detections(network, head_tensor, target):\n" + decode + nms +
              "    return {\n"
              "        'quant_detections': detections(quant_prediction, 0.001, None),\n"
              "        'quant_detections_top20': detections(quant_prediction, 0.25, 20),\n"
              "    }\n")
    path.write_text(observed + helper)
    sys.path.insert(0, str(scripts))
    return importlib.import_module("yolo_v8n_validate_quant")


def compare_values(label, reference, legacy):
    """Report exact differences in logical coordinates, including shape failures."""
    if reference.shape != legacy.shape:
        print(f"FAIL {label} shape_ref={reference.shape} shape_legacy={legacy.shape}")
        return False
    different = reference != legacy
    count = int(np.count_nonzero(different))
    message = f"{'FAIL' if count else 'PASS'} {label} shape={reference.shape} diff={count}"
    if count:
        first = tuple(int(value) for value in np.argwhere(different)[0])
        message += f" first={first} ref={reference[first]} legacy={legacy[first]}"
    print(message, flush=True)
    return count == 0


def repack_candidate(legacy, legacy_plan, plan, cache):
    """Use one quantized model for both paths; translate only spec 4.2/4.3 layout."""
    candidate = legacy.PLAN_PATH.parents[1] / f"models/{CANDIDATE}.bin"
    old_model = candidate.read_bytes()
    report = json.loads(candidate.with_suffix(".json").read_text())
    old_commands = {command["name"]: command for command in legacy_plan["commands"]}
    model = bytearray(plan["image_bytes"])
    for command in plan["commands"]:
        if command["kind"] != "conv":
            continue
        old = old_commands[command["name"]]
        offset = old["weight_base"] - legacy_plan["model_base"]
        weights = legacy.unpack_int8(old_model[offset:offset + old["weight_bytes"]], old)
        cout = command["output_blocks"] * 32 - (16 if command["last_c16_only"] else 0)
        cin = 3 if command["layer"] == 0 else command["cin_blocks"] * 16
        packed = pack_weights(weights[:cout, :cin], convolution_descriptor(command))
        offset = command["weight_base"] - plan["model_base"]
        model[offset:offset + len(packed)] = packed
        offset = old["quant_base"] - legacy_plan["model_base"]
        parameters = bytearray(old_model[offset:offset + old["quant_bytes"]])
        # Old zero point is per channel at byte 7; spec 4.2 reserves that byte.
        # compile_yolo encodes the unchanged output_zero_point in the descriptor.
        for channel in range(cout):
            parameters[(channel // 32) * 512 + (channel % 32) * 8 + 7] = 0
        offset = command["quant_base"] - plan["model_base"]
        model[offset:offset + len(parameters)] = parameters
    cache.mkdir(parents=True, exist_ok=True)
    (cache / "model.bin").write_bytes(model)
    (cache / "quantization.json").write_text(json.dumps({
        "calibration_images": report["calibration_images"],
        "percentile": report["calibration_percentile_per_image_max"],
        "margin": report["calibration_margin"],
        "convolutions": report["convolutions"],
    }, indent=2) + "\n")


def detection_values(rows):
    # Preserve legacy NMS order: compare coordinates, confidence and class exactly.
    return np.array([row["xyxy"] + [row["confidence"], row["class"]]
                     for row in rows], dtype=np.float64).reshape(-1, 6)


def compare_image(image, directory, legacy, legacy_plan, plan, network):
    started = perf_counter()
    print(f"IMAGE {image}", flush=True)
    # Invoke the existing compiler with this run's translated quantization cache.
    command_line = sys.argv
    sys.argv = ["compile_yolo.py", "--image", str(image), "--out", str(directory)]
    compile_yolo.main()
    sys.argv = command_line
    rows = {row["name"]: row for row in json.loads(
        (quantize.CACHE / "quantization.json").read_text())["convolutions"]}
    compiled = perf_counter()
    memory = npu_ref.run_case(directory, per_descriptor=True)
    executed = perf_counter()
    registers = dict(line.split() for line in (directory / "regs.txt").read_text().splitlines())
    bases = tuple(int(registers[name + "_BASE"], 16)
                  for name in ("MODEL", "WORK", "INPUT", "OUTPUT"))
    desc_base = int(registers["DESC_BASE"], 16)
    desc_count = int(registers["DESC_COUNT"], 16)
    commands = legacy_plan["commands"]
    destinations = {}
    for position, command in enumerate(commands):
        if command["kind"] == "add":
            continue
        following = commands[position + 1:position + 2]
        # Spec 2.3: a fused CONV is observed after the old separate residual add.
        observed = following[0] if following and following[0]["kind"] == "add" else command
        destinations[command["name"]] = observed
    encoded = [command for command in plan["commands"] if command["kind"] != "add"]
    assert desc_count == len(encoded) == 68, f"TL-04 descriptor coverage: {desc_count}"
    comparisons = {destinations[command["name"]]["index"]: (index, command)
                   for index, command in enumerate(encoded)}
    results = []
    features = {}
    snapshot_directory = directory / "legacy"
    snapshot_directory.mkdir(exist_ok=True)

    def after_command(index, output):
        value = output[0].numpy().copy()
        np.save(snapshot_directory / f"cmd_{index}.npy", value)
        if index in (45, 50, 55):
            features[index] = output.clone()
        if index in comparisons:
            desc_index, command = comparisons[index]
            desc = npu_ref.Descriptor.read(memory, desc_base + 64 * desc_index)
            snapshot = npu_ref.Memory()
            snapshot.load_hex(directory / f"ref_desc_{desc_index}.hex")
            actual = npu_ref.read_feature(
                snapshot, desc.address(bases, "output"), desc.output_shape,
                desc.output_channels // 16, desc.words[4]).transpose(2, 0, 1)
            label = f"desc={desc_index:02d} cmd={index:02d} {command['name']}"
            if commands[index]["kind"] == "add":
                label += " +add"
            results.append(compare_values(label, actual, value))

    candidate = legacy.PLAN_PATH.parents[1] / f"models/{CANDIDATE}.bin"
    result = legacy.check(DATA / "yolov8n.pt", candidate, image,
                          network=network, all_detections=True, after_command=after_command)
    simulated = perf_counter()
    assert len(results) == 68, f"TL-04 compared {len(results)} descriptors"

    def head_tensor(name):
        info = plan["tensors"][name]
        value = npu_ref.read_feature(
            memory, info["base"], (info["height"], info["width"]),
            info["channels"] // 16, info["plane_stride"])
        q = torch.from_numpy(value.transpose(2, 0, 1).copy()).unsqueeze(0)
        quant = rows[name + ".out"]
        return (q.to(torch.float32) - quant["output_zero_point"]) * quant["output_scale"]

    decoded = legacy.tl04_detections(network, head_tensor, features)
    detection_results = []
    for name in ("quant_detections", "quant_detections_top20"):
        detection_results.append(compare_values(
            name + " (xyxy,confidence,class)", detection_values(decoded[name]),
            detection_values(result[name])))
    elapsed = perf_counter() - started
    print(f"SUMMARY {image.name} layers={sum(results)}/68 "
          f"detections={len(decoded['quant_detections'])} "
          f"detection_checks={sum(detection_results)}/2 "
          f"max_abs_accumulator={result['max_abs_accumulator']} "
          f"compile_s={compiled - started:.3f} ref_s={executed - compiled:.3f} "
          f"legacy_s={simulated - executed:.3f} elapsed_s={elapsed:.3f}", flush=True)
    return all(results) and all(detection_results)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--legacy-root", type=Path, required=True,
                        help="old Linux run containing out/board and out/models")
    parser.add_argument("--images", type=Path, nargs="+", default=DEFAULT_IMAGES)
    parser.add_argument("--out", type=Path, default=ROOT / "build/npu/tl04")
    args = parser.parse_args()
    started = perf_counter()
    legacy = stage_legacy(args.legacy_root.resolve(), args.out.resolve() / "legacy")
    legacy_plan = json.loads(legacy.PLAN_PATH.read_text())
    plan = build_plan()
    quantize.CACHE = args.out.resolve() / "quantized"
    repack_candidate(legacy, legacy_plan, plan, quantize.CACHE)
    network = YOLO(str(DATA / "yolov8n.pt")).model.eval().fuse(verbose=False)
    results = []
    for image in args.images:
        directory = args.out / image.stem
        results.append(compare_image(image, directory, legacy, legacy_plan, plan,
                                     network))
    print(f"TL-04 {'PASS' if all(results) else 'FAIL'} images={len(results)} "
          f"elapsed_s={perf_counter() - started:.3f}")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
