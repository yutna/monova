# syntax=docker/dockerfile:1

# The application service of the Dev Container (OPS-01, ADR-17).
#
# The ruby and node toolchains come from mise.toml. This file pins no
# runtime version, so mise.toml stays the only place that does.

FROM ubuntu:24.04@sha256:562111b88caa79c71391c0c4d3c2114a7d5c35915c20561fd893cb1e07929e6b

ARG DEBIAN_FRONTEND=noninteractive

# Build dependencies for the Ruby toolchain and native gems, the PostgreSQL
# client that loads db/structure.sql, and the tools mise and git need.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      autoconf bison build-essential ca-certificates curl git \
      libffi-dev libgdbm-dev libncurses-dev libpq-dev libreadline-dev \
      libssl-dev libvips libyaml-dev patch pkg-config postgresql-client \
      sudo unzip zlib1g-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# The non-root user the Dev Container connects as.
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupadd --gid "${USER_GID}" "${USERNAME}" && \
    useradd --uid "${USER_UID}" --gid "${USER_GID}" \
      --create-home --shell /bin/bash "${USERNAME}" && \
    echo "${USERNAME} ALL=(root) NOPASSWD:ALL" \
      > "/etc/sudoers.d/${USERNAME}" && \
    chmod 0440 "/etc/sudoers.d/${USERNAME}"

USER ${USERNAME}

# mise installs the toolchains from mise.toml. The trusted path covers the
# bind mount the Dev Container uses at run time.
ENV PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/share/mise/shims:${PATH}" \
    MISE_TRUSTED_CONFIG_PATHS="/workspaces/monova"

RUN curl --proto '=https' --tlsv1.2 -fsSL https://mise.run | \
    MISE_VERSION=v2026.11.3 sh

WORKDIR /workspaces/monova
COPY --chown=${USERNAME}:${USERNAME} mise.toml ./
RUN mise trust && mise install && mise reshim

CMD ["sleep", "infinity"]
