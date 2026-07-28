#!/bin/bash
set -euo pipefail
set +x
ulimit -c 0

[[ $# -eq 2 && "$1" == "--requests-repo" ]] || {
    echo "用法：run_fixture_e2e.sh --requests-repo /路径/ios-harden-signing-requests" >&2
    exit 2
}

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
requests_repository="$(cd "$2" && pwd -P)"
[[ -d "$requests_repository/.git" ]] || {
    echo "错误：请求仓库路径无效" >&2
    exit 2
}
[[ ! -d "$requests_repository/.github/workflows" ]] || {
    echo "错误：请求仓库不得包含 Actions 工作流" >&2
    exit 2
}

cd "$repository_root"
swift build
signer="$repository_root/.build/debug/ios-harden-actions-signer"
fixture_seed="$repository_root/Fixtures/fixture-seed.b64"
fixture_policy="$repository_root/Config/fixture-policy.json"

run_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
[[ "$run_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
run_root="$repository_root/.build/fixture-e2e/$run_id"
mkdir -p "$run_root"
bare_repository="$run_root/transport.git"
working_repository="$run_root/requests-work"
verification_repository="$run_root/requests-verify"

git clone --bare "$requests_repository" "$bare_repository"
git clone "$bare_repository" "$working_repository"
git -C "$working_repository" config user.name "ios-harden-fixture"
git -C "$working_repository" config user.email "fixture@example.invalid"

current_epoch="$(date +%s)"
fixture_request="$run_root/request.json"
jq -cS \
    --argjson current_epoch "$current_epoch" \
    '.created_at_epoch_seconds = $current_epoch' \
    Fixtures/request.json |
    tr -d '\n' > "$fixture_request"
submission="$(
    IOS_HARDEN_SIGNER="$signer" \
        IOS_HARDEN_REVISION="1111111111111111111111111111111111111111" \
        "$working_repository/Scripts/submit_request.sh" \
        --request "$fixture_request" \
        --source-revision fixture-e2e
)"
request_id="$(awk -F= '$1 == "request_id" { print $2 }' <<< "$submission")"
request_sha256="$(awk -F= '$1 == "request_sha256" { print $2 }' <<< "$submission")"
[[ "$request_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
[[ "$request_sha256" =~ ^[0-9a-f]{64}$ ]]
request_directory="$working_repository/requests/$request_id"

output_directory="$run_root/output"
mkdir "$output_directory"
response_path="$output_directory/response.json"
tr -d '\n' < "$fixture_seed" |
    env \
        POLICY_PATH="$fixture_policy" \
        REQUEST_PATH="$request_directory/request.json" \
        RESPONSE_PATH="$response_path" \
        SIGNER_PATH="$signer" \
        "$repository_root/Scripts/run_signer_sandboxed.sh" > /dev/null

public_key_json="$(
    tr -d '\n' < "$fixture_seed" |
        "$signer" derive-public-key --private-key-stdin --format json
)"
public_key_base64="$(jq -r '.public_key_base64' <<< "$public_key_json")"
"$signer" verify-response \
    --request "$request_directory/request.json" \
    --response "$response_path" \
    --public-key-base64 "$public_key_base64" > /dev/null

audit_path="$output_directory/audit.json"
summary_path="$request_directory/summary.json"
signer_sha256="$(shasum -a 256 "$signer" | awk '{print $1}')"
jq -cS -n \
    --arg actor "$(jq -r '.submitted_by' "$summary_path")" \
    --arg build_id "$(jq -r '.build_id' "$request_directory/request.json")" \
    --arg bundle_identifier "$(jq -r '.bundle_identifier' "$request_directory/request.json")" \
    --arg control_commit "$(git rev-parse HEAD)" \
    --arg github_run_id "fixture-e2e" \
    --arg ios_harden_revision "$(jq -r '.ios_harden_revision' "$summary_path")" \
    --arg key_id "$(jq -r '.key_id' "$response_path")" \
    --arg manifest_sha256 "$(jq -r '.manifest_sha256' "$request_directory/request.json")" \
    --arg public_key_sha256 "$(jq -r '.public_key_sha256' "$response_path")" \
    --arg request_id "$request_id" \
    --arg request_sha256 "$request_sha256" \
    --arg signer_sha256 "$signer_sha256" \
    --arg source_revision "$(jq -r '.source_revision' "$summary_path")" \
    --arg submitted_by "$(jq -r '.submitted_by' "$summary_path")" \
    --argjson submitted_at_epoch_seconds "$(jq -r '.submitted_at_epoch_seconds' "$summary_path")" \
    --argjson signed_at_epoch_seconds "$(date +%s)" \
    '{
        actor: $actor,
        build_id: $build_id,
        bundle_identifier: $bundle_identifier,
        control_commit: $control_commit,
        github_run_id: $github_run_id,
        ios_harden_revision: $ios_harden_revision,
        key_id: $key_id,
        manifest_sha256: $manifest_sha256,
        public_key_sha256: $public_key_sha256,
        request_id: $request_id,
        request_sha256: $request_sha256,
        schema_version: 1,
        signed_at_epoch_seconds: $signed_at_epoch_seconds,
        signer_sha256: $signer_sha256,
        source_revision: $source_revision,
        status: "signed",
        submitted_at_epoch_seconds: $submitted_at_epoch_seconds,
        submitted_by: $submitted_by
    }' > "$audit_path"

Scripts/publish_response.sh \
    --requests-repo "$working_repository" \
    --request-id "$request_id" \
    --response "$response_path" \
    --audit "$audit_path" > /dev/null

git clone "$bare_repository" "$verification_repository"
published_request="$verification_repository/requests/$request_id/request.json"
published_response="$verification_repository/responses/$request_id/response.json"
fetched_response="$run_root/fetched-response.json"
"$verification_repository/Scripts/fetch_response.sh" \
    --request-id "$request_id" \
    --destination "$fetched_response" > /dev/null
cmp "$published_response" "$fetched_response"
"$signer" verify-response \
    --request "$published_request" \
    --response "$fetched_response" \
    --public-key-base64 "$public_key_base64" > /dev/null

response_sha256="$(
    shasum -a 256 "$fetched_response" |
        awk '{print $1}'
)"
receipt_temporary="$run_root/last-run.json"
jq -cS -n \
    --arg key_id "skb-integrity-fixture" \
    --arg public_key_sha256 "$(jq -r '.public_key_sha256' <<< "$public_key_json")" \
    --arg request_id "$request_id" \
    --arg request_sha256 "$request_sha256" \
    --arg response_sha256 "$response_sha256" \
    --argjson verified_at_epoch_seconds "$(date +%s)" \
    '{
        key_id: $key_id,
        production_secret_used: false,
        public_key_sha256: $public_key_sha256,
        request_id: $request_id,
        request_sha256: $request_sha256,
        response_sha256: $response_sha256,
        schema_version: 1,
        signature_verified: true,
        verified_at_epoch_seconds: $verified_at_epoch_seconds
    }' > "$receipt_temporary"
mv "$receipt_temporary" Evidence/fixture-e2e/last-run.json

echo "fixture 端到端验证通过"
echo "证据：$repository_root/Evidence/fixture-e2e/last-run.json"
