#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#   Tsugumori installer — Hyprland + Quickshell + Waybar rice
#   Usage: bash <(curl -fsSL https://raw.githubusercontent.com/Aleph1-9012/Tsugumori/main/install.sh)
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────
readonly REPO_URL="${TSUGUMORI_REPO_URL:-https://github.com/Aleph1-9012/Tsugumori.git}"
readonly REPO_BRANCH="${TSUGUMORI_BRANCH:-main}"
readonly CLONE_DIR="${TMPDIR:-/tmp}/Tsugumori-install-$$"
readonly MIN_HYPRLAND_VERSION="0.55.2"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Files that must NEVER be overwritten by re-running the installer.
# Relative to $CONFIG_HOME.
readonly PRESERVED_FILES=(
    "hypr/user.lua"
    # Retained only as migration input. Native Lua does not load this file, but
    # an upgrade must never destroy a user's legacy machine-specific settings.
    "hypr/user.conf"
    "quickshell/settings/Settings.qml"
)

# Add support for flags
PINNED_MODE=false
VM_GL_TWEAKS=false          # Mesa llvmpipe + software libgl for Quickshell/Kitty (VirtualBox and similar).
BOOT_WALLPAPER_VM=false     # Lua start callback applies the first wallpaper in VM mode

[[ "${TSUGUMORI_VM:-}" == "1" || "${TSUGUMORI_VM:-}" == "yes" ]] && VM_GL_TWEAKS=true

for arg in "$@"; do
    case "$arg" in
        --pinned) PINNED_MODE=true ;;
        --latest) PINNED_MODE=false ;;
        --vm)     VM_GL_TWEAKS=true ;;
        --help|-h)
            cat <<EOF
Usage: install.sh [options]

  --latest   Install latest versions of all packages (default).
  --pinned   Install exact versions tested by the maintainer.
             Requires packages/pinned-pacman.txt.
  --vm       VirtualBox / weak GPU: configure Quickshell + Kitty to use software OpenGL
             (llvmpipe), optional boot wallpaper. Or set env TSUGUMORI_VM=1.

  Also: TSUGUMORI_VM=1 same effect as --vm for non-interactive installs.
EOF
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\nRun install.sh --help for usage.\n' "$arg" >&2
            exit 2
            ;;
    esac
done

# Folders managed by this installer (touched in $CONFIG_HOME)
readonly MANAGED_DIRS=(hypr quickshell waybar kitty)

# Temp dir used to stash preserved user files during install
PRESERVED_STASH=""
LEGACY_USER_CONF_ACTIVE=false

# ─── Colors & logging ───────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m';   C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[0;33m'; C_BLUE=$'\033[0;34m'
    C_BOLD=$'\033[1m';     C_RESET=$'\033[0m'
else
    C_RED='';C_GREEN='';C_YELLOW='';C_BLUE='';C_BOLD='';C_RESET=''
