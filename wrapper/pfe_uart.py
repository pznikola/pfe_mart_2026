#!/usr/bin/env python3
"""
pfe_uart.py — Send and receive data to/from DE1-SoC JTAG UART.

Works by wrapping Quartus's nios2-terminal as a subprocess.
The FPGA design uses WORD_BYTES to set the word width — this script
must use the same value so it knows how many bytes to send per word.

Usage:
    python pfe_uart.py                          # interactive mode
    python pfe_uart.py --send 0xDEADBEEF        # send one word (hex)
    python pfe_uart.py --send 12345             # send one word (decimal)
    python pfe_uart.py --send-bytes DE AD BE EF # send raw bytes (hex)
    python pfe_uart.py --send-file data.bin     # send binary file
    python pfe_uart.py --test                   # loopback test
    python pfe_uart.py --word-bytes 2           # use 16-bit words (default: 4)
    python pfe_uart.py --device 2 --instance 0  # specify JTAG device

Requires:
    - nios2-terminal in PATH (comes with Quartus Nios II EDS)
    - FPGA programmed with the JTAG UART design
"""

import subprocess
import struct
import sys
import os
import time
import argparse
import signal
import select
import threading


# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

def word_to_bytes(value, word_bytes):
    """Convert an integer to a list of bytes, MSB first."""
    b = []
    for i in range(word_bytes - 1, -1, -1):
        b.append((value >> (i * 8)) & 0xFF)
    return bytes(b)


def bytes_to_word(data, word_bytes):
    """Convert bytes (MSB first) to an integer."""
    val = 0
    for b in data[:word_bytes]:
        val = (val << 8) | b
    return val


def find_nios2_terminal():
    """Locate nios2-terminal in PATH or common Quartus install dirs."""
    import shutil
    path = shutil.which("nios2-terminal")
    if path:
        return path

    # Try to find it from quartus_sh
    qs = shutil.which("quartus_sh")
    if qs:
        qs = os.path.realpath(qs)
        quartus_root = os.path.dirname(os.path.dirname(os.path.dirname(qs)))
        candidates = [
            os.path.join(quartus_root, "nios2eds", "bin", "nios2-terminal"),
            os.path.join(quartus_root, "nios2eds", "bin", "nios2-terminal.exe"),
        ]
        for c in candidates:
            if os.path.isfile(c):
                return c

    return None


class JtagUart:
    """Manages a nios2-terminal subprocess for bidirectional JTAG UART I/O."""

    def __init__(self, device=2, instance=0):
        self.nios2_term = find_nios2_terminal()
        if not self.nios2_term:
            print("ERROR: nios2-terminal not found.")
            print("Make sure Quartus Nios II EDS is installed and in PATH.")
            print("Or run from the Nios II Command Shell.")
            sys.exit(1)

        cmd = [
            self.nios2_term,
            "--device", str(device),
            "--instance", str(instance),
            "--no-quit-on-ctrl-c",
        ]

        self.proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        # Give it a moment to connect
        time.sleep(1.0)

        # Check if it started OK
        if self.proc.poll() is not None:
            err = self.proc.stderr.read().decode(errors="replace")
            print(f"ERROR: nios2-terminal exited immediately:\n{err}")
            sys.exit(1)

    def send(self, data):
        """Send raw bytes to the FPGA."""
        self.proc.stdin.write(data)
        self.proc.stdin.flush()

    def recv(self, nbytes, timeout=2.0):
        """Receive up to nbytes from the FPGA, with timeout."""
        result = bytearray()
        deadline = time.time() + timeout

        while len(result) < nbytes and time.time() < deadline:
            remaining = deadline - time.time()
            if remaining <= 0:
                break
            # Use select to wait for data with timeout
            try:
                ready, _, _ = select.select([self.proc.stdout], [], [], min(remaining, 0.1))
                if ready:
                    chunk = self.proc.stdout.read1(nbytes - len(result))
                    if chunk:
                        result.extend(chunk)
            except (AttributeError, OSError):
                # read1 not available, fall back
                time.sleep(0.05)
                try:
                    chunk = self.proc.stdout.read(1)
                    if chunk:
                        result.extend(chunk)
                except Exception:
                    break

        return bytes(result)

    def close(self):
        """Shut down the nios2-terminal subprocess."""
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        try:
            self.proc.terminate()
            self.proc.wait(timeout=3)
        except Exception:
            self.proc.kill()


