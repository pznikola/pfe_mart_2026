file mkdir reports
file mkdir out
file mkdir tmp
##############################################################################
# TODO: Zadatak 2: Ucitavanje tehnoloskih biblioteka
##############################################################################
set pdk_dir "../ihp13/pdk"
set pdk_cells_lib ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib
set pdk_sram_lib  ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_sram/lib
set pdk_io_lib    ${pdk_dir}/ihp-sg13g2/libs.ref/sg13g2_io/lib

set tech_cells [list "$pdk_cells_lib/sg13g2_stdcell_typ_1p20V_25C.lib"]
set tech_macros [glob -directory $pdk_sram_lib *_typ_1p20V_25C.lib]
lappend tech_macros "$pdk_io_lib/sg13g2_io_typ_1p2V_3p3V_25C.lib"

# svi lib fajlovi
set lib_list [concat [split $tech_cells] [split $tech_macros] ]
set liberty_args_list [lmap lib $lib_list {concat "-liberty" $lib}]
set liberty_args [concat {*}$liberty_args_list]
# only the standard cells
set tech_cells_args_list [lmap lib $tech_cells {concat "-liberty" $lib}]
set tech_cells_args [concat {*}$tech_cells_args_list]

# procitaj library datoteke
foreach file $lib_list {
  yosys read_liberty -lib "$file"
}


##############################################################################
# TODO: Zadatak 3: Ucitavanje dizajna
##############################################################################
yosys plugin -i slang.so
yosys read_slang --no-proc --top pfe_chip -f ./src/pfe.flist --keep-hierarchy

# # ispisivanje u komandnoj liniji
yosys stat 

# generisati izvestaj 'pfe_parsed.rpt' u reports folderu
yosys tee -q -o "reports/pfe_parsed.rpt" stat

# generisati netlistu
yosys write_verilog -norename -noexpr "out/pfe_parsed.v" 

yosys setattr -set keep_hierarchy 1 "t:pfe_soc$*"
yosys setattr -set keep_hierarchy 1 "t:accumulator$*"

yosys blackbox "t:RM_IHPSG13_2P_256x8_c2_bm_bist$*"

##############################################################################
# TODO: Zadatak 4: Elaboracija
##############################################################################
yosys hierarchy -top pfe_chip
yosys check
yosys proc

yosys tee -q -o "reports/pfe_elaborated.rpt" stat
yosys write_verilog -norename -noexpr -attr2comment out/pfe_elaborated.v

##############################################################################
# TODO: Zadatak 5: Gruba sinteza
##############################################################################
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

##############################################################################
# TODO: Zadatak 6: Definisanje taktnog signala
##############################################################################
set period_ps 20000

##############################################################################
# TODO: Zadatak 8: Genericko mapiranje
##############################################################################
yosys techmap
yosys opt
yosys clean -purge

yosys tee -q -o "reports/pfe_generic.rpt" stat -tech cmos
yosys write_verilog -norename -noexpr "out/pfe_generic.v" 

##############################################################################
# TODO: Zadatak 9: Tehnolosko mapiranje
##############################################################################
# Poravnjanje hijerarhije
yosys flatten

# Mapiranje flip-flopova
yosys dfflibmap {*}$tech_cells_args

# Podesavanje abc optimizacije
set abc_comb_script "scripts/abc-opt.script"

# ABC optimizacija
yosys abc {*}$tech_cells_args -D $period_ps \
        -script $abc_comb_script -constr src/pfe.constr {*}[list] -showtmp

yosys clean -purge

##############################################################################
# TODO: Zadatak 10: Priprema za OpenROAD
##############################################################################
# Netlista za debagovanje
yosys write_verilog -norename -noexpr -attr2comment out/pfe_debug.v

# Razdvajanje visebitnih mreza
yosys splitnets -ports -format __v

# Zamena nedefinisanih vrednosti
yosys setundef -zero

# Brisanje nepovezanih kola i zica
yosys clean -purge

# Mapiranje 1 i 0 na odgovarajuce celije
set tech_cell_tiehi {sg13g2_tiehi L_HI}
set tech_cell_tielo {sg13g2_tielo L_LO}
yosys hilomap -singleton -hicell {*}$tech_cell_tiehi -locell {*}$tech_cell_tielo

# Finalni izvestaji
yosys tee -q -o "reports/pfe_synth.rpt" check
yosys tee -q -o "reports/pfe_area.rpt" stat -top pfe_chip {*}$liberty_args
yosys tee -q -o "reports/pfe_area_logic.rpt" stat -top pfe_chip {*}$tech_cells_args

# Finalna netlista
yosys write_verilog -noattr -noexpr -nohex -nodec out/pfe_yosys.v

exit