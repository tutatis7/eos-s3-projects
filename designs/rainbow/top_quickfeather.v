// Rainbow for the QuickFeather / QuickFeather Lite: the USR button controls the fade.
//
//   tap (< 0.6 s)             pause / resume
//   long press (0.6 - 2 s)    speed
//   very long press (> 2 s)   brightness
//
// The action happens when you let go.

module top #(
    parameter CLK_HZ  = 12_000_000,
    parameter PWM_DIV = 32
) (
    output wire red_led,
    output wire green_led,
    output wire blue_led,
    input  wire usr_btn          // low while pressed; pull-up enabled by build.sh (see quickfeather.pcf)
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

    wire tick_ms;
    wire btn_held, btn_tap, btn_long, btn_very_long;

    button_press u_button (
        .clk             (clk),
        .rst             (rst),
        .tick_ms         (tick_ms),
        .pin_n           (usr_btn),
        .held            (btn_held),
        .tap             (btn_tap),
        .long_press      (btn_long),
        .very_long_press (btn_very_long)
    );

    rainbow_core #(.CLK_HZ(CLK_HZ), .PWM_DIV(PWM_DIV)) u_core (
        .clk          (clk),
        .rst          (rst),
        .pause_toggle (btn_tap),
        .speed_next   (btn_long),
        .dim_next     (btn_very_long),
        .jump         (1'b0),
        .tick_ms      (tick_ms),
        .red_led      (red_led),
        .green_led    (green_led),
        .blue_led     (blue_led)
    );

endmodule
