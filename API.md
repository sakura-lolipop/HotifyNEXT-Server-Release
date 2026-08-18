# Hotify Server API

Base URL 记为 `https://your-domain.example`（未配证书时为 `http://<主机>:8443`）。

## 总览

### 鉴权

两种凭证，能力分层——凭证越强的入口能做的事越多：

| 凭证 | 用法 | 能力 |
|---|---|---|
| **key1**（主凭证） | `Authorization: Bearer <key1>` 头 | 全部 `/api/v1/*`：推消息、拉历史、WebSocket、设备与凭证管理、备份 |
| **设备 key**（每台设备的标识） | 放在 URL 里（bark 路径 / gotify token 位） | 兼容入口：往设备推一条消息 / 广播 |

key1 在首台设备注册时生成（见「设备注册」）；设备 key 在设备列表中查看。

### 响应格式

所有原生接口返回统一 envelope：`{ "code": <同 HTTP status>, "message": "…" }`，`Content-Type: application/json`。数据类接口在 envelope 上附加数据字段（如 `messages`）。

⚠️ **`code:200` 不等于推送成功**——消息已保存但离线推送失败时，`message` 含 `saved but push failed`。脚本请检查 `message` 字段。

## 发送消息

四个入口，能力不同：**只有原生接口支持上传媒体附件**。

| 入口 | 凭证 | 投递目标 | 媒体上传 |
|---|---|---|---|
| `POST /api/v1/push` | key1 | 定向 / 广播 | ✅ |
| `GET·POST /<设备key>/…`（bark 风格） | 设备 key 或 key1 | 定向该设备 / key1=广播 | ❌ |
| `POST /message?token=`（gotify 风格） | 设备 key 或 key1 | 广播全部设备 | ❌ |
| `POST /broadcast/…` | 设备 key 或 key1 | 广播全部设备 | ❌ |

### 原生：POST /api/v1/push

```bash
# JSON 文本消息
curl -X POST https://your-domain.example/api/v1/push \
  -H 'Authorization: Bearer your_key1' \
  -H 'Content-Type: application/json' \
  -d '{"title":"服务器告警","body":"CPU 95%","url":"https://example.com/dashboard"}'
# → {"code":200,"message":"success","hlc":"…","client_msg_id":"…"}
```

- `title` / `body` 至少一个；`url`（点击跳转）、`image_url`（通知大图）、`category` 可选
- `target_profile_id`：定向私聊时填目标（值为 profile id，从 `GET /api/v1/devices` 取，**不是设备 key**）；空 = 广播
- `client_msg_id`：可选调用方消息 id（≤128 字节）；响应原样回显，用于发送去重
- `sender_uuid`：可选，以某台设备身份发送（消息带来源标识）
- 返回的 `hlc` 是这条消息的 id（字符串），用于删除、翻页

**带附件**（multipart）：form 字段 `meta` 放消息 JSON（同上字段集），`file` part 放文件（可多个）。单次上限默认 4GiB（可配）。

### bark 风格 / gotify 风格 / 广播

见 [README](README.md) 的「兼容 bark / gotify 生态」——含完整 curl 示例与参数说明。要点：

- bark：key 在路径（`/<key>/<标题>/<正文>` 最多四段），未识别参数不丢弃原样保留
- gotify：`POST /message` + `?token=` / `X-Gotify-Key` 头 / Bearer；`message` 必填；语义为广播全部设备
- 显式广播：`POST /broadcast/<key>/<标题>/<正文>`（bark 形）/ `POST /broadcast?token=`（gotify 形）
- 凭证不存在 → `400 device not registered`，不落库

## 接收消息

### 拉历史：GET /api/v1/messages

```bash
# 最新消息（?limit=1..200，默认 50）
curl -H 'Authorization: Bearer your_key1' \
  'https://your-domain.example/api/v1/messages?limit=50'

# 向更早翻页：?before=<消息id>
# 重连补漏（增量）：?since=<消息id>
```

