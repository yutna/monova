# Loop driver

One tick of the unattended build loop in
[the protocol](../../docs/development/protocol.md) §5 and §9. A systemd
user timer starts the driver every ten minutes; each tick reads the
budget, starts at most one headless lead run, and records what happened.

## Install

```sh
script/loop/install
```

The installer copies the units to `~/.config/systemd/user/`, reloads
systemd, and enables `monova-loop.timer`. It warns when lingering is
off; without it the timer stops when you log out:

```sh
sudo loginctl enable-linger "$USER"
```

The units run `~/personal/projects/monova/script/loop/driver`. Edit the
paths in `systemd/monova-loop.service` before installing when the
checkout lives elsewhere; `install` warns when the two disagree.

## Stop and resume

```sh
touch "${XDG_STATE_HOME:-$HOME/.local/state}/monova-loop/STOP"
```

The next tick exits at once. Remove the file to resume.

The driver also writes `PAUSED` after three consecutive runs that leave
`origin/main` and the open issues and pull requests unchanged. Remove
`PAUSED` to resume.

## Logs and state

The state directory is
`${MONOVA_LOOP_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/monova-loop}`:

| Path | Contents |
| --- | --- |
| `loop.log` | one line per tick: status, exit code, turns, cost |
| `runs/` | the event stream of each headless run |
| `budget.json` | the last run's rate limit windows |
| `STOP` | presence stops the loop |
| `PAUSED` | presence stops runs until removed |
| `progress.hash`, `idle.count` | the progress check |

A skip is logged with a reason, for example `reason=weekly_budget` with
the reset time, so a quiet log is a sign the timer is not firing.

## Environment

| Variable | Default | Effect |
| --- | --- | --- |
| `MONOVA_LOOP_STATE` | XDG state dir | state directory |
| `MONOVA_LOOP_CLAUDE` | `claude` | the Claude binary |
| `MONOVA_LOOP_TIMEOUT` | `10800` | run timeout in seconds |
| `MONOVA_WEEKLY_STOP` | `0.95` | weekly utilization to stop at |
| `MONOVA_LOOP_IDLE` | `3` | idle runs before `PAUSED` |
| `MONOVA_LOOP_REPO` | this checkout | repository to run in |

A run that times out or exits nonzero is logged as `status=timeout` or
`status=failed`, and the driver exits with the run's code, so
`systemctl --user status monova-loop.service` shows it.

## Uninstall

```sh
script/loop/uninstall
```

State, runs and worktrees are kept.

## Test

```sh
script/loop/test
```

The test uses fake `claude` and `gh` binaries and a temporary
repository, so it never reaches the network. It prints one line per
check and fails when any check fails or none ran.
