# Encrypted Repository Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the production bootstrap's encrypted removable-volume requirement with a
password-encrypted recovery file committed to the private request repository, while keeping the
production seed only in the control repository's GitHub Secret.

**Architecture:** A pinned official `age v1.3.1` binary provides passphrase-based authenticated
encryption. The control repository's bootstrap generates a seed in a `0600` temporary directory,
encrypts and decrypt-verifies it through an interactive terminal, commits only the `.age` ciphertext
to `SoulmateL/ios-harden-signing-requests`, then writes the seed to the control repository Secret.
An owner-only restore script decrypts a named recovery file and pipes the validated seed to the
same Secret. The public control repository contains no recovery ciphertext or production secret.

**Tech Stack:** Bash 3-compatible shell scripts, macOS `/usr/bin/tar`, `/usr/bin/shasum`,
GitHub CLI, `age v1.3.1`, Swift/CryptoKit signer, jq, GitHub Actions on
`macos-15`.

---

## File Map

Control repository:

- Create `Scripts/install_pinned_age.sh`: download the architecture-specific official
  `age-v1.3.1` archive, verify its pinned archive and executable SHA-256, and install it below a
  caller-supplied ignored directory.
- Create `Scripts/verify_pinned_age.sh`: verify an absolute executable is exactly the pinned
  `age v1.3.1` binary for the current macOS architecture and print the canonical path.
- Create `Scripts/verify_recovery_repository.sh`: validate the local private request checkout,
  remote identity, `main` branch, clean worktree, fast-forward synchronization, and the requested
  recovery path.
- Create `Scripts/restore_production_secret.sh`: interactively decrypt a committed `.age` file,
  validate the 32-byte Base64 seed with the release signer, compare its public key to the
  published policy when present, and update the control repository Secret without printing seed
  material.
- Create `Tests/age_tool_contract_test.sh`: static contract checks for the pinned installer and
  verifier.
- Create `Tests/recovery_roundtrip_test.sh`: fixture-only PTY test covering encryption,
  decrypt/compare, wrong passwords, and tampered ciphertext.
- Modify `Scripts/bootstrap_production.sh`: replace `--recovery-volume` with
  `--requests-repo` and `--age`, encrypt/decrypt-verify before any Secret write, push the private
  ciphertext before `gh secret set`, and remove all diskutil usage.
- Modify `Tests/bootstrap_contract_test.sh`: assert the new argument contract, ordering, and
  absence of the old removable-volume flow.
- Modify `.github/workflows/ci.yml`: install the pinned age binary in `$RUNNER_TEMP` and run the
  fixture recovery round-trip test before the repository scan.
- Modify `.gitignore`: ignore `.tools/` and other local age installer output without ignoring
  `.age` files in the private request repository.
- Modify `README.md`, `docs/PRODUCTION_BOOTSTRAP.md`, and the 2026-07-28 design/spec references:
  explain the private encrypted recovery file and the iPhone-only password boundary.

Private request repository:

- Create `Recovery/.gitkeep`.
- Modify `.gitignore`: continue rejecting raw seed/key material while allowing the exact encrypted
  recovery suffix.
- Modify `Tests/request_repository_contract.sh`: allow only `Recovery/.gitkeep` and
  `Recovery/*.age`, reject every other Recovery path, and reject files whose names or content
  indicate a raw seed.
- Modify `README.md`: document that Recovery contains ciphertext only and that the password never
  enters GitHub.

## Task 1: Pin and Verify the `age` Tool

**Files:**

- Create: `ios-harden-signing-control/Tests/age_tool_contract_test.sh`
- Create: `ios-harden-signing-control/Scripts/install_pinned_age.sh`
- Create: `ios-harden-signing-control/Scripts/verify_pinned_age.sh`
- Modify: `ios-harden-signing-control/.gitignore`

- [ ] **Step 1: Write the failing contract test**

