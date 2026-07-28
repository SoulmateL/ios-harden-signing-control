# 生产密钥人工初始化

此步骤会生成真实生产 seed。日常开发、CI 和 fixture 验证都不得执行它。

## 前置条件

- GitHub 当前登录用户是 `SoulmateL`；
- 本仓库远端是 `SoulmateL/ios-harden-signing-control`；
- GitHub Actions 的付费超额已关闭，账号级 Actions 预算为 0；
- 一只由所有者现场解锁的、加密 APFS、可写且可移除的 U 盘；
- 真实 App Bundle ID；
- 已通过全部测试的 release signer 绝对路径。

不要在聊天、Issue、README、截图或命令参数中提供 seed、私钥、U 盘密码。
当前自动化使用的 GitHub 权限不能读取个人账单设置，因此预算状态必须由所有者在
GitHub Billing 页面现场核对；没有确认时不要继续。
脚本会先检查控制仓库的公开状态、唯一协作者、Action SHA 固定、Secret 扫描和
push protection；任一检查失败时不会生成 seed。

## 现场执行

先构建并验证：

```bash
swift build -c release
swift test
bash Tests/bootstrap_contract_test.sh
```

所有者连接并解锁加密 U 盘后，在交互终端运行：

```bash
Scripts/bootstrap_production.sh \
  --recovery-volume /Volumes/你的加密恢复卷 \
  --bundle-identifier com.yourcompany.App \
  --signer "$PWD/.build/release/ios-harden-actions-signer"
```

脚本只会显示 Key ID、新公钥和公钥 SHA-256，不会显示 seed。它会：

1. 把 `PRODUCTION_READY` 明确保持为 `false`；
2. 生成 `skb-integrity-prod-2026-03` 的 32 字节随机 seed；
3. 通过 stdin 写入控制仓库 Secret；
4. 在加密 U 盘写入唯一恢复副本；
5. 生成公开的生产策略和公开收据。
6. 同步并卸载加密恢复卷。

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

## 执行后仍不能上线

初始化完成不等于旧电脑立即失效。还必须在 App 的验证端：

- 信任新公钥；
- 同时撤销 `skb-integrity-prod-2026-01` 和
  `skb-integrity-prod-2026-02`；
- 发布并验证过渡版本；
- 用新 Key ID 完成非生产签名演练。

只有这些外部验证完成并单独授权后，才可把 `PRODUCTION_READY` 改为
`true`。本仓库不会修改公司代码、删除 Mac 钥匙串项目或上传 App Store。
