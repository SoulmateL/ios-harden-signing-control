#!/bin/bash
set -euo pipefail

control_repository="SoulmateL/ios-harden-signing-control"
requests_repository="SoulmateL/ios-harden-signing-requests"

verify_private_owner_repository() {
    local repository="$1"
    gh api "repos/$repository" |
        jq -e '
            .private == true and
            .visibility == "private" and
            .owner.login == "SoulmateL"
        ' > /dev/null || {
        echo "错误：$repository 必须是 SoulmateL 的私有仓库" >&2
        exit 1
    }
}

verify_public_owner_repository() {
    local repository="$1"
    gh api "repos/$repository" |
        jq -e '
            .private == false and
            .visibility == "public" and
            .owner.login == "SoulmateL" and
            .security_and_analysis.secret_scanning.status == "enabled" and
            .security_and_analysis.secret_scanning_push_protection.status == "enabled"
        ' > /dev/null || {
        echo "错误：$repository 必须是 SoulmateL 的公开仓库，且必须启用 Secret 扫描与 push protection" >&2
        exit 1
    }
}

verify_public_owner_repository "$control_repository"
verify_private_owner_repository "$requests_repository"

gh api "repos/$control_repository/actions/permissions" |
    jq -e '
        .enabled == true and
        .allowed_actions == "all" and
        .sha_pinning_required == true
    ' > /dev/null || {
    echo "错误：控制仓库必须启用 Actions 并强制 Action 固定 SHA" >&2
    exit 1
}

gh api "repos/$requests_repository/actions/permissions" |
    jq -e '.enabled == false' > /dev/null || {
    echo "错误：请求仓库必须关闭 GitHub Actions" >&2
    exit 1
}

gh api "repos/$control_repository/collaborators" |
    jq -e '
        length == 1 and
        .[0].login == "SoulmateL" and
        .[0].permissions.admin == true
    ' > /dev/null || {
    echo "错误：控制仓库只能有所有者 SoulmateL" >&2
    exit 1
}

gh api "repos/$requests_repository/keys" |
    jq -e '
        [
            .[] |
            select(
                .title == "ios-harden-signing-control" and
                .read_only == false
            )
        ] | length == 1
    ' > /dev/null || {
    echo "错误：请求仓库必须且只能有一把指定的写入 deploy key" >&2
    exit 1
}

key_count="$(
    gh api "repos/$requests_repository/keys" |
        jq 'length'
)"
[[ "$key_count" -eq 1 ]] || {
    echo "错误：请求仓库存在额外 deploy key" >&2
    exit 1
}

echo "GitHub 仓库安全设置检查通过"
