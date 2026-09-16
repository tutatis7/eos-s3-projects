// Touch detection for one Qomu touch pad.
//
// The pads are bare copper wired straight to the EOS S3 with no pull resistors
// (only an ESD diode to ground). When a finger touches one, the body couples in
// mains hum (50/60 Hz) strong enough to swing the pin above its logic-high
// threshold. The Qomu bootloader uses the same effect: it treats pad 1 as a
// plain input and waits for a rising edge.
//
// To keep an untouched pad from drifting high over time, this sensor repeats a
// short cycle:
//
//   |<-- DISCHARGE_MS -->|<-------------- listen ---------------->|
//     drive pad low        release, note whether the pin goes high
//
// A cycle that sees a high counts as "active". The pad is:
//   touched  after 2 active cycles in a row   (~50 ms with 25 ms cycles)
//   released after 4 quiet cycles in a row    (~100 ms)
// The listen window is longer than one 50 Hz period, so a touch reliably shows
// up in every cycle.

module touch_sense #(
    parameter CYCLE_MS     = 25,
    parameter DISCHARGE_MS = 1
) (
    input  wire clk,
    input  wire rst,
    input  wire tick_ms,     // one-clock pulse every millisecond
    inout  wire pad,
    output reg  touched,     // debounced level
    output wire pressed      // one-clock pulse when a touch starts
);

    reg [7:0] phase;         // ms position inside the current cycle
    reg       seen_high;     // pin went high during this listen window
    reg [3:0] history;       // last 4 cycles, newest in bit 0
    reg [1:0] pad_sync;      // synchronizer for the asynchronous pin
    reg       touched_d;

    wire discharging = (phase < DISCHARGE_MS);

    // Drive the pad low while discharging, otherwise leave it floating as an input
    assign pad = discharging ? 1'b0 : 1'bz;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            phase     <= 8'd0;
            seen_high <= 1'b0;
            history   <= 4'b0000;
            pad_sync  <= 2'b00;
            touched   <= 1'b0;
            touched_d <= 1'b0;
        end else begin
            pad_sync  <= {pad_sync[0], pad};
            touched_d <= touched;

            if (!discharging && pad_sync[1])
                seen_high <= 1'b1;

            if (tick_ms) begin
                if (phase >= CYCLE_MS - 1) begin
                    // End of cycle: record it and start the next discharge
                    phase     <= 8'd0;
                    history   <= {history[2:0], seen_high};
                    seen_high <= 1'b0;

                    if (history[0] && seen_high)
                        touched <= 1'b1;
                    else if (history[2:0] == 3'b000 && !seen_high)
                        touched <= 1'b0;
                end else begin
                    phase <= phase + 8'd1;
                end
            end
        end
    end

    assign pressed = touched & ~touched_d;

endmodule
