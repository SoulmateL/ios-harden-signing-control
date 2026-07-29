#!/bin/bash
set -euo pipefail
set +x

[[ $# -eq 2 && "$1" == "--age" ]] || {
    echo "用法：recovery_roundtrip_test.sh --age /绝对路径/age" >&2
    exit 2
}

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
age_path="$(
    "$repository_root/Scripts/verify_pinned_age.sh" --age "$2"
)"
fixture_seed="$repository_root/Fixtures/fixture-seed.b64"
fixture_passphrase="fixture-only-age-passphrase-not-for-production"

temporary_directory="$(
    mktemp -d "${TMPDIR:-/tmp}/ios-harden-recovery-test.XXXXXX"
)"
chmod 700 "$temporary_directory"
ciphertext="$temporary_directory/fixture.age"
roundtrip="$temporary_directory/roundtrip.b64"
wrong_output="$temporary_directory/wrong.b64"
tampered="$temporary_directory/tampered.age"
tampered_output="$temporary_directory/tampered.b64"
cleanup() {
    exit_status=$?
    for temporary_file in \
        "$ciphertext" \
        "$roundtrip" \
        "$wrong_output" \
        "$tampered" \
        "$tampered_output"; do
        if [[ -e "$temporary_file" ]]; then
            /bin/rm "$temporary_file"
        fi
    done
    /bin/rmdir "$temporary_directory" 2>/dev/null || true
    exit "$exit_status"
}
trap cleanup EXIT

printf '%s\n%s\n' "$fixture_passphrase" "$fixture_passphrase" |
    /usr/bin/script -q /dev/null \
        "$age_path" \
        --encrypt \
        --passphrase \
        --output "$ciphertext" \
        "$fixture_seed" > /dev/null 2>&1

[[ "$(head -c 21 "$ciphertext")" == "age-encryption.org/v1" ]]
if grep -aFq "$fixture_passphrase" "$ciphertext"; then
    echo "错误：密文包含 fixture 密码" >&2
    exit 1
fi
if grep -aFq "$(tr -d '\n' < "$fixture_seed")" "$ciphertext"; then
    echo "错误：密文包含 fixture seed" >&2
    exit 1
fi

printf '%s\n' "$fixture_passphrase" |
    /usr/bin/script -q /dev/null \
        "$age_path" \
        --decrypt \
        --output "$roundtrip" \
        "$ciphertext" > /dev/null 2>&1
cmp "$fixture_seed" "$roundtrip"

if printf '%s\n' "wrong-fixture-passphrase" |
    /usr/bin/script -q /dev/null \
        "$age_path" \
        --decrypt \
        --output "$wrong_output" \
        "$ciphertext" > /dev/null 2>&1; then
    echo "错误：错误密码不得解密恢复副本" >&2
    exit 1
fi
[[ ! -e "$wrong_output" ]]

cp "$ciphertext" "$tampered"
printf 'x' >> "$tampered"
if printf '%s\n' "$fixture_passphrase" |
    /usr/bin/script -q /dev/null \
        "$age_path" \
        --decrypt \
        --output "$tampered_output" \
        "$tampered" > /dev/null 2>&1; then
    echo "错误：被修改的恢复副本不得解密" >&2
    exit 1
fi
[[ ! -e "$tampered_output" ]]

echo "fixture 加密恢复往返检查通过；未使用生产 seed"
