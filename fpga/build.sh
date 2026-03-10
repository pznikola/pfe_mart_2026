#!/bin/bash
# build.sh — Build the JTAG UART project from scratch
#
# Usage:
#   ./build.sh                  Build only
#   ./build.sh --program        Build and program FPGA
#   ./build.sh --prog           Program FPGA only (skip build)
#   ./build.sh --clean          Remove generated files and rebuild
#   ./build.sh --gui            Set up project and open Quartus GUI
#   ./build.sh --open           Check if project exists and then open Quartus GUI

set -e

PROJECT=jtag_uart_project
QSYS=jtag_uart_sys
DEVICE=5CSEMA5F31C6

DO_PROGRAM=0
DO_CLEAN=0
DO_GUI=0
DO_SIM=0
for arg in "$@"; do
    case $arg in
        --program) DO_PROGRAM=1 ;;
        --prog)
            # Program-only: just flash the existing SOF and exit
            echo -e "\n\033[1;36m=== Programming FPGA (DE1-SoC) ===\033[0m\n"
            SOF="output_files/${PROJECT}.sof"
            if [ ! -f "$SOF" ]; then
                echo -e "\033[0;31m  ✗ No bitstream found at $SOF — run ./build.sh first\033[0m"
                exit 1
            fi
            # Auto-detect cable name from jtagconfig
            CABLE=$(jtagconfig 2>/dev/null | grep -oP '^\d+\)\s+\K.*' | head -1)
            if [ -z "$CABLE" ]; then
                echo -e "\033[0;31m  ✗ No JTAG cable detected. Is the board connected?\033[0m"
                exit 1
            fi
            echo -e "\033[0;32m  ✓ Cable: $CABLE\033[0m"
            quartus_pgm -c "$CABLE" -m jtag \
                -o "p;${SOF}@2" || { echo -e "\033[0;31m  ✗ Programming failed\033[0m"; exit 1; }
            echo -e "\033[0;32m  ✓ FPGA programmed with $SOF\033[0m"
            exit 0 ;;
        --clean)   DO_CLEAN=1   ;;
        --clean-only)
            echo "Removing generated files..."
            rm -rf $QSYS ${QSYS}.qsys ${QSYS}.sopcinfo
            rm -rf output_files db incremental_db
            rm -rf simulation
            rm -f ${PROJECT}.qpf ${PROJECT}.qsf ${PROJECT}.qws
            rm -f *.rpt *.done *.summary *.smsg *.pin *.jdi c5_pin_model_dump.txt
            echo "Done."
            exit 0 ;;
        --gui)     DO_GUI=1     ;;
        --open)
            if [ -f "${PROJECT}.qpf" ]; then
                echo "Opening ${PROJECT}.qpf ..."
                quartus ${PROJECT}.qpf &
            else
                echo "Project not found. Run ./build.sh --gui first."
            fi
            exit 0 ;;
        --help)
            echo "Usage: $0 [--program] [--clean] [--clean-only] [--gui] [--open]"
            echo "  --program     Build and program FPGA"
            echo "  --prog        Program FPGA only (skip build)"
            echo "  --clean       Remove generated files and rebuild"
            echo "  --clean-only  Remove generated files and exit"
            echo "  --gui         Set up project (steps 1-3) and open Quartus GUI"
            echo "  --open        Open existing project in Quartus GUI (no build)"
            exit 0 ;;
    esac
done

step() { echo -e "\n\033[1;36m=== $1 ===\033[0m\n"; }
ok()   { echo -e "\033[0;32m  ✓ $1\033[0m"; }
fail() { echo -e "\033[0;31m  ✗ $1\033[0m"; exit 1; }

# ------------------------------------------------------------------
# Resolve Quartus tool paths
# ------------------------------------------------------------------
step "Resolving tool paths"

QUARTUS_SH=$(which quartus_sh 2>/dev/null) || fail "quartus_sh not found in PATH"
QUARTUS_SH=$(readlink -f "$QUARTUS_SH")
QUARTUS_BIN_DIR=$(dirname "$QUARTUS_SH")
QUARTUS_DIR=$(dirname "$QUARTUS_BIN_DIR")
QUARTUS_ROOT=$(dirname "$QUARTUS_DIR")

ok "Quartus root: $QUARTUS_ROOT"

