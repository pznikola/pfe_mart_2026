`timescale 1ns/1ps

`ifndef TB_VERBOSE
  `define TB_VERBOSE 0
`endif

module tb_pfe;

  localparam bit VERBOSE      = (`TB_VERBOSE != 0);
  localparam int DSIZE        = 8;
  localparam int NO2ACC       = 8;
  localparam int SAFE_M       = (NO2ACC < 1) ? 1 : NO2ACC;
  localparam int ACC_BITS     = DSIZE + $clog2(SAFE_M);
  localparam int ACC_BYTES    = (ACC_BITS + 7) / 8;
  localparam int NUM_INPUTS   = 80;  // should be multiple of NO2ACC for this test

  logic                   clk_i;
  logic                   rst_ni;
  logic [DSIZE-1:0]       in_data_i;
  logic                   in_valid_i;
  logic                   in_ready_o;
  logic [DSIZE-1:0]       out_data_o;
  logic                   out_valid_o;
  logic                   out_ready_i;

  int signed sample_q[$];
  logic [ACC_BYTES*8-1:0] expected_word_q[$];
  logic [7:0]             expected_byte_q[$];

  int sent_count;
  int recv_count;

  pfe #(
    .DSIZE (DSIZE)
  ) dut (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .in_data_i  (in_data_i),
    .in_valid_i (in_valid_i),
    .in_ready_o (in_ready_o),
    .out_data_o (out_data_o),
    .out_valid_o(out_valid_o),
    .out_ready_i(out_ready_i)
  );

  // Clock
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  // Random output backpressure
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      out_ready_i <= 1'b0;
    end else begin
      out_ready_i <= ($urandom_range(0, 3) != 0); // 75% ready
    end
  end

  // Build stimulus + expected outputs
  initial begin : build_vectors
    int i, j;
    logic signed [ACC_BYTES*8-1:0] acc;
    logic signed [ACC_BYTES*8-1:0] acc_word;

    for (i = 0; i < NUM_INPUTS; i++) begin
      sample_q.push_back((i % 17) - 8);
    end

    for (i = 0; i < NUM_INPUTS; i += NO2ACC) begin
      acc = '0;
      for (j = 0; j < NO2ACC; j++) begin
        acc += (ACC_BYTES*8)'(sample_q[i+j]);
      end

      acc_word = acc;
      expected_word_q.push_back(acc_word);

      for (j = 0; j < ACC_BYTES; j++) begin
        expected_byte_q.push_back(acc_word[j*8 +: 8]);
      end

      if (VERBOSE) begin
        $display("Expected accumulated word[%0d] = 0x%0h (%0d)",
                 i / NO2ACC, acc_word, acc);
      end
    end
  end

  // Reset + counters
  initial begin
    rst_ni      = 1'b0;
    in_data_i   = '0;
    in_valid_i  = 1'b0;
    sent_count  = 0;
    recv_count  = 0;

    repeat (5) @(posedge clk_i);
    rst_ni = 1'b1;
  end

  // Proper valid/ready input driver
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      in_valid_i <= 1'b0;
      in_data_i  <= '0;
      sent_count <= 0;
    end else begin
      // Present first/next item whenever we're idle
      if (!in_valid_i && sent_count < NUM_INPUTS) begin
        in_valid_i <= 1'b1;
        in_data_i  <= sample_q[sent_count][DSIZE-1:0];

        if (VERBOSE) begin
          $display("[%0t] OFFER sample[%0d] = %0d (0x%02h)",
                   $time, sent_count,
                   $signed(sample_q[sent_count][DSIZE-1:0]),
                   sample_q[sent_count][DSIZE-1:0]);
        end
      end

      // Advance only on a real handshake
      if (in_valid_i && in_ready_o) begin
        if (VERBOSE) begin
          $display("[%0t] SEND sample[%0d] = %0d (0x%02h)",
                   $time, sent_count,
                   $signed(sample_q[sent_count][DSIZE-1:0]),
                   sample_q[sent_count][DSIZE-1:0]);
        end

        sent_count <= sent_count + 1;

        if (sent_count + 1 < NUM_INPUTS) begin
          in_valid_i <= 1'b1;
          in_data_i  <= sample_q[sent_count + 1][DSIZE-1:0];
        end else begin
          in_valid_i <= 1'b0;
          in_data_i  <= '0;
        end
      end
    end
  end

  // Output checker
  always_ff @(posedge clk_i) begin
    if (rst_ni && out_valid_o && out_ready_i) begin
      if (expected_byte_q.size() == 0) begin
        $error("Unexpected output byte: 0x%02h", out_data_o);
        $finish;
      end

      if (VERBOSE) begin
        $display("[%0t] RECV byte[%0d] = 0x%02h, expected = 0x%02h",
                 $time, recv_count, out_data_o, expected_byte_q[0]);
      end

      if (out_data_o !== expected_byte_q[0]) begin
        $error("Byte mismatch at byte %0d: expected=0x%02h got=0x%02h",
               recv_count, expected_byte_q[0], out_data_o);
        $finish;
      end

      expected_byte_q.pop_front();
      recv_count <= recv_count + 1;

      if (expected_byte_q.size() == 1) begin
        $display("PASS: all %0d output bytes matched", recv_count + 1);
      end

      if (expected_byte_q.size() == 1) begin
        fork
          begin
            @(posedge clk_i);
            $finish;
          end
        join_none
      end
    end
  end

  // Optional assembled-word monitor
  initial begin : word_monitor
    int byte_idx;
    logic [ACC_BYTES*8-1:0] assembled_word;
    assembled_word = '0;
    byte_idx = 0;

    forever begin
      @(posedge clk_i);
      if (rst_ni && out_valid_o && out_ready_i) begin
        assembled_word[byte_idx*8 +: 8] = out_data_o;
        byte_idx++;

        if (byte_idx == ACC_BYTES) begin
          if (VERBOSE) begin
            $display("[%0t] OUTPUT WORD = 0x%0h", $time, assembled_word);
          end
          assembled_word = '0;
          byte_idx = 0;
        end
      end
    end
  end

  // Timeout
  initial begin
    #200000;
    $error("Timeout");
    $finish;
  end

endmodule
