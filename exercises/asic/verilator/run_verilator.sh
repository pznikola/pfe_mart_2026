#!/bin/bash
# Copyright (c) 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Thomas Benz     <tbenz@iis.ee.ethz.ch>

set -e  # Exit on error
set -u  # Error on undefined vars
set -o pipefail  # Catch errors in pipes


################
# Setup
################
# Source environment
source "../env.sh"


################
# Helpers
################

show_help() {
    cat << EOF
Verilator Coordinator

Usage:
    ./run_verilator.sh [OPTIONS]

Options:
    --help, -h          Show this help message
    --dry-run, -n       Only print commands instead of executing
    --verbose, -v       Print commands while executing
    --flist             Regenerate flist (fifo.f)
    --netlist           Use yosys netlist (tech.f) instead of RTL
    --build             Build Verilator simulation binary
    --run               Run the simulation

Example:
    # Build and run RTL simulation
    ./run_verilator.sh --build --run

    # Build and run gate-level simulation from yosys netlist
    ./run_verilator.sh --netlist --build --run

EOF
    exit 0
}


run_cmd() {
    if [ "$DRYRUN" = 1 ]; then
        echo "$1"
    else
        eval "$1"
    fi
}


build_verilator() {
    echo "[INFO][Verilator] Build Verilator (flist: ${FLIST}, USE_SRAM=${USE_SRAM})"
    run_cmd "verilator \
        -Wno-fatal \
        -Wno-style \
        -Wno-BLKANDNBLK \
        -Wno-WIDTHEXPAND \
        -Wno-WIDTHTRUNC \
        -Wno-WIDTHCONCAT \
        -Wno-ASCRANGE \
        -Wno-TIMESCALEMOD \
        --binary \
        -j 0 \
        --timing \
        --autoflush \
        --trace-fst \
        --trace-threads 2 \
        --trace-structs \
        --unroll-count 1 \
        --unroll-stmts 1 \
        --x-assign fast \
        --x-initial fast \
        -O3 \
        -DUSE_SRAM=${USE_SRAM} \
        --top tb_fifo_chip \
        -f ${FLIST} 2>&1 | \
        tee ${PROJ_NAME}_build.log"
}


generate_flist() {
    echo "[INFO][Bender] Generate fifo.f"
    run_cmd "bender \
        script flist-plus \
        -t rtl \
        -t verilator \
        -t synthesis \
        -D VERILATOR=1 \
        -D COMMON_CELLS_ASSERTS_OFF=1 \
        > fifo.f"

    echo "[INFO][Bender] Remove absolute paths"
    run_cmd "sed -i 's|${FIFO_ROOT}|..|g' fifo.f"

    echo "[INFO][Bender] File list generated: fifo.f"
}

run_sim() {
    echo "[INFO][Verilator] Running simulation"
    run_cmd "obj_dir/Vtb_fifo_chip | tee ${PROJ_NAME}.log"
}


####################
# Parse Arguments
####################

DRYRUN=0
FLIST=fifo.f

# default action if no argument is given
if [ $# -eq 0 ]; then
    show_help
    return 0
fi

# check for global arguments
for arg in "$@"; do
    [[ "$arg" == -v || "$arg" == --verbose ]] && set -x
    [[ "$arg" == -n || "$arg" == --dry-run ]] && DRYRUN=1
    [[ "$arg" == --netlist ]] && FLIST=tech.f
done

# parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            ;;
        --verbose|-v)
            shift
            ;;
        --dry-run|-n)
            shift
            ;;
        --netlist)
            shift
            ;;
        # script-specific commands
        --flist)
            generate_flist
            shift
            ;;
        --build)
            build_verilator
            shift
            ;;
        --run)
            run_sim
            shift
            ;;
        # Error handling
        *)
            echo "[ERROR] Unknown option: $1 (use --help for usage)" >&2
            exit 1
            ;;
    esac
done