// Debounced push button that tells a tap from a long and a very long press.
//
// The pin reads low while the button is held (switch to ground plus pull-up).
// A change only counts once it has been stable for DEBOUNCE_MS, which filters
// out contact bounce. When the button is released, exactly one pulse fires,
// chosen by how long it was held:
//
//   held <  LONG_MS                  tap
//   LONG_MS <= held < VERY_LONG_MS   long_press
//   held >= VERY_LONG_MS             very_long_press

module button_press #(
    parameter DEBOUNCE_MS  = 20,
    parameter LONG_MS      = 600,
    parameter VERY_LONG_MS = 2000
) (
    input  wire clk,
    input  wire rst,
    input  wire tick_ms,           // one-clock pulse every millisecond
    input  wire pin_n,             // button pin, low = pressed
    output reg  held,              // debounced level, 1 while held
    output reg  tap,               // one-clock pulses, on release
    output reg  long_press,
    output reg  very_long_press
);

    reg  [1:0]  down_sync;         // synchronizer, 1 = button down
    reg  [7:0]  stable_ms;         // how long the pin has disagreed with `held`
    reg  [11:0] held_ms;           // length of the current press, saturates at 4095

    wire down = down_sync[1];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            down_sync       <= 2'b00;
            stable_ms       <= 8'd0;
            held_ms         <= 12'd0;
            held            <= 1'b0;
            tap             <= 1'b0;
            long_press      <= 1'b0;
            very_long_press <= 1'b0;
        end else begin
            down_sync       <= {down_sync[0], ~pin_n};
            tap             <= 1'b0;
            long_press      <= 1'b0;
            very_long_press <= 1'b0;

            // Time the press (the edge handling below overrides this when needed)
            if (held && tick_ms && held_ms != 12'hFFF)
                held_ms <= held_ms + 12'd1;

            if (down == held) begin
                stable_ms <= 8'd0;              // pin agrees, nothing pending
            end else if (tick_ms) begin
                if (stable_ms >= DEBOUNCE_MS - 1) begin
                    // The change has been stable long enough: accept it
                    stable_ms <= 8'd0;
                    held      <= down;
                    held_ms   <= 12'd0;

                    if (!down) begin            // released: report the press
                        if (held_ms >= VERY_LONG_MS)
                            very_long_press <= 1'b1;
                        else if (held_ms >= LONG_MS)
                            long_press <= 1'b1;
                        else
                            tap <= 1'b1;
                    end
                end else begin
                    stable_ms <= stable_ms + 8'd1;
                end
            end
        end
    end

endmodule
