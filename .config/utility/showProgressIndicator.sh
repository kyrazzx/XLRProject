showProgressIndicator() {
    local pid=$!
    local message="$1"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    local start_time=$(date +%s)

    if [[ -z "$TERM" ]]; then
        export TERM=xterm
    fi

    if command -v tput > /dev/null; then
        tput civis  # Hide cursor
    fi

    while kill -0 $pid 2>/dev/null; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        printf "\r [${spin:i++%${#spin}:1}] ${message} (${elapsed}s)"
        sleep 0.1
    done

    if command -v tput > /dev/null; then
        tput cnorm  # Show cursor
    fi

    printf "\r [${COLORS[GREEN]}✔${COLORS[RESET]}] ${message} (${elapsed}s)\n"
}
