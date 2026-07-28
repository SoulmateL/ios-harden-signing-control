# ios-harden GitHub Actions Signing Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two private `SoulmateL` repositories where team members submit non-secret ios-harden requests and only `SoulmateL` can approve GitHub Actions signing with a centrally stored Ed25519 seed.

**Architecture:** `ios-harden-signing-requests` is a secret-free transport repository with Actions disabled. `ios-harden-signing-control` is owner-only and contains a dependency-free macOS CryptoKit signer, strict policy validation, an owner-triggered workflow, and a write deploy key for publishing signed responses. Production signing remains disabled until an encrypted USB is present and the owner executes the bootstrap gate.

**Tech Stack:** Swift 6, CryptoKit, XCTest, Bash, GitHub Actions, GitHub CLI, Git deploy keys.

---

## File Map

Control repository:

- `Package.swift`: dependency-free Swift package definition.
- `Sources/SigningControlCore/StrictJSON.swift`: strict JSON keys, canonical encoding, SHA-256 helpers.
- `Sources/SigningControlCore/SigningDocuments.swift`: request, response, and public policy models.
- `Sources/SigningControlCore/SigningService.swift`: seed decoding, policy checks, Ed25519 signing.
- `Sources/SigningControlCore/SecureFiles.swift`: bounded reads and non-overwriting atomic writes.
- `Sources/ios-harden-actions-signer/main.swift`: stdin-only CLI.
- `Tests/SigningControlCoreTests/SigningServiceTests.swift`: protocol, policy, tamper, and replay tests.
- `Tests/SigningControlCoreTests/CLITests.swift`: stdin, output, and safe error tests.
- `Config/fixture-policy.json`: committed fixture policy only.
- `Config/legacy-revocations.json`: public record for both legacy Key IDs.
- `Fixtures/request.json`: canonical fixture request.
- `Fixtures/fixture-seed.b64`: explicitly non-production deterministic seed.
- `Scripts/validate_repository.sh`: secret-history and repository contract checks.
- `Scripts/run_signer_sandboxed.sh`: network-denied Seatbelt wrapper.
- `Scripts/bootstrap_production.sh`: owner-attended secret and encrypted USB bootstrap.
- `.github/workflows/ci.yml`: tests and secret scanning.
- `.github/workflows/sign-request.yml`: owner-only manual production signing.

Request repository:

- `README.md`: request/response workflow and secret prohibition.
- `.gitignore`: excludes seed and private-key patterns.
- `requests/.gitkeep`: request namespace.
- `responses/.gitkeep`: signed response namespace.
- `Scripts/submit_request.sh`: strict upload helper.
- `Scripts/fetch_response.sh`: verified response download helper.

## Task 1: Scaffold the Strict Swift Signer

**Files:**

- Create: `Package.swift`
- Create: `Sources/SigningControlCore/StrictJSON.swift`
- Create: `Sources/SigningControlCore/SigningDocuments.swift`
- Create: `Sources/SigningControlCore/SecureFiles.swift`
- Create: `Sources/ios-harden-actions-signer/main.swift`
- Create: `Tests/SigningControlCoreTests/SigningDocumentsTests.swift`

- [ ] **Step 1: Write the failing strict-document tests**

Create tests that use the exact existing ios-harden request fields and reject unknown fields:

```swift
import Foundation
import XCTest
@testable import SigningControlCore

final class SigningDocumentsTests: XCTestCase {
    func testRequestUsesCanonicalIOSHardenSchema() throws {
        let data = Data(#"{"algorithm":"Ed25519","build_id":"42","bundle_identifier":"com.example.App","created_at_epoch_seconds":900,"key_id":"skb-integrity-fixture","manifest_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schema_version":1}"#.utf8)
        let request = try IntegritySigningRequest.decode(data)
        XCTAssertEqual(request.keyID, "skb-integrity-fixture")
        XCTAssertEqual(try request.canonicalData(), data)
    }

    func testRequestRejectsUnknownField() {
        let data = Data(#"{"algorithm":"Ed25519","build_id":"42","bundle_identifier":"com.example.App","created_at_epoch_seconds":900,"extra":true,"key_id":"skb-integrity-fixture","manifest_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schema_version":1}"#.utf8)
        XCTAssertThrowsError(try IntegritySigningRequest.decode(data))
    }
}
```

- [ ] **Step 2: Run the focused test and verify the missing-module failure**

Run:

```bash
swift test --filter SigningDocumentsTests
```

