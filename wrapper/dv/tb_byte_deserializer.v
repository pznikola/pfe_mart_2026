`timescale 1ns/1ps

`ifndef TB_VERBOSE
  `define TB_VERBOSE 0
`endif

module tb_byte_deserializer;

  // ---- configure ----
  localparam integer WORD_BYTES = 4;
  localparam integer W = WORD_BYTES*8;

  // Print control (1 = lots of prints, 0 = only PASS/ERROR)
  localparam bit VERBOSE = (`TB_VERBOSE != 0);


  // ---- clock/reset ----
  reg clk = 0;
  reg rst_n = 0;
  always #5 clk = ~clk; // 100 MHz

  // ---- DUT signals ----
  reg  [7:0] in_data;
  reg        in_valid;
  wire       in_ready;

  wire [W-1:0] out_data;
  wire         out_valid;
  reg          out_ready;

  // ---- instantiate DUT ----
  byte_deserializer #(.WORD_BYTES(WORD_BYTES)) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .in_data  (in_data),
    .in_valid (in_valid),
    .in_ready (in_ready),
    .out_data (out_data),
    .out_valid(out_valid),
    .out_ready(out_ready)
  );

  // ---- scoreboard ----
  integer i;
  integer total_words_sent = 0;
  integer total_words_received = 0;

  integer total_bytes_sent = 0;
  integer total_bytes_received = 0;
  integer tx_byte_in_word  = 0;

  // Build expected word MSB-first from bytes accepted by DUT
  reg [W-1:0] exp_shift;
  integer exp_count;

  // Keep a small queue of expected words (ring buffer)
  localparam integer QDEPTH = 256;
  reg [W-1:0] exp_q [0:QDEPTH-1];
  integer q_wr = 0, q_rd = 0;

  task push_expected(input [W-1:0] w);
    begin
      exp_q[q_wr] = w;
      q_wr = (q_wr + 1) % QDEPTH;
      total_words_sent = total_words_sent + 1;
    end
  endtask

  task pop_and_check(input [W-1:0] got);
    reg [W-1:0] expected;
    begin
      expected = exp_q[q_rd];

      if (VERBOSE) begin
        $display("[%0t] RX word #%0d: got=0x%0h exp=0x%0h %s",
                 $time, total_words_received, got, expected,
                 (got===expected) ? "OK" : "MISMATCH");
      end

      q_rd = (q_rd + 1) % QDEPTH;
      total_words_received = total_words_received + 1;

      if (got !== expected) begin
        $display("ERROR: Word mismatch at time %0t", $time);
        $display("  expected = 0x%0h", expected);
        $display("  got      = 0x%0h", got);
        $fatal(1);
      end
    end
  endtask

  // ---- stimulus helpers ----

  // Drive one byte and hold in_valid until DUT accepts it
  task send_byte(input [7:0] b);
    begin
      in_data  = b;
      in_valid = 1'b1;

      // wait until accepted
      while (!(in_valid && in_ready)) begin
        @(posedge clk);
      end

      // accepted on THIS posedge
      if (VERBOSE) begin
        $display("[%0t] TX byte #%0d (word %0d, idx %0d): 0x%02h accepted",
                 $time,
                 total_bytes_sent,
                 (total_bytes_sent / WORD_BYTES),
                 tx_byte_in_word,
                 b);
      end

      total_bytes_sent = total_bytes_sent + 1;
      if (tx_byte_in_word == WORD_BYTES-1) tx_byte_in_word = 0;
      else                                 tx_byte_in_word = tx_byte_in_word + 1;

      // drop valid next cycle
      @(posedge clk);
      in_valid = 1'b0;
      in_data  = 8'h00;
    end
  endtask

  // ---- Dump VCD ----
  initial begin
    $dumpfile("tb_byte_deserializer.vcd");
    $dumpvars(0, tb_byte_deserializer);
  end

  // Random backpressure on out_ready
  always @(posedge clk) begin
    if (!rst_n) out_ready <= 1'b0;
    else begin
      // ~75% chance ready, ~25% stall
      out_ready <= ($random % 4 != 0);
    end
  end

  // Track accepted input bytes and form expected words MSB-first
  always @(posedge clk) begin
    if (!rst_n) begin
      exp_shift <= {W{1'b0}};
      exp_count <= 0;
    end else begin
      if (in_valid && in_ready) begin
        // shift existing left by 8, append new byte in LSB
        exp_shift <= {exp_shift[W-9:0], in_data};

        if (exp_count == WORD_BYTES-1) begin
          // complete word after this byte
          push_expected({exp_shift[W-9:0], in_data});
          exp_count <= 0;
        end else begin
          exp_count <= exp_count + 1;
        end
      end
    end
  end

  // Check outputs when accepted
  always @(posedge clk) begin
    if (rst_n && out_valid && out_ready) begin
      total_bytes_received = total_bytes_received + WORD_BYTES; // received one full word worth

      pop_and_check(out_data);
    end
  end

  // ---- main test ----
  initial begin
    // init
    in_data   = 8'h00;
    in_valid  = 1'b0;
    out_ready = 1'b0;

    // reset
    repeat (5) @(posedge clk);
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    if (VERBOSE) $display("[%0t] Starting deserializer test...", $time);

    // send a few known patterns
    // Word 0: 0xDEADBEEF (bytes: DE AD BE EF)
    send_byte(8'hDE);
    send_byte(8'hAD);
    send_byte(8'hBE);
    send_byte(8'hEF);

    // Word 1: 0x01234567
    send_byte(8'h01);
    send_byte(8'h23);
    send_byte(8'h45);
    send_byte(8'h67);

    // random stream of bytes (multiple words)
    for (i = 0; i < 100; i = i + 1) begin
      send_byte($random[7:0]);
    end

    // wait until all expected words drain
    while (total_words_received < total_words_sent) begin
      @(posedge clk);
    end

    $display("PASS: byte_deserializer (%0d bytes/word). Words checked: %0d (bytes sent: %0d)",
             WORD_BYTES, total_words_received, total_bytes_sent);
    $finish;
  end

endmodule
