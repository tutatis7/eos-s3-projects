# Shared helpers for build.sh / sim.sh / flash.sh. Source from the project root.

IMAGE=qomu-symbiflow:v1.3.1-r4

# Exit with usage unless $1 is a design in designs/ and $2 a board it has a pin file for.
# Sets DESIGN, BOARD, DESIGN_DIR and OUT_DIR (where build/sim output goes).
require_design_and_board() {
    local usage="usage: $(basename "$0") <design> <board>${USAGE_EXTRA:-}"
    if [[ -z "${1:-}" || ! -d "designs/$1" ]]; then
        echo "$usage"
        echo "designs: $(ls designs | tr '\n' ' ')"
        exit 1
    fi
    if [[ -z "${2:-}" || ! -f "designs/$1/$2.pcf" ]]; then
        echo "$usage"
        echo "boards for $1: $(cd "designs/$1" && ls *.pcf | sed 's/\.pcf$//' | tr '\n' ' ')"
        exit 1
    fi
    DESIGN=$1
    BOARD=$2
    DESIGN_DIR=designs/$DESIGN
    OUT_DIR=$DESIGN_DIR/out/$BOARD
}

# Verilog files for a design on a board: top_<board>.v (or top.v) plus every
# other .v in the design folder that is not a top file. Paths are relative to
# the project root.
design_sources() {
    local top="$DESIGN_DIR/top_$BOARD.v"
    [[ -f "$top" ]] || top="$DESIGN_DIR/top.v"
    echo "$top"
    for f in "$DESIGN_DIR"/*.v; do
        case "$(basename "$f")" in
            top.v|top_*.v) ;;
            *) echo "$f" ;;
        esac
    done
}

# Run a command inside the toolchain container, with the project mounted at /work.
# Extra `docker run` options (e.g. more mounts) can be passed in DOCKER_EXTRA_ARGS.
run_in_toolchain() {
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo ">> Building toolchain image $IMAGE (first time only)" >&2
        docker build --platform linux/amd64 -t "$IMAGE" . >&2
    fi
    # shellcheck disable=SC2086
    docker run --rm --platform linux/amd64 -v "$PWD":/work -w /work ${DOCKER_EXTRA_ARGS:-} "$IMAGE" \
        bash -c "source \$INSTALL_DIR/conda/etc/profile.d/conda.sh && conda activate && $1"
}
