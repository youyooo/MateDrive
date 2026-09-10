# MateDrive

MateDrive 是独立开发的 iPhone 原生车辆数据客户端。它连接到用户自行部署的 TeslaMate 兼容 API，以只读方式展示车辆状态、行程、充电、电池、费用、地图和统计数据，不需要 Tesla 账号密码，也不会向车辆发送控制命令。

> 当前状态：源代码与真机测试流程已开放，App Store 版本正在完成 TestFlight 与审核准备。

## 主要功能

- 车辆概览：圆形电量或表显续航、胎压、地图、最近行程、最近充电费用和总里程。
- 行程分析：路线地图、速度、功率、海拔、温度、天气、能耗与多行程比较。
- 充电分析：充电曲线、AC/DC 统计、单笔费用、阶梯/分时价格规则与费用覆盖率。
- 电池分析：可用容量校准、健康趋势、数据质量、缺失样本说明和隐私安全的本地报告分享。
- 可选 iCloud 私人备份：明确授权后备份本地数据库与非敏感设置，保留最近三份，恢复前校验并支持失败自动回滚；Keychain 密钥不会进入备份。
- 历史与统计：里程、活动时间线、相邻行程合并、隐私安全的周期回顾、成就卡片与多行程路程报告分享、地点、通勤、驻车损耗、国家/地区、成就和软件升级。
- iOS 能力：SwiftUI、WidgetKit、本地通知、Keychain、后台刷新、后台全量同步续传和系统地图。
- 本地化：简体中文、繁体中文和英语。
- 区域设置：人民币、港币、新台币、美元等 ISO 4217 货币，以及公制/英制单位。

## 系统要求

- macOS 与 Xcode 26.5 或兼容的新版本。
- XcodeGen 2.45 或兼容版本。
- iOS 18.0 或更高版本。
- 用户自行运行且可由 iPhone 访问的 TeslaMate API。

MateDrive 不直接连接 TeslaMate 的 PostgreSQL，也不接受 Tesla 账号凭据。服务器暴露到互联网时应使用可信 HTTPS 证书和访问控制。

## 开始开发

```bash
git clone https://github.com/youyooo/MateDrive.git
cd MateDrive
/opt/homebrew/bin/xcodegen generate
open MateDrive.xcodeproj
```

常用验证命令：

```bash
make preflight
make verify
make release-technical-gate
```

真实 TeslaMate API 测试使用本地、被 Git 忽略的 `.matedrive-integration.env`。不要把服务器地址、令牌、账号、密码或车辆位置提交到仓库。

## 安装与发布

- [安装到自己的 iPhone](docs/installation/iphone.md)
- [App Store 上架指南](docs/release/app-store-publishing-zh.md)
- [GitHub 开源发布指南](docs/open-source/github-publishing-zh.md)
- [App Store 元数据与审核清单](docs/release/app-store-submission.md)
- [用户支持与隐私页面](https://youyooo.github.io/MateDrive/)

## 参与贡献

提交代码前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题不要公开提交普通 Issue，请按 [SECURITY.md](SECURITY.md) 报告。

## 隐私与免责声明

MateDrive 没有开发者运营的数据后端，不包含广告追踪或开发者分析。车辆和位置数据来自用户配置的服务器，并保存在该服务器和用户设备上；只有在用户明确开启 iCloud 备份后，本地数据库与非敏感设置才会保存到用户自己的 iCloud 私人数据库。Apple 地图/地理编码及 Open-Meteo 天气功能可能按功能需要处理位置和时间信息，详见[隐私政策](docs/support/privacy.html)。

MateDrive 是独立实现的原生 iOS 开源项目，不捆绑车辆照片、厂商宣传图或车辆渲染图。MateDrive 与 Tesla, Inc.、TeslaMate 或其他服务提供方不存在隶属或官方认可关系；相关产品名称仅用于说明兼容性，商标归各自权利人所有。

## 许可证

本项目按 [MIT License](LICENSE) 开源。第三方服务与商标声明见 [NOTICE.md](NOTICE.md)。
