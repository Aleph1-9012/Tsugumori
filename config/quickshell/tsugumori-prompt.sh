#!/bin/bash
# Source from .bashrc. Keep Bash and Kitty's existing command hooks intact.
if [[ $- != *i* || ! -t 1 || ${TERM-} == dumb ]]; then
    return 0 2>/dev/null || exit 0
fi

_tsugumori_prompt() {
    # Capture the command result before any formatting or Git commands run.
    local status=$? command_number='\#' columns=60 branch
    _tsugumori_prompt_status=$status
    printf -v _tsugumori_prompt_number '%03d' "${command_number@P}"

    if [[ ${COLUMNS-} =~ ^[1-9][0-9]*$ ]] && (( COLUMNS <= 60 )); then
        columns=$((COLUMNS - 1))
    fi
    (( columns < 1 )) && columns=1
    printf -v _tsugumori_prompt_rule '%*s' "$columns" ''
    _tsugumori_prompt_rule=${_tsugumori_prompt_rule// /─}

    _tsugumori_prompt_branch=''
    if command -v git >/dev/null 2>&1; then
        if branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null); then
            _tsugumori_prompt_branch=$branch
        elif branch=$(command git rev-parse --short HEAD 2>/dev/null); then
            _tsugumori_prompt_branch="detached:$branch"
        fi
    fi

    PS1='\n\[\e[38;2;55;51;49m\]${_tsugumori_prompt_rule}\[\e[0m\]\n'
    PS1+='\[\e[38;2;204;21;21m\]${_tsugumori_prompt_number}//\[\e[0m\] '
    PS1+='\[\e[38;2;232;232;232m\]\w\[\e[0m\]'
    if [[ -n $_tsugumori_prompt_branch ]]; then
        # Expand the value only when Bash renders PS1, never as prompt code.
        PS1+=' \[\e[38;2;204;21;21m\]// \[\e[38;2;146;144;141m\]${_tsugumori_prompt_branch}\[\e[0m\]'
    fi
    if (( status != 0 )); then
        PS1+=' \[\e[38;2;204;21;21m\]exit ${_tsugumori_prompt_status}\[\e[0m\]'
    fi
    PS1+='\n     \[\e[38;2;204;21;21m\]›\[\e[0m\] '

    return "$status"
}

_tsugumori_install_prompt() {
    local hook
    local -a retained_hooks=()
    for hook in "${PROMPT_COMMAND[@]}"; do
        case "$hook" in
            _tsugumori_prompt|_nier_prompt_cmd|'') continue ;;
            '_nier_prompt_cmd;'*) hook=${hook#'_nier_prompt_cmd;'} ;;
        esac
        retained_hooks+=("$hook")
    done
    PROMPT_COMMAND=(_tsugumori_prompt "${retained_hooks[@]}")
}

_tsugumori_install_prompt
unset -f _tsugumori_install_prompt _nier_prompt_cmd
