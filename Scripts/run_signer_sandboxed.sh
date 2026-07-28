#!/bin/bash
set -euo pipefail
set +x
ulimit -c 0

: "${POLICY_PATH:?错误：缺少 POLICY_PATH}"
: "${REQUEST_PATH:?错误：缺少 REQUEST_PATH}"
: "${RESPONSE_PATH:?错误：缺少 RESPONSE_PATH}"
: "${SIGNER_PATH:?错误：缺少 SIGNER_PATH}"

require_safe_absolute_path() {
    local value="$1"
    if [[ "$value" != /* || "$value" == */ || "$value" == *'//'*
        || "$value" == *'/./'* || "$value" == *'/../'*
        || "$value" == *'"'* || "$value" == *$'\n'* ]]; then
        echo "错误：沙箱路径必须是无点组件的安全绝对路径" >&2
        exit 2
    fi
}

require_safe_absolute_path "$POLICY_PATH"
require_safe_absolute_path "$REQUEST_PATH"
require_safe_absolute_path "$RESPONSE_PATH"
require_safe_absolute_path "$SIGNER_PATH"

SIGNER_PATH="$(realpath "$SIGNER_PATH")"
require_safe_absolute_path "$SIGNER_PATH"
test -x "$SIGNER_PATH" || {
    echo "错误：签名器不可执行" >&2
    exit 2
}

response_parent="$(dirname "$RESPONSE_PATH")"
profile_directory="$(mktemp -d "${TMPDIR:-/tmp}/ios-harden-seatbelt.XXXXXX")"
chmod 700 "$profile_directory"
profile_path="$profile_directory/profile.sb"
trap 'rm -rf "$profile_directory"' EXIT

cat > "$profile_path" <<EOF
(version 1)
(deny default)
(import "dyld-support.sb")
(deny network*)
(deny dynamic-code-generation)
(allow syscall*)
(allow process-exec (literal "$SIGNER_PATH"))
(allow process-info*)
(allow sysctl-read)
(allow mach-lookup)
(allow file-read* file-test-existence
    (literal "$SIGNER_PATH")
    (literal "$POLICY_PATH")
    (literal "$REQUEST_PATH")
    (subpath "/System/Library")
    (subpath "/usr/lib")
    (subpath "/private/var/db/dyld")
    (literal "/dev/random")
    (literal "/dev/urandom"))
(allow file-map-executable
    (literal "$SIGNER_PATH")
    (subpath "/System/Library")
    (subpath "/usr/lib"))
(allow file-read-data file-write-data
    (subpath "/dev/fd"))
(allow file-read-metadata (subpath "$response_parent"))
(allow file-write*
    (subpath "$response_parent")
    (literal "/dev/null"))
EOF
chmod 600 "$profile_path"

/usr/bin/sandbox-exec -f "$profile_path" \
    "$SIGNER_PATH" sign \
    --policy "$POLICY_PATH" \
    --request "$REQUEST_PATH" \
    --response "$RESPONSE_PATH" \
    --private-key-stdin
