#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$repository_root"

prohibited_header='-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
fixture_hex='0707070707070707070707070707070707070707070707070707070707070707'
fixture_seed="$(
    printf '%s' "$fixture_hex" |
        xxd -r -p |
        base64 |
        tr -d '\n'
)"

while IFS= read -r revision; do
    if git grep -n -I -E -e "$prohibited_header" "$revision" -- .; then
        echo "错误：Git 历史包含私钥头，revision=$revision" >&2
        exit 1
    fi
    if git grep -n -I -F -e "$fixture_seed" "$revision" -- \
        . ':(exclude)Fixtures/fixture-seed.b64'; then
        echo "错误：fixture seed 出现在允许路径之外，revision=$revision" >&2
        exit 1
    fi
done < <(git rev-list --all)

while IFS= read -r path; do
    case "$path" in
        Fixtures/fixture-seed.b64)
            ;;
        *)
            if [[ "$path" =~ (^|/)(seed|private[_-]?key)(\.|$) ]]; then
                echo "错误：可疑私钥文件路径 $path" >&2
                exit 1
            fi
            ;;
    esac
done < <(git ls-files)

if [[ -e Config/production-policy.json ]]; then
    jq -e '
        .schema_version == 1 and
        .key_id == "skb-integrity-prod-2026-03" and
        (.public_key_sha256 | test("^[0-9a-f]{64}$"))
    ' Config/production-policy.json > /dev/null || {
        echo "错误：生产策略格式无效" >&2
        exit 1
    }
fi

echo "仓库秘密与历史扫描通过"
