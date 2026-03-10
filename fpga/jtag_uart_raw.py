#!/usr/bin/env python3
"""
Raw binary JTAG UART communication using libjtag_atlantic.

Loads libjtag_atlantic.so and libjtag_client.so directly via ctypes,
bypassing nios2-terminal entirely. This gives true raw byte access
with no terminal interpretation of control characters (0x04, 0x11, etc).

Requirements:
    - Quartus installed with QUARTUS_ROOTDIR set, OR
    - libjtag_atlantic.so and libjtag_client.so in LD_LIBRARY_PATH
    - jtagd daemon running (start with: jtagconfig or quartus_pgm --list)
"""

import ctypes
import ctypes.util
import os
import sys
import time
import signal

# ---------------------------------------------------------------------------
# Ensure Quartus shared libraries are on LD_LIBRARY_PATH.
# On Linux, LD_LIBRARY_PATH is read once at process start, so if we need to
# add to it, we must re-exec ourselves for the change to take effect.
# ---------------------------------------------------------------------------
_REEXEC_ENV_VAR = "_JTAG_UART_RAW_REEXEC"

if os.environ.get(_REEXEC_ENV_VAR) != "1":
    _quartus_root = os.environ.get("QUARTUS_ROOTDIR", "")
    if _quartus_root:
        _lib_dir = os.path.join(_quartus_root, "linux64")
        _ld_path = os.environ.get("LD_LIBRARY_PATH", "")
        if _lib_dir not in _ld_path:
            os.environ["LD_LIBRARY_PATH"] = _lib_dir + (":" + _ld_path if _ld_path else "")
            os.environ[_REEXEC_ENV_VAR] = "1"
            os.execv(sys.executable, [sys.executable] + sys.argv)


def find_quartus_lib_dir():
    """Find the directory containing the JTAG Atlantic shared libraries."""

    # Check QUARTUS_ROOTDIR first
    quartus_root = os.environ.get("QUARTUS_ROOTDIR", "")
    if quartus_root:
        lib_dir = os.path.join(quartus_root, "linux64")
        if os.path.isfile(os.path.join(lib_dir, "libjtag_atlantic.so")):
            return lib_dir
        # Some installations have it directly in QUARTUS_ROOTDIR
        if os.path.isfile(os.path.join(quartus_root, "libjtag_atlantic.so")):
            return quartus_root

    # Try common Quartus installation paths
    common_paths = [
        "/opt/intelFPGA_lite",
        "/opt/intelFPGA",
        "/opt/altera",
        os.path.expanduser("~/intelFPGA_lite"),
        os.path.expanduser("~/intelFPGA"),
    ]

    for base in common_paths:
        if os.path.isdir(base):
            # Search version directories
            try:
                versions = sorted(os.listdir(base), reverse=True)
            except OSError:
                continue
            for ver in versions:
                lib_dir = os.path.join(base, ver, "quartus", "linux64")
                if os.path.isfile(os.path.join(lib_dir, "libjtag_atlantic.so")):
                    return lib_dir

    return None


