#!/usr/bin/env bash
#
# Linux-cleanser by px3l
# Interactive system cleanup for Debian-based distributions.
#
# Run with --dry-run first. Every destructive action is gated behind a prompt
# and printed before it happens.

set -euo pipefail

VERSION="2.0.0"

# Color definitions
RED="\033[0;31m"
YELLOW="\033[1;33m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
ENDCOLOR="\033[0m"

# Configuration
CONFIG_FILE="${CONFIG_FILE:-/etc/linux-cleanser.conf}"
LOG_FILE="${LOG_FILE:-/var/log/linux-cleanser.log}"

# Runtime flags
DRY_RUN=0
ASSUME_YES=0
AGGRESSIVE=0

# Resolved in check_prerequisites
REAL_USER=""
REAL_HOME=""
BACKUP_DIR=""

# Running total of bytes freed
TOTAL_RECLAIMED=0

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

say()  { echo -e "${YELLOW}[Linux-cleanser]: $1${ENDCOLOR}"; }
ok()   { echo -e "${GREEN}  $1${ENDCOLOR}"; }
warn() { echo -e "${RED}[Linux-cleanser]: $1${ENDCOLOR}"; }

log_message() {
    local level="$1" message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # Braces so a failed redirect is swallowed too, not just echo's own stderr.
    { echo "[$timestamp] [$level] $message" >> "$LOG_FILE"; } 2>/dev/null || true
}

error_exit() {
    warn "[ERROR]: $1"
    log_message "ERROR" "$1"
    exit 1
}

show_banner() {
    echo
    echo -e "${BLUE}  ====================================================  ${ENDCOLOR}"
    echo -e "${BLUE} ===                                                === ${ENDCOLOR}"
    echo -e "${BLUE}==               ${RED}Linux-cleanser by px3l${BLUE}               ==${ENDCOLOR}"
    echo -e "${BLUE} ===                     ${ENDCOLOR}v${VERSION}${BLUE}                      === ${ENDCOLOR}"
    echo -e "${BLUE}  ====================================================  ${ENDCOLOR}"
    echo
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "${BLUE}  DRY RUN — nothing will be deleted.${ENDCOLOR}"
        echo
    fi
}

usage() {
    cat <<'EOF'
Usage: sudo ./linux-cleanser.sh [OPTIONS]

Options:
  -n, --dry-run      Show what would be removed without deleting anything.
  -y, --yes          Assume yes for every prompt. Implies you know what you are doing.
  -a, --aggressive   Also offer deeper cleanups (all unused Docker images,
                     full build cache, whole ~/.cache). Still prompts.
  -h, --help         Show this help and exit.

Run with --dry-run first. Docker volumes are never removed; they are only
listed, because "dangling" does not mean "unwanted".
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)    DRY_RUN=1 ;;
            -y|--yes)        ASSUME_YES=1 ;;
            -a|--aggressive) AGGRESSIVE=1 ;;
            -h|--help)       usage; exit 0 ;;
            *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Core helpers
# ---------------------------------------------------------------------------

command_exists() { command -v "$1" >/dev/null 2>&1; }

ask_user() {
    local message="$1" default="${2:-n}" prompt reply

    if [[ $ASSUME_YES -eq 1 ]]; then
        log_message "PROMPT" "$message -> auto-yes"
        return 0
    fi

    if [[ "$default" == "y" ]]; then
        prompt="[Linux-cleanser]: $message (Y/n): "
    else
        prompt="[Linux-cleanser]: $message (y/N): "
    fi

    read -r -p "$(echo -e "${YELLOW}${prompt}${ENDCOLOR}")" -n 1 reply
    echo

    if [[ "$default" == "y" ]]; then
        [[ "$reply" =~ ^[Nn]$ ]] && { log_message "PROMPT" "$message -> no"; return 1; }
        log_message "PROMPT" "$message -> yes"
        return 0
    fi

    if [[ "$reply" =~ ^[Yy]$ ]]; then
        log_message "PROMPT" "$message -> yes"
        return 0
    fi

    log_message "PROMPT" "$message -> no"
    return 1
}

# Execute a command, or describe it under --dry-run.
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "${BLUE}  [dry-run] $*${ENDCOLOR}"
        log_message "DRYRUN" "$*"
        return 0
    fi
    log_message "EXEC" "$*"
    "$@"
}

# Execute a shell snippet (for pipelines and globs), or describe it.
run_sh() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "${BLUE}  [dry-run] sh -c: $1${ENDCOLOR}"
        log_message "DRYRUN" "sh -c: $1"
        return 0
    fi
    log_message "EXEC" "sh -c: $1"
    bash -c "$1" || true
}

