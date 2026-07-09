confirmInstallations() {
    stty sane
    if [[ -z "${manual_game_files}" ]]; then
        while true; do
            printf "\n${COLORS[YELLOW]}$(getMessage "manual_game_files") ${COLORS[RESET]}"
            read -r input
            input=$(echo "$input" | tr '[:upper:]' '[:lower:]')
            case "$input" in
                "" | "o" | "oui" | "y" | "yes")
                    manual_game_files=yes
                    break
                    ;;
                "n" | "non" | "no")
                    manual_game_files=no
                    break
                    ;;
                *)
                    echo "$(getMessage "invalid_input_yn")"
                    ;;
            esac
        done
    fi
    export manual_game_files

    local options=("firewall" "dotnet" "xlr_backups" "xlr_iw4madmin" "xlr_discord" "xlr_chat_commands" "xlr_mapvote")
    local descriptions=("firewall" "dotnet" "xlr_backups" "xlr_iw4madmin" "xlr_discord" "xlr_chat_commands" "xlr_mapvote")
    local variables=("firewall" "dotnet" "xlr_backups" "xlr_iw4madmin" "xlr_discord" "xlr_chat_commands" "xlr_mapvote")

    for i in "${!options[@]}"; do
        local option="${options[$i]}"
        local description="${descriptions[$i]}"
        local variable="${variables[$i]}"

        stty sane
        if [[ -z "${!variable}" ]]; then
            while true; do
                printf "\n${COLORS[YELLOW]}$(getMessage "$description") ${COLORS[RESET]}"
                read -r input

                input=$(echo "$input" | tr '[:upper:]' '[:lower:]')

                case "$input" in
                    "" | "o" | "oui" | "y" | "yes")
                        declare "$variable=yes"
                        break
                        ;;
                    "n" | "non" | "no")
                        declare "$variable=no"
                        break
                        ;;
                    *)
                        echo "$(getMessage "invalid_input_yn")"
                        ;;
                esac
            done
        fi
    done

    if [[ "$firewall" == "yes" ]]; then
        while true; do
            printf "\n${COLORS[YELLOW]}$(getMessage "ssh_port")${COLORS[RESET]}\n"
            printf "${COLORS[LIGHT_RED]}$(getMessage "ssh_port_enter")${COLORS[RESET]}\n"
            printf ">>> "
            read -r ssh_port_input
            
            if [[ -z "$ssh_port_input" ]]; then
                echo "$(getMessage "invalid_port")"
                continue
            fi

            if [[ "$ssh_port_input" =~ ^[1-9][0-9]{0,4}$ ]] && 
               [ "$ssh_port_input" -ge 1 ] && 
               [ "$ssh_port_input" -le 65535 ]; then
                ssh_port=$ssh_port_input
                break
            else
                echo "$(getMessage "invalid_port")"
            fi
        done
    fi
}