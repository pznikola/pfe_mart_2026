`timescale 1ns/1ps
`default_nettype none

`ifndef TB_VERBOSE
  `define TB_VERBOSE 0
`endif

`ifndef USE_SRAM
  `define USE_SRAM 1
`endif

module tb_fifo_chip;

  // Print control (1 = lots of prints, 0 = only PASS/ERROR)
  localparam bit VERBOSE = (`TB_VERBOSE != 0);

  localparam DSIZE = 8;
  localparam ASIZE = 8;
  localparam bit USE_SRAM = (`USE_SRAM != 0);

  localparam DEPTH = (1 << ASIZE);

  // fifo_soc contains two FIFOs internally, so total capacity is 2x.
  localparam TOTAL_DEPTH = 2 * DEPTH;

  reg                  clk_i;
  reg                  rst_ni;

  reg                  in_valid_i;
  wire                 in_ready_o;
  reg  [DSIZE-1:0]     in_data_i;

  wire                 out_valid_o;
  reg                  out_ready_i;
  wire [DSIZE-1:0]     out_data_o;

  `ifdef TARGET_NETLIST_YOSYS
  \fifo_soc$fifo_chip.i_fifo_soc dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .in_valid_i(in_valid_i),
    .in_ready_o(in_ready_o),
    .in_data_i_0_(in_data_i[0]),
    .in_data_i_1_(in_data_i[1]),
    .in_data_i_2_(in_data_i[2]),
    .in_data_i_3_(in_data_i[3]),
    .in_data_i_4_(in_data_i[4]),
    .in_data_i_5_(in_data_i[5]),
    .in_data_i_6_(in_data_i[6]),
    .in_data_i_7_(in_data_i[7]),
    .out_valid_o(out_valid_o),
    .out_ready_i(out_ready_i),
    .out_data_o_0_(out_data_o[0]),
    .out_data_o_1_(out_data_o[1]),
    .out_data_o_2_(out_data_o[2]),
    .out_data_o_3_(out_data_o[3]),
    .out_data_o_4_(out_data_o[4]),
    .out_data_o_5_(out_data_o[5]),
    .out_data_o_6_(out_data_o[6]),
    .out_data_o_7_(out_data_o[7])
  );
  `else
  fifo_soc #(
    .DSIZE(DSIZE),
    .ASIZE(ASIZE),
    .USE_SRAM(USE_SRAM)
  ) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .in_valid_i(in_valid_i),
    .in_ready_o(in_ready_o),
    .in_data_i(in_data_i),
    .out_valid_o(out_valid_o),
    .out_ready_i(out_ready_i),
    .out_data_o(out_data_o)
  );
  `endif

  // ---------------------------------------------------------------------------
  // Reference FIFO model
  // ---------------------------------------------------------------------------
  // For the SRAM backend we cannot check valid/ready against a simple count
  // because the DUT has internal pipeline latency.  Instead we use a reference
  // queue to track expected data ordering: push on accepted writes, pop and
  // compare on accepted reads.  This works for both DFF and SRAM backends.
  // ---------------------------------------------------------------------------
  reg [DSIZE-1:0] ref_mem [0:TOTAL_DEPTH-1];
  reg [ASIZE:0]   ref_wr_ptr, ref_rd_ptr;
  reg [ASIZE+1:0] ref_count;

  integer i;

  // Waveform dump
  initial begin
    $dumpfile("tb_fifo_chip.vcd");
    $dumpvars(0, tb_fifo_chip);
  end

  // Clock
  initial begin
    clk_i = 1'b0;
    forever #50 clk_i = ~clk_i;
  end

  // Reset + init
  initial begin
    rst_ni      = 1'b0;
    in_valid_i  = 1'b0;
    out_ready_i = 1'b0;
    in_data_i   = {DSIZE{1'b0}};

    ref_wr_ptr  = '0;
    ref_rd_ptr  = '0;
    ref_count   = '0;
    for (i = 0; i < TOTAL_DEPTH; i = i + 1)
      ref_mem[i] = {DSIZE{1'b0}};

    #100;
    rst_ni = 1'b0;
    #150;
    rst_ni = 1'b1;

    if (VERBOSE) $display("[%0t] Reset deasserted", $time);
  end

  // Random stimulus
  initial begin
    @(posedge rst_ni);

    for (i = 0; i < 2000; i = i + 1) begin
      @(negedge clk_i);

      in_valid_i  = 1'($random & 1);
      out_ready_i = 1'($random & 1);
      in_data_i   = DSIZE'($random);

      if (VERBOSE) begin
        $display("[%0t] APPLY: in_valid=%0b in_data=0x%0h | in_ready=%0b || out_valid=%0b out_ready=%0b out_data=0x%0h",
                 $time, in_valid_i, in_data_i, in_ready_o, out_valid_o, out_ready_i, out_data_o);
      end
    end

    @(negedge clk_i);
    in_valid_i  = 1'b0;
    out_ready_i = 1'b1;

    // Drain remaining entries.  Gate-level netlist with two SRAM-backed FIFOs
    // needs significant drain time due to pipeline latency and propagation.
    // Use 4*TOTAL_DEPTH to be safe across all backends.
    repeat (4 * TOTAL_DEPTH + 50) @(posedge clk_i);

    if (ref_count !== 0) begin
      $display("ERROR: ref_count=%0d at end of test (expected 0)", ref_count);
      $fatal;
    end

    $display("TEST DONE - no mismatches detected.");
    $finish;
  end

  // ---------------------------------------------------------------------------
  // Scoreboard — data-ordering check
  // ---------------------------------------------------------------------------
  // Push into the reference queue when the DUT accepts a write (handshake).
  // Pop from the reference queue when the DUT produces a read (handshake)
  // and compare data.  No cycle-accurate valid/ready checking — only data
  // ordering and values are verified, which is correct for any internal
  // pipeline depth.
  // ---------------------------------------------------------------------------
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ref_wr_ptr <= '0;
      ref_rd_ptr <= '0;
      ref_count  <= '0;
    end else begin
      reg do_push;
      reg do_pop;
      reg [DSIZE-1:0] exp_out;

      // Observe actual DUT handshakes
      do_push = in_valid_i  & in_ready_o;
      do_pop  = out_valid_o & out_ready_i;

      // Data check on pop
      exp_out = ref_mem[ref_rd_ptr];
      if (do_pop) begin
        if (VERBOSE) begin
          $display("[%0t] POP : got=0x%0h exp=0x%0h @ref_rd_ptr=%0d (ref_count=%0d)",
                   $time, out_data_o, exp_out, ref_rd_ptr, ref_count);
        end
        if (out_data_o !== exp_out) begin
          $display("DATA MISMATCH @%0t: got=0x%0h exp=0x%0h (ref_rd_ptr=%0d ref_count=%0d)",
                   $time, out_data_o, exp_out, ref_rd_ptr, ref_count);
          $fatal;
        end
      end

      // Push into reference
      if (do_push) begin
        if (VERBOSE) begin
          $display("[%0t] PUSH: data=0x%0h @ref_wr_ptr=%0d (ref_count=%0d)",
                   $time, in_data_i, ref_wr_ptr, ref_count);
        end
        ref_mem[ref_wr_ptr] <= in_data_i;
        ref_wr_ptr <= ref_wr_ptr + 1;
      end

      // Pop pointer update
      if (do_pop) begin
        ref_rd_ptr <= ref_rd_ptr + 1;
      end

      // Update count
      case ({do_push, do_pop})
        2'b10: ref_count <= ref_count + 1;
        2'b01: ref_count <= ref_count - 1;
        default: ref_count <= ref_count;
      endcase

      if (VERBOSE) begin
        if (in_valid_i && !in_ready_o)
          $display("[%0t] PUSH BLOCKED (FULL)  ref_count=%0d", $time, ref_count);
        if (out_ready_i && !out_valid_o)
          $display("[%0t] POP  BLOCKED (EMPTY) ref_count=%0d", $time, ref_count);
      end
    end
  end

endmodule

`default_nettype wire
