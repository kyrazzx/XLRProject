#!/bin/bash

if [ "$1" = "--install" ]; then
    source /opt/T6Server/.config/config.sh
fi

installXlrPython() {
    local workdir="${WORKDIR}"
    local xlr_dir="$workdir/Resources/xlr"
    local discord_dir="$workdir/Resources/discord"

    checkAndInstallCommand python3 python3
    mkdir -p "$xlr_dir" /etc/xlr

    if [ ! -d "$xlr_dir/venv" ]; then
        python3 -m venv "$xlr_dir/venv"
    fi

    "$xlr_dir/venv/bin/pip" install -q --upgrade pip
    "$xlr_dir/venv/bin/pip" install -q -r "$xlr_dir/requirements.txt"

    if [ ! -f /etc/xlr/secrets.env ]; then
        cat > /etc/xlr/secrets.env << 'EOF'
# XLR secrets — never commit this file
# DISCORD_TOKEN=your_bot_token_here
# DISCORD_WEBHOOK=https://discord.com/api/webhooks/...
EOF
        chmod 600 /etc/xlr/secrets.env
    fi

    mkdir -p "$workdir/Plutonium/storage/xlr"
    chmod +x "$xlr_dir/"*.py 2>/dev/null || true

    if [ ! -L "$discord_dir/venv" ] && [ -d "$xlr_dir/venv" ]; then
        rm -rf "$discord_dir/venv" 2>/dev/null || true
        ln -sfn "$xlr_dir/venv" "$discord_dir/venv"
    fi
}

if [ "$1" = "--import" ]; then
    :
elif [ "$1" = "--install" ]; then
    installXlrPython
else
    echo "Usage: $0 [--install] | [--import]"
fi
