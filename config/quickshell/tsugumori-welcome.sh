#!/bin/bash
# R2-A Shōi header. Native terminal text only; no output in pipes or logs.
[[ -t 1 && ${TERM-} != dumb ]] || exit 0

ink=$'\033[38;2;232;232;232m'
accent=$'\033[38;2;204;21;21m'
muted=$'\033[38;2;146;144;141m'
rule=$'\033[38;2;55;51;49m'
badge=$'\033[38;2;10;10;10;48;2;204;21;21m'
glyph_regular=$'\033[38;2;101;98;93m'
glyph_bright=$'\033[38;2;152;149;143m'
glyph_quiet=$'\033[38;2;55;54;52m'
glyph_bright_quiet=$'\033[38;2;81;79;77m'
reset=$'\033[0m'

# Read the terminal size without sending queries or consuming keyboard input.
terminal_columns=80
if [[ ${COLUMNS-} =~ ^[1-9][0-9]{0,4}$ ]]; then
    terminal_columns=$COLUMNS
fi
terminal_size=$(stty size 2>/dev/null) || terminal_size=''
if [[ $terminal_size =~ ^[0-9]+[[:space:]]+([1-9][0-9]{0,4})$ ]]; then
    terminal_columns=${BASH_REMATCH[1]}
fi
panel_width=$((terminal_columns - 2))
(( panel_width > 86 )) && panel_width=86
(( panel_width < 1 )) && panel_width=1

# Kitty 0.40+ can size the title while retaining normal scrollback text.
# https://sw.kovidgoyal.net/kitty/text-sizing-protocol/
# Its three-row block is reserved below; no terminal capability queries needed.
title='四騎掌位'
if [[ ${TERM-} == xterm-kitty && -n ${KITTY_WINDOW_ID-}
    && -z ${TMUX-} && -z ${STY-} && -z ${ZELLIJ-} ]]; then
    title=$'\033]66;s=3:w=7:n=5:d=6:v=1;四騎掌位\033\\'
fi

# Exact glyph rows and fourth-band trace from the selected R2-A design.
# These are decorative unit markings, not system-status indicators.
glyph_rows=(
    '┌╱·┐│┤╲·├─┬╱│·└┘'
    '│┬╲╱·┼─┤┌·│┘╲┴·┐'
    '┴│┌·╱┐├┘─╲·┤┬└│╱'
    '╲┤·─┌│┬╱┘├┐·│┴╲┼'
    '┌│╱┬·╲┴┤─┼│└╱┬│┐'
    '┼·┐│├╱─┬╲└┤│─┼╲│'
    '│╲┴┌·┤│┘╱─├┬┬│└╱'
    '└┬│╱┤·┌─│╲┴┘│╱─┘'
)
trace_columns=(12 13 13 14 13 13 13 14)
trace_glyphs=('┌─' '│' '└┐' '│' '┌┘' '│' '└┐' '└─')
glyph_step=2
glyph_band_gap=1
if (( panel_width < 38 )); then
    glyph_step=1
    glyph_band_gap=2
fi
glyph_width=$((15 * glyph_step + 3 * glyph_band_gap + 1))
welcome_output=$'\r\n'

# Horizontal addressing keeps double-width Japanese text out of the matrix.
# Only append new lines: never clear existing output or reposition vertically.
put() {
    local fragment
    printf -v fragment '\033[%dG%s%s%s' "$1" "$2" "$3" "$reset"
    welcome_output+=$fragment
}

new_line() {
    welcome_output+="$reset"$'\r\n'
}

horizontal_rule() {
    local line
    printf -v line '%*s' "$3" ''
    put "$1" "$2" "${line// /─}"
}

