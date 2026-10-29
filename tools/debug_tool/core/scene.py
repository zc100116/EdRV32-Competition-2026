"""scene.py — B2 design 3.4/3.6 configurable UART menu; host clock domain.

Command strings remain unset until the B2-4 firmware menu is finalized.
The GUI, HTTP and terminal clients share this mapping and serial session.
"""

import json
from pathlib import Path

CONFIG = Path(__file__).resolve().parents[1] / 'scenes.json'


class SceneControl:
    def __init__(self, engine):
        self.engine = engine

    def mapping(self):
        return json.loads(CONFIG.read_text(encoding='utf-8'))

    def send(self, name, rate=100):
        if not 10 <= rate <= 1000:
            raise ValueError('sampling rate must be 10..1000 Hz')
        item = self.mapping()[name]
        if item['command'] is None:
            raise ValueError(f'{name}: configure command in scenes.json after B2-4 is finalized')
        return self.engine.send(item['command'].format(rate=rate), item['ending'])
