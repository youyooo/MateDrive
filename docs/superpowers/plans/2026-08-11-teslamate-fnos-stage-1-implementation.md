# TeslaMate 飞牛 FPK 阶段 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一个不含个人数据、可由飞牛应用中心安装和配置，并能在 x86_64 NAS 空数据环境稳定运行五个服务的 TeslaMate 私有 FPK。

**Architecture:** FPK 只携带 manifest、向导、生命周期脚本、桌面入口和使用不可变镜像引用的 Compose；FNOS 应用中心拥有 Compose 生命周期。Python 工具以 AMD64 镜像锁为唯一镜像输入，构建并复验 FPK；NAS 真实验收只访问局域网端口，不触碰个人 Tesla 登录、数据迁移、新加坡隧道或旧实例。

**Tech Stack:** FNOS `fnpack` 1.0.0、Docker Compose 5.2、TeslaMate 4.0.1、PostgreSQL 18、Grafana、Mosquitto 2、第三方 TeslaMateAPI 2.6、Python 3 标准库、`unittest`。

**2026-08-12 执行修正：** `0.1.0` 真实重装暴露了“保留 PostgreSQL 卷并输入新数据库密码”时的认证循环。最终交付版本提升为 `0.1.1`，数据库容器会在健康检查放行前自动同步 `teslamate` 角色密码；空库 `0.1.0 → 0.1.1` 应用中心升级已前移到阶段 1 验收，未扩大到个人数据迁移或公网切换。

## Global Constraints

- 当前只执行设计规格的阶段 1；Tesla 登录、个人数据/Token、新加坡服务器和手机切换全部暂缓。
- 应用标识固定为 `App.Native.TeslaMate`，Compose 项目固定为 `teslamate-fnos`，平台固定为 `x86`。
- 最终五个 `image:` 必须是 `repository@sha256:digest`，且镜像锁记录 `linux/amd64` 验证。
- TeslaMateAPI 因手机客户端需求明确保留，但文档和商店元数据必须标注为第三方生态组件，不得表述为 TeslaMate 官方 API。
- 默认端口为 TeslaMate `14000`、Grafana `14001`、TeslaMateAPI `3030`；PostgreSQL 与 MQTT 不映射宿主端口。
- 阶段 1 的三个 Web 端口只用于家庭局域网，说明书明确禁止路由器直通。
- FPK、源码、日志和报告不包含真实密码、Token、邮箱、手机号、VIN、个人公网 IP 或 SSH 材料。
- 普通配置、停止、启动和卸载不得执行卷删除、Docker 全局清理或宿主软件安装。
- 现有工作区包含大量用户迁移改动；只新增/修改本计划列出的 FPK、脚本、规格、计划和报告文件，不提交、不暂存、不回退其他路径。

---

## File Structure

- `release/fnos/teslamate/manifest`：应用中心元数据和主服务端口。
- `release/fnos/teslamate/config/resource`：声明唯一 `teslamate-fnos` Docker 项目。
- `release/fnos/teslamate/config/privilege`：以包用户运行生命周期脚本。
- `release/fnos/teslamate/wizard/install`：首次安装的端口、时区和四项密钥输入。
- `release/fnos/teslamate/wizard/config`：与安装向导同契约的可重复配置页。
- `release/fnos/teslamate/cmd/main`：三端点状态检查和兼容性密码同步入口；Compose 生命周期仍由应用中心管理，真正的数据库健康门禁位于数据库容器自身。
- `release/fnos/teslamate/cmd/*_init`、`*_callback`：无破坏性的 FNOS 生命周期回调。
- `release/fnos/teslamate/app/docker/config.template`：无秘密的变量名和非敏感默认值。
- `release/fnos/teslamate/app/docker/docker-compose.yaml.in`：由镜像锁渲染的五服务 Compose 模板。
- `release/fnos/teslamate/app/ui/config`、`app/ui/images/*`：FNOS 桌面入口与图标。
- `release/fnos/teslamate/image-lock.json`：五个公开来源标签、AMD64 digest 和验证元数据。
- `release/fnos/teslamate/README.zh-CN.md`：普通用户安装、配置、访问和安全说明。
- `scripts/teslamate_fnos_package.py`：镜像锁、渲染、构建、结构/敏感信息复验命令。
- `scripts/test_teslamate_fnos_package.py`：真实包与脚本行为测试。
- `docs/release/teslamate-fnos-stage-1-report.md`：不含秘密的构建和 NAS 验收证据。

