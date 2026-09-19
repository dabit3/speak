#!/bin/bash
set -euo pipefail

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
        printf 'Warning: temporary signing changes app identity on rebuild and can invalidate Accessibility approval.\n' >&2
    fi
    printf '%s\n' "$CODE_SIGN_IDENTITY"
    exit 0
fi

AVAILABLE="$(security find-identity -v -p codesigning)"
IDENTITIES=()
PATTERN='^[[:space:]]*[0-9]+\)[[:space:]]+([[:xdigit:]]{40})[[:space:]]+"Developer ID Application:'
while IFS= read -r LINE; do
    if [[ "$LINE" =~ $PATTERN ]]; then
        IDENTITIES+=("${BASH_REMATCH[1]}")
    fi
done <<< "$AVAILABLE"

case "${#IDENTITIES[@]}" in
    1) printf '%s\n' "${IDENTITIES[0]}" ;;
    0)
        printf 'No valid Developer ID Application certificate found. Install a signing certificate or set CODE_SIGN_IDENTITY.\nFor temporary local builds only, set CODE_SIGN_IDENTITY=-; permission approval can break after updates.\n' >&2
        exit 1
        ;;
    *)
        printf 'Multiple Developer ID Application certificates found. Set CODE_SIGN_IDENTITY to choose one consistently.\n' >&2
        exit 1
        ;;
esac
