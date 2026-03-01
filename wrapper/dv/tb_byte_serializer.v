`timescale 1ns/1ps

`ifndef TB_VERBOSE
  `define TB_VERBOSE 0
`endif

module tb_byte_serializer;

  // ---- configure ----
  localparam integer WORD_BYTES = 4;
  localparam integer W = WORD_BYTES*8;

  // Print control (1 = lots of prints, 0 = only PASS/ERROR)
  localparam bit VERBOSE = (`TB_VERBOSE != 0);

  // ---- clock/reset ----
  reg clk = 0;
  reg rst_n = 0;
  always #5 clk = ~clk;

  // ---- DUT signals ----
  reg  [W-1:0] in_data;
  reg          in_valid;
  wire         in_ready;

  wire [7:0]   out_data;
  wire         out_valid;
  reg          out_ready;

  // ---- instantiate DUT ----
  byte_serializer #(.WORD_BYTES(WORD_BYTES)) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .in_data  (in_data),
    .in_valid (in_valid),
    .in_ready (in_ready),
    .out_data (out_data),
    .out_valid(out_valid),
    .out_ready(out_ready)
  );

  integer i;
  integer total_words_sent = 0;
  integer total_words_received = 0;

  // Expected bytes queue for checking output stream (MSB-first)
  localparam integer BQDEPTH = 2048;
  reg [7:0] exp_bq [0:BQDEPTH-1];
  integer bq_wr = 0, bq_rd = 0;
  integer exp_bytes_total = 0;
  integer got_bytes_total = 0;

  // For pretty printing which byte within a word we are receiving
  integer rx_byte_in_word = 0;

  task push_exp_byte(input [7:0] b);
    begin
      exp_bq[bq_wr] = b;
      bq_wr = (bq_wr + 1) % BQDEPTH;
      exp_bytes_total = exp_bytes_total + 1;
    end
  endtask

  task check_got_byte(input [7:0] b);
    reg [7:0] e;
    begin
      e = exp_bq[bq_rd];

      // Print BEFORE advancing pointers/counters (easier to read)
      if (VERBOSE) begin
        $display("[%0t] RX byte #%0d (word %0d, idx %0d): got=0x%02h exp=0x%02h %s",
                 $time,
                 got_bytes_total,
                 (got_bytes_total / WORD_BYTES),
                 rx_byte_in_word,
                 b, e,
                 (b===e) ? "OK" : "MISMATCH");
      end

      bq_rd = (bq_rd + 1) % BQDEPTH;
      got_bytes_total = got_bytes_total + 1;

      // Track byte index within current word
      if (rx_byte_in_word == WORD_BYTES-1) rx_byte_in_word = 0;
      else                                rx_byte_in_word = rx_byte_in_word + 1;

      if (b !== e) begin
        $display("ERROR: Byte mismatch at time %0t", $time);
        $display("  expected = 0x%02h", e);
        $display("  got      = 0x%02h", b);
        $fatal(1);
      end
    end
  endtask

  // Send one word, holding in_valid until accepted (in_ready high)
  task send_word(input [W-1:0] w);
    integer k;
    begin
      // enqueue expected output bytes MSB-first
      for (k = 0; k < WORD_BYTES; k = k + 1) begin
        push_exp_byte(w[W-1-8*k -: 8]);
      end

      in_data  = w;
      in_valid = 1'b1;

      // wait until accepted
      while (!(in_valid && in_ready)) begin
        @(posedge clk);
      end

      // accepted on THIS posedge
      if (VERBOSE) begin
        $display("[%0t] TX word accepted #%0d: 0x%0h (bytes MSB->LSB: %02h %02h %02h %02h)",
                 $time, total_words_sent, w,
                 w[31:24], w[23:16], w[15:8], w[7:0]);
      end

      @(posedge clk);
      in_valid = 1'b0;
      in_data  = {W{1'b0}};
      total_words_sent = total_words_sent + 1;
    end
  endtask

  // ---- Dump VCD ----
  initial begin
    $dumpfile("tb_byte_serializer.vcd");
    $dumpvars(0, tb_byte_serializer);
  end

  // Random backpressure on out_ready
  always @(posedge clk) begin
    if (!rst_n) out_ready <= 1'b0;
    else begin
      // ~70% ready
      out_ready <= ($random % 10 < 7);
    end
  end

  // Check bytes as they are accepted
  always @(posedge clk) begin
    if (rst_n && out_valid && out_ready) begin
      check_got_byte(out_data);

      // Count words received when we complete WORD_BYTES bytes
      if ((got_bytes_total % WORD_BYTES) == 0) begin
        total_words_received <= got_bytes_total / WORD_BYTES;
      end
    end
  end

  initial begin
    in_data   = {W{1'b0}};
    in_valid  = 1'b0;
    out_ready = 1'b0;

    // reset
    repeat (5) @(posedge clk);
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    if (VERBOSE) $display("[%0t] Starting test...", $time);

    // known words
    send_word(32'hDEADBEEF);
    send_word(32'h01234567);

    // random words
    for (i = 0; i < 50; i = i + 1) begin
      send_word($random);
    end

    // wait for all expected bytes to drain
    while (got_bytes_total < exp_bytes_total) begin
      @(posedge clk);
    end

    $display("PASS: byte_serializer (%0d bytes/word). Words sent: %0d, Words received: %0d, Bytes checked: %0d",
             WORD_BYTES, total_words_sent, total_words_received, got_bytes_total);
    $finish;
  end

endmodule
