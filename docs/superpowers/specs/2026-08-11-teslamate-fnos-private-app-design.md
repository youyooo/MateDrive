# TeslaMate 飞牛 NAS 私有 FPK 与后续迁移设计

日期：2026-08-11

状态：用户已批准方案 1，并确认阶段 1 先完成通用 FPK 的空数据部署验证
关联目标：先交付别人也能安装配置的 TeslaMate 飞牛 FPK；验证稳定后，再让 MateDrive 的数据源脱离 Mac 并迁移至 NAS。

## 1. 背景与已核实事实

当前 TeslaMate 相关能力分散在 Mac、新加坡 VPS 和飞牛 NAS：

- Mac 上有一套 `teslamate-local` Compose，包括 TeslaMate、PostgreSQL、Grafana、Mosquitto，以及供手机读取数据的第三方生态组件 TeslaMateAPI。Colima 停止时，`127.0.0.1:14000` 与手机 API 会一起失效。
- 新加坡 VPS 上有一套运行约六周的 TeslaMate、PostgreSQL、Grafana 和 Mosquitto，并由 Nginx/HAProxy 提供 TLS 入口。
- 手机 App 的公网 API 由新加坡 Nginx 的 `127.0.0.1:18081` 上游提供；Grafana 使用 `127.0.0.1:18080`。
- 飞牛 NAS `aijia-nas` 为 x86_64，Docker 28.5.2、Compose 5.2.0 可用，`/vol1` 约剩余 39 GB，但已使用 91%。
- NAS 已有专用 `nas-tunnel` SSH 用户、受限密钥和开机自动启动的反向隧道。现有隧道只允许指定的 `127.0.0.1:18xxx` 远端监听。
- NAS 能直接连接 `auth.tesla.cn`、`owner-api.vn.cloud.tesla.cn` 和 `streaming.vn.cloud.tesla.cn`，不需要依赖 Mac 上的中国区代理程序。
- Mac 与 VPS 当前 TeslaMate 数据库都没有车辆、行程、充电过程或 Tesla Token。它们不是历史数据源，NAS 上线后必须由用户重新完成一次 Tesla 登录。
- Mac 的 TeslaMateAPI Token 已被手机使用。迁移应保留该 Token，使手机无需重新填写认证信息。

官方部署约束以 TeslaMate Docker 文档为准：记录器需要长期在线设备，PostgreSQL 18 使用 `/var/lib/postgresql` 挂载，公网访问必须经过安全隧道或经过加固的反向代理。

### 1.1 当前里程碑边界

本设计拆成两个独立验收里程碑：

- **阶段 1：通用安装包跑通。** 构建不含个人信息的 FPK，在 NAS 空数据环境完成应用中心安装、配置页打开与保存、五服务启动、本地页面/API 探针、重启和卸载保留卷验证，并提供普通用户可照做的安装说明。
- **阶段 2：个人迁移与公网切换。** Tesla 登录、历史数据迁移、复用现有手机 Token、新加坡隧道切换、旧实例停机和 30 分钟真实采集观察。

当前只执行阶段 1。阶段 1 不读取或导入 Mac/VPS 的个人 `.env`、数据库或 Tesla Token，也不修改新加坡服务器、NAS 隧道、手机 App 和旧 TeslaMate 服务。

## 2. 目标

### 2.1 必须实现

1. 生成一个可由飞牛应用中心本地安装的私有 FPK。
2. FPK 由应用中心统一管理 Docker Compose 生命周期，不再保留第二套手动 Compose 控制面。
3. NAS 空数据环境独立运行 TeslaMate、PostgreSQL、Grafana、Mosquitto 和 TeslaMateAPI。
4. 安装向导和配置页允许普通用户配置端口、时区、数据库密码、TeslaMate 加密密钥、Grafana 管理密码和 API Token；保存后由应用中心重建服务。
5. TeslaMate Web、Grafana 和 TeslaMateAPI 在 NAS 本地可打开；未登录 Tesla、数据库无车辆时也不得进入重启循环。
6. PostgreSQL、Grafana 和 Mosquitto 数据使用稳定命名卷；配置修改、重启与普通卸载默认不删除数据。
7. 构建物、默认配置、安装说明和验证报告不得包含个人服务器地址、账号、Token、车辆数据或弱默认密码。
8. 通过自动门禁、官方 `fnpack build`、真实应用中心安装、配置修改、服务健康和卸载保留卷验收。

### 2.2 明确不做

