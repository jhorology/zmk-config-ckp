FROM zmkfirmware/zmk-dev-arm:stable

# Install patch command
RUN \
  apt-get -y update \
  && apt-get -y install --no-install-recommends patch
