# ios-harden GitHub Actions 中央签名控制设计

日期：2026-07-28

## 1. 目标

建立一个不需要自建服务器、由 `SoulmateL` 使用手机审批、使用 GitHub
免费额度运行的 Ed25519 中央签名流程。新的生产 seed 不再导入团队 Mac，
团队成员只能提交签名申请，不能取得或直接使用 seed。

本设计解决以下问题：

- 从 GitHub 请求仓库移除成员后，该成员不能再提交新的有效签名申请。
- 只有 `SoulmateL` 能启动生产签名。
- GitHub 仓库、日志、制品和业务仓库中不出现 seed。
- 旧 Mac 中已经导入的历史密钥通过新 App 的信任配置统一撤销。
- GitHub 免费额度耗尽、审批缺失、输入异常或依赖不可用时失败关闭。

## 2. 已确认事实

- GitHub 控制仓库是公开仓库
  `SoulmateL/ios-harden-signing-control`，以使用免费的标准 GitHub 托管 runner。
  它只公开可审查的代码、工作流、公开策略和 fixture；生产 seed 与部署私钥仅保存在
  GitHub Secret。
- 团队请求使用独立私有仓库
  `SoulmateL/ios-harden-signing-requests`。
- 两个仓库都属于个人 GitHub 账号 `SoulmateL`，不连接、不修改、不依赖任何
  公司 GitHub 或 GitLab 仓库。
- 唯一生产审批人是 GitHub 用户 `SoulmateL`。
- 历史 Key ID `skb-integrity-prod-2026-01` 和
  `skb-integrity-prod-2026-02` 对应同一个公钥 SHA-256：
  `409c4c10066e349b5e30b368af22cd17a608e7f7cc98f4b0ff5dd84c04f47953`。
  两个历史 Key ID 都按旧钥匙处理。
- 新生产 Key ID 固定为 `skb-integrity-prod-2026-03`，必须对应全新的 seed
  和全新的公钥指纹。
- 恢复副本使用私有请求仓库中的 `age` 认证加密文件；解密密码只保存在所有者的
  iPhone“密码”App，不进入仓库、聊天、截图或命令参数。

## 3. 非目标

- 不让 GitHub 仓库保存可读取的 seed 文件。
- 不允许团队成员直接运行生产签名。
- 不从 GitHub Actions 回显、导出或下载 seed。
- 不在失败时回退到旧 Mac 密钥、夹具密钥或无签名发布。
- 不自动上传 App Store Connect、提交审核、创建业务 Tag 或执行生产发布。
- 不在没有所有者现场确认、iPhone 独立恢复密码和私有仓库安全检查的情况下生成
  生产 seed。

## 4. 总体架构

系统使用两个 GitHub 仓库：一个公开控制仓库和一个私有请求仓库。

1. `ios-harden-signing-requests`
   - 团队成员可以提交请求和读取签名结果。
   - 保存严格 JSON 请求、响应、非秘密审计元数据和一个 `.age` 加密恢复副本。
   - 解密密码不进入 GitHub；仓库成员只能取得密文。
   - 不保存 GitHub Actions seed，不运行持有生产秘密的工作流。
2. `ios-harden-signing-control`
   - 公开读取；只有 `SoulmateL` 拥有写入和 Actions 手动触发权限。
   - 保存经过审查的签名工作流、策略、公钥和工具版本锁定信息。
   - 使用 GitHub Actions Secret 保存生产 seed。
   - 使用专用部署密钥读写请求仓库。

调用方在本地生成 ios-harden 签名请求后，只把单个请求上传到个人请求仓库。
调用方源码、公司仓库地址、发布脚本和业务凭据不进入这两个个人仓库。

数据流：

1. 需要签名的 Mac 使用固定 revision 的 `ios-harden` 生成签名请求。
2. 上传工具把请求写入
   `requests/<request-id>/request.json`。
3. `SoulmateL` 在手机浏览器中打开控制仓库，输入 `request-id` 并手动运行工作流。
4. 工作流先在不接触 seed 的步骤中读取、规范化和验证请求。
5. 验证通过后，隔离签名步骤从标准输入读取 GitHub Secret，生成响应。
6. 响应写入
   `responses/<request-id>/response.json`，同时写入不含秘密的审计记录。
7. 业务流水线验证响应、公钥、请求摘要和 Key ID 后才完成 manifest。

