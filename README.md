# eos-s3-projects

FPGA designs and Cortex-M4 firmware for QuickLogic **EOS S3** boards, built
entirely with open-source tools on macOS (Apple Silicon) or Linux.

| Project | What it does | Boards |
|---|---|---|
| `designs/blinky` | Cycles the RGB LED red → green → blue every 0.5 s (FPGA only) | Qomu, QuickFeather |
| `designs/rainbow` | Smooth PWM color wheel you control with the touch pads / USR button (FPGA only) | Qomu, QuickFeather |
| `firmware/qf_hello` | M4 firmware: USB-serial command line, USR button cycles the LED color | QuickFeather |

All three have been built and run on real hardware. `quickfeather` also covers
the QuickFeather Lite.

## What you need

- A board:
  - [Qomu](https://github.com/QuickLogic-Corp/qomu-dev-board), which plugs straight into a USB-A port
  - [QuickFeather or QuickFeather Lite](https://github.com/QuickLogic-Corp/quick-feather-dev-board), with a USB data cable
- [Docker Desktop](https://docs.docker.com/desktop/). On Apple Silicon, turn on
  *Settings → General → Use Rosetta for x86_64/amd64 emulation* and give Docker at
  least 8 GB of memory (*Settings → Resources*).
- `git` and `python3` (both come with macOS)

The FPGA toolchain (QuickLogic SymbiFlow), ARM GCC and QuickLogic's SDK all run
inside Docker. The first build creates that image, which takes 15–30 minutes and
several GB. Later builds take about a minute.

## Quick start

```bash
git clone https://github.com/tutatis7/eos-s3-projects.git
cd eos-s3-projects
./build.sh blinky quickfeather        # or: ./build.sh blinky qomu
```

Put the board in **programming mode** (only one board connected):

- **Qomu:** unplug and replug. While the LED blinks **blue** (first 5 s), touch the pads. The LED blinks **green**.
- **QuickFeather:** press **RST**. While the LED blinks **blue**, press **USR**. The LED turns **green**.

Then flash:

```bash
./flash.sh blinky quickfeather
```

The first flash downloads QuickLogic's programmer tool into `tools/`. After
flashing, the board blinks blue for 5 s (bootloader window), then runs your
design. It stays in flash across power cycles.

## FPGA designs

```
designs/<design>/<board>.pcf     pin assignments for that board
designs/<design>/top.v           top level (or top_<board>.v when boards differ)
designs/<design>/*.v             shared modules
designs/<design>/sim/            testbenches (not synthesized)
designs/<design>/out/<board>/    build and simulation output (generated)

build.sh <design> <board>        -> designs/<design>/out/<board>/top.bin
sim.sh   <design> <board>        run sim/tb_<board>.v with Icarus Verilog
flash.sh <design> <board>        write top.bin to the board
scripts/apply_pullups.py         enables pad pull-ups requested in a .pcf ("// pullup: IO_6")
```

Always pass the board name. The boards use different pins (for example, IO_6 is
a Qomu LED output but the QuickFeather's button input), so never flash an image
built for one board onto the other.

### Rainbow controls

**Qomu** (pads numbered as in the Qomu user guide):

| Pad | Pin | Action |
|---|---|---|
| 1 | IO_10 | Pause / resume |
| 2 | IO_17 | Speed: 12 s → 4 s → 1.5 s → 0.4 s per lap (starts at 4 s) |
| 3 | IO_0 | Brightness: 100% → 50% → 25% → 12.5% |
| 4 | IO_29 | Jump ahead 60° |

**QuickFeather** (USR button; the action happens when you let go):

| Press | Action |
|---|---|
| Tap (under 0.6 s) | Pause / resume |
| Long (0.6–2 s) | Speed |
| Very long (over 2 s) | Brightness |

## M4 firmware (QuickFeather)

C firmware for the Cortex-M4, built with QuickLogic's
[qorc-sdk](https://github.com/QuickLogic-Corp/qorc-sdk) (pinned in the Dockerfile)
and ARM GCC 9-2020-q2.

```
firmware/<app>/                  a qorc-sdk app (GCC_Project/, src/, inc/)
fw_build.sh <app>                -> firmware/<app>/GCC_Project/output/bin/<app>.bin
fw_flash.sh <app>                flash it with --mode m4
```

`qf_hello` starts from QuickLogic's `qf_helloworldsw`. It keeps the USB-serial
command line and adds:

- a FreeRTOS task (`src/led_button.c`) that cycles the RGB LED color on each USR press
  and prints the press over USB serial
- commands `color <name>` and `presses` (`src/main_dbg_cli_menu.c`)

```bash
./fw_build.sh qf_hello
# programming mode: RST, then USR while blue
./fw_flash.sh qf_hello
```

After the 5 s blue blink, connect to the board's serial port:

```bash
screen /dev/cu.usbmodemXXXX 115200     # exit: Ctrl-A, K, Y
```

To start a new app, copy `firmware/qf_hello` to `firmware/<new_name>`. The output
file is named after the folder. The SDK makefiles don't support `make -j`.

**M4 or FPGA:** the bootloader runs one mode at a time. `fw_flash.sh` sets `--mode m4`,
and `flash.sh` sets `--mode fpga`. Both images stay in flash, and the last flash
decides which one boots.

## Hardware notes

- **Clock:** `Sys_Clk0` is 12 MHz in FPGA-only mode on both boards. Route it and
  `Sys_Clk0_Rst` through `gclkbuff`, or larger designs fail on hardware.
- **LEDs:** active high on both boards (MOSFET low-side switches).
- **Qomu touch pads:** bare copper with no pull resistors. Detected through mains hum
  picked up by your finger (see `designs/rainbow/touch_sense.v`).
- **QuickFeather USR button:** switch to ground with no external pull-up. The toolchain
  can't enable pad pull-ups, so `build.sh` patches the internal pull-up into `top.bin`.
- **QuickFeather J1 / J7:** leave the shunts off to boot from flash.

## Toolchain notes

The Dockerfile works around problems in QuickLogic's v1.3.1 installer, which no
longer installs cleanly: it needs `curl`, the latest Miniconda can't install its
Python 3.7 packages, and conda takes over an hour to resolve its helper packages.
The Dockerfile pins Miniconda to a Python 3.7 release, installs the helpers with
pip, and fails the build if `ql_symbiflow`, `yosys` or `vpr` is missing.

## Going back to the factory firmware

Enter programming mode, then flash the board's original demo with `--mode m4`:

- Qomu: `qomu_helloworldsw.bin` from qorc-sdk `qomu_apps/qomu-initial-binaries`
- QuickFeather: `qf_helloworldsw.bin` from
  [quick-feather-dev-board/binaries](https://github.com/QuickLogic-Corp/quick-feather-dev-board/tree/master/binaries)

```bash
tools/venv/bin/python tools/TinyFPGA-Programmer-Application/tinyfpga-programmer-gui.py \
  --port /dev/cu.usbmodemXXXX --m4app <helloworldsw.bin> --mode m4 --reset
```

Never flash `--bootloader` or `--bootfpga`. Overwriting those areas can brick the
board (QuickFeather can be recovered with an SWD debugger on J6; Qomu needs one on its test pads).

## License

Apache License 2.0, see [LICENSE](LICENSE). `firmware/qf_hello` is based on
QuickLogic's qorc-sdk (also Apache 2.0); those files keep QuickLogic's copyright
headers. See [NOTICE](NOTICE) for credits and the third-party tools the build downloads.
