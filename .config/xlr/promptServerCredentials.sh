#!/bin/bash

promptServerCredentials() {
  stty sane
  if [[ -z "${server_key:-}" ]]; then
    printf "\n${COLORS[YELLOW]}%s${COLORS[RESET]}\n" "$(getMessage "server_key")"
    printf ">>> "
    read -r server_key
  fi

  if [[ -z "${rcon_password:-}" ]]; then
    printf "\n${COLORS[YELLOW]}%s${COLORS[RESET]}\n" "$(getMessage "rcon_password")"
    printf ">>> "
    read -r rcon_password
    if [[ -z "$rcon_password" ]]; then
      rcon_password="$server_key"
    fi
  fi

  if [[ "${xlr_discord:-}" =~ ^[yYoO]$ ]] && [[ -z "${discord_token:-}" ]]; then
    printf "\n${COLORS[YELLOW]}%s${COLORS[RESET]}\n" "$(getMessage "discord_token")"
    printf ">>> "
    read -r discord_token
  fi

  export server_key rcon_password discord_token discord_webhook
  export xlr_backups xlr_iw4madmin xlr_discord dotnet firewall
}
