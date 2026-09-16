// Qomu (QuickLogic EOS S3) FPGA-only blinky.
//
// Cycles the on-board RGB LED red -> green -> blue, one step every 0.5 s.
//
// Clocking: the eFPGA fabric has no oscillator pin of its own. The clock comes
// from the M4 side through the qlal4s3b_cell_macro. When the bootloader runs an
// FPGA-only image ("--mode fpga") it enables clock C16, which appears here as
// Sys_Clk0, at 12 MHz.
//
// LEDs: the RGB LED's cathodes are switched by N-channel MOSFETs whose gates are
// driven by the EOS S3, so a '1' on the pin turns the LED on (active high).

module top (
    output wire red_led,
    output wire green_led,
    output wire blue_led
);

    // 12 MHz from Sys_Clk0 -> 6,000,000 ticks = 0.5 s
    localparam [23:0] TICKS_PER_STEP = 24'd6_000_000;

    wire sys_clk;
    wire sys_rst;
    wire clk;
    wire rst;

    // Only the clock/reset outputs of the SoC interface macro are used.
    qlal4s3b_cell_macro u_qlal4s3b_cell_macro (
        .Sys_Clk0     (sys_clk),
        .Sys_Clk0_Rst (sys_rst)
    );

    // Route clock and reset on the FPGA's global clock network
    gclkbuff u_gclkbuff_clock (.A(sys_clk), .Z(clk));
    gclkbuff u_gclkbuff_reset (.A(sys_rst), .Z(rst));

    reg [23:0] count = 24'd0;
    reg [2:0]  rgb   = 3'b001;   // one-hot {blue, green, red}

    wire rgb_valid = (rgb == 3'b001) || (rgb == 3'b010) || (rgb == 3'b100);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count <= 24'd0;
            rgb   <= 3'b001;
        end else if (!rgb_valid) begin
            // Initial values are not guaranteed on this flow and reset may not
            // be pulsed, so recover from any non one-hot power-up state.
            count <= 24'd0;
            rgb   <= 3'b001;
        end else if (count >= TICKS_PER_STEP - 1) begin
            count <= 24'd0;
            rgb   <= {rgb[1:0], rgb[2]};   // rotate R -> G -> B -> R
        end else begin
            count <= count + 24'd1;
        end
    end

    assign red_led   = rgb[0];
    assign green_led = rgb[1];
    assign blue_led  = rgb[2];

endmodule
