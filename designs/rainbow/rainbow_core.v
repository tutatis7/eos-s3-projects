// Board-independent PWM rainbow.
//
// Fades the RGB LED around the color wheel. Each board's top file turns its
// inputs (touch pads, buttons) into the one-clock control pulses below.
//
//   pause_toggle  pause / resume
//   speed_next    12 s -> 4 s -> 1.5 s -> 0.4 s per full rainbow (starts at 4 s)
//   dim_next      100% -> 50% -> 25% -> 12.5%
//   jump          jump ahead 60 degrees (red -> yellow -> green -> ...)
//
// Also provides the 1 ms tick the input logic uses. LED outputs are active high.

module rainbow_core #(
    parameter CLK_HZ  = 12_000_000,
    parameter PWM_DIV = 32           // 12 MHz / 32 / 256 steps = ~1.5 kHz PWM
) (
    input  wire clk,
    input  wire rst,
    input  wire pause_toggle,
    input  wire speed_next,
    input  wire dim_next,
    input  wire jump,
    output reg  tick_ms,
    output wire red_led,
    output wire green_led,
    output wire blue_led
);

    // ------------------------------------------------------------------
    // 1 ms tick
    // ------------------------------------------------------------------
    localparam MS_DIV = CLK_HZ / 1000;

    reg [23:0] ms_count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ms_count <= 24'd0;
            tick_ms  <= 1'b0;
        end else if (ms_count >= MS_DIV - 1) begin
            ms_count <= 24'd0;
            tick_ms  <= 1'b1;
        end else begin
            ms_count <= ms_count + 24'd1;
            tick_ms  <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Controls
    // ------------------------------------------------------------------
    reg       paused;
    reg [1:0] speed;         // 0 = slowest
    reg [1:0] dim;           // brightness = full >> dim

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            paused <= 1'b0;
            speed  <= 2'd1;
            dim    <= 2'd0;
        end else begin
            if (pause_toggle) paused <= ~paused;
            if (speed_next)   speed  <= speed + 2'd1;
            if (dim_next)     dim    <= dim + 2'd1;
        end
    end

    // ------------------------------------------------------------------
    // Hue: position on the color wheel, fixed point with 8 fraction bits.
    // The wheel has 6 sectors x 256 steps = 1536 whole steps.
    // Advancing hue_inc per millisecond takes 393216 / hue_inc ms per lap.
    // ------------------------------------------------------------------
    localparam [19:0] HUE_WRAP  = 20'd393216;   // 1536 << 8
    localparam [19:0] HUE_60DEG = 20'd65536;    //  256 << 8

    reg [19:0] hue_fp;
    reg [19:0] hue_inc;

    always @(*) begin
        case (speed)
            2'd0:    hue_inc = 20'd33;   // ~12 s per lap
            2'd1:    hue_inc = 20'd98;   //  ~4 s
            2'd2:    hue_inc = 20'd262;  // ~1.5 s
            default: hue_inc = 20'd983;  // ~0.4 s
        endcase
    end

    wire [19:0] hue_step = (tick_ms && !paused) ? hue_inc   : 20'd0;
    wire [19:0] hue_jump = jump                 ? HUE_60DEG : 20'd0;
    wire [19:0] hue_next = hue_fp + hue_step + hue_jump;

    always @(posedge clk or posedge rst) begin
        if (rst)
            hue_fp <= 20'd0;
        else if (hue_next >= HUE_WRAP)
            hue_fp <= hue_next - HUE_WRAP;
        else
            hue_fp <= hue_next;
    end

    // ------------------------------------------------------------------
    // Hue -> RGB. Each sector holds one channel at max and ramps another:
    //   0 red->yellow   (G up)      3 cyan->blue     (G down)
    //   1 yellow->green (R down)    4 blue->magenta  (R up)
    //   2 green->cyan   (B up)      5 magenta->red   (B down)
    // ------------------------------------------------------------------
    wire [2:0] sector = hue_fp[18:16];
    wire [7:0] up     = hue_fp[15:8];
    wire [7:0] down   = 8'd255 - up;

    reg [7:0] r, g, b;

    always @(*) begin
        case (sector)
            3'd0:    begin r = 8'd255; g = up;     b = 8'd0;   end
            3'd1:    begin r = down;   g = 8'd255; b = 8'd0;   end
            3'd2:    begin r = 8'd0;   g = 8'd255; b = up;     end
            3'd3:    begin r = 8'd0;   g = down;   b = 8'd255; end
            3'd4:    begin r = up;     g = 8'd0;   b = 8'd255; end
            default: begin r = 8'd255; g = 8'd0;   b = down;   end
        endcase
    end

    // ------------------------------------------------------------------
    // PWM: compare each channel against a free-running 8-bit ramp
    // ------------------------------------------------------------------
    reg [7:0] pwm_div;
    reg [7:0] pwm_ramp;
    reg [7:0] duty_r, duty_g, duty_b;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pwm_div  <= 8'd0;
            pwm_ramp <= 8'd0;
            duty_r   <= 8'd0;
            duty_g   <= 8'd0;
            duty_b   <= 8'd0;
        end else begin
            if (pwm_div >= PWM_DIV - 1) begin
                pwm_div  <= 8'd0;
                pwm_ramp <= pwm_ramp + 8'd1;
            end else begin
                pwm_div <= pwm_div + 8'd1;
            end

            // Register the dimmed duty cycles (shortens the timing path)
            duty_r <= r >> dim;
            duty_g <= g >> dim;
            duty_b <= b >> dim;
        end
    end

    assign red_led   = (duty_r > pwm_ramp);
    assign green_led = (duty_g > pwm_ramp);
    assign blue_led  = (duty_b > pwm_ramp);

endmodule
