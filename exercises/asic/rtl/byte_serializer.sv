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
    parameter int unsigned NUM_BYTES = 4
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // Input word
    input  logic [NUM_BYTES*8-1:0] in_data,
    input  logic                   in_valid,
    output logic                   in_ready,

    // Output byte stream
    output logic [7:0]             out_data,
    output logic                   out_valid,
    input  logic                   out_ready
);

    localparam int unsigned WIDTH = NUM_BYTES * 8;

    logic [WIDTH-1:0] shift_reg;
    assign out_data = shift_reg[7:0];

    generate
        if (NUM_BYTES == 1) begin : gen_single
            assign in_ready = !out_valid || out_ready;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    shift_reg <= '0;
                    out_valid <= 1'b0;
                end else begin
                    case ({in_valid && in_ready, out_valid && out_ready})
                        2'b00: ;
                        2'b01: out_valid <= 1'b0;
                        2'b10: begin
                            shift_reg <= in_data;
                            out_valid <= 1'b1;
                        end
                        2'b11: begin
                            shift_reg <= in_data;
                            out_valid <= 1'b1;
                        end
                    endcase
                end
            end
        end else begin : gen_multi
            localparam int unsigned CNT_WIDTH = $clog2(NUM_BYTES);

            logic [CNT_WIDTH-1:0] byte_cnt;
            logic                 busy;
            logic                 last_byte;
            logic                 in_fire;
            logic                 out_fire;

            assign last_byte = (byte_cnt == CNT_WIDTH'(NUM_BYTES - 1));
            assign out_fire  = out_valid && out_ready;
            assign in_ready  = !busy || (out_fire && last_byte);
            assign in_fire   = in_valid && in_ready;

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    shift_reg <= '0;
                    byte_cnt  <= '0;
                    busy      <= 1'b0;
                    out_valid <= 1'b0;
                end else begin
                    if (!busy) begin
                        if (in_fire) begin
                            shift_reg <= in_data;
                            byte_cnt  <= '0;
                            busy      <= 1'b1;
                            out_valid <= 1'b1;
                        end
                    end else begin
                        if (out_fire) begin
                            if (last_byte) begin
                                if (in_valid) begin
                                    shift_reg <= in_data;
                                    byte_cnt  <= '0;
                                    busy      <= 1'b1;
                                    out_valid <= 1'b1;
                                end else begin
                                    busy      <= 1'b0;
                                    out_valid <= 1'b0;
                                end
                            end else begin
                                shift_reg <= {8'b0, shift_reg[WIDTH-1:8]};
                                byte_cnt  <= byte_cnt + 1'b1;
                            end
                        end
                    end
                end
            end
        end
    endgenerate

endmodule
