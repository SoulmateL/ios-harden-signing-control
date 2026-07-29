#!/bin/bash
set -euo pipefail
set +x

[[ $# -eq 2 && "$1" == "--destination" ]] || {
    echo "用法：install_pinned_age.sh --destination /绝对路径/age-v1.3.1" >&2
    exit 2
}

destination="$2"
[[ "$destination" == /* && "$destination" != / &&
    "$destination" != */ && "$destination" != *'/./'* &&
    "$destination" != *'/../'* ]] || {
    echo "错误：destination 必须是无点组件的绝对目录路径" >&2
    exit 2
}
[[ -L "$destination" ]] && {
    echo "错误：destination 不得是符号链接" >&2
    exit 2
}
[[ ! -e "$destination" || -d "$destination" ]] || {
    echo "错误：destination 已被非目录占用" >&2
    exit 2
}

version="v1.3.1"
case "$(uname -m)" in
    arm64)
        archive="age-v1.3.1-darwin-arm64.tar.gz"
        archive_sha256="01120ea2cbf0463d4c6bd767f99f3271bbed1cdc8a9aa718a76ba1fe4f01998b"
        binary_sha256="0e3ea0b1bed2b30aa2dc46eef4e1723864d626c80f37319c20d9b73ca045f56f"
        ;;
    x86_64)
        archive="age-v1.3.1-darwin-amd64.tar.gz"
        archive_sha256="2b233301ad21ab7b1eabd9ae1198a164005fa4928fcdd745d47c39f8593209d7"
        binary_sha256="3c5122c6c5b63c78089ab80f97983bfea98b9afa9e87dde198a1184295defb3c"
        ;;
    *)
        echo "错误：只支持 macOS arm64 或 x86_64" >&2
        exit 2
        ;;
esac

mkdir -p "$destination"
destination="$(cd "$destination" && pwd -P)"
age_path="$destination/age"
if [[ -e "$age_path" || -L "$age_path" ]]; then
    script_directory="$(cd "$(dirname "$0")" && pwd -P)"
    "$script_directory/verify_pinned_age.sh" --age "$age_path"
    exit 0
fi
[[ -z "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
    echo "错误：destination 必须为空目录" >&2
    exit 2
}

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/ios-harden-age.XXXXXX")"
chmod 700 "$temporary_directory"
archive_path="$temporary_directory/$archive"
extracted_directory="$temporary_directory/age"
cleanup() {
    exit_status=$?
    if [[ -e "$archive_path" ]]; then
        /bin/rm "$archive_path"
    fi
    if [[ -e "$extracted_directory/age" ]]; then
        /bin/rm "$extracted_directory/age"
    fi
    /bin/rmdir "$extracted_directory" 2>/dev/null || true
    /bin/rmdir "$temporary_directory" 2>/dev/null || true
    exit "$exit_status"
}
trap cleanup EXIT

gh release download "$version" \
    --repo FiloSottile/age \
    --pattern "$archive" \
    --dir "$temporary_directory"
printf '%s  %s\n' "$archive_sha256" "$archive_path" |
    /usr/bin/shasum -a 256 -c - > /dev/null
/usr/bin/tar -xzf "$archive_path" -C "$temporary_directory" age/age
printf '%s  %s\n' "$binary_sha256" "$extracted_directory/age" |
    /usr/bin/shasum -a 256 -c - > /dev/null
/usr/bin/install -m 0555 "$extracted_directory/age" "$age_path"
printf '%s  %s\n' "$binary_sha256" "$age_path" |
    /usr/bin/shasum -a 256 -c - > /dev/null
[[ "$("$age_path" --version)" == "$version" ]] || {
    echo "错误：安装后的 age 版本不匹配" >&2
    exit 2
}

printf '%s\n' "$age_path"
