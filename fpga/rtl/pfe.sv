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

    logic [31:0] data_w;
    logic                  ready_w, valid_w;

    byte_deserializer #(
        .NUM_BYTES (4)
    ) u_deserializer (
        .clk      (clk_i),
        .rst_n    (rst_ni),
        .in_data  (in_data_i),
        .in_valid (in_valid_i),
        .in_ready (in_ready_o),
        .out_data (data_w),
        .out_valid(valid_w),
        .out_ready(ready_w)
    );

    byte_serializer #(
        .NUM_BYTES (4)
    ) u_serializer (
        .clk      (clk_i),
        .rst_n    (rst_ni),
        .in_data  (data_w),
        .in_valid (valid_w),
        .in_ready (ready_w),
        .out_data (out_data_o),
        .out_valid(out_valid_o),
        .out_ready(out_ready_i)
    );

endmodule
