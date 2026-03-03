// byte_serializer.v
//
// Breaks one wide word into WORD_BYTES consecutive 8-bit bytes.
// Sends most significant byte first.
//
// Example with WORD_BYTES=4, in_data = 32'hDEADBEEF:
//   Byte 0 = 0xDE
//   Byte 1 = 0xAD
//   Byte 2 = 0xBE
//   Byte 3 = 0xEF

module byte_serializer #(
    parameter WORD_BYTES = 4
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // Wide word input (from pfe)
    input  wire [WORD_BYTES*8-1:0]   in_data,
    input  wire                      in_valid,
    output wire                      in_ready,

    // Byte output (to JTAG UART controller tx)
    output wire  [7:0]                out_data,
    output wire                       out_valid,
    input  wire                      out_ready
);

    assign out_data = in_data;
    assign out_valid = in_valid;
    assign in_ready = out_ready;
    
    // localparam W = WORD_BYTES * 8;
    // localparam CNT_BITS = (WORD_BYTES == 1) ? 1 : $clog2(WORD_BYTES);

    // reg [W-1:0]        shift;
    // reg [CNT_BITS:0]   count;  // bytes remaining to send
    // reg                busy;

    // // Accept a new word only when idle
    // assign in_ready = !busy;

    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         shift     <= {W{1'b0}};
    //         count     <= 0;
    //         busy      <= 1'b0;
    //         out_data  <= 8'd0;
    //         out_valid <= 1'b0;
    //     end else begin
    //         if (!busy) begin
    //             // Latch new word
    //             if (in_valid) begin
    //                 shift     <= in_data;
    //                 count     <= WORD_BYTES;
    //                 busy      <= 1'b1;
    //                 // Output first byte (MSB) immediately
    //                 out_data  <= in_data[W-1 -: 8];
    //                 out_valid <= 1'b1;
    //             end
    //         end else begin
    //             // Sending bytes
    //             if (out_valid && out_ready) begin
    //                 if (count == 1) begin
    //                     // Last byte accepted
    //                     out_valid <= 1'b0;
    //                     busy      <= 1'b0;
    //                     count     <= 0;
    //                 end else begin
    //                     // Shift left, output next byte
    //                     shift     <= {shift[W-9:0], 8'd0};
    //                     out_data  <= shift[W-9 -: 8];
    //                     count     <= count - 1;
    //                 end
    //             end
    //         end
    //     end
    // end
endmodule
