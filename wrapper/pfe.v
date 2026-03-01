// pfe.v
//
// Processing module with parametrizable word width.
// WORD_BYTES sets the data width: 1 = 8-bit, 2 = 16-bit, 4 = 32-bit, etc.
//
// Currently passes data through unchanged.
// Modify the always block to add your processing.

module pfe #(
    parameter WORD_BYTES = 4
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // Input word (from deserializer)
    input  wire [WORD_BYTES*8-1:0]   in_data,
    input  wire                      in_valid,
    output wire                      in_ready,

    // Output word (to serializer)
    output reg  [WORD_BYTES*8-1:0]   out_data,
    output reg                       out_valid,
    input  wire                      out_ready
);

    // Passthrough — modify this for your processing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_data  <= 0;
            out_valid <= 1'b0;
        end else begin
            if (out_valid && out_ready)
                out_valid <= 1'b0;

            if (in_valid && in_ready) begin
                out_data  <= in_data;   // <-- your processing here
                out_valid <= 1'b1;
            end
        end
    end

    assign in_ready = out_ready && !out_valid;

endmodule
