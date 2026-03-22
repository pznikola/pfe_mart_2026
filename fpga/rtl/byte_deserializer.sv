// byte_deserializer.v
// Collects bytes from an 8-bit streaming input (little-endian, LSB first)
// and outputs a (NUM_BYTES*8)-bit word once all bytes have arrived.
//
// Parameters:
//   NUM_BYTES - Number of bytes per output word (minimum 1)
//
// Interfaces:
//   Input:  8-bit valid/ready 
//   Output: (NUM_BYTES*8)-bit valid/ready
//
// Byte order: first byte received = bits [7:0], second = bits [15:8], etc.
// When NUM_BYTES=1, acts as a simple valid/ready register stage.

module byte_deserializer #(
    parameter int unsigned NUM_BYTES = 4
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // Input byte stream
    input  logic [7:0]             in_data,
    input  logic                   in_valid,
    output logic                   in_ready,

    // Output word
    output logic [NUM_BYTES*8-1:0] out_data,
    output logic                   out_valid,
    input  logic                   out_ready
);

    localparam int unsigned WIDTH = NUM_BYTES * 8;

    logic [WIDTH-1:0] shift_reg;
    assign out_data = shift_reg;

    generate
        if (NUM_BYTES == 1) begin : gen_single

            assign in_ready = out_ready;
            assign out_valid = in_valid;
            assign out_data = in_data;

        end else begin : gen_multi
          localparam int unsigned CNT_WIDTH = $clog2(NUM_BYTES);

          logic [CNT_WIDTH-1:0] cnt;
          logic                 full;  // all bytes collected

          wire last_byte = (cnt == CNT_WIDTH'(NUM_BYTES - 1));

          // Accept input when not full, or when full word is being consumed this cycle
          assign in_ready  = !full || out_ready;
          assign out_valid = full;

          always_ff @(posedge clk or negedge rst_n) begin
              if (!rst_n) begin
                  full      <= 1'b0;
                  cnt       <= '0;
                  shift_reg <= '0;
              end else begin
                  if (full && out_ready) begin
                      // Output word consumed
                      full <= 1'b0;
                  end

                  if (in_valid && in_ready) begin
                      // Shift new byte into MSB side, pushing earlier bytes down
                      shift_reg <= {in_data, shift_reg[WIDTH-1:8]};

                      if (last_byte) begin
                          cnt  <= '0;
                          full <= 1'b1;
                      end else begin
                          cnt <= cnt + 1'b1;
                      end
                  end
              end
          end
      end
    endgenerate

endmodule
