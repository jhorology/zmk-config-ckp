FROM zmkfirmware/zmk-dev-arm:stable
ARG HOST_GID=1000
ARG HOST_UID=1000
ARG WORK_DIR=/workdir

# Install patch command
RUN \
  apt-get -y update \
  && apt-get -y install --no-install-recommends patch

RUN groupadd -f -g $HOST_GID user \
  && useradd -m -s /bin/bash -u $HOST_UID -g $HOST_GID user \
  && mkdir $WORK_DIR \
  && chown -R $HOST_UID:$HOST_GID $WORK_DIR
USER user