- 本阶段不提交飞牛官方应用商店，不宣称获得官方签名或审核。
- 不把 SSH 私钥、Tesla 账号、数据库密码、API Token 或 Grafana 密码写入 FPK、Git、日志或报告。
- 不直接开放 NAS 路由器端口，不把 TeslaMate 管理页面暴露到公网。
- 阶段 1 不导入个人数据库、不登录 Tesla、不复用手机 Token、不切换新加坡隧道，也不停止 Mac/VPS 旧实例。
- 不删除 Mac 或 VPS 的旧 Compose 配置、数据库卷和备份。
- 不重启 NAS 主机，不执行 Docker 全局清理，不修改其他 NAS 应用。
- 不伪造历史数据；当前空库状态必须如实记录。

## 3. 方案选择

采用 FNOS 原生 Docker FPK：

- `config/resource` 声明唯一 Compose 项目 `teslamate-fnos`，避免接管用户已有的手动 `teslamate` 项目与卷。
- 飞牛应用中心负责容器的创建、停止、升级和卸载。
- 生命周期脚本只报告状态，不与应用中心争夺 Docker 控制权。
- 安装包不携带镜像层或运行数据；安装时拉取并验证 linux/amd64 镜像。
- NAS 到新加坡的隧道继续由现有宿主脚本管理，不纳入 FPK，避免把个人 VPS 地址和 SSH 凭据耦合进可安装包。

阶段 1 的所有运行验收止于 NAS 本地端口。图中的新加坡 VPS 与手机链路属于阶段 2，不是阶段 1 的通过条件。

不采用“先部署普通 Compose 再包装”的双控制面方案，也不采用把私人隧道与服务器配置打入 FPK 的一体化方案。

## 4. 系统架构

```text
Tesla 中国区 API
        │
        ▼
┌───────────────────────────┐
│ 飞牛 NAS / FNOS 应用中心   │
│ App.Native.TeslaMate       │
│                           │
│ TeslaMate  ─ PostgreSQL   │
│     │              │      │
│     ├──────── Grafana     │
│     ├──────── Mosquitto   │
│     └──────── TeslaMateAPI│
└───────────┬───────────────┘
            │ 现有受限 SSH 反向隧道
            ▼
┌───────────────────────────┐
│ 新加坡 VPS                 │
│ 127.0.0.1:18080 → Grafana │
│ 127.0.0.1:18081 → API     │
│ Nginx + TLS + HAProxy      │
└───────────┬───────────────┘
            ▼
       MateDrive 手机 App
```

### 4.1 FPK 身份与目录

- 应用标识：`App.Native.TeslaMate`
- Compose 项目：`teslamate-fnos`
- 初始版本：`0.1.0`
- 平台：`x86`
- 桌面入口：TeslaMate Web
- FPK 结构：
  - `manifest`
  - `ICON.PNG`、`ICON_256.PNG`
  - `config/resource`、`config/privilege`
  - `wizard/install`、`wizard/config`
  - `cmd/main` 与安装、升级、卸载回调
  - `app/docker/docker-compose.yaml`
  - `app/ui/config` 与桌面图标

### 4.2 服务与镜像

| 服务 | 目标镜像 | 作用 |
| --- | --- | --- |
| `teslamate` | 发现标签 `teslamate/teslamate:4.0.1` | Tesla 数据记录与本地管理页 |
| `database` | 发现标签 `postgres:18-trixie` | 持久化 TeslaMate 数据 |
| `grafana` | VPS 当前与 TeslaMate 4.0.1 配套运行的 `teslamate/grafana` 镜像 | 图表与报表 |
| `mosquitto` | 发现标签 `eclipse-mosquitto:2` | 内部 MQTT |
| `teslamateapi` | 发现标签 `mytesla/teslamateapi:2.6` | 第三方生态组件，为 MateDrive 手机提供 JSON API；不是 `teslamate-org` 官方组件 |

上述标签只用于发现候选镜像。最终 `0.1.0` FPK 的五个 `image:` 必须全部写成 `repository@sha256:digest` 不可变引用；构建清单同时记录来源标签、digest 和 linux/amd64 平台验证。不得把 Mac 上的 ARM64 镜像归档直接导入 NAS，也不得在最终包中保留 `latest` 或只有可变标签的引用。

镜像拉取路径与内容归属分开记录：TeslaMate、PostgreSQL、Grafana 和 Mosquitto 使用 DaoCloud 国内传输地址，但 digest 与上游官方镜像清单一致；TeslaMateAPI 使用其规范仓库 `mytesla/teslamateapi` 的固定 digest，让 NAS 自身的镜像加速配置负责故障切换。曾尝试的固定 `docker.1ms.run/mytesla/teslamateapi` 路径在真实下载时发生 TLS 握手超时，因此不写入最终包。保留 TeslaMateAPI 是用户明确确认的手机连接需求，不改变其第三方归属。

