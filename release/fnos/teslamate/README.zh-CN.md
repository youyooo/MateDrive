# TeslaMate 飞牛私有安装包

这是面向 x86_64 飞牛 NAS 的第三方、未签名测试包，不是 TeslaMate 官方发布，也尚未提交飞牛应用商店。应用图标复用 TeslaMate 4.0.1 上游容器内的公开图标资源。

包内运行官方 TeslaMate 及其 PostgreSQL 18、Grafana、Mosquitto 依赖，并额外提供第三方生态组件 TeslaMateAPI，供手机客户端读取行程、充电和实时状态。TeslaMateAPI 不是 `teslamate-org` 官方组件。安装包不包含 Tesla 账号、车辆数据、数据库内容、密码、API Token、SSH 密钥或个人服务器地址。

五个镜像都锁定到经过 `linux/amd64` 校验的 SHA-256。TeslaMate、PostgreSQL、Grafana 和 Mosquitto 通过 DaoCloud 国内传输地址获取，但内容 digest 对应各自上游镜像；TeslaMateAPI 使用规范仓库 `mytesla/teslamateapi` 的固定 digest，由 NAS 的 Docker 镜像加速配置选择可用下载路径。

## 安装前

- NAS 需要可用的 Docker、至少 2 GB 内存和 10 GB 可用空间。
- 首次安装需要下载数 GB 镜像，进度可能长时间停留在“安装中”；不要在镜像仍在下载时反复提交安装。
- 默认端口为 14000、14001 和 3030，安装前确认没有被其他应用占用。
- 默认容器内部网段为 `10.253.0.0/24`。如它与家庭网络、VPN 或 NAS 上已有容器网络冲突，请在向导中换成另一个未占用的私有 IPv4 CIDR。
- 在密码管理器中分别生成并保存：24 位以上数据库密码、32 位以上 TeslaMate 加密密钥、16 位以上 Grafana 密码、32 位以上 API Token。当前向导只接受字母与数字。
- 三个网页端口只用于家庭局域网。不要在路由器上把它们直接转发到公网。

## 安装与配置

完整的点击路径、字段填写规则、首次访问、手机 API、升级和故障排查请参阅：[TeslaMate 飞牛 FPK 安装与首次配置指南](../../../docs/release/teslamate-fnos-install-guide.zh-CN.md)。

准备提交飞牛应用中心时，使用：[TeslaMate 飞牛应用中心提审清单](../../../docs/release/teslamate-fnos-store-submission-checklist.zh-CN.md)。

1. 在飞牛应用中心选择手动安装并上传 `App.Native.TeslaMate_0.1.2_x86_fnpack.fpk`。
2. 按向导确认三个端口、容器内部网段和 IANA 时区，再填写四项独立凭据。
3. 安装完成后，桌面会提供 TeslaMate（默认主入口）、Grafana 和手机 API 三个入口；也可以使用 NAS 地址加对应端口访问。
4. TeslaMate 页面正常打开后，再由安装者自行完成 Tesla 登录。本阶段测试包不会自动导入任何账号或历史数据。
5. 后续修改端口、时区或凭据时，从应用中心打开配置页。配置保存会重建容器，但不会主动删除命名卷。

若重装或配置时更换数据库密码，`0.1.2` 会在 PostgreSQL 健康检查放行前同步保留数据卷中的 `teslamate` 数据库角色；其他服务只会在同步成功后启动。此过程不会删除或重建数据库卷。

## 卸载与数据

普通卸载回调不会调用 Docker 卷删除。数据库等命名卷可能继续留在 NAS；删除数据必须由管理员另行确认，不属于本包的自动行为。

上游项目与 Docker 部署说明：https://docs.teslamate.org/docs/installation/docker/
