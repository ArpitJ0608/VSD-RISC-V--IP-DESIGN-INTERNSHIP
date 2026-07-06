// =============================================================
// spi_clk_div.v
// Programmable SPI clock divider
// SCLK toggles every (clk_div + 1) system clock cycles
// =============================================================
module spi_clk_div(
    input clk,
    input rst,
    input enable,
    input [7:0] clk_div,
    output reg spi_clk,
    output reg tick
);

    reg [7:0] counter;

    always @(posedge clk) begin
        if(rst) begin
            counter <= 8'd0;
            tick    <= 1'b0;
            spi_clk <= 1'b0;
        end
        else if(enable) begin
            if(counter == clk_div) begin
                counter <= 8'd0;
                spi_clk <= ~spi_clk;
                tick    <= 1'b1;
            end
            else begin
                counter <= counter + 1'b1;
                tick    <= 1'b0;
            end
        end
        else begin
            counter <= 8'd0;
            tick    <= 1'b0;
            spi_clk <= 1'b0;
        end
    end
endmodule