for candidate in \
    "$QUARTUS_DIR/sopc_builder/bin" \
    "$QUARTUS_ROOT/qsys/bin" \
    "$QUARTUS_DIR/bin" \
    "$QUARTUS_DIR/bin64"
do
    if [ -d "$candidate" ]; then
        export PATH="$PATH:$candidate"
    fi
done

for tool in quartus_sh qsys-script qsys-generate quartus_pgm; do
    if command -v "$tool" &>/dev/null; then
        ok "$tool  →  $(which $tool)"
    else
        found=$(find "$QUARTUS_ROOT" -name "$tool" -type f 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            export PATH="$PATH:$(dirname "$found")"
            ok "$tool  →  $found (auto-detected)"
        else
            fail "$tool not found anywhere under $QUARTUS_ROOT"
        fi
    fi
done

# ------------------------------------------------------------------
# Clean
# ------------------------------------------------------------------
if [ $DO_CLEAN -eq 1 ]; then
    step "Cleaning"
    rm -rf $QSYS ${QSYS}.qsys ${QSYS}.sopcinfo
    rm -rf output_files db incremental_db
    rm -rf simulation
    rm -f ${PROJECT}.qpf ${PROJECT}.qsf
    rm -f *.rpt *.done *.summary *.smsg *.pin *.jdi c5_pin_model_dump.txt
    ok "Clean"
fi



# ------------------------------------------------------------------
# Step 1 — Create Platform Designer system
# ------------------------------------------------------------------
step "Step 1/4: Platform Designer system"
if [ -f "${QSYS}.qsys" ] && [ $DO_CLEAN -eq 0 ]; then
    ok "Already exists, skipping (use --clean to regenerate)"
else
    qsys-script --script=jtag_uart_qsys.tcl || fail "qsys-script failed"
    ok "Created ${QSYS}.qsys"
fi

# ------------------------------------------------------------------
# Step 2 — Generate HDL
# ------------------------------------------------------------------
step "Step 2/4: Generate HDL"
if [ -f "${QSYS}/synthesis/${QSYS}.qip" ] && [ $DO_CLEAN -eq 0 ]; then
    ok "Already generated, skipping"
else
    qsys-generate ${QSYS}.qsys \
        --synthesis=VERILOG \
        --output-directory=${QSYS} \
        --family="Cyclone V" \
        --part=${DEVICE} || fail "qsys-generate failed"
    ok "HDL generated"
fi
[ -f "${QSYS}/synthesis/${QSYS}.qip" ] || fail "QIP file not found"

# ------------------------------------------------------------------
# Step 3 — Create Quartus project
# ------------------------------------------------------------------
step "Step 3/4: Quartus project setup"
quartus_sh -t setup_project.tcl || fail "Project setup failed"
ok "Project ready"

# ------------------------------------------------------------------
# GUI mode — open Quartus and stop here
# ------------------------------------------------------------------
if [ $DO_GUI -eq 1 ]; then
    step "Opening Quartus GUI"
    ok "Project set up — launching Quartus..."
    echo "  You can compile, edit, and program from the GUI."
    echo ""
    quartus ${PROJECT}.qpf &
    exit 0
fi

# ------------------------------------------------------------------
# Step 4 — Compile
# ------------------------------------------------------------------
step "Step 4/4: Compiling (5-15 min)"
quartus_sh --flow compile $PROJECT || fail "Compilation failed"
[ -f "output_files/${PROJECT}.sof" ] || fail "SOF not found"
ok "output_files/${PROJECT}.sof"

# ------------------------------------------------------------------
# Program
# ------------------------------------------------------------------
if [ $DO_PROGRAM -eq 1 ]; then
    step "Programming FPGA"
    CABLE=$(jtagconfig 2>/dev/null | grep -oP '^\d+\)\s+\K.*' | head -1)
    if [ -z "$CABLE" ]; then
        fail "No JTAG cable detected. Is the board connected and jtagd running?"
    fi
    ok "Cable: $CABLE"
    quartus_pgm -c "$CABLE" -m jtag \
        -o "p;output_files/${PROJECT}.sof@2" || fail "Programming failed"
    ok "FPGA programmed"
fi

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------
step "Done"
echo "  SOF: output_files/${PROJECT}.sof"
echo ""
echo "  To program: "
echo "  $ ./build.sh --prog"
echo "  or "
echo "  $ make program-only"
echo "  To connect: "
echo "  $ python3 jtag_uart_raw.py"
echo "  or "
echo "  $ make connect"
echo ""
