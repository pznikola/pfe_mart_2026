module pfe #(
    parameter int DSIZE  = 8
)(
    input  logic             clk_i,
    input  logic             rst_ni,
    // Input
    input  logic [DSIZE-1:0] a_i,
    input  logic [DSIZE-1:0] b_i,
    // Output
    output logic [DSIZE-1:0] c_o
);

    always_ff @(posedge clk_i, negedge rst_ni) begin
      if (rst_ni == 1'b0) begin
        c_o <= '0;
      end
      else begin
        c_o <= a_i + b_i;
      end
    end

endmodule
