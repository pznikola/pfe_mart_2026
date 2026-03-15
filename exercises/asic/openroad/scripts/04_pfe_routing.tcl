###############################################################################
# Zadatak 9: Setup
###############################################################################
source scripts/startup.tcl

# Load checkpoint from previous stage
load_checkpoint 03_pfe.cts

# Set layers used for estimate_parasitics
set_wire_rc -clock -layer Metal3
set_wire_rc -signal -layer Metal3

set dont_use_pads [list sg13g2_IOPad* ]
set_dont_use $dont_use_pads


###############################################################################
# Zadatak 10: Globalno rutiranje
###############################################################################

# Reduce TM1 to avoid too much routing there (bigger tracks -> bad for routing)

set_routing_layers -signal Metal2-TopMetal1 -clock Metal2-TopMetal1

set_global_routing_layer_adjustment TopMetal1 0.20

global_route -guide_file ${report_dir}/04_pfe_route.guide \
    -congestion_report_file ${report_dir}/04_pfe_route_congestionrpt \
    -allow_congestion


estimate_parasitics -global_routing
report_metrics "04-01_pfe.grt"
report_image "04-01_pfe.grt" true false false true
save_checkpoint 04-01_pfe.grt

###############################################################################
# Zadatak 11: Popravka tajminga
###############################################################################
global_route -start_incremental -allow_congestion

repair_design -verbose
repair_timing -setup -verbose -repair_tns 100
repair_timing -hold -hold_margin 0.1 -verbose -repair_tns 100

detailed_placement

# Route only the modified net by DPL
global_route -end_incremental \
            -guide_file ${report_dir}/04_pfe_route.guide \
            -congestion_report_file ${report_dir}/04_pfe_route_congestion.rpt \
            -allow_congestion \
            -verbose

repair_antennas  -iterations 5

estimate_parasitics -global_routing
report_metrics "04-01_pfe.grt_repaired"
report_image "04-01_pfe.grt_repaired" true true false true
save_checkpoint 04-01_pfe.grt_repaired

###############################################################################
# Zadatak 12: Detaljno rutiranje
###############################################################################

set_thread_count 8

detailed_route -output_drc ${report_dir}/04_pfe_route_drc.rpt \
               -drc_report_iter_step 5 \
               -save_guide_updates \
               -clean_patches \
               -verbose 1

report_metrics "04_pfe.routed"
report_image "04_pfe.routed" true false false true
save_checkpoint 04_pfe.routed

###############################################################################
# Zadatak 13: Zavrsni detalji
###############################################################################
set stdfill [ list sg13g2_fill_8 sg13g2_fill_4 sg13g2_fill_2 sg13g2_fill_1 ]
filler_placement $stdfill

global_connect


report_image "05_pfe.final" true true false true
report_metrics "05_pfe.final"
save_checkpoint 05_pfe.final

write_def                      out/pfe.def
write_verilog -include_pwr_gnd -remove_cells "$stdfill bondpad*" out/pfe_lvs.v
write_verilog                  out/pfe.v
write_db                       out/pfe.odb
write_sdc                      out/pfe.sdc

define_process_corner -ext_model_index 0 X
extract_parasitics -ext_model_file ../ihp13/pdk/ihp-sg13g2/libs.tech/librelane/IHP_rcx_patterns.rules
write_spef out/pfe.spef