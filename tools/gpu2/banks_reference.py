#!/usr/bin/env python3
"""G-P04 old-data read trace; independent software stores, no RTL introspection."""
import random
from pathlib import Path


def packed(values, width):
    return sum(value << (width*i) for i, value in enumerate(values))


def trace(destination):
    rng = random.Random(20261128)
    rf = [None]*512
    constants = [None]*128
    program = [None]*1024
    banks = [[None]*16 for _ in range(72)]
    # Captured output is one cycle behind the enabled RAM result.
    memory_results = [None]*78
    outputs = [None]*78
    collisions = 0
    rows = []
    for cycle in range(3072):
        init = cycle < 1024
        rfwa = cycle % 384
        cwa = cycle % 128
        pwa = cycle % 1024
        swa = [cycle % 16]*72 if init else [rng.randrange(16) for _ in range(72)]
        swen = [1]*72 if init or cycle % 4 != 0 else [rng.randrange(2) for _ in range(72)]
        sren = [1]*72 if cycle % 5 != 0 else [rng.randrange(2) for _ in range(72)]
        # Same-bank different-address read/write plus read/write exact collisions.
        sra = [swa[i] if cycle % 3 == 0 else (swa[i]+1) % 16 for i in range(72)]
        rfwe, cwe, pwe = (1, 1, 1) if init else (cycle % 3 != 0, cycle % 4 != 0,
                                                               cycle % 5 != 0)
        rfren = [1, 1, 1] if init or cycle % 7 else [rng.randrange(2) for _ in range(3)]
        cren = [1, 1] if init or cycle % 7 else [rng.randrange(2) for _ in range(2)]
        pren = 1 if init or cycle % 7 else rng.randrange(2)
        rfra = [rfwa, (rfwa+1) % 384, (rfwa+383) % 384]
        cra = [cwa, (cwa+1) % 128]
        pra = pwa if cycle % 2 else (pwa+1) % 1024
        rfdata = rng.getrandbits(128)
        cdata = rng.getrandbits(128)
        pdata = rng.getrandbits(160)
        sdata = [rng.getrandbits(92) for _ in range(72)]
        outputs = memory_results[:]
        requests = [(rf, rfra[i], rfren[i]) for i in range(3)]
        requests += [(constants, cra[i], cren[i]) for i in range(2)]
        requests += [(program, pra, pren)]
        requests += [(banks[i], sra[i], sren[i]) for i in range(72)]
        for i, (store, address, enabled) in enumerate(requests):
            if enabled:
                memory_results[i] = store[address]
        if rfwe:
            rf[rfwa] = rfdata
        if cwe:
            constants[cwa] = cdata
        if pwe:
            program[pwa] = pdata
        for i in range(72):
            if swen[i]:
                banks[i][swa[i]] = sdata[i]
                collisions += bool(sren[i] and sra[i] == swa[i])
        inputs = [int(rfwe), rfwa, rfdata, packed(rfren, 1), packed(rfra, 9),
                  int(cwe), cwa, cdata, packed(cren, 1), packed(cra, 7),
                  int(pwe), pwa, pdata, pren, pra, packed(swen, 1), packed(swa, 4),
                  packed(sdata, 92), packed(sren, 1), packed(sra, 4)]
        masks = packed([value is not None for value in outputs], 1)
        expected = [packed([value or 0 for value in outputs[:3]], 128),
                    packed([value or 0 for value in outputs[3:5]], 128), outputs[5] or 0,
                    packed([value or 0 for value in outputs[6:]], 92)]
        rows.append(inputs+[masks]+expected)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(''.join(' '.join(f'{x:x}' for x in row)+'\n' for row in rows))
    print(f'banks trace={len(rows)} clocks, scratch=72x16x92, old-data collisions={collisions}')


if __name__ == '__main__':
    trace(Path('build/gpu2/banks/trace.txt'))
