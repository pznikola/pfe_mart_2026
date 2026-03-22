`default_nettype none

module jtag_uart_top (
    input wire CLOCK_50,
    input wire RSTN
);

    // =====================================================
    // Change this parameter to set the word width
    // =====================================================
    localparam NUM_BYTES = 4;   // 4 bytes = 32 bits
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

    // FIFO to SER/DESER and back
    wire [7:0] fifo_deser_data;
    wire       fifo_deser_valid;
    wire       fifo_deser_ready;
    wire [7:0] ser_fifo_data;
    wire       ser_fifo_valid;
    wire       ser_fifo_ready;

    // SER/DESER to PFE
    wire [NUM_BYTES*8-1:0] deser_pfe_data;
    wire                   deser_pfe_valid;
    wire                   deser_pfe_ready;
    wire [NUM_BYTES*8-1:0] pfe_ser_data;
    wire                   pfe_ser_valid;
    wire                   pfe_ser_ready;

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
      .out_data_o   (fifo_deser_data),
      .out_valid_o  (fifo_deser_valid),
      .out_ready_i  (fifo_deser_ready)
    );

    byte_deserializer #(
        .NUM_BYTES (NUM_BYTES)
    ) u_deserializer (
        .clk      (CLOCK_50),
        .rst_n    (rst_n),
        .in_data  (fifo_deser_data),
        .in_valid (fifo_deser_valid),
        .in_ready (fifo_deser_ready),
        .out_data (deser_pfe_data),
        .out_valid(deser_pfe_valid),
        .out_ready(deser_pfe_ready)
    );


    // PFE module
    pfe #(
        .DSIZE (4*8)
    ) u_pfe (
        .clk_i        (CLOCK_50),
        .rst_ni       (rst_n),
        .in_data_i    (deser_pfe_data),
        .in_valid_i   (deser_pfe_valid),
        .in_ready_o   (deser_pfe_ready),
        .out_data_o   (pfe_ser_data),
        .out_valid_o  (pfe_ser_valid),
        .out_ready_i  (pfe_ser_ready)
    );

    byte_serializer #(
        .NUM_BYTES (NUM_BYTES)
    ) u_serializer (
        .clk      (CLOCK_50),
        .rst_n    (rst_n),
        .in_data  (pfe_ser_data),
        .in_valid (pfe_ser_valid),
        .in_ready (pfe_ser_ready),
        .out_data (ser_fifo_data),
        .out_valid(ser_fifo_valid),
        .out_ready(ser_fifo_ready)
    );

    fifo #(
      .DSIZE (8), 
      .ASIZE (8)
    ) u_fifo_ser (
      .clk_i        (CLOCK_50),     
      .rst_ni       (rst_n),    
      .in_data_i    (ser_fifo_data),
      .in_valid_i   (ser_fifo_valid),
      .in_ready_o   (ser_fifo_ready),
      .out_data_o   (fifo_ctrl_data),
      .out_valid_o  (fifo_ctrl_valid),
      .out_ready_i  (fifo_ctrl_ready)
    );

endmodule

`default_nettype wire
