# TeslaMate 飞牛 FPK 阶段 1 验收报告

日期：2026-08-12
范围：通用空数据 FPK 构建、飞牛应用中心安装与本地服务验收
明确未执行：Tesla 登录、个人数据迁移、个人手机 Token 复用、新加坡服务器或隧道切换、Mac/VPS 旧服务停机

## 1. 交付结论

阶段 1 的交付物是一个面向 x86_64 飞牛 NAS 的第三方、未签名 TeslaMate FPK。包内包含官方 TeslaMate 及 PostgreSQL、Grafana、Mosquitto，并按用户确认保留第三方生态组件 TeslaMateAPI，供手机客户端读取行程、充电与实时状态。TeslaMateAPI 不属于 `teslamate-org` 官方组件，README 已明确标注。

最终安装包不包含 Tesla 账号、车辆数据、数据库导出、密码、API Token、邮箱、手机号、VIN、SSH 密钥、新加坡服务器地址或其他个人配置。四项安装凭据均在安装时临时生成，未写入仓库、安装包、终端输出或本报告。

## 2. 可交付构建物

- 官方 `fnpack` 产物：`/Users/youyooo/Documents/matedroid-ios/release/fnos/teslamate/dist/App.Native.TeslaMate_0.1.2_x86_fnpack.fpk`
- SHA-256：`96f3bc486964b0601a98af57c3d4c75560df3bb95f760b7aca5f7841e3f9d5b4`
- 官方结构复验：17 个外层成员、7 个 `app.tgz` 内层成员，应用 ID `App.Native.TeslaMate`，版本 `0.1.2`
- 官方构建环境：飞牛 NAS `/usr/local/bin/fnpack` 1.0.0
- 本轮官方构建目录：`/vol1/1000/teslamate-fpk-stage/ui-0.1.2b.lhCsjS`
- 可复现本地构建物：`/Users/youyooo/Documents/matedroid-ios/release/fnos/teslamate/dist/App.Native.TeslaMate_0.1.2_x86.fpk`
- 本地构建物 SHA-256：`cbc58ccd8c6d7ded46c7943204e66a954fc2313043825ffa7337cad39075f28b`

## 3. 组件与镜像来源

所有镜像都使用 `repository@sha256:digest` 不可变引用，并已在真实 NAS 上确认 `linux/amd64`：

| 服务 | 内容来源与传输策略 |
| --- | --- |
| TeslaMate 4.0.1 | `teslamate/teslamate` 官方内容，DaoCloud 国内传输地址，固定 digest |
| PostgreSQL 18 | PostgreSQL 官方内容，DaoCloud 国内传输地址，固定 digest |
| Grafana | TeslaMate 配套 Grafana 内容，DaoCloud 国内传输地址，固定 digest |
| Mosquitto 2 | Eclipse Mosquitto 官方内容，DaoCloud 国内传输地址，固定 digest |
| TeslaMateAPI 2.6 | 第三方 `mytesla/teslamateapi`，规范仓库名，固定 digest；供手机 API 使用 |

固定代理 `docker.1ms.run/mytesla/teslamateapi` 在真实拉取中发生 TLS 握手超时。最终包改用规范仓库名，让 NAS 自身的 Docker 镜像加速配置完成故障切换；同一固定 digest 已在 NAS 成功拉取并验证。官方四镜像保留已在该 NAS 验证可用的 DaoCloud 传输地址。

## 4. 自动测试与缺陷修复

- 最终自动测试：19/19 通过，0 failure。
- FPK 官方复验：通过。
- 镜像平台检查：5/5 为 `linux/amd64`。
- Compose 契约：5 个隔离服务；宿主只开放 `14000`、`14001`、`3030`；PostgreSQL 与 MQTT 不映射宿主端口；内部网段默认 `10.253.0.0/24`。
- 安全门禁：包内无真实秘密或个人地址，生命周期脚本无卷删除、全局 Docker 清理或宿主软件安装命令。

本轮真实重装发现一个只有在“保留旧 PostgreSQL 卷并更换数据库密码”时才会触发的问题：同步脚本以容器操作系统用户 `postgres` 启动 `psql`，但数据库只创建了 `teslamate` 角色，导致密码同步失败，TeslaMate 出现认证失败和重启循环。

第一轮修复采用 TDD：先把行为测试收紧为必须调用 `psql -U teslamate`，测试按预期 RED；再对生产脚本增加显式数据库角色，聚焦测试与完整 18 项测试均 GREEN。真实应用中心重装随后进一步证明，飞牛 Docker 应用的 Compose 生命周期不会依赖 `cmd/main start` 完成这项同步，因此该接入点不足以保护普通用户。

第二轮修复继续按 TDD 执行：先新增“旧数据卷密码必须在数据库健康前完成轮换”的契约测试并取得 RED，再把同步门禁放入 PostgreSQL 容器自身启动流程。数据库只有在 `ALTER ROLE teslamate` 成功并写入内部就绪标记后才会通过健康检查，TeslaMate、Grafana 与 TeslaMateAPI 仍通过 `service_healthy` 等待；未增加第六个服务、Docker 套接字或额外宿主权限。修复后聚焦测试与完整 19 项测试均 GREEN；本轮 0.1.2 仅增加三个飞牛桌面入口和端口联动，不改变五服务或数据卷结构。

