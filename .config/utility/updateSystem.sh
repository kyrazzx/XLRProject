updateSystem() {
    {
        if ! apt-get update --dry-run 2>&1 | grep -q "0 packages can be upgraded"; then
            apt-get update
        else
            sleep 2
        fi
    } > /dev/null 2>&1 &
    showProgressIndicator "$(getMessage "update")"
}
