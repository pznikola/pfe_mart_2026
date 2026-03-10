module fifo_soc #(
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

    // FIFO to PFE and back
    wire             fifo_pfe_valid_w;
    wire             fifo_pfe_ready_w;
    wire [DSIZE-1:0] fifo_pfe_data_w;
    wire             pfe_fifo_valid_w;
    wire             pfe_fifo_ready_w;
    wire [DSIZE-1:0] pfe_fifo_data_w;

  fifo #(
    .DSIZE       ( DSIZE ),
    .ASIZE       ( ASIZE ),
    .USE_SRAM    ( USE_SRAM )
  )
  i_fifo_in (
    .clk_i       ( clk_i            ),
    .rst_ni      ( rst_ni           ),
    .in_valid_i  ( in_valid_i       ),
    .in_ready_o  ( in_ready_o       ),
    .in_data_i   ( in_data_i        ),
    .out_valid_o ( fifo_pfe_valid_w ),
    .out_ready_i ( fifo_pfe_ready_w ),
    .out_data_o  ( fifo_pfe_data_w  )
  );

  // Processing module
  pfe #(
    .DSIZE       (DSIZE)
  ) u_pfe (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .in_valid_i  (fifo_pfe_valid_w),
    .in_ready_o  (fifo_pfe_ready_w),
    .in_data_i   (fifo_pfe_data_w),
    .out_valid_o (pfe_fifo_valid_w),
    .out_ready_i (pfe_fifo_ready_w),
    .out_data_o  (pfe_fifo_data_w)
  );

  fifo #(
    .DSIZE       ( DSIZE ),
    .ASIZE       ( ASIZE ),
    .USE_SRAM    ( USE_SRAM )
  )
  i_fifo_out (
    .clk_i       ( clk_i            ),
    .rst_ni      ( rst_ni           ),
    .in_valid_i  ( pfe_fifo_valid_w ),
    .in_ready_o  ( pfe_fifo_ready_w ),
    .in_data_i   ( pfe_fifo_data_w  ),
    .out_valid_o ( out_valid_o      ),
    .out_ready_i ( out_ready_i      ),
    .out_data_o  ( out_data_o       )
  );

endmodule
