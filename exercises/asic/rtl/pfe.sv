module pfe #(
    parameter int DSIZE  = 8
)(
    input  logic             clk_i,
    input  logic             rst_ni,
    // Input
    input  logic [DSIZE-1:0] in_data_i,
    input  logic             in_valid_i,
    output logic             in_ready_o,
    // Output
    output logic [DSIZE-1:0] out_data_o,
    output logic             out_valid_o,
    input  logic             out_ready_i
);

    localparam int NO2ACC = 8;
    localparam int IN_BYTES  = DSIZE / 8;
    localparam int SAFE_M    = (NO2ACC < 1) ? 1 : NO2ACC;
    localparam int ACC_BITS  = DSIZE + $clog2(SAFE_M);
    localparam int ACC_BYTES = (ACC_BITS + 7) / 8;
    localparam int ACC_WIDTH = ACC_BYTES * 8;

    // Optional guard: serializer output is 8-bit, so this module
    // is intended for DSIZE == 8.
    generate
        if (DSIZE != 8) begin : g_bad_dsize
            DSIZE_MUST_BE_8_FOR_THIS_PFE invalid_inst();
        end
    endgenerate

    logic signed [ACC_WIDTH-1:0] acc_data;
    logic                        acc_valid;
    logic                        acc_ready;

    accumulator #(
        .IN_BYTES (IN_BYTES),
        .NO2ACC   (NO2ACC)
    ) u_accumulator (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .in_data_i  (in_data_i),
        .in_valid_i (in_valid_i),
        .in_ready_o (in_ready_o),
        .out_data_o (acc_data),
        .out_valid_o(acc_valid),
        .out_ready_i(acc_ready)
    );

    byte_serializer #(
        .NUM_BYTES (ACC_BYTES)
    ) u_serializer (
        .clk      (clk_i),
        .rst_n    (rst_ni),
        .in_data  (acc_data),
        .in_valid (acc_valid),
        .in_ready (acc_ready),
        .out_data (out_data_o),
        .out_valid(out_valid_o),
        .out_ready(out_ready_i)
    );

endmodule
