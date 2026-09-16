// Self-checking testbench for the rainbow design on the QuickFeather (USR button).
//
// Runs the real top_quickfeather.v, rainbow_core.v and button_press.v with a
// 10 kHz clock instead of 12 MHz (CLK_HZ is scaled to match, so all
// millisecond timing stays the same).
//
// The button is modeled like the board: a switch to ground plus the pad pull-up.
// Presses include contact bounce.
`timescale 1us/1us

module tb_top;

    localparam MS = 1000;   // 1 ms in time units (us)

    // ---------------- stimulus ----------------
    reg  contact = 1'b0;    // 1 = switch closed
    wire usr_btn;
    wire red_led, green_led, blue_led;

    assign usr_btn = contact ? 1'b0 : 1'bz;
    pullup (usr_btn);

    top #(.CLK_HZ(10_000), .PWM_DIV(1)) dut (
        .red_led(red_led), .green_led(green_led), .blue_led(blue_led),
        .usr_btn(usr_btn)
    );

    // ---------------- helpers ----------------
    integer errors = 0;
    integer taps = 0, longs = 0, very_longs = 0;

    always @(posedge dut.clk) begin
        if (dut.btn_tap)       taps       = taps + 1;
        if (dut.btn_long)      longs      = longs + 1;
        if (dut.btn_very_long) very_longs = very_longs + 1;
    end

    task check(input ok, input [8*60-1:0] what);
        begin
            if (ok) $display("  ok    %0s", what);
            else begin
                $display("  FAIL  %0s   (t=%0d ms)", what, $time / MS);
                errors = errors + 1;
            end
        end
    endtask

    // Contact bounce: the switch chatters for ~8 ms when it changes
    task bounce(input final_state);
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                contact = ~contact;
                #(1 * MS);
            end
            contact = final_state;
        end
    endtask

    // Press and hold the button, release, and wait for things to settle
    task press(input integer hold_ms);
        begin
            contact = 1'b0;
            bounce(1'b1);
            #(hold_ms * MS);
            bounce(1'b0);
            #(100 * MS);
        end
    endtask

    task reset_counts;
        begin taps = 0; longs = 0; very_longs = 0; end
    endtask

    // Count how many clocks the LED is on during one full 256-step PWM period
    task measure(output integer r_on, output integer g_on, output integer b_on);
        integer i;
        begin
            @(posedge dut.clk);
            while (dut.u_core.pwm_ramp != 8'd0) @(posedge dut.clk);
            r_on = 0; g_on = 0; b_on = 0;
            for (i = 0; i < 256; i = i + 1) begin
                @(negedge dut.clk);
                r_on = r_on + red_led;
                g_on = g_on + green_led;
                b_on = b_on + blue_led;
            end
        end
    endtask

    always @(posedge dut.clk)
        if (!dut.rst && dut.u_core.hue_fp >= 20'd393216) begin
            $display("  FAIL  hue_fp out of range: %0d", dut.u_core.hue_fp);
            errors = errors + 1;
        end

    integer h0, h1, r_on, g_on, b_on;

    // ---------------- test sequence ----------------
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb_top);

        #(300 * MS);
        $display("idle");
        check(dut.btn_held == 0 && taps == 0,                  "released button reads as not held");
        check(dut.u_core.paused == 0 && dut.u_core.speed == 1 && dut.u_core.dim == 0,
                                                               "reset defaults: running, speed 1, full brightness");
        h0 = dut.u_core.hue_fp; #(100 * MS); h1 = dut.u_core.hue_fp;
        check((h1 - h0) >= 9300 && (h1 - h0) <= 10300,         "hue advances ~98/ms (4 s per lap)");

        $display("tap: pause");
        reset_counts;
        contact = 1'b0; bounce(1'b1);
        #(150 * MS);
        check(dut.btn_held == 1,                               "held button registers");
        check(dut.u_core.paused == 0,                          "nothing happens until release");
        bounce(1'b0); #(100 * MS);
        check(taps == 1 && longs == 0 && very_longs == 0,      "bouncy 150 ms press = exactly one tap");
        check(dut.u_core.paused == 1,                          "tap pauses the rainbow");
        h0 = dut.u_core.hue_fp; #(200 * MS);
        check(dut.u_core.hue_fp == h0,                         "hue frozen while paused");

        $display("PWM");
        measure(r_on, g_on, b_on);
        check(r_on == dut.u_core.duty_r && g_on == dut.u_core.duty_g && b_on == dut.u_core.duty_b,
                                                               "LED on-time per period equals duty cycle");

        $display("glitch");
        reset_counts;
        contact = 1'b1; #(5 * MS); contact = 1'b0;
        #(100 * MS);
        check(taps == 0 && longs == 0 && very_longs == 0,      "5 ms glitch ignored");

        $display("long press: speed");
        reset_counts;
        press(1000);
        check(longs == 1 && taps == 0 && very_longs == 0,      "1 s press = one long press");
        check(dut.u_core.speed == 2,                           "speed steps up");
        check(dut.u_core.paused == 1,                          "still paused");

        $display("very long press: brightness");
        reset_counts;
        press(2500);
        check(very_longs == 1 && taps == 0 && longs == 0,      "2.5 s press = one very long press");
        check(dut.u_core.dim == 1,                             "brightness steps to 50%");
        measure(r_on, g_on, b_on);
        check(r_on == (dut.u_core.r >> 1) && g_on == (dut.u_core.g >> 1) && b_on == (dut.u_core.b >> 1),
                                                               "LED on-time halved");

        $display("boundaries");
        reset_counts;
        press(500);
        check(taps == 1,                                       "0.5 s press is still a tap");
        press(700);
        check(longs == 1,                                      "0.7 s press is a long press");
        check(dut.u_core.speed == 3,                           "speed 3");

        $display("resume at fastest speed");
        check(dut.u_core.paused == 0,                          "the 0.5 s tap resumed");
        h0 = dut.u_core.hue_fp; #(100 * MS); h1 = dut.u_core.hue_fp;
        if (h1 < h0) h1 = h1 + 393216;
        check((h1 - h0) >= 93000 && (h1 - h0) <= 103000,       "hue advances ~983/ms (0.4 s per lap)");
        #(1500 * MS);   // several laps; the always block above checks the wrap

        $display("");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

endmodule