### 4.3 网络与端口

| 能力 | NAS 监听 | 暴露范围 | 新加坡上游 |
| --- | --- | --- | --- |
| TeslaMate Web | `0.0.0.0:14000` | NAS 局域网与私有 Tailnet；路由器不转发 | 不公开 |
| Grafana | 阶段 1 默认 `0.0.0.0:14001`；阶段 2 个人安装收紧为 `127.0.0.1:14001` | 阶段 1 家庭局域网；阶段 2 NAS 本机与反向隧道 | 阶段 2 使用 `127.0.0.1:18080` |
| TeslaMateAPI | 阶段 1 默认 `0.0.0.0:3030`；阶段 2 个人安装收紧为 `127.0.0.1:3030` | 阶段 1 家庭局域网且必须 Token 认证；阶段 2 NAS 本机与反向隧道 | 阶段 2 使用 `127.0.0.1:18081` |
| PostgreSQL | 容器网络 `5432` | 不映射宿主端口 | 无 |
| Mosquitto | 容器网络 `1883` | 不映射宿主端口 | 无 |

容器使用单独的内部网络。数据库和 MQTT 不允许宿主端口映射。TeslaMate、Grafana 和 API 的宿主端口必须在安装前检查冲突。阶段 1 的三项 Web 服务默认绑定 `0.0.0.0`，确保局域网用户能完成安装验收，但安装说明必须明确禁止路由器端口转发；阶段 2 再将 Grafana/API 收紧至 `127.0.0.1`。TeslaMate Web 不配置公网 Nginx 上游。

## 5. 配置与密钥边界

### 5.1 FPK 内允许出现

- 非敏感默认端口、时区和镜像引用。
- 变量名、配置模板和安装向导字段。
- Tesla 中国区公开主机名与 `/oauth2/v3` 路径。
- Compose、图标、桌面入口和生命周期脚本。

### 5.2 FPK 内禁止出现

- `TM_ENCRYPTION_KEY`
- `TM_DB_PASS`
- `GRAFANA_PW`
- `MYTESS_API_TOKEN`
- Tesla Access/Refresh Token
- SSH 私钥、NAS/VPS 登录密钥或授权密钥正文
- 手机号码、邮箱、VIN、车辆名称或数据库导出

### 5.3 阶段 1 的通用配置来源

- 安装者在飞牛安装向导中输入独立的 TeslaMate 加密密钥、数据库密码、Grafana 管理密码和 TeslaMateAPI Token。
- 测试安装使用本轮临时生成的高熵凭据；凭据不写入仓库、FPK、日志或报告，验收后只保留“字段存在”的证据。
- 值由 FNOS 写入应用私有配置，文件权限为仅应用用户可读。
- FPK 构建、校验、报告和终端输出只记录变量是否存在，不记录变量值。

安装向导和配置页都提供相同的必需字段及校验规则。测试包和仓库不提供默认弱密码；缺失或格式不合格时必须阻止保存。阶段 2 才从个人现有环境安全迁移凭据。

## 6. 数据与持久化

稳定卷：

- `teslamate-db`
- `teslamate-grafana-data`
- `teslamate-import`
- `mosquitto-conf`
- `mosquitto-data`

Compose 项目名固定为 `teslamate-fnos`，使升级继续复用同一组隔离卷且不会自动采用已有手动 `teslamate` 项目的卷。PostgreSQL 18 挂载点固定为 `/var/lib/postgresql`。

阶段 1 创建全新的空数据库卷，不读取任何个人迁移源。阶段 1 的验证基线至少包含：

- 时间戳
- FPK 版本与 SHA-256
- Compose 项目和五个容器状态
- 命名卷名称与身份
- 数据库大小
- `cars`、`drives`、`charging_processes`、`charges`、`positions` 行数；`tokens` 仅在当前 TeslaMate schema 存在该表时查询，否则记录表不存在并检查实际 Token 字段是否为空
- 配置修改前后卷身份是否一致

阶段 1 允许这些业务表保持空；服务必须在空库和未登录 Tesla 的状态稳定运行。`cars >= 1`、`tokens >= 1` 与真实采集只属于阶段 2，且不得用伪造记录代替。

## 7. 生命周期

### 7.1 安装

1. 应用中心检查 `14000`、`14001` 和 `3030` 无冲突。
2. 检查 Docker 可用、架构为 x86_64、可用空间不少于 10 GB。
3. 检查五个镜像均提供 linux/amd64。
4. 写入应用私有配置；任何密钥缺失或格式不合格则阻止保存。
5. 应用中心创建 `teslamate-fnos` Compose 项目与持久卷。
6. PostgreSQL 和 Mosquitto 就绪后启动 TeslaMate、Grafana 和 TeslaMateAPI。
7. `cmd/main status` 同时检查 TeslaMate Web、Grafana 与 API，本地任一不可用时返回非零。

