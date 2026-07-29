#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
bootstrap="$repository_root/Scripts/bootstrap_production.sh"
recovery_verifier="$repository_root/Scripts/verify_recovery_repository.sh"
age_verifier="$repository_root/Scripts/verify_pinned_age.sh"
settings_verifier="$repository_root/Scripts/verify_repository_settings.sh"
guide="$repository_root/docs/PRODUCTION_BOOTSTRAP.md"

test -f "$bootstrap"
test -f "$recovery_verifier"
test -f "$age_verifier"
test -f "$settings_verifier"
test -f "$guide"
bash -n "$bootstrap"
bash -n "$recovery_verifier"
bash -n "$age_verifier"

grep -Fq 'SoulmateL/ios-harden-signing-control' "$bootstrap"
grep -Fq 'SoulmateL/ios-harden-signing-requests' "$recovery_verifier"
grep -Fq 'skb-integrity-prod-2026-03' "$bootstrap"
grep -Fq '[[ -t 0 && -t 1 ]]' "$bootstrap"
grep -Fq -- '--requests-repo' "$bootstrap"
grep -Fq -- '--age' "$bootstrap"
grep -Fq '/usr/bin/openssl rand 32' "$bootstrap"
grep -Fq 'derive-public-key' "$bootstrap"
grep -Fq 'gh secret set IOS_HARDEN_ED25519_SEED_B64' "$bootstrap"
grep -Fq 'Config/production-policy.json' "$bootstrap"
grep -Fq 'PRODUCTION_READY --body false' "$bootstrap"
grep -Fq 'verify_recovery_repository.sh' "$bootstrap"
grep -Fq 'verify_pinned_age.sh' "$bootstrap"
grep -Fq -- '--encrypt' "$bootstrap"
grep -Fq -- '--passphrase' "$bootstrap"
grep -Fq -- '--decrypt' "$bootstrap"
grep -Fq 'cmp "$seed_base64_path" "$roundtrip_path"' "$bootstrap"
grep -Fq 'git -C "$recovery_repository" push origin main' "$bootstrap"
grep -Fq 'Scripts/verify_repository_settings.sh' "$bootstrap" || {
    echo "错误：bootstrap 必须在生成 seed 前检查 GitHub 仓库安全设置" >&2
    exit 1
}

settings_check_line="$(grep -n -F 'Scripts/verify_repository_settings.sh' "$bootstrap" | cut -d: -f1)"
seed_generation_line="$(grep -n -F '/usr/bin/openssl rand 32' "$bootstrap" | cut -d: -f1)"
[[ "$settings_check_line" -lt "$seed_generation_line" ]] || {
    echo "错误：bootstrap 必须在生成 seed 前检查 GitHub 仓库安全设置" >&2
    exit 1
}
grep -Fq 'repos/$control_repository/actions/permissions' "$settings_verifier" || {
    echo "错误：bootstrap 的仓库安全预检必须验证控制仓库 Actions 设置" >&2
    exit 1
}
grep -Fq '.sha_pinning_required == true' "$settings_verifier" || {
    echo "错误：bootstrap 的仓库安全预检必须要求 Action 固定 SHA" >&2
    exit 1
}
grep -Fq '.security_and_analysis.secret_scanning.status == "enabled"' "$settings_verifier" || {
    echo "错误：bootstrap 的仓库安全预检必须要求 Secret 扫描" >&2
    exit 1
}
grep -Fq '.security_and_analysis.secret_scanning_push_protection.status == "enabled"' "$settings_verifier" || {
    echo "错误：bootstrap 的仓库安全预检必须要求 push protection" >&2
    exit 1
}

grep -Fq 'git -C "$recovery_repository" pull --ff-only' "$recovery_verifier"
grep -Fq 'git -C "$recovery_repository" status --porcelain' "$recovery_verifier"
grep -Fq 'git -C "$recovery_repository" branch --show-current' "$recovery_verifier"
grep -Fq 'Recovery' "$recovery_verifier"
grep -Fq '[[ -L "$requested_repository" ]]' "$recovery_verifier"
grep -Fq '付费超额' "$guide"
grep -Fq '预算为 0' "$guide"
grep -Fq 'git add Config/production-policy.json' "$guide"
grep -Fq 'git push origin main' "$guide"
grep -Fq 'APPROVED_IOS_HARDEN_REVISION' "$guide"

recovery_push_line="$(
    grep -n -F 'git -C "$recovery_repository" push origin main' "$bootstrap" |
        cut -d: -f1
)"
secret_line="$(
    grep -n -F 'gh secret set IOS_HARDEN_ED25519_SEED_B64' "$bootstrap" |
        cut -d: -f1
)"
[[ "$recovery_push_line" -lt "$secret_line" ]] || {
    echo "错误：必须先推送加密恢复副本，再写入 GitHub Secret" >&2
    exit 1
}

if grep -Eq \
    'verify_encrypted_recovery_volume|diskutil|recovery-volume|AGE_PASSPHRASE|--password-file' \
    "$bootstrap"; then
    echo "错误：bootstrap 包含旧 U 盘流程或非交互密码传递" >&2
    exit 1
fi

if grep -Eq \
    'gh secret set IOS_HARDEN_ED25519_SEED_B64.*(--body|--app|--env)' \
    "$bootstrap"; then
    echo "错误：生产 seed 只能从 stdin 写入仓库 Secret" >&2
    exit 1
fi

echo "生产 bootstrap 契约检查通过；未生成生产 seed"
