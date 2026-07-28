#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd -P)"
ci_workflow="$repository_root/.github/workflows/ci.yml"
sign_workflow="$repository_root/.github/workflows/sign-request.yml"
publisher="$repository_root/Scripts/publish_response.sh"
scanner="$repository_root/Scripts/validate_repository.sh"

test -f "$ci_workflow"
test -f "$sign_workflow"
test -f "$publisher"
test -f "$scanner"
bash -n "$publisher"
bash -n "$scanner"
grep -Fq 'push origin HEAD:main' "$publisher"
grep -Fq 'git rev-list --all' "$scanner"

/usr/bin/ruby --disable-gems - "$ci_workflow" "$sign_workflow" <<'RUBY'
require "yaml"

ci = YAML.safe_load(File.read(ARGV[0]), aliases: false)
sign = YAML.safe_load(File.read(ARGV[1]), aliases: false)

def assert(condition, message)
  raise message unless condition
end

dispatch = sign.dig("on", "workflow_dispatch")
assert(dispatch.is_a?(Hash), "生产签名必须由 workflow_dispatch 手动触发")
inputs = dispatch.fetch("inputs", {})
assert(inputs.key?("request_id"), "缺少 request_id 输入")
assert(inputs.key?("request_sha256"), "缺少 request_sha256 输入")
assert(sign["permissions"] == {"contents" => "read"}, "生产工作流权限必须精确为 contents: read")

jobs = sign.fetch("jobs")
assert(jobs.length == 1, "生产工作流只能有一个 job")
job = jobs.values.first
guard = job.fetch("if", "")
assert(guard.include?("github.actor == 'SoulmateL'"), "缺少所有者 guard")
assert(guard.include?("vars.PRODUCTION_READY == 'true'"), "缺少生产就绪 guard")
assert(guard.include?("github.ref == 'refs/heads/main'"), "生产签名只能从 main 运行")
assert(job["timeout-minutes"] == 10, "生产签名 job 必须有 10 分钟超时")

steps = job.fetch("steps")
checkout_steps = steps.select { |step| step.key?("uses") }
assert(!checkout_steps.empty?, "缺少 checkout")
checkout_steps.each do |step|
  assert(
    step["uses"].match?(/\Aactions\/checkout@[0-9a-f]{40}\z/),
    "所有 Action 必须固定到完整 commit SHA"
  )
end

seed_index = steps.index do |step|
  step.fetch("env", {}).key?("IOS_HARDEN_ED25519_SEED_B64")
end
assert(!seed_index.nil?, "缺少 step 级 seed 注入")
seed_step = steps.fetch(seed_index)
assert(
  seed_step.fetch("run", "").include?("run_signer_sandboxed.sh"),
  "seed 只能交给沙箱签名器"
)
assert(
  steps[(seed_index + 1)..].none? { |step| step.key?("uses") },
  "seed 注入后不得运行第三方 Action"
)

workflow_text = File.read(ARGV[1])
assert(workflow_text.include?("SIGNING_REQUESTS_DEPLOY_KEY"), "缺少请求仓库 deploy key")
assert(workflow_text.include?("publish_response.sh"), "缺少响应发布步骤")
assert(!workflow_text.include?("pull_request_target"), "禁止 pull_request_target")
assert(!workflow_text.match?(/fallback|fixture-seed|old[_ -]?key/i), "生产工作流禁止回退密钥")

ci_text = File.read(ARGV[0])
assert(!ci_text.include?("pull_request_target"), "CI 禁止 pull_request_target")
assert(ci_text.include?("swift test"), "CI 必须运行 Swift 测试")
assert(ci_text.include?("workflow_contract_test.sh"), "CI 必须检查工作流契约")
assert(ci_text.include?("bootstrap_contract_test.sh"), "CI 必须检查生产 bootstrap 契约")
assert(ci_text.include?("fixture_e2e_contract_test.sh"), "CI 必须检查 fixture 端到端契约")
assert(ci_text.include?("validate_repository.sh"), "CI 必须扫描仓库")

puts "GitHub Actions 工作流契约检查通过"
RUBY
