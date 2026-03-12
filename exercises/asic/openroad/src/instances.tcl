# pfe_chip-specific SRAM instance discovery
# Two 256x8 SRAM macros.

set macros [list]

# Prefer the dual-port macro, but allow 1P as fallback in case that's what is in the netlist/LEF.
set SRAM_MASTER_CANDIDATES [list \
    "RM_IHPSG13_2P_256x8_c2_bm_bist" \
    "RM_IHPSG13_1P_256x8_c2_bm_bist" \
]

proc resolve_sram_master {candidates} {
    set db [ord::get_db]
    foreach master $candidates {
        set m [$db findMaster $master]
        if {$m != "NULL" && $m != ""} {
            return $master
        }
    }
    return ""
}

proc get_cell_name {cell} {
    if {[catch {set n [get_name $cell]}]} {
        set n $cell
    }
    return $n
}

set SRAM_MASTER [resolve_sram_master $SRAM_MASTER_CANDIDATES]
if {$SRAM_MASTER eq ""} {
    puts stderr "ERROR: Could not resolve any supported 256x8 SRAM master."
    puts stderr "Tried: $SRAM_MASTER_CANDIDATES"
    error "instances.tcl: SRAM master not found"
}

# Collect all hierarchical cells matching the resolved master by ref_name.
set sram_cells [list]
set all_cells [get_cells -hierarchical -quiet *]
foreach c $all_cells {
    set ref_name [get_property $c ref_name]
    if {$ref_name eq $SRAM_MASTER} {
        lappend sram_cells [get_cell_name $c]
    }
}

# Deterministic ordering.
set sram_cells [lsort $sram_cells]

if {[llength $sram_cells] < 1} {
    puts stderr "ERROR: Expected 2 SRAM instances of $SRAM_MASTER, found [llength $sram_cells]."
    puts stderr "Found: $sram_cells"
    error "instances.tcl: insufficient SRAM instances"
}

set bank0_sram0 [lindex $sram_cells 0]
set bank1_sram0 [lindex $sram_cells 1]
set srams [list $bank0_sram0 $bank1_sram0]
set macros $srams

puts "Resolved SRAM macro master:   $SRAM_MASTER"
puts "Resolved SRAM macro instance: $bank0_sram0"
puts "Resolved SRAM macro instance: $bank1_sram0"
puts "Macro list:                  $macros"