## 5. 权限模型

- 控制仓库公开读取、不添加协作者，只有所有者 `SoulmateL` 可写入或手动触发工作流。
- 控制仓库强制 Action 使用固定 SHA，并启用 GitHub Secret 扫描与 push protection。
- 请求仓库成员权限决定谁能提交请求。
- 从请求仓库移除成员后，该成员不能推送新请求。
- 签名工作流只能由控制仓库所有者手动触发。
- 请求仓库启用 Actions 禁用策略，不允许其中的成员创建读取生产秘密的工作流。
- 控制仓库使用一把只绑定请求仓库的专用部署密钥。部署私钥只进入控制仓库
  Secret，不复用个人 SSH 密钥或当前 `gh` 登录令牌。
- 请求仓库中的响应即使被成员修改，也会因 Ed25519 验签或请求摘要不匹配而失败。

## 6. 请求协议与审批

请求继续使用 `ios-harden` 已有严格签名请求协议，并补充外层传输元数据：

- `request_id`：随机 UUID，小写规范形式。
- `source_revision`：调用方提供的来源 revision，仅用于审计，不绑定任何公司仓库。
- `ios_harden_revision`：生成请求的工具 commit。
- `request_sha256`：规范请求 JSON 的 SHA-256。
- `submitted_by`：提交者 GitHub 登录名，仅作审计，不参与密码学信任。
- `submitted_at_epoch_seconds`：提交时间。

生产策略继续校验：

- Key ID 必须等于 `skb-integrity-prod-2026-03`。
- Bundle ID 必须在批准列表中。
- build ID 必须符合数字格式。
- 请求年龄不得超过 600 秒。
- 请求摘要、manifest 摘要和响应中的公钥必须一致。
- 同一 `request-id` 已存在响应时拒绝再次签名。
- 控制工作流触发者必须精确等于 `SoulmateL`。

手机审批页面必须显示 Bundle ID、版本、build ID、业务 revision、请求摘要和提交者，
不显示 seed 或其他秘密。

## 7. Actions 签名执行

签名任务使用公开控制仓库中的标准 GitHub 托管 macOS runner 和系统 CryptoKit。
公开仓库的标准 runner 按 GitHub 规则免费；不得切换到收费的大型 runner。任何
runner 不可用或审批检查失败时停止，不启用付费超额。

production bootstrap 在生成 seed 前必须验证控制仓库的公开状态、唯一协作者、Action
SHA 固定、Secret 扫描和 push protection；任何设置回退都必须失败关闭。

控制仓库提供一个无第三方依赖的短生命周期 signer：

- 不修改现有 macOS Keychain signer，也不读取任何本机钥匙串。
- seed 只通过标准输入传入，不接受命令参数、文件路径或普通环境输出。
- 使用与 ios-harden 相同的请求规范化和 Ed25519 响应协议。
- 策略、公钥指纹、Bundle ID 和工具 revision 继续失败关闭。
- 使用系统 CryptoKit，避免引入新的密码学包和跨平台兼容层。

持有 seed 的签名步骤必须满足：

- 只调用已验证 SHA-256 的 signer 制品。
- signer 在 Seatbelt 沙箱中运行，默认拒绝并显式禁止网络，只允许读取签名器、策略和
  请求，只允许写入响应临时目录。
- 关闭 shell 跟踪和 core dump。
- 不在 seed 注入后运行第三方 Action、构建脚本或包管理器。
- 响应产生后立即结束沙箱进程；临时 runner 随任务销毁。

## 8. Secret 与恢复

控制仓库使用以下 Secret：

- `IOS_HARDEN_ED25519_SEED_B64`：严格 Base64 的 32 字节新 seed。
- `SIGNING_REQUESTS_DEPLOY_KEY`：仅绑定请求仓库的部署私钥。

生产 seed 的初始化必须在可信 Mac 上通过受审脚本完成：

1. 使用系统密码学随机源生成 32 字节 seed。
2. 本地派生公钥和公钥 SHA-256。
3. 使用固定 SHA-256 的 `age v1.3.1` 从交互终端读取 iPhone 中的恢复密码。
4. 加密 seed，再现场解密并逐字节比较。
5. 将唯一 `.age` 密文提交并推送到私有请求仓库。
6. 只有密文推送成功后，才通过标准输入写入 GitHub Secret。
7. 临时目录只允许位于 `mktemp -d` 创建的目录，结束时安全清理。
8. 输出只包含 Key ID、公钥和公钥指纹。

