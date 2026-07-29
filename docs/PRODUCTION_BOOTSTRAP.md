# 生产密钥人工初始化

此步骤会生成真实生产 seed。日常开发、CI 和 fixture 验证都不得执行它。

## 前置条件

- GitHub 当前登录用户是 `SoulmateL`；
- 本仓库远端是 `SoulmateL/ios-harden-signing-control`；
- GitHub Actions 的付费超额已关闭，账号级 Actions 预算为 0；
- 私有请求仓库 `SoulmateL/ios-harden-signing-requests` 的本地 `main` 分支干净且已同步；
- iPhone“密码”App 已建立 `skb-integrity-prod-2026-03 recovery` 条目，并使用自动生成的
  独立高强度密码；
- 真实 App Bundle ID；
- 已通过全部测试的 release signer 绝对路径；
- 通过仓库脚本安装并验证的固定 `age v1.3.1` 绝对路径。

不要在聊天、Issue、README、截图或命令参数中提供 seed、私钥或恢复密码。
当前自动化使用的 GitHub 权限不能读取个人账单设置，因此预算状态必须由所有者在
GitHub Billing 页面现场核对；没有确认时不要继续。
脚本会先检查控制仓库的公开状态、唯一协作者、Action SHA 固定、Secret 扫描和
push protection，并检查请求仓库为私有且 Actions 关闭；任一检查失败时不会生成
seed。

## 现场执行

先安装固定版本的免费加密工具，再构建并验证：

```bash
Scripts/install_pinned_age.sh \
  --destination "$PWD/.tools/age-v1.3.1"
swift build -c release
swift test
bash Tests/age_tool_contract_test.sh
bash Tests/recovery_roundtrip_test.sh \
  --age "$PWD/.tools/age-v1.3.1/age"
bash Tests/bootstrap_contract_test.sh
bash Tests/restore_secret_contract_test.sh
```

在 iPhone“密码”App 中确认恢复密码条目已经存在。密码必须是自动生成且只用于这一个
条目，不能使用 Apple ID、GitHub 或其他网站的密码。

所有者在 Mac 交互终端运行：

```bash
Scripts/bootstrap_production.sh \
  --requests-repo /绝对路径/ios-harden-signing-requests \
  --bundle-identifier com.yourcompany.App \
  --signer "$PWD/.build/release/ios-harden-actions-signer" \
  --age "$PWD/.tools/age-v1.3.1/age"
```

`age` 会在隐藏终端提示中要求输入并确认恢复密码，然后再次输入一次完成现场解密
校验。密码不会显示，也不会进入 shell history。不要把密码作为命令参数或环境变量。

脚本只会显示 Key ID、新公钥和公钥 SHA-256，不会显示 seed。它会：

1. 验证两个仓库和固定 `age` 工具；
2. 把 `PRODUCTION_READY` 明确保持为 `false`；
3. 生成 `skb-integrity-prod-2026-03` 的 32 字节随机 seed；
4. 加密 seed，并立即解密后逐字节比较；
5. 只把 `Recovery/skb-integrity-prod-2026-03.age` 密文提交并推送到私有请求仓库；
6. 只有密文推送成功后，才通过 stdin 写入控制仓库 Secret；
7. 生成公开的生产策略和公开收据，并清理临时明文。

私有仓库成员即使克隆了 `.age` 文件，没有 iPhone 中的独立恢复密码也不能直接使用
seed。以后移除成员不会删除其本地密文副本，因此不能把仓库成员权限当作密文撤销。

## 审查并发布公开配置

脚本不会替你提交公开生产配置。确认终端只显示新的 Key ID、公钥和公钥指纹后，
审查并推送这两个不含 seed 的文件：

```bash
jq . Config/production-policy.json
jq . Evidence/production-bootstrap/public-receipt.json
git add Config/production-policy.json Evidence/production-bootstrap/public-receipt.json
git diff --cached
git commit -m "feat: publish production signing public key"
git push origin main
```

然后把已审查的 `ios-harden` 完整 40 位 commit 写入公开变量：

```bash
gh variable set APPROVED_IOS_HARDEN_REVISION \
  --body <40位小写commit> \
  --repo SoulmateL/ios-harden-signing-control
```

没有完成上述推送和 revision 设置时，生产工作流必须失败关闭。

## 从密文恢复 Secret

只有 GitHub Secret 丢失或仓库迁移时才运行恢复脚本：

```bash
Scripts/restore_production_secret.sh \
  --requests-repo /绝对路径/ios-harden-signing-requests \
  --signer "$PWD/.build/release/ios-harden-actions-signer" \
  --age "$PWD/.tools/age-v1.3.1/age"
```

脚本会从 iPhone 密码解开固定 `.age` 文件、重新派生并核对公钥指纹、先把
`PRODUCTION_READY` 设为 `false`，再通过 stdin 恢复 Secret。它不会自动启用生产签名。

如果恢复密码丢失或密文损坏，不从日志、Actions 制品或同事电脑寻找 seed；应创建
新 Key ID、新 seed 和新公钥，并重新执行 App 信任轮换。

## 执行后仍不能上线

初始化完成不等于旧电脑立即失效。还必须在 App 的验证端：

- 信任新公钥；
- 同时撤销 `skb-integrity-prod-2026-01` 和
  `skb-integrity-prod-2026-02`；
- 发布并验证过渡版本；
- 用新 Key ID 完成非生产签名演练。

只有这些外部验证完成并单独授权后，才可把 `PRODUCTION_READY` 改为
`true`。本仓库不会修改公司代码、删除 Mac 钥匙串项目或上传 App Store。
