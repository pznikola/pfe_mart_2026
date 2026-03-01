`timescale 1ns/1ps

module tb_jtag_uart_controller;

`ifndef TB_VERBOSE
  `define TB_VERBOSE 0
`endif
  localparam VERBOSE = (`TB_VERBOSE != 0);

  reg clk = 0;
  reg rst_n = 0;
  always #5 clk = ~clk;

  // Avalon wires
  wire        av_chipselect;
  wire        av_address;
  wire        av_read_n;
  wire [31:0] av_readdata;
  wire        av_write_n;
  wire [31:0] av_writedata;
  wire        av_waitrequest;

  // Controller streaming
  wire [7:0] rx_data;
  wire       rx_valid;
  reg        rx_ready;

  reg  [7:0] tx_data;
  reg        tx_valid;
  wire       tx_ready;

  // PC-side model interface
  reg  [7:0] pc_rx_data;
  reg        pc_rx_valid;
  wire       pc_rx_ready;

  wire [7:0] pc_tx_data;
  wire       pc_tx_valid;
  reg        pc_tx_ready;

  // DUT
  jtag_uart_controller dut (
    .clk(clk),
    .rst_n(rst_n),

    .av_chipselect(av_chipselect),
    .av_address(av_address),
    .av_read_n(av_read_n),
    .av_readdata(av_readdata),
    .av_write_n(av_write_n),
    .av_writedata(av_writedata),
    .av_waitrequest(av_waitrequest),

    .rx_data(rx_data),
    .rx_valid(rx_valid),
    .rx_ready(rx_ready),

    .tx_data(tx_data),
    .tx_valid(tx_valid),
    .tx_ready(tx_ready)
  );

  // Model
  jtag_uart_model #(
    .RX_DEPTH(64),
    .TX_DEPTH(64),
    .WAIT_PCT(20)
  ) model (
    .clk(clk),
    .rst_n(rst_n),

    .av_chipselect(av_chipselect),
    .av_address(av_address),
    .av_read_n(av_read_n),
    .av_readdata(av_readdata),
    .av_write_n(av_write_n),
    .av_writedata(av_writedata),
    .av_waitrequest(av_waitrequest),

    .pc_rx_data(pc_rx_data),
    .pc_rx_valid(pc_rx_valid),
    .pc_rx_ready(pc_rx_ready),

    .pc_tx_data(pc_tx_data),
    .pc_tx_valid(pc_tx_valid),
    .pc_tx_ready(pc_tx_ready)
  );

  // Scoreboards
  localparam integer QDEPTH = 2048;
  reg [7:0] exp_rx_q [0:QDEPTH-1];
  integer exp_rx_wr = 0, exp_rx_rd = 0, exp_rx_count = 0;

  reg [7:0] exp_tx_q [0:QDEPTH-1];
  integer exp_tx_wr = 0, exp_tx_rd = 0, exp_tx_count = 0;

  task push_exp_rx(input [7:0] b);
    begin
      exp_rx_q[exp_rx_wr] = b;
      exp_rx_wr = (exp_rx_wr + 1) % QDEPTH;
      exp_rx_count = exp_rx_count + 1;
    end
  endtask

  task check_rx(input [7:0] b);
    reg [7:0] e;
    begin
      if (exp_rx_count <= 0) begin
        $display("ERROR: DUT produced RX byte but none expected at %0t. got=0x%02h", $time, b);
        $fatal(1);
      end
      e = exp_rx_q[exp_rx_rd];
      exp_rx_rd = (exp_rx_rd + 1) % QDEPTH;
      exp_rx_count = exp_rx_count - 1;

      if (VERBOSE) $display("[%0t] DUT RX got=0x%02h exp=0x%02h %s", $time, b, e, (b===e)?"OK":"BAD");

      if (b !== e) begin
        $display("ERROR: RX mismatch at %0t: got=0x%02h exp=0x%02h", $time, b, e);
        $fatal(1);
      end
    end
  endtask

  task push_exp_tx(input [7:0] b);
    begin
      exp_tx_q[exp_tx_wr] = b;
      exp_tx_wr = (exp_tx_wr + 1) % QDEPTH;
      exp_tx_count = exp_tx_count + 1;
    end
  endtask

  task check_tx(input [7:0] b);
    reg [7:0] e;
    begin
      if (exp_tx_count <= 0) begin
        $display("ERROR: Model produced TX byte but none expected at %0t. got=0x%02h", $time, b);
        $fatal(1);
      end
      e = exp_tx_q[exp_tx_rd];
      exp_tx_rd = (exp_tx_rd + 1) % QDEPTH;
      exp_tx_count = exp_tx_count - 1;

      if (VERBOSE) $display("[%0t] PC  TX got=0x%02h exp=0x%02h %s", $time, b, e, (b===e)?"OK":"BAD");

      if (b !== e) begin
        $display("ERROR: TX mismatch at %0t: got=0x%02h exp=0x%02h", $time, b, e);
        $fatal(1);
      end
    end
  endtask

  // PC inject RX
  task pc_send_byte(input [7:0] b);
    begin
      pc_rx_data  = b;
      pc_rx_valid = 1'b1;
      while (!(pc_rx_valid && pc_rx_ready)) @(posedge clk);
      if (VERBOSE) $display("[%0t] PC injected RX byte 0x%02h", $time, b);
      push_exp_rx(b);
      @(posedge clk);
      pc_rx_valid = 1'b0;
      pc_rx_data  = 8'h00;
    end
  endtask

  // DUT request TX
  task dut_send_tx(input [7:0] b);
    begin
      tx_data  = b;
      tx_valid = 1'b1;
      while (!(tx_valid && tx_ready)) @(posedge clk);
      if (VERBOSE) $display("[%0t] DUT accepted TX byte request 0x%02h", $time, b);
      push_exp_tx(b);
      @(posedge clk);
      tx_valid = 1'b0;
      tx_data  = 8'h00;
    end
  endtask

  // Random backpressure
  always @(posedge clk) begin
    if (!rst_n) begin
      rx_ready    <= 1'b0;
      pc_tx_ready <= 1'b0;
    end else begin
      rx_ready    <= (($random % 10) < 7);  // 70%
      pc_tx_ready <= (($random % 10) < 8);  // 80%
    end
  end

  // Monitors
  always @(posedge clk) begin
    if (rst_n && rx_valid && rx_ready) begin
      check_rx(rx_data);
    end
  end

  always @(posedge clk) begin
    if (rst_n && pc_tx_valid && pc_tx_ready) begin
      check_tx(pc_tx_data);
    end
  end

  // VCD
  initial begin
    $dumpfile("tb_jtag_uart_controller.vcd");
    $dumpvars(0, tb_jtag_uart_controller);
  end

  integer i;
  integer watchdog;

  initial begin
    pc_rx_data  = 8'h00;
    pc_rx_valid = 1'b0;
    tx_data     = 8'h00;
    tx_valid    = 1'b0;

    repeat (5) @(posedge clk);
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;

    if (VERBOSE) $display("[%0t] Starting JTAG UART controller test...", $time);

    // 1) Burst PC->FPGA RX
    for (i = 0; i < 50; i = i + 1) begin
      pc_send_byte($random[7:0]);
    end

    // 2) DUT->PC TX requests
    for (i = 0; i < 50; i = i + 1) begin
      dut_send_tx($random[7:0]);
    end

    // 3) Mixed traffic
    for (i = 0; i < 100; i = i + 1) begin
      if (($random % 2) == 0) pc_send_byte($random[7:0]);
      else                    dut_send_tx($random[7:0]);
    end

    // Drain with timeout
    watchdog = 0;
    while (exp_rx_count > 0 || exp_tx_count > 0) begin
      @(posedge clk);
      watchdog = watchdog + 1;
      if (watchdog == 300000) begin
        $display("TIMEOUT at %0t: exp_rx_count=%0d exp_tx_count=%0d", $time, exp_rx_count, exp_tx_count);
        $fatal(1);
      end
    end

    $display("PASS: jtag_uart_controller test complete.");
    $finish;
  end

endmodule
