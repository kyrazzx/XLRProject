getMessage() {
    local key="${1}_en"
    [[ $language -eq 1 ]] && key="${1}_fr"
    [[ $language -eq 2 ]] && key="${1}_sp"
    [[ $language -eq 3 ]] && key="${1}_cn"
    echo "${!key}"
}