# ─────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────

def cmd_send_word(uart, value, word_bytes):
    """Send one word and receive the response."""
    tx = word_to_bytes(value, word_bytes)
    print(f"TX: 0x{value:0{word_bytes*2}X}  ({word_bytes} bytes: {' '.join(f'{b:02X}' for b in tx)})")

    uart.send(tx)
    rx = uart.recv(word_bytes)

    if len(rx) == word_bytes:
        rx_val = bytes_to_word(rx, word_bytes)
        print(f"RX: 0x{rx_val:0{word_bytes*2}X}  ({word_bytes} bytes: {' '.join(f'{b:02X}' for b in rx)})")
        if rx_val == value:
            print("✓ Match (passthrough)")
        else:
            print(f"  Δ  TX=0x{value:X}  RX=0x{rx_val:X}  (pfe modified the data)")
    else:
        print(f"RX: got {len(rx)} bytes, expected {word_bytes}")


def cmd_send_bytes(uart, hex_bytes, word_bytes):
    """Send raw hex bytes."""
    tx = bytes(int(h, 16) for h in hex_bytes)
    if len(tx) % word_bytes != 0:
        print(f"WARNING: {len(tx)} bytes is not a multiple of WORD_BYTES={word_bytes}")

    print(f"TX: {' '.join(f'{b:02X}' for b in tx)}  ({len(tx)} bytes)")
    uart.send(tx)
    rx = uart.recv(len(tx))
    print(f"RX: {' '.join(f'{b:02X}' for b in rx)}  ({len(rx)} bytes)")


