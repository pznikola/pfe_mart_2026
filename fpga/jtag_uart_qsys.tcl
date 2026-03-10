# jtag_uart_qsys.tcl
# Creates a Platform Designer system with clock source + JTAG UART IP.
# The Avalon slave interface is exported so custom Verilog can drive it.
# Run with: qsys-script --script=jtag_uart_qsys.tcl

package require -exact qsys 16.0

create_system jtag_uart_sys

set_project_property DEVICE_FAMILY "Cyclone V"
set_project_property DEVICE 5CSEMA5F31C6

# --- Clock source ---
add_instance clk_0 clock_source
set_instance_parameter_value clk_0 clockFrequency 50000000
set_instance_parameter_value clk_0 clockFrequencyKnown true
set_instance_parameter_value clk_0 resetSynchronousEdges DEASSERT

# Export clock and reset
add_interface clk clock sink
set_interface_property clk EXPORT_OF clk_0.clk_in
add_interface reset reset sink
set_interface_property reset EXPORT_OF clk_0.clk_in_reset

# --- JTAG UART ---
add_instance jtag_uart_0 altera_avalon_jtag_uart
set_instance_parameter_value jtag_uart_0 writeBufferDepth 512
set_instance_parameter_value jtag_uart_0 readBufferDepth 512
set_instance_parameter_value jtag_uart_0 writeIRQThreshold 8
set_instance_parameter_value jtag_uart_0 readIRQThreshold 8
set_instance_parameter_value jtag_uart_0 allowMultipleConnections false

# Connect clock and reset
add_connection clk_0.clk jtag_uart_0.clk
add_connection clk_0.clk_reset jtag_uart_0.reset

# Export the Avalon slave so our Verilog can talk to it
add_interface jtag_uart_avalon avalon slave
set_interface_property jtag_uart_avalon EXPORT_OF jtag_uart_0.avalon_jtag_slave

save_system jtag_uart_sys.qsys
