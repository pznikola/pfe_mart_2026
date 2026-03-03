// byte_deserializer.v
// Collects bytes from an 8-bit streaming input (little-endian, LSB first)
// and outputs a (NUM_BYTES*8)-bit word once all bytes have arrived.
//
// Parameters:
//   NUM_BYTES - Number of bytes per output word (minimum 1)
//
// Interfaces:
//   Input:  8-bit valid/ready (from JTAG UART RX or similar)
//   Output: (NUM_BYTES*8)-bit valid/ready
//
// Byte order: first byte received = bits [7:0], second = bits [15:8], etc.
// When NUM_BYTES=1, acts as a simple valid/ready register stage.

module byte_deserializer #(
    parameter NUM_BYTES = 4
) (
    input  wire                        clk,
    input  wire                        rst_n,

    // Input byte stream (valid/ready)
    input  wire [7:0]                  in_data,
    input  wire                        in_valid,
    output wire                        in_ready,

    // Output word (valid/ready)
    output wire [NUM_BYTES*8-1:0]      out_data,
    output reg                         out_valid,
    input  wire                        out_ready
);

    localparam WIDTH = NUM_BYTES * 8;

    reg [WIDTH-1:0] shift_reg;

    // Accept input bytes when not holding a completed word
    assign in_ready = !out_valid;
    assign out_data = shift_reg;

    generate
        if (NUM_BYTES == 1) begin : gen_single
            // Single byte: no counter, just register the byte
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

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    shift_reg <= {WIDTH{1'b0}};
                    byte_cnt  <= {CNT_WIDTH{1'b0}};
                    out_valid <= 1'b0;
                end else begin
                    if (out_valid && out_ready) begin
                        out_valid <= 1'b0;
                    end

                    if (in_valid && in_ready) begin
                        // Little-endian: first byte into [7:0], next into [15:8], etc.
                        // Shift new byte in from the top.
                        shift_reg <= {in_data, shift_reg[WIDTH-1:8]};

                        if (byte_cnt == NUM_BYTES[CNT_WIDTH-1:0] - 1'b1) begin
                            byte_cnt  <= {CNT_WIDTH{1'b0}};
                            out_valid <= 1'b1;
                        end else begin
                            byte_cnt <= byte_cnt + 1'b1;
                        end
                    end
                end
            end
        end
    endgenerate

endmodule
