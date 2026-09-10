# Contributing to MateDrive

感谢你改进 MateDrive。提交贡献代表你同意按仓库的 MIT License 发布该贡献，并确认你有权提交相关代码和素材。

## 开发环境

1. 安装 Xcode 26.5 或兼容的新版本。
2. 安装 XcodeGen：`brew install xcodegen`。
3. 运行 `xcodegen generate` 生成工程。
4. 使用 `MateDrive` scheme 开发和测试。

## 提交前检查

```bash
make preflight
make verify
```

涉及发布、权限、隐私清单、图标或本地化时，还需运行：

```bash
make release-technical-gate
make app-store-audit
```

## 开发约定

- 保持 TeslaMate 访问只读；新增写操作必须先讨论安全边界。
- 不用 `0` 伪装缺失数据；界面和统计必须区分真实零值、估算值和不可用值。
- 新增用户可见文字时更新 String Catalog，并覆盖简体/繁体中文和英语。
- 费用、距离、速度、温度和能耗必须通过统一格式化逻辑展示。
- 对计算、解码、缓存迁移和 API 兼容性补充针对性测试。
- 不提交真实服务器、令牌、Basic Auth、AK/SK、车辆标识、轨迹或截图中的私人位置。

## Pull Request

PR 应说明问题、实现方式、测试结果和用户界面变化。界面变更附去除私人信息的截图；数据修复说明真实零值、缺失值和估算值的处理方式。

安全漏洞请按 `SECURITY.md` 私下报告，不要创建公开 Issue。
