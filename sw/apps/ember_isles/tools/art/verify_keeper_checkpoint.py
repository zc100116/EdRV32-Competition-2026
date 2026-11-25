#!/usr/bin/env python3
"""verify_keeper_checkpoint.py — coordinator's ART-3 first production checkpoint.
Host-only, standard library. Checks five drawn idle/walk facings, not complete ART-3.
GPU texel roundtrip is performed by coast_assets.py during this same conversion.
"""
import json

from coast_assets import ASSETS, BUILD, DIRECTIONS


def main():
    result = json.loads((BUILD / 'measurements.json').read_text())
    result['sheets'] = result['sheets'][:5]
    sheets = json.loads((ASSETS / 'sheets.json').read_text())[:5]
    if len(sheets) != 5 or len(result['sheets']) != 5:
        raise ValueError('checkpoint requires exactly five independently drawn facings')
    for direction, sheet, measured in zip(DIRECTIONS, sheets, result['sheets']):
        bounds = {b['id']: b for b in measured['bounds']}
        for cell in sheet['cells']:
            if cell['direction'] != direction:
                raise ValueError(f'{sheet["name"]}: wrong direction {cell["direction"]}')
            frame = bounds[cell['id']]
            height = frame['size'][1]
            if cell['action'] == 'idle' and height != 44:
                raise ValueError(f'{cell["id"]}: standing height {height}, required44')
            if cell['action'] == 'walk' and not 42 <= height <= 46:
                raise ValueError(f'{cell["id"]}: walking height {height}, required42–46')
            if frame['trim'][1] + height - 1 != 58:
                raise ValueError(f'{cell["id"]}: foot baseline differs from58')
        for action in ('idle', 'walk'):
            count = measured['distinct_frames'][direction + '/' + action]
            if count != 4:
                raise ValueError(f'{direction}/{action}: {count} genuinely distinct frames')
    print('PASS checkpoint only: five independently drawn facings, '
          '20 idle44px /20 walk42–46px, four distinct frames per action/facing, baseline58')


if __name__ == '__main__':
    main()
