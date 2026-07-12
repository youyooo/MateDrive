# 将 MateDrive 安装到 iPhone

本文适用于从当前源码安装调试版本。准备上架 App Store 时，建议直接使用已加入 Apple Developer Program 的 Apple 账号；免费 Personal Team 适合短期调试，但签名有效期和可用能力有限。

## 1. 准备 Mac 和 iPhone

1. 在 Mac App Store 安装与手机 iOS 版本兼容的 Xcode。当前项目已用 Xcode 26.5 验证。
2. 运行 `xcode-select -p`，确认命令行工具指向当前 Xcode。
3. 安装 XcodeGen：`brew install xcodegen`。
4. 用数据线连接 iPhone，解锁手机，并在手机上选择信任这台 Mac。
5. 在 iPhone 的“设置 > 隐私与安全性 > 开发者模式”中开启开发者模式并按提示重启。
6. 打开 Xcode 的 `Settings > Accounts`，添加 Apple 账号并确认账号下出现开发团队。

## 2. 完成签名

在项目目录执行：

```bash
xcodegen generate
open MateDroidIOS.xcodeproj
```

在 Xcode 中依次选择 `MateDroidIOS` 和 `MateDroidWidget` target：

1. 打开 `Signing & Capabilities`。
2. 勾选 `Automatically manage signing`。
3. 两个 target 选择同一个 Team。
4. 确认 App Groups 中存在 `group.com.matedrive.ios`。
5. 如果 `com.matedrive.ios` 已被其他开发者占用，先把 `project.yml` 中 App、Widget、后台任务和 App Group 标识统一改成你自己的反向域名，再重新运行 `xcodegen generate`。

不要只在生成后的 `.xcodeproj` 内永久修改标识；工程由 `project.yml` 生成，下次生成会覆盖手工改动。

## 3. 一键安装

保持手机解锁并连接。先查看可用设备和 Team ID：

```bash
xcrun devicectl list devices
```

Team ID 可在 Apple Developer 账号 Membership 页面或 Xcode 账号详情中找到。然后执行：

```bash
MATEDRIVE_DEVELOPMENT_TEAM=你的_TEAM_ID make install-device
```

连接多台手机时指定设备标识：

```bash
MATEDRIVE_DEVELOPMENT_TEAM=你的_TEAM_ID \
MATEDRIVE_DEVICE_ID=设备标识 \
make install-device
```

脚本会生成工程、自动签名、构建 App 与 Widget、安装到手机并启动 MateDrive。

## 4. 通过 Xcode 安装

脚本失败时可在 Xcode 顶部选择已连接的 iPhone，选择 `MateDrive` scheme，然后按 `Command-R`。首次启动若系统阻止开发者 App，在 iPhone 的“设置 > 通用 > VPN 与设备管理”中信任对应开发者证书。

## 5. 配置 TeslaMate 测试

1. 确保 iPhone 能访问 TeslaMate API 地址；Mac 能访问不代表手机一定能访问。
2. 互联网访问使用可信 HTTPS 证书，不要长期开放无认证 HTTP 服务。
3. 在 MateDrive 设置中输入 API 地址与对应认证方式。
4. 点击“测试连接”，确认车辆、状态、行程、充电、设置和诊断能力均通过。
5. 检查首页、行程能耗、充电费用、电池健康、地图、单位、语言和 Widget。

真实凭据只填入手机或本机被忽略的 `.matedrive-integration.env`，不要写进源码、Issue 或截图。

## 常见问题

- `0 valid identities found`：Xcode 还没有创建 Apple Development 证书。在 Xcode 账号页管理证书，或打开工程让自动签名创建。
- `No available iPhone was found`：解锁并信任手机，开启开发者模式，检查 Xcode 是否支持手机的 iOS 版本。
- Bundle ID 不可用：改用自己控制的唯一反向域名，并同步 App、Widget、App Group 和后台任务标识。
- App Group 权限失败：确认付费开发团队已启用 App Groups，App 与 Widget 使用同一 Team 和同一 Group。
- 安装后无法连接：从 iPhone Safari 访问 API 域名，检查 DNS、HTTPS 证书、反向代理、防火墙与认证。
