# syntax=docker/dockerfile:1

# The application service of the Dev Container (OPS-01, ADR-17).
#
# The ruby and node toolchains come from mise.toml. This file pins no
# runtime version, so mise.toml stays the only place that does.

FROM ubuntu:24.04@sha256:562111b88caa79c71391c0c4d3c2114a7d5c35915c20561fd893cb1e07929e6b

ARG DEBIAN_FRONTEND=noninteractive

# Build dependencies for the Ruby toolchain and native gems, and the tools
# mise and git need. The PostgreSQL client comes from the PGDG archive below,
# so its pg_dump matches the pinned PostgreSQL 18 server (OPS-01, DATA-04).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      autoconf bison build-essential ca-certificates curl git jq \
      libffi-dev libgdbm-dev libncurses-dev libpq-dev libreadline-dev \
      libssl-dev libyaml-dev patch pkg-config \
      sudo tzdata unzip zlib1g-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# The client loads db/structure.sql and dumps it for the migration replay
# guard. Ubuntu 24.04 ships version 16, and pg_dump refuses a server newer
# than itself, so install version 18 from the PGDG archive that the pinned
# server comes from (OPS-01, DATA-04, DATA-05).
RUN install -d /usr/share/postgresql-common/pgdg && \
    curl --proto '=https' --tlsv1.2 -fsSL \
      https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc && \
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt noble-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y postgresql-client-18 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# The non-root user the Dev Container connects as. Ubuntu 24.04 ships an
# `ubuntu` user with UID and GID 1000, so rename it instead of creating a
# second 1000 to keep ownership of the bind mount.
ARG USERNAME=vscode
RUN groupmod --new-name "${USERNAME}" ubuntu && \
    usermod --login "${USERNAME}" --home "/home/${USERNAME}" \
      --move-home --shell /bin/bash ubuntu && \
    echo "${USERNAME} ALL=(root) NOPASSWD:ALL" \
      > "/etc/sudoers.d/${USERNAME}" && \
    chmod 0440 "/etc/sudoers.d/${USERNAME}"

USER ${USERNAME}

# mise installs the toolchains from mise.toml. The trusted path covers the
# bind mount the Dev Container uses at run time.
ENV LANG="C.UTF-8" \
    LC_ALL="C.UTF-8" \
    PATH="/home/${USERNAME}/.local/bin:/home/${USERNAME}/.local/share/mise/shims:${PATH}" \
    MISE_TRUSTED_CONFIG_PATHS="/workspaces/monova"

RUN curl --proto '=https' --tlsv1.2 -fsSL https://mise.run | \
    MISE_VERSION=v2026.11.3 sh

WORKDIR /workspaces/monova
COPY --chown=${USERNAME}:${USERNAME} mise.toml ./
RUN mise trust && mise install && mise reshim

CMD ["sleep", "infinity"]
