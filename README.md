# Devbox Container Machine

This repository builds an Apple `container machine` image for isolated development VMs on macOS.

The intended workflow is:

1. Keep one or more project checkouts on the Mac host.
2. Create a container machine from this image for an isolated branch or agent session.
3. Run the agent harness and project commands inside the Linux machine.
4. Use Podman through Docker-compatible commands for builds, tests, and Compose stacks.
5. Stop or delete the machine when the work is done.

Apple container machines mount your host home directory into the Linux machine, so your existing repositories and dotfiles are visible inside the VM. The VM gets its own Linux userspace, package set, container storage, volumes, ports, and services, keeping test containers isolated from the host and from other machines.

## Included Tools

The image is based on Ubuntu 24.04 with `systemd` and includes:

- Podman with Docker-compatible `docker` and `docker-compose` commands
- `podman-compose`, `buildah`, `skopeo`, rootless Podman support packages
- Docker API compatibility at `/run/docker.sock`, backed by Podman
- PostgreSQL 18 client only (`psql`, `pg_dump`, etc.)
- `jq`, `yq`, `ripgrep`, `vim`, `curl`, `git`, `unzip`
- Common dev tools including `gh`, `tmux`, `fzf`, `fd`, `shellcheck`, `direnv`, `build-essential`, `cmake`, `ninja-build`, Python tooling, `rsync`, `strace`, `lsof`, and network utilities
- Ghostty terminfo entries for `TERM=xterm-ghostty`

## Build The Image

From this repository:

```bash
container build -t local/devbox-machine:latest .
```

You can use a different tag if you want to keep multiple versions around:

```bash
container build -t local/devbox-machine:2026-07-24 .
```

## Create A Machine

Create a new persistent machine from the image:

```bash
container machine create local/devbox-machine:latest --name devbox0
```

Optionally size it for heavier builds:

```bash
container machine set -n devbox0 cpus=6 memory=12G
container machine stop devbox0
```

Changes from `container machine set` take effect the next time the machine starts.

## Run Commands

Open an interactive shell:

```bash
container machine run -n devbox0
```

Interactive shells are login bash sessions. They read the machine user's
`~/.profile`, which on Ubuntu sources `~/.bashrc` by default.

Run a single command:

```bash
container machine run -n devbox0 -- uname -a
```

Single commands run through `bash -c` and do not read interactive startup files.

Run as root when needed:

```bash
container machine run -n devbox0 --root -- apt-get update
```

Install Ghostty terminfo into an existing machine from the host Ghostty entry:

```bash
infocmp -x xterm-ghostty | container machine run -n devbox0 --root -- tic -x -
```

Set a default machine if you do not want to pass `-n` every time:

```bash
container machine set-default devbox0
container machine run
```

## Work In A Project

Your host home directory is mounted in the machine. For example, to work on `me0`:

```bash
container machine run -n devbox0
cd /Users/john/projects/me0
git status
```

Project Docker commands should work through Podman:

```bash
docker build -t me-server -f packages/server/Dockerfile .
docker run --rm docker.io/library/alpine:latest uname -m
docker compose up --build
```

The Docker-compatible API socket is available for tools that expect Docker Engine:

```bash
curl --unix-socket /run/docker.sock http://localhost/_ping
```

Expected output:

```text
OK
```

## Verify A Machine

Useful smoke checks after creating a machine:

```bash
container machine run -n devbox0 -- whoami
container machine run -n devbox0 -- psql --version
container machine run -n devbox0 -- docker --version
container machine run -n devbox0 -- docker compose version
container machine run -n devbox0 -- docker run --rm docker.io/library/alpine:latest uname -m
container machine run -n devbox0 -- curl --unix-socket /run/docker.sock http://localhost/_ping
```

## Lifecycle

List machines:

```bash
container machine ls
```

Inspect one machine:

```bash
container machine inspect devbox0
```

Stop a machine:

```bash
container machine stop devbox0
```

Start it again by running a shell or command:

```bash
container machine run -n devbox0
```

Delete a machine and its persistent storage:

```bash
container machine rm devbox0
```

## Notes

- Each machine has separate Podman images, containers, volumes, and networks.
- The same host checkout can be used from multiple machines, but only one agent should modify the same worktree at a time unless you are deliberately coordinating that work.
- For parallel agent work on the same project, use separate host worktrees or clones and a separate container machine per branch.
- The image exposes a permissive Podman-backed Docker socket because the container machine is already an isolated development VM. Do not treat that socket as a security boundary inside the VM.