# Run a command as the invoking user rather than root.
as_user() {
    if [[ -z "$REAL_USER" || "$REAL_USER" == "root" ]]; then
        run "$@"
        return
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "${BLUE}  [dry-run] (as $REAL_USER) $*${ENDCOLOR}"
        log_message "DRYRUN" "as $REAL_USER: $*"
        return 0
    fi
    log_message "EXEC" "as $REAL_USER: $*"
    sudo -u "$REAL_USER" -H "$@"
}

dir_bytes() {
    [[ -e "$1" ]] || { echo 0; return; }
    # du exits non-zero on any unreadable child, and pipefail would otherwise
    # let both the real total and a fallback "0" through.
    local out
    out=$(du -sb "$1" 2>/dev/null | cut -f1) || true
    [[ "$out" =~ ^[0-9]+$ ]] || out=0
    echo "$out"
}

human() {
    numfmt --to=iec-i --suffix=B "${1:-0}" 2>/dev/null || echo "${1:-0}B"
}

# Delete the *contents* of a directory, accounting for what was freed.
reclaim_dir() {
    local target="$1" label="${2:-$1}" bytes

    [[ -d "$target" ]] || return 0
    bytes=$(dir_bytes "$target")
    [[ "$bytes" -eq 0 ]] && return 0

    ok "$label — $(human "$bytes")"
    run_sh "rm -rf -- '${target:?}'/* '${target:?}'/.[!.]* 2>/dev/null"

    if [[ $DRY_RUN -eq 0 ]]; then
        TOTAL_RECLAIMED=$((TOTAL_RECLAIMED + bytes))
    fi
}

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

check_prerequisites() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root (try: sudo $0 --dry-run)"
    fi

    # Resolve the human behind the sudo, so user-level caches hit the right home.
    REAL_USER="${SUDO_USER:-root}"
    REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
    [[ -d "$REAL_HOME" ]] || error_exit "Could not resolve home directory for '$REAL_USER'"

    BACKUP_DIR="/var/backups/linux-cleanser"

    say "Target user: $REAL_USER ($REAL_HOME)"
    log_message "INFO" "Run started (user=$REAL_USER dry_run=$DRY_RUN aggressive=$AGGRESSIVE)"

    check_disk_space
    load_config
}

check_disk_space() {
    local available_space required_space=1048576  # 1GB in KB
    available_space=$(df / | awk 'NR==2 {print $4}')

    if [[ $available_space -lt $required_space ]]; then
        warn "Low disk space detected!"
        say "Available: $((available_space / 1024))MB"
        ask_user "Continue anyway?" || exit 1
    fi
}

load_config() {
    # shellcheck source=/dev/null
    [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
    return 0
}

create_backup() {
    say "Creating package list backup..."
    run mkdir -p "$BACKUP_DIR"
    local dest="$BACKUP_DIR/package-list-$(date +%Y%m%d-%H%M%S).txt"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "${BLUE}  [dry-run] dpkg --get-selections > $dest${ENDCOLOR}"
    else
        dpkg --get-selections > "$dest"
        ok "Saved to $dest"
        log_message "INFO" "Package list backed up to $dest"
    fi
}

show_cleanup_preview() {
    say "Scanning for reclaimable space (this takes a moment)..."
    echo

    local apt_c journal_c cache_c npm_c gradle_c oldconf_n

    apt_c=$(dir_bytes /var/cache/apt/archives)
    cache_c=$(dir_bytes "$REAL_HOME/.cache")
    npm_c=$(dir_bytes "$REAL_HOME/.npm")
    gradle_c=$(dir_bytes "$REAL_HOME/.gradle/caches")
    journal_c=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]?' | head -1 || echo "?")
    oldconf_n=$(dpkg -l 2>/dev/null | grep -c "^rc" || true)

    ok "APT archives      $(human "$apt_c")"
    ok "User cache        $(human "$cache_c")  ($REAL_HOME/.cache)"
    ok "npm cache         $(human "$npm_c")"
    ok "Gradle cache      $(human "$gradle_c")"
    ok "Journal logs      ${journal_c}"
    ok "Orphaned configs  ${oldconf_n} packages"

    if command_exists docker && docker info >/dev/null 2>&1; then
        echo
        say "Docker:"
        docker system df 2>/dev/null | sed 's/^/  /' || true
    fi
    echo
}

# ---------------------------------------------------------------------------
# System cleanup
# ---------------------------------------------------------------------------

