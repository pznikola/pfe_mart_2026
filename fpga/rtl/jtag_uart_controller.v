module jtag_uart_controller (
    input  wire        clk,
    input  wire        rst_n,

    // Avalon-MM master interface to JTAG UART slave
    output reg         av_chipselect,
    output reg         av_address,     // 0 = data reg, 1 = control reg
    output reg         av_read_n,
    input  wire [31:0] av_readdata,
    output reg         av_write_n,
    output reg  [31:0] av_writedata,
    input  wire        av_waitrequest,

    // RX streaming interface (data read from UART)
    output reg  [7:0]  rx_data,
    output reg         rx_valid,
    input  wire        rx_ready,

    // TX streaming interface (data to write to UART)
    input  wire [7:0]  tx_data,
    input  wire        tx_valid,
    output reg         tx_ready
);

    // FSM states
    localparam S_IDLE       = 3'd0;
    localparam S_RD_WAIT    = 3'd1;  // Wait for data register read to complete
    localparam S_RX_STREAM  = 3'd2;  // Push byte onto RX streaming interface
    localparam S_WR_CHECK   = 3'd3;  // Read control register to check WSPACE
    localparam S_WR_WAIT    = 3'd4;  // Wait for control register read to complete
    localparam S_WR_DATA    = 3'd5;  // Assert write to data register
    localparam S_WR_HOLD    = 3'd6;  // Wait for write to complete

    reg [2:0] state;

    // Latched values
    reg [31:0] rd_data_latched;
    reg [15:0] wspace_latched;
    reg [7:0]  tx_data_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            av_chipselect  <= 1'b0;
            av_address     <= 1'b0;
            av_read_n      <= 1'b1;
            av_write_n     <= 1'b1;
            av_writedata   <= 32'd0;
            rx_data        <= 8'd0;
            rx_valid       <= 1'b0;
            tx_ready       <= 1'b0;
            rd_data_latched <= 32'd0;
            wspace_latched  <= 16'd0;
            tx_data_latched <= 8'd0;
        end else begin
            case (state)

                // -------------------------------------------------------
                // IDLE: start by reading the data register
                // -------------------------------------------------------
                S_IDLE: begin
                    rx_valid <= 1'b0;
                    tx_ready <= 1'b0;
                    // Begin read from data register (address 0)
                    av_chipselect <= 1'b1;
                    av_address    <= 1'b0;
                    av_read_n     <= 1'b0;
                    av_write_n    <= 1'b1;
                    state         <= S_RD_WAIT;
                end

                // -------------------------------------------------------
                // RD_WAIT: wait for Avalon read to complete
                // -------------------------------------------------------
                S_RD_WAIT: begin
                    if (!av_waitrequest) begin
                        rd_data_latched <= av_readdata;
                        // Deassert bus
                        av_chipselect <= 1'b0;
                        av_read_n     <= 1'b1;

                        // Check RVALID (bit 15)
                        if (av_readdata[15]) begin
                            // Valid data - present on RX streaming interface
                            rx_data  <= av_readdata[7:0];
                            rx_valid <= 1'b1;
                            state    <= S_RX_STREAM;
                        end else begin
                            // FIFO empty - switch to TX phase
                            rx_valid <= 1'b0;
                            state    <= S_WR_CHECK;
                        end
                    end
                    // else: stay here, bus is stalling
                end

                // -------------------------------------------------------
                // RX_STREAM: wait for downstream to accept the byte
                // -------------------------------------------------------
                S_RX_STREAM: begin
                    if (rx_ready) begin
                        rx_valid <= 1'b0;
                        // Try to read next byte from FIFO
                        av_chipselect <= 1'b1;
                        av_address    <= 1'b0;
                        av_read_n     <= 1'b0;
                        av_write_n    <= 1'b1;
                        state         <= S_RD_WAIT;
                    end
                    // else: hold rx_data and rx_valid, wait for ready
                end

                // -------------------------------------------------------
                // WR_CHECK: read control register to get WSPACE
                // -------------------------------------------------------
                S_WR_CHECK: begin
                    tx_ready <= 1'b0;
                    av_chipselect <= 1'b1;
                    av_address    <= 1'b1;   // Control register
                    av_read_n     <= 1'b0;
                    av_write_n    <= 1'b1;
                    state         <= S_WR_WAIT;
                end

                // -------------------------------------------------------
                // WR_WAIT: wait for control register read to complete
                // -------------------------------------------------------
                S_WR_WAIT: begin
                    if (!av_waitrequest) begin
                        wspace_latched <= av_readdata[31:16];
                        av_chipselect  <= 1'b0;
                        av_read_n      <= 1'b1;

                        if (av_readdata[31:16] != 16'd0 && tx_valid) begin
                            // There's space and upstream has data - latch it
                            tx_data_latched <= tx_data;
                            tx_ready        <= 1'b1;
                            state           <= S_WR_DATA;
                        end else begin
                            // No space or no data to send - go back to RX phase
                            state <= S_IDLE;
                        end
                    end
                end

                // -------------------------------------------------------
                // WR_DATA: assert write bus signals (one setup cycle)
                // -------------------------------------------------------
                S_WR_DATA: begin
                    tx_ready       <= 1'b0;
                    av_chipselect  <= 1'b1;
                    av_address     <= 1'b0;   // Data register
                    av_read_n      <= 1'b1;
                    av_write_n     <= 1'b0;
                    av_writedata   <= {24'd0, tx_data_latched};
                    state          <= S_WR_HOLD;
                end

                // -------------------------------------------------------
                // WR_HOLD: wait for waitrequest to deassert
                // -------------------------------------------------------
                S_WR_HOLD: begin
                    if (!av_waitrequest) begin
                        // Write accepted - deassert bus, go back to RX phase
                        av_chipselect <= 1'b0;
                        av_write_n    <= 1'b1;
                        state         <= S_IDLE;
                    end
                    // else: hold bus signals, slave is stalling
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
