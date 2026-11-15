// Serial UART (8N1) used by UART1.
//   - one start bit, 8 data bits (LSB first), one stop bit, no parity
//   - bit time = BAUD_DIV clocks (BAUD_DIV >= 2)
//   - RX and TX FIFOs of FIFO_DEPTH bytes
//   - RTS/CTS handshake lines; RTS is a plain FW-controlled bit (no automatic logic)
// See platform/UART1_DATASHEET.md for the register interface.

module sync_fifo #(
    parameter WIDTH = 8 ,
    parameter DEPTH = 16
)(
    input  wire                       i_clk   ,
    input  wire                       i_rst_n ,
    input  wire                       i_push  ,
    input  wire [WIDTH-1:0]           i_din   ,
    input  wire                       i_pop   ,
    output wire [WIDTH-1:0]           o_dout  ,
    output wire                       o_full  ,
    output wire                       o_empty ,
    output wire [$clog2(DEPTH):0]     o_level
);
    localparam AW = $clog2(DEPTH);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW-1:0]    wr_ptr, rd_ptr;
    reg [AW:0]      count;

    assign o_full  = (count == DEPTH);
    assign o_empty = (count == 0);
    assign o_level = count;
    assign o_dout  = mem[rd_ptr];

    wire do_push = i_push && !o_full;
    wire do_pop  = i_pop  && !o_empty;

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
        end else begin
            if (do_push) begin
                mem[wr_ptr] <= i_din;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (do_pop) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            case ({do_push, do_pop})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule


