#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
restore_script="$repository_root/Scripts/restore_production_secret.sh"

test -f "$restore_script"
bash -n "$restore_script"

grep -Fq 'SoulmateL/ios-harden-signing-control' "$restore_script"
grep -Fq 'skb-integrity-prod-2026-03' "$restore_script"
grep -Fq '[[ -t 0 && -t 1 ]]' "$restore_script"
grep -Fq -- '--requests-repo' "$restore_script"
grep -Fq -- '--signer' "$restore_script"
grep -Fq -- '--age' "$restore_script"
grep -Fq 'verify_recovery_repository.sh' "$restore_script"
grep -Fq 'verify_pinned_age.sh' "$restore_script"
grep -Fq 'Scripts/verify_repository_settings.sh' "$restore_script"
grep -Fq -- '--decrypt' "$restore_script"
grep -Fq 'derive-public-key' "$restore_script"
grep -Fq 'public_key_sha256' "$restore_script"
grep -Fq 'gh variable set PRODUCTION_READY' "$restore_script"
grep -Fq -- '--body false' "$restore_script"
grep -Fq 'gh secret set IOS_HARDEN_ED25519_SEED_B64' "$restore_script"

ready_line="$(
    grep -n -F 'gh variable set PRODUCTION_READY' "$restore_script" |
        cut -d: -f1
)"
secret_line="$(
    grep -n -F 'gh secret set IOS_HARDEN_ED25519_SEED_B64' "$restore_script" |
        cut -d: -f1
)"
[[ "$ready_line" -lt "$secret_line" ]] || {
    echo "错误：恢复 Secret 前必须先关闭生产签名" >&2
    exit 1
}

if grep -Eq 'AGE_PASSPHRASE|--password-file|PRODUCTION_READY --body true' \
    "$restore_script"; then
    echo "错误：恢复脚本不得非交互接收密码或启用生产签名" >&2
    exit 1
fi
if grep -Eq \
    'gh secret set IOS_HARDEN_ED25519_SEED_B64.*(--body|--app|--env)' \
    "$restore_script"; then
    echo "错误：恢复 seed 只能通过标准输入写入 Secret" >&2
    exit 1
fi

echo "生产 Secret 恢复契约检查通过；未读取恢复副本"