## 5. 飞牛应用中心与生命周期证据

- 手动安装页成功识别官方 `fnpack` FPK，并显示未签名应用提示。
- 网络与地区向导显示并接受默认端口 `14000`、`14001`、`3030`、网段 `10.253.0.0/24` 和时区 `Asia/Shanghai`。
- 安全凭据向导显示 PostgreSQL 密码、TeslaMate 加密密钥、Grafana 管理密码、TeslaMateAPI Token 四个密码字段。
- 配置页已验证八项字段可打开、秘密字段不以明文显示，保存操作可被应用中心接受。
- 普通卸载后 Compose 容器数量为 0，以下 5 个命名卷全部保留：
  - `teslamate-fnos_mosquitto-conf`
  - `teslamate-fnos_mosquitto-data`
  - `teslamate-fnos_teslamate-db`
  - `teslamate-fnos_teslamate-grafana-data`
  - `teslamate-fnos_teslamate-import`
- 卸载未执行任何手工卷删除。
- 用户批准后只清理了旧 Docker 构建缓存，释放约 17 GB；未执行全局镜像、容器或卷清理。

## 6. 最终固定包运行验收

飞牛应用中心此前已完成 `0.1.0 → 0.1.1` 真实升级，详情页显示当前版本 `0.1.1` 且状态为“打开”。本轮 0.1.2 只完成官方打包与结构复验，尚未在 NAS 上覆盖安装，因此当前运行实例和五个命名卷均未改变。

- 运行服务：PostgreSQL、Mosquitto、TeslaMate、Grafana、TeslaMateAPI，5/5 运行。
- 稳定性：升级后两次独立采样的 5 个容器 `RestartCount` 均为 0；PostgreSQL 为 `healthy`。
- 保留卷密码门禁：`/tmp/teslamate-password-synced` 存在，证明旧数据库角色密码已在数据库健康前自动同步；本次最终升级未执行人工 SQL 修复。
- 当前日志：PostgreSQL、TeslaMate、Grafana、TeslaMateAPI 的近期日志中，`password authentication failed`、`FATAL`、`panic`、`Crash` 均为 0 命中。
- 容器网段：`10.253.0.0/24`。
- 宿主端口：TeslaMate `14000`、Grafana `14001`、TeslaMateAPI `3030`；PostgreSQL 与 MQTT 未映射宿主端口。
- NAS 本机 HTTP：TeslaMate `302`、Grafana `302`、TeslaMateAPI 根路径 `200`。
- Mac 局域网 HTTP：TeslaMate `302`、Grafana `302`、TeslaMateAPI 根路径 `200`。
- API 认证：Token 已配置、`API_TOKEN_DISABLE=false`；`/api/v1/cars` 不带 Token 返回 `401`，带临时 Bearer Token 返回 `200`。Token 值未回显。
- 空数据基线：`cars=0`、`drives=0`、`charging_processes=0`、`charges=0`、`positions=0`、`states=0`、`updates=0`。当前 TeslaMate 4 schema 没有通用 `tokens` 表；`settings=1` 是初始化设置行，不含 Tesla Token 字段。
- 配置与 UI：应用中心能打开应用设置，展示安装位置、运行设置与访问端口；安装/配置向导的八项字段和密码掩码已在同一真实包流程中验证。
- 上架文档：已补充 [TeslaMate 飞牛 FPK 安装与首次配置指南](teslamate-fnos-install-guide.zh-CN.md)，覆盖应用中心点击路径、字段规则、首次访问、手机 API、升级保卷和常见问题。
- 提审资料：已补充 [TeslaMate 飞牛应用中心提审清单](teslamate-fnos-store-submission-checklist.zh-CN.md)，列出 FPK、哈希、截图、第三方组件、权限与安全说明，以及仍需飞牛账号完成的申请表步骤。

局域网入口：

- TeslaMate：`http://192.168.3.82:14000/`
- Grafana：`http://192.168.3.82:14001/`
- TeslaMateAPI：`http://192.168.3.82:3030/`

## 7. 剩余风险与阶段 2 边界

- 这是未签名测试包，尚未提交飞牛官方应用商店审核。
- 首次安装需要下载数 GB 镜像，在国内镜像链路较慢时会长时间显示“安装中”。
- TeslaMate 尚未登录 Tesla，真实车辆采集、Token 生命周期与 30 分钟连续记录属于阶段 2。
- TeslaMateAPI 作为手机所需第三方组件被明确保留；其上游发布与安全更新需要独立跟踪。
- 路由器不得把 `14000`、`14001` 或 `3030` 直接转发到公网。
- 本轮未修改 Mac 旧实例、VPS、新加坡 Nginx/HAProxy、NAS 隧道和手机设置。
