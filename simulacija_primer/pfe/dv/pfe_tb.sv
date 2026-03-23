`timescale 1ns / 1ps

module pfe_tb;

    // ──────────────────────────────────────────────
    // Parameters
    // ──────────────────────────────────────────────
    parameter int DSIZE      = 8;
    parameter int CLK_PERIOD = 10; // ns

    // ──────────────────────────────────────────────
    // Test stimulus - edit these arrays to change
    // what gets sent and what is expected
    // ──────────────────────────────────────────────
    logic [DSIZE-1:0] input_data []    = '{8'hA0, 8'hB1, 8'hC2, 8'hD3, 8'hE4, 8'h01, 8'h02, 8'h03};
    logic [DSIZE-1:0] expected_data [] = '{8'hA0, 8'hB1, 8'hC2, 8'hD3, 8'hE4, 8'h01, 8'h02, 8'h03};

    // ──────────────────────────────────────────────
    // DUT signals
    // ──────────────────────────────────────────────
    logic             clk;
    logic             rst_n;
    logic [DSIZE-1:0] in_data;
    logic             in_valid;
    logic             in_ready;
    logic [DSIZE-1:0] out_data;
    logic             out_valid;
    logic             out_ready;

    // ──────────────────────────────────────────────
    // DUT instantiation
    // ──────────────────────────────────────────────
    pfe #(
        .DSIZE(DSIZE)
    ) dut (
        .clk_i       (clk),
        .rst_ni      (rst_n),
        .in_data_i   (in_data),
        .in_valid_i  (in_valid),
        .in_ready_o  (in_ready),
        .out_data_o  (out_data),
        .out_valid_o (out_valid),
        .out_ready_i (out_ready)
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
        rst_n     <= 1'b0;
        in_data   <= '0;
        in_valid  <= 1'b0;
        out_ready <= 1'b0;
        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        @(posedge clk);
    endtask

    // ──────────────────────────────────────────────
    // Sender process
    // ──────────────────────────────────────────────
    int send_count = 0;

    task automatic sender();
        $display("[SENDER  ] Starting - %0d words to send", input_data.size());

        for (int i = 0; i < input_data.size(); i++) begin
            // Drive data + valid (will appear at next posedge)
            in_data  <= input_data[i];
            in_valid <= 1'b1;
            // Now wait for handshake: sample at each posedge
            forever begin
                @(posedge clk);
                if (in_valid && in_ready) begin
                    $display("[SENDER  ] [%0t] Sent word [%0d] = 0x%0h", $time, i, input_data[i]);
                    send_count++;
                    break;
                end
            end
        end
        // De-assert after last transfer
        in_valid <= 1'b0;
        in_data  <= '0;
        $display("[SENDER  ] Done - %0d words sent", send_count);
    endtask

    // ──────────────────────────────────────────────
    // Receiver process
    //
    // Same handshake logic on the output side:
    // assert ready, then check valid on each posedge.
    // ──────────────────────────────────────────────
    int recv_count  = 0;
    int error_count = 0;

    task automatic receiver();
        $display("[RECEIVER] Starting - expecting %0d words", expected_data.size());

        out_ready <= 1'b1;

        for (int i = 0; i < expected_data.size(); i++) begin
            forever begin
                @(posedge clk);
                if (out_valid && out_ready) begin
                    recv_count++;
                    if (out_data !== expected_data[i]) begin
                        $error("[RECEIVER] [%0t] MISMATCH word [%0d]: got 0x%0h, expected 0x%0h",
                               $time, i, out_data, expected_data[i]);
                        error_count++;
                    end else begin
                        $display("[RECEIVER] [%0t] OK word [%0d] = 0x%0h", $time, i, out_data);
                    end
                    break;
                end
            end
        end
        out_ready <= 1'b0;
        $display("[RECEIVER] Done - %0d words received, %0d errors", recv_count, error_count);
    endtask

    // ──────────────────────────────────────────────
    // Main test sequence
    // ──────────────────────────────────────────────
    initial begin
        $display("========================================");
        $display(" PFE Testbench Start");
        $display("========================================");

        do_reset();

        // Fork means that this should work in parallel
        fork
            sender();
            receiver();
        join

        repeat (5) @(posedge clk);
        $display("========================================");
        if (error_count == 0)
            $display(" TEST PASSED (%0d words)", recv_count);
        else
            $display(" TEST FAILED (%0d errors out of %0d words)", error_count, recv_count);
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