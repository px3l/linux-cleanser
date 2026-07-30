# Linux Cleanser

Interactive system cleanup for Debian-based distributions. Reclaims disk space from
package caches, logs, browser and toolchain caches, and Docker, prompting before
every destructive step.

## Usage

```bash
chmod +x linux-cleanser.sh
sudo ./linux-cleanser.sh --dry-run   # see what would happen
sudo ./linux-cleanser.sh             # actually do it
```

### Options

| Flag | Effect |
|------|--------|
| `-n`, `--dry-run` | Print every action without deleting anything. |
| `-y`, `--yes` | Assume yes at every prompt. |
| `-a`, `--aggressive` | Offer deeper cleanups (all unused Docker images, full build cache, the whole `~/.cache`). Still prompts. |
| `-h`, `--help` | Show usage. |

Always run `--dry-run` first.

## What it cleans

**System**
- APT package cache and orphaned config files from removed packages
- Packages no longer required, via `apt-get --purge autoremove` (this is also what
  removes superseded kernels)
- systemd journal, vacuumed to 7 days / 100M
- Stored core dumps
- `/tmp` and `/var/tmp` files untouched for 7+ days
- Rotated log archives in `/var/log` older than 30 days

**User**
- Known-large `~/.cache` entries (Firefox, Brave, Chrome, Chromium, Sublime,
  TypeScript, mesa shader cache, thumbnails, fontconfig, and others)
- Browser profile caches
- Trash
- Shell history, on request

**Developer toolchains**
- npm cache (`npm cache clean --force`)
- pnpm store, Yarn cache
- Gradle caches, pip cache, Go module cache

**Containers and sandboxed apps**
- Stopped Docker containers, dangling images, unused build cache
- Unused Flatpak runtimes and superseded snap revisions

## Safety

The script runs as root, so it is deliberately conservative about a few things.

**Docker volumes are never removed.** They are listed if unreferenced, and that is
all. Docker reports a volume as "dangling" whenever no container currently
references it, which is also true of every project database whose container has
been recreated. Removing one is a manual `docker volume rm`.

**Stopped containers are listed with their volumes before you are asked.** Pruning
containers reclaims almost nothing in bytes, so the prompt looks trivial. What it
actually destroys is the only link between a project and an anonymous volume
holding its data, so any anonymous volume is called out in red before the prompt.

**`node_modules` directories are never touched.** Only toolchain *caches* are
cleared. A recursive `node_modules` sweep would delete
`~/.nvm/versions/node/*/lib/node_modules`, which is where globally installed
packages live, including npm itself.

**Broken symlinks are not removed.** Firefox, Steam and Electron apps all use
deliberately-dangling symlinks as lock files and singleton markers, so a broken
symlink is not reliable evidence of anything.

**Active `.log` files are left alone.** Only rotated archives (`*.gz`, `*.xz`,
`*.1`) are removed. Deleting a log file that a running daemon holds open does not
free the space and silently stops that daemon logging until it restarts.

Other safeguards:
- Root check, and low-disk-space warning before starting
- Package list backed up to `/var/backups/linux-cleanser/` (not `/tmp`, which the
  script itself cleans)
- User-level paths resolve via `SUDO_USER`, so they hit your home rather than `/root`
- Every action is logged to `/var/log/linux-cleanser.log`

## Requirements

- Root privileges
- Debian-based distribution (Ubuntu, Mint, Debian)
- `bash`, `coreutils`. Docker, Flatpak, snap, npm and friends are all optional and
  detected at runtime.

## Warning

This script deletes files as root. Run `--dry-run` first and read the output.
