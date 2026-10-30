#!/usr/bin/env python3
# File: check_mapper19.py
# Spec: Task T-NES3; patches/mapper19-ciram.patch.
# Description: Run every supplied Namco 163 ROM, including the 13 CIRAM crashes.
# Clock domain: host.
from pathlib import Path
import importlib.util
import tempfile

root = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('rom_survey', root / 'tools/nes/rom_survey.py')
survey = importlib.util.module_from_spec(spec)
spec.loader.exec_module(survey)
count = 0
with tempfile.TemporaryDirectory(dir=root / 'build/nes') as temp:
    for rom in sorted((root / 'third_party/nes').rglob('*')):
        if not rom.is_file():
            continue
        blob = rom.read_bytes()
        if blob[:4] == b'NES\x1a' and survey.header_info(blob)['mapper'] == 19:
            result, detail = survey.host_run(rom, Path(temp))
            assert result in ('picture', 'uniform'), f'{rom}: {result}: {detail}'
            count += 1
assert count == 15, f'expected 15 supplied mapper 19 ROMs, got {count}'
print(f'PASS mapper 19: {count} ROMs, no CIRAM crashes')