响应：`{ "code":200, "messages":[ … ] }`，消息按时间升序。消息对象含 `title` / `body` / `url` / `image_url` / `media`（附件列表，`[{size,mime},…]`）/ 时间戳等字段。

### 取附件：GET /api/v1/media/{消息id}/{序号}

```bash
curl -H 'Authorization: Bearer your_key1' -o photo.jpg \
  'https://your-domain.example/api/v1/media/<hlc>/0'
```

流式返回。此端点也接受 `?key1=` query 鉴权（浏览器直接打开附件用；其余端点只认 header）。

### WebSocket 实时：GET /api/v1/stream

连接后**首帧发 JSON 鉴权**：`{"key1":"your_key1"}`，之后实时收新消息帧。断线重连后用 `GET /api/v1/messages?since=<最后消息id>` 补漏。

### 阅读进度：POST / GET /api/v1/cursor

多设备同步「读到哪了」：POST 上报当前消息 id，GET 读回。覆盖式单值。

## 设备与凭证

### 注册：POST /api/v1/register

```bash
curl -X POST https://your-domain.example/api/v1/register \
  -H 'Content-Type: application/json' \
  -d '{"uuid":"设备UUIDv4","platform":"harmony","push_token":"推送token","name":"我的手机"}'
# → {"code":200,"message":"registered","key1":"…","key2":"…"}
```

- 必填：`uuid` / `platform`（`harmony`/`ios`/`android`/`windows`）/ `push_token`
- 空服务器首台设备注册可不带凭证（生成 key1 下发）；之后注册需 `Authorization: Bearer <key1>`
- 同 uuid 重复注册 = 刷新推送 token，身份不变

### 设备列表：GET /api/v1/devices

`Authorization: Bearer <key1>`。返回全部设备（类型 / 名称 / 最后在线 / profile id）。

### 凭证轮换

```bash
# 查当前分享 URL
curl -H 'Authorization: Bearer your_key1' https://your-domain.example/api/v1/share-url
# → {"code":200,"key2":"…","share_path":"/share/K2…"}

# 换分享地址（老地址作废，设备无感）
curl -X POST -H 'Authorization: Bearer your_key1' https://your-domain.example/api/v1/rotate-key2

# 换主凭证（⚠️ 老设备全部失联，需重新接入；body {"key1":"新值"} 可自定）
curl -X POST -H 'Authorization: Bearer your_key1' https://your-domain.example/api/v1/rotate-key1
```

## 运维

```bash
# 版本/构建信息（公开无鉴权，探活首选）
curl https://your-domain.example/api/v1/info
# → {"code":200,"version":"v1.0-L2.1","commit":"…",…}

# 整库流式备份（不停机，输出 db 字节流）
curl -H 'Authorization: Bearer your_key1' \
  -o backup.db https://your-domain.example/api/v1/backup

# 删单条消息
curl -X DELETE -H 'Authorization: Bearer your_key1' \
  https://your-domain.example/api/v1/messages/<hlc>

# 范围删除（from_ts/to_ts=毫秒时间戳）/ 全清（无参数）
curl -X DELETE -H 'Authorization: Bearer your_key1' \
  'https://your-domain.example/api/v1/messages?from_ts=…&to_ts=…'

# 删设备（消息保留）
curl -X DELETE -H 'Authorization: Bearer your_key1' \
  https://your-domain.example/api/v1/devices/<uuid>
```

## 错误码

| HTTP | 含义 |
|---|---|
| 400 | 请求错误（缺字段 / key 不存在 `device not registered` / 超长） |
| 401 | key1 缺失或不符 |
| 404 | 端点不存在或对象不存在 |
| 410 | 已废弃端点 |
| 413 | 请求体超限 |
| 415 | Content-Type 既非 JSON 也非 multipart |
| 500 / 502 / 503 | 服务器内部错误 / 上游推送通道失败 |

错误响应同 envelope：`{"code":<status>,"message":"<原因>"}`。