fi
log()   { printf "%s[*]%s %s\n" "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf "%s[✓]%s %s\n" "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf "%s[!]%s %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err()   { printf "%s[✗]%s %s\n" "$C_RED"    "$C_RESET" "$*" >&2; }
fatal() { err "$*"; exit 1; }

ask_yn() {
    local prompt="$1" default="${2:-n}" reply hint="[y/N]"
    [[ "$default" == "y" ]] && hint="[Y/n]"
    while true; do
        read -rp "$(printf '%s[?]%s %s %s ' "$C_YELLOW" "$C_RESET" "$prompt" "$hint")" reply
        reply="${reply:-$default}"
        case "${reply,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) warn "Please answer y or n." ;;
        esac
    done
}

cleanup() {
    [[ -d "$CLONE_DIR" ]] && rm -rf "$CLONE_DIR"
    [[ -n "$PRESERVED_STASH" && -d "$PRESERVED_STASH" ]] && rm -rf "$PRESERVED_STASH"
    return 0
}
trap cleanup EXIT

# ─── Pre-flight ─────────────────────────────────────────────────────
preflight() {
    log "Running pre-flight checks…"
    [[ $EUID -ne 0 ]] || fatal "Do not run this script as root. Run as your normal user; sudo will be invoked when needed."
    command -v pacman >/dev/null || fatal "pacman not found — this script is for Arch Linux only."
    command -v sudo   >/dev/null || fatal "sudo is required."
    command -v curl   >/dev/null || fatal "curl is required for connectivity checks and remote installation."
    command -v realpath >/dev/null || fatal "GNU realpath is required for safe symlink preservation."
    if ! realpath --canonicalize-missing --no-symlinks -- / >/dev/null 2>&1 \
        || ! realpath --canonicalize-existing -- / >/dev/null 2>&1; then
        fatal "GNU realpath with --canonicalize-missing, --no-symlinks, and --canonicalize-existing support is required for safe symlink preservation."
    fi
    log "Asking for sudo password upfront…"
    sudo -v || fatal "sudo authentication failed."
    # Keep sudo alive in background
    while true; do sudo -n true; sleep 60; kill -0 $$ 2>/dev/null || exit; done 2>/dev/null &
    log "Checking internet connectivity…"
    curl -fsSIL --connect-timeout 5 --max-time 10 https://archlinux.org/ >/dev/null 2>&1 || fatal "Could not reach archlinux.org."
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        warn "You are running this from inside Hyprland. You will need to log out / restart your session at the end."
    fi
    ok "All checks passed."
}

# ─── User prompts ───────────────────────────────────────────────────
collect_choices() {
    echo
    log "I'll ask a few questions before starting."
    echo
    BACKUP_OLD=true;          ask_yn "Backup existing configs to $BACKUP_DIR?" y || BACKUP_OLD=false
    INSTALL_WALLPAPERS=true;  ask_yn "Install default wallpapers to ~/Pictures/wallpapers?" y || INSTALL_WALLPAPERS=false
    INSTALL_BASHRC=true;      ask_yn "Install Tsugumori .bashrc (welcome banner + Tsugumori prompt)?" y || INSTALL_BASHRC=false
    ENABLE_SERVICES=true;     ask_yn "Enable system services (NetworkManager, pipewire)?" y || ENABLE_SERVICES=false

    if $VM_GL_TWEAKS; then
        log "VirtualBox / software-GL mode enabled (--vm or TSUGUMORI_VM=1)."
    elif ask_yn "VirtualBox or limited GPU? Apply software OpenGL for Quickshell + Kitty (fixes many VM crashes)" n; then
        VM_GL_TWEAKS=true
    fi
    if $VM_GL_TWEAKS && $INSTALL_WALLPAPERS; then
        BOOT_WALLPAPER_VM=false
        ask_yn "Apply the first bundled wallpaper automatically at each Hyprland login (awww)?" y && BOOT_WALLPAPER_VM=true || true
    fi
    echo
}

# ─── Hyprland user-config migration check ──────────────────────────
inspect_legacy_user_config() {
    local legacy="$CONFIG_HOME/hypr/user.conf"

    [[ -f "$legacy" ]] || return 0

    # Comments-only templates need no translation. Any other line may contain
    # a monitor, binding, or machine setting which the Lua entry point cannot
    # source, so fail closed unless a user.lua is already present.
    if awk '
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            if (line != "" && line !~ /^#/) {
                found = 1
                exit
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$legacy"; then
        LEGACY_USER_CONF_ACTIVE=true
        warn "Legacy Hyprland overrides detected in $legacy."
        warn "Native Hyprland Lua does not load user.conf; translate those settings to $CONFIG_HOME/hypr/user.lua."
        if [[ ! -f "$CONFIG_HOME/hypr/user.lua" ]]; then
            warn "No user.lua exists, so continuing would silently disable these overrides."
            warn "Installation stopped before package or configuration changes; user.conf is untouched."
            fatal "Migrate active hypr/user.conf overrides to user.lua before installing the Lua configuration."
        fi

        warn "The existing user.lua and dormant user.conf will both be preserved without modification."
        if [[ "${BACKUP_OLD:-false}" == "true" ]]; then
            warn "A second copy of user.conf will be kept under $BACKUP_DIR/hypr/."
        else
            warn "Backups are disabled; keep a manual copy until migration is complete."
        fi
    fi
}

# ─── Base setup ─────────────────────────────────────────────────────
install_base() {
    log "Installing git…"
    sudo pacman -S --needed --noconfirm git
}

# ─── Clone ──────────────────────────────────────────────────────────
clone_repo() {
    log "Cloning Tsugumori ($REPO_BRANCH)…"
    git clone --depth=1 --branch "$REPO_BRANCH" "$REPO_URL" "$CLONE_DIR"
}

# ─── Packages ───────────────────────────────────────────────────────
require_manifest() {
    local file="$1"
    [[ -f "$file" ]] || fatal "Required package manifest is missing: ${file#"$CLONE_DIR/"}. This checkout cannot perform the requested installation mode."
}

validate_pinned_manifest() {
    local source_manifest="$1" pinned_manifest="$2" label="$3"
    local expected actual invalid duplicates
    invalid=$(awk -F= '!/^[[:space:]]*(#|$)/ && (NF != 3 || $1 == "" || $2 == "" || $3 == "" || ($3 != "any" && $3 != "x86_64")) {print NR ":" $0}' "$pinned_manifest")
    [[ -z "$invalid" ]] || fatal "$label pinned manifest contains malformed records; expected package=version=architecture."
    expected=$(grep -vE '^\s*(#|$)' "$source_manifest" | sort)
    actual=$(awk -F= '!/^[[:space:]]*(#|$)/ {print $1}' "$pinned_manifest" | sort)
    duplicates=$(awk -F= '!/^[[:space:]]*(#|$)/ {count[$1]++} END {for (pkg in count) if (count[pkg] > 1) print pkg}' "$pinned_manifest")
    [[ -z "$duplicates" ]] || fatal "$label pinned manifest contains duplicate package records."
    [[ "$expected" == "$actual" ]] || fatal "$label pinned manifest does not exactly match its package manifest; regenerate it with scripts/update-pins.sh."
}

install_packages() {
    local pacman_list="$CLONE_DIR/packages/pacman.txt"

    require_manifest "$pacman_list"

    if $PINNED_MODE; then
        local pinned_pacman="$CLONE_DIR/packages/pinned-pacman.txt"
        log "Pinned mode: installing exact tested versions from Arch Archive."

        require_manifest "$pinned_pacman"
        validate_pinned_manifest "$pacman_list" "$pinned_pacman" "Pacman"

        local pinned_hyprland=""
        pinned_hyprland=$(awk -F= '$1 == "hyprland" {print $2; exit}' "$pinned_pacman")
        [[ -n "$pinned_hyprland" ]] || fatal "packages/pinned-pacman.txt does not pin Hyprland; refusing an unverifiable pinned install."
        log "Installing pinned pacman packages…"
        install_pinned_from_archive "$pinned_pacman"
    else
        # Latest mode (default)
        local pacman_pkgs
        mapfile -t pacman_pkgs < <(grep -vE '^\s*(#|$)' "$pacman_list")

        # Older Tsugumori releases installed quickshell-git from the AUR. It
        # provides the same `quickshell` dependency but conflicts with the now
        # official package. Preserve a working provider instead of forcing a
        # destructive package replacement during an unattended upgrade.
        if pacman -T quickshell >/dev/null 2>&1; then
            local installed_qs_version=""
            installed_qs_version=$(qs --version 2>/dev/null | sed -n 's/.* \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1)
            [[ -n "$installed_qs_version" ]] || fatal "The installed Quickshell provider has an unreadable version; install official quickshell 0.3 or newer."
            if [[ "$(vercmp "$installed_qs_version" 0.3.0)" == -* ]]; then
                fatal "The installed Quickshell provider is $installed_qs_version. Replace it with official quickshell 0.3 or newer before installing Tsugumori."
            fi
            local filtered_pacman_pkgs=()
            local package
            for package in "${pacman_pkgs[@]}"; do
                [[ "$package" == "quickshell" ]] || filtered_pacman_pkgs+=("$package")
            done
            pacman_pkgs=("${filtered_pacman_pkgs[@]}")
            ok "An installed package already provides Quickshell; keeping it."
        fi

        if (( ${#pacman_pkgs[@]} > 0 )); then
            log "Installing ${#pacman_pkgs[@]} pacman packages (latest)…"
            sudo pacman -S --needed --noconfirm "${pacman_pkgs[@]}"
        fi
    fi
}

validate_font_assets() {
    local source_dir="$CLONE_DIR/assets/fonts/share-tech-mono"
    [[ -s "$source_dir/ShareTechMono-Regular.ttf" ]] \
        || fatal "Bundled Share Tech Mono font is missing or empty."
    [[ -s "$source_dir/OFL.txt" ]] \
        || fatal "Bundled Share Tech Mono OFL license is missing or empty."
    ok "Bundled Share Tech Mono font and license are present."
}

install_font_assets() {
    local source_dir="$CLONE_DIR/assets/fonts/share-tech-mono"
    local font_source="$source_dir/ShareTechMono-Regular.ttf"
    local license_source="$source_dir/OFL.txt"
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local font_dir="$data_home/fonts/Tsugumori"
    local font_tmp license_tmp

    [[ -s "$font_source" ]] || fatal "Bundled Share Tech Mono font is missing or empty."
    [[ -s "$license_source" ]] || fatal "Bundled Share Tech Mono OFL license is missing or empty."

    install -d -m 0755 -- "$font_dir"
    font_tmp=$(mktemp "$font_dir/.ShareTechMono-Regular.ttf.XXXXXX")
    license_tmp=$(mktemp "$font_dir/.OFL.txt.XXXXXX")
    if ! install -m 0644 -- "$font_source" "$font_tmp" \
        || ! install -m 0644 -- "$license_source" "$license_tmp"; then
        rm -f -- "$font_tmp" "$license_tmp"
        fatal "Could not prepare bundled Share Tech Mono assets."
    fi
    if ! mv -f -- "$font_tmp" "$font_dir/ShareTechMono-Regular.ttf" \
        || ! mv -f -- "$license_tmp" "$font_dir/OFL.txt"; then
        rm -f -- "$font_tmp" "$license_tmp"
        fatal "Could not install bundled Share Tech Mono assets."
    fi

    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f "$font_dir" >/dev/null 2>&1 \
            || warn "Font cache refresh failed; log out and back in before using Share Tech Mono."
    else
        warn "fc-cache is unavailable; log out and back in before using Share Tech Mono."
    fi
    ok "Installed bundled Share Tech Mono font: $font_dir"
}

validate_hyprland_config() {
    local config="$CLONE_DIR/config/hypr/hyprland.lua"
    local installed_version candidate_root candidate_config runtime_dir runtime_tmp=""

    command -v Hyprland >/dev/null || fatal "Hyprland was not installed; cannot validate the bundled configuration."
    command -v vercmp >/dev/null || fatal "vercmp was not installed; cannot enforce the Hyprland compatibility floor."
    [[ -f "$config" ]] || fatal "Bundled Hyprland Lua configuration is missing."
    [[ -f "$CLONE_DIR/config/hypr/user.lua" ]] || fatal "Bundled Hyprland user.lua template is missing."
    [[ -f "$CLONE_DIR/config/hypr/tsugumori_options.lua" ]] || fatal "Bundled installer options module is missing."

    installed_version=$(pacman -Q hyprland 2>/dev/null | awk 'NR == 1 { print $2 }')
    [[ -n "$installed_version" ]] || fatal "Could not determine the installed Hyprland package version."
    if [[ "$(vercmp "$installed_version" "$MIN_HYPRLAND_VERSION")" == -* ]]; then
        fatal "Hyprland $MIN_HYPRLAND_VERSION or newer is required for native Lua; found $installed_version."
    fi

    runtime_dir="${XDG_RUNTIME_DIR:-}"
    if [[ -z "$runtime_dir" || ! -d "$runtime_dir" ]]; then
        runtime_tmp=$(mktemp -d)
        chmod 700 "$runtime_tmp"
        runtime_dir="$runtime_tmp"
    fi

    log "Validating bundled Lua configuration with Hyprland $installed_version…"
    if ! XDG_RUNTIME_DIR="$runtime_dir" Hyprland --verify-config --config "$config"; then
        [[ -z "$runtime_tmp" ]] || rm -rf "$runtime_tmp"
        fatal "The installed Hyprland cannot parse this Tsugumori configuration. No user configuration has been replaced."
    fi

    # Validate the exact effective configuration before deployment. A preserved
    # user.lua is executable Lua and can fail even when the bundled template is
    # valid, so place it and the selected installer options in a private copy.
    candidate_root=$(mktemp -d)
    mkdir -p "$candidate_root/hypr"
    cp -a "$CLONE_DIR/config/hypr/." "$candidate_root/hypr/"
    if [[ -f "$CONFIG_HOME/hypr/user.lua" ]]; then
        # Dereference only this validation copy. A relative user.lua symlink is
        # valid at ~/.config/hypr but would point somewhere else from the
        # private candidate directory. Stash/restore deliberately keeps `cp -a`
        # so the deployed user-owned symlink itself is preserved.
        cp -L "$CONFIG_HOME/hypr/user.lua" "$candidate_root/hypr/user.lua"
    fi
    write_tsugumori_options "$candidate_root/hypr/tsugumori_options.lua" false
    candidate_config="$candidate_root/hypr/hyprland.lua"

    if ! XDG_RUNTIME_DIR="$runtime_dir" Hyprland --verify-config --config "$candidate_config"; then
        rm -rf "$candidate_root"
        [[ -z "$runtime_tmp" ]] || rm -rf "$runtime_tmp"
        fatal "Hyprland cannot parse the candidate Lua configuration, including preserved user overrides. No user configuration has been replaced."
    fi

    rm -rf "$candidate_root"
    [[ -z "$runtime_tmp" ]] || rm -rf "$runtime_tmp"
    ok "Bundled and candidate Hyprland Lua configurations parsed successfully."
}

validate_wallpaper_runtime() {
    command -v awww >/dev/null || fatal "awww was not installed; the wallpaper picker requires the official awww package."
    command -v awww-daemon >/dev/null || fatal "awww-daemon was not installed; the wallpaper picker cannot operate without it."
    ok "Wallpaper client and daemon are installed."
}

validate_lock_runtime() {
    local lock_root="$CLONE_DIR/config/quickshell"
    local asset qs_version

    command -v qs >/dev/null || fatal "Quickshell was not installed; refusing to deploy a session whose lock client cannot start."
    command -v hyprlock >/dev/null || fatal "Hyprlock was not installed; its PAM service and fallback client are required."
    command -v ffmpeg >/dev/null || fatal "ffmpeg was not installed; the animated lock requires its Qt multimedia backend."
    command -v flock >/dev/null || fatal "flock was not found; the lock launch guard requires util-linux."
    qs_version=$(qs --version 2>/dev/null | sed -n 's/.* \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1)
    [[ -n "$qs_version" ]] || fatal "Could not determine the installed Quickshell version."
    [[ "$(vercmp "$qs_version" 0.3.0)" != -* ]] || fatal "Quickshell 0.3 or newer is required; found $qs_version."
    [[ -r /etc/pam.d/hyprlock ]] || fatal "The required PAM service /etc/pam.d/hyprlock is missing."
    [[ -r "$lock_root/widgets/lockscreen.qml" ]] || fatal "The secure Quickshell lockscreen is missing from the checkout."

    for asset in wave_reveal.mp4 wave_hide.mp4 wave_last_frame.png; do
        [[ -s "$lock_root/videos/$asset" ]] || fatal "Required secure-lock asset is missing or empty: config/quickshell/videos/$asset"
    done
    ok "Secure lock runtime and bundled animation assets are present."
}

install_pinned_from_archive() {
    local pinned_file="$1"
    local archive_base="https://archive.archlinux.org/packages"
    local urls=()

    while IFS='=' read -r pkg version architecture; do
        [[ "$pkg" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${pkg//[[:space:]]/}" ]] && continue
        [[ -n "$pkg" && -n "$version" && -n "$architecture" ]] || fatal "Malformed non-comment record in $pinned_file."
        [[ "$architecture" == "any" || "$architecture" == "x86_64" ]] || fatal "Unsupported pinned architecture for $pkg: $architecture"
        # Archive structure: /packages/<first-letter>/<pkg>/<pkg>-<version>-<architecture>.pkg.tar.zst
        local first="${pkg:0:1}"
        local url="$archive_base/$first/$pkg/$pkg-$version-$architecture.pkg.tar.zst"
        urls+=("$url")
    done < "$pinned_file"

    if (( ${#urls[@]} > 0 )); then
        sudo pacman -U --noconfirm "${urls[@]}"
    fi
}

# ─── Preserve user files across re-installs ─────────────────────────
path_is_within() {
    local candidate="$1" root="$2"
    if [[ "$root" == "/" ]]; then
        [[ "$candidate" == /* ]]
    else
        [[ "$candidate" == "$root" || "$candidate" == "$root/"* ]]
    fi
}

fatal_preserved_symlink_dependency() {
    local src="$1" link_target="$2" name="$3"
    fatal "Preserved symlink $src -> $link_target depends on $CONFIG_HOME/$name, and deployment would remove that dependency. Move the target outside installer-managed directories or replace the link with a regular file."
}

assert_relative_symlink_parent_is_stable() {
    local src="$1" link_target="$2"
    local source_parent lexical_parent canonical_parent canonical_config_home
    local name lexical_root managed_entry parent_suffix future_parent

    [[ "$link_target" != /* ]] || return 0

    source_parent=$(dirname -- "$src")
    lexical_parent=$(realpath --canonicalize-missing --no-symlinks -- "$source_parent")
    canonical_parent=$(realpath --canonicalize-existing -- "$source_parent")
    canonical_config_home=$(realpath --canonicalize-missing -- "$CONFIG_HOME")

    for name in "${MANAGED_DIRS[@]}"; do
        lexical_root=$(realpath --canonicalize-missing --no-symlinks -- "$CONFIG_HOME/$name")
        path_is_within "$lexical_parent" "$lexical_root" || continue

        # Deployment replaces the managed entry with a fresh tree. Build the
        # physical parent path that the restored relative link will use without
        # following any current symlink at or below that entry. If it differs
        # from today's parent, the link's anchor would change during deploy.
        managed_entry=$(realpath --canonicalize-missing --no-symlinks -- "$canonical_config_home/$name")
        parent_suffix="${lexical_parent#"$lexical_root"}"
        future_parent=$(realpath --canonicalize-missing --no-symlinks -- "$managed_entry$parent_suffix")
        if [[ "$canonical_parent" != "$future_parent" ]]; then
            fatal_preserved_symlink_dependency "$src" "$link_target" "$name"
        fi
        return 0
    done
}

assert_symlink_resolution_avoids_managed_dirs() {
    local src="$1" link_target="$2"
    local resolved pending component probe hop_target name
    local lexical_root canonical_root managed_entry canonical_config_home
    local symlink_hops=0

    # Follow the target one path component at a time. GNU realpath gives us the
    # two endpoint views checked by the caller, but a fully resolved endpoint
    # does not reveal an outside -> managed -> outside symlink chain. Start
    # relative targets at the link's existing parent; that parent is deliberately
    # not treated as a dependency because deployment recreates it before restore.
    canonical_config_home=$(realpath --canonicalize-missing -- "$CONFIG_HOME")
    if [[ "$link_target" == /* ]]; then
        resolved="/"
        pending="${link_target#/}"
    else
        resolved=$(realpath --canonicalize-existing -- "$(dirname -- "$src")")
        pending="$link_target"
    fi

    while [[ -n "$pending" ]]; do
        if [[ "$pending" == */* ]]; then
            component="${pending%%/*}"
            pending="${pending#*/}"
        else
            component="$pending"
            pending=""
        fi

        case "$component" in
            ""|.) continue ;;
            ..)
                if [[ "$resolved" != "/" ]]; then
                    resolved="${resolved%/*}"
                    [[ -n "$resolved" ]] || resolved="/"
                fi
                continue
                ;;
        esac

        if [[ "$resolved" == "/" ]]; then
            probe="/$component"
        else
            probe="$resolved/$component"
        fi

        for name in "${MANAGED_DIRS[@]}"; do
            lexical_root=$(realpath --canonicalize-missing --no-symlinks -- "$CONFIG_HOME/$name")
            canonical_root=$(realpath --canonicalize-missing -- "$CONFIG_HOME/$name")
            # If CONFIG_HOME is itself a symlink, this is the physical path of
            # the managed entry without following that entry's final symlink.
            managed_entry=$(realpath --canonicalize-missing --no-symlinks -- "$canonical_config_home/$name")
            if path_is_within "$probe" "$lexical_root" \
                || path_is_within "$probe" "$managed_entry"; then
                fatal_preserved_symlink_dependency "$src" "$link_target" "$name"
            fi
            # Replacing a managed-root symlink removes only the alias, not its
            # external target tree. Traversal through the alias was caught by
            # managed_entry above; a direct path to that external tree is safe.
            if [[ ! -L "$CONFIG_HOME/$name" ]] \
                && path_is_within "$probe" "$canonical_root"; then
                fatal_preserved_symlink_dependency "$src" "$link_target" "$name"
            fi
        done

        if [[ -L "$probe" ]]; then
            symlink_hops=$((symlink_hops + 1))
            (( symlink_hops <= 64 )) \
                || fatal "Could not safely resolve preserved symlink target after 64 symlink hops: $src"
            hop_target=$(readlink -- "$probe") \
                || fatal "Could not inspect preserved symlink dependency: $probe"
            if [[ "$hop_target" == /* ]]; then
                resolved="/"
                hop_target="${hop_target#/}"
            fi
            if [[ -n "$pending" ]]; then
                pending="$hop_target/$pending"
            else
                pending="$hop_target"
            fi
        else
            resolved="$probe"
        fi
    done
}

assert_preserved_symlink_survives_deploy() {
    local src="$1"
    local link_target lexical_destination canonical_target name
    local lexical_root canonical_root

    link_target=$(readlink -- "$src") || fatal "Could not read preserved symlink target: $src"
    if [[ "$link_target" == /* ]]; then
        lexical_destination="$link_target"
    else
        lexical_destination="$(dirname -- "$src")/$link_target"
    fi

    # Check both the written path and its resolved target: either can depend on
    # a managed directory even when the other points outside one.
    lexical_destination=$(realpath --canonicalize-missing --no-symlinks -- "$lexical_destination")
    canonical_target=$(realpath --canonicalize-existing -- "$src")
    for name in "${MANAGED_DIRS[@]}"; do
        lexical_root=$(realpath --canonicalize-missing --no-symlinks -- "$CONFIG_HOME/$name")
        canonical_root=$(realpath --canonicalize-missing -- "$CONFIG_HOME/$name")
        if path_is_within "$lexical_destination" "$lexical_root"; then
            fatal_preserved_symlink_dependency "$src" "$link_target" "$name"
        fi
        if [[ ! -L "$CONFIG_HOME/$name" ]] \
            && path_is_within "$canonical_target" "$canonical_root"; then
            fatal_preserved_symlink_dependency "$src" "$link_target" "$name"
        fi
    done
    assert_relative_symlink_parent_is_stable "$src" "$link_target"
    assert_symlink_resolution_avoids_managed_dirs "$src" "$link_target"
}

# Stash all files listed in PRESERVED_FILES to a temp dir BEFORE deploy_configs
# wipes the managed dirs. They will be restored AFTER the copy.
stash_preserved_files() {
    PRESERVED_STASH=$(mktemp -d)
    local count=0 rel
    for rel in "${PRESERVED_FILES[@]}"; do
        local src="$CONFIG_HOME/$rel"
        local stash="$PRESERVED_STASH/$rel"

        # Test symlinks lexically before testing their target. A relative link
        # copied into the private stash is normally dangling there, but `cp -a`
        # still preserves the exact link text for restoration. Reject links
        # that are already dangling, or resolve to anything except a regular
        # file, before deploy_configs replaces any managed directory.
        if [[ -L "$src" ]]; then
            [[ -f "$src" ]] || fatal "Preserved path is a dangling symlink or does not resolve to a regular file: $src"
            assert_preserved_symlink_survives_deploy "$src"
        elif [[ ! -e "$src" ]]; then
            continue
        elif [[ ! -f "$src" ]]; then
            fatal "Preserved path is not a regular file: $src"
        fi

        mkdir -p "$(dirname "$stash")"
        cp -a -- "$src" "$stash"
        count=$((count + 1))
    done
    if (( count > 0 )); then
        ok "Preserved $count user file(s) for restoration after install."
    fi
}

# Restore preserved files (overwrites whatever the repo copy put in their place).
restore_preserved_files() {
    [[ -z "$PRESERVED_STASH" || ! -d "$PRESERVED_STASH" ]] && return 0
    local rel
    for rel in "${PRESERVED_FILES[@]}"; do
        local stash="$PRESERVED_STASH/$rel"
        local dest="$CONFIG_HOME/$rel"
        # A stashed relative symlink can be dangling until it returns to its
        # original directory, so recognize the link object with -L. Remove the
        # freshly installed template first to avoid destination-dependent cp
        # behavior and then restore the preserved entry verbatim.
        if [[ -L "$stash" || -f "$stash" ]]; then
            mkdir -p "$(dirname "$dest")"
            rm -f -- "$dest"
            cp -a -- "$stash" "$dest"
            ok "Restored user file: $rel"
        fi
    done
}

# ─── Deploy configs ─────────────────────────────────────────────────
deploy_configs() {
    mkdir -p "$CONFIG_HOME"

    # 1. Stash files that must survive the install.
    stash_preserved_files

    # 2. Backup or remove existing managed dirs, then copy fresh from repo.
    for name in "${MANAGED_DIRS[@]}"; do
        local src="$CLONE_DIR/config/$name"
        local dest="$CONFIG_HOME/$name"
        [[ -d "$src" ]] || { warn "Skipping $name (not in repo)."; continue; }

        if [[ -e "$dest" ]]; then
            if $BACKUP_OLD; then
                mkdir -p "$BACKUP_DIR"
                log "Backing up $dest → $BACKUP_DIR/$name"
                mv "$dest" "$BACKUP_DIR/$name"
            else
                warn "Removing existing $dest (no backup)."
                rm -rf "$dest"
            fi
        fi
        log "Installing config: $name"
        cp -r "$src" "$dest"
    done

    # 3. Restore preserved user files (overwrites any template the repo provided).
    restore_preserved_files

    # 4. Make all .sh / .py executable.
    log "Setting executable bits on scripts…"
    find "$CONFIG_HOME/hypr" "$CONFIG_HOME/quickshell" "$CONFIG_HOME/waybar" \
        -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + 2>/dev/null || true

    # 5. Create the Lua user override file if it still doesn't exist
    #    (first-time install, nothing to restore).
    local user_lua="$CONFIG_HOME/hypr/user.lua"
    if [[ ! -f "$user_lua" ]]; then
        cat > "$user_lua" <<'EOF'
-- Personal Hyprland Lua overrides.
--
-- The installer preserves this file across upgrades. It loads after the
-- Tsugumori defaults, so later hl.config calls override matching base values.
-- Replace an existing bind with hl.unbind("KEYS") followed by hl.bind(...).
--
-- Examples:
-- hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })
-- hl.config({ input = { kb_layout = "us" } })
-- hl.bind("SUPER + B", hl.dsp.exec_cmd("firefox"))
EOF
        ok "Created user.lua for personal Hyprland overrides."
    else
        ok "Hyprland user.lua is ready; an existing file was preserved when present."
    fi

    if [[ -f "$CONFIG_HOME/hypr/user.conf" ]]; then
        warn "Preserved legacy hypr/user.conf; native Lua does not load it."
    fi
}

install_lock_background() {
    local bundled="$CLONE_DIR/assets/wallpapers/Aleph1.png"
    local output="$CONFIG_HOME/hypr/lockbg.png"

    log "Installing the bundled Tsugumori wallpaper for Hyprlock…"
    if [[ -s "$bundled" ]] && install -m 644 "$bundled" "$output"; then
        ok "Installed Hyprlock background: $output"
        return 0
    fi

    warn "Aleph1.png is unavailable; Hyprlock will use its configured solid-color fallback."
}

warn_legacy_pam() {
    if [[ -e /etc/pam.d/qs-lock ]]; then
        warn "Legacy /etc/pam.d/qs-lock remains from an older Tsugumori install. It is no longer used; review and remove it manually after confirming no local service depends on it."
    fi
}

# Render the installer-owned options module atomically, without ever modifying
# preserved user.lua. Re-rendering false values also removes stale --vm state.
write_tsugumori_options() {
    local target="$1"
    local report_changes="${2:-true}"
    local vm_software_gl=false boot_wallpaper=false target_dir tmp

    $VM_GL_TWEAKS && vm_software_gl=true
    $BOOT_WALLPAPER_VM && boot_wallpaper=true

    target_dir=$(dirname -- "$target")
    mkdir -p "$target_dir"
    tmp=$(mktemp "$target_dir/.tsugumori_options.lua.XXXXXX")
    {
        printf '%s\n' '-- Managed by the Tsugumori installer. Personal settings belong in user.lua.'
        printf '%s\n' 'return {'
        printf '    vm_software_gl = %s,\n' "$vm_software_gl"
        printf '    boot_wallpaper = %s,\n' "$boot_wallpaper"
        printf '%s\n' '}'
    } >"$tmp"
    chmod 644 "$tmp"
    mv -f "$tmp" "$target"

    if [[ "$report_changes" == "true" ]]; then
        ok "Prepared installer options: vm_software_gl=$vm_software_gl, boot_wallpaper=$boot_wallpaper."
    fi
}

# ─── Shell config (.bashrc with welcome banner) ────────────────────
deploy_shell_config() {
    $INSTALL_BASHRC || { warn "Skipping .bashrc installation."; return; }

    local bashrc_src="$CLONE_DIR/config/bash/.bashrc"
    local bashrc_dest="$HOME/.bashrc"

    [[ -f "$bashrc_src" ]] || { warn "No bundled .bashrc found in repo."; return; }

    # Backup existing .bashrc if it's not already a Tsugumori one
    if [[ -f "$bashrc_dest" ]] && ! grep -q "Tsugumori default .bashrc" "$bashrc_dest"; then
        if $BACKUP_OLD; then
            mkdir -p "$BACKUP_DIR"
            cp "$bashrc_dest" "$BACKUP_DIR/.bashrc"
            log "Backed up existing ~/.bashrc"
        fi
    fi

    log "Installing Tsugumori .bashrc (welcome banner enabled)…"
    cp "$bashrc_src" "$bashrc_dest"

    # Create empty user override if missing
    if [[ ! -f "$HOME/.bashrc.local" ]]; then
        cat > "$HOME/.bashrc.local" <<'OVR'
# Tsugumori user overrides — never touched by updates.
# Put your personal aliases, functions, exports here.
#
# Examples:
#   alias ll='ls -la'
#   export EDITOR=nano
#   export PATH="$PATH:$HOME/.local/bin"
OVR
        ok "Created empty ~/.bashrc.local for your personal overrides."
    fi

    ok "Bashrc installed."
}

# ─── Wallpapers & Pictures dir ─────────────────────────────────────
setup_user_dirs() {
    mkdir -p "$HOME/Pictures/wallpapers" "$HOME/Screenshots"
    if $INSTALL_WALLPAPERS && [[ -d "$CLONE_DIR/assets/wallpapers" ]]; then
        log "Installing default wallpapers…"
        cp -n "$CLONE_DIR/assets/wallpapers/"* "$HOME/Pictures/wallpapers/" 2>/dev/null || true
    fi
}

# ─── Services ──────────────────────────────────────────────────────
enable_services() {
    $ENABLE_SERVICES || { warn "Skipping service activation."; return; }
    log "Enabling system services…"
    sudo systemctl enable --now NetworkManager.service 2>/dev/null || warn "NetworkManager: skipped."
    sudo systemctl enable --now bluetooth.service 2>/dev/null || warn "Bluetooth: skipped."
    log "Enabling user audio services…"
    systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || warn "pipewire: skipped (this is fine if you'll start it from the session)."
}


# ─── qshare CLI symlink ────────────────────────────────────────────
deploy_qshare_symlink() {
    local script="$CONFIG_HOME/quickshell/scripts/qshare.py"
    local link="$HOME/.local/bin/qshare"

    if [[ ! -f "$script" ]]; then
        warn "qshare.py not found in quickshell/scripts/, skipping symlink."
        return
    fi

    mkdir -p "$HOME/.local/bin"
    if [[ -L "$link" || -e "$link" ]]; then
        rm -f "$link"
    fi
    ln -s "$script" "$link"
    ok "Symlinked qshare CLI: $link → $script"

    # Check that ~/.local/bin is in PATH
    if ! echo "$PATH" | tr ':' '\n' | grep -qFx "$HOME/.local/bin"; then
        warn "~/.local/bin is not in your PATH."
        warn "Add this line to ~/.bashrc.local:"
        warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}


# ─── Final message ─────────────────────────────────────────────────
finalize() {
    echo
    ok "${C_BOLD}Installation complete!${C_RESET}"
    echo
    echo "  ${C_BOLD}Next steps:${C_RESET}"
    echo "    1. Reboot or log out, then log back into Hyprland."
    if $VM_GL_TWEAKS; then
        echo "    - VirtualBox/software-GL: from TTY login, prefer: exec start-hyprland"
        echo "      (bare Hyprland prints a warning; start-hyprland sets session properly)."
    fi
    echo "    2. Customise via ~/.config/hypr/user.lua — keep personal changes out of hyprland.lua."
    echo "    3. Bashrc personal overrides go in ~/.bashrc.local"
    echo "    4. Wallpapers go in ~/Pictures/wallpapers/ (use SUPER+P to pick one)."
    if $LEGACY_USER_CONF_ACTIVE; then
        echo
        echo "  ${C_BOLD}Legacy Hyprland override reminder:${C_RESET}"
        echo "    $CONFIG_HOME/hypr/user.conf was preserved but remains dormant under Lua."
        echo "    Your existing $CONFIG_HOME/hypr/user.lua remains active and was not rewritten."
        echo "    Translate any remaining settings into user.lua, then archive user.conf."
        if $BACKUP_OLD; then
            echo "    Backup copy: $BACKUP_DIR/hypr/user.conf"
        fi
    fi
    if [[ -d "$BACKUP_DIR" ]]; then
        echo
        echo "  ${C_BOLD}Backup of your old configs:${C_RESET}"
        echo "    $BACKUP_DIR"
    fi
    echo
    echo "  ${C_BOLD}Docs & support:${C_RESET}"
    echo "    https://github.com/Aleph1-9012/Tsugumori#readme"
    echo
}

main() {
    preflight
    collect_choices
    inspect_legacy_user_config
    install_base
    clone_repo
    install_packages
    validate_font_assets
    validate_wallpaper_runtime
    write_tsugumori_options "$CLONE_DIR/config/hypr/tsugumori_options.lua"
    validate_lock_runtime
    validate_hyprland_config
    deploy_configs
    install_font_assets
    install_lock_background
    warn_legacy_pam
    deploy_shell_config
    setup_user_dirs
    deploy_qshare_symlink
    enable_services
    finalize
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
