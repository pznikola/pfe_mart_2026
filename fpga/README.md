# DE1-SoC JTAG UART Project — README

## Project Overview

This project implements a JTAG UART communication pipeline on the DE1-SoC (Cyclone V, 5CSEMA5F31C6). Data flows from a host PC through the JTAG UART into a processing module (PFE / accumulator), and the result is sent back to the PC.

### File Summary

| File | Role |
|------|------|
| `rtl/jtag_uart_top.v` | **Top-level module** — instantiates all submodules and defines all board-level I/O ports |
| `rtl/jtag_uart_controller.v` | FSM that drives the Avalon-MM bus to read/write the JTAG UART IP |
| `rtl/fifo.v` | Generic synchronous FIFO with valid/ready handshaking |
| `rtl/pfe.sv` | PFE -- passthrough, edit this file |
| `rtl/byte_deserializer.sv` | Collects individual bytes into a wider word |
| `rtl/byte_serializer.sv` | Breaks a wide word back into individual bytes |
| `setup_project.tcl` | Quartus project setup script -- **contains all pin assignments** |
| `jtag_uart_qsys.tcl` | Platform Designer (Qsys) script -- generates the JTAG UART IP system |
| `timing.sdc` | Timing constraints (clock definition, false paths) |
| `build.sh` | Main build script -- handles Qsys generation, project setup, compilation, and programming |
| `Makefile` | Convenience targets wrapping `build.sh` and Verilator simulations |

---

## How to Add New I/O Signals (Buttons, LEDs, 7-Segment, etc.)

Adding new board I/O requires changes in **two files**. Optionally, a third file may need a small update.

### Step 1 — Add the port to the top-level module

**File to edit:** `rtl/jtag_uart_top.v`

The top-level module `jtag_uart_top` is where every physical pin on the FPGA is declared. Currently it only has two ports:

```verilog
module jtag_uart_top (
    input wire CLOCK_50,
    input wire RSTN
);
```

To add new I/O, extend this port list. For example, to add the DE1-SoC's 10 switches, 4 push-buttons, 10 red LEDs, and six 7-segment displays:

```verilog
module jtag_uart_top (
    input  wire        CLOCK_50,
    input  wire        RSTN,

    // New I/O
    input  wire [9:0]  SW,          // 10 slide switches
    input  wire [3:0]  KEY,         // 4 push-buttons (active low)
    output wire [9:0]  LEDR,        // 10 red LEDs
    output wire [6:0]  HEX0,        // 7-segment digit 0
    output wire [6:0]  HEX1,        // 7-segment digit 1
    output wire [6:0]  HEX2,        // 7-segment digit 2
    output wire [6:0]  HEX3,        // 7-segment digit 3
    output wire [6:0]  HEX4,        // 7-segment digit 4
    output wire [6:0]  HEX5         // 7-segment digit 5
);
```

You can then use these signals anywhere inside the module body — connect them to your processing logic, tie LEDs to switch values, drive 7-segment decoders, etc.

### Step 2 — Add pin location assignments (constraints)

**File to edit:** `setup_project.tcl`

This is the **only file** that contains pin-to-FPGA-pad mappings. Currently it assigns just the clock and reset:

```tcl
# --- CLOCK_50 ---
set_location_assignment PIN_AF14 -to CLOCK_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CLOCK_50

# --- RESET_N ---
set_location_assignment PIN_AA14 -to RSTN
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to RSTN
```

For every new port you added in Step 1, you need a matching `set_location_assignment` and `set_instance_assignment` block here. The pin names come from the DE1-SoC User Manual. For example:

