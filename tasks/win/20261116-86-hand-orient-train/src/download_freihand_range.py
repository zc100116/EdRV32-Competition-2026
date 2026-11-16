#!/usr/bin/env python3
"""download_freihand_range.py: supplement 2, official ZIP member Range downloads.
Downloads only green-screen RGB, masks and the three required JSON files.
Clock domain: not applicable (server dataset download).
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
import argparse
import io
from pathlib import Path
import struct
import threading
import time
import zipfile
import zlib
import requests

URL = 'https://lmb.informatik.uni-freiburg.de/data/freihand/FreiHAND_pub_v2.zip'


def fetch_range(session, start, end):
    with session.get(URL, headers={'Range': f'bytes={start}-{end}'},
                     timeout=60, stream=True) as response:
        response.raise_for_status()
        if response.status_code != 206:
            raise RuntimeError(f'Official server ignored HTTP Range {start}-{end}')
        return response.content


def get_range(start, end):
    ranges = [(offset, min(offset + 1048575, end)) for offset in range(start, end + 1, 1048576)]
    workers = ThreadPoolExecutor(max_workers=16)
    futures = {workers.submit(fetch_range, requests, *part): index
               for index, part in enumerate(ranges)}
    parts = [None] * len(ranges)
    try:
        for future in as_completed(futures):
            parts[futures[future]] = future.result()
    finally:
        workers.shutdown(wait=False, cancel_futures=True)
    return b''.join(parts)


class RangeFile(io.RawIOBase):
    def __init__(self):
        response = requests.head(URL, timeout=60)
        response.raise_for_status()
        self.size = int(response.headers['Content-Length'])
        self.position = 0

    def seek(self, offset, whence=0):
        if whence == 0:
            self.position = offset
        elif whence == 1:
            self.position += offset
        else:
            self.position = self.size + offset
        return self.position

    def tell(self):
        return self.position

    def read(self, size=-1):
        end = self.size if size == -1 else min(self.position + size, self.size)
        data = get_range(self.position, end - 1)
        self.position = end
        return data


def catalog():
    with zipfile.ZipFile(RangeFile()) as archive:
        infos = sorted(archive.infolist(), key=lambda item: item.header_offset)
        central = archive.start_dir
    jobs = []
    for index, info in enumerate(infos):
        path = Path(info.filename)
        rgb = path.parent.as_posix() == 'training/rgb' and int(path.stem) < 32560
        mask = path.parent.as_posix() == 'training/mask' and not info.is_dir()
        annotation = info.filename in ['training_xyz.json', 'training_K.json',
                                       'training_scale.json']
        if rgb or mask or annotation:
            end = infos[index + 1].header_offset if index + 1 < len(infos) else central
            jobs.append((info, end))
    return jobs


def write_member(info, data, output):
    header = struct.unpack_from('<4s5H3I2H', data)
    offset = 30 + header[-2] + header[-1]
    compressed = data[offset:offset + info.compress_size]
    if info.compress_type == zipfile.ZIP_DEFLATED:
        content = zlib.decompress(compressed, -15)
    elif info.compress_type == zipfile.ZIP_STORED:
        content = compressed
    else:
        raise ValueError(f'Unexpected ZIP compression: {info.filename}')
    (output / info.filename).write_bytes(content)


def download_annotations(output):
    for info, end in catalog():
        if info.filename in ['training_xyz.json', 'training_K.json', 'training_scale.json']:
            data = get_range(info.header_offset, end - 1)
            write_member(info, data, output)
            print('ANNOTATION_COMPLETE', info.filename, len(data), flush=True)


def download(output, resume):
    started = time.time()
    jobs = catalog()
    output.mkdir(parents=True, exist_ok=True)
    for directory in ['training/rgb', 'training/mask']:
        (output / directory).mkdir(parents=True, exist_ok=True)
    pending = [(info, end) for info, end in jobs
               if not resume or not (output / info.filename).is_file()]
    print('required_members', len(jobs), 'members_to_download', len(pending), flush=True)

    connections = threading.local()

    def connect():
        connections.session = requests.Session()

    def extract(job):
        info, end = job
        if end - info.header_offset > 1048576:
            data = get_range(info.header_offset, end - 1)
        else:
            data = fetch_range(connections.session, info.header_offset, end - 1)
        write_member(info, data, output)
        return len(data)

    total = 0
    workers = ThreadPoolExecutor(max_workers=16, initializer=connect)
    futures = [workers.submit(extract, job) for job in pending]
    try:
        for count, future in enumerate(as_completed(futures), 1):
            total += future.result()
            if count % 1000 == 0:
                print('members', count, 'of', len(pending), 'bytes', total,
                      'seconds', round(time.time() - started, 2), flush=True)
    finally:
        workers.shutdown(wait=False, cancel_futures=True)
    missing = [info.filename for info, _ in jobs if not (output / info.filename).is_file()]
    if missing:
        raise RuntimeError(f'Missing required ZIP members: {missing}')
    print('DOWNLOAD_COMPLETE', len(jobs), total, time.time() - started, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    download(args.output, args.resume)
