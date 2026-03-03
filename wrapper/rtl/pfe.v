// pfe.v
//
// Processing module with parametrizable word width.
// NUM_BYTES sets the data width: 1 = 8-bit, 2 = 16-bit, 4 = 32-bit, etc.
//
// Currently passes data through unchanged.
// Modify the always block to add your processing.

module pfe #(
    parameter NUM_BYTES = 4
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // Input word (from deserializer)
    input  wire [NUM_BYTES*8-1:0]   in_data,
    input  wire                      in_valid,
    output wire                      in_ready,

    // Output word (to serializer)
    output wire  [NUM_BYTES*8-1:0]   out_data,
    output wire                       out_valid,
    input  wire                       out_ready
);

    assign out_data  = in_data;
    assign out_valid = in_valid;
    assign in_ready  = out_ready;

endmodule
