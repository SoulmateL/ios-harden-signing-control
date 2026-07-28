#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
wrapper="$repository_root/Scripts/run_signer_sandboxed.sh"

test -f "$wrapper"
grep -Fq '(deny default)' "$wrapper"
grep -Fq '(import "dyld-support.sb")' "$wrapper"
grep -Fq '(deny network*)' "$wrapper"
grep -Fq '(allow syscall*)' "$wrapper"
grep -Fq '(allow file-map-executable' "$wrapper"
grep -Fq 'ulimit -c 0' "$wrapper"
grep -Fq 'realpath "$SIGNER_PATH"' "$wrapper"
grep -Fq 'POLICY_PATH' "$wrapper"
grep -Fq 'REQUEST_PATH' "$wrapper"
grep -Fq 'RESPONSE_PATH' "$wrapper"
grep -Fq 'SIGNER_PATH' "$wrapper"
grep -Fq '/usr/bin/sandbox-exec' "$wrapper"
grep -Fq -- '--private-key-stdin' "$wrapper"

if grep -Eq -- '--private-key($|[ =])|PRIVATE_KEY_PATH|SEED_PATH' "$wrapper"; then
    echo "错误：包装器不得通过参数或文件传递 seed" >&2
    exit 1
fi

echo "Seatbelt 包装器契约检查通过"
