# CLAUDE.md

Guidance for Claude Code in this repository. User-facing instructions are in
README.md; this file records how the project works and the pitfalls found while
building it on real hardware.

## Project

FPGA designs (Verilog) and Cortex-M4 firmware (C, FreeRTOS) for QuickLogic
EOS S3 boards: **Qomu** (42-ball WLCSP chip) and **QuickFeather / QuickFeather
Lite** (64-pin QFN). All tools run in Docker (`linux/amd64`, Rosetta on Apple
Silicon); the host only needs Docker, git and python3.

## Commands

```bash
./sim.sh   <design> <board>   # Icarus Verilog testbench: designs/<design>/sim/tb_<board>.v
./build.sh <design> <board>   # -> designs/<design>/out/<board>/top.bin
./flash.sh <design> <board>   # FPGA-only image, --mode fpga
./fw_build.sh <app>           # qorc-sdk M4 app -> firmware/<app>/GCC_Project/output/bin/<app>.bin
./fw_flash.sh <app>           # --mode m4
```

Boards: `qomu`, `quickfeather`. Designs: `blinky`, `rainbow`. Firmware: `qf_hello`.

- **Always simulate before building.** Hardware debugging only has an RGB LED to go on.
- **Flashing needs the user.** The board must be put in programming mode by hand,
  so give the user the flash command to run instead of running it yourself.
  Check the port with `ls /dev/cu.usbmodem*`; the name changes between USB ports.
- **Board names matter.** Never flash an image built for one board onto the other:
  IO_6 is a Qomu LED output but the QuickFeather's button input.

## Layout conventions

- `designs/<design>/<board>.pcf` pins per board; `top.v`, or `top_<board>.v` when
  boards need different tops (both define `module top`); shared `.v` files; `sim/`
  holds testbenches plus `eos_s3_sim.v`, simulation stand-ins for
  `qlal4s3b_cell_macro` and `gclkbuff`.
- `build.sh` stages each board's sources into `out/<board>/` and builds there;
  `ql_symbiflow` keeps state in its `-src` folder.
- Use `IO_x` pad names in `.pcf` files with `-P PU64` for both boards, as QuickLogic's
  own Qomu apps do.
- A firmware app is a copy of a qorc-sdk app. `fw_build.sh` bind-mounts it at
  `/opt/qorc-sdk/user_apps/<app>` because SDK makefiles use `GCC_Project/../../..`.
  New `.c` files in `src/` are picked up automatically. The output name is the folder name.

## Hardware facts (verified)

| | Qomu | QuickFeather |
|---|---|---|
| Red / green / blue LED | IO_24 / IO_6 / IO_30 | IO_22 / IO_21 / IO_18 |
| Inputs | touch pads IO_10, IO_17, IO_0, IO_29 | USR button IO_6 (low when pressed) |
| Programming mode | replug, touch pads while blue blinks | RST, then USR while blue blinks |

- LEDs are active high on both boards (common anode, MOSFET low-side switch).
- In FPGA-only mode the bootloader starts `Sys_Clk0` at **12 MHz** and applies the
  IO mux from the `.bin`.
- Qomu touch pads are bare copper with no pull resistors. `touch_sense.v` detects mains
  hum from a finger: it discharges the pad, then listens for a high level.
- The QuickFeather USR button has **no external pull-up**. The toolchain always writes
  FPGA pads with pull = none, so `scripts/apply_pullups.py` patches the pull bits
  (register bits 7:6) in the `.bin` IO mux section for pads listed as
  `// pullup: IO_x` in the `.pcf`. The bootloader doesn't check that section's CRC.
- Never flash `--bootloader` or `--bootfpga`; that can brick a board.

## Pitfalls (each one cost real debugging time)

**FPGA**
- **Route `Sys_Clk0` and `Sys_Clk0_Rst` through `gclkbuff`.** Without it, the clock goes
  through general routing: a 27-flip-flop blinky works, but a 154-flip-flop design
  stayed dark on hardware. Check the build's `.eblif` has `GMUX_IC` cells.
- Timing margins are thin (SymbiFlow's EOS S3 models report roughly 13–15 MHz Fmax
  for modest logic). Avoid variable shifters and wide multipliers; register
  decode paths; check `route.log` and the reg-to-reg paths in `report_timing.setup.rpt`.
  Hold violations only on async input pads going into a synchronizer are harmless.
- Tri-state `inout` pads work (yosys warns about limited support, but they map to
  bidir cells correctly).
- `initial` values are not reliable; use reset or self-correcting logic.

**Toolchain (Dockerfile)**
- QuickLogic's `Symbiflow_v1.3.1.gz.run` installer no longer works as shipped: it
  silently needs `curl`, the latest Miniconda can't install its py3.7 packages, and a
  conda solve of its helper packages hangs for over an hour. The Dockerfile replays its
  steps with Miniconda `py37_4.12.0` and pip, and checks the tools exist. Don't
  "simplify" it back to the installer.
- qorc-sdk needs the `s3-gateware` submodule (`gateware.h`), pinned in the Dockerfile.
- The SDK's FPGA rule calls `time` under `/bin/sh`, so the image installs GNU `time`.
- SDK makefiles break with `make -j`.
- The SDK FPGA rule pipes through `grep`, which can hide a failed FPGA build. Verify
  `fpga/rtl/build/route.log` and the generated `*_bit.h` yourself.

**M4 firmware with custom FPGA logic** (unresolved; not in this repo yet)
An experimental app combining QuickLogic's `qf_advancedfpga` example (custom FPGA
plus Wishbone registers at `0x40020000`) with the MC3635 accelerometer driver never
got I2C working on hardware. What we learned:
- A custom FPGA design replaces the USB-serial logic, so debug output must go to
  the hardware UART (J3 pins 2/3, 3.3 V USB-serial adapter). Get one before
  debugging; LED color codes were slow and inconclusive.
- `qf_advancedfpga` never calls `HAL_Delay_Init()`, so `HAL_DelayUSec()` (used by the
  MC3635 driver) loops forever. Call it in `main()`.
- `qf_advancedfpga`'s `s3x_pwrcfg.c` runs `CLK_C08X4` (the sensor-subsystem bus master
  behind the I2C HAL) at 2 MHz / 256 kHz; `qf_ssi_ai_app` uses 24 / 12 MHz.
- Even with both fixes, and with I2C initialized in `main()` before the scheduler,
  `HAL_I2C_Init()` hung. The suspect is `HAL_WB_Init()`'s unbounded
  `while(!(PMU->FFE_STATUS & 0x1))` or I2C0 access while a custom FPGA is loaded.
  QuickLogic's working accelerometer app (`qf_ssi_ai_app`) never loads a custom FPGA.
  Next step would be the UART console, or starting from `qf_ssi_ai_app` and adding
  the FPGA instead.

## Working style

- Match the existing code: comment density, naming, and explaining *why* in comments.
- Before relying on EOS S3 facts, check QuickLogic's sources (qorc-sdk, board
  schematics, user guides) instead of assuming. Several "obvious" defaults were wrong.
- Keep testbenches self-checking (`ALL TESTS PASSED`) and sanity-check them by
  breaking the design on purpose once.
