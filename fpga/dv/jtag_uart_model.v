`timescale 1ns/1ps
// jtag_uart_model.v
//
// Behavioral model of Intel/Altera JTAG UART Avalon-MM slave.
//
// Important timing note:
// The real JTAG UART provides readdata in the same cycle a read transfer
// completes (i.e. when waitrequest is low). If the model registers readdata on
// the same posedge that the master samples it, the master will see stale data
// and can silently drop RX bytes. Therefore, this model drives av_readdata
// combinationally from current state, and only updates FIFO pointers/counts on
// the clock edge when the transfer "fires".
//
// Register semantics implemented (per typical Intel docs):
//   DATA    (address=0): [31:16]=RAVAIL, [15]=RVALID, [7:0]=RDATA
//                        Reading pops one RX byte when RVALID=1.
//                        Writing pushes one TX byte (if space).
//   CONTROL (address=1): [31:16]=WSPACE, [15:0]=RAVAIL
//
// WAIT_PCT adds random stall cycles via waitrequest.

module jtag_uart_model #(
  parameter integer RX_DEPTH = 64,
  parameter integer TX_DEPTH = 64,
  parameter integer WAIT_PCT = 20
)(
  input  wire        clk,
  input  wire        rst_n,

  // Avalon-MM slave
  input  wire        av_chipselect,
  input  wire        av_address,     // 0=DATA, 1=CONTROL
  input  wire        av_read_n,
  output wire [31:0] av_readdata,
  input  wire        av_write_n,
  input  wire [31:0] av_writedata,
  output wire        av_waitrequest,

  // TB-facing "PC side"
  input  wire [7:0]  pc_rx_data,
  input  wire        pc_rx_valid,
  output wire        pc_rx_ready,

  output wire [7:0]  pc_tx_data,
  output wire        pc_tx_valid,
  input  wire        pc_tx_ready
);

  // RX FIFO (PC -> FPGA)
  reg [7:0] rx_fifo [0:RX_DEPTH-1];
  integer rx_wr, rx_rd, rx_count;

  // TX FIFO (FPGA -> PC)
  reg [7:0] tx_fifo [0:TX_DEPTH-1];
  integer tx_wr, tx_rd, tx_count;

  assign pc_rx_ready = (rx_count < RX_DEPTH);
  assign pc_tx_valid = (tx_count > 0);
  assign pc_tx_data  = tx_fifo[tx_rd];

  function integer inc_mod;
    input integer val;
    input integer mod;
    begin
      if (val == (mod-1)) inc_mod = 0;
      else                inc_mod = val + 1;
    end
  endfunction

  wire selected = av_chipselect && (!av_read_n || !av_write_n);

  // Stall bit generated once per cycle, updated on negedge so it is stable
  // before the master's posedge logic evaluates waitrequest.
  reg stall_bit;
  always @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stall_bit <= 1'b0;
    end else begin
      if (selected)
        stall_bit <= (($random % 100) < WAIT_PCT);
      else
        stall_bit <= 1'b0;
    end
  end

  assign av_waitrequest = selected ? stall_bit : 1'b0;

  // Combinational readback
  reg [31:0] av_readdata_r;
  assign av_readdata = av_readdata_r;

  always @(*) begin
    integer wspace;
    integer ravail;

    wspace = TX_DEPTH - tx_count;
    if (wspace < 0) wspace = 0;
    if (wspace > 16'hFFFF) wspace = 32'h0000FFFF;

    ravail = rx_count;
    if (ravail < 0) ravail = 0;
    if (ravail > 16'hFFFF) ravail = 32'h0000FFFF;

    av_readdata_r = 32'd0;
    if (av_chipselect && !av_read_n) begin
      if (av_address == 1'b0) begin
        // DATA
        if (rx_count > 0)
          av_readdata_r = {ravail[15:0], 1'b1, 7'd0, rx_fifo[rx_rd]};
        else
          av_readdata_r = {16'd0, 1'b0, 7'd0, 8'd0};
      end else begin
        // CONTROL
        av_readdata_r = {wspace[15:0], ravail[15:0]};
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    reg av_rd_fire, av_wr_fire;
    reg pc_rx_fire, pc_tx_fire;

    integer rx_delta;
    integer tx_delta;

    if (!rst_n) begin
      rx_wr    <= 0;
      rx_rd    <= 0;
      rx_count <= 0;

      tx_wr    <= 0;
      tx_rd    <= 0;
      tx_count <= 0;
    end else begin
      // Fires (waitrequest is combinational/stable for this posedge)
      av_rd_fire = av_chipselect && !av_read_n  && !av_waitrequest;
      av_wr_fire = av_chipselect && !av_write_n && !av_waitrequest;

      pc_rx_fire = pc_rx_valid && (rx_count < RX_DEPTH);
      pc_tx_fire = pc_tx_ready && (tx_count > 0);

      rx_delta = 0;
      tx_delta = 0;

      // PC -> FPGA: RX push
      if (pc_rx_fire) begin
        rx_fifo[rx_wr] <= pc_rx_data;
        rx_wr          <= inc_mod(rx_wr, RX_DEPTH);
        rx_delta       = rx_delta + 1;
      end

      // FPGA -> PC: TX pop
      if (pc_tx_fire) begin
        tx_rd    <= inc_mod(tx_rd, TX_DEPTH);
        tx_delta = tx_delta - 1;
      end

      // Avalon read side-effects
      if (av_rd_fire) begin
        // DATA read pops when data available
        if (av_address == 1'b0) begin
          if (rx_count > 0) begin
            rx_rd    <= inc_mod(rx_rd, RX_DEPTH);
            rx_delta = rx_delta - 1;
          end
        end
      end

      // Avalon write side-effects
      if (av_wr_fire) begin
        if (av_address == 1'b0) begin
          if (tx_count < TX_DEPTH) begin
            tx_fifo[tx_wr] <= av_writedata[7:0];
            tx_wr          <= inc_mod(tx_wr, TX_DEPTH);
            tx_delta       = tx_delta + 1;
          end
        end
      end

      // Commit counts (single NBA each)
      rx_count <= rx_count + rx_delta;
      tx_count <= tx_count + tx_delta;
    end
  end

endmodule
