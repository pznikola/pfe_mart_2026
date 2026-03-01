// byte_deserializer.v
//
// Collects WORD_BYTES consecutive 8-bit bytes into one wide word.
// First byte received goes into the most significant position (MSB first).
//
// Example with WORD_BYTES=4:
//   Byte 0 → bits[31:24]
//   Byte 1 → bits[23:16]
//   Byte 2 → bits[15:8]
//   Byte 3 → bits[7:0]
//   → out_valid pulses, out_data = full 32-bit word

module byte_deserializer #(
    parameter WORD_BYTES = 4    // 1, 2, 3, 4, ...
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // Byte input (from JTAG UART controller rx)
    input  wire [7:0]                in_data,
    input  wire                      in_valid,
    output wire                      in_ready,

    // Wide word output (to pfe)
    output reg  [WORD_BYTES*8-1:0]   out_data,
    output reg                       out_valid,
    input  wire                      out_ready
);

    localparam W = WORD_BYTES * 8;
    localparam CNT_BITS = (WORD_BYTES == 1) ? 1 : $clog2(WORD_BYTES);

    reg [W-1:0]        shift;
    reg [CNT_BITS:0]   count;  // extra bit so we can count up to WORD_BYTES

    // Accept bytes when we haven't completed a word yet
    assign in_ready = (count < WORD_BYTES) && !(out_valid && !out_ready);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift     <= {W{1'b0}};
            count     <= 0;
            out_data  <= {W{1'b0}};
            out_valid <= 1'b0;
        end else begin
            // Clear out_valid once downstream accepts
            if (out_valid && out_ready) begin
                out_valid <= 1'b0;
            end

            // Shift in bytes
            if (in_valid && in_ready) begin
                shift <= {shift[W-9:0], in_data};  // MSB first: new byte at bottom
                if (count == WORD_BYTES - 1) begin
                    out_data  <= {shift[W-9:0], in_data};
                    out_valid <= 1'b1;
                    count     <= 0;
                end else begin
                    count <= count + 1;
                end
            end
        end
    end
endmodule
