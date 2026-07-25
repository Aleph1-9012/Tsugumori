#!/bin/bash
INK='\033[38;2;70;63;46m'
ACC='\033[38;2;110;42;42m'
DIM='\033[38;2;50;45;36m'
RESET='\033[0m'

NOW=$(date "+%Y · %m · %d")
HOUR=$(date "+%H:%M:%S")
KERN=$(uname -r | cut -d'-' -f1)

echo ""
EMBLEM=(
"┌─[ SEED SHIP: SIDONIA ]──────────────────────[ CRUISE: 0.1c ]─┐"
"│                                                              │"
"│  ◄██████▓▓▒░  ==[ 播種船シドニア ]==  ░▒▓▓██████████████▓►   │"
"│                                                              │"
"└─[ POP: 500,000 ]────────[ HEADING: LEM-VII ]─────────────────┘"
)

for i in "${!EMBLEM[@]}"; do
    printf "${ACC}%s${RESET}\n" "${EMBLEM[$i]}"
done
echo ""
printf "${DIM}    ───────────────────────────────────────${RESET}\n"
printf "    ${DIM}node  ${RESET}${INK}${USER}@${HOSTNAME}${RESET}\n"
printf "    ${DIM}kern  ${RESET}${INK}${KERN}${RESET}\n"
printf "    ${DIM}time  ${RESET}${INK}${HOUR}  ${NOW}${RESET}\n"
printf "${DIM}    ───────────────────────────────────────${RESET}\n"
printf "    ${DIM}壱百満天原  ·  long live mankind${RESET}\n"
printf "${DIM}    ───────────────────────────────────────${RESET}\n"
echo ""
