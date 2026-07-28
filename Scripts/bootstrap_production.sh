#!/bin/bash
set -euo pipefail
set +x
ulimit -c 0

[[ -t 0 && -t 1 ]] || {
    echo "错误：生产 bootstrap 必须由所有者在交互终端现场执行" >&2
    exit 2
}
[[ $# -eq 6 &&
    "$1" == "--recovery-volume" &&
    "$3" == "--bundle-identifier" &&
    "$5" == "--signer" ]] || {
    echo "用法：bootstrap_production.sh --recovery-volume /Volumes/加密卷 --bundle-identifier com.example.App --signer /绝对路径/ios-harden-actions-signer" >&2
    exit 2
}

requested_volume="$2"
bundle_identifier="$4"
signer_path="$6"
key_id="skb-integrity-prod-2026-03"
expected_repository="SoulmateL/ios-harden-signing-control"

[[ "$bundle_identifier" =~ ^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$ ]] || {
    echo "错误：Bundle ID 格式无效" >&2
    exit 2
}
[[ "$signer_path" == /* && -x "$signer_path" ]] || {
    echo "错误：signer 必须是可执行文件的绝对路径" >&2
    exit 2
}
signer_path="$(realpath "$signer_path")"

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repository_root"
actual_repository="$(
    gh repo view --json nameWithOwner --jq '.nameWithOwner'
)"
[[ "$actual_repository" == "$expected_repository" ]] || {
    echo "错误：只能为 $expected_repository 执行生产 bootstrap" >&2
    exit 2
}
[[ ! -e Config/production-policy.json ]] || {
    echo "错误：生产策略已存在，拒绝覆盖或重复生成密钥" >&2
    exit 2
}

recovery_volume="$(
    Scripts/verify_encrypted_recovery_volume.sh --volume "$requested_volume"
)"
recovery_directory="$recovery_volume/ios-harden-signing-control-recovery"
recovery_path="$recovery_directory/$key_id.seed.b64"
[[ ! -e "$recovery_path" && ! -L "$recovery_path" ]] || {
    echo "错误：恢复副本已存在，拒绝覆盖" >&2
    exit 2
}

printf '将为 %s 生成全新生产 seed。\n' "$key_id"
printf '输入完整 Key ID 以继续：'
IFS= read -r confirmation
[[ "$confirmation" == "$key_id" ]] || {
    echo "错误：确认内容不匹配" >&2
    exit 2
}

gh variable set PRODUCTION_READY --body false --repo "$expected_repository"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/ios-harden-production.XXXXXX")"
chmod 700 "$temporary_directory"
seed_raw_path="$temporary_directory/seed.raw"
seed_base64_path="$temporary_directory/seed.b64"
public_receipt_path="$temporary_directory/public-key.json"
policy_temporary_path="$temporary_directory/production-policy.json"
receipt_temporary_path="$temporary_directory/public-receipt.json"
cleanup() {
    exit_status=$?
    for temporary_file in \
        "$seed_raw_path" \
        "$seed_base64_path" \
        "$public_receipt_path" \
        "$policy_temporary_path" \
        "$receipt_temporary_path"; do
        if [[ -e "$temporary_file" ]]; then
            /bin/rm "$temporary_file"
        fi
    done
    /bin/rmdir "$temporary_directory" 2>/dev/null || true
    exit "$exit_status"
}
trap cleanup EXIT
umask 077

/usr/bin/openssl rand 32 > "$seed_raw_path"
chmod 600 "$seed_raw_path"
/usr/bin/base64 < "$seed_raw_path" | tr -d '\n' > "$seed_base64_path"
chmod 600 "$seed_base64_path"
"$signer_path" \
    derive-public-key \
    --private-key-stdin \
    --format json \
    < "$seed_base64_path" > "$public_receipt_path"

public_key_base64="$(jq -r '.public_key_base64' "$public_receipt_path")"
public_key_sha256="$(jq -r '.public_key_sha256' "$public_receipt_path")"
[[ "$public_key_sha256" =~ ^[0-9a-f]{64}$ ]] || {
    echo "错误：无法派生公钥指纹" >&2
    exit 2
}

gh secret set IOS_HARDEN_ED25519_SEED_B64 \
    --repo "$expected_repository" \
    < "$seed_base64_path"

if [[ ! -d "$recovery_directory" ]]; then
    mkdir "$recovery_directory"
    chmod 700 "$recovery_directory"
fi
(
    set -o noclobber
    umask 077
    cat "$seed_base64_path" > "$recovery_path"
)
chmod 600 "$recovery_path"
sync "$recovery_path"

jq -n \
    --arg bundle_identifier "$bundle_identifier" \
    --arg key_id "$key_id" \
    --arg public_key_sha256 "$public_key_sha256" \
    '{
        allowed_bundle_identifiers: [$bundle_identifier],
        build_id_pattern: "^[0-9]+$",
        key_id: $key_id,
        max_future_skew_seconds: 120,
        max_request_age_seconds: 600,
        public_key_sha256: $public_key_sha256,
        schema_version: 1
    }' > "$policy_temporary_path"
chmod 644 "$policy_temporary_path"
mv "$policy_temporary_path" Config/production-policy.json

jq -n \
    --arg bundle_identifier "$bundle_identifier" \
    --arg key_id "$key_id" \
    --arg public_key_base64 "$public_key_base64" \
    --arg public_key_sha256 "$public_key_sha256" \
    --argjson created_at_epoch_seconds "$(date +%s)" \
    '{
        bundle_identifier: $bundle_identifier,
        created_at_epoch_seconds: $created_at_epoch_seconds,
        key_id: $key_id,
        public_key_base64: $public_key_base64,
        public_key_sha256: $public_key_sha256,
        schema_version: 1,
        production_ready: false
    }' > "$receipt_temporary_path"
chmod 644 "$receipt_temporary_path"
mkdir -p Evidence/production-bootstrap
mv "$receipt_temporary_path" \
    Evidence/production-bootstrap/public-receipt.json

echo "生产 seed 初始化完成，但生产签名仍保持禁用。"
echo "Key ID: $key_id"
echo "Public key (Base64): $public_key_base64"
echo "Public key SHA-256: $public_key_sha256"
echo "下一步必须先更新并验证 App 信任配置；不要设置 PRODUCTION_READY=true。"
