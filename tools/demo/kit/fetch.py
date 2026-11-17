#!/usr/bin/env python3
"""fetch.py — showcase R5-9: public video download and offline transcode. Host clock."""
import json
import shutil
from pathlib import Path
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parent
BUILD = Path('build/demo-kit')
FFMPEG = Path.home() / '.local/opt/video/bin/ffmpeg'


def main():
    (BUILD / 'downloads').mkdir(parents=True, exist_ok=True)
    (BUILD / 'clips').mkdir(parents=True, exist_ok=True)
    clips = json.loads((ROOT / 'clips.json').read_text())
    for clip in clips:
        if sys.argv[1:] and clip['id'] not in sys.argv[1:]:
            continue
        source = BUILD / 'downloads' / (clip['id'] + '.source')
        request = urllib.request.Request(clip['file_url'],
                                         headers={'User-Agent': 'demo-media-fetch/1.0'})
        with urllib.request.urlopen(request) as response, source.open('wb') as output:
            shutil.copyfileobj(response, output)
        # Fade the tail into the head, then start at the head's final frame.
        duration = clip['playback_duration']
        middle = duration - 1
        filters = (
            'scale=1280:720:force_original_aspect_ratio=decrease,'
            'pad=1280:720:(ow-iw)/2:(oh-ih)/2,'
            f"setpts=PTS/{clip['speed']},fps=25,setsar=1,split=3[a][b][c];"
            f'[a]trim=start=0.5:end={duration-0.5},setpts=PTS-STARTPTS,fps=25[mid];'
            '[b]trim=end=0.5,setpts=PTS-STARTPTS,fps=25[head];'
            f'[c]trim=start={duration-0.5},setpts=PTS-STARTPTS,fps=25[tail];'
            '[tail][head]xfade=transition=fade:duration=0.5:offset=0[seam];'
            '[mid][seam]concat=n=2:v=1:a=0[out]')
        subprocess.run([str(FFMPEG), '-y', '-ss', str(clip['start']), '-t', str(clip['duration']),
                        '-i', str(source), '-filter_complex', filters, '-map', '[out]',
                        '-an', '-c:v', 'libx264', '-profile:v', 'main', '-pix_fmt', 'yuv420p',
                        '-b:v', '1300k', '-maxrate', '1700k', '-bufsize', '2600k',
                        '-threads', '2', '-filter_complex_threads', '1',
                        '-movflags', '+faststart', str(BUILD / 'clips' / (clip['id']+'.mp4'))],
                       check=True)
        print(clip['id'], 'transcoded', middle + .5, 'seconds', flush=True)


if __name__ == '__main__':
    main()
