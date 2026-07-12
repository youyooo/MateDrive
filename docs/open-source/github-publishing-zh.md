# MateDrive GitHub 开源发布指南

## 仓库结构

公开仓库地址：`https://github.com/youyooo/MateDrive`

- `README.md`：项目入口、功能、构建和文档索引。
- `LICENSE`：GNU GPLv3 完整许可证。
- `NOTICE.md`：第三方来源、商标和法律声明。
- `CONTRIBUTING.md`：贡献流程和数据准确性约定。
- `SECURITY.md`：私密漏洞报告流程。
- `.github/ISSUE_TEMPLATE`：去除私人车辆信息的 Bug/功能模板。
- `.github/workflows/pages.yml`：自动发布支持与隐私页面。

## 首次发布命令

如果本地 Git 历史已经完成敏感信息审查，GitHub CLI 已登录时可在项目根目录运行：

```bash
gh repo create youyooo/MateDrive --public --source=. --remote=origin
git push -u origin HEAD:main
```

若旧提交含本机邮箱、内网地址、凭据或私人轨迹，不要直接推送完整历史。保留本地开发分支，并从已审查的当前工作树创建无父提交的公开 `main` 快照；本项目首次公开发布采用这种方式。不要为了清理公开仓库而删除本地历史。

然后在 GitHub 仓库 `Settings > Pages` 中确认 Source 为 `GitHub Actions`。工作流成功后：

- 支持页：`https://youyooo.github.io/MateDrive/`
- 隐私页：`https://youyooo.github.io/MateDrive/privacy.html`

## 发布前安全检查

```bash
git status --short
git grep -n -I -E '(api[_-]?token|secret[_-]?key|basic[_-]?password)' HEAD
git log --all --oneline
```

搜索命中测试字段名并不等于泄漏；每项都要确认只有占位值或测试值。还要人工检查截图、`.env`、诊断导出、服务器域名、VIN 和轨迹。真实凭据一旦提交，应先在服务端撤销和轮换，再重写 Git 历史。

## 版本发布

```bash
git tag -a v1.0.0 -m "MateDrive 1.0.0"
git push origin v1.0.0
gh release create v1.0.0 --generate-notes
```

不要在 Release 附件中发布未签名来源不明的 IPA。App Store 版本发布时，tag 对应源码应能够构建该版本，并保留完整许可证和构建说明。

## 日常协作

1. 从默认分支创建功能分支。
2. 提交前运行 `make preflight` 和相关测试。
3. 使用 Pull Request 合并并保留审查记录。
4. 启用 Dependabot、Secret scanning、Code scanning 和 Private vulnerability reporting。
5. Issue 和截图必须删除服务器、认证、VIN、地址与轨迹等私人数据。