### 7.2 升级

- 升级包不得重置应用私有配置或删除命名卷。
- 原计划把 `0.1.0 → 0.1.1` 真实应用中心升级放在阶段 2；阶段 1 真实重装发现保留 PostgreSQL 卷时的密码轮换缺陷后，为确保通用包可重装，已将该修复升级前移到阶段 1 并完成验证。个人数据迁移和未来版本升级仍属于阶段 2。
- 升级前记录数据库行数和卷身份；升级后必须一致。
- 镜像版本变化必须写入版本说明并重新验证 AMD64 manifest。

### 7.3 停止与卸载

- 停止由应用中心统一执行。
- 普通卸载停止并移除容器与应用文件，但默认保留命名卷和显式备份。
- 删除数据库卷必须是单独的人工确认操作，不属于 FPK 卸载回调。

## 8. 分阶段交付与切换顺序

### 阶段 A：通用包构建

1. 以公开镜像和通用默认值创建 FPK 源码、安装向导、配置页、Compose 与中文安装说明。
2. 生成一次性测试凭据，但不将值写入源码、包、日志或报告。
3. 构建并校验 `App.Native.TeslaMate_0.1.0_x86.fpk`。
4. 运行结构、Compose、敏感信息、镜像平台和生命周期自动门禁。

### 阶段 B：NAS 空数据安装与本地验证

1. 通过飞牛应用中心安装私有 FPK。
2. 验证安装向导与配置页字段、校验提示、打开和保存均正常。
3. 验证五个容器、命名卷、端口和本地 HTTP/API；不执行 Tesla 登录。
4. 修改一个非敏感配置项并由应用中心应用，确认服务恢复且卷身份不变。
5. 停止、启动并普通卸载一次，确认没有删除命名卷；是否保留未安装状态由验证报告如实记录。
6. 输出不含密钥值的阶段 1 报告和可交付 FPK。

### 阶段 C：个人迁移与公网切换（阶段 2，暂缓）

1. 在 VPS 为现有 NAS 隧道密钥增加且只增加 `127.0.0.1:18080`、`127.0.0.1:18081` 两个 `permitlisten`。
2. 在 NAS 隧道脚本中增加：
   - `18080 → 127.0.0.1:14001`
   - `18081 → 127.0.0.1:3030`
3. 验证 NAS 脚本语法与 VPS 授权范围。
4. 停止 Mac 占用 `18080/18081` 的旧反向隧道，释放远端监听。
5. 重连 NAS 隧道，确认 VPS 两个监听均由 `nas-tunnel` 会话持有。
6. 保持 Nginx 公网域名和端口不变，验证 Grafana 与 API 外部响应。
7. 手机 App 使用原地址和原 Token 完成真实请求。

### 阶段 D：旧实例停机与观察（阶段 2，暂缓）

1. 停止 Mac `teslamate-local` 项目，不删除卷或配置。
2. 停止 VPS `/opt/teslamate` 项目，不删除卷或配置。
3. 连续 30 分钟观察 NAS 五个容器无重启、API 可用、TeslaMate 无认证错误。
4. 完成一次带真实个人数据的后续版本升级并复验数据保留；空库 `0.1.0 → 0.1.1` 修复升级已在阶段 1 完成。

## 9. 回滚

切换失败时按以下顺序回滚：

1. 停止 NAS `teslamate-fnos` 项目，但不删除卷。
2. 恢复 VPS `nas-tunnel` 授权行和 NAS 隧道脚本的时间戳备份。
3. 启动 VPS 原 TeslaMate 项目。
4. 启动 Mac 原 TeslaMateAPI 与原反向隧道，使 `18080/18081` 恢复旧来源。
5. 验证 Nginx 配置无需更改，公网 API/Grafana 恢复。
6. 对比回滚前后的配置与数据库 SHA-256，记录失败原因。

任何验证失败都不得删除 NAS、Mac 或 VPS 数据卷。

## 10. 测试与验收

### 10.1 自动门禁

- manifest、resource、privilege、wizard 和 UI 配置结构校验。
- Compose 解析成功，项目名与五个服务固定。
- 数据库/MQTT 无宿主端口。
- TeslaMate Web、Grafana、API 绑定范围符合设计。
- 四类敏感变量在 FPK 解包内容中零匹配。
- 私钥格式、邮箱、手机号、VIN、Authorization Header 在 FPK 中零匹配。
- 五个镜像的 linux/amd64 manifest 校验成功。
- 生命周期脚本不会执行 `docker volume rm`、`docker system prune` 或宿主级安装命令。
- 官方 `fnpack build` 成功，解包后结构复验成功。

