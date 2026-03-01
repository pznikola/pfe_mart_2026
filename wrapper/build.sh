#!/bin/bash
# build.sh — Build the JTAG UART project from scratch
#
# Usage:
#   ./build.sh                  Build only
#   ./build.sh --program        Build and program FPGA
#   ./build.sh --clean          Remove generated files and rebuild
#   ./build.sh --gui            Set up project and open Quartus GUI
#   ./build.sh --open           Check if project exists and then open Quartus GUI
#   ./build.sh --sim            Run simulation in batch mode (ModelSim)
#   ./build.sh --sim-gui        Run simulation and open ModelSim GUI with waveforms

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
            echo "Usage: $0 [--program] [--clean] [--clean-only] [--gui] [--open] [--sim] [--sim-gui]"
            echo "  --program     Build and program FPGA"
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

# Resolve ModelSim paths if simulation is requested
if [ $DO_SIM -eq 1 ]; then
    # Find ModelSim-Altera Starter Edition (modelsim_ase) first.
    # Questa requires a separate license — avoid it unless it's all we have.
    MODELSIM_BIN=""
    for candidate in \
        "$QUARTUS_ROOT/modelsim_ase/bin" \
        "$QUARTUS_ROOT/modelsim_ae/bin" \
        "$QUARTUS_ROOT/modelsim/bin"
    do
        if [ -d "$candidate" ] && [ -x "$candidate/vsim" ]; then
            MODELSIM_BIN="$candidate"
            break
        fi
    done

    # Fall back to Questa only if ModelSim not found
    if [ -z "$MODELSIM_BIN" ]; then
        for candidate in \
            "$QUARTUS_ROOT/questa_fse/bin" \
            "$QUARTUS_ROOT/questa_fe/bin"
        do
            if [ -d "$candidate" ] && [ -x "$candidate/vsim" ]; then
                MODELSIM_BIN="$candidate"
                echo "  NOTE: Only Questa found — you may need a license file."
                echo "        Set LM_LICENSE_FILE if you see license errors."
                break
            fi
        done
    fi

    if [ -z "$MODELSIM_BIN" ]; then
        # Last resort: search the entire Quartus tree
        found=$(find "$QUARTUS_ROOT" -path "*/modelsim*/bin/vsim" -type f 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            MODELSIM_BIN=$(dirname "$found")
        fi
    fi

    [ -n "$MODELSIM_BIN" ] || fail "ModelSim not found. Is it installed with Quartus?"

    # Put ModelSim at the FRONT of PATH so it takes priority over Questa
    export PATH="$MODELSIM_BIN:$PATH"
    ok "Simulator: $MODELSIM_BIN"

    for tool in vlib vlog vsim; do
        if [ -x "$MODELSIM_BIN/$tool" ]; then
            ok "$tool  →  $MODELSIM_BIN/$tool"
        else
            fail "$tool not found in $MODELSIM_BIN"
        fi
    done
fi

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
    quartus_pgm -c USB-Blaster -m jtag \
        -o "p;output_files/${PROJECT}.sof@2" || fail "Programming failed"
    ok "FPGA programmed"
fi

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------
step "Done"
echo "  SOF: output_files/${PROJECT}.sof"
echo ""
echo "  To program:  quartus_pgm -c USB-Blaster -m jtag -o \"p;output_files/${PROJECT}.sof@2\""
echo "  To connect:  nios2-terminal --device 2 --instance 0"
echo ""
