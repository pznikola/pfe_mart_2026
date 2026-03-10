// byte_serializer.v
// Takes a (NUM_BYTES*8)-bit word and sends it as bytes on an 8-bit
// streaming output (little-endian, LSB first) with valid/ready handshaking.
//
// Parameters:
//   NUM_BYTES - Number of bytes per input word (minimum 1)
//
// Interfaces:
//   Input:  (NUM_BYTES*8)-bit valid/ready
//   Output: 8-bit valid/ready (to JTAG UART TX or similar)
//
// Byte order: bits [7:0] sent first, then [15:8], etc.
// When NUM_BYTES=1, acts as a simple valid/ready register stage.

module byte_serializer #(
    parameter NUM_BYTES = 4
) (
    input  wire                        clk,
    input  wire                        rst_n,

    // Input word (valid/ready)
    input  wire [NUM_BYTES*8-1:0]      in_data,
    input  wire                        in_valid,
    output wire                        in_ready,

    // Output byte stream (valid/ready)
    output wire [7:0]                  out_data,
    output reg                         out_valid,
    input  wire                        out_ready
);

    localparam WIDTH = NUM_BYTES * 8;

    reg [WIDTH-1:0] shift_reg;

    // Current byte is always the lowest 8 bits
    assign out_data = shift_reg[7:0];

    generate
        if (NUM_BYTES == 1) begin : gen_single
            // Single byte: no counter, just register the byte
            assign in_ready = !out_valid;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    shift_reg <= 8'd0;
                    out_valid <= 1'b0;
                end else begin
                    if (out_valid && out_ready) begin
                        out_valid <= 1'b0;
                    end
                    if (in_valid && in_ready) begin
                        shift_reg <= in_data;
                        out_valid <= 1'b1;
                    end
                end
            end
        end else begin : gen_multi
            // Multiple bytes: counter + shift register
            localparam CNT_WIDTH = $clog2(NUM_BYTES);
            reg [CNT_WIDTH-1:0] byte_cnt;
            reg                 busy;

            assign in_ready = !busy;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    shift_reg <= {WIDTH{1'b0}};
                    byte_cnt  <= {CNT_WIDTH{1'b0}};
                    busy      <= 1'b0;
                    out_valid <= 1'b0;
                end else begin
                    if (!busy) begin
                        // Idle: latch a new word if available
                        if (in_valid) begin
                            shift_reg <= in_data;
                            byte_cnt  <= {CNT_WIDTH{1'b0}};
                            busy      <= 1'b1;
                            out_valid <= 1'b1;
                        end
                    end else begin
                        // Busy: sending bytes
                        if (out_valid && out_ready) begin
                            if (byte_cnt == NUM_BYTES[CNT_WIDTH-1:0] - 1'b1) begin
                                // Last byte accepted
                                busy      <= 1'b0;
                                out_valid <= 1'b0;
                            end else begin
                                // Shift right to expose next byte (little-endian)
                                shift_reg <= {{8{1'b0}}, shift_reg[WIDTH-1:8]};
                                byte_cnt  <= byte_cnt + 1'b1;
                            end
                        end
                    end
                end
            end
        end
    endgenerate

endmodule
