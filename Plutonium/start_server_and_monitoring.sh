#!/bin/bash
readonly XLR_LEGACY_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec "$XLR_LEGACY_DIR/XLRManager.sh" "$@"