glyph_row() {
    local row=$1 left=$2 column position character color trace offset
    trace=${trace_glyphs[row]}
    for ((column = 0; column < 16; column++)); do
        character=${glyph_rows[row]:column:1}
        offset=$((column - trace_columns[row]))
        if (( offset >= 0 && offset < ${#trace} )); then
            character=${trace:offset:1}
            color=$accent
        elif (( (row * 3 + column * 5) % 11 < 3 )); then
            color=$glyph_bright
            (( (row + column * 2) % 7 == 0 )) && color=$glyph_bright_quiet
        else
            color=$glyph_regular
            (( (row + column * 2) % 7 == 0 )) && color=$glyph_quiet
        fi
        position=$((left + column * glyph_step + column / 4 * glyph_band_gap))
        put "$position" "$color" "$character"
    done
}

unit_strip() {
    local part=$1 unit start end color marker label
    for ((unit = 0; unit < 4; unit++)); do
        start=$((3 + unit * (panel_width - 4) / 4))
        end=$((3 + (unit + 1) * (panel_width - 4) / 4 - 2))
        (( unit == 3 )) && end=$((panel_width - 2))
        if [[ $part == rules ]]; then
            color=$rule
            (( unit == 3 )) && color=$accent
            horizontal_rule "$start" "$color" "$((end - start + 1))"
        else
            color=$muted marker='◇'
            (( unit == 3 )) && { color=$accent; marker='◆'; }
            printf -v label '%02d' "$((unit + 1))"
            put "$start" "$color" "$label"
            put "$end" "$color" "$marker"
        fi
    done
}

ship_band() {
    local width=60 right badge_left rule_left=1
    (( terminal_columns <= 60 )) && width=$((terminal_columns - 1))
    (( width < 12 )) && return 0
    right=$width
    if (( width >= 36 )); then
        right=$((width - 2))
        put 3 "$accent" '╴'
        # Seven Japanese characters occupy fourteen terminal cells.
        put 5 "$ink" '播種船 シドニア'
        rule_left=21
    fi
    badge_left=$((right - 11))
    if (( badge_left > rule_left + 1 )); then
        horizontal_rule "$rule_left" "$rule" "$((badge_left - rule_left - 1))"
    fi
    put "$badge_left" "$badge" $' \033[1mSID0NIA\033[22m '
    put "$((right - 1))" "$accent" '//'
}

if (( panel_width >= 36 )); then
    matrix_first_row=3
    unit_rule_row=12
    last_row=14
    divider_column=$((panel_width / 2 - 1))
    matrix_left=$((divider_column + 3 + (panel_width - divider_column - 4 - glyph_width) / 2))
    stacked=0
    if (( panel_width < 74 )); then
        stacked=1
        matrix_first_row=14
        unit_rule_row=23
        last_row=25
        matrix_left=$(((panel_width - glyph_width) / 2 + 1))
    fi

    for ((row = 0; row <= last_row; row++)); do
        case $row in
            0)
                horizontal_rule 1 "$rule" "$panel_width"
                put 1 "$accent" '┌─'
                ;;
            1)
                put 1 "$accent" '│'
                put 3 "$ink" "TSUGUMORI ${accent}// ${muted}TYPE-17"
                put "$((panel_width - 8))" "$badge" $' ◆ \033[1m704\033[22m '
                ;;
            4) put 5 "$ink" "$title" ;;
            7) put 5 "$accent" 'SHŌI LINK' ;;
            10) put 5 "$muted" "東亜重工 ${accent}// ${muted}継衛" ;;
        esac

        if (( row >= 4 && row <= 10 )); then
            put 3 "$accent" '▌'
        fi
        if (( stacked == 0 && row >= 3 && row <= 10 )); then
            put "$divider_column" "$rule" '│'
        elif (( stacked == 1 && row == 12 )); then
            horizontal_rule 3 "$rule" "$((panel_width - 4))"
        fi
        if (( row >= matrix_first_row && row < matrix_first_row + 8 )); then
            glyph_row "$((row - matrix_first_row))" "$matrix_left"
        fi
        if (( row == unit_rule_row )); then
            unit_strip rules
        elif (( row == unit_rule_row + 1 )); then
            unit_strip labels
            put "$panel_width" "$accent" '│'
        elif (( row == last_row )); then
            horizontal_rule 1 "$rule" "$panel_width"
            put "$panel_width" "$accent" '┘'
        fi
        new_line
    done
else
    # Tiny splits keep the identity readable without wrapping a framed layout.
    put 1 "$ink" 'TSUGUMORI'
    if (( panel_width >= 20 )); then
        put 11 "$accent" "// ${muted}TYPE-17"
    fi
    new_line
    put 1 "$ink" '四騎掌位'
    (( panel_width >= 17 )) && put 10 "$badge" $' ◆ \033[1m704\033[22m '
    new_line
    put 1 "$accent" 'SHŌI LINK'
    new_line
    if (( panel_width >= glyph_width + 2 )); then
        new_line
        for ((row = 0; row < 8; row++)); do
            glyph_row "$row" 2
            new_line
        done
    fi
fi

ship_band
# PS1 adds another newline, leaving one blank row below the header.
new_line
printf '%s' "$welcome_output"
