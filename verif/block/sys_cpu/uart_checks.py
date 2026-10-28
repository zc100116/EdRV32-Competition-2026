# File: uart_checks.py
# Spec: sys-subsys-testplan 3.6 SC-01/SC-08; edrv32-soc-spec 7.5.
# Description: Compare boot fields and monitor menu/CoreMark UART output against the SC contract.
# Clock domain: none (host checker).
"""Field checks for the S-W2 UART key contract in sw/apps/monitor/README.md."""
import json
from pathlib import Path
import re

REGIONS = {region['name']: region for region in json.loads(
    (Path(__file__).resolve().parents[3] / 'rtl/include/soc_address_map.json').read_text()
)['regions']}

MENU = 'Menu: 1=CoreMark 2=Peripheral tests 3=System info'
LOGO = (
    '  EEEEEEE   DDDD    RRRRR   V   V   3333   2222 ',
    '  E         D   D   R   R   V   V      3      2 ',
    '  EEEE      D   D   RRRRR    V V    3333   2222 ',
    '  E         D   D   R  R     V V       3   2    ',
    '  EEEEEEE   DDDD    R    R    V     3333   2222 ',
)
HPM_NAMES = (
    'dual retire', 'single retire', 'zero retire', 'branches', 'pair RAW',
    'pair structural', 'pair slot1 type', 'pair missing slot1', 'load-use stall',
    'divide stall', 'device wait', 'frontend empty', 'I-cache miss', 'D-cache miss',
    'dirty writeback', 'branch mispredict',
)
ISA = 'rv32im_zicsr_zifencei'


def values(text, key):
    return re.findall('^' + re.escape(key) + r': ([^\n]*)$', text, re.MULTILINE)


def expect(text, key, expected):
    expected = expected if isinstance(expected, list) else [expected]
    actual = values(text, key)
    if actual != expected:
        raise RuntimeError(f'UART {key}: expected {expected!r}, actual {actual!r}')


def formatted(text, key, pattern, count=1):
    actual = values(text, key)
    if len(actual) != count or not all(re.fullmatch(pattern, value) for value in actual):
        raise RuntimeError(f'UART {key}: expected {count} values matching {pattern!r}, '
                           f'actual {actual!r}')


def check_system_info(text, commit, compiler):
    # sys-subsys-spec 2.9/4.6 and SoC 6.1/8.2: fixed SC hardware configuration.
    expected = {
        'CHIP_ID': '0xed320001', 'CLK_SYS_HZ': '150000000',
        'ROM bytes': '16384', 'SRAM bytes': str(int(REGIONS['SRAM']['size'], 0)),
        'I-cache bytes': '8192', 'D-cache bytes': '8192', 'MEM_READY': '1',
        'Boot mode': 'SRAM app', 'Build commit': commit, 'Compiler version': compiler,
    }
    for key, value in expected.items():
        expect(text, key, value)


def check_boot(text, commit, compiler):
    logo = '\n'.join(LOGO) + '\n'
    if logo not in text:
        raise RuntimeError('UART boot logo: expected all five EdRV32 ASCII rows')
    if '  EdRV32 Boot ROM - UART 115200 8N1\n' not in text:
        raise RuntimeError('UART boot logo: missing EdRV32 boot title')
    check_system_info(text, commit, compiler)


def check_build_fields(text, compiler):
    expect(text, 'Compiler version', compiler)
    expect(text, 'ISA', ISA)
    formatted(text, 'Compiler flags', r'.+')
    flags = values(text, 'Compiler flags')[0].split()
    for flag in ('-march=' + ISA, '-mabi=ilp32', '-O2'):
        if flag not in flags:
            raise RuntimeError(f'UART Compiler flags: missing {flag!r}')


def check_monitor(text, commit, compiler):
    sections = text.split(MENU + '\n')
    if len(sections) != 4:
        raise RuntimeError(f'UART monitor: expected initial menu and two returns, '
                           f'actual menus={len(sections)-1}')
    expect(sections[0], 'Monitor', 'EdRV32')
    info, coremark = sections[1:3]
    check_system_info(info, commit, compiler)
    check_build_fields(info, compiler)
    for key, value in {
        'Cache ways': '2', 'Cache line bytes': '32',
        'D-cache policy': 'write-back, write-allocate',
        'Cache configuration source': 'cache-spec 2.1 constants',
        'HPM event 00': 'disabled', 'HPM events 17-31': 'reserved, no counting',
        'System info result': 'PASS',
    }.items():
        expect(info, key, value)
    for event, name in enumerate(HPM_NAMES, 1):
        expect(info, f'HPM {event:02} {name}', str(event))
        formatted(coremark, f'HPM {event:02} {name}', r'0|[1-9][0-9]*')
    for key, value in {
        'Iterations default': '10',
        'Iterations input': 'decimal 1..4294967295 then Enter; Enter selects default',
        'Iterations': '1', 'HPM rounds': '2',
        'HPM round': ['1', '2'], 'HPM first event': ['1', '9'],
        'HPM last event': ['8', '16'], 'CRC result': ['PASS', 'PASS'],
        'Score status': 'short diagnostic run (<10 s); not a publishable CoreMark score',
        'CoreMark result': 'PASS',
    }.items():
        expect(coremark, key, value)
    for field, crc in {'seed': 'e9f5', 'list': 'e714', 'matrix': '1fd7',
                       'state': '8e3a'}.items():
        expect(coremark, 'CRC ' + field, ['0x0000' + crc] * 2)
        expect(coremark, 'CRC ' + field + ' result', ['PASS'] * 2)
    formatted(coremark, 'CRC final', r'0x[0-9a-f]{8}', count=2)
    for key in ('HPM round cycles', 'HPM round instructions'):
        formatted(coremark, key, r'[1-9][0-9]*', count=2)
    for key in ('Cycles', 'Instructions'):
        formatted(coremark, key, r'[1-9][0-9]*')
    for key in ('Iterations/Sec', 'CoreMark/MHz', 'IPC', 'Dual retire ratio',
                'Load-use stall ratio', 'Divide stall ratio', 'Device wait ratio',
                'Frontend empty ratio', 'Branch mispredict rate',
                'I-cache MPKI', 'D-cache MPKI'):
        formatted(coremark, key, r'[0-9]+\.[0-9]{3}|N/A \(denominator=0\)')
    check_build_fields(coremark, compiler)
