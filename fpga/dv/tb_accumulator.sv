`timescale 1ns/1ps

`ifndef TB_VERBOSE
  `define TB_VERBOSE 0
`endif

module tb_accumulator;

    // Print control (1 = lots of prints, 0 = only PASS/ERROR)
    localparam bit VERBOSE = (`TB_VERBOSE != 0);

    localparam int IN_BYTES = 1;
    localparam int NO2ACC   = 4;

    localparam int ISIZE     = IN_BYTES * 8;
    localparam int SAFE_M    = (NO2ACC < 1) ? 1 : NO2ACC;
    localparam int ACC_BITS  = ISIZE + $clog2(SAFE_M);
    localparam int OUT_BYTES = (ACC_BITS + 7) / 8;
    localparam int OSIZE     = OUT_BYTES * 8;

    logic                    clk_w;
    logic                    rstn_w;

    logic signed [ISIZE-1:0] in_data_w;
    logic                    in_valid_w;
    logic                    in_ready_w;

    logic signed [OSIZE-1:0] out_data_w;
    logic                    out_valid_w;
    logic                    out_ready_w;

    // DUT
    accumulator #(
        .IN_BYTES(IN_BYTES),
        .NO2ACC  (NO2ACC)
    ) dut (
        .clk_i      (clk_w),
        .rst_ni     (rstn_w),
        .in_data_i  (in_data_w),
        .in_valid_i (in_valid_w),
        .in_ready_o (in_ready_w),
        .out_data_o (out_data_w),
        .out_valid_o(out_valid_w),
        .out_ready_i(out_ready_w)
    );

    // Clock
    initial clk_w = 1'b0;
    always #5 clk_w = ~clk_w;

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    task automatic send_sample(input logic signed [ISIZE-1:0] sample);
    begin
        @(posedge clk_w);
        in_data_w  = sample;
        in_valid_w = 1'b1;

        while (!in_ready_w) begin
            @(posedge clk_w);
        end

        if (VERBOSE) begin
            $display("[%0t] IN : data=%0d", $time, $signed(sample));
        end

        @(posedge clk_w);
        in_valid_w = 1'b0;
        in_data_w  = '0;
    end
    endtask

    task automatic expect_output(input logic signed [OSIZE-1:0] expected);
    begin
        while (!out_valid_w) begin
            @(posedge clk_w);
        end

        if (VERBOSE) begin
            $display("[%0t] OUT: data=%0d expected=%0d",
                     $time, $signed(out_data_w), $signed(expected));
        end

        if ($signed(out_data_w) !== $signed(expected)) begin
            $error("Mismatch: got %0d expected %0d",
                   $signed(out_data_w), $signed(expected));
            $fatal;
        end

        @(posedge clk_w);
    end
    endtask

    task automatic run_group(
        input logic signed [ISIZE-1:0] x0,
        input logic signed [ISIZE-1:0] x1,
        input logic signed [ISIZE-1:0] x2,
        input logic signed [ISIZE-1:0] x3
    );
        logic signed [OSIZE-1:0] expected;
    begin
        expected = OSIZE'($signed(x0))
                 + OSIZE'($signed(x1))
                 + OSIZE'($signed(x2))
                 + OSIZE'($signed(x3));

        send_sample(x0);
        send_sample(x1);
        send_sample(x2);
        send_sample(x3);

        expect_output(expected);
    end
    endtask

    // Generic version for arbitrary NO2ACC
    task automatic run_group_dynamic(input logic signed [ISIZE-1:0] data_in [0:NO2ACC-1]);
        logic signed [OSIZE-1:0] expected;
        int i;
    begin
        expected = '0;
        for (i = 0; i < NO2ACC; i++) begin
            expected = expected + OSIZE'($signed(data_in[i]));
            send_sample(data_in[i]);
        end
        expect_output(expected);
    end
    endtask

    // ------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------
    integer i;
    logic signed [ISIZE-1:0] vec [0:NO2ACC-1];
    logic signed [OSIZE-1:0] expected_sum;

    initial begin
        in_data_w   = '0;
        in_valid_w  = 1'b0;
        out_ready_w = 1'b1;
        rstn_w      = 1'b0;

        repeat (5) @(posedge clk_w);
        rstn_w = 1'b1;
        repeat (2) @(posedge clk_w);

        if (VERBOSE) begin
            $display("==================================================");
            $display("Starting tb_accumulator");
            $display("IN_BYTES=%0d ISIZE=%0d NO2ACC=%0d OSIZE=%0d",
                     IN_BYTES, ISIZE, NO2ACC, OSIZE);
            $display("==================================================");
        end

        // Test 1: 1..NO2ACC
        expected_sum = '0;
        for (i = 0; i < NO2ACC; i++) begin
            vec[i] = ISIZE'(i + 1);
            expected_sum = expected_sum + OSIZE'($signed(vec[i]));
        end
        run_group_dynamic(vec);

        // Test 2: negative values
        expected_sum = '0;
        for (i = 0; i < NO2ACC; i++) begin
            vec[i] = ISIZE'(-(i + 1));
            expected_sum = expected_sum + OSIZE'($signed(vec[i]));
        end
        run_group_dynamic(vec);

        // Test 3: mixed signed values
        expected_sum = '0;
        for (i = 0; i < NO2ACC; i++) begin
            case (i % 4)
                0: vec[i] = ISIZE'(12);
                1: vec[i] = ISIZE'(-3);
                2: vec[i] = ISIZE'(7);
                default: vec[i] = ISIZE'(-9);
            endcase
            expected_sum = expected_sum + OSIZE'($signed(vec[i]));
        end
        run_group_dynamic(vec);

        // Test 4: output backpressure
        expected_sum = '0;
        for (i = 0; i < NO2ACC; i++) begin
            vec[i] = ISIZE'(i - 2);
            expected_sum = expected_sum + OSIZE'($signed(vec[i]));
        end

        for (i = 0; i < NO2ACC; i++) begin
            send_sample(vec[i]);
        end

        // Stall output for a few cycles
        out_ready_w = 1'b0;
        repeat (3) @(posedge clk_w);

        if (VERBOSE) begin
            $display("[%0t] Applying output backpressure", $time);
        end

        out_ready_w = 1'b1;
        expect_output(expected_sum);

        $display("PASS");
        $finish;
    end

endmodule