### Task 1: 包契约测试与构建器

**Files:**
- Create: `scripts/test_teslamate_fnos_package.py`
- Create: `scripts/teslamate_fnos_package.py`

**Interfaces:**
- Produces: `ImageLock.load(path)`, `render_compose(template, lock) -> str`, `build_fpk(source, output, lock, epoch) -> Path`, `verify_fpk(path) -> VerificationResult`。
- Consumes: 仅 Python 3 标准库；不读取 Docker 凭据或个人环境变量。

- [ ] **Step 1: 写构建与复验 RED 测试**

  用临时目录创建最小合法包 fixture，断言 `build_fpk` 产出包含外层 manifest/config/wizard/cmd/icons/app.tgz/SHA256SUMS，内层 Compose 中五个镜像均来自锁文件且没有模板标记。另写合成敏感材料用例，注入 `user@example.invalid`、`BEGIN PRIVATE KEY`、`Authorization: Bearer synthetic-token` 和 `203.0.113.10`，断言 `verify_fpk` 拒绝。

- [ ] **Step 2: 运行测试确认因生产模块不存在而失败**

  Run: `python3 -m unittest scripts.test_teslamate_fnos_package -v`

  Expected: FAIL，首个错误为无法导入 `scripts.teslamate_fnos_package`。

- [ ] **Step 3: 最小实现可复现构建与安全复验**

  `ImageLock.load` 必须要求恰好五个服务、每项 `platform == "linux/amd64"`、`digest` 匹配 `sha256:[0-9a-f]{64}`。`render_compose` 逐一替换 `@@TESLAMATE_IMAGE@@`、`@@DATABASE_IMAGE@@`、`@@GRAFANA_IMAGE@@`、`@@MOSQUITTO_IMAGE@@`、`@@TESLAMATEAPI_IMAGE@@`，替换后仍有 `@@` 即失败。`build_fpk` 使用固定 uid/gid/mtime 和排序成员生成 `app.tgz` 与外层 gzip tar；`verify_fpk` 重算 SHA-256、复验路径安全和敏感信息规则。

- [ ] **Step 4: 运行测试确认 GREEN**

  Run: `python3 -m unittest scripts.test_teslamate_fnos_package -v`

  Expected: PASS，所有 Task 1 用例 0 failure。

- [ ] **Step 5: 限定差异审计**

  Run: `git diff --check -- scripts/teslamate_fnos_package.py scripts/test_teslamate_fnos_package.py`

  Expected: 无输出。共享工作区不创建混合提交。

### Task 2: 通用 FPK 源文件与行为测试

**Files:**
- Create: `release/fnos/teslamate/manifest`
- Create: `release/fnos/teslamate/config/resource`
- Create: `release/fnos/teslamate/config/privilege`
- Create: `release/fnos/teslamate/wizard/install`
- Create: `release/fnos/teslamate/wizard/config`
- Create: `release/fnos/teslamate/cmd/main`
- Create: `release/fnos/teslamate/cmd/install_init`
- Create: `release/fnos/teslamate/cmd/install_callback`
- Create: `release/fnos/teslamate/cmd/config_init`
- Create: `release/fnos/teslamate/cmd/config_callback`
- Create: `release/fnos/teslamate/cmd/upgrade_init`
- Create: `release/fnos/teslamate/cmd/upgrade_callback`
- Create: `release/fnos/teslamate/cmd/uninstall_init`
- Create: `release/fnos/teslamate/cmd/uninstall_callback`
- Create: `release/fnos/teslamate/app/docker/config.template`
- Create: `release/fnos/teslamate/app/docker/docker-compose.yaml.in`
- Create: `release/fnos/teslamate/app/ui/config`
- Create: `release/fnos/teslamate/app/ui/images/icon_64.png`
- Create: `release/fnos/teslamate/app/ui/images/icon_256.png`
- Create: `release/fnos/teslamate/ICON.PNG`
- Create: `release/fnos/teslamate/ICON_256.PNG`
- Create: `release/fnos/teslamate/README.zh-CN.md`
- Modify: `scripts/test_teslamate_fnos_package.py`

**Interfaces:**
- Consumes: Task 1 的构建与复验函数。
- Produces: 可被渲染成 FNOS Docker FPK 的完整通用源目录。

