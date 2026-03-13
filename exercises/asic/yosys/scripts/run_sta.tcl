# Copyright (c) 2026 ASIC Bootcamp
# SPDX-License-Identifier: Apache-2.0
#
# OpenSTA: Load liberty files and run timing analysis
# Uses the same PDK path structure as yosys/scripts/init_tech.tcl

# ── PDK Path Discovery ────────────────────────────────
puts "Loading technology from Github PDK\n"
set pdk_dir "../ihp13/pdk"
set pdk_cells_lib ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib
set pdk_sram_lib  ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_sram/lib
set pdk_io_lib    ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_io/lib


# ── Read Liberty Files ────────────────────────────────
# Standard cells (typical corner)
read_liberty ${pdk_cells_lib}/sg13g2_stdcell_typ_1p20V_25C.lib

# SRAM macros (all typical corner libs)
foreach lib [glob -directory $pdk_sram_lib *_typ_1p20V_25C.lib] {
    read_liberty $lib
}

# IO cells
read_liberty ${pdk_io_lib}/sg13g2_io_typ_1p2V_3p3V_25C.lib

# ── Read Netlist ──────────────────────────────────────
read_verilog ./out/pfe_yosys.v
link_design pfe_chip

# ── Read Constraints (SDC) ────────────────────────────
read_sdc ./scripts/constraints.sdc

# ── Reports ───────────────────────────────────────────
puts "\n══ Worst Hold Path ══"
report_checks -path_delay min -fields {slew cap input_pins nets} -digits 3

puts "\n══ Setup Violations (top 10) ══"
report_checks -path_delay max -slack_max 0 -group_path_count 10 -digits 3

puts "\n══ Hold Violations (top 10) ══"
report_checks -path_delay min -slack_max 0 -group_path_count 10 -digits 3

puts "\n══ Timing Summary ══"
report_tns
report_wns

exit