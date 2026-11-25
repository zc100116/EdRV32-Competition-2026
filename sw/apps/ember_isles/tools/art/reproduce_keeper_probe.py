#!/usr/bin/env python3
"""reproduce_keeper_probe.py — requested initial keeper capacity checkpoint.
Host, standard library. Rebuild saved sources, then compare I8/I4 exact GPU packages.
This does not start image generation or alter the game.
"""
import json

from coast_assets import ASSETS, normalize
from probe_keeper_budget import main


for item in json.loads((ASSETS / 'keeper-budget-sources.json').read_text()):
    sheet = json.loads((ASSETS / item['metadata']).read_text())
    sprites, measured = normalize(sheet)
    print(sheet['name'], [(b['id'], b['size']) for b in measured['bounds']], flush=True)
main()