- [ ] **Step 1: 写真实源目录 RED 行为测试**

  覆盖：manifest 身份/端口；resource 的 `teslamate-fnos`；两个 wizard 的字段集合完全相同；四项秘密均为 password 且有长度规则；Compose 恰好五服务；三 Web 端口可配置；DB/MQTT 无宿主端口；API 强制 `API_TOKEN_DISABLE=false`；PostgreSQL 18 挂载 `/var/lib/postgresql`；生命周期脚本运行时不调用 fake Docker；`main status` 对三个真实临时 HTTP server 全通返回 0、缺一个返回 3。

- [ ] **Step 2: 运行测试确认因源目录缺失而失败**

  Run: `python3 -m unittest scripts.test_teslamate_fnos_package -v`

  Expected: FAIL，明确指向缺失 `release/fnos/teslamate/manifest`。

- [ ] **Step 3: 添加最小 FPK 源文件**

  安装/配置字段固定为 `TESLAMATE_PORT`、`GRAFANA_PORT`、`TESLAMATEAPI_PORT`、`TZ`、`DATABASE_PASS`、`ENCRYPTION_KEY`、`GRAFANA_PW`、`API_TOKEN`。数据库用户名/库名固定 `teslamate`，Grafana 用户固定 `admin`。Compose 用 healthcheck 等待 PostgreSQL；Mosquitto 使用 `/mosquitto-no-auth.conf` 且只在内部网络；三个 Web 端口默认映射 `0.0.0.0`，说明书禁止路由器转发。

- [ ] **Step 4: 复用 TeslaMate 上游图标并明确归属**

  从本机正在运行的 TeslaMate 4.0.1 容器读取 `apple-touch-icon.png`，机械缩放为 64x64 与 256x256；README 说明图标来自 TeslaMate 上游且 FPK 是第三方未签名测试包，避免冒充官方商店发布。

- [ ] **Step 5: 运行行为测试确认 GREEN**

  Run: `python3 -m unittest scripts.test_teslamate_fnos_package -v`

  Expected: PASS，源结构、向导、Compose、脚本和图标全部通过。

### Task 3: 锁定 AMD64 镜像并生成可交付 FPK

**Files:**
- Create: `release/fnos/teslamate/image-lock.json`
- Create: `release/fnos/teslamate/dist/App.Native.TeslaMate_0.1.0_x86.fpk`（构建物，不纳入 Git）
- Modify: `scripts/test_teslamate_fnos_package.py`

**Interfaces:**
- Consumes: 五个候选标签与 NAS Docker 28.5.2。
- Produces: 带真实 AMD64 digest 的镜像锁和可复验 FPK。

- [ ] **Step 1: 写镜像锁边界 RED 测试**

  断言拒绝 ARM64、可变 tag-only 引用、重复服务、缺失服务和 digest 格式错误；断言最终包中 `image:` 恰好五行且全部包含 `@sha256:`。

- [ ] **Step 2: 运行新增测试确认 RED**

  Run: `python3 -m unittest scripts.test_teslamate_fnos_package.ImageLockTests -v`

  Expected: FAIL，当前实现尚未覆盖至少一个新增边界。

- [ ] **Step 3: 在 NAS 拉取并记录 AMD64 镜像**

  候选标签固定为 `teslamate/teslamate:4.0.1`、`postgres:18-trixie`、`teslamate/grafana:latest`、`eclipse-mosquitto:2`、`mytesla/teslamateapi:2.6`。在 `/vol1/1000/teslamate-fpk-stage` 运行锁定命令；每次 pull 后用 `docker image inspect` 要求 `Os=linux`、`Architecture=amd64`，并把公开 RepoDigest 写入锁文件，不记录 Registry 凭据。官方四镜像使用已验证的 DaoCloud 传输地址；TeslaMateAPI 使用规范仓库名与固定 digest，避免把已发生 TLS 握手超时的单一 `docker.1ms.run` 代理写死在包内。

- [ ] **Step 4: 构建和双重复验 FPK**

  Run: `SOURCE_DATE_EPOCH=1786377600 python3 scripts/teslamate_fnos_package.py build --source release/fnos/teslamate --lock release/fnos/teslamate/image-lock.json --output release/fnos/teslamate/dist/App.Native.TeslaMate_0.1.0_x86.fpk`

  Run: `python3 scripts/teslamate_fnos_package.py verify release/fnos/teslamate/dist/App.Native.TeslaMate_0.1.0_x86.fpk`

  Expected: 两条命令 exit 0，输出只含成员数量、版本、大小和 SHA-256。

