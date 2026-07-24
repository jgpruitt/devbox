FROM ubuntu:24.04

ENV container=container
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

ARG PG_MAJOR=18

# Base OS, init, container tooling, and general development tools.
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash-completion \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    dbus \
    direnv \
    dnsutils \
    fd-find \
    file \
    fzf \
    gh \
    git \
    gnupg \
    htop \
    iproute2 \
    iptables \
    iputils-ping \
    jq \
    less \
    locales \
    lsb-release \
    lsof \
    make \
    man-db \
    manpages \
    manpages-dev \
    net-tools \
    netcat-openbsd \
    ninja-build \
    openssh-client \
    openssh-server \
    openssl \
    pkg-config \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    rsync \
    shellcheck \
    skopeo \
    slirp4netns \
    strace \
    sudo \
    systemd \
    tmux \
    tree \
    uidmap \
    unzip \
    vim \
    wget \
    xz-utils \
    yq \
    zip \
    zsh \
    podman \
    podman-compose \
    podman-docker \
    buildah \
    crun \
    fuse-overlayfs \
  && locale-gen en_US.UTF-8 \
  && yes | unminimize \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# PostgreSQL client only
RUN install -d /usr/share/postgresql-common/pgdg \
  && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg \
  && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] https://apt.postgresql.org/pub/repos/apt noble-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends postgresql-client-${PG_MAJOR} \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Friendly command names for packages that use Debian-specific binary names.
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd \
  && printf '%s\n' \
    '#!/bin/sh' \
    'exec /usr/bin/podman "$@"' \
    > /usr/local/bin/docker \
  && chmod 0755 /usr/local/bin/docker \
  && printf '%s\n' \
    '#!/bin/sh' \
    'exec /usr/bin/podman-compose "$@"' \
    > /usr/local/bin/docker-compose \
  && chmod 0755 /usr/local/bin/docker-compose

# Let `docker compose` use podman-compose as its provider.
RUN install -d /etc/containers \
  && >/etc/containers/nodocker \
  && printf '%s\n' \
    '[engine]' \
    'cgroup_manager = "cgroupfs"' \
    'compose_providers = ["/usr/bin/podman-compose"]' \
    > /etc/containers/containers.conf

# Provide Docker CLI aliases in interactive shells. The /usr/local/bin wrappers
# above handle scripts that do not expand aliases.
RUN printf '%s\n' \
    'alias docker=podman' \
    'alias docker-compose=podman-compose' \
    > /etc/profile.d/podman-docker-aliases.sh

# Expose Podman's Docker-compatible API on the conventional Docker socket path.
# This is intentionally permissive because each container machine is isolated.
RUN groupadd --system docker \
  && install -d /etc/systemd/system/podman.socket.d \
  && printf '%s\n' \
    '[Socket]' \
    'SocketMode=0666' \
    'SocketUser=root' \
    'SocketGroup=docker' \
    > /etc/systemd/system/podman.socket.d/docker-compat.conf \
  && printf '%s\n' \
    'L+ /run/docker.sock - - - - /run/podman/podman.sock' \
    > /etc/tmpfiles.d/docker-compat.conf

# Apple container machine creates the real user on first boot. This service makes
# that user usable with rootless Podman and the rootful Docker-compatible socket.
RUN install -d /usr/local/sbin \
  && printf '%s\n' \
    '#!/bin/sh' \
    'set -eu' \
    'ensure_line() {' \
    '  file="$1"' \
    '  user="$2"' \
    '  if ! grep -q "^${user}:" "$file" 2>/dev/null; then' \
    '    printf "%s:100000:65536\n" "$user" >> "$file"' \
    '  fi' \
    '}' \
    'mount --make-rshared / || true' \
    'chmod 0666 /dev/net/tun 2>/dev/null || true' \
    'while IFS=: read -r user _ uid _ _ home shell; do' \
    '  case "$user:$home:$shell" in' \
    '    root:*|nobody:*|*:/nonexistent:*|*:/usr/sbin/nologin|*:/bin/false) continue ;;' \
    '  esac' \
    '  case "$home" in' \
    '    /home/*|/Users/*) ;;' \
    '    *) continue ;;' \
    '  esac' \
    '  ensure_line /etc/subuid "$user"' \
    '  ensure_line /etc/subgid "$user"' \
    '  usermod -aG docker "$user" || true' \
    '  loginctl enable-linger "$user" || true' \
    'done < /etc/passwd' \
    'systemd-tmpfiles --create /etc/tmpfiles.d/docker-compat.conf || true' \
    'ln -sfn /run/podman/podman.sock /run/docker.sock || true' \
    > /usr/local/sbin/setup-devbox-users \
  && chmod 0755 /usr/local/sbin/setup-devbox-users \
  && printf '%s\n' \
    '[Unit]' \
    'Description=Configure Apple container machine users for Podman development' \
    'After=systemd-user-sessions.service' \
    '' \
    '[Service]' \
    'Type=oneshot' \
    'ExecStart=/usr/local/sbin/setup-devbox-users' \
    '' \
    '[Install]' \
    'WantedBy=multi-user.target' \
    > /etc/systemd/system/setup-devbox-users.service

RUN >/etc/machine-id
RUN >/var/lib/dbus/machine-id

RUN ln -sf ../lib/systemd/systemd /sbin/init

RUN systemctl set-default multi-user.target
RUN systemctl enable podman.socket setup-devbox-users.service
RUN systemctl mask \
      dev-hugepages.mount \
      sys-fs-fuse-connections.mount \
      systemd-update-utmp.service \
      systemd-tmpfiles-setup.service \
      console-getty.service
RUN systemctl disable \
      networkd-dispatcher.service \
  || true

RUN sed -i -e 's/^AcceptEnv LANG LC_\*$/#AcceptEnv LANG LC_*/' /etc/ssh/sshd_config
