#!/usr/bin/env python3
"""Generate the approved 1024x32 dual-read SFU ROM image (one physical DRM)."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.gpu2.sfu import RCP, RSQ, LOG, INV, EXP
out = ROOT / 'build/gpu2_sfu'
out.mkdir(parents=True, exist_ok=True)
words = RCP + RSQ + LOG + INV + EXP
(out / 'rom.hex').write_text(''.join(f'{word:08x}\n' for word in words + (0,)*(1024-len(words))))
print('SFU ROM: 290 meaningful 32-bit words, 1024 physical rows')
