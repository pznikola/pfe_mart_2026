#!/usr/bin/env python3
"""
Send and receive a 32x32 grayscale PNG image over JTAG UART.

Reads images/pfe.png, extracts raw 8-bit grayscale pixels (1024 bytes),
sends them over JTAG UART to the FPGA, then receives 1024 bytes back
and saves the result as images/pfe_received.png.

Uses libjtag_atlantic directly via ctypes (same as jtag_uart_raw.py).

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
import struct
import zlib
import argparse

# ---------------------------------------------------------------------------
# Ensure Quartus shared libraries are on LD_LIBRARY_PATH.
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
    quartus_root = os.environ.get("QUARTUS_ROOTDIR", "")
    if quartus_root:
        lib_dir = os.path.join(quartus_root, "linux64")
        if os.path.isfile(os.path.join(lib_dir, "libjtag_atlantic.so")):
            return lib_dir
        if os.path.isfile(os.path.join(quartus_root, "libjtag_atlantic.so")):
            return quartus_root

    common_paths = [
        "/opt/intelFPGA_lite",
        "/opt/intelFPGA",
        "/opt/altera",
        os.path.expanduser("~/intelFPGA_lite"),
        os.path.expanduser("~/intelFPGA"),
    ]
    for base in common_paths:
        if os.path.isdir(base):
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

    def __init__(self, cable=None, device=-1, instance=-1, progname="jtag_uart_image"):
        self._handle = None
        self._lib = None

        lib_dir = find_quartus_lib_dir()
        if lib_dir:
            ld_path = os.environ.get("LD_LIBRARY_PATH", "")
            if lib_dir not in ld_path:
                os.environ["LD_LIBRARY_PATH"] = lib_dir + ":" + ld_path
            client_path = os.path.join(lib_dir, "libjtag_client.so")
            atlantic_path = os.path.join(lib_dir, "libjtag_atlantic.so")
        else:
            client_path = "libjtag_client.so"
            atlantic_path = "libjtag_atlantic.so"

        try:
            ctypes.CDLL(client_path, mode=ctypes.RTLD_GLOBAL)
            self._lib = ctypes.CDLL(atlantic_path)
        except OSError as e:
            raise RuntimeError(
                "Could not load JTAG Atlantic libraries.\n"
                "Make sure Quartus is installed and QUARTUS_ROOTDIR is set.\n"
                "Error: {}".format(e)
            )

        self._fn_open      = self._lib["_Z17jtagatlantic_openPKciiS0_"]
        self._fn_close     = self._lib["_Z18jtagatlantic_closeP12JTAGATLANTIC"]
        self._fn_read      = self._lib["_Z17jtagatlantic_readP12JTAGATLANTICPcj"]
        self._fn_write     = self._lib["_Z18jtagatlantic_writeP12JTAGATLANTICPKcj"]
        self._fn_flush     = self._lib["_Z18jtagatlantic_flushP12JTAGATLANTIC"]
        self._fn_avail     = self._lib["_Z28jtagatlantic_bytes_availableP12JTAGATLANTIC"]
        self._fn_get_info  = self._lib["_Z21jtagatlantic_get_infoP12JTAGATLANTICPPKcPiS4_"]
        self._fn_get_error = self._lib["_Z22jtagatlantic_get_errorPPKc"]

        self._fn_open.restype = ctypes.c_void_p
        self._fn_open.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_char_p]
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
            ctypes.c_void_p, ctypes.POINTER(ctypes.c_char_p),
            ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
        ]
        self._fn_get_error.restype = ctypes.c_char_p
        self._fn_get_error.argtypes = [ctypes.POINTER(ctypes.c_char_p)]

        cable_arg = cable.encode("utf-8") if cable else None
        progname_arg = progname.encode("utf-8")
        self._handle = self._fn_open(cable_arg, device, instance, progname_arg)

        if not self._handle:
            err_info = ctypes.c_char_p()
            err = self._fn_get_error(ctypes.byref(err_info))
            err_msg = err.decode("utf-8") if err else "Unknown error"
            info_msg = err_info.value.decode("utf-8") if err_info.value else ""
            raise RuntimeError("Failed to open JTAG Atlantic: {} {}".format(err_msg, info_msg))

    def get_info(self):
        cable = ctypes.c_char_p()
        device = ctypes.c_int()
        instance = ctypes.c_int()
        self._fn_get_info(self._handle, ctypes.byref(cable), ctypes.byref(device), ctypes.byref(instance))
        cable_str = cable.value.decode("utf-8") if cable.value else "unknown"
        return cable_str, device.value, instance.value

    def read(self, max_bytes=4096):
        buf = ctypes.create_string_buffer(max_bytes)
        n = self._fn_read(self._handle, buf, max_bytes)
        if n < 0:
            raise IOError("JTAG Atlantic read error (connection lost?)")
        return buf.raw[:n]

    def write(self, data):
        n = self._fn_write(self._handle, data, len(data))
        if n < 0:
            raise IOError("JTAG Atlantic write error (connection lost?)")
        return n

    def flush(self):
        self._fn_flush(self._handle)

    def bytes_available(self):
        return self._fn_avail(self._handle)

    def close(self):
        if self._handle:
            self._fn_close(self._handle)
            self._handle = None

    def __del__(self):
        self.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


# ---------------------------------------------------------------------------
# PNG helpers (no external dependencies - pure Python)
# ---------------------------------------------------------------------------

def png_read_grayscale(filepath):
    """Read a grayscale PNG and return (width, height, pixel_bytes).

    Returns raw pixel data as bytes, one byte per pixel, row-major order.
    Only supports 8-bit grayscale (color type 0, bit depth 8).
    """
    with open(filepath, "rb") as f:
        data = f.read()

    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError("Not a valid PNG file: {}".format(filepath))

    pos = 8
    width = height = bit_depth = color_type = 0
    idat_chunks = []

    while pos < len(data):
        chunk_len = struct.unpack(">I", data[pos:pos+4])[0]
        chunk_type = data[pos+4:pos+8]
        chunk_data = data[pos+8:pos+8+chunk_len]
        pos += 12 + chunk_len

        if chunk_type == b'IHDR':
            width = struct.unpack(">I", chunk_data[0:4])[0]
            height = struct.unpack(">I", chunk_data[4:8])[0]
            bit_depth = chunk_data[8]
            color_type = chunk_data[9]
            if color_type != 0 or bit_depth != 8:
                raise ValueError(
                    "Only 8-bit grayscale PNG supported. "
                    "Got color_type={}, bit_depth={}".format(color_type, bit_depth)
                )
        elif chunk_type == b'IDAT':
            idat_chunks.append(chunk_data)
        elif chunk_type == b'IEND':
            break

    compressed = b''.join(idat_chunks)
    raw = zlib.decompress(compressed)

    stride = width + 1
    pixels = bytearray()
    prev_row = bytearray(width)

    for y in range(height):
        row_start = y * stride
        filter_byte = raw[row_start]
        row_data = bytearray(raw[row_start + 1: row_start + 1 + width])

        if filter_byte == 0:
            pass
        elif filter_byte == 1:
            for x in range(1, width):
                row_data[x] = (row_data[x] + row_data[x - 1]) & 0xFF
        elif filter_byte == 2:
            for x in range(width):
                row_data[x] = (row_data[x] + prev_row[x]) & 0xFF
        elif filter_byte == 3:
            for x in range(width):
                left = row_data[x - 1] if x > 0 else 0
                row_data[x] = (row_data[x] + (left + prev_row[x]) // 2) & 0xFF
        elif filter_byte == 4:
            for x in range(width):
                a = row_data[x - 1] if x > 0 else 0
                b = prev_row[x]
                c = prev_row[x - 1] if x > 0 else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                row_data[x] = (row_data[x] + pr) & 0xFF
        else:
            raise ValueError("Unknown PNG filter type: {}".format(filter_byte))

        pixels.extend(row_data)
        prev_row = row_data

    return width, height, bytes(pixels)


def png_write_grayscale(filepath, width, height, pixel_bytes):
    """Write raw grayscale pixel data as an 8-bit grayscale PNG."""
    raw_rows = bytearray()
    for y in range(height):
        raw_rows.append(0)  # filter: None
        raw_rows.extend(pixel_bytes[y * width: (y + 1) * width])

    compressed = zlib.compress(bytes(raw_rows))

    def make_chunk(ctype, cdata):
        chunk = ctype + cdata
        crc = struct.pack(">I", zlib.crc32(chunk) & 0xFFFFFFFF)
        return struct.pack(">I", len(cdata)) + chunk + crc

    png = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    png += make_chunk(b'IHDR', ihdr)
    png += make_chunk(b'IDAT', compressed)
    png += make_chunk(b'IEND', b'')

    with open(filepath, "wb") as f:
        f.write(png)


# ---------------------------------------------------------------------------
# Send / receive helpers
# ---------------------------------------------------------------------------

def send_all(ja, data, chunk_delay=0.001):
    """Send all bytes over JTAG UART, retrying as needed."""
    total = len(data)
    offset = 0
    while offset < total:
        n = ja.write(data[offset:])
        if n == 0:
            time.sleep(chunk_delay)
            continue
        offset += n
        # Flush periodically for reliability over JTAG
        if offset % 256 == 0 or offset == total:
            ja.flush()

        # Progress
        pct = 100.0 * offset / total
        sys.stdout.write("\r  Sent: {} / {} bytes ({:.0f}%)".format(offset, total, pct))
        sys.stdout.flush()

    ja.flush()
    sys.stdout.write("\n")
    return offset


def receive_all(ja, expected_bytes, timeout=30.0, poll_interval=0.01):
    """Receive exactly expected_bytes from JTAG UART with timeout."""
    rx_buf = bytearray()
    t_start = time.time()

    while len(rx_buf) < expected_bytes:
        elapsed = time.time() - t_start
        if elapsed > timeout:
            break

        chunk = ja.read(expected_bytes - len(rx_buf))
        if chunk:
            rx_buf.extend(chunk)
            t_start = time.time()  # reset timeout on each received chunk

            pct = 100.0 * len(rx_buf) / expected_bytes
            sys.stdout.write("\r  Received: {} / {} bytes ({:.0f}%)".format(
                len(rx_buf), expected_bytes, pct
            ))
            sys.stdout.flush()
        else:
            time.sleep(poll_interval)

    sys.stdout.write("\n")
    return bytes(rx_buf)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Send/receive a 32x32 grayscale image over JTAG UART"
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
    parser.add_argument(
        "--input", default="images/pfe.png",
        help="Input PNG image to send (default: images/pfe.png)"
    )
    parser.add_argument(
        "--output", default="images/pfe_received.png",
        help="Output PNG image received back (default: images/pfe_received.png)"
    )
    parser.add_argument(
        "--timeout", type=float, default=30.0,
        help="Receive timeout in seconds (default: 30)"
    )
    parser.add_argument(
        "--kernel-size", type=int, default=1,
        help="Convolution kernel size K (default: 1 = no convolution, output same as input). "
             "Output will be (W-K+1) x (H-K+1). E.g. --kernel-size 3 for a 3x3 kernel."
    )
    args = parser.parse_args()

    # -----------------------------------------------------------------------
    # 1. Load the image
    # -----------------------------------------------------------------------
    print("=" * 60)
    print("  JTAG UART Image Transfer Tool")
    print("=" * 60)
    print()

    input_path = args.input
    output_path = args.output

    if not os.path.isfile(input_path):
        print("Error: Input image not found: {}".format(input_path))
        sys.exit(1)

    print("Loading image: {}".format(input_path))
    width, height, pixels = png_read_grayscale(input_path)
    num_pixels = width * height
    print("  Input size: {}x{}, {} pixels, {} bytes to send".format(
        width, height, num_pixels, num_pixels
    ))

    # Compute output dimensions based on kernel size (no-padding convolution)
    K = args.kernel_size
    if K < 1:
        print("Error: --kernel-size must be >= 1")
        sys.exit(1)

    out_width = width - K + 1
    out_height = height - K + 1

    if out_width <= 0 or out_height <= 0:
        print("Error: kernel size {} is too large for {}x{} image".format(K, width, height))
        sys.exit(1)

    out_pixels = out_width * out_height

    if K > 1:
        print("  Kernel size: {}x{}".format(K, K))
        print("  Expected output: {}x{}, {} pixels, {} bytes to receive".format(
            out_width, out_height, out_pixels, out_pixels
        ))
    else:
        print("  No convolution (kernel_size=1), expecting same size back")

    # Show a few pixel values for verification
    print("  First 16 pixel values:")
    print("    " + " ".join("{:3d}".format(pixels[i]) for i in range(min(16, num_pixels))))
    print("  Last 16 pixel values:")
    print("    " + " ".join("{:3d}".format(pixels[i]) for i in range(max(0, num_pixels-16), num_pixels)))
    print()

    # -----------------------------------------------------------------------
    # 2. Open JTAG UART connection
    # -----------------------------------------------------------------------
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

    # Handle Ctrl-C
    running = True
    def signal_handler(sig, frame):
        nonlocal running
        running = False
    signal.signal(signal.SIGINT, signal_handler)

    # Drain any stale data in the receive buffer
    time.sleep(0.3)
    stale = ja.read()
    if stale:
        print("Drained {} stale bytes from receive buffer.".format(len(stale)))
        print()

    try:
        # -------------------------------------------------------------------
        # 3. Send image pixels
        # -------------------------------------------------------------------
        print("Sending {} bytes ({} pixels)...".format(num_pixels, num_pixels))
        t0 = time.time()
        sent = send_all(ja, pixels)
        t_send = time.time() - t0
        print("  Completed in {:.2f}s ({:.0f} bytes/s)".format(
            t_send, sent / t_send if t_send > 0 else 0
        ))
        print()

        # -------------------------------------------------------------------
        # 4. Receive convolved image pixels back
        # -------------------------------------------------------------------
        print("Waiting to receive {} bytes back ({}x{}, timeout: {}s)...".format(
            out_pixels, out_width, out_height, args.timeout
        ))
        t0 = time.time()
        rx_data = receive_all(ja, out_pixels, timeout=args.timeout)
        t_recv = time.time() - t0

        if len(rx_data) == 0:
            print("  No data received. Is the FPGA sending data back?")
            print("  (If your design doesn't echo, that's expected.)")
            print()
            print("Image was sent successfully. No received image to save.")
            return

        print("  Completed: {} / {} bytes in {:.2f}s".format(
            len(rx_data), out_pixels, t_recv
        ))

        if len(rx_data) < out_pixels:
            print()
            print("  WARNING: Received fewer bytes than expected!")
            print("  The received image will be padded with zeros (black).")
            rx_data = rx_data + bytes(out_pixels - len(rx_data))

        print()

        # Show received pixel values for verification
        print("  First 16 received pixel values:")
        print("    " + " ".join("{:3d}".format(rx_data[i]) for i in range(min(16, len(rx_data)))))
        print("  Last 16 received pixel values:")
        print("    " + " ".join("{:3d}".format(rx_data[i]) for i in range(max(0, len(rx_data)-16), len(rx_data))))
        print()

        # -------------------------------------------------------------------
        # 5. Save received image
        # -------------------------------------------------------------------
        out_dir = os.path.dirname(output_path)
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        png_write_grayscale(output_path, out_width, out_height, rx_data)
        print("Saved received image to: {} ({}x{})".format(output_path, out_width, out_height))

    except KeyboardInterrupt:
        print("\nInterrupted by user.")

    except IOError as e:
        print("\nConnection error: {}".format(e))

    finally:
        print()
        print("Closing JTAG Atlantic connection...")
        ja.close()
        print("Done.")


if __name__ == "__main__":
    main()
