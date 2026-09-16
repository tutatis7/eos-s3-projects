#!/usr/bin/env bash
# Synthesize, place & route and package a design for one board.
#
#   ./build.sh <design> <board>            build inside Docker (macOS / any host with Docker)
#   ./build.sh <design> <board> --native   use ql_symbiflow already on PATH (Linux install)
#
# Output: designs/<design>/out/<board>/top.bin
#
# A design folder holds <board>.pcf per supported board, top.v (or top_<board>.v
# when boards need different tops), and any shared .v files. sim/ is not synthesized.
set -euo pipefail

cd "$(dirname "$0")"
source ./scripts/common.sh

require_design_and_board "${1:-}" "${2:-}"

# Stage this board's sources in a clean folder, since the toolchain builds
# everything in -src and keeps state there between runs.
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/build"
for f in $(design_sources); do
    case "$(basename "$f")" in
        top_*.v) cp "$f" "$OUT_DIR/top.v" ;;
        *)       cp "$f" "$OUT_DIR/" ;;
    esac
done
cp "$DESIGN_DIR/$BOARD.pcf" "$OUT_DIR/"

SRCS=$(cd "$OUT_DIR" && ls *.v | tr '\n' ' ')
COMPILE="ql_symbiflow -compile -src $OUT_DIR -d ql-eos-s3 -t top -v $SRCS -p $BOARD.pcf -P PU64 -dump binary"

if [[ "${3:-}" == "--native" ]]; then
    bash -c "$COMPILE"
else
    run_in_toolchain "$COMPILE"
fi

python3 scripts/apply_pullups.py "$OUT_DIR/top.bin" "$OUT_DIR/$BOARD.pcf"

echo
echo ">> Bitstream: $OUT_DIR/top.bin"
ls -l "$OUT_DIR/top.bin"
