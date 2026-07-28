#!/bin/bash
set -euo pipefail

[[ $# -eq 2 && "$1" == "--volume" ]] || {
    echo "用法：verify_encrypted_recovery_volume.sh --volume /Volumes/已解锁卷" >&2
    exit 2
}
volume_path="$2"
[[ "$volume_path" == /Volumes/* && "$volume_path" != "/Volumes/"*/* &&
    ! -L "$volume_path" ]] || {
    echo "错误：恢复卷必须是 /Volumes 下的直接挂载点且不能是符号链接" >&2
    exit 2
}
volume_path="$(realpath "$volume_path")"
[[ "$volume_path" != "/" && "$volume_path" != "$HOME" ]] || {
    echo "错误：拒绝使用系统卷或用户目录" >&2
    exit 2
}

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
[[ "$volume_path" != "$repository_root" ]] || {
    echo "错误：拒绝把仓库当作恢复卷" >&2
    exit 2
}

information_plist="$(mktemp "${TMPDIR:-/tmp}/ios-harden-volume.XXXXXX")"
trap '/bin/rm "$information_plist"' EXIT
/usr/sbin/diskutil info -plist "$volume_path" > "$information_plist"

plist_value() {
    /usr/bin/plutil -extract "$1" raw -o - "$information_plist" 2>/dev/null
}

[[ "$(plist_value Mounted)" == "true" ]] || {
    echo "错误：恢复卷未挂载" >&2
    exit 2
}
[[ "$(plist_value Writable)" == "true" ]] || {
    echo "错误：恢复卷不可写" >&2
    exit 2
}
[[ "$(plist_value FilesystemType)" == "apfs" ]] || {
    echo "错误：恢复卷必须使用 APFS" >&2
    exit 2
}
[[ "$(plist_value Encrypted)" == "true" ]] || {
    echo "错误：恢复卷必须启用加密" >&2
    exit 2
}
[[ "$(plist_value RemovableMedia)" == "true" ]] || {
    echo "错误：恢复卷必须位于可移除介质" >&2
    exit 2
}
[[ "$(plist_value MountPoint)" == "$volume_path" ]] || {
    echo "错误：恢复卷挂载点不匹配" >&2
    exit 2
}

printf '%s\n' "$volume_path"