### 10.2 真实环境验收

- `0.1.0` 干净安装成功一次，并通过保留 5 个命名卷的 `0.1.0 → 0.1.1` 修复升级完成最终验收。
- 安装向导和配置页均可打开；必需字段为空或格式错误时可见校验，合法配置可保存。
- TeslaMate Web、Grafana、API 在空数据且未登录 Tesla 时本地健康。
- 配置修改及停止/启动后，五个容器恢复且命名卷身份不变。
- 普通卸载不执行 Docker 卷删除；自动或人工检查均不得发现 `docker volume rm`。
- 不改新加坡 Nginx/HAProxy、NAS 隧道、手机配置或 Mac/VPS 旧项目。
- 阶段 1 报告记录 FPK SHA-256、容器状态、HTTP 状态、数据库计数、卷身份和剩余风险。

## 11. 风险与停止条件

| 风险 | 控制措施 |
| --- | --- |
| NAS `/vol1` 已使用 91% | 安装前要求至少 10 GB 可用；不导入 ARM64 镜像；不保留重复镜像归档 |
| Tesla 账号尚未登录 | 阶段 1 明确保持未登录，以验证空库稳定性；阶段 2 再由用户在 LAN 页面完成 |
| Mac 与 NAS 同时占用 VPS 远端端口 | 先备份和授权，再按明确顺序释放旧监听、启动新监听 |
| API Token 泄露 | 不回显传输、包内零密钥、文件权限收紧、报告只记录存在性 |
| FPK 卸载误删记录 | 卸载回调不删卷；删除卷必须独立人工确认 |
| 可变镜像标签漂移 | 候选标签只用于发现；最终五个镜像全部使用经过 linux/amd64 校验的不可变 digest |
| 固定第三方镜像代理失联 | 官方四镜像使用已验证的 DaoCloud 传输地址；TeslaMateAPI 使用规范仓库名与固定 digest，由 NAS 镜像加速器自动选择可用路径 |
| VPS 共享边缘受影响 | 不改 HAProxy SNI 分流；Nginx 配置改动前备份并执行 `nginx -t` |

遇到以下情况必须停止并请求用户确认：

- 阶段 1 出现任何要求输入 Tesla 密码、验证码或导入个人 Token 的步骤。
- 需要删除任何数据库卷或旧备份。
- 需要重启 NAS、修改路由器端口或公开 TeslaMate 管理界面。
- 需要提交飞牛官方商店、签名或公开发布镜像。
- 备份校验失败、数据库计数异常或 NAS 可用空间低于 10 GB。

## 12. 完成定义

### 12.1 当前阶段 1 完成定义

只有同时满足以下条件才可标记阶段 1 完成：

1. 私有 `0.1.0` FPK 已完成初始安装验证，最终修复版 `0.1.1` FPK 已构建、自动校验并由飞牛官方 `fnpack` 成功打包。
2. FPK 已在飞牛应用中心完成一次空数据干净安装，安装向导和配置页均可打开、校验和保存。
3. 五个容器运行，TeslaMate Web、Grafana 和 TeslaMateAPI 本地探针通过，未登录 Tesla 时无重启循环。
4. 配置修改与停止/启动后命名卷身份不变；普通卸载路径没有删除卷。
5. 安装包敏感信息扫描为零命中，并有普通用户可执行的中文安装说明。
6. 阶段 1 报告包含 FPK SHA-256、容器状态、HTTP 状态、数据库空基线、卷身份与剩余风险。
7. 新加坡服务器、NAS 隧道、手机配置以及 Mac/VPS 旧 TeslaMate 均未改变。

### 12.2 最终迁移完成定义（阶段 2）

阶段 1 通过后另行执行：Tesla 登录与真实车辆基线、个人数据/Token 迁移、新加坡公网切换、手机验证、旧实例停机、后续版本升级验证和 30 分钟稳定性观察。

## 13. 参考

- TeslaMate 官方 Docker 安装文档：https://docs.teslamate.org/docs/installation/docker/
- TeslaMate 官方发布页：https://github.com/teslamate-org/teslamate/releases
- 飞牛现有应用包模式：本机 `AssetNest/release/fnos/`
- NAS 现有隧道：`/home/Youyooo/bin/nas-to-sgp-tunnel.sh`
- VPS TeslaMate：`/opt/teslamate`
