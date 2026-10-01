#!/usr/bin/env python3
"""
Run a short shell command on the camera through sutest-daemon command 52.

This is powerful; use only for explicit, scoped tests.
"""

from __future__ import annotations

import argparse
import struct
import sys

from x1d_usb_pull_file import (
    EP_OUT,
    SUTEST_PACKET_LEN,
    drain,
    make_testd_frame,
    open_camera,
    read_sutest_payload,
    sutest_crc16,
)


CMD_OS_SYSTEM = 52


def make_exec_request(command: str) -> bytes:
    payload = bytearray(SUTEST_PACKET_LEN)
    struct.pack_into("<I", payload, 0x00, CMD_OS_SYSTEM)
    encoded = command.encode("utf-8")
    if len(encoded) >= 232:
        raise ValueError("command is too long for sutest payload")
    payload[0x14 : 0x14 + len(encoded)] = encoded
    struct.pack_into("<I", payload, 0x0C, sutest_crc16(payload[0x14 : 0x14 + 232]))
    return make_testd_frame(payload)


def run_command(dev, command: str, timeout_ms: int) -> bytes:
    drain(dev)
    dev.write(EP_OUT, make_exec_request(command), timeout=1000)
    payload = read_sutest_payload(dev, timeout_ms=timeout_ms)
    cmd, status, _unused, _crc, result = struct.unpack_from("<IIIII", payload, 0)
    if cmd != CMD_OS_SYSTEM:
        raise RuntimeError(f"unexpected command in response: {cmd}")
    if status != 0:
        raise RuntimeError(f"OsSystemCommand failed or invalid response status: {status}")
    if result != 0:
        raise RuntimeError(f"shell command returned non-zero result: {result}")
    return bytes(payload[0x14 :]).split(b"\0", 1)[0]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", help="short shell command to execute on the camera")
    parser.add_argument("--timeout-ms", type=int, default=3000)
    parser.add_argument(
        "--libusb",
        default="/opt/homebrew/lib/libusb-1.0.dylib",
        help="libusb dylib path; use empty string for default discovery",
    )
    args = parser.parse_args(argv)

    dev = open_camera(args.libusb or None)
    output = run_command(dev, args.command, args.timeout_ms)
    sys.stdout.buffer.write(output)
    if output and not output.endswith(b"\n"):
        sys.stdout.buffer.write(b"\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