module uart_serial #(
    parameter FIFO_DEPTH  = 16 ,
    parameter DEFAULT_DIV = 32
)(
    input  wire        i_clk      ,
    input  wire        i_rst_n    ,

    // serial pins
    input  wire        i_rx       ,
    output wire        o_tx       ,
    output wire        o_rts_n    ,   // low = FW is ready to receive
    input  wire        i_cts_n    ,   // low = peer is ready to receive

    // register interface (one-cycle strobes)
    input  wire        i_wr_baud  ,
    input  wire        i_wr_ctrl  ,
    input  wire        i_wr_tx    ,
    input  wire        i_rd_rx    ,
    input  wire [31:0] i_wdata    ,
    output wire [31:0] o_status   ,
    output wire [31:0] o_rx_data
);
    localparam LW = $clog2(FIFO_DEPTH) + 1;

    // ---------------------------------------------------------------
    // control registers
    // ---------------------------------------------------------------
    reg [31:0] baud_div;
    reg        rts;
    wire       clr_err = i_wr_ctrl && i_wdata[1];

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            baud_div <= DEFAULT_DIV;
            rts      <= 1'b0;
        end else begin
            if (i_wr_baud) baud_div <= i_wdata;
            if (i_wr_ctrl) rts      <= i_wdata[0];
        end
    end

    assign o_rts_n = ~rts;

    // ---------------------------------------------------------------
    // TX path
    // ---------------------------------------------------------------
    wire [7:0]    txf_dout;
    wire          txf_full, txf_empty;
    wire [LW-1:0] txf_level;
    reg           txf_pop;

    sync_fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) u_tx_fifo (
        .i_clk   (i_clk)           ,
        .i_rst_n (i_rst_n)         ,
        .i_push  (i_wr_tx)         ,
        .i_din   (i_wdata[7:0])    ,
        .i_pop   (txf_pop)         ,
        .o_dout  (txf_dout)        ,
        .o_full  (txf_full)        ,
        .o_empty (txf_empty)       ,
        .o_level (txf_level)
    );

    reg        tx_busy;
    reg [9:0]  tx_sh;
    reg [3:0]  tx_bit;
    reg [31:0] tx_cnt;

    always @(posedge i_clk) begin
        txf_pop <= 1'b0;
        if (!i_rst_n) begin
            tx_busy <= 1'b0;
            tx_sh   <= 10'h3FF;
            tx_bit  <= 4'd0;
            tx_cnt  <= 32'd0;
        end else if (!tx_busy) begin
            // CTS is only checked at the start of each byte
            if (!txf_empty && !i_cts_n && !txf_pop) begin
                tx_sh   <= {1'b1, txf_dout, 1'b0};   // stop, data, start
                tx_busy <= 1'b1;
                tx_bit  <= 4'd0;
                tx_cnt  <= baud_div - 1'b1;
                txf_pop <= 1'b1;
            end
        end else begin
            if (tx_cnt == 0) begin
                tx_cnt <= baud_div - 1'b1;
                if (tx_bit == 4'd9) begin
                    tx_busy <= 1'b0;
                end else begin
                    tx_sh  <= {1'b1, tx_sh[9:1]};
                    tx_bit <= tx_bit + 1'b1;
                end
            end else begin
                tx_cnt <= tx_cnt - 1'b1;
            end
        end
    end

    assign o_tx = tx_busy ? tx_sh[0] : 1'b1;

    // ---------------------------------------------------------------
    // RX path
    // ---------------------------------------------------------------
    reg rx_s0, rx_s1;
    always @(posedge i_clk) begin
        rx_s0 <= i_rx;
        rx_s1 <= rx_s0;
    end

    localparam [2:0] R_IDLE = 3'd0, R_START = 3'd1, R_DATA = 3'd2, R_STOP = 3'd3, R_WAIT = 3'd4;

    reg [2:0]  rx_state;
    reg [31:0] rx_cnt;
    reg [2:0]  rx_bit;
    reg [7:0]  rx_sh;
    reg        rx_push;
    reg        overrun, frame_err;

    wire [7:0]    rxf_dout;
    wire          rxf_full, rxf_empty;
    wire [LW-1:0] rxf_level;

    sync_fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) u_rx_fifo (
        .i_clk   (i_clk)           ,
        .i_rst_n (i_rst_n)         ,
        .i_push  (rx_push)         ,
        .i_din   (rx_sh)           ,
        .i_pop   (i_rd_rx)         ,
        .o_dout  (rxf_dout)        ,
        .o_full  (rxf_full)        ,
        .o_empty (rxf_empty)       ,
        .o_level (rxf_level)
    );

    always @(posedge i_clk) begin
        rx_push <= 1'b0;
        if (clr_err) begin
            overrun   <= 1'b0;
            frame_err <= 1'b0;
        end
        if (!i_rst_n) begin
            rx_state  <= R_IDLE;
            rx_cnt    <= 32'd0;
            rx_bit    <= 3'd0;
            rx_sh     <= 8'd0;
            overrun   <= 1'b0;
            frame_err <= 1'b0;
        end else begin
            case (rx_state)
                R_IDLE: begin
                    if (!rx_s1) begin
                        rx_cnt   <= (baud_div >> 1) - 1'b1;
                        rx_state <= R_START;
                    end
                end
                R_START: begin           // re-check the start bit at mid-bit
                    if (rx_cnt == 0) begin
                        if (!rx_s1) begin
                            rx_cnt   <= baud_div - 1'b1;
                            rx_bit   <= 3'd0;
                            rx_state <= R_DATA;
                        end else begin
                            rx_state <= R_IDLE;   // glitch
                        end
                    end else begin
                        rx_cnt <= rx_cnt - 1'b1;
                    end
                end
                R_DATA: begin
                    if (rx_cnt == 0) begin
                        rx_sh  <= {rx_s1, rx_sh[7:1]};
                        rx_cnt <= baud_div - 1'b1;
                        if (rx_bit == 3'd7) rx_state <= R_STOP;
                        else                rx_bit   <= rx_bit + 1'b1;
                    end else begin
                        rx_cnt <= rx_cnt - 1'b1;
                    end
                end
                R_STOP: begin
                    if (rx_cnt == 0) begin
                        if (rx_s1) begin
                            if (rxf_full) overrun <= 1'b1;
                            else          rx_push <= 1'b1;
                            rx_state <= R_IDLE;
                        end else begin
                            frame_err <= 1'b1;
                            rx_state  <= R_WAIT;  // wait for the line to go idle
                        end
                    end else begin
                        rx_cnt <= rx_cnt - 1'b1;
                    end
                end
                R_WAIT: begin
                    if (rx_s1) rx_state <= R_IDLE;
                end
                default: rx_state <= R_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------------
    // status / data read-back
    // ---------------------------------------------------------------
    assign o_status = {8'd0,
                       {(8-LW){1'b0}}, txf_level,       // [23:16] TX_LEVEL
                       {(8-LW){1'b0}}, rxf_level,       // [15:8]  RX_LEVEL
                       ~i_cts_n,                        // [7]     CTS
                       (txf_empty & ~tx_busy),          // [6]     TX_IDLE
                       txf_empty,                       // [5]     TX_EMPTY
                       txf_full,                        // [4]     TX_FULL
                       frame_err,                       // [3]     FRAME_ERR
                       overrun,                         // [2]     OVERRUN
                       rxf_full,                        // [1]     RX_FULL
                       ~rxf_empty};                     // [0]     RX_NOT_EMPTY

    assign o_rx_data = {23'd0, ~rxf_empty, rxf_dout};
endmodule
