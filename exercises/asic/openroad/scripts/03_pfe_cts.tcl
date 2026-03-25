###############################################################################
# Zadatak 7: Setup
###############################################################################
source scripts/startup.tcl

load_checkpoint 02_pfe.placed

###############################################################################
# Zadatak 8: CTS
###############################################################################
set_wire_rc -clock -layer Metal3
set_wire_rc -signal -layer Metal3

set dont_use_pads [list sg13g2_IOPad* ]
set_dont_use $dont_use_pads

set clock_nets [get_nets -of_objects [get_pins -of_objects "*_reg" -filter "name == CLK"]]
unset_dont_touch $clock_nets

repair_clock_inverters

set ctsBuf     [ list sg13g2_buf_16 sg13g2_buf_8 sg13g2_buf_4 sg13g2_buf_2 ]
set ctsBufRoot sg13g2_buf_8

clock_tree_synthesis -buf_list $ctsBuf -root_buf $ctsBufRoot \
                     -sink_clustering_enable \
                     -repair_clock_nets

report_clock_skew

detailed_placement 

estimate_parasitics -placement

set_propagated_clock [all_clocks]

report_metrics "03_pfe.cts_unrepaired"

repair_timing -setup -verbose


detailed_placement

check_placement -verbose

estimate_parasitics -placement

report_cts -out_file ${report_dir}/03_pfe.cts.rpt
report_metrics "03_pfe.cts"
report_image "03_pfe.cts" true false true
save_checkpoint 03_pfe.cts
