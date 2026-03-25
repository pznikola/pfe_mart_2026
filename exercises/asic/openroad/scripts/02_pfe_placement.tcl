###############################################################################
# Zadatak 2: Setup
###############################################################################
source scripts/startup.tcl

load_checkpoint 01_pfe.floorplan

###############################################################################
# Zadatak 3: Priprema
###############################################################################
set_wire_rc -clock -layer Metal3
set_wire_rc -signal -layer Metal3

set dont_use_pads [list sg13g2_IOPad* ]
set_dont_use $dont_use_pads

set clock_nets [get_nets -of_objects [get_pins -of_objects "*_reg" -filter "name == CLK"]]
set_dont_touch $clock_nets

repair_tie_fanout "TIEHI/Y"
repair_tie_fanout "TIELO/Y"

remove_buffers

repair_design -verbose

save_checkpoint 02-01_pfe.pre_place


###############################################################################
# Zadatak 4: Globalno rasporedjivanje
###############################################################################

set_thread_count 8

global_placement -density 0.60

report_metrics "02-02_pfe.gpl1"
report_image "02-02_pfe.gpl1" true true
save_checkpoint 02-02_pfe.gpl1

estimate_parasitics -placement
repair_design -verbose
repair_timing -setup -verbose
save_checkpoint 02-02_pfe.gpl1_repaired

###############################################################################
# Zadatak 5: Globalno rasporedjivanje nastavak
###############################################################################

global_placement -density 0.60 \
                 -routability_driven \
                 -routability_check_overflow 0.30 \
                 -timing_driven

report_metrics "02-02_pfe.gpl2"
report_image "02-02_pfe.gpl2" true true
save_checkpoint 02-02_pfe.gpl2


###############################################################################
# Zadatak 6: Detaljno rasporedjivanje
###############################################################################

detailed_placement

optimize_mirroring

estimate_parasitics -placement

# opciono
repair_design -verbose
repair_timing -setup -verbose
# kraj opcionog

report_metrics "02_pfe.placed"
report_image "02_pfe.placed" true true
save_checkpoint 02_pfe.placed
