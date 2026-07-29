#!/bin/bash
set -euo pipefail
set +x

[[ $# -eq 2 && "$1" == "--age" ]] || {
    echo "用法：verify_pinned_age.sh --age /绝对路径/age" >&2
    exit 2
}

age_path="$2"
[[ "$age_path" == /* && "$age_path" != */ &&
    "$age_path" != *'/./'* && "$age_path" != *'/../'* ]] || {
    echo "错误：age 必须是无点组件的绝对文件路径" >&2
    exit 2
}
[[ -L "$age_path" ]] && {
    echo "错误：age 不得是符号链接" >&2
    exit 2
}
[[ -f "$age_path" && -x "$age_path" ]] || {
    echo "错误：age 必须是可执行的普通文件" >&2
    exit 2
}
resolved_age_path="$(realpath "$age_path")"
[[ "$resolved_age_path" == "$age_path" ]] || {
    echo "错误：age 路径不得经过符号链接" >&2
    exit 2
}

case "$(uname -m)" in
    arm64)
        expected_sha256="0e3ea0b1bed2b30aa2dc46eef4e1723864d626c80f37319c20d9b73ca045f56f"
        ;;
    x86_64)
        expected_sha256="3c5122c6c5b63c78089ab80f97983bfea98b9afa9e87dde198a1184295defb3c"
        ;;
    *)
        echo "错误：只支持 macOS arm64 或 x86_64" >&2
        exit 2
        ;;
esac

actual_sha256="$(
    /usr/bin/shasum -a 256 "$resolved_age_path" |
        awk '{ print $1 }'
)"
[[ "$actual_sha256" == "$expected_sha256" ]] || {
    echo "错误：age 可执行文件 SHA-256 不匹配" >&2
    exit 2
}
[[ "$("$resolved_age_path" --version)" == "v1.3.1" ]] || {
    echo "错误：age 版本必须为 v1.3.1" >&2
    exit 2
}

printf '%s\n' "$resolved_age_path"