Add assertions that the two scripts exist and are Bash-syntax-valid, contain `v1.3.1`, the
official release repository, both Darwin archive SHA-256 values, both executable SHA-256 values, reject
unknown architectures, reject symlink destinations, and never accept a password argument or
environment variable. The test must fail immediately because the scripts do not exist.

```bash
test -f "$installer"
test -f "$verifier"
bash -n "$installer"
bash -n "$verifier"
grep -Fq 'v1.3.1' "$installer"
grep -Fq '01120ea2cbf0463d4c6bd767f99f3271bbed1cdc8a9aa718a76ba1fe4f01998b' "$installer"
grep -Fq '2b233301ad21ab7b1eabd9ae1198a164005fa4928fcdd745d47c39f8593209d7' "$installer"
grep -Fq '0e3ea0b1bed2b30aa2dc46eef4e1723864d626c80f37319c20d9b73ca045f56f' "$verifier"
grep -Fq '3c5122c6c5b63c78089ab80f97983bfea98b9afa9e87dde198a1184295defb3c' "$verifier"
! grep -Eq -- '--passphrase|AGE_PASSPHRASE|PASSWORD' "$verifier"
```

Run:

```bash
bash Tests/age_tool_contract_test.sh
```

Expected: FAIL because both scripts are absent.

- [ ] **Step 2: Implement the pinned installer**

`install_pinned_age.sh` accepts exactly `--destination /absolute/path`. It maps `arm64` and
`x86_64` to the two fixed Darwin archive names and checksums, rejects a symlink or non-directory
destination, downloads only through `gh release download v1.3.1 --repo FiloSottile/age`, verifies the archive with
`/usr/bin/shasum -a 256 -c -`, extracts only `age/age`, verifies the executable checksum, installs
mode `0555`, and prints the installed path. It must not accept any passphrase or seed input.

```bash
case "$(uname -m)" in
    arm64) archive="age-v1.3.1-darwin-arm64.tar.gz"; archive_sha="01120ea2cbf0463d4c6bd767f99f3271bbed1cdc8a9aa718a76ba1fe4f01998b"; binary_sha="0e3ea0b1bed2b30aa2dc46eef4e1723864d626c80f37319c20d9b73ca045f56f" ;;
    x86_64) archive="age-v1.3.1-darwin-amd64.tar.gz"; archive_sha="2b233301ad21ab7b1eabd9ae1198a164005fa4928fcdd745d47c39f8593209d7"; binary_sha="3c5122c6c5b63c78089ab80f97983bfea98b9afa9e87dde198a1184295defb3c" ;;
    *) echo "错误：只支持 macOS arm64 或 x86_64" >&2; exit 2 ;;
esac
```

- [ ] **Step 3: Implement the verifier**

`verify_pinned_age.sh` accepts exactly `--age /absolute/path`, rejects symlinks and paths with
`.` or `..` components, checks the architecture-specific executable SHA-256 and exact
`v1.3.1` output, then prints the resolved path. It never reads a password.

- [ ] **Step 4: Run the contract and installer checks**

Run:

```bash
bash Tests/age_tool_contract_test.sh
Scripts/install_pinned_age.sh --destination "$PWD/.tools/age-v1.3.1"
Scripts/verify_pinned_age.sh --age "$PWD/.tools/age-v1.3.1/age"
```

Expected: all checks pass and the final command prints the absolute `age` path. The `.tools`
directory must remain ignored and untracked.

- [ ] **Step 5: Commit**

```bash
git add Scripts/install_pinned_age.sh Scripts/verify_pinned_age.sh Tests/age_tool_contract_test.sh .gitignore
git commit -m "feat: pin age recovery encryption tool"
```

## Task 2: Permit Ciphertext in the Private Request Repository

**Files:**

- Create: `work/ios-harden-signing-requests/Recovery/.gitkeep`
- Modify: `work/ios-harden-signing-requests/Tests/request_repository_contract.sh`
- Modify: `work/ios-harden-signing-requests/README.md`

- [ ] **Step 1: Extend the contract test before adding the directory**

