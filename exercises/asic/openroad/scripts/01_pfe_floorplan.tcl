###############################################################################
# Zadatak 2: Setup
###############################################################################
source scripts/startup.tcl

read_verilog ../yosys/out/pfe_yosys.v
link_design pfe_chip

read_sdc src/constraints.sdc

check_setup -verbose > reports/01-01_pfe_checks.rpt

report_checks -unconstrained -format end \
    -no_line_splits >> reports/01-01_pfe_checks.rpt
report_checks -path_delay max -format end \
    -no_line_splits >> reports/01-01_pfe_checks.rpt
report_checks -path_delay min -format end \
    -no_line_splits >> reports/01-01_pfe_checks.rpt

source scripts/power_connect.tcl

###############################################################################
# Zadatak 3: Inicijalizacija floorplan-a
###############################################################################

set chipH    1600; # OR die height (top to bottom)
set chipW    1600; # OR die width (left to right)
set padD      180; # pad depth (edge to core)
set padW       80; # pad width (beachfront)
set padBond    70; # bonding pad size
set powerRing  80; # reserved space for power ring

# starting from the outside and working towards the core area on each side
set coreMargin [expr {$padD + $padBond + $powerRing}];

utl::report "Initialize Chip"
# coordinates are lower-left x and y, upper-right x and y
initialize_floorplan -die_area "0 0 $chipW $chipH" \
                     -core_area "$coreMargin $coreMargin [expr $chipW-$coreMargin] [expr $chipH-$coreMargin]" \
                     -site "CoreSite"


###############################################################################
# Zadatak 6: Postavljanje I/O pinova, prvo modifikujte src/pfe_padring.tcl
###############################################################################
source src/pfe_padring.tcl

make_tracks

set siteHeight [ord::dbu_to_microns [[dpl::get_row_site] getHeight]]


###############################################################################
# Zadatak 7: Postavljanje SRAM makro celija
###############################################################################
set bank0_sram0 i_fifo_soc/i_fifo_in.gen_sram.i_sram 
set bank1_sram0 i_fifo_soc/i_fifo_out.gen_sram.i_sram

set RamMaster256x8 [[ord::get_db] findMaster "RM_IHPSG13_2P_256x8_c2_bm_bist"]
set RamSize256x8_W [ord::dbu_to_microns [$RamMaster256x8 getWidth]]
set RamSize256x8_H [ord::dbu_to_microns [$RamMaster256x8 getHeight]]

set coreArea      [ord::get_core_area]
set core_leftX    [lindex $coreArea 0]
set core_bottomY  [lindex $coreArea 1]
set core_rightX   [lindex $coreArea 2]
set core_topY     [lindex $coreArea 3]

set floorPaddingX      10.0
set floorPaddingY      10.0
set floor_leftX       [expr $core_leftX + $floorPaddingX]
set floor_bottomY     [expr $core_bottomY + $floorPaddingY]
set floor_rightX      [expr $core_rightX - $floorPaddingX]
set floor_topY        [expr $core_topY - $floorPaddingY]
set floor_midpointX   [expr $floor_leftX + ($floor_rightX - $floor_leftX)/2]
set floor_midpointY   [expr $floor_bottomY + ($floor_topY - $floor_bottomY)/2]

set sram_gap_x 220

set Y [expr {$floor_midpointY - $RamSize256x8_H/2}]

set X0 [expr {$floor_midpointX - $sram_gap_x/2 - $RamSize256x8_W}]
placeInstance $bank0_sram0 $X0 $Y R0

set X1 [expr {$floor_midpointX + $sram_gap_x/2}]
placeInstance $bank1_sram0 $X1 $Y R0

cut_rows -halo_width_x 2 -halo_width_y 2
###############################################################################
# Zadatak 8: Napajanje
###############################################################################
source scripts/power_grid.tcl

###############################################################################
# Zadatak 9: Checkpoint
###############################################################################
save_checkpoint 01_pfe.floorplan
report_image "01_pfe.floorplan" true
