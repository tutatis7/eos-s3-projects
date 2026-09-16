# QuickLogic EOS S3 FPGA toolchain (SymbiFlow v1.3.1, the version qorc-sdk pins).
#
# These are the steps from QuickLogic's Symbiflow_v1.3.1.gz.run installer, done
# directly so the build stops on errors. That installer has no error checking
# and pulls the *latest* Miniconda, which can no longer install its Python 3.7
# packages. Here Miniconda is pinned to a Python 3.7 release instead.
#
# x86_64 Linux only: build.sh passes --platform linux/amd64 (Rosetta on Apple Silicon).
FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget git make xz-utils bzip2 libtbb-dev \
    && rm -rf /var/lib/apt/lists/*

ENV INSTALL_DIR=/opt/symbiflow/eos-s3

# Miniconda with Python 3.7 base
RUN curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-py37_4.12.0-Linux-x86_64.sh -o /tmp/conda.sh \
    && bash /tmp/conda.sh -b -p $INSTALL_DIR/conda \
    && rm /tmp/conda.sh

# QuickLogic architecture definitions (contains ql_symbiflow)
RUN curl -fsSL https://storage.googleapis.com/symbiflow-arch-defs-install/quicklogic-arch-defs-87dab559.tar.gz \
        | tar -C $INSTALL_DIR -xz \
    && test -x $INSTALL_DIR/quicklogic-arch-defs/bin/ql_symbiflow

# Synthesis / place & route tools, pinned exactly as in the v1.3.1 installer
ARG CONDA_FLAGS="-y -q --override-channels -c defaults -c conda-forge"
RUN source $INSTALL_DIR/conda/etc/profile.d/conda.sh && conda activate \
    && conda install $CONDA_FLAGS -c quicklogic-corp/label/ql \
        "yosys=0.8.0_0003_e80fb742f_20201208_122808" \
        "yosys-plugins=1.2.0_0011_g21045a9" \
        "vtr=v8.0.0_rc2_2894_gdadca7ecf" \
        python=3.7 \
    && conda clean -afy

# Python helpers used by ql_symbiflow. The installer used conda for these, but
# resolving them against today's channels takes over an hour; pip is instant.
# make and git come from apt above.
RUN source $INSTALL_DIR/conda/etc/profile.d/conda.sh && conda activate \
    && pip install --no-cache-dir lxml simplejson intervaltree python-constraint \
        git+https://github.com/QuickLogic-Corp/quicklogic-fasm@57b6e60574a9d483dc94710d0d3ff42a62b4ec41

ENV PATH="${INSTALL_DIR}/quicklogic-arch-defs/bin:${INSTALL_DIR}/quicklogic-arch-defs/bin/python:${INSTALL_DIR}/conda/bin:${PATH}"

# Fail the image build if the tools are not usable
RUN source $INSTALL_DIR/conda/etc/profile.d/conda.sh && conda activate \
    && which ql_symbiflow yosys vpr genfasm qlfasm

# Icarus Verilog for running testbenches (sim.sh), and GNU time,
# which the qorc-sdk FPGA build rule calls from /bin/sh
RUN apt-get update && apt-get install -y --no-install-recommends iverilog time \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# M4 firmware (fw_build.sh): the ARM GCC release and qorc-sdk that QuickLogic's
# envsetup.sh uses. The SDK is pinned to a commit so builds are reproducible.
# ---------------------------------------------------------------------------
RUN curl -fsSL "https://developer.arm.com/-/media/Files/downloads/gnu-rm/9-2020q2/gcc-arm-none-eabi-9-2020-q2-update-x86_64-linux.tar.bz2" \
        | tar -C /opt -xj \
    && /opt/gcc-arm-none-eabi-9-2020-q2-update/bin/arm-none-eabi-gcc --version | head -1

ENV PATH="/opt/gcc-arm-none-eabi-9-2020-q2-update/bin:${PATH}"

ARG QORC_SDK_COMMIT=d61d064146c0ee927aa12b088b3bbbce60615f4d
RUN git init -q /opt/qorc-sdk \
    && git -C /opt/qorc-sdk fetch -q --depth 1 https://github.com/QuickLogic-Corp/qorc-sdk "$QORC_SDK_COMMIT" \
    && git -C /opt/qorc-sdk checkout -q FETCH_HEAD \
    && rm -rf /opt/qorc-sdk/.git \
    && mkdir -p /opt/qorc-sdk/user_apps

# s3-gateware submodule (prebuilt FPGA images such as USB serial, gateware.h),
# at the commit that qorc-sdk commit references
ARG S3_GATEWARE_COMMIT=2f8fed632d5bf1196485c5b57de46be4f8341485
RUN git init -q /opt/qorc-sdk/s3-gateware \
    && git -C /opt/qorc-sdk/s3-gateware fetch -q --depth 1 https://github.com/QuickLogic-Corp/s3-gateware "$S3_GATEWARE_COMMIT" \
    && git -C /opt/qorc-sdk/s3-gateware checkout -q FETCH_HEAD \
    && rm -rf /opt/qorc-sdk/s3-gateware/.git \
    && test -f /opt/qorc-sdk/s3-gateware/gateware.h

WORKDIR /work