clean_package_cache() {
    ask_user "Clean the APT package cache?" || return 0
    say "Flushing retrieved package files..."
    run apt-get clean
    run apt-get autoclean
}

clean_autoremove() {
    # apt's autoremove is also the correct, safe way to drop old kernels on
    # Ubuntu/Mint. The old hand-rolled kernel regex has been removed because it
    # would purge the newest kernel if you had updated but not yet rebooted.
    ask_user "Remove packages no longer required (includes superseded kernels)?" || return 0
    say "Removing redundant dependencies..."
    run apt-get -y --purge autoremove
}

handle_old_configs() {
    local oldconf
    oldconf=$(dpkg -l 2>/dev/null | awk '/^rc/ {print $2}' || true)

    if [[ -z "$oldconf" ]]; then
        say "No orphaned config files found."
        return 0
    fi

    say "Orphaned config files from removed packages:"
    echo "$oldconf" | sed 's/^/    /'
    ask_user "Purge these config files?" || return 0
    # shellcheck disable=SC2086
    run apt-get -y purge $oldconf
}

clean_journal_logs() {
    ask_user "Vacuum systemd journal logs (keep 7 days / 100M)?" || return 0
    say "Vacuuming systemd journal..."
    run journalctl --vacuum-time=7d
    run journalctl --vacuum-size=100M
}

clean_coredumps() {
    [[ -d /var/lib/systemd/coredump ]] || return 0
    local bytes
    bytes=$(dir_bytes /var/lib/systemd/coredump)
    [[ "$bytes" -lt 1048576 ]] && return 0

    say "Core dumps: $(human "$bytes")"
    ask_user "Remove stored core dumps?" || return 0
    reclaim_dir /var/lib/systemd/coredump "core dumps"
}

clean_temp_files() {
    ask_user "Remove /tmp and /var/tmp files untouched for 7+ days?" || return 0
    say "Cleaning stale temporary files..."
    run_sh "find /tmp -xdev -type f -atime +7 -delete 2>/dev/null"
    run_sh "find /var/tmp -xdev -type f -atime +7 -delete 2>/dev/null"
}

clean_rotated_logs() {
    # Only rotated/compressed logs. Deleting a live *.log that a daemon holds
    # open does not free the space and silently stops that daemon logging.
    ask_user "Remove rotated log archives older than 30 days?" || return 0
    say "Cleaning rotated logs (active .log files are left alone)..."
    run_sh "find /var/log -type f \\( -name '*.gz' -o -name '*.xz' -o -name '*.old' -o -regex '.*\\.[0-9]+' \\) -mtime +30 -delete 2>/dev/null"
}

# ---------------------------------------------------------------------------
# User-level caches
# ---------------------------------------------------------------------------

clean_user_caches() {
    local cache_root="$REAL_HOME/.cache"
    [[ -d "$cache_root" ]] || return 0

    # XDG says ~/.cache is disposable, but a few entries hold state that is
    # annoying rather than free to lose, so target the known-large ones.
    local targets=(
        mozilla sublime-text typescript Google BraveSoftware Chromium
        google-chrome mesa_shader_cache thumbnails mintinstall appstream
        fontconfig hugo_cache pip yarn go-build electron chromium
    )

    say "User caches under $cache_root:"
    local found=0 name
    for name in "${targets[@]}"; do
        [[ -d "$cache_root/$name" ]] && { found=1; ok "$name — $(human "$(dir_bytes "$cache_root/$name")")"; }
    done
    [[ $found -eq 0 ]] && { say "Nothing to clean."; return 0; }

    if ask_user "Clear these cache directories?"; then
        for name in "${targets[@]}"; do
            [[ -d "$cache_root/$name" ]] && reclaim_dir "$cache_root/$name" ".cache/$name"
        done
    fi

    if [[ $AGGRESSIVE -eq 1 ]]; then
        say "Whole cache directory: $(human "$(dir_bytes "$cache_root")")"
        ask_user "Also clear EVERYTHING else under $cache_root?" && reclaim_dir "$cache_root" ".cache"
    fi
}

clean_browser_caches() {
    # Note: these are unquoted on purpose so the profile globs expand.
    ask_user "Clear browser profile caches?" || return 0
    say "Clearing browser caches for $REAL_USER..."
    run_sh "rm -rf ${REAL_HOME}/.mozilla/firefox/*/cache2 2>/dev/null"
    run_sh "rm -rf ${REAL_HOME}/.config/BraveSoftware/*/Default/Cache 2>/dev/null"
    run_sh "rm -rf ${REAL_HOME}/.config/google-chrome/*/Cache 2>/dev/null"
    run_sh "rm -rf ${REAL_HOME}/.config/chromium/*/Cache 2>/dev/null"
    # Flatpak browsers keep their own tree.
    run_sh "rm -rf ${REAL_HOME}/.var/app/org.mozilla.firefox/cache/* 2>/dev/null"
}

