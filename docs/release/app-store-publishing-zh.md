# MateDrive App Store 上架指南

本文是实际发布顺序。Apple 的界面和要求可能更新，上架时同时核对 App Store Connect 的最新提示。

## 当前发布状态

当前源代码和发布事实以 `docs/release/app-store-submission.md` 的 Build 19 记录为准。Build 18 已经上传，只保留为历史候选；Build 16 只保留为更早的历史证据。

已确认：

- Apple Developer 资格、Apple Development 与 Apple Distribution 证书。
- App、Widget、App Group 标识及 App Store Connect App 记录。
- 公开 HTTPS 支持页和隐私政策页。
- Build 19 已于 2026 年 8 月 10 日完成最新源码的本地 Release 归档和 Apple Distribution IPA 导出；归档位于 `/tmp/matedrive-build19-first-run-archive.n0nfPi/MateDrive.xcarchive`，IPA 位于 `/tmp/matedrive-build19-first-run-local-export.vYc1ry/MateDrive.ipa`，SHA-256 为 `725268453e6fa90ed7d802543002f3d6840b0ee82e41ffa615449ce70bc71664`。App 与 Widget 均为 `1.0 (19)`，签名、dSYM、IPA 完整性、调试权限关闭和归档审计全部通过，未执行上传或提交审核。
- Build 18 已于 2026 年 7 月 28 日上传 App Store Connect；本轮再次使用 18 时被 Apple 明确拒绝为重复构建号，因此当前候选递增为 Build 19。
- Build 19 最终源码已重新通过 1139 项完整单元回归（34 项外部环境用例按预期跳过）和 35 项完整界面回归，失败数为 0；界面回归已包含首次配置、验证失败后留在配置页并显示恢复建议、连接隐私安全的本地 TeslaMate HTTP 合成服务后进入稳定首页、终止并重启后保留原服务器地址、英语、繁体中文、横屏、无障碍大字体、四主页面系统无障碍扫描、断网缓存、错误重试和重复点击防重入。另有深色加高对比四主页面专项审计通过。
- 配对 iPhone 15 Pro Max 上的 Build 18 开发直装已由用户确认可以成功拉取真实数据，证明公网转发、认证、接口和 App 展示主链路可用；Build 19 仍需通过 TestFlight 安装验证，不能用开发直装替代分发包验收。
- `iCloud.com.matedrive.ios` 的 `MateDriveBackup` Schema 已部署到 CloudKit Production；生产环境已确认 15 个字段、`recordName` 查询索引和 `createdAt` 排序索引。
- 当前签名源码已在配对的 iPhone 15 Pro Max 上通过 CloudKit Production 上传、列表、下载字节校验、删除和测试记录清理闭环；结果保存在 `/tmp/MateDrive-CloudKitProductionPhysical-20260728-11.xcresult`。
- 当前技术审计、独立发布审计和归档资源检查无阻断项。
- Build 19 源码包含一级“支持与反馈”和“隐私政策”入口；发布脚本回归保护公开合成审核接口，并阻止其专用地址进入正式 App、Widget 和项目配置。三语完整性检查和 Release 归档均已通过。
- 公开只读的合成 TeslaMate API 已由 GitHub Actions 部署，运行 `30295441857` 成功；对应部署产物已通过原生 iOS 只读接口集成测试。2026 年 7 月 28 日已通过 Chrome 成功打开公开 HTTPS 根入口，并核对到“合成、只读、不含用户数据和凭据”的预期说明。
- App Store Connect 的简体中文宣传文本和描述已按当前产品状态完成同步并保存，已移除旧版车型图片、已删除卡片和未通过首发门禁的语言声明。
- 最终截图流水线已生成并人工复核 6 张 `1242x2688` 简体中文合成数据草稿；首次启动预热避免截到开屏或加载状态，尺寸、重复、空白和内容差异门禁均通过。首页、动态和功能页信息完整，选作首发素材；充电详情和电池页保留真实的缺失数据与校准状态，不纳入首发截图。
- 首页、动态和功能页三张截图已按顺序上传；审核登录已关闭，只读公开合成 API 的无认证操作步骤已写入审核备注。Build 19 上传并通过 TestFlight 真机验收后，才能选为 App Store 版本 1.0 的正式候选。
- 首发价格已设为免费，供应范围为全部 175 个国家或地区，年龄分级为 4+。
- App Privacy 已发布：披露“精确位置”由第三方天气服务用于 App 功能，不与身份关联，也不用于跟踪。

仍需完成：

