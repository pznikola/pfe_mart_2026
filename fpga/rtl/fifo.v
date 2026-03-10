`default_nettype none

module fifo #(
  parameter DSIZE = 8,
  parameter ASIZE = 4
) (
  input  wire             clk_i,
  input  wire             rst_ni,        // async active-low reset

  // Input stream (producer -> FIFO)
  input  wire             in_valid_i,
  output wire             in_ready_o,
  input  wire [DSIZE-1:0] in_data_i,

  // Output stream (FIFO -> consumer)
  output wire             out_valid_o,
  input  wire             out_ready_i,
  output wire [DSIZE-1:0] out_data_o
);

  localparam DEPTH = (1 << ASIZE);

  reg [DSIZE-1:0] mem [0:DEPTH-1];
  reg [ASIZE-1:0] wr_ptr_r, rd_ptr_r;
  reg [ASIZE:0]   count_r; // 0..DEPTH

  // Ready/Valid derived from occupancy
  assign in_ready_o  = (count_r != DEPTH);
  assign out_valid_o = (count_r != 0);

  // Asynchronous read datapath (like your previous FIFO style)
  assign out_data_o  = mem[rd_ptr_r];

  wire do_push = in_valid_i  && in_ready_o;
  wire do_pop  = out_valid_o && out_ready_i;

  // Write memory on push
  always @(posedge clk_i) begin
    if (do_push)
      mem[wr_ptr_r] <= in_data_i;
  end

  // Update pointers
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_ptr_r <= {ASIZE{1'b0}};
      rd_ptr_r <= {ASIZE{1'b0}};
    end else begin
      if (do_push) wr_ptr_r <= wr_ptr_r + {{(ASIZE-1){1'b0}}, 1'b1};
      if (do_pop)  rd_ptr_r <= rd_ptr_r + {{(ASIZE-1){1'b0}}, 1'b1};
    end
  end

  // Update occupancy count
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      count_r <= {(ASIZE+1){1'b0}};
    end else begin
      case ({do_push, do_pop})
        2'b10: count_r <= count_r + 1; // push only
        2'b01: count_r <= count_r - 1; // pop only
        default: count_r <= count_r;   // both or neither
      endcase
    end
  end

endmodule

`default_nettype wire
