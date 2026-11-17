#!/usr/bin/env python3
"""build.py — showcase R5-8/9: build one offline demo HTML. Host clock."""
import base64
import io
import json
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent


def encoded(path):
    return base64.b64encode(path.read_bytes()).decode('ascii')


def main():
    scenes = json.loads((ROOT / 'media.json').read_text())
    clips = {clip['id']: clip for clip in json.loads((ROOT / 'clips.json').read_text())}
    for scene in scenes:
        for item in scene['items']:
            if item['id'] in clips:
                item.update(clips[item['id']])
            path = Path(item['path'])
            item['data'] = encoded(path)
        thumbnail = Image.open(scene['thumbnail_path']).convert('RGB')
        stream = io.BytesIO()
        ImageOps.fit(thumbnail, (400, 225)).save(stream, format='JPEG', quality=75)
        thumbnail_data = base64.b64encode(stream.getvalue()).decode()
        scene['thumbnail'] = 'data:image/jpeg;base64,' + thumbnail_data
    farm = (ROOT.parent / 'farm-sim/farm-sim.html').read_text()
    data = json.dumps(scenes, ensure_ascii=False).replace('</', '<\\/')
    farm = json.dumps(farm, ensure_ascii=False).replace('</', '<\\/')
    html = (ROOT / 'src/template.html').read_text()
    html = html.replace('/*STYLES*/', (ROOT / 'src/style.css').read_text())
    html = html.replace('/*SCRIPT*/', (ROOT / 'src/app.js').read_text())
    html = html.replace('/*DATA*/', data).replace('/*FARM*/', farm)
    output = ROOT / 'demo-kit.html'
    output.write_text(html)
    print(f'{output}: {output.stat().st_size} bytes')


if __name__ == '__main__':
    main()
