`timescale 1ns/1ps

`ifndef TB_VERBOSE
  `define TB_VERBOSE 0
`endif

module tb_byte_serializer;

    parameter NUM_BYTES = 4;

    // Print control (1 = lots of prints, 0 = only PASS/ERROR)
    localparam bit VERBOSE = (`TB_VERBOSE != 0);
    localparam WIDTH = NUM_BYTES * 8;

    // ----------------------------------------------------------------
    // Clock / Reset
    // ----------------------------------------------------------------
    reg clk;
    reg rst_n;

    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    reg  [WIDTH-1:0] in_data;
    reg              in_valid;
    wire             in_ready;

    wire [7:0]       out_data;
    wire             out_valid;
    reg              out_ready;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    byte_serializer #(
        .NUM_BYTES(NUM_BYTES)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_data   (in_data),
        .in_valid  (in_valid),
        .in_ready  (in_ready),
        .out_data  (out_data),
        .out_valid (out_valid),
        .out_ready (out_ready)
    );

    // ----------------------------------------------------------------
    // Scoreboard
    // ----------------------------------------------------------------
    integer errors;
    integer test_num;

    // ----------------------------------------------------------------
    // Helper tasks
    // ----------------------------------------------------------------

    // Apply synchronous reset for N cycles
    task reset(input integer n);
        begin
            rst_n = 1'b0;
            in_valid = 1'b0;
            in_data = {WIDTH{1'b0}};
            out_ready = 1'b0;
            repeat (n) @(posedge clk);
            #1;
            rst_n = 1'b1;
            @(posedge clk);
            #1;
        end
    endtask

    // Drive a word on the input interface (blocks until handshake)
    // Handshake completes on the posedge where both in_valid & in_ready are high.
    // in_ready is combinational (!busy), so we check it BEFORE the consuming edge.
    task drive_word(input [WIDTH-1:0] word);
        begin
            in_data = word;
            in_valid = 1'b1;
            // Wait until in_ready is high, then let the posedge consume it
            while (!in_ready) begin @(posedge clk); #1; end
            @(posedge clk); #1;  // This edge is the handshake
            in_valid = 1'b0;
            in_data = {WIDTH{1'bx}};
        end
    endtask

    // Receive one byte from output interface (blocks until handshake)
    // Handshake fires on the posedge where out_valid & out_ready are both high.
    // out_valid is registered, so we check it BEFORE the consuming edge.
    task receive_byte(output [7:0] b);
        begin
            out_ready = 1'b1;
            // Wait until out_valid is high (pre-edge state)
            while (!out_valid) begin @(posedge clk); #1; end
            // out_valid is high now; capture data then let next edge consume
            b = out_data;
            @(posedge clk); #1;  // This edge is the handshake
            out_ready = 1'b0;
        end
    endtask

    // Receive one byte with out_ready already high (for back-to-back)
    task receive_byte_ready_high(output [7:0] b);
        begin
            // Wait until out_valid is high (pre-edge state)
            while (!out_valid) begin @(posedge clk); #1; end
            b = out_data;
            @(posedge clk); #1;  // This edge is the handshake
        end
    endtask

    // Check one complete serialized word (little-endian byte order)
    task check_word(input [WIDTH-1:0] expected, input string label);
        reg [7:0] got_byte;
        reg [7:0] exp_byte;
        integer i;
        begin
            for (i = 0; i < NUM_BYTES; i = i + 1) begin
                receive_byte(got_byte);
                exp_byte = expected[i*8 +: 8];
                if (got_byte !== exp_byte) begin
                    $display("ERROR [%s] byte %0d: expected 0x%02h, got 0x%02h",
                             label, i, exp_byte, got_byte);
                    errors = errors + 1;
                end else if (VERBOSE) begin
                    $display("  [%s] byte %0d OK: 0x%02h", label, i, got_byte);
                end
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Test sequences
    // ----------------------------------------------------------------

    // T1 – Basic single-word serialization
    task test_basic_single_word;
        reg [WIDTH-1:0] word;
        begin
            test_num = 1;
            if (VERBOSE) $display("\n=== T1: Basic single-word serialization ===");

            word = 0;
            begin : build_word
                integer k;
                for (k = 0; k < NUM_BYTES; k = k + 1)
                    word[k*8 +: 8] = k[7:0] + 8'd1; // 0x01, 0x02, ...
            end

            drive_word(word);
            check_word(word, "T1");

            if (VERBOSE) $display("T1 done");
        end
    endtask

    // T2 – All-ones and all-zeros
    task test_all_ones_zeros;
        begin
            test_num = 2;
            if (VERBOSE) $display("\n=== T2: All-ones / all-zeros ===");

            drive_word({WIDTH{1'b1}});
            check_word({WIDTH{1'b1}}, "T2-ones");

            drive_word({WIDTH{1'b0}});
            check_word({WIDTH{1'b0}}, "T2-zeros");

            if (VERBOSE) $display("T2 done");
        end
    endtask

    // T3 – Back-to-back words (output always ready)
    task test_back_to_back;
        reg [WIDTH-1:0] word_a, word_b;
        reg [7:0] got_byte, exp_byte;
        integer i;
        begin
            test_num = 3;
            if (VERBOSE) $display("\n=== T3: Back-to-back words ===");

            word_a = {WIDTH{1'b0}};
            word_b = {WIDTH{1'b0}};
            begin : build_t3
                integer k;
                for (k = 0; k < NUM_BYTES; k = k + 1) begin
                    word_a[k*8 +: 8] = (8'hA0 + k[7:0]);
                    word_b[k*8 +: 8] = (8'hB0 + k[7:0]);
                end
            end

            // Drive first word
            drive_word(word_a);

            // Keep out_ready high; while receiving word_a bytes,
            // present word_b as soon as in_ready goes high
            out_ready = 1'b1;

            fork
                // Receiver: collect word_a then word_b bytes
                begin : recv
                    for (i = 0; i < NUM_BYTES; i = i + 1) begin
                        receive_byte_ready_high(got_byte);
                        exp_byte = word_a[i*8 +: 8];
                        if (got_byte !== exp_byte) begin
                            $display("ERROR [T3-a] byte %0d: expected 0x%02h, got 0x%02h",
                                     i, exp_byte, got_byte);
                            errors = errors + 1;
                        end
                    end
                    for (i = 0; i < NUM_BYTES; i = i + 1) begin
                        receive_byte_ready_high(got_byte);
                        exp_byte = word_b[i*8 +: 8];
                        if (got_byte !== exp_byte) begin
                            $display("ERROR [T3-b] byte %0d: expected 0x%02h, got 0x%02h",
                                     i, exp_byte, got_byte);
                            errors = errors + 1;
                        end
                    end
                end

                // Sender: push word_b once serializer is free
                begin : send
                    while (!in_ready) begin @(posedge clk); #1; end
                    drive_word(word_b);
                end
            join

            #1;
            out_ready = 1'b0;
            if (VERBOSE) $display("T3 done");
        end
    endtask

    // T4 – Stalled output (out_ready deasserted mid-transfer)
    task test_stalled_output;
        reg [WIDTH-1:0] word;
        reg [7:0] got_byte, exp_byte;
        integer i;
        begin
            test_num = 4;
            if (VERBOSE) $display("\n=== T4: Stalled output ===");

            word = {WIDTH{1'b0}};
            begin : build_t4
                integer k;
                for (k = 0; k < NUM_BYTES; k = k + 1)
                    word[k*8 +: 8] = (8'hC0 + k[7:0]);
            end

            drive_word(word);

            for (i = 0; i < NUM_BYTES; i = i + 1) begin
                // Accept one byte
                receive_byte(got_byte);
                exp_byte = word[i*8 +: 8];
                if (got_byte !== exp_byte) begin
                    $display("ERROR [T4] byte %0d: expected 0x%02h, got 0x%02h",
                             i, exp_byte, got_byte);
                    errors = errors + 1;
                end
                // Stall for a few cycles between each byte
                out_ready = 1'b0;
                repeat (3) @(posedge clk);
                #1;
            end

            if (VERBOSE) $display("T4 done");
        end
    endtask

    // T5 – Reset mid-transfer
    task test_reset_mid_transfer;
        reg [WIDTH-1:0] word;
        reg [7:0] dummy;
        begin
            test_num = 5;
            if (VERBOSE) $display("\n=== T5: Reset mid-transfer ===");

            word = {WIDTH{1'b0}};
            begin : build_t5
                integer k;
                for (k = 0; k < NUM_BYTES; k = k + 1)
                    word[k*8 +: 8] = (8'hD0 + k[7:0]);
            end

            drive_word(word);

            // Accept first byte only
            if (NUM_BYTES > 1) begin
                receive_byte(dummy);
            end

            // Hit reset
            reset(2);

            // After reset: out_valid must be low, in_ready must be high
            if (out_valid !== 1'b0) begin
                $display("ERROR [T5] out_valid not 0 after reset");
                errors = errors + 1;
            end
            if (in_ready !== 1'b1) begin
                $display("ERROR [T5] in_ready not 1 after reset");
                errors = errors + 1;
            end

            // Verify module still works after reset
            word = {WIDTH{1'b0}};
            begin : build_t5b
                integer k;
                for (k = 0; k < NUM_BYTES; k = k + 1)
                    word[k*8 +: 8] = (8'hE0 + k[7:0]);
            end
            drive_word(word);
            check_word(word, "T5-post-rst");

            if (VERBOSE) $display("T5 done");
        end
    endtask

    // T6 – in_valid asserted while busy (should be ignored / not accepted)
    task test_input_while_busy;
        reg [WIDTH-1:0] word;
        begin
            test_num = 6;
            if (VERBOSE) $display("\n=== T6: Input while busy ===");

            word = {WIDTH{1'b0}};
            begin : build_t6
                integer k;
                for (k = 0; k < NUM_BYTES; k = k + 1)
                    word[k*8 +: 8] = (8'hF0 + k[7:0]);
            end

            drive_word(word);

            // While DUT is serialising, assert in_valid with garbage
            if (NUM_BYTES > 1) begin
                in_data = {WIDTH{1'b1}};
                in_valid = 1'b1;
                repeat (2) @(posedge clk);
                // in_ready should be low while busy
                if (in_ready !== 1'b0) begin
                    $display("ERROR [T6] in_ready should be 0 while busy");
                    errors = errors + 1;
                end
                #1;
                in_valid = 1'b0;
            end

            check_word(word, "T6");

            if (VERBOSE) $display("T6 done");
        end
    endtask

    // T7 – Randomised stress test
    task test_random_stress;
        integer n, i;
        reg [WIDTH-1:0] word;
        reg [7:0] got_byte, exp_byte;
        begin
            test_num = 7;
            if (VERBOSE) $display("\n=== T7: Random stress (%0d words) ===", 20);

            for (n = 0; n < 20; n = n + 1) begin
                // Random word
                word = {WIDTH{1'b0}};
                begin : rand_w
                    integer k;
                    for (k = 0; k < NUM_BYTES; k = k + 1)
                        word[k*8 +: 8] = $urandom[7:0];
                end

                drive_word(word);

                for (i = 0; i < NUM_BYTES; i = i + 1) begin
                    // Random stall on receiver
                    if (($urandom % 3) == 0) begin
                        out_ready = 1'b0;
                        repeat (1 + ($urandom % 4)) @(posedge clk);
                        #1;
                    end
                    receive_byte(got_byte);
                    exp_byte = word[i*8 +: 8];
                    if (got_byte !== exp_byte) begin
                        $display("ERROR [T7] word %0d byte %0d: exp 0x%02h got 0x%02h",
                                 n, i, exp_byte, got_byte);
                        errors = errors + 1;
                    end
                end
            end
            if (VERBOSE) $display("T7 done");
        end
    endtask

    // T8 – Walking-ones pattern (catch stuck bits in shift register)
    task test_walking_ones;
        integer b;
        reg [WIDTH-1:0] word;
        begin
            test_num = 8;
            if (VERBOSE) $display("\n=== T8: Walking-ones ===");

            for (b = 0; b < WIDTH; b = b + 1) begin
                word = ({{(WIDTH-1){1'b0}}, 1'b1} << b);
                drive_word(word);
                check_word(word, "T8");
            end
            if (VERBOSE) $display("T8 done");
        end
    endtask

    // ----------------------------------------------------------------
    // Timeout watchdog
    // ----------------------------------------------------------------
    initial begin
        #(500_000);
        $display("TIMEOUT: simulation exceeded time limit");
        $finish;
    end

    // ----------------------------------------------------------------
    // Main stimulus
    // ----------------------------------------------------------------
    initial begin
        errors = 0;
        reset(3);

        test_basic_single_word;
        test_all_ones_zeros;
        test_back_to_back;
        test_stalled_output;
        test_reset_mid_transfer;
        test_input_while_busy;
        test_random_stress;
        test_walking_ones;

        repeat (5) @(posedge clk);

        $display("");
        if (errors == 0)
            $display("PASS: All byte_serializer tests passed (NUM_BYTES=%0d)", NUM_BYTES);
        else
            $display("FAIL: %0d error(s) in byte_serializer tests (NUM_BYTES=%0d)",
                     errors, NUM_BYTES);
        $display("");
        $finish;
    end

    // ----------------------------------------------------------------
    // Optional VCD dump
    // ----------------------------------------------------------------
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_byte_serializer.vcd");
            $dumpvars(0, tb_byte_serializer);
        end
    end

endmodule