- [ ] **Step 5: 在 NAS 使用官方 fnpack 构建并复验**

  先用 `ssh Youyooo@192.168.3.82 'mkdir -p /vol1/1000/teslamate-fpk-stage && mktemp -d /vol1/1000/teslamate-fpk-stage/official.XXXXXX'` 取得唯一目录，将无秘密源目录和锁定后渲染的 Compose 复制进去，再运行 `/usr/local/bin/fnpack build --directory "$stage_dir"`；把官方产物复制回 `dist/` 并运行同一个 verifier 的 official 模式。不得覆盖或删除 NAS 其他应用目录。

### Task 4: 飞牛应用中心真实安装与配置页验收

**Files:**
- Create: `docs/release/teslamate-fnos-stage-1-report.md`

**Interfaces:**
- Consumes: Task 3 的官方 FPK、FNOS 应用中心、临时高熵测试凭据。
- Produces: 真实安装、配置页与空库服务证据。

- [ ] **Step 1: 安装前只读快照**

  记录 NAS 主机名、架构、Docker/Compose 版本、剩余空间、14000/14001/3030 监听、现有 `teslamate-fnos` 容器/卷数量。若端口占用、空间低于 10 GB 或已有同名项目，停止并报告。

- [ ] **Step 2: 通过应用中心手动安装**

  打开 FNOS 应用中心“手动安装”，上传官方 FPK。为四个秘密字段各使用独立临时高熵值；不输入 Tesla 账号，不使用个人 API Token。确认安装页字段、帮助文字和错误校验均可见。

- [ ] **Step 3: 验证五服务和本地页面**

  要求五个 `teslamate-fnos-*` 容器运行且 5 分钟内重启次数不增加；NAS 本机与 LAN 分别验证 TeslaMate 14000、Grafana 14001、API 3030。API 未带 Token 应拒绝，带临时 Token 应返回非 401/403 的应用响应。

- [ ] **Step 4: 打开配置页并应用非敏感修改**

  打开应用“设置/配置”，确认八个字段可见且现有秘密不被明文显示。将时区从 `Asia/Shanghai` 改为 `Etc/UTC` 并保存，等待应用中心重建后再改回；两次都要求服务恢复，命名卷 ID 不变。

- [ ] **Step 5: 记录空库基线**

  只执行计数查询，记录 `cars`、`drives`、`charging_processes`、`charges`、`positions`、`tokens` 为 0 或表尚未出现时的迁移状态；不得插入伪造记录。

### Task 5: 停止/启动、卸载保留卷与阶段总结

**Files:**
- Modify: `docs/release/teslamate-fnos-stage-1-report.md`
- Modify: `docs/superpowers/specs/2026-08-11-teslamate-fnos-private-app-design.md`

**Interfaces:**
- Consumes: Task 4 已安装的空数据应用。
- Produces: 可交付包、可重复安装说明、生命周期证据和阶段 2 明确边界。

- [ ] **Step 1: 应用中心停止/启动验收**

  记录五个命名卷 ID，停止应用并确认五容器停止；启动后确认五容器恢复、三个 HTTP 探针通过、卷 ID 未变。

- [ ] **Step 2: 普通卸载保留卷验收**

  从应用中心普通卸载，不选择任何删除数据选项。确认应用文件/容器已移除、五个命名卷仍存在；不得执行任何手工卷删除。

- [ ] **Step 3: 完成敏感信息和破坏性命令终审**

  Run: `python3 scripts/teslamate_fnos_package.py verify-official release/fnos/teslamate/dist/App.Native.TeslaMate_0.1.1_x86_fnpack.fpk`

  Run: `git diff --check -- release/fnos/teslamate scripts/teslamate_fnos_package.py scripts/test_teslamate_fnos_package.py docs/release/teslamate-fnos-stage-1-report.md docs/superpowers/specs/2026-08-11-teslamate-fnos-private-app-design.md docs/superpowers/plans/2026-08-11-teslamate-fnos-stage-1-implementation.md`

  Expected: 两条命令 exit 0；扫描无真实秘密、无 `docker volume rm`、无 `docker system prune`、无宿主安装命令。

- [ ] **Step 4: 写阶段 1 结论**

  报告列出 FPK 绝对路径与 SHA-256、测试计数、官方 fnpack 结果、容器/HTTP/空库/卷证据、UI 配置结果和剩余风险；明确阶段 2 未开始，Mac/VPS/新加坡/手机均未改变。

- [ ] **Step 5: 保持工作区未提交**

  只报告本计划列出的新增/修改路径，不暂存或提交共享工作区中的其他迁移成果。
