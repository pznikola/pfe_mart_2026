// jtag_uart_top.v
//
// Data flow:
//   PC  →  JTAG UART  →  controller rx (8-bit)
//                              ↓
//                       deserializer (collects NUM_BYTES bytes)
//                              ↓
//                         pfe (NUM_BYTES*8 bits wide)
//                              ↓
//                        serializer (breaks back into bytes)
//                              ↓
//                       controller tx (8-bit)  →  JTAG UART  →  PC
//
// Change NUM_BYTES to set the processing width:
//   1 = 8-bit,  2 = 16-bit,  3 = 24-bit,  4 = 32-bit, etc.
//
// The PC must send data in multiples of NUM_BYTES.

`default_nettype none

module jtag_uart_top (
    input wire CLOCK_50,
    input wire RSTN
);

    // =====================================================
    // Change this parameter to set the word width
    // =====================================================
    localparam NUM_BYTES = 1;   // 4 bytes = 32 bits
    // =====================================================

    wire rst_n = RSTN;

    // Avalon-MM bus
    wire        av_chipselect;
    wire        av_address;
    wire        av_read_n;
    wire [31:0] av_readdata;
    wire        av_write_n;
    wire [31:0] av_writedata;
    wire        av_waitrequest;

    // Controller RX stream (8-bit bytes from PC) and TX stream (8-bit bytes to PC)
    wire [7:0]  ctrl_fifo_data;
    wire        ctrl_fifo_valid;
    wire        ctrl_fifo_ready;
    wire [7:0]  fifo_ctrl_data;
    wire        fifo_ctrl_valid;
    wire        fifo_ctrl_ready;

    // FIFO to PFE and back
    wire [NUM_BYTES*8-1:0] fifo_pfe_data;
    wire                   fifo_pfe_valid;
    wire                   fifo_pfe_ready;
    wire [NUM_BYTES*8-1:0] pfe_fifo_data;
    wire                   pfe_fifo_valid;
    wire                   pfe_fifo_ready;

    // Platform Designer system
    jtag_uart_sys u_sys (
        .clk_clk                              (CLOCK_50),
        .reset_reset_n                        (rst_n),
        .jtag_uart_avalon_chipselect          (av_chipselect),
        .jtag_uart_avalon_address             (av_address),
        .jtag_uart_avalon_read_n              (av_read_n),
        .jtag_uart_avalon_readdata            (av_readdata),
        .jtag_uart_avalon_write_n             (av_write_n),
        .jtag_uart_avalon_writedata           (av_writedata),
        .jtag_uart_avalon_waitrequest         (av_waitrequest)
    );

    // JTAG UART controller
    jtag_uart_controller u_ctrl (
        .clk              (CLOCK_50),
        .rst_n            (rst_n),
        .av_chipselect    (av_chipselect),
        .av_address       (av_address),
        .av_read_n        (av_read_n),
        .av_readdata      (av_readdata),
        .av_write_n       (av_write_n),
        .av_writedata     (av_writedata),
        .av_waitrequest   (av_waitrequest),
        .rx_data          (ctrl_fifo_data),
        .rx_valid         (ctrl_fifo_valid),
        .rx_ready         (ctrl_fifo_ready),
        .tx_data          (fifo_ctrl_data),
        .tx_valid         (fifo_ctrl_valid),
        .tx_ready         (fifo_ctrl_ready)
    );

    // FIFO between ctrl and deserializer
    fifo #(
      .DSIZE (8),
      .ASIZE (8)
    ) u_fifo_deser (
      .clk_i        (CLOCK_50),     
      .rst_ni       (rst_n),
      .in_data_i    (ctrl_fifo_data),    
      .in_valid_i   (ctrl_fifo_valid),
      .in_ready_o   (ctrl_fifo_ready),
      .out_data_o   (fifo_pfe_data),
      .out_valid_o  (fifo_pfe_valid),
      .out_ready_i  (fifo_pfe_ready)
    );


    // Processing module
    pfe #(
        .DSIZE (8)
    ) u_pfe (
        .clk_i        (CLOCK_50),
        .rst_ni       (rst_n),
        .in_data_i    (fifo_pfe_data),
        .in_valid_i   (fifo_pfe_valid),
        .in_ready_o   (fifo_pfe_ready),
        .out_data_o   (pfe_fifo_data),
        .out_valid_o  (pfe_fifo_valid),
        .out_ready_i  (pfe_fifo_ready)
    );

    // FIFO between serializer and ctrl
    fifo #(
      .DSIZE (8), 
      .ASIZE (8)
    ) u_fifo_ser (
      .clk_i        (CLOCK_50),     
      .rst_ni       (rst_n),    
      .in_data_i    (pfe_fifo_data),
      .in_valid_i   (pfe_fifo_valid),
      .in_ready_o   (pfe_fifo_ready),
      .out_data_o   (fifo_ctrl_data),
      .out_valid_o  (fifo_ctrl_valid),
      .out_ready_i  (fifo_ctrl_ready)
    );

endmodule

`default_nettype wire
