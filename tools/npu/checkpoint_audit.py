"""checkpoint_audit.py — NPU spec 2.5: check the fused pretrained graph.

Check all 63 convolution shapes and the three feature and detection scales.
Clock domain: offline host tool.
"""

import torch


def resolve_conv(network: torch.nn.Module, model_key: str) -> torch.nn.Module:
    parts = model_key.split(".")
    module = network.model[int(parts[1])]
    for part in parts[2:]:
        module = module[int(part)] if part.isdigit() else getattr(module, part)
    return module


def audit(network: torch.nn.Module, plan: dict) -> dict:
    if len(network.model) != 23:
        raise ValueError("checkpoint is not the expected 23-module YOLOv8n")

    conv_rows = []
    for command in plan["commands"]:
        if command["kind"] != "conv":
            continue
        module = resolve_conv(network, command["model_key"])
        convolution = module.conv if hasattr(module, "conv") else module
        weight = convolution.weight
        cout, cin, ky, kx = map(int, weight.shape)
        expected_cout = (command["output_blocks"] - 1) * 32 + (
            16 if command["last_c16_only"] else 32)
        expected_cin = command["cin_blocks"] * 16
        expected_kernel = 3 if command["kernel3"] else 1
        if (cout, ky, kx) != (expected_cout, expected_kernel,
                             expected_kernel):
            raise ValueError(
                f"{command['name']} output/kernel: {tuple(weight.shape)} "
                f"vs C{expected_cout}/K{expected_kernel}"
            )
        if cin != expected_cin and not (
            command["layer"] == 0 and cin == 3 and expected_cin == 16
        ):
            raise ValueError(
                f"{command['name']} input: C{cin} vs C{expected_cin}"
            )
        if tuple(convolution.bias.shape) != (cout,):
            raise ValueError(f"{command['name']} BN fusion left no bias")
        conv_rows.append({
            "index": command["index"], "name": command["name"],
            "model_key": command["model_key"],
            "weight_shape": [cout, cin, ky, kx],
            "physical_bytes": command["weight_bytes"],
        })
    observed_shapes = {}
    hooks = []
    for layer_id in (15, 18, 21):
        def capture(_module, _inputs, output, *, key=layer_id):
            observed_shapes[str(key)] = list(output.shape)
        hooks.append(network.model[layer_id].register_forward_hook(capture))
    detect = network.model[22]
    for scale in range(3):
        for branch, module in (("box", detect.cv2[scale]),
                               ("cls", detect.cv3[scale])):
            key = f"22.{branch}{scale}"
            def capture_head(_module, _inputs, output, *, name=key):
                observed_shapes[name] = list(output.shape)
            hooks.append(module.register_forward_hook(capture_head))
    with torch.inference_mode():
        network(torch.zeros(1, 3, 384, 640))
    for hook in hooks:
        hook.remove()
    expected_shapes = {
        "15": [1, 64, 48, 80],
        "18": [1, 128, 24, 40],
        "21": [1, 256, 12, 20],
        "22.box0": [1, 64, 48, 80],
        "22.cls0": [1, 80, 48, 80],
        "22.box1": [1, 64, 24, 40],
        "22.cls1": [1, 80, 24, 40],
        "22.box2": [1, 64, 12, 20],
        "22.cls2": [1, 80, 12, 20],
    }
    if observed_shapes != expected_shapes:
        raise ValueError(
            f"checkpoint output shapes differ: {observed_shapes}"
        )
    return {"conv_count": len(conv_rows), "output_shapes": observed_shapes}


def main() -> None:
    from fixed_plan import build_plan
    from quantize import DEFAULT_WEIGHTS
    from ultralytics import YOLO

    network = YOLO(str(DEFAULT_WEIGHTS)).model.eval().fuse(verbose=False)
    print(audit(network, build_plan()))


if __name__ == "__main__":
    main()
