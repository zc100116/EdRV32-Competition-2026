# File: link_wait.py
# Spec: T-ETH-LINKWAIT, host tools; no clock domain.
# Wait for the interface owning the selected IPv4 address before sending.
"""Shared local-interface readiness polling for BIOS and application traffic."""
import ctypes
from pathlib import Path
import socket
import sys
import time

LINK_TIMEOUT = 10.0
LINK_POLL_INTERVAL = 0.1


class _SocketAddress(ctypes.Structure):
    _fields_ = [('address', ctypes.c_void_p), ('length', ctypes.c_int)]


class _Unicast(ctypes.Structure):
    pass


_Unicast._fields_ = [
    ('alignment', ctypes.c_uint64), ('next', ctypes.POINTER(_Unicast)),
    ('socket', _SocketAddress), ('prefix_origin', ctypes.c_int),
    ('suffix_origin', ctypes.c_int), ('dad_state', ctypes.c_int),
]


class _Adapter(ctypes.Structure):
    pass


# Only the documented prefix through OperStatus is needed; ULONG is always 32 bits.
_Adapter._fields_ = [
    ('alignment', ctypes.c_uint64), ('next', ctypes.POINTER(_Adapter)),
    ('adapter_name', ctypes.c_char_p), ('unicast', ctypes.POINTER(_Unicast)),
    ('anycast', ctypes.c_void_p), ('multicast', ctypes.c_void_p),
    ('dns_server', ctypes.c_void_p), ('dns_suffix', ctypes.c_wchar_p),
    ('description', ctypes.c_wchar_p), ('friendly_name', ctypes.c_wchar_p),
    ('physical_address', ctypes.c_ubyte * 8), ('physical_length', ctypes.c_uint32),
    ('flags', ctypes.c_uint32), ('mtu', ctypes.c_uint32),
    ('if_type', ctypes.c_uint32), ('oper_status', ctypes.c_int),
]


def _windows_state(local_ip):
    api = ctypes.windll.iphlpapi.GetAdaptersAddresses
    api.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p,
                    ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    api.restype = ctypes.c_uint32
    size = ctypes.c_uint32()
    # The first call requests the required buffer size, not an operation retry.
    result = api(socket.AF_INET, 0, None, None, ctypes.byref(size))
    if result != 111:  # ERROR_BUFFER_OVERFLOW is the size-query result.
        raise OSError(f'GetAdaptersAddresses size for {local_ip}: error {result}')
    buffer = ctypes.create_string_buffer(size.value)
    result = api(socket.AF_INET, 0, None, buffer, ctypes.byref(size))
    if result:
        raise OSError(f'GetAdaptersAddresses for {local_ip}: error {result}')
    adapter = ctypes.cast(buffer, ctypes.POINTER(_Adapter))
    source = socket.inet_aton(local_ip)
    oper_names = ('Unknown', 'Up', 'Down', 'Testing', 'Unknown',
                  'Dormant', 'NotPresent', 'LowerLayerDown')
    dad_names = ('Invalid', 'Tentative', 'Duplicate', 'Deprecated', 'Preferred')
    while adapter:
        item = adapter.contents
        unicast = item.unicast
        while unicast:
            address = unicast.contents
            # AF_INET sockaddr_in: family, port, then the four IPv4 bytes.
            if ctypes.string_at(address.socket.address + 4, 4) == source:
                oper, dad = item.oper_status, address.dad_state
                state = f'OperStatus={oper_names[oper]}, DAD={dad_names[dad]}'
                return item.friendly_name, oper == 1 and dad == 4, state
            unicast = address.next
        adapter = item.next
    return None, False, 'IPv4 address not assigned'


class _Ifaddrs(ctypes.Structure):
    pass


_Ifaddrs._fields_ = [
    ('next', ctypes.POINTER(_Ifaddrs)), ('name', ctypes.c_char_p),
    ('flags', ctypes.c_uint), ('address', ctypes.c_void_p),
    ('netmask', ctypes.c_void_p), ('destination', ctypes.c_void_p),
    ('data', ctypes.c_void_p),
]


def _linux_state(local_ip):
    libc = ctypes.CDLL(None, use_errno=True)
    libc.getifaddrs.argtypes = [ctypes.POINTER(ctypes.POINTER(_Ifaddrs))]
    libc.getifaddrs.restype = ctypes.c_int
    libc.freeifaddrs.argtypes = [ctypes.POINTER(_Ifaddrs)]
    addresses = ctypes.POINTER(_Ifaddrs)()
    if libc.getifaddrs(ctypes.byref(addresses)):
        raise OSError(ctypes.get_errno(), f'getifaddrs for {local_ip}')
    source = socket.inet_aton(local_ip)
    try:
        current = addresses
        while current:
            item = current.contents
            if (item.address and ctypes.c_ushort.from_address(item.address).value == socket.AF_INET
                    and ctypes.string_at(item.address + 4, 4) == source):
                name = item.name.decode()
                state = (Path('/sys/class/net') / name / 'operstate').read_text().strip()
                return name, state == 'up', f'operstate={state}'
            current = item.next
    finally:
        libc.freeifaddrs(addresses)
    return None, False, 'IPv4 address not assigned'


def wait_for_link(local_ip):
    """Return (interface name, elapsed seconds); poll for at most ten seconds."""
    if sys.platform == 'win32':
        read_state = _windows_state
    elif sys.platform == 'linux':
        read_state = _linux_state
    else:
        raise OSError(f'Interface readiness unsupported on {sys.platform}')
    started = time.monotonic()
    name = '<未找到>'
    while True:
        observed_name, ready, state = read_state(local_ip)
        if observed_name is not None:
            name = observed_name
        elapsed = time.monotonic() - started
        if ready:
            return name, elapsed
        if elapsed >= LINK_TIMEOUT:
            raise OSError(f'等待网卡 {name} 就绪超时：local_ip={local_ip}，'
                          f'最后状态 {state}，用时 {elapsed:.1f} s')
        time.sleep(min(LINK_POLL_INTERVAL, LINK_TIMEOUT - elapsed))