def cmd_send_file(uart, filepath, word_bytes):
    """Send a binary file and receive the response."""
    if not os.path.isfile(filepath):
        print(f"File not found: {filepath}")
        return

    with open(filepath, "rb") as f:
        data = f.read()

    if len(data) % word_bytes != 0:
        pad = word_bytes - (len(data) % word_bytes)
        data += b'\x00' * pad
        print(f"Padded {pad} zero bytes to align to WORD_BYTES={word_bytes}")

    total = len(data)
    print(f"Sending {total} bytes ({total // word_bytes} words of {word_bytes} bytes)")

    chunk_size = 64
    received = bytearray()
    start = time.time()

    for i in range(0, total, chunk_size):
        chunk = data[i:i + chunk_size]
        uart.send(chunk)
        time.sleep(0.01)

        rx = uart.recv(len(chunk), timeout=0.5)
        received.extend(rx)

        pct = min(100, (i + chunk_size) * 100 // total)
        print(f"\r  Progress: {pct:3d}%  ({len(received)}/{total} bytes)", end="", flush=True)

    # Drain remaining
    time.sleep(0.5)
    rx = uart.recv(total - len(received), timeout=2.0)
    received.extend(rx)

    elapsed = time.time() - start
    print(f"\n  Sent:     {total} bytes")
    print(f"  Received: {len(received)} bytes")
    print(f"  Time:     {elapsed:.2f}s")
    if elapsed > 0:
        print(f"  Rate:     {len(received) / elapsed:.0f} bytes/s")
    print(f"  Match:    {'✓ Yes' if data == bytes(received) else '✗ No'}")


def cmd_test(uart, word_bytes):
    """Loopback test with several word values."""
    print(f"Loopback test (WORD_BYTES={word_bytes})")
    print("=" * 50)

    max_val = (1 << (word_bytes * 8)) - 1
    test_values = [
        0,
        1,
        0x55 * ((max_val + 1) // 256 or 1),
        0xAA * ((max_val + 1) // 256 or 1),
        max_val // 2,
        max_val,
    ]
    # Deduplicate and clamp
    test_values = list(dict.fromkeys(v & max_val for v in test_values))

    passed = 0
    failed = 0

    for val in test_values:
        tx = word_to_bytes(val, word_bytes)
        uart.send(tx)
        rx = uart.recv(word_bytes, timeout=2.0)

        if len(rx) == word_bytes:
            rx_val = bytes_to_word(rx, word_bytes)
            ok = rx_val == val
            status = "✓" if ok else "✗"
            print(f"  {status}  TX: 0x{val:0{word_bytes*2}X}  →  RX: 0x{rx_val:0{word_bytes*2}X}")
            if ok:
                passed += 1
            else:
                failed += 1
        else:
            print(f"  ✗  TX: 0x{val:0{word_bytes*2}X}  →  RX: {len(rx)} bytes (expected {word_bytes})")
            failed += 1

        time.sleep(0.05)

    print("=" * 50)
    print(f"  Passed: {passed}  Failed: {failed}")


def cmd_interactive(uart, word_bytes):
    """Interactive mode: type hex values, see responses."""
    print(f"Interactive JTAG UART  (WORD_BYTES={word_bytes})")
    print(f"  Type a hex value (e.g. DEADBEEF) and press Enter to send as a {word_bytes*8}-bit word.")
    print(f"  Type 'raw XX XX XX' to send raw hex bytes.")
    print(f"  Type 'quit' to exit.")
    print()

    while True:
        try:
            line = input("> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if not line:
            continue
        if line.lower() == "quit":
            break

        if line.lower().startswith("raw "):
            parts = line.split()[1:]
            try:
                tx = bytes(int(h, 16) for h in parts)
                print(f"  TX: {' '.join(f'{b:02X}' for b in tx)}")
                uart.send(tx)
                rx = uart.recv(len(tx))
                print(f"  RX: {' '.join(f'{b:02X}' for b in rx)}")
            except ValueError as e:
                print(f"  Error: {e}")
            continue

        # Parse as hex or decimal word
        try:
            if line.lower().startswith("0x"):
                val = int(line, 16)
            else:
                val = int(line, 16)  # default to hex
        except ValueError:
            try:
                val = int(line, 10)
            except ValueError:
                print(f"  Cannot parse '{line}'. Use hex (DEADBEEF) or decimal.")
                continue

        max_val = (1 << (word_bytes * 8)) - 1
        if val > max_val:
            print(f"  Value 0x{val:X} exceeds {word_bytes*8}-bit range (max 0x{max_val:X})")
            continue

        cmd_send_word(uart, val, word_bytes)


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Send/receive data to DE1-SoC FPGA via JTAG UART"
    )
    parser.add_argument("--word-bytes", type=int, default=4,
                        help="Word width in bytes, must match FPGA WORD_BYTES (default: 4)")
    parser.add_argument("--device", type=int, default=2,
                        help="JTAG device index (default: 2 for DE1-SoC FPGA)")
    parser.add_argument("--instance", type=int, default=0,
                        help="JTAG UART instance (default: 0)")
    parser.add_argument("--send", type=str,
                        help="Send one word (hex or decimal, e.g. 0xDEADBEEF or 12345)")
    parser.add_argument("--send-bytes", nargs="+",
                        help="Send raw hex bytes (e.g. DE AD BE EF)")
    parser.add_argument("--send-file", type=str,
                        help="Send a binary file")
    parser.add_argument("--test", action="store_true",
                        help="Run loopback test")

    args = parser.parse_args()

    print(f"Connecting to JTAG UART (device={args.device}, instance={args.instance})...")
    uart = JtagUart(device=args.device, instance=args.instance)
    print("Connected.\n")

    try:
        if args.send:
            val = int(args.send, 0)  # auto-detect hex/decimal
            cmd_send_word(uart, val, args.word_bytes)
        elif args.send_bytes:
            cmd_send_bytes(uart, args.send_bytes, args.word_bytes)
        elif args.send_file:
            cmd_send_file(uart, args.send_file, args.word_bytes)
        elif args.test:
            cmd_test(uart, args.word_bytes)
        else:
            cmd_interactive(uart, args.word_bytes)
    finally:
        uart.close()
        print("Disconnected.")


if __name__ == "__main__":
    main()