```tcl
# --- Slide switches ---
set_location_assignment PIN_AB12 -to SW[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW[0]
set_location_assignment PIN_AC12 -to SW[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW[1]
# ... SW[2] through SW[9] ...

# --- Push-buttons ---
set_location_assignment PIN_AA14 -to KEY[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to KEY[0]
# ... KEY[1] through KEY[3] ...

# --- Red LEDs ---
set_location_assignment PIN_V16  -to LEDR[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDR[0]
# ... LEDR[1] through LEDR[9] ...

# --- 7-Segment display HEX0 ---
set_location_assignment PIN_AE26 -to HEX0[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX0[0]
# ... HEX0[1] through HEX0[6], then HEX1–HEX5 ...
```

> **Important:** Always look up the correct pin numbers in the [DE1-SoC User Manual](https://www.terasic.com.tw/cgi-bin/page/archive.pl?No=836) (Chapter 3, Pin Assignments tables). The pin names shown above are examples — verify them against the manual for your board revision.

### Step 3 (optional) — Update timing constraints

**File to edit:** `timing.sdc`

For simple I/O like switches, buttons, and LEDs, you typically do **not** need to add timing constraints — they are asynchronous or slow-changing signals. However, if you want to suppress Quartus timing warnings on these pins, you can add false-path declarations:

```tcl
set_false_path -from [get_ports {SW[*]}]  -to *
set_false_path -from [get_ports {KEY[*]}] -to *
set_false_path -from *  -to [get_ports {LEDR[*]}]
set_false_path -from *  -to [get_ports {HEX0[*]}]
# ... and so on for HEX1–HEX5
```

---

## Quick-Reference: Which File Does What

| Task | File |
|------|------|
| Declare a new board-level I/O port | `rtl/jtag_uart_top.v` — add to the module port list |
| Assign an FPGA pin location to that port | `setup_project.tcl` — add `set_location_assignment` and `set_instance_assignment` |
| Constrain or exclude timing on new I/O | `timing.sdc` — add `set_false_path` or other SDC commands |
| Add new RTL source files to the project | `setup_project.tcl` — add a `set_global_assignment -name VERILOG_FILE` line |
| Modify the JTAG UART IP or Qsys system | `jtag_uart_qsys.tcl` |
| Build / program / open GUI | `build.sh` (or use `Makefile` targets) |
| Run Verilator simulations | `Makefile` — `make sim_fifo`, `make sim_all`, etc. |

---

## Building, Programming, and Simulating

### Using the Makefile (recommended)

| Command | What it does |
|---------|--------------|
| `make q_build` | Clean and full build (Qsys → project setup → compile) |
| `make q_program` | Clean build **and** program the FPGA |
| `make q_program_only` | Program the FPGA with the last compiled bitstream (no rebuild) |
| `make q_open` | Open the existing project in the Quartus GUI |
| `make q_clean` | Remove all generated files |
| `make connect` | Open a JTAG UART terminal to the FPGA (`jtag_uart_raw.py`) |
| `make clean` | Remove simulation build artifacts **and** Quartus generated files |

### Using build.sh directly

```bash
./build.sh                  # Full build (Qsys + project + compile)
./build.sh --program        # Full build then program the FPGA
./build.sh --prog           # Program only (skip build)
./build.sh --clean          # Clean all generated files, then rebuild
./build.sh --clean-only     # Clean all generated files and exit
./build.sh --gui            # Set up project and open Quartus GUI
./build.sh --open           # Open existing project in Quartus GUI
```

### Verilator Simulations

Individual module testbenches can be run with Verilator. Testbench sources live in the `dv/` directory.

| Command | Module under test |
|---------|-------------------|
| `make sim_fifo` | `fifo.v` |
| `make sim_deser` | `byte_deserializer.sv` |
| `make sim_ser` | `byte_serializer.sv` |
| `make sim_jtag` | `jtag_uart_controller.v` (with `jtag_uart_model.v`) |
| `make sim_acc` | `accumulator.sv` |
| `make sim_all` | Run **all** of the above in sequence |

Set `VERBOSE=0` for quieter output: `make sim_fifo VERBOSE=0`

# There is a simpler solution for your troubles in the `simulacija_primer` folder!!!