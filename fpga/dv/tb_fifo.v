`timescale 1ns/1ps
`default_nettype none

`ifndef TB_VERBOSE
  `define TB_VERBOSE 0
`endif

module tb_fifo;

  // Print control (1 = lots of prints, 0 = only PASS/ERROR)
  localparam bit VERBOSE = (`TB_VERBOSE != 0);

  localparam DSIZE = 8;
  localparam ASIZE = 4;
  localparam DEPTH = (1 << ASIZE);

  reg                  clk_i;
  reg                  rst_ni;

  reg                  in_valid_i;
  wire                 in_ready_o;
  reg  [DSIZE-1:0]     in_data_i;

  wire                 out_valid_o;
  reg                  out_ready_i;
  wire [DSIZE-1:0]     out_data_o;

  fifo #(
    .DSIZE(DSIZE),
    .ASIZE(ASIZE)
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

  // Reference model (simple ring + count)
  reg [DSIZE-1:0] ref_mem [0:DEPTH-1];
  reg [ASIZE-1:0] ref_wr_ptr, ref_rd_ptr;
  reg [ASIZE:0]   ref_count;

  integer i;

  // Clock
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  // Reset + init
  initial begin
    rst_ni      = 1'b0;
    in_valid_i  = 1'b0;
    out_ready_i = 1'b0;
    in_data_i   = {DSIZE{1'b0}};

    ref_wr_ptr  = {ASIZE{1'b0}};
    ref_rd_ptr  = {ASIZE{1'b0}};
    ref_count   = {(ASIZE+1){1'b0}};
    for (i = 0; i < DEPTH; i = i + 1)
      ref_mem[i] = {DSIZE{1'b0}};

    #2;
    rst_ni = 1'b0;
    #23;
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
    out_ready_i = 1'b0;

    repeat (5) @(posedge clk_i);

    $display("TEST DONE - no mismatches detected.");
    $finish;
  end

  // Scoreboard/checks
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ref_wr_ptr <= {ASIZE{1'b0}};
      ref_rd_ptr <= {ASIZE{1'b0}};
      ref_count  <= {(ASIZE+1){1'b0}};
    end else begin
      reg do_push;
      reg do_pop;
      reg [DSIZE-1:0] exp_out;

      // expected ready/valid from reference count
      if (in_ready_o !== (ref_count != DEPTH)) begin
        $display("READY MISMATCH @%0t: dut_in_ready=%0b exp=%0b (ref_count=%0d)",
                 $time, in_ready_o, (ref_count != DEPTH), ref_count);
        $fatal;
      end
      if (out_valid_o !== (ref_count != 0)) begin
        $display("VALID MISMATCH @%0t: dut_out_valid=%0b exp=%0b (ref_count=%0d)",
                 $time, out_valid_o, (ref_count != 0), ref_count);
        $fatal;
      end

      do_push = in_valid_i  && (ref_count != DEPTH);
      do_pop  = out_ready_i && (ref_count != 0);

      // Data check on pop: out_data_o is current head (async read)
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

      // Apply push into reference
      if (do_push) begin
        if (VERBOSE) begin
          $display("[%0t] PUSH: data=0x%0h @ref_wr_ptr=%0d (ref_count=%0d)",
                   $time, in_data_i, ref_wr_ptr, ref_count);
        end
        ref_mem[ref_wr_ptr] <= in_data_i;
        ref_wr_ptr <= ref_wr_ptr + {{(ASIZE-1){1'b0}}, 1'b1};
      end

      // Apply pop pointer update
      if (do_pop) begin
        ref_rd_ptr <= ref_rd_ptr + {{(ASIZE-1){1'b0}}, 1'b1};
      end

      // Update count
      case ({do_push, do_pop})
        2'b10: ref_count <= ref_count + 1;
        2'b01: ref_count <= ref_count - 1;
        default: ref_count <= ref_count;
      endcase

      // Optional verbose blocked info
      if (VERBOSE) begin
        if (in_valid_i && !do_push)
          $display("[%0t] PUSH BLOCKED (FULL)  ref_count=%0d", $time, ref_count);
        if (out_ready_i && !do_pop)
          $display("[%0t] POP  BLOCKED (EMPTY) ref_count=%0d", $time, ref_count);
      end
    end
  end

endmodule

`default_nettype wire
