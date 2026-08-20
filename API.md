# Hotify Server API

Base URL 记为 `https://your-domain.example`（未配证书时为 `http://<主机>:8443`）。

## 总览

### 鉴权

两种凭证，能力分层——凭证权限越高，可执行的操作越多：

| 凭证 | 用法 | 能力 |
|---|---|---|
| **key1**（主凭证） | `Authorization: Bearer <key1>` 头 | 全部 `/api/v1/*`：推消息、拉历史、WebSocket、设备与凭证管理、备份 |
| **设备 uuid**（每台设备的标识，可用 slug 别名替代——slug：自行设置的短别名，见「设备地址别名」） | 放在 URL 里（bark 路径 / gotify token 位） | 兼容入口：往设备推一条消息 / 广播 |

key1 可在浏览器打开 `/setup` 设置获取，或首台设备注册时自动生成（见「设备注册」）；设备 uuid 在设备列表中查看。

### 响应格式

所有原生接口返回统一 envelope：`{ "code": <同 HTTP status>, "message": "…" }`，`Content-Type: application/json`。数据类接口在 envelope 上附加数据字段（如 `messages`）。

⚠️ **`code:200` 不等于推送成功**——消息已保存但离线推送失败时，`message` 含 `saved but push failed`。脚本请检查 `message` 字段。（例外：gotify 兼容入口返回 gotify 原生格式、不回传推送结果。）

## 发送消息

四个入口，能力不同：**只有原生接口支持上传媒体附件**。

| 入口 | 凭证 | 投递目标 | 媒体上传 |
|---|---|---|---|
| `POST /api/v1/push` | key1 | 定向 / 广播 | ✅ |
| `GET·POST /<uuid或slug>/…`（bark 风格） | 设备 uuid（或其 slug 别名）或 key1 | 定向该设备 / key1=广播 | ❌ |
| `POST /message?token=`（gotify 风格） | 设备 uuid（或其 slug 别名）或 key1 | 广播全部设备 | ❌ |
| `POST /broadcast/…` | 设备 uuid（或其 slug 别名）或 key1 | 广播全部设备 | ❌ |

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
- `target_profile_id`：定向推给某台设备时填目标（值为 profile id，从 `GET /api/v1/devices` 取，**不是设备 uuid**）；空 = 广播
- `client_msg_id`：可选调用方消息 id（≤128 字节）；响应原样回显，供调用方关联请求与消息。**服务端不做幂等去重——重发会生成新消息**
- `sender_uuid`：可选，以某台设备身份发送（消息带来源标识）
- 返回的 `hlc` 是这条消息的 id（字符串），用于删除、翻页

**带附件**（multipart）：form 字段 `meta` 放消息 JSON（同上字段集），`file` part 放文件（可多个）。单次上限默认 4GiB（可配）。

### bark 风格 / gotify 风格 / 广播

见 [README](README.md) 的「兼容 bark / gotify 生态」——含完整 curl 示例与参数说明。要点：

- bark：凭证在路径（`/<凭证>/<标题>/<正文>` 最多四段），未识别参数不丢弃原样保留
- gotify：`POST /message` + `?token=` / `X-Gotify-Key` 头 / Bearer；`message` 必填；语义为广播全部设备
- 显式广播：`POST /broadcast/<凭证>/<标题>/<正文>`（bark 形）/ `POST /broadcast?token=`（gotify 形）
- **以设备身份广播**：广播入口凭证用设备 uuid 时消息带该设备的来源标识（其他设备显示「来自 XX」）；用 key1 则匿名。原生接口等价用法：`POST /api/v1/push` 带 `sender_uuid`（见上）
- 凭证不存在 → `400 device not registered`，不落库

## 接收消息

### 拉取历史：GET /api/v1/messages

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

流式返回。此端点也接受 `?key1=` query 鉴权（浏览器直接打开附件用；其余端点仅接受 header 鉴权）。

### WebSocket 实时：GET /api/v1/stream

连接后**首帧发 JSON 鉴权**（`type` / `uuid` / `key1` 三字段必填）：

```json
{"type":"auth","uuid":"<设备uuid>","key1":"your_key1","since":"0"}
```

`since` 可选（缺省=只拉最新）。之后实时收新消息帧。关闭码：**4401** = key1 错（勿重连）/ **4402** = 协议错（立即重连）/ 4000 = 服务端重启（退避重连）。断线重连后用 `GET /api/v1/messages?since=<最后消息id>` 补漏。

### 阅读进度：POST / GET /api/v1/cursor

多设备同步「读到哪了」，覆盖式单值：

```bash
curl -X POST -H 'Authorization: Bearer your_key1' -H 'Content-Type: application/json' \
  -d '{"view":"messages","focus_hlc":"<消息id>"}' \
  https://your-domain.example/api/v1/cursor
```

## 设备与凭证

### 注册：POST /api/v1/register

```bash
curl -X POST https://your-domain.example/api/v1/register \
  -H 'Content-Type: application/json' \
  -d '{"uuid":"设备UUIDv4","platform":"harmony","push_token":"推送token","name":"我的手机"}'
# → {"code":200,"message":"registered","key1":"…","key2":"…（预留字段，当前版本无消费功能）"}
```

- 必填：`uuid` / `platform`（`harmony`/`ios`/`android`/`windows`）/ `push_token`
- **注册时填的 `uuid` 就是兼容入口的凭证**——bark `/<uuid>/标题/正文`、gotify `?token=<uuid>` 用的都是它（slug 别名同样可用）
- 空服务器首台设备注册可不带凭证（生成 key1 下发）；也可 body 带 `"key1":"自定值"` 直接作为 key1 使用；之后注册需 `Authorization: Bearer <key1>`
- 同 uuid 重复注册 = 刷新推送 token，身份不变

### 设备列表：GET /api/v1/devices

`Authorization: Bearer <key1>`。返回全部设备（类型 / 名称 / 最后在线 / profile id）。

### 设备地址别名：PUT /api/v1/devices/{uuid}/slug

给设备设一个短名，替代兼容入口里的 36 位 uuid（bark 路径、gotify token、客户端 token 输入框均可填别名，语义与设备 id 完全相同）：

```bash
curl -X PUT -H 'Authorization: Bearer your_key1' -H 'Content-Type: application/json' \
  -d '{"slug":"pad"}' \
  https://your-domain.example/api/v1/devices/<uuid>/slug
# → {"code":200,"message":"…","slug":"pad"}
```

- 格式：小写字母/数字/连字符，2-32 字符（`^[a-z0-9][a-z0-9-]{1,31}$`）
- 全域唯一（被其他设备占用 → `409 slug taken`）；格式错 → 400
- 别名请避开与 key1 同名（同名时按 key1 解析，定向会变成广播）
- `{"slug":""}` = 清除；**换值后旧别名立即失效**（别名疑似泄露时更换新值即可吊销旧别名）

### 凭证轮换

```bash
# 换主凭证（⚠️ 旧设备全部失去连接，需重新接入；body {"key1":"新值"} 可自定）
curl -X POST -H 'Authorization: Bearer your_key1' https://your-domain.example/api/v1/rotate-key1
```

## 运维

```bash
# 版本/构建信息（公开无鉴权，探活首选）
curl https://your-domain.example/api/v1/info
# → {"code":200,"version":"v1.0","commit":"…",…}

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
