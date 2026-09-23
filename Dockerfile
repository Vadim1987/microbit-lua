# To build an image:
#   $ podman build --platform linux/amd64 -t microbit -f Dockerfile .
#
# To enter that image:
#   $ cd /path/to/project/root
#   $ podman run --tty --rm --interactive --volume "$(pwd)":/workspace --workdir /workspace microbit
#
# To build it inside that image:
#   Note: image entry point is bash, hence the extra -c.
#   $ cd /path/to/project/root
#   $ podman run --tty --rm --volume "$(pwd)":/workspace --workdir /workspace microbit -c ./build.py
#
# Updating/publishing the image for the CI:
#
# to push the image, you need to log in with a token generated at:
# https://github.com/settings/tokens
#   $ podman login ghcr.io -u attila-lendvai # then paste the <personal-access-token>
#   $ podman push microbit ghcr.io/attila-lendvai/microbit:amd64
#
# for the first time go to:
# https://github.com/attila-lendvai?tab=packages&ecosystem=container
# and make the image public in the package settings
#
# Inside the image you can run build.py to build the project. The
# current directory from where you run podman will be shared into the
# image under /workspace, which will also be the default directory
# when running the image. This means that the built MICROBIT.hex file
# will be available in the source folder outside the image.

FROM ubuntu:26.04 AS builder

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      software-properties-common \
      git \
      make \
      cmake \
      diffutils \
      patch \
      less \
      lua5.1 \
      lua5.2 \
      lua5.3 \
      lua5.4 \
      python3 \
      python3-pip \
      gcc-arm-none-eabi \
      binutils-arm-none-eabi \
      libnewlib-arm-none-eabi \
      libstdc++-arm-none-eabi-newlib \
      ca-certificates && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

RUN update-alternatives --set lua-interpreter /usr/bin/lua5.1

# Project sources volume should be mounted at /app
# COPY . /opt/microbit-samples
# WORKDIR /opt/microbit-samples

# RUN python3 build.py

# FROM scratch AS export-stage
# COPY --from=builder /opt/microbit-samples/MICROBIT.bin .
# COPY --from=builder /opt/microbit-samples/MICROBIT.hex .

ENTRYPOINT ["/bin/bash"]
