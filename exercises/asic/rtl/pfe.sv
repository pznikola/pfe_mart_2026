// pfe.v
//
// Processing module with parametrizable word width.
// NUM_BYTES sets the data width: 1 = 8-bit, 2 = 16-bit, 4 = 32-bit, etc.
//
// Currently passes data through unchanged.
// Modify the always block to add your processing.

module pfe #(
    parameter DSIZE = 8
)(
    input  wire             clk_i,
    input  wire             rst_ni,
    // Input word (from deserializer)
    input  wire [DSIZE-1:0] in_data_i,
    input  wire             in_valid_i,
    output wire             in_ready_o,
    // Output word (to serializer)
    output wire [DSIZE-1:0] out_data_o,
    output wire             out_valid_o,
    input  wire             out_ready_i
);

    assign out_data_o  = in_data_i;
    assign out_valid_o = in_valid_i;
    assign  in_ready_o = out_ready_i;

endmodule
