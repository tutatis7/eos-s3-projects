// Rainbow for the Qomu: four touch pads control the fade.
//
//   pad 1 (IO_10)  pause / resume
//   pad 2 (IO_17)  speed
//   pad 3 (IO_0)   brightness
//   pad 4 (IO_29)  jump ahead 60 degrees

module top #(
    parameter CLK_HZ  = 12_000_000,
    parameter PWM_DIV = 32
) (
    output wire red_led,
    output wire green_led,
    output wire blue_led,
    inout  wire touch1,
    inout  wire touch2,
    inout  wire touch3,
    inout  wire touch4
);

    // Clock (12 MHz) and reset from the SoC, on the global clock network.
    // Without gclkbuff, larger designs fail on hardware.
    wire sys_clk, sys_rst, clk, rst;

    qlal4s3b_cell_macro u_qlal4s3b_cell_macro (
        .Sys_Clk0     (sys_clk),
        .Sys_Clk0_Rst (sys_rst)
    );

    gclkbuff u_gclkbuff_clock (.A(sys_clk), .Z(clk));
    gclkbuff u_gclkbuff_reset (.A(sys_rst), .Z(rst));

    wire       tick_ms;
    wire [3:0] touched;
    wire [3:0] pressed;

    touch_sense u_touch1 (.clk(clk), .rst(rst), .tick_ms(tick_ms), .pad(touch1), .touched(touched[0]), .pressed(pressed[0]));
    touch_sense u_touch2 (.clk(clk), .rst(rst), .tick_ms(tick_ms), .pad(touch2), .touched(touched[1]), .pressed(pressed[1]));
    touch_sense u_touch3 (.clk(clk), .rst(rst), .tick_ms(tick_ms), .pad(touch3), .touched(touched[2]), .pressed(pressed[2]));
    touch_sense u_touch4 (.clk(clk), .rst(rst), .tick_ms(tick_ms), .pad(touch4), .touched(touched[3]), .pressed(pressed[3]));

    rainbow_core #(.CLK_HZ(CLK_HZ), .PWM_DIV(PWM_DIV)) u_core (
        .clk          (clk),
        .rst          (rst),
        .pause_toggle (pressed[0]),
        .speed_next   (pressed[1]),
        .dim_next     (pressed[2]),
        .jump         (pressed[3]),
        .tick_ms      (tick_ms),
        .red_led      (red_led),
        .green_led    (green_led),
        .blue_led     (blue_led)
    );

endmodule
