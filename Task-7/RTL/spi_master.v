// =============================================================
// spi_master.v
// SPI Master IP - Top level
// Mode 0 (CPOL=0, CPHA=0), 8-bit, single transfer, polling based
// =============================================================
module spi_master (
    input clk,
    input rst,
    input write_en,
    input [1:0] addr_off,
    input [31:0] w_data,
    output reg [31:0] r_data,
    output sclk,
    output mosi,
    input miso,
    output reg cs_n
);

    reg [31:0] ctrl_reg;
    reg [31:0] status_reg;
    reg [7:0]  tx_reg;
    reg [7:0]  rx_reg;
    reg [2:0]  bit_count;

    wire spi_clk;
    wire tick;
    reg  [1:0] state;

    localparam IDLE     = 2'd0;
    localparam LOAD     = 2'd1;
    localparam TRANSFER = 2'd2;
    localparam DONE     = 2'd3;

    assign sclk = spi_clk;

    // Programmable SPI clock generator
    spi_clk_div clk_inst (
        .clk(clk),
        .rst(rst),
        .enable(state == TRANSFER),
        .clk_div(ctrl_reg[15:8]),
        .spi_clk(spi_clk),
        .tick(tick)
    );

    wire [7:0] rx_data;
    reg  shift_en;
    reg  load, busy;

    // 8-bit TX/RX shift register
    spi_shift shift_inst (
        .clk(clk),
        .rst(rst),
        .load(load),
        .shift_en(shift_en),
        .tx_data(tx_reg),
        .miso(miso),
        .mosi(mosi),
        .rx_data(rx_data)
    );

    // ---- bit counter (0..7) ----
    always @(posedge clk) begin
        if (rst)
            bit_count <= 3'd0;
        else if (state == LOAD)
            bit_count <= 3'd0;
        else if (state == TRANSFER && tick)
            bit_count <= bit_count + 1'b1;
    end

    // ---- FSM (sequential) ----
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (ctrl_reg[0] && ctrl_reg[1])
                        state <= LOAD;
                end

                LOAD: begin
                    state <= TRANSFER;
                    $display("SPI START");
                    status_reg[0] <= 1'b1;   // BUSY = 1
                    ctrl_reg[1]   <= 1'b0;   // auto-clear START
                end

                TRANSFER: begin
                    if (bit_count == 3'd7 && tick)
                        state <= DONE;
                end

                DONE: begin
                    $display("SPI DONE");
                    state <= IDLE;
                    status_reg[0] <= 1'b0;   // BUSY = 0
                    status_reg[1] <= 1'b1;   // DONE = 1
                    rx_reg <= rx_data;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // ---- FSM (combinational outputs) ----
    always @(*) begin
        load     = 1'b0;
        shift_en = 1'b0;
        busy     = 1'b0;
        cs_n     = 1'b1;

        case (state)
            IDLE: begin
                busy = 1'b0;
                cs_n = 1'b1;
            end
            LOAD: begin
                load = 1'b1;
                busy = 1'b1;
                cs_n = 1'b0;
            end
            TRANSFER: begin
                busy = 1'b1;
                cs_n = 1'b0;
                if (tick)
                    shift_en = 1'b1;
            end
            DONE: begin
                busy = 1'b0;
                cs_n = 1'b1;
            end
        endcase
    end

    // ---- register writes (synchronous) ----
    always @(posedge clk) begin
        if (rst) begin
            ctrl_reg   <= 32'd0;
            status_reg <= 32'd0;
            tx_reg     <= 8'd0;
            rx_reg     <= 8'd0;
            bit_count  <= 3'd0;
        end
        else if (write_en) begin
            case (addr_off)
                2'b00: begin
                    ctrl_reg <= w_data;
                end
                2'b01: tx_reg <= w_data[7:0];
                2'b11: if (w_data[1])
                           status_reg[1] <= 1'b0;   // write-1-to-clear DONE
            endcase
        end
    end

    // ---- register reads (combinational) ----
    always @(*) begin
        case (addr_off)
            2'b00: r_data = ctrl_reg;
            2'b01: r_data = {24'd0, tx_reg};
            2'b10: r_data = {24'd0, rx_reg};
            2'b11: r_data = {30'b0, status_reg[1], status_reg[0]};
            default: r_data = 32'd0;
        endcase
    end
endmodule
