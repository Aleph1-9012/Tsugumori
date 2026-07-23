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
"┌─[ TYPE-17: TSUGUMORI ]─────────────────────────────[ 谷-704 ]─┐"
"│ STATUS: READY   │   壱百満天原   │   HIGGS DRIVE: ONLINE     │"
"├─[ KABIZASHI ]--------------------------|==|------------------->│"
"│ >=====================================[  ]||==================>│"
"└─[ KILLS: 07 ]─────────────────[ KNIGHTS OF SIDONIA ]──────────┘"
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
