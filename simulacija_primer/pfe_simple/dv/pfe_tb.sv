`timescale 1ns / 1ps

module pfe_tb;

    // ──────────────────────────────────────────────
    // Parameters
    // ──────────────────────────────────────────────
    parameter int DSIZE      = 8;
    parameter int CLK_PERIOD = 10; // ns

    // ──────────────────────────────────────────────
    // Test stimulus - edit these to change the test
    //
    // input_a[i] + input_b[i] should produce
    // expected_c[i] one clock cycle later.
    // ──────────────────────────────────────────────
    logic [DSIZE-1:0] input_a []    = '{8'h01, 8'h10, 8'hFF, 8'h80, 8'h00};
    logic [DSIZE-1:0] input_b []    = '{8'h02, 8'h20, 8'h01, 8'h7F, 8'h00};
    logic [DSIZE-1:0] expected_c [] = '{8'h03, 8'h30, 8'h00, 8'hFF, 8'h00};

    // ──────────────────────────────────────────────
    // DUT signals
    // ──────────────────────────────────────────────
    logic             clk;
    logic             rst_n;
    logic [DSIZE-1:0] a;
    logic [DSIZE-1:0] b;
    logic [DSIZE-1:0] c;

    // ──────────────────────────────────────────────
    // DUT instantiation
    // ──────────────────────────────────────────────
    pfe #(
        .DSIZE(DSIZE)
    ) dut (
        .clk_i  (clk),
        .rst_ni (rst_n),
        .a_i    (a),
        .b_i    (b),
        .c_o    (c)
    );

    // ──────────────────────────────────────────────
    // Clock generation
    // ──────────────────────────────────────────────
    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ──────────────────────────────────────────────
    // Reset
    // ──────────────────────────────────────────────
    task automatic do_reset();
        rst_n <= 1'b0;
        a     <= '0;
        b     <= '0;
        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
    endtask

    // ──────────────────────────────────────────────
    // Sender process - drives a_i and b_i
    //
    // Drives one pair per clock cycle, then sets
    // inputs back to zero.
    // ──────────────────────────────────────────────
    int send_count = 0;

    task automatic sender();
        $display("[SENDER  ] Starting - %0d pairs to send", input_a.size());
        for (int i = 0; i < input_a.size(); i++) begin
            a <= input_a[i];
            b <= input_b[i];
            @(posedge clk);
            $display("[SENDER  ] [%0t] Sent pair [%0d]: a=0x%0h, b=0x%0h", $time, i, input_a[i], input_b[i]);
            send_count++;
        end
        a <= '0;
        b <= '0;
        $display("[SENDER  ] Done - %0d pairs sent", send_count);
    endtask

    // ──────────────────────────────────────────────
    // Receiver process - checks c_o
    //
    // Output is registered, so c_o appears one cycle
    // after inputs are driven. The receiver waits one
    // cycle to account for this pipeline latency,
    // then samples c_o once per cycle.
    // ──────────────────────────────────────────────
    int recv_count  = 0;
    int error_count = 0;

    task automatic receiver();
        $display("[RECEIVER] Starting - expecting %0d results", expected_c.size());
        // Wait one cycle for pipeline latency
        @(posedge clk);
        for (int i = 0; i < expected_c.size(); i++) begin
            @(posedge clk);
            recv_count++;
            if (c !== expected_c[i]) begin
                $error("[RECEIVER] [%0t] MISMATCH result [%0d]: got 0x%0h, expected 0x%0h",
                       $time, i, c, expected_c[i]);
                error_count++;
            end else begin
                $display("[RECEIVER] [%0t] OK result [%0d] = 0x%0h", $time, i, c);
            end
        end
        $display("[RECEIVER] Done - %0d results checked, %0d errors", recv_count, error_count);
    endtask

    // ──────────────────────────────────────────────
    // Main test sequence
    // ──────────────────────────────────────────────
    initial begin
        $display("========================================");
        $display(" PFE Testbench Start");
        $display("========================================");

        // Dump vcd
        $dumpfile("pfe.vcd");
        $dumpvars(0, pfe_tb);

        do_reset();

        fork
            sender();
            receiver();
        join

        repeat (2) @(posedge clk);
        $display("========================================");
        if (error_count == 0)
            $display(" TEST PASSED (%0d results)", recv_count);
        else
            $display(" TEST FAILED (%0d errors out of %0d results)", error_count, recv_count);
        $display("========================================");
        $finish;
    end

    // ──────────────────────────────────────────────
    // Timeout watchdog
    // ──────────────────────────────────────────────
    initial begin
        #(CLK_PERIOD * 1000);
        $error("TIMEOUT - simulation did not finish in time");
        $finish;
    end

endmodule