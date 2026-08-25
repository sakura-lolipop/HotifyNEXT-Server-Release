# fpkpath — 飞牛 fnOS 打包踩坑与机制账本

> 惯例同 HotifyNEXT/archpath.md：fpk 相关结构性踩坑与机制结论落这，不进 auto-memory。2026-08-25 v1.2.0→v1.2.1 一天三轮（图标灰→向导扩→空地址）的总结。机制结论全部来自 **conversun/fnos-apps 155 个现役 app 全量普查 + wg-easy/n8n/mihomo/miair-next 深读**，非官方文档转述。

## 现象与根因（v1.2.0「点应用地址是空的」）

- ui/config 写了 `"port": "${wizard_port}"`——app-entry 文档明确合法（"需要使用向导中收集的端口时，可以使用 `${wizard_port}`"），**但野外替换不稳**：155 个现役 app 里 154 个用字面量，唯一用 `${wizard_port}` 的（miair-next）是孤例。用户实测=空地址（替换没发生或值没收集到）。
- compose 侧同写法却没事——因为加了 `:-8443` 兜底（docker compose 原生语法，fnOS 没喂变量时回落）。**双保险只保了一侧的教训：两侧机制不同（compose 插值 vs fnOS 入口替换），不能假设同命运。**

## 机制结论（普查级证据）

| 机制 | 结论 | 证据 |
|---|---|---|
| `${wizard_*}` → compose 替换 | **通**。向导值由 fnOS 喂给 docker compose 环境，容器侧拿到 | wg-easy `INIT_PASSWORD=${wizard_password:-}` 实证 |
| 装时改端口 | **物理不可能**。fnOS 建**容器早于 install_callback**，脚本 patch 只落磁盘进不了已建容器 | wg-easy 代码注释原文（"Patching the compose in service_postinst cannot work"）；155-app 里**装时收端口=0 个** |
| ui/config 端口 | **字面量**（154/155） | 全量 grep；Hotify 用户实证占位符=空地址 |
| compose 宿主端口 | **`${TRIM_SERVICE_PORT}:容器口`**（40+ 处）。TRIM_SERVICE_PORT=fnOS 系统变量，manifest service_port 的运行态 | 全量 grep |
| 端口改动入口 | **wizard/config（应用设置）**，非 wizard/install——76 个 app 在 config 收端口 | 全量统计（install 收端口 0 / config 76） |
| config 流改端口 | `cmd/service-setup` 的 `service_postconfig` 钩子：读 `$wizard_port` → **sed 改写 compose 端口行** + 存 `${TRIM_PKGVAR}/.port`；`service_postupgrade` 升级后恢复 | n8n/wg-easy 完整实现；153/155 有此脚本 |
| checkport | `false`（生态主流）——端口冲突不挡安装，装完进设置改 | wg-easy/n8n manifest |
| wizard/install 本身 | 合法常用（73/155 有），收**非端口**项（路径/密码/host） | 全量统计 |

## Hotify v1.2.1 对齐清单（参照 wg-easy——与咱需求同型：装时向导+端口+env 注入）

- manifest：`checkport = false`，service_port=8443
- compose：`ports: - "${TRIM_SERVICE_PORT}:8443"`（**引号必须保留**——service-setup 的 sed 按带引号 `"…:8443"` 模式匹配改写）；env 保持 `${wizard_*:-默认}` 注入
- ui/config：`"port": "8443"` 字面量
- wizard/install：保留（含端口字段——`wizard_port` 疑似 fnOS 保留字段名绑原生端口设置，字段无害）；wizard/config：端口项（装后改）
- cmd/service-setup：n8n 形状照抄（postconfig apply_port / postupgrade 恢复 / postinst）
- 官方骨架的 9 个 cmd 生命周期脚本保留（no-op 无害）

## 未验项（真机清单）

- `wizard_port` 保留字段假说（绑 fnOS 原生端口设置→图标跟随）——文档未明说，行为待真机
- config 流改端口后：容器是否自动重建、图标是否跟随
- 应用中心图标灰（v1.1.x 报过一次）：圆角+RGB 已换，**根因未坐实**，若复发 SSH `ls -la /var/apps/hotify-server/` 取证

## 打包纪律（老坑，防复发）

- fnpack 必须 **Linux 侧**打（Docker alpine 即可）：Windows 版产物 cmd 丢执行位 + manifest 带 CRLF（`#!/bin/bash\r` 上机即挂）
- 重建 dist-gitee 类产物目录先清场（gitee-upload.sh 曾混传旧版本文件）
- fpk 结构/接线改动后：tar 开包验 cmd 权限、manifest 行尾、compose/ wizard JSON 内容三件套
