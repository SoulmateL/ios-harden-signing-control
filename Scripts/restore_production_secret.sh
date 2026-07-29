#!/bin/bash
set -euo pipefail
set +x
ulimit -c 0

[[ -t 0 && -t 1 ]] || {
    echo "错误：生产 Secret 恢复必须由所有者在交互终端现场执行" >&2
    exit 2
}
[[ $# -eq 6 &&
    "$1" == "--requests-repo" &&
    "$3" == "--signer" &&
    "$5" == "--age" ]] || {
    echo "用法：restore_production_secret.sh --requests-repo /绝对路径/ios-harden-signing-requests --signer /绝对路径/ios-harden-actions-signer --age /绝对路径/age" >&2
    exit 2
}

requested_recovery_repository="$2"
signer_path="$4"
requested_age_path="$6"
key_id="skb-integrity-prod-2026-03"
expected_repository="SoulmateL/ios-harden-signing-control"

[[ "$signer_path" == /* && "$signer_path" != */ &&
    "$signer_path" != *'/./'* && "$signer_path" != *'/../'* &&
    -f "$signer_path" && -x "$signer_path" && ! -L "$signer_path" ]] || {
    echo "错误：signer 必须是无点组件的绝对可执行普通文件" >&2
    exit 2
}
signer_path="$(realpath "$signer_path")"

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repository_root"
actual_repository="$(
    gh repo view --json nameWithOwner --jq '.nameWithOwner'
)"
[[ "$actual_repository" == "$expected_repository" ]] || {
    echo "错误：只能为 $expected_repository 恢复生产 Secret" >&2
    exit 2
}
Scripts/verify_repository_settings.sh

age_path="$(
    Scripts/verify_pinned_age.sh --age "$requested_age_path"
)"
recovery_repository="$(
    Scripts/verify_recovery_repository.sh \
        --repository "$requested_recovery_repository"
)"
recovery_path="$recovery_repository/Recovery/$key_id.age"
[[ -f "$recovery_path" && ! -L "$recovery_path" ]] || {
    echo "错误：找不到固定 Key ID 的加密恢复副本" >&2
    exit 2
}
[[ "$(realpath "$recovery_path")" == "$recovery_path" ]] || {
    echo "错误：恢复副本路径不得经过符号链接" >&2
    exit 2
}
[[ "$(head -c 21 "$recovery_path")" == "age-encryption.org/v1" ]] || {
    echo "错误：恢复副本不是 age 加密文件" >&2
    exit 2
}
[[ "$(stat -f '%z' "$recovery_path")" -le 1048576 ]] || {
    echo "错误：恢复副本异常过大" >&2
    exit 2
}

printf '将从加密恢复副本还原 %s。\n' "$key_id"
printf '输入完整 Key ID 以继续：'
IFS= read -r confirmation
[[ "$confirmation" == "$key_id" ]] || {
    echo "错误：确认内容不匹配" >&2
    exit 2
}

temporary_directory="$(
    mktemp -d "${TMPDIR:-/tmp}/ios-harden-restore.XXXXXX"
)"
chmod 700 "$temporary_directory"
seed_base64_path="$temporary_directory/recovered.b64"
public_receipt_path="$temporary_directory/public-key.json"
cleanup() {
    exit_status=$?
    for temporary_file in "$seed_base64_path" "$public_receipt_path"; do
        if [[ -e "$temporary_file" ]]; then
            /bin/rm "$temporary_file"
        fi
    done
    /bin/rmdir "$temporary_directory" 2>/dev/null || true
    exit "$exit_status"
}
trap cleanup EXIT
umask 077

"$age_path" \
    --decrypt \
    --output "$seed_base64_path" \
    "$recovery_path"
chmod 600 "$seed_base64_path"
"$signer_path" \
    derive-public-key \
    --private-key-stdin \
    --format json \
    < "$seed_base64_path" > "$public_receipt_path"

public_key_sha256="$(jq -r '.public_key_sha256' "$public_receipt_path")"
[[ "$public_key_sha256" =~ ^[0-9a-f]{64}$ ]] || {
    echo "错误：无法派生恢复 seed 的公钥指纹" >&2
    exit 2
}

expected_public_key_sha256=""
if [[ -e Config/production-policy.json ]]; then
    [[ -f Config/production-policy.json && ! -L Config/production-policy.json ]] || {
        echo "错误：生产策略必须是普通文件" >&2
        exit 2
    }
    [[ "$(jq -r '.key_id' Config/production-policy.json)" == "$key_id" ]] || {
        echo "错误：生产策略 Key ID 不匹配" >&2
        exit 2
    }
    expected_public_key_sha256="$(
        jq -r '.public_key_sha256' Config/production-policy.json
    )"
fi
if [[ -e Evidence/production-bootstrap/public-receipt.json ]]; then
    [[ -f Evidence/production-bootstrap/public-receipt.json &&
        ! -L Evidence/production-bootstrap/public-receipt.json ]] || {
        echo "错误：生产公开收据必须是普通文件" >&2
        exit 2
    }
    receipt_key_id="$(
        jq -r '.key_id' Evidence/production-bootstrap/public-receipt.json
    )"
    receipt_public_key_sha256="$(
        jq -r '.public_key_sha256' \
            Evidence/production-bootstrap/public-receipt.json
    )"
    [[ "$receipt_key_id" == "$key_id" ]] || {
        echo "错误：生产公开收据 Key ID 不匹配" >&2
        exit 2
    }
    if [[ -n "$expected_public_key_sha256" &&
        "$receipt_public_key_sha256" != "$expected_public_key_sha256" ]]; then
        echo "错误：生产策略与公开收据的公钥指纹不一致" >&2
        exit 2
    fi
    expected_public_key_sha256="$receipt_public_key_sha256"
fi
if [[ -n "$expected_public_key_sha256" ]]; then
    [[ "$expected_public_key_sha256" =~ ^[0-9a-f]{64}$ &&
        "$public_key_sha256" == "$expected_public_key_sha256" ]] || {
        echo "错误：恢复 seed 与公开公钥指纹不匹配" >&2
        exit 2
    }
else
    echo "警告：尚无公开生产策略；恢复后仍须完成 bootstrap 公开配置。" >&2
fi

gh variable set PRODUCTION_READY \
    --body false \
    --repo "$expected_repository"
gh secret set IOS_HARDEN_ED25519_SEED_B64 \
    --repo "$expected_repository" \
    < "$seed_base64_path"

echo "生产 Secret 已恢复，但生产签名仍保持禁用。"
echo "Key ID: $key_id"
echo "Public key SHA-256: $public_key_sha256"
echo "不要设置 PRODUCTION_READY=true，直到 App 公钥轮换和演练全部完成。"