生产初始化前必须由 `SoulmateL` 从 iPhone“密码”App 取得独立恢复密码，并只在
`age` 的隐藏交互提示中输入。自动化不得通过参数、环境变量或普通文件接收、保存或
记录该密码。

## 9. 旧钥匙撤销与轮换

首次上线执行一次正式轮换：

1. 生成 `skb-integrity-prod-2026-03` 的全新 seed。
2. 在 App 的 RuntimeGuard 信任配置中加入新公钥。
3. 将 `skb-integrity-prod-2026-01` 和
   `skb-integrity-prod-2026-02` 同时加入 `revokedKeyIDs`。
4. 发布过渡版本并验证新签名。
5. 停止本地 Fastlane 使用旧 signer Key ID。
6. 在受控 Mac 上通过 Keychain UI 清理旧 service/account；该清理不是撤销的
   权威依据，权威依据仍是验证端拒绝旧 Key ID。

历史已发布 App 不会因仓库或 Secret 改动自动更新。生产发布、App Store 上传及撤销
生效范围必须在上线门禁中单独确认。

## 10. 审计

每次请求和响应保留以下非秘密信息：

- GitHub run ID、触发者和时间。
- request ID、request SHA-256 和 manifest SHA-256。
- Key ID 和公钥 SHA-256。
- Bundle ID、build ID、业务 revision 和 ios-harden revision。
- 结果状态与稳定错误码。
- signer 制品 SHA-256 和控制仓库 commit。

审计记录不得包含 seed、恢复副本、GitHub 令牌、部署私钥、Apple 凭据或完整环境变量。

## 11. 失败处理

- GitHub Actions 免费额度耗尽：停止签名，不启用付费超额。
- GitHub 不可用：等待恢复，不回退本地旧密钥。
- 请求过期：重新生成请求，不延长旧请求。
- 请求被修改：摘要不匹配，拒绝签名。
- 响应已存在：拒绝重放。
- Secret 缺失：失败关闭并提示执行正式轮换或恢复流程。
- 恢复密码丢失或 `.age` 密文损坏：不从日志或制品寻找 seed；生成新 Key ID 并
  重新轮换。
- signer、策略或工具 revision 不一致：拒绝签名。

## 12. 测试与验收

使用仓库夹具测试密钥完成全部自动测试，测试密钥不得进入生产 Secret。

必须覆盖：

- 所有者批准的合法请求成功。
- 非所有者不能触发生产签名。
- 请求过期、字段未知、Bundle ID 不允许、Key ID 错误均失败。
- 批准后修改请求导致摘要失败。
- 相同 request ID 不能再次签名。
- 响应可由 ios-harden 和 RuntimeGuard 使用新公钥验证。
- `2026-01` 与 `2026-02` 均返回 revoked key。
- Actions 日志、制品、缓存和 Git 历史不包含测试 seed 的 Base64 或原始字节。
- 签名 Seatbelt 沙箱无网络且仅允许必要文件访问。
- 请求仓库部署密钥不能访问其他仓库。
- 免费额度或依赖不可用时没有旧密钥回退。

## 13. 实施顺序

1. 在控制仓库实现请求校验、fixture signer、审计和测试。
2. 创建请求仓库并配置专用部署密钥。
3. 在控制仓库实现无第三方依赖的短生命周期 CryptoKit signer。
4. 使用 fixture key 完成双仓库端到端测试。
5. 提供独立的本地上传和响应读取工具，不修改任何公司仓库。
6. 完成旧 Key ID 撤销和新公钥的 App 过渡版本验证。
7. 所有者在 iPhone 保存独立恢复密码，现场执行私有仓库加密恢复初始化。
8. 完成真实新密钥演练，但不自动上传 App Store。
9. 经所有者单独授权后执行生产切换和发布。

## 14. 人工门禁

以下动作不能由后台自主执行：

- 生成并启用生产 seed。
- 写入或恢复私有仓库中的 `.age` 加密副本。
- 修改 App 的生产信任根并发布过渡版本。
- 上传 App Store Connect、提交审核或撤销线上发布。
- 删除任何现有 Mac 钥匙串项目。

在上述门禁前，仓库保持 fixture-only，生产签名关闭。