Require `Recovery/.gitkeep`, allow `Recovery/*.age`, reject every other `Recovery/*` path, and
scan any existing `.age` file for an age header while rejecting Base64 fixture content. Run the
test and confirm it fails because `Recovery/.gitkeep` is missing.

- [ ] **Step 2: Add the empty Recovery directory and documentation**

Add `Recovery/.gitkeep`, update the allowed-path case to include `Recovery/.gitkeep|Recovery/*.age`,
and document that only authenticated ciphertext is allowed. Do not add a real `.age` file.

- [ ] **Step 3: Run the private repository contract**

```bash
bash Tests/request_repository_contract.sh
```

Expected: `请求仓库契约检查通过`.

- [ ] **Step 4: Commit and push the private repository change**

```bash
git add Recovery/.gitkeep Tests/request_repository_contract.sh README.md
git commit -m "feat: reserve encrypted recovery path"
git push origin main
```

## Task 3: Add Fixture Encryption and Recovery Tests

**Files:**

- Create: `ios-harden-signing-control/Tests/recovery_roundtrip_test.sh`
- Modify: `ios-harden-signing-control/.github/workflows/ci.yml`
- Modify: `ios-harden-signing-control/Tests/workflow_contract_test.sh`

- [ ] **Step 1: Write the failing fixture test**

The test accepts exactly `--age /absolute/path`, creates a `0700` temporary directory, encrypts
`Fixtures/fixture-seed.b64` with the public fixture passphrase by feeding a PTY to `age --passphrase`,
decrypts it through a PTY, and checks `cmp`. It must also assert that wrong-password decryption
fails, that appending one byte to the ciphertext fails, and that the output/log files do not
contain the fixture seed or passphrase.

Use macOS `/usr/bin/script -q /dev/null` only in this fixture test; production scripts must use
the real interactive terminal directly and must not contain `AGE_PASSPHRASE`.

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash Tests/recovery_roundtrip_test.sh --age "$PWD/.tools/age-v1.3.1/age"
```

Expected: FAIL because the new test file is absent.

- [ ] **Step 3: Add the CI installation and test steps**

Insert before repository scans and before any future secret-injection step:

```yaml
- name: Install pinned age
  run: Scripts/install_pinned_age.sh --destination "$RUNNER_TEMP/age-v1.3.1"

- name: Test encrypted recovery round trip
  run: bash Tests/recovery_roundtrip_test.sh --age "$RUNNER_TEMP/age-v1.3.1/age"
```

Extend `Tests/workflow_contract_test.sh` to require both step names and to assert that the
installer runs before the round-trip test.

- [ ] **Step 4: Run the fixture test and workflow contract**

```bash
bash Tests/recovery_roundtrip_test.sh --age "$PWD/.tools/age-v1.3.1/age"
bash Tests/workflow_contract_test.sh
```

Expected: both pass; no production secret is read or written.

- [ ] **Step 5: Commit**

```bash
git add Tests/recovery_roundtrip_test.sh .github/workflows/ci.yml Tests/workflow_contract_test.sh
git commit -m "test: verify encrypted recovery round trip"
```

## Task 4: Replace USB Bootstrap with Private-Repository Bootstrap

**Files:**

- Create: `ios-harden-signing-control/Scripts/verify_recovery_repository.sh`
- Modify: `ios-harden-signing-control/Scripts/bootstrap_production.sh`
- Modify: `ios-harden-signing-control/Tests/bootstrap_contract_test.sh`

- [ ] **Step 1: Write failing bootstrap assertions**

Replace the old USB assertions with checks for `--requests-repo`, `--age`,
`verify_recovery_repository.sh`, `age --encrypt --passphrase`, `age --decrypt`, `git push origin
main`, and the required ordering:

```bash
recovery_push_line="$(grep -n -F 'git push origin main' "$bootstrap" | cut -d: -f1)"
secret_line="$(grep -n -F 'gh secret set IOS_HARDEN_ED25519_SEED_B64' "$bootstrap" | cut -d: -f1)"
[[ "$recovery_push_line" -lt "$secret_line" ]]
! grep -Fq 'verify_encrypted_recovery_volume.sh' "$bootstrap"
! grep -Fq 'diskutil unmount' "$bootstrap"
```

Run `bash Tests/bootstrap_contract_test.sh` and confirm the old implementation fails.

- [ ] **Step 2: Implement recovery checkout validation**

`verify_recovery_repository.sh` accepts exactly `--repository /absolute/path`, resolves the
checkout root, rejects symlinks, requires remote `SoulmateL/ios-harden-signing-requests`,
requires `main`, runs `git pull --ff-only`, rejects a dirty worktree, requires local `Recovery`
to be a non-symlink directory, and prints the resolved root. It must not create files or accept
the seed/password.

- [ ] **Step 3: Rewrite bootstrap argument and preflight gates**

The command becomes:

```bash
Scripts/bootstrap_production.sh \
  --requests-repo /absolute/path/ios-harden-signing-requests \
  --bundle-identifier com.real.app \
  --signer "$PWD/.build/release/ios-harden-actions-signer" \
  --age "$PWD/.tools/age-v1.3.1/age"
