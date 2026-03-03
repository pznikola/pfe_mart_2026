`timescale 1ns/1ps

`ifndef TB_VERBOSE
  `define TB_VERBOSE 0
`endif

module tb_byte_deserializer;

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
    reg  [7:0]       in_data;
    reg              in_valid;
    wire             in_ready;

    wire [WIDTH-1:0] out_data;
    wire             out_valid;
    reg              out_ready;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    byte_deserializer #(
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
            in_data = 8'd0;
            out_ready = 1'b0;
            repeat (n) @(posedge clk);
            #1;
            rst_n = 1'b1;
            @(posedge clk);
            #1;
        end
    endtask

    // Send a single byte on the input interface (blocks until handshake)
    // Handshake fires on the posedge where in_valid & in_ready are both high.
    // in_ready is combinational (!out_valid), so check it BEFORE the consuming edge.
    task send_byte(input [7:0] b);
        begin
            in_data = b;
            in_valid = 1'b1;
            while (!in_ready) begin @(posedge clk); #1; end
            @(posedge clk); #1;  // This edge is the handshake
            in_valid = 1'b0;
            in_data = 8'hxx;
        end
    endtask

    // Send all bytes of a word (little-endian: LSB first)
    task send_word(input [WIDTH-1:0] word);
        integer i;
        begin
            for (i = 0; i < NUM_BYTES; i = i + 1) begin
                send_byte(word[i*8 +: 8]);
            end
        end
    endtask

    // Wait for out_valid then read out_data (blocks until handshake)
    // out_valid is registered, so check BEFORE the consuming edge.
    task receive_word(output [WIDTH-1:0] word);
        begin
            out_ready = 1'b1;
            while (!out_valid) begin @(posedge clk); #1; end
            word = out_data;
            @(posedge clk); #1;  // This edge is the handshake
            out_ready = 1'b0;
        end
    endtask

    // Send a word and verify the reassembled output
    task send_and_check(input [WIDTH-1:0] expected, input string label);
        reg [WIDTH-1:0] got;
        begin
            fork
                // Sender: push bytes
                send_word(expected);
                // Receiver: wait for reassembled word
                receive_word(got);
            join

            if (got !== expected) begin
                $display("ERROR [%s] expected 0x%0h, got 0x%0h", label, expected, got);
                errors = errors + 1;
            end else if (VERBOSE) begin
                $display("  [%s] OK: 0x%0h", label, got);
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Test sequences
    // ----------------------------------------------------------------

    // T1 – Basic single-word deserialization
    task test_basic_single_word;
        reg [WIDTH-1:0] word;
        begin
            test_num = 1;
            if (VERBOSE) $display("\n=== T1: Basic single-word deserialization ===");

            word = 0;
            begin : build_word
                integer k;
                for (k = 0; k < NUM_BYTES; k = k + 1)
                    word[k*8 +: 8] = k[7:0] + 8'd1; // 0x01, 0x02, ...
            end

            send_and_check(word, "T1");
            if (VERBOSE) $display("T1 done");
        end
    endtask

    // T2 – All-ones and all-zeros
    task test_all_ones_zeros;
        begin
            test_num = 2;
            if (VERBOSE) $display("\n=== T2: All-ones / all-zeros ===");

            send_and_check({WIDTH{1'b1}}, "T2-ones");
            send_and_check({WIDTH{1'b0}}, "T2-zeros");

            if (VERBOSE) $display("T2 done");
        end
    endtask

    // T3 – Back-to-back words (output consumed immediately)
    task test_back_to_back;
        reg [WIDTH-1:0] word_a, word_b;
        reg [WIDTH-1:0] got;
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

            // Word A
            send_and_check(word_a, "T3-a");

            // Word B immediately after
            send_and_check(word_b, "T3-b");

            if (VERBOSE) $display("T3 done");
        end
    endtask

    // T4 – Stalled sender (gaps between bytes)
    task test_stalled_sender;
        reg [WIDTH-1:0] word;
        reg [WIDTH-1:0] got;
        integer i;
        begin
            test_num = 4;
            if (VERBOSE) $display("\n=== T4: Stalled sender ===");

            word = {WIDTH{1'b0}};
            begin : build_t4
                integer k;
                for (k = 0; k < NUM_BYTES; k = k + 1)
                    word[k*8 +: 8] = (8'hC0 + k[7:0]);
            end

            fork
                // Sender with stalls
                begin
                    for (i = 0; i < NUM_BYTES; i = i + 1) begin
                        // Random gap between bytes
                        repeat (2 + (i % 3)) @(posedge clk);
                        #1;
                        send_byte(word[i*8 +: 8]);
                    end
                end
                // Receiver
                receive_word(got);
            join

            if (got !== word) begin
                $display("ERROR [T4] expected 0x%0h, got 0x%0h", word, got);
                errors = errors + 1;
            end else if (VERBOSE) begin
                $display("  [T4] OK: 0x%0h", got);
            end

            if (VERBOSE) $display("T4 done");
        end
    endtask

    // T5 – Delayed consumer (out_ready late)
    task test_delayed_consumer;
        reg [WIDTH-1:0] word;
        reg [WIDTH-1:0] got;
        begin
            test_num = 5;
            if (VERBOSE) $display("\n=== T5: Delayed consumer ===");

            word = {WIDTH{1'b0}};
            begin : build_t5
                integer k;
                for (k = 0; k < NUM_BYTES; k = k + 1)
                    word[k*8 +: 8] = (8'hD0 + k[7:0]);
            end

            // Send all bytes without asserting out_ready
            send_word(word);

            // Wait a few cycles, then read
            repeat (5) @(posedge clk);

            // out_valid should be asserted and data should be stable
            if (out_valid !== 1'b1) begin
                $display("ERROR [T5] out_valid not asserted after all bytes sent");
                errors = errors + 1;
            end

            // in_ready should be low (word is waiting)
            if (in_ready !== 1'b0) begin
                $display("ERROR [T5] in_ready should be 0 while word is pending");
                errors = errors + 1;
            end

            // Now consume - out_valid already verified high above
            out_ready = 1'b1;
            got = out_data;
            @(posedge clk); #1;  // Handshake edge
            out_ready = 1'b0;

            if (got !== word) begin
                $display("ERROR [T5] expected 0x%0h, got 0x%0h", word, got);
                errors = errors + 1;
            end else if (VERBOSE) begin
                $display("  [T5] OK: 0x%0h", got);
            end

            if (VERBOSE) $display("T5 done");
        end
    endtask

    // T6 – Reset mid-collection
    task test_reset_mid_collection;
        reg [WIDTH-1:0] word;
        begin
            test_num = 6;
            if (VERBOSE) $display("\n=== T6: Reset mid-collection ===");

            word = {WIDTH{1'b0}};
            begin : build_t6
                integer k;
                for (k = 0; k < NUM_BYTES; k = k + 1)
                    word[k*8 +: 8] = (8'hE0 + k[7:0]);
            end

            // Send partial word (half the bytes)
            begin : partial
                integer k;
                for (k = 0; k < (NUM_BYTES / 2 > 0 ? NUM_BYTES / 2 : 1); k = k + 1)
                    send_byte(word[k*8 +: 8]);
            end

            // Hit reset
            reset(2);

            // After reset: out_valid must be low, in_ready must be high
            if (out_valid !== 1'b0) begin
                $display("ERROR [T6] out_valid not 0 after reset");
                errors = errors + 1;
            end
            if (in_ready !== 1'b1) begin
                $display("ERROR [T6] in_ready not 1 after reset");
                errors = errors + 1;
            end

            // Verify module still works after reset
            word = {WIDTH{1'b0}};
            begin : build_t6b
                integer k;
                for (k = 0; k < NUM_BYTES; k = k + 1)
                    word[k*8 +: 8] = (8'hF0 + k[7:0]);
            end
            send_and_check(word, "T6-post-rst");

            if (VERBOSE) $display("T6 done");
        end
    endtask

    // T7 – Randomised stress test
    task test_random_stress;
        integer n;
        reg [WIDTH-1:0] word;
        reg [WIDTH-1:0] got;
        integer i;
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

                fork
                    // Sender with random stalls
                    begin
                        for (i = 0; i < NUM_BYTES; i = i + 1) begin
                            if (($urandom % 3) == 0) begin
                                repeat (1 + ($urandom % 4)) @(posedge clk);
                                #1;
                            end
                            send_byte(word[i*8 +: 8]);
                        end
                    end
                    // Receiver with random delay before accepting
                    begin
                        // Wait for out_valid
                        while (!out_valid) begin @(posedge clk); #1; end
                        // Random delay before accepting
                        if (($urandom % 2) == 0) begin
                            repeat (1 + ($urandom % 3)) @(posedge clk);
                        end
                        out_ready = 1'b1;
                        got = out_data;
                        @(posedge clk); #1;  // Handshake edge
                        out_ready = 1'b0;
                    end
                join

                if (got !== word) begin
                    $display("ERROR [T7] word %0d: exp 0x%0h got 0x%0h", n, word, got);
                    errors = errors + 1;
                end else if (VERBOSE) begin
                    $display("  [T7] word %0d OK: 0x%0h", n, got);
                end
            end
            if (VERBOSE) $display("T7 done");
        end
    endtask

    // T8 – Walking-ones pattern
    task test_walking_ones;
        integer b;
        reg [WIDTH-1:0] word;
        begin
            test_num = 8;
            if (VERBOSE) $display("\n=== T8: Walking-ones ===");

            for (b = 0; b < WIDTH; b = b + 1) begin
                word = ({{(WIDTH-1){1'b0}}, 1'b1} << b);
                send_and_check(word, "T8");
            end
            if (VERBOSE) $display("T8 done");
        end
    endtask

    // T9 – Byte counter alignment (send 2 words back-to-back to verify
    //       the internal counter resets properly between words)
    task test_counter_alignment;
        reg [WIDTH-1:0] word_a, word_b;
        begin
            test_num = 9;
            if (VERBOSE) $display("\n=== T9: Counter alignment across words ===");

            word_a = {WIDTH{1'b0}};
            word_b = {WIDTH{1'b0}};
            begin : build_t9
                integer k;
                for (k = 0; k < NUM_BYTES; k = k + 1) begin
                    word_a[k*8 +: 8] = (8'h10 + k[7:0]);
                    word_b[k*8 +: 8] = (8'h20 + k[7:0]);
                end
            end

            send_and_check(word_a, "T9-a");
            send_and_check(word_b, "T9-b");

            if (VERBOSE) $display("T9 done");
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
        test_stalled_sender;
        test_delayed_consumer;
        test_reset_mid_collection;
        test_random_stress;
        test_walking_ones;
        test_counter_alignment;

        repeat (5) @(posedge clk);

        $display("");
        if (errors == 0)
            $display("PASS: All byte_deserializer tests passed (NUM_BYTES=%0d)", NUM_BYTES);
        else
            $display("FAIL: %0d error(s) in byte_deserializer tests (NUM_BYTES=%0d)",
                     errors, NUM_BYTES);
        $display("");
        $finish;
    end

    // ----------------------------------------------------------------
    // Optional VCD dump
    // ----------------------------------------------------------------
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_byte_deserializer.vcd");
            $dumpvars(0, tb_byte_deserializer);
        end
    end

endmodule