class JtagAtlantic:
    """Wrapper around Intel's libjtag_atlantic for raw JTAG UART access."""

    def __init__(self, cable=None, device=-1, instance=-1, progname="jtag_uart_comm"):
        """Open a JTAG Atlantic connection.

        Args:
            cable:    Cable name (e.g. "USB-Blaster [3-2]"), or None for auto.
            device:   Device number in JTAG chain (1-based), or -1 for auto.
            instance: JTAG UART instance number, or -1 for auto.
            progname: Program name for the lock identifier.
        """
        self._handle = None
        self._lib = None

        # Find and load the shared libraries
        lib_dir = find_quartus_lib_dir()

        if lib_dir:
            # Add to library search path
            ld_path = os.environ.get("LD_LIBRARY_PATH", "")
            if lib_dir not in ld_path:
                os.environ["LD_LIBRARY_PATH"] = lib_dir + ":" + ld_path

            client_path = os.path.join(lib_dir, "libjtag_client.so")
            atlantic_path = os.path.join(lib_dir, "libjtag_atlantic.so")
        else:
            # Fall back to system library search
            client_path = "libjtag_client.so"
            atlantic_path = "libjtag_atlantic.so"

        try:
            # Must load jtag_client first as jtag_atlantic depends on it
            ctypes.CDLL(client_path, mode=ctypes.RTLD_GLOBAL)
            self._lib = ctypes.CDLL(atlantic_path)
        except OSError as e:
            raise RuntimeError(
                "Could not load JTAG Atlantic libraries.\n"
                "Make sure Quartus is installed and QUARTUS_ROOTDIR is set.\n"
                "Or add the library directory to LD_LIBRARY_PATH.\n"
                "Error: {}".format(e)
            )

        # C++ mangled symbol names from libjtag_atlantic.so
        # Use bracket access to look up mangled names directly
        self._fn_open      = self._lib["_Z17jtagatlantic_openPKciiS0_"]
        self._fn_close     = self._lib["_Z18jtagatlantic_closeP12JTAGATLANTIC"]
        self._fn_read      = self._lib["_Z17jtagatlantic_readP12JTAGATLANTICPcj"]
        self._fn_write     = self._lib["_Z18jtagatlantic_writeP12JTAGATLANTICPKcj"]
        self._fn_flush     = self._lib["_Z18jtagatlantic_flushP12JTAGATLANTIC"]
        self._fn_avail     = self._lib["_Z28jtagatlantic_bytes_availableP12JTAGATLANTIC"]
        self._fn_get_info  = self._lib["_Z21jtagatlantic_get_infoP12JTAGATLANTICPPKcPiS4_"]
        self._fn_get_error = self._lib["_Z22jtagatlantic_get_errorPPKc"]

        # Set up function signatures
        self._fn_open.restype = ctypes.c_void_p
        self._fn_open.argtypes = [
            ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_char_p
        ]

        self._fn_close.restype = None
        self._fn_close.argtypes = [ctypes.c_void_p]

        self._fn_read.restype = ctypes.c_int
        self._fn_read.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint]

        self._fn_write.restype = ctypes.c_int
        self._fn_write.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint]

        self._fn_flush.restype = ctypes.c_int
        self._fn_flush.argtypes = [ctypes.c_void_p]

        self._fn_avail.restype = ctypes.c_int
        self._fn_avail.argtypes = [ctypes.c_void_p]

        self._fn_get_info.restype = None
        self._fn_get_info.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_char_p),
            ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_int),
        ]

        self._fn_get_error.restype = ctypes.c_char_p
        self._fn_get_error.argtypes = [ctypes.POINTER(ctypes.c_char_p)]

        # Open the connection
        cable_arg = cable.encode("utf-8") if cable else None
        progname_arg = progname.encode("utf-8")

        self._handle = self._fn_open(
            cable_arg, device, instance, progname_arg
        )

        if not self._handle:
            err_info = ctypes.c_char_p()
            err = self._fn_get_error(ctypes.byref(err_info))
            err_msg = err.decode("utf-8") if err else "Unknown error"
            info_msg = err_info.value.decode("utf-8") if err_info.value else ""
            raise RuntimeError(
                "Failed to open JTAG Atlantic: {} {}".format(err_msg, info_msg)
            )

    def get_info(self):
        """Get connection info (cable name, device number, instance number)."""
        cable = ctypes.c_char_p()
        device = ctypes.c_int()
        instance = ctypes.c_int()
        self._fn_get_info(
            self._handle, ctypes.byref(cable), ctypes.byref(device), ctypes.byref(instance)
        )
        cable_str = cable.value.decode("utf-8") if cable.value else "unknown"
        return cable_str, device.value, instance.value

    def read(self, max_bytes=4096):
        """Read available bytes. Returns bytes (may be empty if nothing available).

        Args:
            max_bytes: Maximum number of bytes to read.

        Returns:
            bytes: The received data (empty if nothing available).
        """
        buf = ctypes.create_string_buffer(max_bytes)
        n = self._fn_read(self._handle, buf, max_bytes)
        if n < 0:
            raise IOError("JTAG Atlantic read error (connection lost?)")
        return buf.raw[:n]

    def write(self, data):
        """Write raw bytes. Returns number of bytes actually written.

        Args:
            data: bytes to send.

        Returns:
            int: Number of bytes written.
        """
        n = self._fn_write(self._handle, data, len(data))
        if n < 0:
            raise IOError("JTAG Atlantic write error (connection lost?)")
        return n

    def flush(self):
        """Flush the write buffer to ensure all data is sent."""
        self._fn_flush(self._handle)

    def bytes_available(self):
        """Return number of bytes available to read."""
        return self._fn_avail(self._handle)

    def close(self):
        """Close the JTAG Atlantic connection."""
        if self._handle:
            self._fn_close(self._handle)
            self._handle = None

    def __del__(self):
        self.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


