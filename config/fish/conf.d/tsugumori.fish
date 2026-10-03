# Managed by the Tsugumori installer.
# Existing config.fish loads afterward and can override these defaults.

if not status is-interactive
    return
end

alias ls 'ls --color=auto'
alias grep 'grep --color=auto'

if not contains -- "$HOME/.local/bin" $PATH
    set -gx PATH "$HOME/.local/bin" $PATH
end

if test -f "$__fish_config_dir/config.fish.local"
    source "$__fish_config_dir/config.fish.local"
end
