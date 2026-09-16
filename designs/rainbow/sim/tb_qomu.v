// Self-checking testbench for the rainbow design on the Qomu (touch pads).
//
// Runs the real top_qomu.v, rainbow_core.v and touch_sense.v with a 10 kHz clock instead of 12 MHz
// (CLK_HZ is scaled to match, so all millisecond timing stays the same).
//
// Touch pads are modeled like the real board: untouched, a pad is weakly held
// low (ESD diode leakage). Touched, the finger couples in 60 Hz mains hum.
// The design drives the pad strongly low while discharging, which overrides both.
`timescale 1us/1us

module tb_top;

    localparam MS = 1000;   // 1 ms in time units (us)

    // ---------------- stimulus ----------------
    reg [3:0] finger = 4'b0000;
    reg       hum    = 1'b0;
    always #8333 hum = ~hum;   // 60 Hz square wave

    wire red_led, green_led, blue_led;
    wire touch1, touch2, touch3, touch4;

    assign (weak0, weak1) touch1 = finger[0] ? hum : 1'b0;
    assign (weak0, weak1) touch2 = finger[1] ? hum : 1'b0;
    assign (weak0, weak1) touch3 = finger[2] ? hum : 1'b0;
    assign (weak0, weak1) touch4 = finger[3] ? hum : 1'b0;

    top #(.CLK_HZ(10_000), .PWM_DIV(1)) dut (
        .red_led(red_led), .green_led(green_led), .blue_led(blue_led),
        .touch1(touch1), .touch2(touch2), .touch3(touch3), .touch4(touch4)
    );

    // ---------------- helpers ----------------
    integer errors = 0;

    task check(input ok, input [8*60-1:0] what);
        begin
            if (ok) $display("  ok    %0s", what);
            else begin
                $display("  FAIL  %0s   (t=%0d ms)", what, $time / MS);
                errors = errors + 1;
            end
        end
    endtask

    // Hold a finger on pad n (0-3) for a while, then lift it and let it settle
    task touch(input integer n, input integer hold_ms);
        begin
            finger[n] = 1'b1;
            #(hold_ms * MS);
            finger[n] = 1'b0;
            #(200 * MS);
        end
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

    // The hue must never leave the color wheel
    always @(posedge dut.clk)
        if (!dut.rst && dut.u_core.hue_fp >= 20'd393216) begin
            $display("  FAIL  hue_fp out of range: %0d", dut.u_core.hue_fp);
            errors = errors + 1;
        end

    integer h0, h1, r_on, g_on, b_on, sector0, t0;

    // ---------------- test sequence ----------------
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb_top);

        #(300 * MS);
        $display("idle");
        check(dut.touched == 4'b0000,                          "untouched pads stay released");
        check(dut.u_core.paused == 0 && dut.u_core.speed == 1 && dut.u_core.dim == 0, "reset defaults: running, speed 1, full brightness");

        h0 = dut.u_core.hue_fp; #(100 * MS); h1 = dut.u_core.hue_fp;
        check((h1 - h0) >= 9300 && (h1 - h0) <= 10300,         "hue advances ~98/ms (4 s per lap)");

        $display("pad 1: pause");
        finger[0] = 1'b1;
        #(150 * MS);
        check(dut.touched[0] == 1,                             "held finger registers as touched");
        check(dut.u_core.paused == 1,                                 "touch pauses the rainbow");
        finger[0] = 1'b0;
        t0 = $time;
        while (dut.touched[0]) #(1 * MS);
        check(($time - t0) <= 130 * MS,                        "release detected within ~100 ms");
        #(200 * MS);
        check(dut.u_core.paused == 1,                                 "lifting the finger does not toggle again");
        h0 = dut.u_core.hue_fp; #(200 * MS);
        check(dut.u_core.hue_fp == h0,                                "hue frozen while paused");

        $display("PWM");
        measure(r_on, g_on, b_on);
        check(r_on == dut.u_core.duty_r && g_on == dut.u_core.duty_g && b_on == dut.u_core.duty_b,
                                                               "LED on-time per period equals duty cycle");
        check(dut.u_core.duty_r == dut.u_core.r && dut.u_core.duty_g == dut.u_core.g && dut.u_core.duty_b == dut.u_core.b,
                                                               "full brightness: duty = color value");

        $display("pad 4: jump 60 degrees");
        sector0 = dut.u_core.hue_fp[18:16];
        h0 = dut.u_core.hue_fp;
        touch(3, 150);
        check(dut.u_core.hue_fp[18:16] == (sector0 + 1) % 6,          "moved to the next color sector");
        check(dut.u_core.hue_fp[15:0] == h0[15:0],                    "position within the sector unchanged");

        $display("pad 3: brightness");
        touch(2, 150);
        check(dut.u_core.dim == 1,                                    "brightness steps to 50%");
        measure(r_on, g_on, b_on);
        check(r_on == (dut.u_core.r >> 1) && g_on == (dut.u_core.g >> 1) && b_on == (dut.u_core.b >> 1),
                                                               "LED on-time halved");
        touch(2, 150); touch(2, 150); touch(2, 150);
        check(dut.u_core.dim == 0,                                    "four presses wrap back to 100%");

        $display("pad 2: speed");
        touch(1, 150);
        check(dut.u_core.speed == 2,                                  "speed steps up");
        touch(0, 150);
        check(dut.u_core.paused == 0,                                 "pad 1 again resumes");
        h0 = dut.u_core.hue_fp; #(100 * MS); h1 = dut.u_core.hue_fp;
        if (h1 < h0) h1 = h1 + 393216;
        check((h1 - h0) >= 25000 && (h1 - h0) <= 27400,        "hue advances ~262/ms (1.5 s per lap)");

        $display("debounce");
        // A 10 ms brush that fits inside one listen window must not count as a press
        while (dut.u_touch2.phase != 2) @(posedge dut.clk);
        finger[1] = 1'b1; #(10 * MS); finger[1] = 1'b0;
        #(200 * MS);
        check(dut.u_core.speed == 2,                                  "brief brush ignored");

        $display("fastest speed, several laps");
        touch(1, 150);
        check(dut.u_core.speed == 3,                                  "speed 3");
        #(1500 * MS);   // ~4 laps; the always block above checks the wrap

        $display("");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

endmodule
