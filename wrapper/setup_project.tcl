# setup_project.tcl
# Creates the Quartus project with only clock and reset pins.
# Run with: quartus_sh -t setup_project.tcl

package require ::quartus::project

set project_name "jtag_uart_project"

if { [project_exists $project_name] } {
    project_open $project_name
} else {
    project_new -revision $project_name $project_name
}

# --- Device ---
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CSEMA5F31C6
set_global_assignment -name TOP_LEVEL_ENTITY jtag_uart_top
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
set_global_assignment -name MAX_CORE_JUNCTION_TEMP 85
set_global_assignment -name ERROR_CHECK_FREQUENCY_DIVISOR 256

# --- Source files ---
set_global_assignment -name VERILOG_FILE jtag_uart_top.v
set_global_assignment -name VERILOG_FILE jtag_uart_controller.v
set_global_assignment -name VERILOG_FILE pfe.v
set_global_assignment -name VERILOG_FILE byte_deserializer.v
set_global_assignment -name VERILOG_FILE byte_serializer.v
set_global_assignment -name QIP_FILE jtag_uart_sys/synthesis/jtag_uart_sys.qip
set_global_assignment -name SDC_FILE timing.sdc

# --- CLOCK_50 ---
set_location_assignment PIN_AF14 -to CLOCK_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CLOCK_50

# --- RESET_N ---
set_location_assignment PIN_AA14 -to RSTN
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to RSTN

export_assignments
project_close

puts ""
puts "Project setup complete: $project_name"
puts ""
