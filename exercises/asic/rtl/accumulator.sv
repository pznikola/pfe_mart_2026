module accumulator #(
    parameter int IN_BYTES = 2,
    parameter int NO2ACC   = 8
) (
    input  logic                               clk_i,
    input  logic                               rst_ni,

    input  logic signed [IN_BYTES*8-1:0]       in_data_i,
    input  logic                               in_valid_i,
    output logic                               in_ready_o,

    output logic signed [(((IN_BYTES*8)+$clog2((NO2ACC<1)?1:NO2ACC)+7)/8)*8-1:0] out_data_o,
    output logic                               out_valid_o,
    input  logic                               out_ready_i
);

    localparam int ISIZE     = IN_BYTES * 8;
    localparam int SAFE_M    = (NO2ACC < 1) ? 1 : NO2ACC;
    localparam int ACC_BITS  = ISIZE + $clog2(SAFE_M);
    localparam int OUT_BYTES = (ACC_BITS + 7) / 8;
    localparam int OSIZE     = OUT_BYTES * 8;

    generate
        if (NO2ACC < 1) begin : g_invalid_m
            PARAMETER_M_MUST_BE_AT_LEAST_1 invalid_inst();
        end

        if (IN_BYTES < 1) begin : g_invalid_in_bytes
            PARAMETER_IN_BYTES_MUST_BE_AT_LEAST_1 invalid_inst();
        end
    endgenerate

    logic signed [OSIZE-1:0] acc_r;
    logic [$clog2(SAFE_M+1)-1:0] count_r;

    wire in_fire_w  = in_valid_i && in_ready_o;
    wire out_fire_w = out_valid_o && out_ready_i;

    assign in_ready_o = !out_valid_o;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            acc_r       <= '0;
            count_r     <= '0;
            out_data_o  <= '0;
            out_valid_o <= 1'b0;
        end else begin
            if (out_fire_w) begin
                out_valid_o <= 1'b0;
                out_data_o  <= '0;
                acc_r       <= '0;
                count_r     <= '0;
            end

            if (in_fire_w) begin
                if (count_r == $clog2(SAFE_M+1)'(NO2ACC-1)) begin
                    out_data_o  <= acc_r + OSIZE'($signed(in_data_i));
                    out_valid_o <= 1'b1;
                end else begin
                    acc_r   <= acc_r + OSIZE'($signed(in_data_i));
                    count_r <= count_r + 1'b1;
                end
            end
        end
    end

endmodule
