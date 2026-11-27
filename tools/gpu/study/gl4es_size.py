#!/usr/bin/env python3
"""Count pinned gl4es C/header sources for the GPU v2 design study.
Host-only streaming tar reader; no extracted files or runtime size inference.
"""
import json
import tarfile
import urllib.request

COMMIT = '8b1a3da5d2331d0f88b70be25963182d46eed857'
url = f'https://api.github.com/repos/ptitSeb/gl4es/tarball/{COMMIT}'
files = lines = size = 0
with urllib.request.urlopen(url) as response:
    with tarfile.open(fileobj=response, mode='r|gz') as archive:
        for member in archive:
            if member.isfile() and '/src/' in member.name and member.name.endswith(('.c', '.h')):
                files += 1
                lines += archive.extractfile(member).read().count(b'\n')
                size += member.size
print(json.dumps(dict(commit=COMMIT, files=files, lines=lines, source_bytes=size), indent=2))
