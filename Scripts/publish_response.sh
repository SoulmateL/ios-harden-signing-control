#!/bin/bash
set -euo pipefail
set +x

usage() {
    echo "用法：publish_response.sh --requests-repo /绝对路径 --request-id <uuid> --response /绝对路径 --audit /绝对路径" >&2
    exit 2
}

[[ $# -eq 8 &&
    "$1" == "--requests-repo" &&
    "$3" == "--request-id" &&
    "$5" == "--response" &&
    "$7" == "--audit" ]] || usage

requests_repository="$2"
request_id="$4"
response_path="$6"
audit_path="$8"

safe_absolute_path() {
    local path="$1"
    [[ "$path" == /* && "$path" != */ &&
        "$path" != *'/./'* && "$path" != *'/../'* ]]
}

safe_absolute_path "$requests_repository" || usage
safe_absolute_path "$response_path" || usage
safe_absolute_path "$audit_path" || usage
[[ "$request_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || {
    echo "错误：request ID 格式无效" >&2
    exit 2
}
[[ -d "$requests_repository/.git" ]] || {
    echo "错误：请求仓库路径无效" >&2
    exit 2
}
for source_file in "$response_path" "$audit_path"; do
    [[ -f "$source_file" && ! -L "$source_file" ]] || {
        echo "错误：发布源必须是普通文件" >&2
        exit 2
    }
done

jq -e '
    type == "object" and
    keys == [
        "key_id",
        "public_key_sha256",
        "request_sha256",
        "schema_version",
        "signature_base64"
    ] and
    .schema_version == 1 and
    (.key_id | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")) and
    (.public_key_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    (.request_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    (.signature_base64 | type == "string" and test("^[A-Za-z0-9+/]{86}==$"))
' "$response_path" > /dev/null || {
    echo "错误：响应格式无效" >&2
    exit 2
}
jq -e \
    --arg request_id "$request_id" \
    --arg request_sha256 "$(jq -r '.request_sha256' "$response_path")" \
    '
        type == "object" and
        .schema_version == 1 and
        .request_id == $request_id and
        .request_sha256 == $request_sha256 and
        .status == "signed"
    ' \
    "$audit_path" > /dev/null || {
    echo "错误：审计记录与响应不匹配" >&2
    exit 2
}

destination="$requests_repository/responses/$request_id"
[[ ! -e "$destination" && ! -L "$destination" ]] || {
    echo "错误：响应已存在，拒绝覆盖" >&2
    exit 2
}
mkdir "$destination"
cp "$response_path" "$destination/response.json"
cp "$audit_path" "$destination/audit.json"
chmod 600 "$destination/response.json" "$destination/audit.json"

git -C "$requests_repository" config user.name "ios-harden-signing-control"
git -C "$requests_repository" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$requests_repository" add \
    "responses/$request_id/response.json" \
    "responses/$request_id/audit.json"
git -C "$requests_repository" commit -m "response: sign $request_id"
git -C "$requests_repository" push origin HEAD:main
