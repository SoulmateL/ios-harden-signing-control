#!/bin/bash
set -euo pipefail
set +x
ulimit -c 0

[[ -t 0 && -t 1 ]] || {
    echo "错误：生产 bootstrap 必须由所有者在交互终端现场执行" >&2
    exit 2
}
[[ $# -eq 8 &&
    "$1" == "--requests-repo" &&
    "$3" == "--bundle-identifier" &&
    "$5" == "--signer" &&
    "$7" == "--age" ]] || {
    echo "用法：bootstrap_production.sh --requests-repo /绝对路径/ios-harden-signing-requests --bundle-identifier com.example.App --signer /绝对路径/ios-harden-actions-signer --age /绝对路径/age" >&2
    exit 2
}

requested_recovery_repository="$2"
bundle_identifier="$4"
signer_path="$6"
requested_age_path="$8"
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
age_path="$(
    Scripts/verify_pinned_age.sh --age "$requested_age_path"
)"
actual_repository="$(
    gh repo view --json nameWithOwner --jq '.nameWithOwner'
)"
[[ "$actual_repository" == "$expected_repository" ]] || {
    echo "错误：只能为 $expected_repository 执行生产 bootstrap" >&2
    exit 2
}
Scripts/verify_repository_settings.sh
[[ ! -e Config/production-policy.json ]] || {
    echo "错误：生产策略已存在，拒绝覆盖或重复生成密钥" >&2
    exit 2
}

recovery_repository="$(
    Scripts/verify_recovery_repository.sh \
        --repository "$requested_recovery_repository"
)"
recovery_relative_path="Recovery/$key_id.age"
recovery_path="$recovery_repository/$recovery_relative_path"
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
encrypted_temporary_path="$temporary_directory/$key_id.age"
roundtrip_path="$temporary_directory/roundtrip.b64"
cleanup() {
    exit_status=$?
    for temporary_file in \
        "$seed_raw_path" \
        "$seed_base64_path" \
        "$public_receipt_path" \
        "$policy_temporary_path" \
        "$receipt_temporary_path" \
        "$encrypted_temporary_path" \
        "$roundtrip_path"; do
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

"$age_path" \
    --encrypt \
    --passphrase \
    --output "$encrypted_temporary_path" \
    "$seed_base64_path"
chmod 600 "$encrypted_temporary_path"
"$age_path" \
    --decrypt \
    --output "$roundtrip_path" \
    "$encrypted_temporary_path"
chmod 600 "$roundtrip_path"
cmp "$seed_base64_path" "$roundtrip_path"

(
    set -o noclobber
    umask 077
    cat "$encrypted_temporary_path" > "$recovery_path"
)
chmod 600 "$recovery_path"
git -C "$recovery_repository" add "$recovery_relative_path"
git -C "$recovery_repository" commit \
    -m "recovery: add encrypted production copy"
git -C "$recovery_repository" push origin main

gh secret set IOS_HARDEN_ED25519_SEED_B64 \
    --repo "$expected_repository" \
    < "$seed_base64_path"

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
