# Security Policy

## Supported Version

安全修复优先应用到默认分支的最新代码。正式版本发布后，本页会列出仍受支持的版本范围。

## Report a Vulnerability

请使用 GitHub 仓库的 **Security > Report a vulnerability** 私下提交安全报告：

https://github.com/youyooo/MateDrive/security/advisories/new

报告应包含受影响版本、复现步骤、影响范围和建议修复。请勿在公开 Issue 中提交漏洞细节、服务器地址、认证信息、车辆 VIN、位置或行程轨迹。

普通连接问题和不含敏感信息的功能缺陷可提交到：

https://github.com/youyooo/MateDrive/issues

## Credential Handling

MateDrive 将认证密钥存储在 Apple Keychain。仓库、测试日志、截图、Issue 和诊断导出中不得包含真实 API Token、Basic Auth 密码或 MyTesS API Secret Key。发现凭据意外公开后，应先在服务端撤销并轮换，再清理 Git 历史。
