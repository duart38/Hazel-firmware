#!/usr/bin/env python3
"""
Interactive USB shell for the Hasselblad X1D sutest channel.

Default mode uses command 65 (HblShell). Each input line is executed in a
temporary /bin/sh and output is streamed back through sutest notify packets, so
long stdout/stderr is not limited to the small command-52 result payload.
"""

from __future__ import annotations

import argparse
import os
import select
import shlex
import struct
import sys
import time

import usb.core

from x1d_usb_exec import CMD_OS_SYSTEM, make_exec_request
from x1d_usb_pull_file import (
    EP_OUT,
    SUTEST_PACKET_LEN,
    drain,
    make_testd_frame,
    open_camera,
    read_sutest_payload,
    sutest_crc16,
)


CMD_HBL_SHELL = 65
INTERRUPT_ACTIONS = (("sigint", "SIGINT"),)


def make_hbl_shell_request(command: str, notify_delay: int, request: int = 0) -> bytes:
    return make_hbl_shell_request_bytes(command.encode("utf-8"), notify_delay, request)


def make_hbl_shell_request_bytes(data: bytes, notify_delay: int, request: int = 0) -> bytes:
    payload = bytearray(SUTEST_PACKET_LEN)
    struct.pack_into("<I", payload, 0x00, CMD_HBL_SHELL)
    struct.pack_into("<I", payload, 0x04, request)
    struct.pack_into("<I", payload, 0x10, notify_delay)
    if len(data) >= 232:
        raise ValueError("command is too long for HblShell payload")
    payload[0x14 : 0x14 + len(data)] = data
    struct.pack_into("<I", payload, 0x0C, sutest_crc16(payload[0x14 : 0x14 + 232]))
    return make_testd_frame(payload)


def run_command(dev, command: str, timeout_ms: int) -> tuple[int, int, bytes]:
    drain(dev)
    dev.write(EP_OUT, make_exec_request(command), timeout=1000)
    payload = read_sutest_payload(dev, timeout_ms=timeout_ms)
    cmd, status, _unused, _crc, result = struct.unpack_from("<IIIII", payload, 0)
    if cmd != CMD_OS_SYSTEM:
        raise RuntimeError(f"unexpected command in response: {cmd}")
    output = bytes(payload[0x14:]).split(b"\0", 1)[0]
    return status, result, output


def stream_hbl_shell(
    dev,
    command: str,
    timeout_ms: int,
    notify_delay: int,
    on_chunk=None,
    on_interrupt=None,
    forward_stdin: bool = False,
) -> tuple[int, bytes]:
    drain(dev)
    dev.write(EP_OUT, make_hbl_shell_request(command, notify_delay), timeout=1000)

    output = bytearray()
    last_status = 0
    interrupt_count = 0
    poll_timeout_ms = 100 if forward_stdin else min(timeout_ms, 1000)
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    while True:
        if not forward_stdin and time.monotonic() > deadline:
            raise usb.core.USBTimeoutError("HblShell response timed out")
        forward_local_stdin(dev, notify_delay, forward_stdin)
        try:
            payload = read_sutest_payload(dev, timeout_ms=poll_timeout_ms)
        except KeyboardInterrupt:
            interrupt_count += 1
            action, signal_name = INTERRUPT_ACTIONS[min(interrupt_count, len(INTERRUPT_ACTIONS)) - 1]
            if on_interrupt:
                on_interrupt(action, signal_name)
            deadline = time.monotonic() + (timeout_ms / 1000.0)
            continue
        except usb.core.USBTimeoutError:
            continue

        cmd, status, _unused, _crc, result = struct.unpack_from("<IIIII", payload, 0)
        if cmd != CMD_HBL_SHELL:
            continue
        last_status = status
        chunk = bytes(payload[0x14:]).split(b"\0", 1)[0]
        if status == 4:
            output.extend(chunk)
            if on_chunk and chunk:
                on_chunk(chunk)
            deadline = time.monotonic() + (timeout_ms / 1000.0)
            continue
        if status == 0 and not chunk:
            return result, bytes(output)
        if chunk:
            output.extend(chunk)
            if on_chunk:
                on_chunk(chunk)
            deadline = time.monotonic() + (timeout_ms / 1000.0)
            continue
        return result or last_status, bytes(output)


def shell_quote(value: str) -> str:
    return shlex.quote(value)


def run_os_in_cwd(dev, cwd: str, command: str, timeout_ms: int) -> tuple[int, int, bytes]:
    wrapped = f"cd {shell_quote(cwd)} && {command} 2>&1"
    if len(wrapped.encode("utf-8")) >= 232:
        raise ValueError("command is too long after cwd prefix; shorten it or cd closer first")
    return run_command(dev, wrapped, timeout_ms)


def run_hbl_in_cwd(
    dev,
    cwd: str,
    command: str,
    timeout_ms: int,
    notify_delay: int,
    on_chunk=None,
) -> tuple[int, int, bytes]:
    wrapped = (
        f"cd {shell_quote(cwd)} || exit\n"
        f"{{ {command}; }} 2>&1\n"
        "exit\n"
    )
    result, output = stream_hbl_shell(
        dev,
        wrapped,
        timeout_ms,
        notify_delay,
        on_chunk=on_chunk,
        on_interrupt=lambda action, signal_name: interrupt_remote_command(
            dev,
            action,
            signal_name,
            notify_delay,
            command,
        ),
        forward_stdin=sys.stdin.isatty(),
    )
    return 0, result, output


