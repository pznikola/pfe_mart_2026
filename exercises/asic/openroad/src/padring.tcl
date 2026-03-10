# Copyright (c) 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

#
# - The "#pin no.: nn" comment shows the corresponding pin number for the package.

# [QFN48]
#                   package die
#   pins               24    32
#   I/O                22    22
#   Core power          4     4
#   Core ground         -     4
#   Pad  power          4     4
#   Pad  ground         -     4
#
# pad pitch (min)    90.0  90.0
#
# Chip geometry comes from floorplan.tcl
# Keep only the pad positioning/spacing here

# Positioning for every edge works like this:
#   - the IO site spans the entire edge
#   - pads start cornerToPad microns away from the corner (pad -> bond -> gap)
#   - the remaining usable edge length is split into (numPads-1) equal gaps

set numPadsPerEdge 10
# corner width is equal to padD, bondpad outside
set cornerToPad [expr {$padBond + $padD}]

make_io_sites -horizontal_site sg13g2_ioSite \
    -vertical_site sg13g2_ioSite \
    -corner_site sg13g2_ioSite \
    -offset $padBond \
    -rotation_horizontal R0 \
    -rotation_vertical R0 \
    -rotation_corner R0

##########################################################################
# Edge: LEFT (top to bottom)                                             #
# Keep start of in_* group here.                                         #
##########################################################################
set westSpan  [expr {$chipH - 2*$cornerToPad - $padW}]
set westPitch [expr {floor($westSpan / double($numPadsPerEdge - 1))}]
set westStart [expr {$chipH - $cornerToPad - $padW}]

place_pad -row IO_WEST -location [expr {$westStart -  0*$westPitch}] "pad_vssio0"
place_pad -row IO_WEST -location [expr {$westStart -  1*$westPitch}] "pad_vddio0"
place_pad -row IO_WEST -location [expr {$westStart -  2*$westPitch}] "pad_in_data_0_i"
place_pad -row IO_WEST -location [expr {$westStart -  3*$westPitch}] "pad_in_data_1_i"
place_pad -row IO_WEST -location [expr {$westStart -  4*$westPitch}] "pad_in_data_2_i"
place_pad -row IO_WEST -location [expr {$westStart -  5*$westPitch}] "pad_in_data_3_i"
place_pad -row IO_WEST -location [expr {$westStart -  6*$westPitch}] "pad_in_data_4_i"
place_pad -row IO_WEST -location [expr {$westStart -  7*$westPitch}] "pad_in_data_5_i"
place_pad -row IO_WEST -location [expr {$westStart -  8*$westPitch}] "pad_vss0"
place_pad -row IO_WEST -location [expr {$westStart -  9*$westPitch}] "pad_vdd0"

##########################################################################
# Edge: BOTTOM (left to right)                                           #
# Continue the in_* group here.                                          #
##########################################################################
set southSpan  [expr {$chipW - 2*$cornerToPad - $padW}]
set southPitch [expr {floor($southSpan / double($numPadsPerEdge - 1))}]
set southStart $cornerToPad

place_pad -row IO_SOUTH -location [expr {$southStart +  0*$southPitch}] "pad_vssio1"
place_pad -row IO_SOUTH -location [expr {$southStart +  1*$southPitch}] "pad_vddio1"
place_pad -row IO_SOUTH -location [expr {$southStart +  2*$southPitch}] "pad_in_data_6_i"
place_pad -row IO_SOUTH -location [expr {$southStart +  3*$southPitch}] "pad_in_data_7_i"
place_pad -row IO_SOUTH -location [expr {$southStart +  4*$southPitch}] "pad_in_valid_i"
place_pad -row IO_SOUTH -location [expr {$southStart +  5*$southPitch}] "pad_in_ready_o"
place_pad -row IO_SOUTH -location [expr {$southStart +  6*$southPitch}] "pad_clk_i"
place_pad -row IO_SOUTH -location [expr {$southStart +  7*$southPitch}] "pad_rst_ni"
place_pad -row IO_SOUTH -location [expr {$southStart +  8*$southPitch}] "pad_vss1"
place_pad -row IO_SOUTH -location [expr {$southStart +  9*$southPitch}] "pad_vdd1"

