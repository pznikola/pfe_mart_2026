module pfe_soc #(
  parameter int unsigned DSIZE    = 8,
  parameter int unsigned ASIZE    = 8,
  parameter bit          USE_SRAM = 1'b1
) (
  input  logic             clk_i,
  input  logic             rst_ni,

  input  logic             in_valid_i,
  output logic             in_ready_o,
  input  logic [DSIZE-1:0] in_data_i,

  output logic             out_valid_o,
  input  logic             out_ready_i,
  output logic [DSIZE-1:0] out_data_o
);

  logic bit_0_r;

  // Simple pass-through handshake
  assign in_ready_o  = out_ready_i;
  assign out_valid_o = in_valid_i;

  // Register bit 0
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      bit_0_r <= 1'b0;
    else
      bit_0_r <= in_data_i[0];
  end

  //  bit 0: registered
  assign out_data_o[0] = bit_0_r;

  // bit 1: invert input bit 1
  assign out_data_o[1] = ~in_data_i[1];

  // bit 2: add bits 2 and 1
  assign out_data_o[2] = in_data_i[2] + in_data_i[1];

  // bit 3: multiply bits 3 and 2
  assign out_data_o[3] = in_data_i[3] * in_data_i[2];

  // bit 4: XOR of bits 4 and 3
  assign out_data_o[4] = (!in_data_i[4] && in_data_i[3]) || (in_data_i[4] && !in_data_i[3]);

  // bit 5: NAND of bits 5 and 4
  assign out_data_o[5] = !(in_data_i[5] && in_data_i[4]);

  // bit 6: NOR of bits 7 and 6
  assign out_data_o[6] = !(in_data_i[7] || in_data_i[6]);

  // bit 7: tie to 1
  assign out_data_o[7] = 1'b1;

endmodule
