#!/usr/bin/env bash
# Run a design's testbench for one board with Icarus Verilog.
#
#   ./sim.sh <design> <board>
#
# Testbench: designs/<design>/sim/tb_<board>.v
# Waveform:  designs/<design>/out/<board>/sim/tb.vcd (open with GTKWave or Surfer)
set -euo pipefail

cd "$(dirname "$0")"
source ./scripts/common.sh

require_design_and_board "${1:-}" "${2:-}"

TB="$DESIGN_DIR/sim/tb_$BOARD.v"
[[ -f "$TB" ]] || { echo "No testbench at $TB"; exit 1; }

SIM_DIR="$OUT_DIR/sim"
mkdir -p "$SIM_DIR"
SRCS="$TB $DESIGN_DIR/sim/eos_s3_sim.v $(design_sources | tr '\n' ' ')"

OUTPUT=$(run_in_toolchain "iverilog -g2005 -Wall -Wno-timescale -o $SIM_DIR/tb.vvp $SRCS && cd $SIM_DIR && vvp -n tb.vvp" | tee /dev/stderr)

grep -q "ALL TESTS PASSED" <<<"$OUTPUT"
