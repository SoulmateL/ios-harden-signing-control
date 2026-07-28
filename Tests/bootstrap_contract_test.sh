#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
bootstrap="$repository_root/Scripts/bootstrap_production.sh"
volume_verifier="$repository_root/Scripts/verify_encrypted_recovery_volume.sh"
guide="$repository_root/docs/PRODUCTION_BOOTSTRAP.md"

test -f "$bootstrap"
test -f "$volume_verifier"
test -f "$guide"
bash -n "$bootstrap"
bash -n "$volume_verifier"

grep -Fq 'SoulmateL/ios-harden-signing-control' "$bootstrap"
grep -Fq 'skb-integrity-prod-2026-03' "$bootstrap"
grep -Fq '[[ -t 0 && -t 1 ]]' "$bootstrap"
grep -Fq '/usr/bin/openssl rand 32' "$bootstrap"
grep -Fq 'derive-public-key' "$bootstrap"
grep -Fq 'gh secret set IOS_HARDEN_ED25519_SEED_B64' "$bootstrap"
grep -Fq 'Config/production-policy.json' "$bootstrap"
grep -Fq 'PRODUCTION_READY --body false' "$bootstrap"
grep -Fq 'verify_encrypted_recovery_volume.sh' "$bootstrap"

grep -Fq 'diskutil info -plist' "$volume_verifier"
grep -Fq 'plutil' "$volume_verifier"
grep -Fq 'RemovableMedia' "$volume_verifier"
grep -Fq 'FilesystemType' "$volume_verifier"
grep -Fq 'Encrypted' "$volume_verifier"

if grep -Eq \
    'gh secret set IOS_HARDEN_ED25519_SEED_B64.*(--body|--app|--env)' \
    "$bootstrap"; then
    echo "错误：生产 seed 只能从 stdin 写入仓库 Secret" >&2
    exit 1
fi

echo "生产 bootstrap 契约检查通过；未生成生产 seed"