```

Keep the interactive TTY check, owner confirmation, control repository settings check, existing
production-policy refusal, and `PRODUCTION_READY=false`. Replace the volume verifier and recovery
directory with the private checkout verifier and exact
`Recovery/skb-integrity-prod-2026-03.age` target refusal.

- [ ] **Step 4: Implement encrypt, verify, push, then Secret ordering**

Generate the seed in the existing `0600` temporary directory. Invoke:

```bash
"$age_path" --encrypt --passphrase --output "$encrypted_temporary_path" "$seed_base64_path"
"$age_path" --decrypt --output "$roundtrip_path" "$encrypted_temporary_path"
cmp "$seed_base64_path" "$roundtrip_path"
```

Copy only the ciphertext into the private checkout, commit with
`recovery: add encrypted production copy`, and push `origin main`. Only after the push returns
success may the script run `gh secret set IOS_HARDEN_ED25519_SEED_B64 < "$seed_base64_path"`.
Continue to create the public policy and receipt, but never print seed or password and never set
`PRODUCTION_READY=true`. Cleanup must remove seed, Base64, round-trip, and temporary ciphertext
files on every exit.

- [ ] **Step 5: Run bootstrap contract and shell syntax checks**

```bash
bash Tests/bootstrap_contract_test.sh
bash -n Scripts/bootstrap_production.sh Scripts/verify_recovery_repository.sh
```

Expected: pass without invoking the production bootstrap or generating a seed.

- [ ] **Step 6: Commit**

```bash
git add Scripts/bootstrap_production.sh Scripts/verify_recovery_repository.sh Tests/bootstrap_contract_test.sh
git commit -m "feat: bootstrap recovery into private repository"
```

## Task 5: Add Owner Recovery Script

**Files:**

- Create: `ios-harden-signing-control/Scripts/restore_production_secret.sh`
- Create: `ios-harden-signing-control/Tests/restore_secret_contract_test.sh`

- [ ] **Step 1: Write the failing restore contract**

Require the script to accept `--requests-repo`, `--signer`, and `--age`, require an interactive TTY,
call the recovery checkout verifier, use `age --decrypt` and signer `derive-public-key`, write the
Secret only through stdin, and never contain `echo`/`printf` of the seed variable or
`AGE_PASSPHRASE`.

- [ ] **Step 2: Run the contract to verify it fails**

```bash
bash Tests/restore_secret_contract_test.sh
```

Expected: FAIL because the restore script is absent.

- [ ] **Step 3: Implement restore**

After pulling and validating the private checkout, decrypt only the exact
`Recovery/skb-integrity-prod-2026-03.age` file into a `0600` temporary file. Call the release
signer with `derive-public-key --private-key-stdin --format json`, validate the canonical Base64
and 32-byte seed through the signer, and when `Config/production-policy.json` already exists,
require its public SHA-256 to match the derived fingerprint. Use:

```bash
gh secret set IOS_HARDEN_ED25519_SEED_B64 \
  --repo SoulmateL/ios-harden-signing-control \
  < "$seed_base64_path"
