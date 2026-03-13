# FIFO chip backend constraints for Yosys/OpenROAD
# Single-clock top with one external stream input and one external stream output



#############################
## Driving Cells and Loads ##
#############################
# Reasonable default assumptions for pad-limited chip IO.
# External drivers are modeled as SG13 output pads driving this chip's inputs.
# External loads are modeled as modest off-chip load on this chip's outputs.
set_load 15.0 [all_outputs]
set_driving_cell -lib_cell sg13g2_IOPadOut16mA -pin pad [get_ports [list \
  rst_ni \
  in_valid_i \
  out_ready_i \
  in_data_0_i in_data_1_i in_data_2_i in_data_3_i \
  in_data_4_i in_data_5_i in_data_6_i in_data_7_i \
]]

##################
## Input Clocks ##
##################
puts "Clocks..."

# 50 MHz system clock
set TCK_SYS 20.0
create_clock -name clk_sys -period $TCK_SYS [get_ports clk_i]

# Reasonable clock quality assumptions
set_clock_uncertainty 0.10 [get_clocks clk_sys]
set_clock_transition  0.20 [get_clocks clk_sys]

#############
## Resets   ##
#############
puts "Reset..."
# Treat reset as asynchronous for timing closure.
set_false_path -from [get_ports rst_ni]
set_input_delay -clock clk_sys -max 1.0 [get_ports rst_ni]
set_input_delay -clock clk_sys -min 0.0 [get_ports rst_ni]

#############
## Inputs   ##
#############
puts "Inputs..."
# Input stream arriving from external logic.
set_input_delay  -clock clk_sys -min 1.0 [get_ports {in_valid_i out_ready_i in_data_*_i}]
set_input_delay  -clock clk_sys -max 3.0 [get_ports {in_valid_i out_ready_i in_data_*_i}]

#############
## Outputs  ##
#############
puts "Outputs..."
# Output stream observed by external logic.
set_output_delay -clock clk_sys -min 1.0 [get_ports {in_ready_o out_valid_o out_data_*_o unused*_o}]
set_output_delay -clock clk_sys -max 3.0 [get_ports {in_ready_o out_valid_o out_data_*_o unused*_o}]

