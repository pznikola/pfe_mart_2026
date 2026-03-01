// jtag_uart_top.v
//
// Data flow:
//   PC  →  JTAG UART  →  controller rx (8-bit)
//                              ↓
//                       deserializer (collects WORD_BYTES bytes)
//                              ↓
//                         pfe (WORD_BYTES*8 bits wide)
//                              ↓
//                        serializer (breaks back into bytes)
//                              ↓
//                       controller tx (8-bit)  →  JTAG UART  →  PC
//
// Change WORD_BYTES to set the processing width:
//   1 = 8-bit,  2 = 16-bit,  3 = 24-bit,  4 = 32-bit, etc.
//
// The PC must send data in multiples of WORD_BYTES.

module jtag_uart_top (
    input wire CLOCK_50,
    input wire RSTN
);

    // =====================================================
    // Change this parameter to set the word width
    // =====================================================
    localparam WORD_BYTES = 4;   // 4 bytes = 32 bits
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

    // Controller RX stream (8-bit bytes from PC)
    wire [7:0]  ctrl_rx_data;
    wire        ctrl_rx_valid;
    wire        ctrl_rx_ready;

    // Controller TX stream (8-bit bytes to PC)
    wire [7:0]  ctrl_tx_data;
    wire        ctrl_tx_valid;
    wire        ctrl_tx_ready;

    // Wide word: deserializer -> pfe
    wire [WORD_BYTES*8-1:0] deser_data;
    wire                    deser_valid;
    wire                    deser_ready;

    // Wide word: pfe -> serializer
    wire [WORD_BYTES*8-1:0] pfe_data;
    wire                    pfe_valid;
    wire                    pfe_ready;

    // --- Platform Designer system ---
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

    // --- JTAG UART controller ---
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
        .rx_data          (ctrl_rx_data),
        .rx_valid         (ctrl_rx_valid),
        .rx_ready         (ctrl_rx_ready),
        .tx_data          (ctrl_tx_data),
        .tx_valid         (ctrl_tx_valid),
        .tx_ready         (ctrl_tx_ready)
    );

    // --- Deserializer: N bytes → wide word ---
    byte_deserializer #(
        .WORD_BYTES (WORD_BYTES)
    ) u_deser (
        .clk        (CLOCK_50),
        .rst_n      (rst_n),
        .in_data    (ctrl_rx_data),
        .in_valid   (ctrl_rx_valid),
        .in_ready   (ctrl_rx_ready),
        .out_data   (deser_data),
        .out_valid  (deser_valid),
        .out_ready  (deser_ready)
    );

    // --- Processing module ---
    pfe #(
        .WORD_BYTES (WORD_BYTES)
    ) u_pfe (
        .clk        (CLOCK_50),
        .rst_n      (rst_n),
        .in_data    (deser_data),
        .in_valid   (deser_valid),
        .in_ready   (deser_ready),
        .out_data   (pfe_data),
        .out_valid  (pfe_valid),
        .out_ready  (pfe_ready)
    );

    // --- Serializer: wide word → N bytes ---
    byte_serializer #(
        .WORD_BYTES (WORD_BYTES)
    ) u_ser (
        .clk        (CLOCK_50),
        .rst_n      (rst_n),
        .in_data    (pfe_data),
        .in_valid   (pfe_valid),
        .in_ready   (pfe_ready),
        .out_data   (ctrl_tx_data),
        .out_valid  (ctrl_tx_valid),
        .out_ready  (ctrl_tx_ready)
    );

endmodule
