#!/usr/bin/env python3
"""
Pull a file from Hasselblad X1D over the sutest USB channel.

This uses sutest-daemon command 66 (PullFile). It is read-only on the camera.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys
import time
from pathlib import Path

import usb.backend.libusb1
import usb.core
import usb.util


VID = 0x2756
PID = 0x0002
EP_OUT = 0x02
EP_IN = 0x82
SUTEST_PACKET_LEN = 252
CMD_PULL_FILE = 66


def sutest_crc16(data: bytes | bytearray) -> int:
    crc = 0
    for b in data:
        x = (b ^ (crc >> 8)) & 0xFF
        x = (x ^ (x >> 4)) & 0xFFFF
        crc = (
            (x | ((crc << 8) & 0xFFFF))
            ^ ((x << 12) & 0xFFFF)
            ^ ((x << 5) & 0xFFFF)
        ) & 0xFFFF
    return crc


def make_testd_frame(payload: bytes | bytearray) -> bytes:
    if len(payload) != SUTEST_PACKET_LEN:
        raise ValueError(f"sutest payload must be {SUTEST_PACKET_LEN} bytes")
    return bytes([0x0A, 0x00, 0x08, 0x05, 0xFC]) + bytes(payload)


def make_pull_request(remote_path: str, packet_delay_ms: int) -> bytes:
    payload = bytearray(SUTEST_PACKET_LEN)
    struct.pack_into("<I", payload, 0x00, CMD_PULL_FILE)
    struct.pack_into("<I", payload, 0x10, packet_delay_ms)
    encoded = remote_path.encode("utf-8")
    if len(encoded) >= 232:
        raise ValueError("remote path is too long for sutest payload")
    payload[0x14 : 0x14 + len(encoded)] = encoded
    struct.pack_into("<I", payload, 0x0C, sutest_crc16(payload[0x14 : 0x14 + 232]))
    return make_testd_frame(payload)


def make_pull_action(action: int) -> bytes:
    payload = bytearray(SUTEST_PACKET_LEN)
    struct.pack_into("<I", payload, 0x00, CMD_PULL_FILE)
    struct.pack_into("<I", payload, 0x14, action)
    struct.pack_into("<I", payload, 0x0C, sutest_crc16(payload[0x14 : 0x14 + 232]))
    return make_testd_frame(payload)


def open_camera(libusb_path: str | None):
    if libusb_path:
        backend = usb.backend.libusb1.get_backend(find_library=lambda _: libusb_path)
    else:
        backend = usb.backend.libusb1.get_backend()
    if backend is None:
        raise RuntimeError("libusb backend not available; pass --libusb on macOS if needed")

    dev = usb.core.find(idVendor=VID, idProduct=PID, backend=backend)
    if dev is None:
        raise RuntimeError("X1D USB device 2756:0002 not found")
    try:
        dev.set_configuration(1)
    except Exception:
        pass
    try:
        usb.util.claim_interface(dev, 0)
    except Exception:
        pass
    return dev


def drain(dev) -> None:
    while True:
        try:
            dev.read(EP_IN, 512, timeout=80)
        except usb.core.USBTimeoutError:
            return


def read_sutest_payload(dev, timeout_ms: int = 1000) -> bytes:
    raw = bytes(dev.read(EP_IN, 512, timeout=timeout_ms))
    if len(raw) < 5:
        raise RuntimeError(f"short USB frame: {raw.hex()}")
    signal = raw[0] | (raw[1] << 8)
    src = raw[2]
    dst = raw[3]
    length = raw[4]
    if signal != 0x0009 or src != 5 or dst != 8 or length != SUTEST_PACKET_LEN:
        raise RuntimeError(
            f"unexpected frame header: signal=0x{signal:04x} src={src} dst={dst} len={length}"
        )
    return raw[5 : 5 + length]


def parse_common(payload: bytes) -> tuple[int, int, int, int, int]:
    return struct.unpack_from("<IIIII", payload, 0)


def parse_header(payload: bytes) -> tuple[int, int, bytes]:
    cmd, status, _unused, _crc, _result = parse_common(payload)
    if cmd != CMD_PULL_FILE:
        raise RuntimeError(f"unexpected command in response: {cmd}")
    if status != 4:
        raise RuntimeError(f"PullFile header failed or invalid response status: {status}")

    header = payload[0x14 : 0x14 + 80]
    full_chunks = struct.unpack_from("<I", header, 0x04)[0]
    packet_size = struct.unpack_from("<I", header, 0x08)[0]
    remainder = struct.unpack_from("<I", header, 0x0C)[0]
    expected_md5 = bytes(struct.unpack_from("<I", header, 0x10 + i * 4)[0] & 0xFF for i in range(16))
    if packet_size != 232:
        raise RuntimeError(f"unexpected PullFile packet size: {packet_size}")
    total_size = full_chunks * packet_size + remainder
    return total_size, packet_size, expected_md5


def pull_file(dev, remote_path: str, packet_delay_ms: int, timeout_s: float) -> tuple[bytes, bytes]:
    drain(dev)
    dev.write(EP_OUT, make_pull_request(remote_path, packet_delay_ms), timeout=1000)
    header_payload = read_sutest_payload(dev, timeout_ms=1500)
    total_size, packet_size, expected_md5 = parse_header(header_payload)

    dev.write(EP_OUT, make_pull_action(1), timeout=1000)
    deadline = time.time() + timeout_s
    data = bytearray()
    while len(data) < total_size:
        if time.time() > deadline:
            raise TimeoutError(f"timed out after receiving {len(data)} of {total_size} bytes")
        payload = read_sutest_payload(dev, timeout_ms=1000)
        cmd, _status, _unused, _crc, _result = parse_common(payload)
        if cmd != CMD_PULL_FILE:
            continue
        remaining = total_size - len(data)
        data.extend(payload[0x14 : 0x14 + min(packet_size, remaining)])
    return bytes(data[:total_size]), expected_md5


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("remote_path", help="absolute path on the camera")
    parser.add_argument("output", type=Path, help="local output path")
    parser.add_argument("--delay-ms", type=int, default=0, help="camera packet delay")
    parser.add_argument("--timeout", type=float, default=30.0, help="overall transfer timeout")
    parser.add_argument(
        "--libusb",
        default="/opt/homebrew/lib/libusb-1.0.dylib",
        help="libusb dylib path; use empty string for default discovery",
    )
    args = parser.parse_args(argv)

    libusb_path = args.libusb or None
    dev = open_camera(libusb_path)
    data, expected_md5 = pull_file(dev, args.remote_path, args.delay_ms, args.timeout)
    actual_md5 = hashlib.md5(data).digest()
    if expected_md5 and expected_md5 != actual_md5:
        raise RuntimeError(
            "MD5 mismatch: expected "
            + expected_md5.hex()
            + " got "
            + actual_md5.hex()
        )
    args.output.write_bytes(data)
    print(f"wrote {len(data)} bytes to {args.output}")
    print(f"md5 {actual_md5.hex()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
