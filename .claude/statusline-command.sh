#!/usr/bin/env bash
# Claude Code status line script
# ~/.claude/statusline-command.sh

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
total_tokens=$(echo "$input" | jq -r '.context_window.total_tokens // empty')
five_hour=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Build prompt segment: directory only (no user@host)
dir=$(basename "$cwd")

# Color codes
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
DIM='\033[2m'
RESET='\033[0m'
BAR_GREEN='\033[0;32m'
BAR_YELLOW='\033[0;33m'
BAR_RED='\033[0;31m'

# Draw a progress bar: draws a 10-char bar with color based on percentage
# Usage: progress_bar <percentage>
progress_bar() {
    local pct=$1
    local width=10
    local fill=$(printf "%.0f" "$(echo "$pct * $width / 100" | bc -l)")
    [ "$fill" -gt "$width" ] && fill=$width
    [ "$fill" -lt 0 ] && fill=0

    local empty=$((width - fill))
    local color=$BAR_GREEN
    if [ "$(printf "%.0f" "$pct")" -ge 80 ]; then
        color=$BAR_YELLOW
    fi
    if [ "$(printf "%.0f" "$pct")" -ge 90 ]; then
        color=$BAR_RED
    fi

    printf "["
    if [ "$fill" -gt 0 ]; then
        printf "${color}%*s${RESET}" "$fill" "" | tr ' ' '█'
    fi
    if [ "$empty" -gt 0 ]; then
        printf "%*s" "$empty" "" | tr ' ' '░'
    fi
    printf "]"
}

# directory only
printf "${CYAN}%s${RESET}" "$dir"

# model
if [ -n "$model" ]; then
    printf " ${DIM}[%s]${RESET}" "$model"
fi

# context usage + progress bar
if [ -n "$used_pct" ]; then
    printf " "
    progress_bar "$used_pct"
    printf " ${DIM}%.0f%%${RESET}" "$used_pct"
fi

# rate limits
rate=""
if [ -n "$five_hour" ]; then
    rate="5h:$(printf '%.0f' "$five_hour")%"
fi
if [ -n "$seven_day" ]; then
    [ -n "$rate" ] && rate="$rate "
    rate="${rate}7d:$(printf '%.0f' "$seven_day")%"
fi
if [ -n "$rate" ]; then
    printf " ${DIM}%s${RESET}" "$rate"
fi
