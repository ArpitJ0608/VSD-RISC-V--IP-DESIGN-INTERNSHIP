// =============================================================
// spi_shift.v
// 8-bit MSB-first TX/RX shift register
// =============================================================
module spi_shift(
    input clk,
    input rst,
    input load,
    input shift_en,
    input [7:0] tx_data,
    input miso,
    output mosi,
    output [7:0] rx_data
);

    reg [7:0] shift_tx;
    reg [7:0] shift_rx;

    always @(posedge clk) begin
        if(rst) begin
            shift_tx <= 8'd0;
            shift_rx <= 8'd0;
        end
        else begin
            if(load) begin
                shift_tx <= tx_data;
                shift_rx <= 8'd0;
            end
            else if(shift_en) begin
                shift_tx <= {shift_tx[6:0],1'b0};
                shift_rx <= {shift_rx[6:0],miso};
            end
        end
    end

    assign mosi = shift_tx[7];
    assign rx_data = shift_rx;
endmodule
