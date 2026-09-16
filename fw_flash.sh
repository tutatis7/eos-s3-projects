#!/usr/bin/env bash
# Flash built M4 firmware to the board.
#
#   ./fw_flash.sh <app>                     auto-detect /dev/cu.usbmodem*
#   ./fw_flash.sh <app> /dev/cu.usbmodemXX  explicit port
#
# Put the board in programming mode first (QuickFeather: press RST, then USR
# while the LED blinks blue; the LED turns green). Only have one board connected.
#
# --mode m4: the bootloader loads only the M4 app on boot. Any FPGA design
# flashed with flash.sh stays in flash but is not loaded; flash.sh switches back.
set -euo pipefail

cd "$(dirname "$0")"

APP=${1:-}
BIN=firmware/$APP/GCC_Project/output/bin/$APP.bin
PROG_DIR=tools/TinyFPGA-Programmer-Application
VENV=tools/venv

if [[ -z "$APP" || ! -d "firmware/$APP" ]]; then
    echo "usage: $(basename "$0") <app> [port]"
    echo "apps: $(ls firmware 2>/dev/null | tr '\n' ' ')"
    exit 1
fi
[[ -f "$BIN" ]] || { echo "Missing $BIN - run ./fw_build.sh $APP first"; exit 1; }

if [[ ! -d "$PROG_DIR" ]]; then
    mkdir -p tools
    git clone --recursive https://github.com/QuickLogic-Corp/TinyFPGA-Programmer-Application.git "$PROG_DIR"
fi

if [[ ! -x "$VENV/bin/python" ]]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet pyserial tinyfpgab
fi

PORT="${2:-}"
if [[ -z "$PORT" ]]; then
    PORT=$(ls /dev/cu.usbmodem* /dev/ttyACM* 2>/dev/null | head -n 1 || true)
    [[ -n "$PORT" ]] || { echo "No board serial port found. Is it in programming mode (green LED)?"; exit 1; }
fi
echo ">> Flashing $BIN via $PORT"

# never pass --bootloader / --bootfpga: overwriting those can brick the board
"$VENV/bin/python" "$PROG_DIR/tinyfpga-programmer-gui.py" \
    --port "$PORT" --m4app "$BIN" --mode m4 --reset
