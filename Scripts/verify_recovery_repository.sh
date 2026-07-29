#!/bin/bash
set -euo pipefail
set +x

[[ $# -eq 2 && "$1" == "--repository" ]] || {
    echo "用法：verify_recovery_repository.sh --repository /绝对路径/ios-harden-signing-requests" >&2
    exit 2
}

requested_repository="$2"
[[ "$requested_repository" == /* && "$requested_repository" != / &&
    "$requested_repository" != */ &&
    "$requested_repository" != *'/./'* &&
    "$requested_repository" != *'/../'* ]] || {
    echo "错误：请求仓库必须是无点组件的绝对目录路径" >&2
    exit 2
}
[[ -L "$requested_repository" ]] && {
    echo "错误：请求仓库不得是符号链接" >&2
    exit 2
}
[[ -d "$requested_repository/.git" ]] || {
    echo "错误：请求仓库路径无效" >&2
    exit 2
}

recovery_repository="$(cd "$requested_repository" && pwd -P)"
[[ "$recovery_repository" == "$requested_repository" ]] || {
    echo "错误：请求仓库路径不得经过符号链接" >&2
    exit 2
}
[[ "$(git -C "$recovery_repository" rev-parse --show-toplevel)" == "$recovery_repository" ]] || {
    echo "错误：请求仓库根目录校验失败" >&2
    exit 2
}
[[ "$(git -C "$recovery_repository" branch --show-current)" == "main" ]] || {
    echo "错误：请求仓库必须位于 main 分支" >&2
    exit 2
}

remote_url="$(git -C "$recovery_repository" remote get-url origin)"
case "$remote_url" in
    https://github.com/SoulmateL/ios-harden-signing-requests.git|\
    git@github.com:SoulmateL/ios-harden-signing-requests.git)
        ;;
    *)
        echo "错误：请求仓库 origin 必须是 SoulmateL/ios-harden-signing-requests" >&2
        exit 2
        ;;
esac

[[ -z "$(git -C "$recovery_repository" status --porcelain)" ]] || {
    echo "错误：请求仓库工作区必须干净" >&2
    exit 2
}
git -C "$recovery_repository" pull --ff-only > /dev/null
[[ -z "$(git -C "$recovery_repository" status --porcelain)" ]] || {
    echo "错误：同步后请求仓库工作区不干净" >&2
    exit 2
}

[[ -n "$(git -C "$recovery_repository" config user.name)" &&
    -n "$(git -C "$recovery_repository" config user.email)" ]] || {
    echo "错误：请求仓库必须配置 Git 提交姓名和邮箱" >&2
    exit 2
}

recovery_directory="$recovery_repository/Recovery"
[[ ! -L "$recovery_directory" && -d "$recovery_directory" ]] || {
    echo "错误：请求仓库缺少安全的 Recovery 目录" >&2
    exit 2
}
[[ "$(realpath "$recovery_directory")" == "$recovery_directory" ]] || {
    echo "错误：Recovery 目录路径不得经过符号链接" >&2
    exit 2
}

printf '%s\n' "$recovery_repository"