def format_rx_bytes(data):
    """Format received bytes showing hex and ASCII."""
    lines = []
    for b in data:
        if 0x20 <= b <= 0x7E:
            lines.append("  RX: 0x{:02X} ('{}')".format(b, chr(b)))
        else:
            lines.append("  RX: 0x{:02X}".format(b))
    return "\n".join(lines)


def format_rx_string(data):
    """Convert received bytes to a printable string."""
    result = []
    for b in data:
        if 0x20 <= b <= 0x7E:
            result.append(chr(b))
        else:
            result.append("\\x{:02X}".format(b))
    return "".join(result)


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Raw binary JTAG UART communication via libjtag_atlantic"
    )
    parser.add_argument(
        "--cable", default=None,
        help="USB-Blaster cable name (e.g. 'USB-Blaster [3-2]'). Auto-detect if omitted."
    )
    parser.add_argument(
        "--device", type=int, default=-1,
        help="Device number in JTAG chain (1-based). -1 for auto."
    )
    parser.add_argument(
        "--instance", type=int, default=-1,
        help="JTAG UART instance number. -1 for auto."
    )
    args = parser.parse_args()

    print("=" * 60)
    print("  JTAG UART Raw Binary Communication Tool")
    print("  (using libjtag_atlantic - no nios2-terminal)")
    print("=" * 60)
    print()

    # Open the connection
    print("Opening JTAG Atlantic connection...")
    try:
        ja = JtagAtlantic(
            cable=args.cable,
            device=args.device,
            instance=args.instance,
        )
    except RuntimeError as e:
        print("Error: {}".format(e))
        sys.exit(1)

    cable, device, instance = ja.get_info()
    print("Connected to cable '{}', device {}, instance {}".format(cable, device, instance))
    print()

    # Handle Ctrl-C gracefully
    running = True

    def signal_handler(sig, frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGINT, signal_handler)

    # Read any initial data
    print("Reading initial data...")
    time.sleep(0.5)
    initial = ja.read()
    if initial:
        print("  Received {} bytes:".format(len(initial)))
        print(format_rx_bytes(initial))
        print("  As string: {}".format(format_rx_string(initial)))
    else:
        print("  No initial data.")
    print()

    # Interactive loop
    print("Commands:")
    print("  Type a message and press Enter to send as ASCII (with newline)")
    print("  'hex XX YY ZZ' to send raw hex bytes (e.g. hex 01 04 11 FF)")
    print("  'int[N][s] V'  to send integers as little-endian bytes")
    print("                 N = 8, 16, or 32 (bit width)")
    print("                 append 's' for signed (default: unsigned)")
    print("                 e.g. int8s -10 -128 / int16 395 1023 / int32s -99999")
    print("  'read'         to read without sending")
    print("  'quit'         to exit")
    print()

    try:
        while running:
            try:
                user_input = input("TX> ")
            except EOFError:
                break

            if not running:
                break

            if not user_input:
                continue

            cmd = user_input.strip().lower()

            if cmd == "quit":
                break

            elif cmd == "read":
                print("  Reading...")
                time.sleep(0.1)
                rx = ja.read()
                if rx:
                    print("  Received {} bytes:".format(len(rx)))
                    print(format_rx_bytes(rx))
                    print("  As string: {}".format(format_rx_string(rx)))
                else:
                    print("  No data available.")

            elif cmd.startswith("hex "):
                try:
                    hex_parts = user_input.strip()[4:].split()
                    tx_bytes = bytes(int(h, 16) for h in hex_parts)
                except ValueError:
                    print("  Error: Invalid hex format. Use: hex 01 04 11 FF")
                    print()
                    continue

                hex_str = " ".join("0x{:02X}".format(b) for b in tx_bytes)
                print("  Sending {} raw bytes: {}".format(len(tx_bytes), hex_str))

                # Write all bytes (may need multiple calls if buffer is full)
                offset = 0
                while offset < len(tx_bytes):
                    n = ja.write(tx_bytes[offset:])
                    if n == 0:
                        time.sleep(0.01)
                        continue
                    offset += n
                ja.flush()
                print("  Sent OK.")

                # Read response
                print("  Waiting for response...")
                time.sleep(0.2)
                rx = ja.read()
                if rx:
                    print("  Received {} bytes:".format(len(rx)))
                    print(format_rx_bytes(rx))
                    print("  As string: {}".format(format_rx_string(rx)))
                else:
                    print("  No response received.")

            elif cmd.startswith("int"):
                # Parse format: int8, int16, int32, int8s, int16s, int32s
                try:
                    parts = user_input.strip().split()
                    tag = parts[0].lower()
                    values_str = parts[1:]

                    if not values_str:
                        print("  Error: No values provided.")
                        print("  Usage: int16s -10 1023  or  int8 255 128")
                        print()
                        continue

                    # Parse the tag to get width and signedness
                    tag_body = tag[3:]  # strip "int"
                    signed = tag_body.endswith("s")
                    if signed:
                        tag_body = tag_body[:-1]

                    if tag_body == "8":
                        width = 8
                    elif tag_body == "16":
                        width = 16
                    elif tag_body == "32":
                        width = 32
                    else:
                        print("  Error: Unknown width '{}'. Use int8, int16, or int32.".format(tag_body))
                        print()
                        continue

                    byte_count = width // 8
                    if signed:
                        min_val = -(1 << (width - 1))
                        max_val = (1 << (width - 1)) - 1
                    else:
                        min_val = 0
                        max_val = (1 << width) - 1

                    # Pack all integers
                    tx_bytes = bytearray()
                    pack_error = False
                    for v_str in values_str:
                        v = int(v_str)
                        if v < min_val or v > max_val:
                            kind = "int{}{}".format(width, "s" if signed else "")
                            print("  Error: {} out of range for {} [{}, {}]".format(
                                v, kind, min_val, max_val))
                            pack_error = True
                            break
                        if signed and v < 0:
                            # Two's complement
                            v = v + (1 << width)
                        # Little-endian packing
                        for i in range(byte_count):
                            tx_bytes.append((v >> (8 * i)) & 0xFF)

                    if pack_error:
                        print()
                        continue

                    tx_bytes = bytes(tx_bytes)
                    hex_str = " ".join("0x{:02X}".format(b) for b in tx_bytes)
                    kind = "int{}{}".format(width, "s" if signed else "")
                    print("  Packing {} value(s) as {} little-endian: [{}]".format(
                        len(values_str), kind, ", ".join(values_str)))
                    print("  Sending {} bytes: {}".format(len(tx_bytes), hex_str))

                    offset = 0
                    while offset < len(tx_bytes):
                        n = ja.write(tx_bytes[offset:])
                        if n == 0:
                            time.sleep(0.01)
                            continue
                        offset += n
                    ja.flush()
                    print("  Sent OK.")

                    print("  Waiting for response...")
                    time.sleep(0.2)
                    rx = ja.read()
                    if rx:
                        print("  Received {} bytes:".format(len(rx)))
                        print(format_rx_bytes(rx))
                        print("  As string: {}".format(format_rx_string(rx)))
                        # Decode response as the same integer format
                        if len(rx) >= byte_count:
                            num_ints = len(rx) // byte_count
                            usable = num_ints * byte_count
                            leftover = len(rx) - usable
                            decoded = []
                            for i in range(num_ints):
                                raw_val = 0
                                for j in range(byte_count):
                                    raw_val |= rx[i * byte_count + j] << (8 * j)
                                if signed and (raw_val >= (1 << (width - 1))):
                                    raw_val -= (1 << width)
                                decoded.append(str(raw_val))
                            print("  As {} (x{}): [{}]".format(kind, num_ints, ", ".join(decoded)))
                            if leftover > 0:
                                extra = " ".join("0x{:02X}".format(rx[usable + k]) for k in range(leftover))
                                print("  Leftover {} byte(s): {}".format(leftover, extra))
                        else:
                            print("  (Not enough bytes to decode as {})".format(kind))
                    else:
                        print("  No response received.")

                except ValueError as e:
                    print("  Error: Could not parse integer value: {}".format(e))
                    print("  Usage: int16s -10 1023  or  int8 255 128")

            else:
                # Send as ASCII with newline
                tx_bytes = (user_input + "\n").encode("ascii", errors="replace")
                print("  Sending {} bytes: {!r}".format(len(tx_bytes), user_input))

                offset = 0
                while offset < len(tx_bytes):
                    n = ja.write(tx_bytes[offset:])
                    if n == 0:
                        time.sleep(0.01)
                        continue
                    offset += n
                ja.flush()
                print("  Sent OK.")

                # Read response
                print("  Waiting for response...")
                time.sleep(0.2)
                rx = ja.read()
                if rx:
                    print("  Received {} bytes:".format(len(rx)))
                    print(format_rx_bytes(rx))
                    print("  As string: {}".format(format_rx_string(rx)))
                else:
                    print("  No response received.")

            print()

    except KeyboardInterrupt:
        print()

    print("Closing JTAG Atlantic connection...")
    ja.close()
    print("Done.")


if __name__ == "__main__":
    main()