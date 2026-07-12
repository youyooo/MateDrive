# MateDrive App Store 上架指南

本文是实际发布顺序。Apple 的界面和要求可能更新，上架时同时核对 App Store Connect 的最新提示。

## 当前发布阻塞项

1. 加入 Apple Developer Program，并在本机创建有效的 Apple Development 与 Apple Distribution 签名能力。
2. 确认最终 Bundle ID、App Group、开发团队和 App Store 名称可用。
3. 准备 App Review 可访问的临时 TeslaMate API 测试服务器，私下提供临时凭据，审核后撤销。
4. 使用真实车辆数据完成真机回归、TestFlight 内测和隐私检查。
5. 处理 GPLv3 与 App Store 分发条款：本项目是 GPLv3 跨语言重写并包含受其覆盖的素材。提交商店前应取得相关原权利人的书面 App Store 额外许可或双重许可，并让熟悉开源许可的专业人士确认发布方案。仅公开 GitHub 源码不能自动解决商店附加条款风险。

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
- 审核备注、临时 TeslaMate API 地址和临时认证凭据。

审核凭据只填 App Store Connect，不提交 GitHub。截图不得出现私人服务器、Token、VIN、家庭/工作地点或真实行程轨迹。

## 4. 发布前验证

```bash
make preflight
make verify
make release-technical-gate
make app-store-audit
```

再对审核测试服务器执行：

```bash
MATEDRIVE_INTEGRATION_BASE_URL=https://你的审核服务器 \
MATEDRIVE_INTEGRATION_API_TOKEN=临时令牌 \
make integration-test
```

必须在真实 iPhone 上验证语言、单位、费用、电池、行程能耗、地图、离线状态、Widget 和异常提示。

## 5. 归档并上传

1. 在 `MateDroidIOS/Info.plist` 更新 `CFBundleShortVersionString` 和递增的 `CFBundleVersion`。
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
5. 审核期间保持临时 TeslaMate 服务和凭据可用，及时回复 App Review 消息。
6. 审核结束后撤销临时凭据；发布方式建议首版选择手动发布。

## 8. 每次更新

- 每个上传构建使用新的 Build 号。
- 每次发布重新运行四个发布门禁和真实 API 测试。
- 同步更新公开源码对应 tag，确保用户能取得与商店二进制匹配的完整源代码。
- 更新隐私政策、审核说明、截图和 `NOTICE.md` 中发生变化的内容。