clean_thumbnail_cache() {
    local thumbs="$REAL_HOME/.cache/thumbnails"
    [[ -d "$thumbs" ]] || return 0
    say "Thumbnail cache: $(human "$(dir_bytes "$thumbs")")"
    ask_user "Clear the thumbnail cache?" || return 0
    reclaim_dir "$thumbs" "thumbnails"
}

# ---------------------------------------------------------------------------
# Developer toolchain caches
# ---------------------------------------------------------------------------

clean_dev_caches() {
    # This only ever touches *caches*. It never walks the filesystem deleting
    # node_modules — that used to live here and would take out
    # ~/.nvm/.../lib/node_modules, i.e. npm itself.
    say "Developer toolchain caches:"

    local npm_c="$REAL_HOME/.npm"
    local pnpm_c="$REAL_HOME/.local/share/pnpm/store"
    local yarn_c="$REAL_HOME/.cache/yarn"
    local gradle_c="$REAL_HOME/.gradle/caches"
    local pip_c="$REAL_HOME/.cache/pip"
    local go_c="$REAL_HOME/go/pkg/mod"

    local p bytes
    for p in "$npm_c" "$pnpm_c" "$yarn_c" "$gradle_c" "$pip_c" "$go_c"; do
        [[ -d "$p" ]] || continue
        bytes=$(dir_bytes "$p")
        [[ "$bytes" -gt 0 ]] && ok "${p/#$REAL_HOME/\~} — $(human "$bytes")"
    done

    ask_user "Clear developer toolchain caches?" || return 0

    if command_exists npm && [[ -d "$npm_c" ]]; then
        say "Cleaning npm cache..."
        as_user npm cache clean --force
    fi
    if command_exists pnpm && [[ -d "$pnpm_c" ]]; then
        say "Pruning pnpm store..."
        as_user pnpm store prune
    fi
    [[ -d "$yarn_c" ]]   && reclaim_dir "$yarn_c" "yarn cache"
    [[ -d "$gradle_c" ]] && reclaim_dir "$gradle_c" "gradle caches"
    [[ -d "$pip_c" ]]    && reclaim_dir "$pip_c" "pip cache"

    if [[ -d "$go_c" ]] && command_exists go; then
        say "Cleaning Go module cache..."
        as_user go clean -modcache
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Containers and sandboxed apps
# ---------------------------------------------------------------------------

# Print every stopped container with the volumes it holds, so the real cost of
# removing it is visible at the prompt. Container prune reclaims almost nothing
# in bytes; what it actually destroys is the only link between a project and an
# anonymous volume holding its data.
list_stopped_containers() {
    local ids id name image state mounts mtype mname mdest anon=0

    ids=$(docker ps -aq --filter status=exited --filter status=created 2>/dev/null || true)
    [[ -z "$ids" ]] && return 1

    while read -r id; do
        [[ -n "$id" ]] || continue
        name=$(docker inspect "$id" --format '{{.Name}}' 2>/dev/null | sed 's|^/||') || true
        image=$(docker inspect "$id" --format '{{.Config.Image}}' 2>/dev/null) || true
        state=$(docker inspect "$id" --format '{{.State.Status}}' 2>/dev/null) || true
        echo -e "${GREEN}  ${name:-$id}${ENDCOLOR}  (${image:-unknown}, ${state:-unknown})"

        mounts=$(docker inspect "$id" --format \
            '{{range .Mounts}}{{.Type}}|{{if eq .Type "volume"}}{{.Name}}{{else}}{{.Source}}{{end}}|{{.Destination}}{{println}}{{end}}' \
            2>/dev/null) || true

        if [[ -z "${mounts//[[:space:]]/}" ]]; then
            echo "      no volumes"
        else
            while IFS='|' read -r mtype mname mdest; do
                [[ -n "$mtype" ]] || continue
                if [[ "$mtype" == "volume" && "$mname" =~ ^[0-9a-f]{64}$ ]]; then
                    echo -e "      ${RED}anonymous volume${ENDCOLOR} ${mname} -> ${mdest}"
                    anon=1
                else
                    echo "      ${mtype} ${mname} -> ${mdest}"
                fi
            done <<< "$mounts"
        fi
    done <<< "$ids"

    if [[ $anon -eq 1 ]]; then
        echo
        warn "Some of the containers above hold ANONYMOUS volumes."
        say "Removing the container does not delete the volume, but it does leave it"
        say "as an unnamed hash with nothing pointing at it. Copy those hashes"
        say "somewhere before answering yes, or keep the containers."
    fi
    return 0
}

clean_docker() {
    command_exists docker || return 0
    docker info >/dev/null 2>&1 || { say "Docker installed but daemon unreachable, skipping."; return 0; }

    say "Docker usage:"
    docker system df 2>/dev/null | sed 's/^/    /' || true
    echo

    if list_stopped_containers; then
        echo
        if ask_user "Remove the stopped containers listed above?"; then
            run docker container prune -f
        fi
    fi

    if ask_user "Remove dangling (untagged) images?"; then
        run docker image prune -f
    fi

    if ask_user "Prune unused build cache?"; then
        run docker builder prune -f
    fi

    if [[ $AGGRESSIVE -eq 1 ]]; then
        warn "Aggressive mode: the next two remove anything not attached to a running container."
        ask_user "Remove ALL unused images (forces re-pull later)?" && run docker image prune -a -f
        ask_user "Remove the ENTIRE build cache (slower rebuilds)?" && run docker builder prune -a -f
    fi

    # Volumes are deliberately never pruned. "Dangling" only means no container
    # currently references it, which is also true of every dev database whose
    # container has been recreated.
    local dangling
    dangling=$(docker volume ls -qf dangling=true 2>/dev/null || true)
    if [[ -n "$dangling" ]]; then
        echo
        warn "These Docker volumes are unreferenced but were NOT touched:"
        echo "$dangling" | sed 's/^/    /'
        say "Review them yourself — some may hold project databases."
        say "Remove one with: docker volume rm <name>"
    fi
}

clean_flatpak_snap() {
    if command_exists flatpak; then
        ask_user "Remove unused Flatpak runtimes?" && run flatpak uninstall --unused -y
    fi

    if command_exists snap; then
        if ask_user "Remove disabled (superseded) snap revisions?"; then
            say "Removing old snap revisions..."
            run_sh "snap list --all | awk '/disabled/{print \$1, \$3}' | while read -r n r; do snap remove \"\$n\" --revision=\"\$r\"; done"
        fi
    fi
}

# ---------------------------------------------------------------------------
# User data
# ---------------------------------------------------------------------------

handle_shell_history() {
    # Runs as root, so ~ would be /root. Target the real user's files instead.
    local files=("$REAL_HOME/.bash_history" "$REAL_HOME/.zsh_history")
    local existing=() f
    for f in "${files[@]}"; do
        [[ -f "$f" ]] && existing+=("$f")
    done
    [[ ${#existing[@]} -eq 0 ]] && return 0

    say "Shell history files for $REAL_USER:"
    printf '    %s\n' "${existing[@]}"
    ask_user "Clear shell history? This cannot be undone." || return 0
    for f in "${existing[@]}"; do
        run truncate -s 0 "$f"
    done
}

empty_trash() {
    local trash="$REAL_HOME/.local/share/Trash"
    [[ -d "$trash" ]] || return 0
    say "Trash: $(human "$(dir_bytes "$trash")")"
    ask_user "Empty the trash?" || return 0
    for sub in files info expunged; do
        [[ -d "$trash/$sub" ]] && reclaim_dir "$trash/$sub" "trash/$sub"
    done
}

# ---------------------------------------------------------------------------

show_summary() {
    echo
    if [[ $DRY_RUN -eq 1 ]]; then
        say "Dry run complete. Nothing was deleted."
        say "Re-run without --dry-run to apply."
    else
        say "Cleansing complete. Freed roughly $(human "$TOTAL_RECLAIMED") in tracked directories."
        say "Package manager and Docker reclaim is reported inline above."
    fi
    log_message "INFO" "Run finished (tracked_reclaimed=$TOTAL_RECLAIMED)"
    echo
}

main() {
    parse_args "$@"
    show_banner
    check_prerequisites
    show_cleanup_preview

    ask_user "Create a package list backup first?" "y" && create_backup

    clean_package_cache
    clean_autoremove
    handle_old_configs

    clean_journal_logs
    clean_coredumps
    clean_temp_files
    clean_rotated_logs

    clean_user_caches
    clean_browser_caches
    clean_thumbnail_cache

    clean_dev_caches
    clean_docker
    clean_flatpak_snap

    handle_shell_history
    empty_trash

    show_summary
}

main "$@"
