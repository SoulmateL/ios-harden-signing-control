#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
installer="$repository_root/Scripts/install_pinned_age.sh"
verifier="$repository_root/Scripts/verify_pinned_age.sh"

test -f "$installer"
test -f "$verifier"
bash -n "$installer"
bash -n "$verifier"

for script in "$installer" "$verifier"; do
    grep -Fq 'v1.3.1' "$script"
    if grep -Eq 'AGE_PASSPHRASE|--password-file' "$script"; then
        echo "错误：age 工具安装与验证脚本不得接收恢复密码" >&2
        exit 1
    fi
done

grep -Fq 'gh release download "$version"' "$installer"
grep -Fq -- '--repo FiloSottile/age' "$installer"
grep -Fq -- '--pattern "$archive"' "$installer"
grep -Fq \
    '01120ea2cbf0463d4c6bd767f99f3271bbed1cdc8a9aa718a76ba1fe4f01998b' \
    "$installer"
grep -Fq \
    '2b233301ad21ab7b1eabd9ae1198a164005fa4928fcdd745d47c39f8593209d7' \
    "$installer"
grep -Fq \
    '0e3ea0b1bed2b30aa2dc46eef4e1723864d626c80f37319c20d9b73ca045f56f' \
    "$verifier"
grep -Fq \
    '3c5122c6c5b63c78089ab80f97983bfea98b9afa9e87dde198a1184295defb3c' \
    "$verifier"

grep -Fq 'arm64)' "$installer"
grep -Fq 'x86_64)' "$installer"
grep -Fq 'arm64)' "$verifier"
grep -Fq 'x86_64)' "$verifier"
grep -Fq '[[ -L "$destination" ]]' "$installer"
grep -Fq '[[ -L "$age_path" ]]' "$verifier"
grep -Fq '/usr/bin/shasum' "$installer"
grep -Fq '/usr/bin/shasum' "$verifier"

echo "固定 age 工具契约检查通过"
