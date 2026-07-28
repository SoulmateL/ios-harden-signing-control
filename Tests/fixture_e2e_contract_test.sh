#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
runner="$repository_root/Scripts/run_fixture_e2e.sh"
readme="$repository_root/README.md"

test -f "$runner"
bash -n "$runner"
grep -Fq -- '--requests-repo' "$runner"
grep -Fq 'clone --bare' "$runner"
grep -Fq 'Scripts/submit_request.sh' "$runner"
grep -Fq 'Scripts/fetch_response.sh' "$runner"
grep -Fq 'Fixtures/fixture-seed.b64' "$runner"
grep -Fq 'run_signer_sandboxed.sh' "$runner"
grep -Fq 'publish_response.sh' "$runner"
grep -Fq 'verify-response' "$runner"
grep -Fq 'Evidence/fixture-e2e/last-run.json' "$runner"

grep -Fq '手机审批' "$readme"
grep -Fq 'PRODUCTION_READY=false' "$readme"
grep -Fq '没有生成生产 seed' "$readme"

echo "fixture 端到端契约检查通过"
