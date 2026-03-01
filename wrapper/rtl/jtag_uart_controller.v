// jtag_uart_controller.v
//
// Avalon-MM master that polls the JTAG UART IP.
// Exposes a simple rx/tx streaming interface for external processing.
//
//   rx_data + rx_valid + rx_ready  —  bytes received from PC
//   tx_data + tx_valid + tx_ready  —  bytes to send back to PC

module jtag_uart_controller (
    input  wire        clk,
    input  wire        rst_n,

    // Avalon-MM master to JTAG UART slave
    output reg         av_chipselect,
    output reg         av_address,
    output reg         av_read_n,
    input  wire [31:0] av_readdata,
    output reg         av_write_n,
    output reg  [31:0] av_writedata,
    input  wire        av_waitrequest,

    // RX streaming interface (data from PC)
    output reg  [7:0]  rx_data,
    output reg         rx_valid,
    input  wire        rx_ready,

    // TX streaming interface (data to PC)
    input  wire [7:0]  tx_data,
    input  wire        tx_valid,
    output wire        tx_ready   // now a wire, not reg
);

    localparam S_IDLE        = 4'd0,
               S_READ_DATA   = 4'd1,
               S_WAIT_READ   = 4'd2,
               S_HOLD_RX     = 4'd3,   // NEW: hold rx_valid until rx_ready
               S_CHECK_TX    = 4'd4,
               S_READ_CTRL   = 4'd5,
               S_WAIT_CTRL   = 4'd6,
               S_WRITE_DATA  = 4'd7,
               S_WAIT_WRITE  = 4'd8;

    reg [3:0] state;
    reg [7:0] delay;

    // TX holding register
    reg [7:0] tx_hold;
    reg       tx_pending;

    // tx_ready: accept a new byte only when no byte is already pending
    assign tx_ready = !tx_pending;

    // Latch tx_data when tx_valid & tx_ready
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_hold    <= 8'd0;
            tx_pending <= 1'b0;
        end else begin
            if (tx_valid && tx_ready) begin
                tx_hold    <= tx_data;
                tx_pending <= 1'b1;
            end else if (state == S_WAIT_WRITE && !av_waitrequest) begin
                tx_pending <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            av_chipselect <= 1'b0;
            av_address    <= 1'b0;
            av_read_n     <= 1'b1;
            av_write_n    <= 1'b1;
            av_writedata  <= 32'd0;
            rx_data       <= 8'd0;
            rx_valid      <= 1'b0;
            delay         <= 8'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    av_chipselect <= 1'b0;
                    av_read_n     <= 1'b1;
                    av_write_n    <= 1'b1;
                    if (delay < 8'd7) begin
                        delay <= delay + 1;
                    end else begin
                        delay <= 8'd0;
                        state <= S_READ_DATA;
                    end
                end

                // Poll DATA register for incoming byte
                S_READ_DATA: begin
                    av_chipselect <= 1'b1;
                    av_address    <= 1'b0;
                    av_read_n     <= 1'b0;
                    av_write_n    <= 1'b1;
                    state         <= S_WAIT_READ;
                end

                S_WAIT_READ: begin
                    if (!av_waitrequest) begin
                        av_chipselect <= 1'b0;
                        av_read_n     <= 1'b1;
                        if (av_readdata[15]) begin   // RVALID
                            rx_data  <= av_readdata[7:0];
                            rx_valid <= 1'b1;
                            state    <= S_HOLD_RX;   // wait for handshake
                        end else begin
                            state <= S_CHECK_TX;     // nothing received
                        end
                    end
                end

                // Hold rx_valid high until the deserializer accepts the byte.
                // Only then move on — this prevents silent byte drops.
                S_HOLD_RX: begin
                    if (rx_ready) begin
                        rx_valid <= 1'b0;
                        state    <= S_CHECK_TX;
                    end
                end

                // Check if we have a byte to transmit
                S_CHECK_TX: begin
                    if (tx_pending) begin
                        state <= S_READ_CTRL;
                    end else begin
                        state <= S_IDLE;
                    end
                end

                // Read CONTROL register for WSPACE
                S_READ_CTRL: begin
                    av_chipselect <= 1'b1;
                    av_address    <= 1'b1;
                    av_read_n     <= 1'b0;
                    av_write_n    <= 1'b1;
                    state         <= S_WAIT_CTRL;
                end

                S_WAIT_CTRL: begin
                    if (!av_waitrequest) begin
                        av_chipselect <= 1'b0;
                        av_read_n     <= 1'b1;
                        if (av_readdata[31:16] > 0)  // WSPACE > 0
                            state <= S_WRITE_DATA;
                        else
                            state <= S_READ_CTRL;    // retry
                    end
                end

                // Write byte to DATA register
                S_WRITE_DATA: begin
                    av_chipselect <= 1'b1;
                    av_address    <= 1'b0;
                    av_read_n     <= 1'b1;
                    av_write_n    <= 1'b0;
                    av_writedata  <= {24'd0, tx_hold};
                    state         <= S_WAIT_WRITE;
                end

                S_WAIT_WRITE: begin
                    if (!av_waitrequest) begin
                        av_chipselect <= 1'b0;
                        av_write_n    <= 1'b1;
                        state         <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