def resolve_cd(dev, cwd: str, target: str, timeout_ms: int, notify_delay: int, mode: str) -> str:
    cd_target = "cd" if not target or target == "~" else f"cd {shell_quote(target)}"
    command = f"cd {shell_quote(cwd)} && {cd_target} && pwd 2>&1"
    if mode == "hbl":
        result, output = stream_hbl_shell(dev, command + "\nexit\n", timeout_ms, notify_delay)
        status = 0
    else:
        status, result, output = run_command(dev, command, timeout_ms)
    if status != 0 or result != 0:
        text = output.decode("utf-8", "replace").strip()
        raise RuntimeError(text or f"cd failed: status={status} result={result}")
    new_cwd = output.decode("utf-8", "replace").strip().splitlines()[-1]
    if not new_cwd.startswith("/"):
        raise RuntimeError(f"unexpected pwd result: {new_cwd!r}")
    return new_cwd


def print_output(output: bytes) -> None:
    if not output:
        return
    sys.stdout.buffer.write(output)
    if not output.endswith(b"\n"):
        sys.stdout.buffer.write(b"\n")
    sys.stdout.buffer.flush()


def write_output_chunk(chunk: bytes) -> None:
    sys.stdout.buffer.write(chunk)
    sys.stdout.buffer.flush()


def finish_streamed_output(output: bytes) -> None:
    if output and not output.endswith(b"\n"):
        sys.stdout.buffer.write(b"\n")
        sys.stdout.buffer.flush()


def command_name(command: str) -> str:
    try:
        parts = shlex.split(command)
    except ValueError:
        return ""
    if not parts:
        return ""
    return parts[0].rsplit("/", 1)[-1]


def send_hbl_stdin_bytes(dev, data: bytes, notify_delay: int) -> None:
    start = 0
    while start < len(data):
        chunk = data[start : start + 231]
        dev.write(EP_OUT, make_hbl_shell_request_bytes(chunk, notify_delay, request=1), timeout=1000)
        start += len(chunk)


def send_hbl_stdin(dev, text: str, notify_delay: int) -> None:
    send_hbl_stdin_bytes(dev, text.encode("utf-8"), notify_delay)


def forward_local_stdin(dev, notify_delay: int, enabled: bool) -> None:
    if not enabled:
        return
    readable, _writable, _errors = select.select([sys.stdin], [], [], 0)
    if not readable:
        return
    data = os.read(sys.stdin.fileno(), 4096)
    if data:
        send_hbl_stdin_bytes(dev, data, notify_delay)


def interrupt_remote_command(dev, action: str, signal_name: str, notify_delay: int, command: str) -> None:
    name = command_name(command)
    if action == "sigint" and name == "top":
        send_hbl_stdin(dev, "q\n", notify_delay)
        print("\n^C translated to top quit", file=sys.stderr)
    elif action == "sigint":
        dev.write(EP_OUT, make_hbl_shell_request("\x03", notify_delay, request=1), timeout=1000)
        print(f"\n^C sent native HblShell {signal_name}", file=sys.stderr)
    else:
        raise ValueError(f"unknown interrupt action: {action}")


def repl(dev, timeout_ms: int, initial_cwd: str, mode: str, notify_delay: int) -> int:
    cwd = initial_cwd
    if mode == "hbl":
        print("X1D USB shell via sutest command 65 (HblShell). Type 'exit' or Ctrl-D to quit.")
        print("Each input line runs in a temporary shell; output is streamed through notify packets.")
        print("Input typed while a command is running is forwarded to the camera; Ctrl-C uses native HblShell control.")
    else:
        print("X1D USB shell via sutest command 52. Type 'exit' or Ctrl-D to quit.")
        print("Note: command output is limited to one sutest payload, about 232 bytes.")

    while True:
        try:
            line = input(f"x1d:{cwd}$ ")
        except EOFError:
            print()
            return 0
        except KeyboardInterrupt:
            print()
            continue

        command = line.strip()
        if not command:
            continue
        if command in {"exit", "quit"}:
            return 0
        if command == "pwd":
            print(cwd)
            continue
        if command == "help":
            print("Builtins: cd [dir], pwd, exit, quit, help")
            print(f"Other input is executed on the camera through sutest command {'65' if mode == 'hbl' else '52'}.")
            continue
        if command == "clear":
            print("\033c", end="")
            continue
        if command == "cd" or command.startswith("cd "):
            target = command[2:].strip() or "~"
            try:
                cwd = resolve_cd(dev, cwd, target, timeout_ms, notify_delay, mode)
            except (RuntimeError, usb.core.USBError, ValueError) as exc:
                print(f"cd: {exc}", file=sys.stderr)
            continue

        try:
            if mode == "hbl":
                status, result, output = run_hbl_in_cwd(
                    dev,
                    cwd,
                    command,
                    timeout_ms,
                    notify_delay,
                    on_chunk=write_output_chunk,
                )
                finish_streamed_output(output)
            else:
                status, result, output = run_os_in_cwd(dev, cwd, command, timeout_ms)
                print_output(output)
            if status != 0 or result != 0:
                print(f"[status={status} result={result}]", file=sys.stderr)
        except usb.core.USBTimeoutError:
            print("error: USB response timed out", file=sys.stderr)
        except (RuntimeError, usb.core.USBError, ValueError) as exc:
            print(f"error: {exc}", file=sys.stderr)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout-ms", type=int, default=3000)
    parser.add_argument("--cwd", default="/", help="initial camera working directory")
    parser.add_argument("--mode", choices=("hbl", "os"), default="hbl", help="hbl uses command 65; os uses old command 52")
    parser.add_argument("--notify-delay", type=int, default=0, help="HblShell notify delay selector")
    parser.add_argument(
        "--libusb",
        default="/opt/homebrew/lib/libusb-1.0.dylib",
        help="libusb dylib path; use empty string for default discovery",
    )
    args = parser.parse_args(argv)

    dev = open_camera(args.libusb or None)
    return repl(dev, args.timeout_ms, args.cwd, args.mode, args.notify_delay)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