Expected: FAIL because `Package.swift` and `SigningControlCore` do not exist.

- [ ] **Step 3: Add the package and strict request model**

Define a macOS 13 package with one library, one executable, and one test target. Implement:

```swift
public struct IntegritySigningRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let algorithm: String
    public let keyID: String
    public let bundleIdentifier: String
    public let buildID: String
    public let manifestSHA256: String
    public let createdAtEpochSeconds: Int64

    public static func decode(_ data: Data) throws -> Self
    public func canonicalData() throws -> Data
    public func requestSHA256() throws -> String
}
```

`decode` must require exactly these JSON keys:

```text
schema_version
algorithm
key_id
bundle_identifier
build_id
manifest_sha256
created_at_epoch_seconds
```

Use `JSONEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]`.
Require schema `1`, algorithm `Ed25519`, a dotted Bundle ID, a safe identifier Key ID,
a safe identifier build ID, a lowercase 64-character manifest SHA-256, and a nonnegative timestamp.

- [ ] **Step 4: Add bounded secure file helpers and a placeholder CLI**

`SecureFiles.readRegularFile` must reject symlinks and files over 1 MiB.
`SecureFiles.writeNewFile` must reject existing destinations, write mode `0600`, sync, and rename atomically.
The CLI initially supports `version --format json` and returns stable Chinese errors on stderr.

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter SigningDocumentsTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: add strict ios-harden signing documents"
```

## Task 2: Implement Policy-Bound Ed25519 Signing

**Files:**

- Create: `Sources/SigningControlCore/SigningService.swift`
- Modify: `Sources/SigningControlCore/SigningDocuments.swift`
- Create: `Tests/SigningControlCoreTests/SigningServiceTests.swift`
- Create: `Fixtures/request.json`
- Create: `Fixtures/fixture-seed.b64`
- Create: `Config/fixture-policy.json`
- Create: `Config/legacy-revocations.json`

- [ ] **Step 1: Write failing signing and rejection tests**

Use a deterministic fixture seed of 32 bytes with value `0x07`. Cover:

```swift
func testSigningProducesVerifiableIOSHardenResponse() throws
func testSigningRejectsWrongKeyID() throws
func testSigningRejectsWrongPublicKeyFingerprint() throws
func testSigningRejectsExpiredRequest() throws
func testSigningRejectsFutureRequest() throws
func testSigningRejectsDisallowedBundleID() throws
func testSigningRejectsExistingResponse() throws
```

The success test must construct CryptoKit `Curve25519.Signing.PublicKey` and verify the
64-byte response signature against the canonical request bytes.

- [ ] **Step 2: Verify tests fail**

Run:

```bash
swift test --filter SigningServiceTests
```

Expected: FAIL because `SigningService` and policy decoding are absent.

- [ ] **Step 3: Implement the public policy**

Implement strict schema:

```json
{
  "allowed_bundle_identifiers": ["com.example.App"],
  "build_id_pattern": "^[0-9]+$",
  "key_id": "skb-integrity-fixture",
  "max_future_skew_seconds": 120,
  "max_request_age_seconds": 600,
  "public_key_sha256": "<fixture public key SHA-256>",
  "schema_version": 1
}
```

The production policy file must not exist until bootstrap. Policy validation rejects empty
allowlists, nonnumeric build patterns, invalid Key IDs, invalid SHA-256, nonpositive age, and
negative future skew.

- [ ] **Step 4: Implement stdin seed decoding and signing**

`SigningService.sign` must:

```swift
public func sign(
    requestData: Data,
    policyData: Data,
    privateKeyInput: Data,
    now: Date
) throws -> IntegritySignatureResponse
```

Accept either exactly 32 raw bytes or canonical Base64 text decoding to exactly 32 bytes.
Derive the public key, compare its SHA-256 to policy, validate request age and policy, sign
canonical request bytes, and return the exact ios-harden response fields:

```text
schema_version
request_sha256
key_id
public_key_sha256
signature_base64
```

- [ ] **Step 5: Add fixture and legacy public records**

Commit only the deterministic fixture seed. Add:

```json
{
  "revoked_key_ids": [
    "skb-integrity-prod-2026-01",
    "skb-integrity-prod-2026-02"
  ],
  "shared_public_key_sha256": "409c4c10066e349b5e30b368af22cd17a608e7f7cc98f4b0ff5dd84c04f47953"
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
swift test --filter SigningServiceTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests Fixtures Config
git commit -m "feat: add policy-bound Ed25519 signing"
```

## Task 3: Add the Stdin-Only Production CLI

**Files:**

- Modify: `Sources/ios-harden-actions-signer/main.swift`
- Create: `Tests/SigningControlCoreTests/CLITests.swift`
- Create: `Scripts/run_signer_sandboxed.sh`

- [ ] **Step 1: Write failing CLI tests**

Cover the exact command:

```text
ios-harden-actions-signer sign
  --policy /absolute/policy.json
  --request /absolute/request.json
  --response /absolute/response.json
  --private-key-stdin
```

Tests require an interactive-independent stdin read capped at 256 bytes, an absent response
destination, no private material on stdout/stderr, and stable nonzero exit status on failure.

- [ ] **Step 2: Verify tests fail**

Run:

```bash
swift test --filter CLITests
```

Expected: FAIL because the sign command is not implemented.

- [ ] **Step 3: Implement the command**

Parse only absolute paths with no `.` or `..` components. Read the seed from stdin once.
On success write only:

```json
{"key_id":"<id>","public_key_sha256":"<sha256>","request_sha256":"<sha256>","status":"signed"}
```

Never include `privateKeyInput` or its Base64 form in an error.

- [ ] **Step 4: Add the Seatbelt wrapper**

`Scripts/run_signer_sandboxed.sh` must require:

```text
POLICY_PATH
REQUEST_PATH
RESPONSE_PATH
SIGNER_PATH
```

Create a temporary Seatbelt profile that starts with `(deny default)`, explicitly denies
`network*`, allows reading the signer, policy, request, system libraries, and allows writing
only the response parent and `/dev/null`. Execute `/usr/bin/sandbox-exec` with the seed passed
only over stdin.

- [ ] **Step 5: Run all Swift tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests Scripts/run_signer_sandboxed.sh
git commit -m "feat: add stdin-only sandboxed signer CLI"
```

## Task 4: Create the Secret-Free Request Repository

**Files:**

- Create repository: `SoulmateL/ios-harden-signing-requests`
- Create: `README.md`
- Create: `.gitignore`
- Create: `requests/.gitkeep`
- Create: `responses/.gitkeep`
- Create: `Scripts/submit_request.sh`
- Create: `Scripts/fetch_response.sh`

- [ ] **Step 1: Create and clone the private repository**

Run:

```bash
gh repo create SoulmateL/ios-harden-signing-requests \
  --private \
  --description "Secret-free request and response transport for ios-harden signing" \
  --add-readme \
  --clone
```

Expected: repository URL and a local `ios-harden-signing-requests` clone.

- [ ] **Step 2: Add repository contract tests before scripts**

Create `Tests/request_repository_contract.sh` that fails unless:

- no `.github/workflows` directory exists;
- `.gitignore` blocks `*seed*`, `*.key`, `*.pem`, `*.p8`, `*.p12`, and `.env*`;
- only `requests/`, `responses/`, `Scripts/`, `Tests/`, README, and `.gitignore` are tracked.

Run:

```bash
bash Tests/request_repository_contract.sh
```

Expected: FAIL until the layout and ignore rules are added.

- [ ] **Step 3: Add layout and helpers**

`submit_request.sh` takes:

```text
--request /absolute/request.json
--source-revision <safe identifier>
```

It validates strict JSON through the control signer CLI, generates a lowercase UUID request ID,
copies the request to `requests/<id>/request.json`, and writes `summary.json` containing:

```json
{
  "bundle_identifier": "...",
  "build_id": "...",
  "key_id": "...",
  "request_id": "...",
  "request_sha256": "...",
  "source_revision": "..."
}
```

It commits and pushes without accepting seed input. `fetch_response.sh` copies only a strict
`responses/<id>/response.json`.

- [ ] **Step 4: Disable Actions**

Run:

```bash
gh api --method PUT repos/SoulmateL/ios-harden-signing-requests/actions/permissions \
  -F enabled=false
```

Expected: HTTP 204.

- [ ] **Step 5: Run contract and commit**

```bash
bash Tests/request_repository_contract.sh
git add README.md .gitignore requests responses Scripts Tests
git commit -m "feat: add secret-free signing request transport"
git push origin main
```

Expected: PASS and a pushed commit.

## Task 5: Connect the Repositories with a Dedicated Deploy Key

**Files:**

- Create locally: temporary deploy key pair under `mktemp -d`
- Create GitHub secret: `SIGNING_REQUESTS_DEPLOY_KEY`
- Modify remote repository: add write deploy key to `ios-harden-signing-requests`
- Create: `Scripts/verify_repository_settings.sh`

- [ ] **Step 1: Write the settings verification script**

The script uses `gh api` to assert:

- both repositories are private and owned by `SoulmateL`;
- request repository Actions are disabled;
- control repository has no collaborators other than owner;
- exactly one deploy key with title `ios-harden-signing-control` exists on request repository.

- [ ] **Step 2: Run it and confirm failure**

Run:

```bash
bash Scripts/verify_repository_settings.sh
```

Expected: FAIL because the deploy key does not exist.

- [ ] **Step 3: Generate and configure the deploy key**

Use `mktemp -d`, mode `0700`, and:

```bash
ssh-keygen -q -t ed25519 -N "" \
  -C "ios-harden-signing-control" \
  -f "$temporary_directory/requests-deploy-key"
```

Add the public key to only `SoulmateL/ios-harden-signing-requests` with write permission.
Pipe the private key directly to:

```bash
gh secret set SIGNING_REQUESTS_DEPLOY_KEY \
  --repo SoulmateL/ios-harden-signing-control
```

Remove the temporary directory after both operations succeed.

- [ ] **Step 4: Verify settings**

Run:

```bash
bash Scripts/verify_repository_settings.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Scripts/verify_repository_settings.sh
git commit -m "test: verify signing repository isolation"
git push origin main
```

## Task 6: Add CI and the Owner-Only Signing Workflow

**Files:**

- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/sign-request.yml`
- Create: `Scripts/publish_response.sh`
- Create: `Scripts/validate_repository.sh`
- Create: `Tests/workflow_contract_test.sh`

- [ ] **Step 1: Write failing workflow contract tests**

The test requires:

- `workflow_dispatch` inputs `request_id` and `request_sha256`;
- job guard `github.actor == 'SoulmateL'`;
- job guard `vars.PRODUCTION_READY == 'true'`;
- exact permissions `contents: read`;
- a pinned full commit SHA for `actions/checkout`;
- no `pull_request_target`;
- no third-party action after seed injection;
- step-level use of `IOS_HARDEN_ED25519_SEED_B64`;
- response push through `SIGNING_REQUESTS_DEPLOY_KEY`;
- no production fallback.

- [ ] **Step 2: Verify the contract fails**

Run:

```bash
bash Tests/workflow_contract_test.sh
```

Expected: FAIL because workflows do not exist.

- [ ] **Step 3: Add CI**

CI runs on pull requests and main pushes:

```text
swift test
bash Tests/workflow_contract_test.sh
bash Scripts/validate_repository.sh
```

`validate_repository.sh` scans tracked files and Git history for prohibited private-key headers,
production seed labels, and the known fixture seed outside `Fixtures/`.

- [ ] **Step 4: Add production signing workflow**

The workflow:

1. verifies owner actor and `PRODUCTION_READY`;
2. validates both inputs with anchored regular expressions;
3. builds the signer before exposing the seed;
4. installs the requests deploy key with `IdentitiesOnly yes`;
5. clones the request repository;
6. checks the supplied SHA-256 against exact canonical request bytes;
7. rejects an existing response;
8. invokes `run_signer_sandboxed.sh` with the seed at step scope;
9. commits `response.json` and public `audit.json`;
10. pushes to request repository main.

- [ ] **Step 5: Add fixture workflow validation**

Run the production workflow contract tests and a local fixture sign:

```bash
bash Tests/workflow_contract_test.sh
printf '%s' "$(tr -d '\n' < Fixtures/fixture-seed.b64)" |
  .build/debug/ios-harden-actions-signer sign \
    --policy "$PWD/Config/fixture-policy.json" \
    --request "$PWD/Fixtures/request.json" \
    --response "$PWD/.build/fixture-response.json" \
    --private-key-stdin
```

Expected: PASS and a valid fixture response.

- [ ] **Step 6: Commit and push**

```bash
git add .github Scripts Tests
git commit -m "feat: add owner-only GitHub signing workflow"
git push origin main
```

## Task 7: Add Production Bootstrap Without Executing It

**Files:**

- Create: `Scripts/bootstrap_production.sh`
- Create: `Scripts/verify_encrypted_recovery_volume.sh`
- Create: `docs/PRODUCTION_BOOTSTRAP.md`
- Create: `Tests/bootstrap_contract_test.sh`

- [ ] **Step 1: Write failing bootstrap contract tests**

Require the bootstrap script to:

- demand exact repository `SoulmateL/ios-harden-signing-control`;
- demand Key ID `skb-integrity-prod-2026-03`;
- verify an attached encrypted APFS volume;
- generate 32 bytes from `/usr/bin/openssl rand`;
- write GitHub Secret only through stdin;
- create `Config/production-policy.json` with derived public fingerprint;
- write one recovery copy only to the mounted encrypted volume;
- never print or pass seed as an argument;
- leave `PRODUCTION_READY` false.

- [ ] **Step 2: Verify the contract fails**

Run:

```bash
bash Tests/bootstrap_contract_test.sh
```

Expected: FAIL because bootstrap scripts do not exist.

- [ ] **Step 3: Implement encrypted volume validation**

`verify_encrypted_recovery_volume.sh` must call `diskutil info -plist`, parse with `plutil`,
and require:

```text
Mounted = true
Writable = true
FilesystemType = apfs
Encryption = true
```

Reject `/`, `$HOME`, the repository, and any non-removable target.

- [ ] **Step 4: Implement the owner-attended bootstrap**

The script refuses noninteractive execution. It uses a `mktemp -d` directory with mode `0700`,
creates a mode `0600` seed file, derives the public key through the signer, writes the repository
secret through stdin, writes the recovery file to the encrypted volume, creates the public policy,
syncs, and removes the temporary directory. It does not set `PRODUCTION_READY`.

- [ ] **Step 5: Run tests without a production seed**

Run:

```bash
bash Tests/bootstrap_contract_test.sh
```

Expected: PASS. Do not run `Scripts/bootstrap_production.sh`.

- [ ] **Step 6: Commit**

```bash
git add Scripts docs Tests
git commit -m "feat: add gated production key bootstrap"
git push origin main
```

## Task 8: End-to-End Fixture Verification

**Files:**

- Create: `Scripts/run_fixture_e2e.sh`
- Create: `Evidence/fixture-e2e/.gitkeep`
- Modify: `README.md`

- [ ] **Step 1: Write the end-to-end script**

The script creates a fresh fixture request ID, writes it into the local request-repository clone,
signs it with the committed fixture seed under Seatbelt, publishes the response, verifies the
signature with the fixture public key, and writes a redacted receipt containing only hashes.

- [ ] **Step 2: Run local end-to-end verification**

Run:

```bash
bash Scripts/run_fixture_e2e.sh \
  --requests-repo ../ios-harden-signing-requests
```

Expected: PASS and no production secret.

- [ ] **Step 3: Run complete verification**

Run:

```bash
swift test
bash Tests/workflow_contract_test.sh
bash Tests/bootstrap_contract_test.sh
bash Scripts/validate_repository.sh
bash Scripts/verify_repository_settings.sh
git diff --check
git status --short
```

Expected: all tests PASS and only the intended receipt/README changes remain.

- [ ] **Step 4: Update README**

Document the phone workflow:

```text
Open request summary -> copy request ID and SHA-256 ->
open Actions in ios-harden-signing-control -> Run workflow ->
verify response in ios-harden-signing-requests.
```

State clearly that production is disabled until encrypted USB bootstrap and separate release
authorization.

- [ ] **Step 5: Commit and push**

```bash
git add README.md Scripts/run_fixture_e2e.sh Evidence
git commit -m "test: verify fixture signing control end to end"
git push origin main
```

## Task 9: Production Gate Handoff

**Files:**

- Modify after attended bootstrap: `Config/production-policy.json`
- Create after attended bootstrap: `Evidence/production-bootstrap/public-receipt.json`
- GitHub Secret after attended bootstrap: `IOS_HARDEN_ED25519_SEED_B64`
- GitHub variable after all external verifier changes: `PRODUCTION_READY=true`

- [ ] **Step 1: Stop at the attended gate**

Report:

```text
Code and fixture verification complete.
No production seed generated.
Encrypted APFS recovery volume and owner presence required.
```

- [ ] **Step 2: Perform bootstrap only with owner present**

Run the documented bootstrap with the owner-unlocked encrypted APFS volume. Verify the printed
public Key ID and fingerprint only; never display seed.

- [ ] **Step 3: Verify the new key**

Submit one non-production request using Key ID `skb-integrity-prod-2026-03`, sign through the
manual workflow, and verify the response with the new public key.

- [ ] **Step 4: Keep production disabled**

Do not set `PRODUCTION_READY=true` until external RuntimeGuard/App verification trusts the new
public key and revokes both legacy Key IDs. This repository does not modify company code or
perform App Store actions.
