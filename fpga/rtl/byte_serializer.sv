// byte_serializer.v
// Takes a (NUM_BYTES*8)-bit word and sends it as bytes on an 8-bit
// streaming output (little-endian, LSB first) with valid/ready handshaking.
//
// Parameters:
//   NUM_BYTES - Number of bytes per input word (minimum 1)
//
// Interfaces:
//   Input:  (NUM_BYTES*8)-bit valid/ready
//   Output: 8-bit valid/ready 
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

    generate
        if (NUM_BYTES == 1) begin : gen_single

            assign in_ready = out_ready;
            assign out_valid = in_valid;
            assign out_data = in_data;

        end else begin : gen_multi
          localparam int unsigned CNT_WIDTH = $clog2(NUM_BYTES);

          logic [WIDTH-1:0]      shreg;
          logic [CNT_WIDTH-1:0]  cnt;
          logic                  active;  // currently serializing

          wire last_byte = active && (cnt == CNT_WIDTH'(NUM_BYTES - 1));

          // Input accepted when idle or finishing last byte
          assign in_ready  = !active || (last_byte && out_ready);
          assign out_valid = active;
          assign out_data  = shreg[7:0];

          always_ff @(posedge clk or negedge rst_n) begin
              if (!rst_n) begin
                  active <= 1'b0;
                  cnt    <= '0;
                  shreg  <= '0;
              end else begin
                  if (!active) begin
                      // Idle — latch new word
                      if (in_valid) begin
                          shreg  <= in_data;
                          cnt    <= '0;
                          active <= 1'b1;
                      end
                  end else if (out_ready) begin
                      if (last_byte) begin
                          // Last byte consumed — try back-to-back load
                          if (in_valid) begin
                              shreg  <= in_data;
                              cnt    <= '0;
                          end else begin
                              active <= 1'b0;
                          end
                      end else begin
                          // Shift right by one byte
                          shreg <= {{8{1'b0}}, shreg[WIDTH-1:8]};
                          cnt   <= cnt + 1'b1;
                      end
                  end
              end
          end
      end
    endgenerate

endmodule
