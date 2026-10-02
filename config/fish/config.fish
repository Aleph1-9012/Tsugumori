# ═══════════════════════════════════════════════════════════════════
# Tsugumori default Fish config
# Personal overrides go in ~/.config/fish/config.fish.local — never touched by updates.
# ═══════════════════════════════════════════════════════════════════

# Source system fish config if it exists
if test -f /etc/fish/config.fish
    source /etc/fish/config.fish
end

# Stop here if not running interactively
if not status is-interactive
    exit
end

# ─── Standard aliases ──────────────────────────────────────────────
alias ls 'ls --color=auto'
alias grep 'grep --color=auto'

# ─── User-specific overrides ───────────────────────────────────────
if test -f "$HOME/.config/fish/config.fish.local"
    source "$HOME/.config/fish/config.fish.local"
end

# Add user-local executables to PATH
if not contains "$HOME/.local/bin" $PATH
    set -gx PATH "$HOME/.local/bin" $PATH
end
