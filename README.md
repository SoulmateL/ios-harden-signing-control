# ios-harden-signing-control

`ios-harden` 的所有者审批式 GitHub Actions 签名控制面。它与无秘密请求仓库
`SoulmateL/ios-harden-signing-requests` 配合使用，不连接、不修改任何公司仓库。

当前状态：

- Swift/CryptoKit Ed25519 signer、严格请求协议和 Seatbelt 断网沙箱已实现；
- 请求仓库不保存 Secret，并已关闭 Actions；
- 生产工作流只允许 `SoulmateL` 手动触发；
- `PRODUCTION_READY=false`，没有生成生产 seed；
- 仓库只包含明确标注的公开 fixture seed，用于自动测试。

## 手机审批

团队成员提交请求后，所有者在手机上：

1. 打开请求仓库中的 `summary.json`；
2. 核对 Bundle ID、build ID、request ID 和 request SHA-256；
3. 打开控制仓库的 Actions 页面，选择 `Sign ios-harden request`；
4. 输入 request ID 和 request SHA-256，手动运行；
5. 回到请求仓库查看并验签 `response.json`。

如果所有者未批准、GitHub 免费额度不足、请求被改动、响应已存在或任何检查失败，
流程都会停止，不会回退到旧 Mac 密钥。

## 本地 fixture 验证

```bash
bash Scripts/run_fixture_e2e.sh \
  --requests-repo ../ios-harden-signing-requests
```

此命令只使用公开测试 seed，在本地临时 Git 仓库中完成端到端演练，不会调用生产
工作流或修改远端请求仓库。

## 生产门禁

生产初始化说明见
[生产密钥人工初始化](docs/PRODUCTION_BOOTSTRAP.md)。初始化完成后仍需先让 App 信任
新公钥，并同时撤销旧 Key ID `skb-integrity-prod-2026-01` 和
`skb-integrity-prod-2026-02`。在这些外部工作完成前，不得启用生产签名。

完整设计见
[GitHub Actions 中央签名控制设计](docs/superpowers/specs/2026-07-28-ios-harden-github-actions-signing-control-design.md)。
