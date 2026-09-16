#!/usr/bin/env bash
# Flash a built design to a board as an FPGA-only application.
#
#   ./flash.sh <design> <board>                     auto-detect /dev/cu.usbmodem*
#   ./flash.sh <design> <board> /dev/cu.usbmodemXX  explicit port
#
# Put the board in programming mode first (LED blinking/breathing green):
#   qomu:          unplug and replug; while the LED blinks blue, touch the pads
#   quickfeather:  press RST; while the LED blinks blue, press USR
#
# Only have one board connected, so auto-detect can't pick the wrong one.
set -euo pipefail

cd "$(dirname "$0")"
source ./scripts/common.sh

USAGE_EXTRA=" [port]"
require_design_and_board "${1:-}" "${2:-}"
BIN=$OUT_DIR/top.bin
PROG_DIR=tools/TinyFPGA-Programmer-Application
VENV=tools/venv

[[ -f "$BIN" ]] || { echo "Missing $BIN - run ./build.sh $DESIGN $BOARD first"; exit 1; }

if [[ ! -d "$PROG_DIR" ]]; then
    mkdir -p tools
    git clone --recursive https://github.com/QuickLogic-Corp/TinyFPGA-Programmer-Application.git "$PROG_DIR"
fi

if [[ ! -x "$VENV/bin/python" ]]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet pyserial tinyfpgab
fi

PORT="${3:-}"
if [[ -z "$PORT" ]]; then
    PORT=$(ls /dev/cu.usbmodem* /dev/ttyACM* 2>/dev/null | head -n 1 || true)
    [[ -n "$PORT" ]] || { echo "No board serial port found. Is it in programming mode (green LED)?"; exit 1; }
fi
echo ">> Flashing $BIN ($DESIGN for $BOARD) via $PORT"

# --mode fpga : bootloader loads only the app FPGA image on boot (no M4 app)
# never pass --bootloader / --bootfpga: overwriting those can brick the board
"$VENV/bin/python" "$PROG_DIR/tinyfpga-programmer-gui.py" \
    --port "$PORT" --appfpga "$BIN" --mode fpga --reset
