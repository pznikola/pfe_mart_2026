#######################################
###### Read Technology Libraries ######
#######################################

# TODO: student task 2
# Read liberty files for standard cells, SRAM macros, and I/O pads

set pdk_dir "../ihp13/pdk"
set pdk_cells_lib ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib
set pdk_sram_lib  ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_sram/lib
set pdk_io_lib    ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_io/lib

set tech_cells [list "$pdk_cells_lib/sg13g2_stdcell_typ_1p20V_25C.lib"]
set tech_macros [glob -directory $pdk_sram_lib *_typ_1p20V_25C.lib]
lappend tech_macros "$pdk_io_lib/sg13g2_io_typ_1p2V_3p3V_25C.lib"

# pre-formated for easier use in yosys commands
# all liberty files
set lib_list [concat [split $tech_cells] [split $tech_macros] ]
set liberty_args_list [lmap lib $lib_list {concat "-liberty" $lib}]
set liberty_args [concat {*}$liberty_args_list]
# only the standard cells
set tech_cells_args_list [lmap lib $tech_cells {concat "-liberty" $lib}]
set tech_cells_args [concat {*}$tech_cells_args_list]

# read library files
foreach file $lib_list {
  yosys read_liberty -lib "$file"
}

#########################
###### Load Design ######
#########################

# TODO: student task 3
# 3.1: Enable Yosys SystemVerilog frontend
# 3.2: Load PFE chip design

yosys plugin -i slang.so
yosys read_slang --no-proc --top pfe_chip -f ./src/pfe.flist --keep-hierarchy

yosys stat
yosys tee -q -o "reports/pfe_parsed.rpt" stat
yosys write_verilog -norename -noexpr "out/pfe_parsed.v" 

# TODO: Preserve
# preserve hierarchy of selected modules/instances
# 't' means type as in select all instances of this type/module
# yosys-slang uniquifies all modules with the naming scheme:
# <module-name>$<instance-name> -> match for t:<module-name>$$
yosys setattr -set keep_hierarchy 1 "t:pfe_soc$*"
yosys setattr -set keep_hierarchy 1 "t:accumulator$*"
yosys setattr -set keep_hierarchy 1 "t:fifo$*"
yosys setattr -set keep_hierarchy 1 "t:pfe$*"

yosys blackbox "t:RM_IHPSG13_2P_256x8_c2_bm_bist$*"

#########################
###### Elaboration ######
#########################

# TODO: student task 4
# 5.1 Resolve design hierarchy 
# 5.2 Convert processes to netlists
# 5.3 Export report and netlist

yosys hierarchy -top pfe_chip
yosys check
yosys proc
yosys tee -q -o "reports/pfe_elaborated.rpt" stat
yosys write_verilog -norename -noexpr -attr2comment out/pfe_elaborated.v

####################################
###### Coarse-grain Synthesis ######
####################################

# TODO: student task 5
# 6.1 Early-stage design check
# 6.2 First opt pass (no FF)
# 6.3 Extract FSM and write report
# 6.4 Perform wreduce
# 6.3 Infer memories and optimize register-files
# 6.4 Optimize flip-flops

yosys check
yosys opt -noff
yosys fsm
yosys write_verilog -norename -noexpr out/pfe_postfsm.v
yosys tee -q -o "reports/pfe_postfsm.rpt" stat -width -tech cmos

yosys wreduce 
yosys peepopt
yosys opt_clean
yosys opt -full
yosys share
yosys opt

yosys memory -nomap
yosys memory_map
yosys opt -fast

yosys opt_dff -sat -nodffe -nosdff
yosys opt -full
yosys clean -purge

# reports optional
yosys tee -q -o "reports/pfe_abstract.rpt" stat -width -tech cmos
yosys write_verilog -norename -noexpr "out/pfe_abstract.v" 

###########################################
###### Define target clock frequency ######
###########################################

# TODO: student task 6
# 7.1 Define clock period variable

set period_ps 20000

##################################
###### Fine-grain synthesis ######
##################################

# TODO: student task 9
# 9.1 Generic cell substitution
# 9.2 Generate report

yosys techmap
yosys opt
yosys clean -purge

yosys tee -q -o "reports/pfe_generic.rpt" stat -tech cmos
yosys write_verilog -norename -noexpr "out/pfe_generic.v" 

################################
###### Technology Mapping ######
################################

# TODO: student task 10
# 10.1 Register mapping
# 10.2 Generate a report
# 10.3 Combinational logic mapping
# 10.4 Export netlist

# Before flattening the hierarchy to allow cross-module optimizations,
# preserve hierarchy of selected modules/instances.
# 't' means type as in select all instances of this type/module
# yosys-slang uniquifies all modules with the naming scheme:
# <module-name>$<instance-name> -> match for t:<module-name>$$
# Examples:
# yosys setattr -set keep_hierarchy 1 "t:croc_soc$*"
# yosys setattr -set keep_hierarchy 1 "t:cdc_*$*"

# TODO: student task 12 & 13
# 12.1 Flatten design

# flatten all hierarchy except marked modules
yosys flatten

# first map flip-flops
yosys dfflibmap {*}$tech_cells_args

# then perform bit-level optimization and mapping on all combinational clouds in ABC
# pre-process abc file (written to tmp directory)
set abc_comb_script   "scripts/abc-opt.script"
# call ABC
yosys abc {*}$tech_cells_args -D $period_ps -script $abc_comb_script -constr src/pfe.constr {*}[list] -showtmp

yosys clean -purge

#######################################
###### Prepare for OpenROAD flow ######
#######################################

# TODO: student task 14
# 14.1 Split multi-bit nets
# 14.2 Replace undefined constants
# 14.3 Replace constant bits with driver cells
# 14.4 Export

# -----------------------------------------------------------------------------
# prep for openROAD
yosys write_verilog -norename -noexpr -attr2comment out/netlist_debug.v

yosys splitnets -ports -format __v
yosys setundef -zero
yosys clean -purge
# map constants to tie cells
set tech_cell_tiehi {sg13g2_tiehi L_HI}
set tech_cell_tielo {sg13g2_tielo L_LO}
yosys hilomap -singleton -hicell {*}$tech_cell_tiehi -locell {*}$tech_cell_tielo

# final reports
yosys tee -q -o "reports/pfe_synth.rpt" check
yosys tee -q -o "reports/pfe_area.rpt" stat -top pfe_chip {*}$liberty_args
yosys tee -q -o "reports/pfe_area_logic.rpt" stat -top pfe_chip {*}$tech_cells_args

# final netlist
yosys write_verilog -noattr -noexpr -nohex -nodec out/pfe_yosys.v

exit

