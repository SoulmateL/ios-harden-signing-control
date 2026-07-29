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
grep -Fq 'ios_harden_revision' "$publisher"
grep -Fq 'submitted_at_epoch_seconds' "$publisher"
grep -Fq 'submitted_by' "$publisher"
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
approved_checkout = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
checkout_steps.each do |step|
  assert(
    step["uses"] == approved_checkout,
    "checkout 必须固定到已审查的 actions/checkout v7.0.1 commit"
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
assert(workflow_text.include?("APPROVED_IOS_HARDEN_REVISION"), "缺少批准的 ios-harden revision")
assert(workflow_text.include?("shasum -a 256 -c"), "seed 注入前必须复核 signer 哈希")
assert(!workflow_text.include?("ssh-keyscan"), "禁止运行时获取 SSH host key")
assert(
  workflow_text.include?("AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"),
  "缺少 GitHub 官方 Ed25519 host key"
)
%w[bundle_identifier build_id manifest_sha256].each do |field|
  assert(workflow_text.scan(field).length >= 3, "审批摘要未绑定 #{field}")
end
assert(workflow_text.include?("submitted_by"), "审计缺少 submitted_by")
assert(workflow_text.include?("submitted_at_epoch_seconds"), "审计缺少提交时间")
assert(workflow_text.include?("publish_response.sh"), "缺少响应发布步骤")
assert(!workflow_text.include?("pull_request_target"), "禁止 pull_request_target")
assert(!workflow_text.match?(/fallback|fixture-seed|old[_ -]?key/i), "生产工作流禁止回退密钥")

ci_text = File.read(ARGV[0])
assert(!ci_text.include?("pull_request_target"), "CI 禁止 pull_request_target")
assert(ci_text.include?("swift test"), "CI 必须运行 Swift 测试")
assert(ci_text.include?("workflow_contract_test.sh"), "CI 必须检查工作流契约")
assert(ci_text.include?("age_tool_contract_test.sh"), "CI 必须检查固定 age 工具契约")
assert(ci_text.include?("bootstrap_contract_test.sh"), "CI 必须检查生产 bootstrap 契约")
assert(ci_text.include?("restore_secret_contract_test.sh"), "CI 必须检查生产 Secret 恢复契约")
assert(ci_text.include?("fixture_e2e_contract_test.sh"), "CI 必须检查 fixture 端到端契约")
assert(ci_text.include?("validate_repository.sh"), "CI 必须扫描仓库")

ci_steps = ci.fetch("jobs").values.first.fetch("steps")
age_install_index = ci_steps.index { |step| step["name"] == "Install pinned age" }
roundtrip_index = ci_steps.index { |step| step["name"] == "Test encrypted recovery round trip" }
assert(!age_install_index.nil?, "CI 缺少固定 age 安装步骤")
assert(!roundtrip_index.nil?, "CI 缺少加密恢复往返测试")
assert(age_install_index < roundtrip_index, "CI 必须先安装固定 age，再测试恢复密文")
assert(
  ci_steps.fetch(age_install_index).fetch("run", "").include?("install_pinned_age.sh"),
  "CI 必须通过受审安装脚本取得 age"
)
assert(
  ci_steps.fetch(roundtrip_index).fetch("run", "").include?("recovery_roundtrip_test.sh"),
  "CI 必须执行恢复密文往返测试"
)

puts "GitHub Actions 工作流契约检查通过"
RUBY
