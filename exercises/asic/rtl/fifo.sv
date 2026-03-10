module fifo #(
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

  localparam int unsigned Depth = (1 << ASIZE);

  logic [ASIZE:0] wr_ptr_q, wr_ptr_d;
  logic [ASIZE:0] rd_ptr_q, rd_ptr_d;
  logic [ASIZE-1:0] wr_addr, rd_addr;
  logic full, empty;
  logic do_write, do_read;

  assign wr_addr = wr_ptr_q[ASIZE-1:0];
  assign rd_addr = rd_ptr_q[ASIZE-1:0];

  // full/empty and in_ready_o are driven inside the generate blocks
  // because the SRAM backend needs different logic.

  // --------------------------------------------------------------------------
  // DFF backend
  // --------------------------------------------------------------------------
  if (USE_SRAM == 1'b0) begin : gen_dff
    logic [DSIZE-1:0] mem [0:Depth-1];

    // Standard extra-MSB FIFO full/empty detection.
    assign empty = (wr_ptr_q == rd_ptr_q);
    assign full  = (wr_ptr_q[ASIZE] != rd_ptr_q[ASIZE]) &&
                   (wr_ptr_q[ASIZE-1:0] == rd_ptr_q[ASIZE-1:0]);

    // Allow a write when not full, or when a read also happens this cycle.
    assign in_ready_o = ~full | out_ready_i;

    assign out_valid_o = ~empty;
    assign out_data_o  = mem[rd_addr];

    assign do_read  = out_valid_o & out_ready_i;
    assign do_write = in_valid_i & in_ready_o;

    assign wr_ptr_d = do_write ? (wr_ptr_q + 1'b1) : wr_ptr_q;
    assign rd_ptr_d = do_read  ? (rd_ptr_q + 1'b1) : rd_ptr_q;

    always_ff @(posedge clk_i) begin
      if (do_write)
        mem[wr_addr] <= in_data_i;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        wr_ptr_q <= '0;
        rd_ptr_q <= '0;
      end else begin
        wr_ptr_q <= wr_ptr_d;
        rd_ptr_q <= rd_ptr_d;
      end
    end

  end else begin : gen_sram
    // SRAM mode is only valid for this exact macro shape.
    initial begin
      if (DSIZE != 8 || ASIZE != 8)
        $error("fifo: USE_SRAM=1 requires DSIZE=8 and ASIZE=8 for RM_IHPSG13_2P_256x8_c2_bm_bist");
    end

    logic [DSIZE-1:0] sram_b_dout;
    logic             out_valid_q, out_valid_d;
    logic [DSIZE-1:0] out_data_q, out_data_d;
    logic             rd_pending_q, rd_pending_d;
    logic             out_taken;
    logic             out_reg_free;
    logic             can_issue_read;

    // Occupancy counter: tracks data *logically* inside the FIFO, from
    // accepted input handshake to accepted output handshake.  This is the
    // ground truth for full/empty — pointer comparison cannot be used because
    // rd_ptr advances when an SRAM read is issued, which is before the data
    // is actually consumed at the output.
    logic [ASIZE:0] occ_count_q, occ_count_d;
    logic            occ_full, occ_empty;

    assign occ_full  = (occ_count_q == Depth);
    assign occ_empty = (occ_count_q == '0);

    // Use occupancy counter for flow control.
    assign full  = occ_full;
    assign empty = occ_empty;

    // No bypass: in SRAM mode a read takes multiple cycles, so we cannot
    // free a slot in the same cycle a pop happens.
    assign in_ready_o = ~occ_full;

    assign out_taken     = out_valid_q & out_ready_i;
    assign out_reg_free  = ~out_valid_q | out_taken;

    // Determine if there is data inside the SRAM that hasn't been read yet.
    // The SRAM holds data between wr_ptr and rd_ptr; it may be non-empty
    // even when occ_empty is true (if the last entry is in the output reg
    // or in flight via rd_pending).  Use pointer comparison for SRAM-level
    // emptiness.
    logic sram_has_data;
    assign sram_has_data = (wr_ptr_q != rd_ptr_q);

    // Only issue a new SRAM read when the SRAM has unread data, the output
    // register can accept the returning word, and no read is already in
    // flight.
    assign can_issue_read = sram_has_data & out_reg_free & ~rd_pending_q;

    assign do_read  = can_issue_read;
    assign do_write = in_valid_i & in_ready_o;

    assign wr_ptr_d = do_write ? (wr_ptr_q + 1'b1) : wr_ptr_q;
    assign rd_ptr_d = do_read  ? (rd_ptr_q + 1'b1) : rd_ptr_q;

    // Occupancy: increments on input handshake, decrements on output handshake.
    always_comb begin
      occ_count_d = occ_count_q;
      case ({do_write, out_taken})
        2'b10:   occ_count_d = occ_count_q + 1;
        2'b01:   occ_count_d = occ_count_q - 1;
        default: occ_count_d = occ_count_q;
      endcase
    end

    RM_IHPSG13_2P_256x8_c2_bm_bist i_sram (
      .A_CLK       ( clk_i         ),
      .A_MEN       ( do_write      ),
      .A_WEN       ( do_write      ),
      .A_REN       ( 1'b0          ),
      .A_ADDR      ( wr_addr       ),
      .A_DIN       ( in_data_i     ),
      .A_BM        ( {DSIZE{1'b1}} ),
      .A_DOUT      (               ),
      .A_DLY       ( 1'b1          ),

      .A_BIST_EN   ( 1'b0          ),
      .A_BIST_MEN  ( 1'b0          ),
      .A_BIST_WEN  ( 1'b0          ),
      .A_BIST_REN  ( 1'b0          ),
      .A_BIST_CLK  ( 1'b0          ),
      .A_BIST_ADDR ( {ASIZE{1'b0}} ),
      .A_BIST_DIN  ( {DSIZE{1'b0}} ),
      .A_BIST_BM   ( {DSIZE{1'b0}} ),

      .B_CLK       ( clk_i         ),
      .B_MEN       ( do_read       ),
      .B_WEN       ( 1'b0          ),
      .B_REN       ( do_read       ),
      .B_ADDR      ( rd_addr       ),
      .B_DIN       ( {DSIZE{1'b0}} ),
      .B_BM        ( {DSIZE{1'b0}} ),
      .B_DOUT      ( sram_b_dout   ),
      .B_DLY       ( 1'b1          ),

      .B_BIST_EN   ( 1'b0          ),
      .B_BIST_MEN  ( 1'b0          ),
      .B_BIST_WEN  ( 1'b0          ),
      .B_BIST_REN  ( 1'b0          ),
      .B_BIST_CLK  ( 1'b0          ),
      .B_BIST_ADDR ( {ASIZE{1'b0}} ),
      .B_BIST_DIN  ( {DSIZE{1'b0}} ),
      .B_BIST_BM   ( {DSIZE{1'b0}} )
    );

    // Track the 1-cycle read latency.
    assign rd_pending_d = do_read;

    always_comb begin
      out_valid_d = out_valid_q;
      out_data_d  = out_data_q;

      if (rd_pending_q) begin
        out_valid_d = 1'b1;
        out_data_d  = sram_b_dout;
      end else if (out_taken) begin
        out_valid_d = 1'b0;
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        wr_ptr_q     <= '0;
        rd_ptr_q     <= '0;
        rd_pending_q <= 1'b0;
        out_valid_q  <= 1'b0;
        out_data_q   <= '0;
        occ_count_q  <= '0;
      end else begin
        wr_ptr_q     <= wr_ptr_d;
        rd_ptr_q     <= rd_ptr_d;
        rd_pending_q <= rd_pending_d;
        out_valid_q  <= out_valid_d;
        out_data_q   <= out_data_d;
        occ_count_q  <= occ_count_d;
      end
    end

    assign out_valid_o = out_valid_q;
    assign out_data_o  = out_data_q;
  end

endmodule
