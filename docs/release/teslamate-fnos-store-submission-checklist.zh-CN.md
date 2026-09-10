# TeslaMate 飞牛应用中心提审清单

当前状态：资料已准备，尚未代提交申请表。

## 1. 当前交付物

| 项目 | 文件或信息 |
| --- | --- |
| FPK | `release/fnos/teslamate/dist/App.Native.TeslaMate_0.1.2_x86_fnpack.fpk` |
| FPK SHA-256 | `96f3bc486964b0601a98af57c3d4c75560df3bb95f760b7aca5f7841e3f9d5b4` |
| 安装指南 | `docs/release/teslamate-fnos-install-guide.zh-CN.md` |
| 阶段验收报告 | `docs/release/teslamate-fnos-stage-1-report.md` |
| 应用 ID | `App.Native.TeslaMate` |
| 版本 | `0.1.2` |
| 架构 | x86 / linux/amd64 |
| 服务 | TeslaMate、PostgreSQL、Grafana、Mosquitto、TeslaMateAPI |

## 2. 飞牛申请表需要准备的内容

按飞牛官方“应用生态”入口提交申请表。申请表需要飞牛账号登录，表单字段以提交时页面为准；以下内容已经准备好：

- 应用名称：TeslaMate
- 应用简介：在飞牛 NAS 上运行 TeslaMate 数据记录、Grafana 可视化和手机客户端 API。
- 发布者：Youyooo
- 应用类型：第三方应用 / Docker FPK
- 支持架构：x86/x86_64；不声明 ARM 支持。
- 首次安装端口：`14000`、`14001`、`3030`。
- 桌面入口：TeslaMate（主入口，安装完成后默认打开）、Grafana（内置可视化）、手机 API（内置 TeslaMateAPI）。
- 数据卷说明：5 个命名卷，普通卸载不主动删除。
- 权限说明：仅使用应用自身 Compose 服务和持久卷；不需要宿主 Docker 套接字，不开放数据库/MQTT 宿主端口。
- 网络说明：三个网页/API 端口仅建议在局域网使用，不要求路由器端口直通。
- 第三方组件说明：TeslaMateAPI 来自 `mytesla/teslamateapi`，为手机客户端提供 API，不属于 TeslaMate 官方组件。
- 数据边界：安装包不带 Tesla 账号、车辆、历史行程、个人 Token、邮箱、手机号、VIN、SSH 密钥或公网服务器配置。

## 3. 审核附件建议

提交时建议一并提供：

1. `App.Native.TeslaMate_0.1.2_x86_fnpack.fpk`。
2. FPK SHA-256 校验值。
3. [安装与首次配置指南](teslamate-fnos-install-guide.zh-CN.md)。
4. [阶段 1 验收报告](teslamate-fnos-stage-1-report.md)。
5. 应用图标：`release/fnos/teslamate/ICON.PNG`、`ICON_256.PNG`。
6. 运行截图：安装向导、应用设置、TeslaMate 首页、Grafana 首页、手机 API 入口/配置说明页。
7. 第三方组件和许可证/来源说明，尤其是 TeslaMateAPI、Grafana、PostgreSQL、Mosquitto 及图标来源。
8. 隐私与安全说明：不上传用户数据；Token 由安装者自行生成；API 默认要求 Bearer Token；不建议公网直连。

## 4. 提交前门禁

- [x] 官方 `fnpack` 结构复验通过：17 个外层成员、7 个内层成员。
- [x] 自动测试 19/19 通过。
- [x] NAS x86_64 实机安装、升级、5 服务运行和空库验收通过。
- [x] API 未认证返回 `401`，认证请求返回 `200`。
- [x] 保留数据库卷更换密码不会造成认证重启循环。
- [x] FPK 和文档不包含真实密码、Token、车辆或服务器个人配置。
- [x] 文档明确 TeslaMateAPI 是第三方组件。
- [ ] 飞牛账号登录申请表并提交。
- [ ] 飞牛审核反馈和签名/发布要求确认。
- [ ] 官方商店页面上线后复核安装链接、版本、截图和说明。

## 5. 不能在本地替代的事项

飞牛官方帮助中心目前只公开提供“请求上架应用中心”的申请入口；申请表需要飞牛账号登录，审核和签名/发布结果由飞牛平台决定。本地可以完成 FPK、文档、测试和安全边界准备，不能代替开发者账号提交或预先保证审核通过。

官方入口：

- [飞牛联系我们 / 应用生态申请](https://help.fnnas.com/articles/v1/contact/contact-us)
- [飞牛第三方应用安全说明](https://help.fnnas.com/articles/v1/contact/safe-report.md)
