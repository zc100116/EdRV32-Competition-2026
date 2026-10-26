"""Static traffic/MAC accounting for the read-only legacy 74-command program.

References: SoC spec 8.9; legacy fixed-plan and C16/C32 execution layout.
All generated tables go to build/npu_eval. Python standard library only.
"""

import argparse
import csv
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
YAML = Path('/home/workspace/Projects/EdRV32-Competition-2026/thirdparty/'
            'ultralytics/ultralytics/cfg/models/v8/yolov8.yaml')
BUILD = ROOT / 'build/npu_eval'


def build_plan(source_yaml=YAML):
    spec = importlib.util.spec_from_file_location(
        'legacy_fixed_plan', ROOT / 'legacy/scripts/yolo_v8n_fixed_plan.py')
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    module.SOURCE_YAML = Path(source_yaml)
    return module.build_plan()


def analyze(command):
    c = command
    row = dict(c)
    row.update(real_mac=0, padded_mac=0, ideal_cycles=0, weight_read=0,
               quant_read=0, feature_read=0, output_write=0, operator_read=0,
               operator_write=0, unique_feature_read=0)
    if c['kind'] == 'conv':
        iw, ih, cin = c['input_width'], c['input_height'], c['cin_blocks'] * 16
        ow, oh = c['output_width_pairs'] * 2, c['output_height']
        cout = c['output_blocks'] * 32 - c['last_c16_only'] * 16
        kernel = 3 if c['kernel3'] else 1
        true_cin = 3 if c['index'] == 0 else cin
        row['input_shape'] = f'{iw}x{ih}x{true_cin}'
        row['output_shape'] = f'{ow}x{oh}x{cout}'
        row['real_mac'] = ow * oh * true_cin * cout * kernel**2
        row['padded_mac'] = ow * oh * cin * c['output_blocks'] * 32 * kernel**2
        row['ideal_cycles'] = row['padded_mac'] // 512
        row['weight_read'] = c['weight_bytes']
        row['quant_read'] = c['quant_bytes']
        # For all current 3x3 s2 commands the union includes every input row.
        row['unique_feature_read'] = iw * ih * cin
        row['feature_read'] = row['unique_feature_read'] * c['output_blocks']
        row['output_write'] = ow * oh * cout
    elif c['kind'] == 'add':
        row['input_shape'] = f"{c['beat_count']}x32B (each operand)"
        row['output_shape'] = f"{c['beat_count']}x32B"
        row['operator_read'] = c['beat_count'] * 64
        row['operator_write'] = c['beat_count'] * 32
    else:
        iw, ih, cin = c['input_width'], c['input_height'], c['cin_blocks'] * 16
        scale = 2 if c['kind'] == 'up' else 1
        row['input_shape'] = f'{iw}x{ih}x{cin}'
        row['output_shape'] = f'{iw*scale}x{ih*scale}x{cin}'
        row['operator_read'] = iw * ih * cin
        row['operator_write'] = iw * ih * cin * scale**2
    row['ddr_read'] = sum(row[k] for k in ('weight_read', 'quant_read',
                                         'feature_read', 'operator_read'))
    row['ddr_write'] = row['output_write'] + row['operator_write']
    row['ddr_bytes'] = row['ddr_read'] + row['ddr_write']
    return row


def analysis(source_yaml=YAML):
    return [analyze(c) for c in build_plan(source_yaml)['commands']]


def summarize(rows):
    keys = ('real_mac', 'padded_mac', 'ideal_cycles', 'weight_read', 'quant_read',
            'feature_read', 'unique_feature_read', 'output_write',
            'operator_read', 'operator_write', 'ddr_read', 'ddr_write', 'ddr_bytes')
    result = {k: sum(r[k] for r in rows) for k in keys}
    result['padding_fraction'] = 1 - result['real_mac'] / result['padded_mac']
    result['first_layer_ideal_fraction'] = rows[0]['ideal_cycles'] / result['ideal_cycles']
    result['first_layer_ddr_fraction'] = rows[0]['ddr_bytes'] / result['ddr_bytes']
    result['max_reused_input_bytes'] = max(
        r['unique_feature_read'] for r in rows if r['output_blocks'] > 1)
    result['max_resident_weight_bytes'] = max(r['weight_read'] for r in rows)
    result['layers_over_128KiB_weights'] = sum(r['weight_read'] > 131072 for r in rows)
    result['command_counts'] = {kind: sum(r['kind'] == kind for r in rows)
                                for kind in ('conv', 'add', 'pool', 'up')}
    return result


def write_csv(path, rows):
    with Path(path).open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-yaml', type=Path, default=YAML)
    args = parser.parse_args()
    rows = analysis(args.source_yaml)
    BUILD.mkdir(parents=True, exist_ok=True)
    write_csv(BUILD / 'static.csv', rows)
    summary = summarize(rows)
    (BUILD / 'static_summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