1. 经用户明确授权后上传 Build 19，并实时核对其处理状态、TestFlight 可用性和 App Store 版本 1.0 的选中状态；本轮没有上传或提交审核。
2. 通过 TestFlight 在真实 iPhone 上安装 Build 19，完成候选构建、真实数据、离线、后台恢复、CloudKit 和隐私回归。
3. 为支持页提供一个可公开的支持邮箱或联系电话；不要未经确认公开私人邮箱。
4. 填写准确的审核联系人名字、姓氏、电话和邮箱，并由账户持有人确认第三方内容版权声明。
5. 由账户持有人完成欧盟《数字服务法》交易商或非交易商声明；若选择交易商，Apple 会要求验证并公开地址、电话和邮箱。当前免费首发不需要签署付费 App 协议。
6. App 辅助功能产品页标签暂不发布。最终大字体核查已修复电池指标卡图标与标题重叠、动态会话时间裁切，并移除对应的应用内容裁切豁免；但 iOS 26.5 模拟器的 Dynamic Type 类别和系统或视口边缘误报仍有文档化过滤，尚不能对外宣称整套 App 全面支持大字体等能力。

## 1. Apple 开发者准备

1. 使用将长期持有应用的 Apple 账号加入 Apple Developer Program。
2. 在 Xcode `Settings > Accounts` 登录该账号。
3. 在 Apple Developer 的 Certificates, Identifiers & Profiles 中创建或确认：
   - App ID：`com.matedrive.ios`
   - Widget App ID：`com.matedrive.ios.widget`
   - App Group：`group.com.matedrive.ios`
4. 如标识已被占用，先在 `project.yml`、entitlements 和后台任务标识中统一更换，再生成工程和归档。

## 2. 创建 App Store Connect 记录

在 App Store Connect 的 Apps 页面点击 `+ > New App`：

- Platform：iOS
- Name：MateDrive
- Primary Language：Simplified Chinese 或计划维护的主语言
- Bundle ID：与签名 App ID 完全一致
- SKU：内部唯一值，例如 `matedrive-ios-001`
- User Access：按团队需要设置

Apple 要求先创建 App 记录，再上传构建；账号持有人还需先接受最新协议。

## 3. 完成元数据和公开页面

以 `docs/release/app-store-submission.md` 为发布事实来源，填写：

- 名称、副标题、描述、关键词和宣传文本。
- 分类、年龄分级、版权信息、价格和销售地区。
- 支持 URL：`https://youyooo.github.io/MateDrive/`
- 隐私政策 URL：`https://youyooo.github.io/MateDrive/privacy.html`
- App Privacy 问卷、出口合规和内容权利声明。
- 审核备注和公开合成 TeslaMate API 地址；认证方式选择“无”。

正式 App 不内置审核地址；用户仍连接自己的 TeslaMate。截图不得出现私人服务器、Token、VIN、家庭/工作地点或真实行程轨迹。

## 4. 发布前验证

```bash
make preflight
make verify
make release-technical-gate
make app-store-audit
```

再对审核测试服务器执行：

```bash
MATEDRIVE_INTEGRATION_BASE_URL=https://youyooo.github.io/MateDrive/review-demo \
make review-integration-test
```

必须在真实 iPhone 上验证语言、单位、费用、电池、行程能耗、地图、离线状态、Widget 和异常提示。

## 5. 归档并上传

仅生成本地 Apple Distribution IPA 进行验证时，使用 `docs/release/AppStoreLocalExportOptions.plist`，它不会上传。`docs/release/AppStoreExportOptions.plist` 的目标是上传，只有得到用户明确授权后才能使用。

1. 在 `project.yml` 更新 `MARKETING_VERSION` 和递增 `CURRENT_PROJECT_VERSION`。
2. 重新运行 `xcodegen generate`。
3. Xcode 选择 `Any iOS Device (arm64)` 和 `MateDrive` scheme。
4. 执行 `Product > Archive`。
5. 在 Organizer 中选择归档，运行 `Validate App`。
6. 选择 `Distribute App > App Store Connect > Upload`，使用自动签名上传。
7. 等待 App Store Connect 处理完成；Bundle ID、版本号和 Build 号会把构建关联到对应 App 版本。

## 6. TestFlight

1. 先添加内部测试人员，完成完整真实数据回归。
2. 需要外部测试时，填写 Beta App Review 信息并提交 TestFlight 审核。
3. 收集崩溃、连接失败、数据缺失和本地化问题，修复后递增 Build 号重新上传。

## 7. 提交审核

1. 在 App 版本页选择正确构建。
2. 检查所有必填元数据、截图、隐私和审核联系信息。
3. 点击 `Add for Review`。
4. 进入 Draft Submission，点击 `Submit for Review`。
5. 审核期间保持 GitHub Pages 合成数据入口可用，及时回复 App Review 消息。
6. 发布方式建议首版选择手动发布。

## 8. 每次更新

- 每个上传构建使用新的 Build 号。
- 每次发布重新运行四个发布门禁和真实 API 测试。
- 同步更新公开源码对应 tag，确保用户能取得与商店二进制匹配的完整源代码。
- 更新隐私政策、审核说明、截图和 `NOTICE.md` 中发生变化的内容。
