#!/usr/bin/env python3
# File: rom_survey.py
# Spec: sw/apps/nes/README.md "ROM"; nofrendo nes_rom.c rom_getheader, mmclist.c.
# Description: Classify every ROM under a directory the way the board NES port would see it:
#              iNES header and mapper (nofrendo rules), 2 MiB + header slot fit, then a host run of
#              600 frames that must exit cleanly and end on a non-uniform picture.
# Clock domain: host.
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
NOF = ROOT / 'third_party/nofrendo/components/nofrendo'
HOST = ROOT / 'build/sw/nes-host/nes-host'
SLOT_BYTES = 2 * 1024 * 1024 + 16  # sw/apps/nes/rom.S nes_rom_slot
FRAMES = 600


def supported_mappers():
    text = (NOF / 'nes/mmclist.c').read_text()
    return {int(n) for n in re.findall(r'&map(\d+)_intf', text)}


def header_info(blob):
    """Mirror nofrendo rom_getheader: 8-bit bank counts, dirty-header/DiskDude rules."""
    flags6, flags7 = blob[6], blob[7]
    mapper = flags6 >> 4
    reserved = blob[8:16]
    dirty = any(reserved)
    if not dirty or not (flags7 == ord('D') and reserved == b'iskDude!'):
        mapper |= flags7 & 0xf0
    trainer = 512 if flags6 & 0x04 else 0
    need = 16 + trainer + blob[4] * 16384 + blob[5] * 8192
    return {'mapper': mapper, 'prg_kib': blob[4] * 16, 'chr_kib': blob[5] * 8,
            'trainer': bool(trainer), 'battery': bool(flags6 & 0x02),
            'nes2': (flags7 & 0x0c) == 0x08, 'dirty': dirty, 'need': need}


def picture(frame):
    data = frame.read_bytes()
    pixels = data[data.index(b'255\n') + 4:]
    return len({pixels[i:i + 3] for i in range(0, len(pixels), 3)})


def host_run(rom, work):
    frames = work / 'frames'
    shutil.rmtree(frames, ignore_errors=True)
    frames.mkdir()
    try:
        run = subprocess.run([str(HOST), str(rom), str(FRAMES), str(frames)],
                             capture_output=True, text=True, errors='replace', timeout=60)
    except subprocess.TimeoutExpired:
        return 'timeout', ''
    tail = (run.stdout + run.stderr).strip().splitlines()[-1:] or ['']
    if run.returncode != 0:
        return f'exit {run.returncode}', tail[0]
    colors = max(picture(f) for f in sorted(frames.glob('frame-*.ppm'))[-5:])
    return ('picture' if colors > 1 else 'uniform'), f'colors={colors}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('output', type=Path, help='TSV to write')
    args = parser.parse_args()
    mappers = supported_mappers()
    rows = []
    with tempfile.TemporaryDirectory() as temp:
        work = Path(temp)
        for rom in sorted(p for p in args.directory.rglob('*') if p.is_file()):
            name = str(rom.relative_to(args.directory))
            blob = rom.read_bytes()
            row = {'rom': name, 'bytes': len(blob)}
            if blob[:4] != b'NES\x1a':
                row.update(verdict='not iNES (FDS or other)')
                rows.append(row)
                continue
            info = header_info(blob)
            row.update(info)
            if info['mapper'] not in mappers:
                row['verdict'] = f'mapper {info["mapper"]} unsupported'
            elif len(blob) > SLOT_BYTES:
                row['verdict'] = 'larger than 2 MiB + header slot'
            elif len(blob) < info['need']:
                row['verdict'] = 'file shorter than header sizes'
            else:
                result, detail = host_run(rom, work)
                row.update(verdict=f'host {result}', detail=detail)
            rows.append(row)
    keys = ['rom', 'bytes', 'mapper', 'prg_kib', 'chr_kib', 'trainer', 'battery', 'nes2',
            'dirty', 'verdict', 'detail']
    with args.output.open('w') as out:
        out.write('\t'.join(keys) + '\n')
        for row in rows:
            out.write('\t'.join(str(row.get(k, '')) for k in keys) + '\n')
    counts = {}
    for row in rows:
        counts[row['verdict']] = counts.get(row['verdict'], 0) + 1
    for verdict, count in sorted(counts.items(), key=lambda item: -item[1]):
        print(f'{count:5d}  {verdict}')


if __name__ == '__main__':
    main()