##########################################################################
# Edge: RIGHT (bottom to top)                                            #
# Start of out_* group.                                                  #
##########################################################################
set eastSpan  [expr {$chipH - 2*$cornerToPad - $padW}]
set eastPitch [expr {floor($eastSpan / double($numPadsPerEdge - 1))}]
set eastStart $cornerToPad

place_pad -row IO_EAST -location [expr {$eastStart +  0*$eastPitch}] "pad_vssio2"
place_pad -row IO_EAST -location [expr {$eastStart +  1*$eastPitch}] "pad_vddio2"
place_pad -row IO_EAST -location [expr {$eastStart +  2*$eastPitch}] "pad_out_data_0_o"
place_pad -row IO_EAST -location [expr {$eastStart +  3*$eastPitch}] "pad_out_data_1_o"
place_pad -row IO_EAST -location [expr {$eastStart +  4*$eastPitch}] "pad_out_data_2_o"
place_pad -row IO_EAST -location [expr {$eastStart +  5*$eastPitch}] "pad_out_data_3_o"
place_pad -row IO_EAST -location [expr {$eastStart +  6*$eastPitch}] "pad_out_data_4_o"
place_pad -row IO_EAST -location [expr {$eastStart +  7*$eastPitch}] "pad_out_data_5_o"
place_pad -row IO_EAST -location [expr {$eastStart +  8*$eastPitch}] "pad_vss2"
place_pad -row IO_EAST -location [expr {$eastStart +  9*$eastPitch}] "pad_vdd2"

##########################################################################
# Edge: TOP (right to left)                                              #
# Continue the out_* group here.                                         #
##########################################################################
set northSpan  [expr {$chipW - 2*$cornerToPad - $padW}]
set northPitch [expr {floor($northSpan / double($numPadsPerEdge - 1))}]
set northStart [expr {$chipW - $cornerToPad - $padW}]

place_pad -row IO_NORTH -location [expr {$northStart -  0*$northPitch}] "pad_vssio3"
place_pad -row IO_NORTH -location [expr {$northStart -  1*$northPitch}] "pad_vddio3"
place_pad -row IO_NORTH -location [expr {$northStart -  2*$northPitch}] "pad_out_data_6_o"
place_pad -row IO_NORTH -location [expr {$northStart -  3*$northPitch}] "pad_out_data_7_o"
place_pad -row IO_NORTH -location [expr {$northStart -  4*$northPitch}] "pad_out_valid_o"
place_pad -row IO_NORTH -location [expr {$northStart -  5*$northPitch}] "pad_out_ready_i"
place_pad -row IO_NORTH -location [expr {$northStart -  6*$northPitch}] "pad_unused0_o"
place_pad -row IO_NORTH -location [expr {$northStart -  7*$northPitch}] "pad_unused1_o"
place_pad -row IO_NORTH -location [expr {$northStart -  8*$northPitch}] "pad_vss3"
place_pad -row IO_NORTH -location [expr {$northStart -  9*$northPitch}] "pad_vdd3"

# Fill in the rest of the padring
place_corners $iocorner

place_io_fill -row IO_NORTH {*}$iofill
place_io_fill -row IO_SOUTH {*}$iofill
place_io_fill -row IO_WEST  {*}$iofill
place_io_fill -row IO_EAST  {*}$iofill

# Connect built-in power rings
connect_by_abutment

# Bondpad integrated into IO cell (or bondpad after OpenROAD):
# tells OpenROAD which IO-Cell pin is the pad and places the IO-terminal
# (the internal concept of an IO) ontop of this pin
# place_io_terminals */pad

# Bondpad as separate cell placed in OpenROAD:
# place the bonding pad relative to the IO cell
place_bondpad -bond $bondPadCell -offset {5.0 -70.0} pad_*

# remove rows created by via make_io_sites as they are no longer needed
remove_io_rows