```

Print only the fixed Key ID and derived public fingerprint. Remove the temporary seed in an EXIT
trap. If the policy is missing, print a warning that the bootstrap must still publish public
policy before enabling production; do not enable production automatically.

- [ ] **Step 4: Run restore contract and syntax checks**

```bash
bash Tests/restore_secret_contract_test.sh
bash -n Scripts/restore_production_secret.sh
```

Expected: pass without calling GitHub Secret APIs.

- [ ] **Step 5: Commit**

```bash
git add Scripts/restore_production_secret.sh Tests/restore_secret_contract_test.sh
git commit -m "feat: restore production secret from encrypted copy"
```

## Task 6: Update Control Documentation and Re-run Repository Contracts

**Files:**

- Modify: `ios-harden-signing-control/docs/PRODUCTION_BOOTSTRAP.md`
- Modify: `ios-harden-signing-control/README.md`
- Modify: `ios-harden-signing-control/docs/superpowers/specs/2026-07-28-ios-harden-github-actions-signing-control-design.md`

- [ ] **Step 1: Update the control documentation**

Replace every production U-disk prerequisite and command with the private request checkout and
pinned age command. Document that the owner types or pastes the password from iPhone into hidden
terminal prompts, that `Recovery/*.age` is ciphertext only, and that bootstrap pushes ciphertext
before writing the Secret. Keep the Bundle ID, billing, public-policy review, old Key ID
revocation, and `PRODUCTION_READY=false` gates.

- [ ] **Step 2: Recheck the private request documentation and contract**

Confirm the Task 2 changes still document
`Recovery/skb-integrity-prod-2026-03.age` as the only allowed recovery artifact. Re-run the
contract that rejects raw seed extensions and any file under Recovery not ending in `.age`.

- [ ] **Step 3: Run all local contracts**

```bash
bash Tests/request_repository_contract.sh
bash Scripts/validate_repository.sh
bash Tests/age_tool_contract_test.sh
bash Tests/recovery_roundtrip_test.sh --age "$PWD/.tools/age-v1.3.1/age"
bash Tests/bootstrap_contract_test.sh
bash Tests/restore_secret_contract_test.sh
bash Tests/workflow_contract_test.sh
bash Tests/sandbox_contract_test.sh
bash Tests/fixture_e2e_contract_test.sh
swift test
```

Expected: all commands pass; no production `Config/production-policy.json`,
`IOS_HARDEN_ED25519_SEED_B64`, or production recovery ciphertext is generated locally.

- [ ] **Step 4: Commit control documentation and push both repositories**

```bash
git add README.md docs/PRODUCTION_BOOTSTRAP.md docs/superpowers/specs/2026-07-28-ios-harden-github-actions-signing-control-design.md
git commit -m "docs: document encrypted repository recovery"
git push origin main
```

## Task 7: Final Verification and Handoff

- [ ] **Step 1: Check both worktrees**

```bash
git -C ios-harden-signing-control status --short --branch
git -C work/ios-harden-signing-requests status --short --branch
```

Expected: both `main` branches are clean and match their pushed remotes.

- [ ] **Step 2: Confirm no production side effects**

```bash
test ! -e ios-harden-signing-control/Config/production-policy.json
test ! -e ios-harden-signing-control/Evidence/production-bootstrap/public-receipt.json
test -z "$(find ios-harden-signing-control -path '*/.git' -prune -o -name '*.age' -type f -print -quit)"
```

Expected: no production seed, policy, receipt, or encrypted recovery file exists in the public
control repository.

- [ ] **Step 3: Report only confirmed results**

Report the pushed commits, test commands and outcomes, the exact future bootstrap command shape
without a real Bundle ID, and the fact that the user still must create the iPhone Passwords entry
and supply the actual App source or built artifact so the Bundle ID can be found. Do not request or
display a seed, private key, recovery password, GitHub token, or U-disk password.
