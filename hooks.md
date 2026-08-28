# hooks — webhook 声明式插件

> **想接入一个新服务？你不需要懂下面的任何规则。** 把本文件和那个服务的源码/文档地址，
> 交给任意 AI 助手，说"给我接好它"——AI 会写插件、装好、（有源端凭证时）配好源端、
> 触发真事件验证到你能收到通知为止（工作流见 §10 全自动模式）。你最多做的事：源端界面
> 点两下或抄一个密钥。

服务器开一扇门 `POST /hooks/{id}`。门后站一个**翻译员**，行为由一份 YAML 插件文件描述。
插件是**纯数据**（无代码执行），任何人都能写：放进 `hooks/` 目录 + 重启 = 安装；删文件 = 卸载。
官方发行版**不预装任何插件**（`examples/hooks/` 里的只是样例，见 §7）。

**它不是什么**：不是脚本运行时（Gotify plugin 的坟头在那边）、不是市场（无 UI/无远程拉取）、
不支持热加载（改插件需重启，与全仓"改配置需重启"一致）。

## 1. 安装

```
hooks/                 ← 工作目录下固定路径 ./hooks（v1 不进 config）
  memos.yaml           ← 一个插件一个文件，任意文件名
```

- 目录不存在或为空 = 零插件，正常启动。**Docker 部署**：容器工作目录是 `/data`，插件目录即
  `/data/hooks`——compose 挂载一行 `./hooks:/data/hooks`。**挂错路径 = 静默零插件**（ReadDir
  不存在=空集正常启动，无任何报错），10 秒探针：`curl -X POST https://host/hooks/<id>` →
  **401（或 none 族 200）= 已加载；404 = 没加载**（路径挂错了）。
- 加载在启动时一次完成，任何插件不过检 = **启动 fatal**（早失败，防"装了但静默没生效"——
  注意 fatal 只覆盖"找到了但非法"，不覆盖"根本没找到"，所以上面的探针是部署验证的必做步）。

## 2. 插件文件格式

一个文件 = 一个插件。全部字段如下（**未知字段 = 拒绝加载**）：

| 字段 | 类型 | 必填 | 语义 |
|---|---|---|---|
| `id` | string | ✓ | 插件标识 = URL 段 `/hooks/{id}`；`^[a-z0-9][a-z0-9-]{1,31}$`（对齐仓内 slug 白名单）；两个文件同 id = fatal |
| `apiVersion` | string | ✓ | 当前唯一合法值 `hooks/v1`；引擎不认识 = 拒绝加载 |
| `verify` | object | ✓ | 身份验证声明，见 §3。**不写 = 拒绝加载**（不许静默无验证） |
| `filter` | object | ✗ | 事件筛选，不写 = 所有事件都推 |
| `mapping` | object | ✓ | 通知内容，见 §4.3 |
| `device` | string | ✓ | 投递目标：`""` = 广播全部设备；slug 或 uuid = 定向一台。**禁止 key1**（key1=Hotify 部署的主密钥，明文进模板文件 = 新泄漏面，加载时与请求时双重拒） |
| `examples` | list | ✓ | ≥1 条样例，见 §5。**没有 = 拒绝加载** |

## 3. verify — 四种验证形态

webhook 生态的鉴权形态归纳为四族。`type` 取值之一（不适用的族参数会被**静默忽略**——
hmac 写了 secret 之外的 SW 参数不报错也不生效，别留 cargo-cult 残料）：

### 3.1 `standard-webhooks`（memos / Svix / Clerk…）

```yaml
verify:
  type: standard-webhooks
```

无额外参数。行为（引擎实现规范，插件作者无需关心细节，列出供排障）：
- 三个 header `webhook-id` / `webhook-timestamp` / `webhook-signature`，缺任一 = 401
- 签名原文 = `webhook-id + "." + webhook-timestamp + "." + 原始 body 字节`（JSON 解析**之前**对 raw bytes 验）
- `webhook-signature` 是**空格分隔的签名列表**，任一 `v1,` 前缀项匹配即过（密钥轮换期双签兼容）；不认识的前缀（如 `v1a`）跳过不拒
- 比较用常数时间（`hmac.Equal`）
- 时间戳为 unix 秒，容差 **±5 分钟**（双向）；超差 = 401，log 带时钟差值
- 密钥从环境变量读（见 §3.5），剥 `whsec_` 前缀后 base64 解码当 HMAC key；**无前缀 = 裸字节直接用**（两种形态都合法）

### 3.2 `hmac`（GitHub / Gogs / Gitea / Shopify…）

```yaml
verify:
  type: hmac
  header: X-Hub-Signature-256   # 必填，签名所在 header 名
  algo: sha256                  # 必填，sha256 | sha1
  encoding: hex                 # 必填，hex | base64
  prefix: "sha256="             # 可选，签名串前缀（比较前剥掉），默认 ""
```

签名原文 = **原始 body 字节**（无时间戳头）。其余行为：常数时间比较；**签名值按单条整体解码——
不支持空格分隔多签名列表**（那是 standard-webhooks 专属的密钥轮换机制，hmac 族没有）。

### 3.3 `static-token`（GitLab…）

```yaml
verify:
  type: static-token
  header: X-Gitlab-Token    # 必填
```

header 值与环境变量密钥**常数时间相等比较**——比较的是**完整 header 值**（含 scheme 前缀）：
用 `Authorization` 时源端常发 `Bearer <token>`，secret 必须原样含 `Bearer ` 前缀，否则**永久 401**
（"装好了但不工作"的头号成因）。源端能自定义 header 名就**避开 Authorization**（防中间层/反代
剥改），塞 `X-XXX-Token` 走裸值更稳。

### 3.4 `none`（Bitbucket 类只能 IP 白名单的 / 无签名小服务）

```yaml
verify:
  type: none
```

**显式 opt-in 的无验证**（不写 verify 是拒载的；写 none = 明知无签名而为之）。`device` 允许为空
（广播）——"none 必须定向单台"的护栏**预留未启用**（2026-08-28 裁定：单用户自托管下垃圾可删，
真被轰炸出 issue 再加）。
known risk：公开端点，任何人 POST 即可推（广播=全部设备）；注意 payload 格式是开源公开知识，
防不住"照文档编请求"。能用前三族就别用这族——源端支持自定义 header 时塞个 token 走 §3.3
（自己发密码）永远更优。

### 3.5 密钥（secret）

不写在插件文件里（文件会进 git/被分享），从环境变量读：

- 变量名 = `HOOKS_` + id 大写 + 连字符转下划线 + `_SECRET`
- 例：`id: memos` → `HOOKS_MEMOS_SECRET`；`id: github-watch` → `HOOKS_GITHUB_WATCH_SECRET`
- 密钥形态**按族**：`standard-webhooks` 剥 `whsec_` 前缀 base64 解码（无前缀=裸字节）；**`hmac` / `static-token` 一律裸字节原样**（GitHub 官方测试向量 `It's a Secret to Everybody` 含空格非 base64——不做任何解码）
- 启动时解析：`type != none` 而变量未设 = fatal（格式非法仅 SW 族可能）
- ⚠️ 部署文档写密钥时用 compose `environment:` 块（GUI 部署不吃 `.env`，既有教训）

## 4. filter 与 mapping

### 4.1 点路径语法（filter 与 mapping 共用）

- `$` = JSON 根；`$.a.b.c` = 逐层取字段
- 值类型：string / number / bool → 可用；**标量数组 → join ", "**（元素全是标量）；**对象 / 缺失 / null / 元素含对象的数组 → 提取失败**（对象渲染不成通知文本——GitHub `commits[]`/Grafana `alerts[]` 这类数组套对象即此，别引用）
- **不支持**：数组下标、循环、条件、函数调用、任意表达式（白名单刻意封顶，见 §8 逃生门）

### 4.2 filter（可选）

```yaml
filter:
  equals:
    $.activityType: memos.memo.comment.created   # string 期望值
    $.memo.visibility: 2                         # number 期望值（YAML 原生不引号）——仅演示数字匹配；
                                                 # 真实 memos 插件只按 activityType 过滤（examples/hooks/memos.yaml）
```

- `equals` 是 path → 期望值的 map，**多键 = AND**（全部相等才匹配）；`filter: {}`（空 equals）≡ 不写 filter（空 AND 条件集 = 永真）
- 期望值用 YAML 原生类型写（`$.type: notify` 是字符串、`$.priority: 5` 是数字、`$.pinned: true` 是布尔）
- **类型严格匹配**：同类型才比——number 比 number、string 比 string；JSON `5` ≠ `"5"`、`true` ≠ `"true"`；类型不匹配 = **不匹配**（非报错）；**filter 里的路径缺失/null 同样=不匹配**（静默跳过该事件，非报错）
- 不匹配 = 正常静默：响应 `200 {"code":0}`，fileOnly log 带**实际观察到的值**（把"过滤器写错"变成一次 grep 能修的事）

### 4.3 mapping（必填）

```yaml
mapping:
  title: "Memos 新评论"                # 固定字符串
  body: "{{$.memo.content}}"          # 或含占位符的模板
  url: "{{$.link}}"                   # 可选：通知点开跳转
  priority: "4"                       # 可选：也可含占位符；**YAML 字符串，引号别省**（`priority: 4` 裸数字
                                      # =加载 fatal——"自动字符串化"只作用于占位符抽出的值，不管 YAML 字面量）；
                                      # 渲染后落 Ext["priority"]（字段归宿：入站不替出站决定生死——
                                      # ntfy 出站已消费 1-5，harmony 将来支持 importance 时再读）
```

- `title` / `body` 至少一个渲染后非空；**渲染成功但 title/body 双空 = 视同提取失败**（200+stdout log，不产空通知）
- 占位符 `{{$.path}}`，一条模板里可多个；**单遍替换**（抽出的值永不二次扫描——评论内容里含字面 `{{$.x}}` 不会展开）
- **分级语义**（2026-08-28 三源压测钉死）：
  - `title`/`body` = **主体**——占位符路径**缺失/null/对象/对象数组** = 整条提取失败：`200 {"code":0}` + **stdout log**（真故障留屏——区别于 filter miss 的 fileOnly；"模板腐烂"最坏的失败形态，必须可观测）
  - `url`/`priority` = **装饰**——同样情况 = **省略该字段照发**（丢跳转链接远比丢通知强；源字段 nullable 时引用它才安全）
- number/bool 自动字符串化（`5` → `"5"`、`true` → `"true"`）；数组 join ", "

## 5. examples — 模板必须自带测试

每条 = 一个输入样本 + 期望产出。**两条用途**：启动自检（§6）+ 引擎回归测试集。

```yaml
examples:
  - name: comment-created
    body:
      url: https://push.example.com/hooks/memos   # ⚠️ 顶层 url 是 webhook 目标地址回显，不是 memo 深链
      activityType: memos.memo.comment.created
      creator: users/golden                        # v0.30 形态=users/{username}（非数字 id）
      memo: { name: "memos/x1", content: "好文！", visibility: 2 }
    expect:
      pass: true
      title: "Memos 新评论"
      body: "好文！"
  - name: memo-updated-ignored
    body:
      activityType: memos.memo.updated
    expect:
      pass: false        # 期望被 filter 拒
```

> ⚠️ **wire 格式 ≠ 源端 REST API 响应**：memos 的 API 走 protojson（时间戳 RFC3339 字符串、枚举是名字），
> webhook body 走 encoding/json（内层 snake_case、时间是 `{"seconds":N}` 结构、枚举是数字）。拿 API 响应
> 当"真实捕获"填 examples，自检照样绿（自检不碰未引用字段），漂移完全无声。捕获只认 webhook 原始 body。

| 字段 | 类型 | 必填 | 语义 |
|---|---|---|---|
| `name` | string | ✓ | 用例名（log/失败信息引用） |
| `body` | object | ✓ | 源端 payload 样本（JSON） |
| `expect.pass` | bool | ✓ | true = 应产出通知；**false = 整条管道不产出通知**（filter miss / 提取失败 / 双空渲染，任一环节断掉即成立——无 filter 插件的负样本 = 提取失败型） |
| `expect.title` / `expect.body` | string | pass=true 时必填 | 期望渲染结果（逐字相等）。**expect 只断言 title/body**——url/priority 的装饰降级行为不可在 examples 中断言（别写 expect.url，未知字段=拒载） |

**examples 分两型**（按源的 wire 形态选，二选一）：

- **捕获型**（固定 wire 源——memos/GitHub…body 格式源端定死）：body 必须源自**真实捕获**
  （源端文档/源码/真机抓包）。自造样本 = 循环验证，只验引擎不验现实（memos 官方文档落后于代码的教训）。
- **契约型**（模板型源——healthchecks/n8n…body 全文由部署者在源端配置，无固定 wire）：插件作者
  在文件注释里定义 **canonical body**（部署指令的一部分——教部署者在源端怎么配；实物样板见
  `examples/hooks/healthchecks.yaml` 与 `n8n` 同族），examples = canonical body 的实例。此时 examples
  验证的是**契约自洽**（部署者照指令配出的任何真实事件必然渲染出 expect 结果），字段取值语义须钉到
  源端占位符实现（如 `$NAME_JSON` 的 JSON 安全性）。**契约违例负样本合法**：body 由部署者控制，
  "漏必填字段"是真实可能形状——它是契约型的 filter-miss 等价物（正当地固化"漏字段→不产通知"）。
  两条设计自由度：**条件文案优先放源端模板语言**（Handlebars/if_equals——比在 Hotify 侧赌字段存在性强，
  grafana/jellyfin 样板同款）；可把可空字段在源端模板**规约成恒在空串**再引用（规避主体提取失败）。
  实例值边界：形状与类型可构造（uuid/ISO/枚举字面量），**语义值不可编**（用真实样例数据+注释标注）。
  目标场景若源端无精确触发器（Immich 无"相册新增"只有"资产入库"），**必须头注释声明近似关系**。

两型共同铁律：**每个取值可追溯到源端事实**（捕获/源码/契约定义），禁止凭空想象。

**捕获型的降级档**（文档样例断供或陈旧时——GitHub 现行文档已不发 push 样例、Grafana 文档样例落后于代码，均实证）：
按"字段值各有官方出处、整体形状拼装"构造合法，但**必须在样本注释如实标注降级档**（如"值取自字段表+归档样例，整体拼装"），且**文档样例与源码矛盾时以源码为准**（memos/Grafana 两次实证文档落后）。

## 6. 请求处理时序（引擎行为规范）

```
POST /hooks/{id}（body ≤ 1MB，超限=413，与 bark/gotify/ntfy 三入口同限；**引擎不检查
Content-Type**——按原始字节做 JSON parse，源端发 text/plain 也能收，只要字节是合法 JSON）
→ 未知 id → 404
→ verify 段（按 type 分派；失败 → 401，log 带 clock delta）
→ 去重（仅 standard-webhooks 有 webhook-id 时；TTL 5min，容量封顶 4096；重复 → 200 {"code":0}）
→ JSON parse 失败 → 200 {"code":0} + stdout log（防源端重试；真异常可观测）
→ filter 不匹配 → 200 {"code":0} + fileOnly log（带观察值）
→ mapping 提取失败 → 200 {"code":0} + stdout log
→ device 解析（请求时解析，非加载时——设备增删不该要求改模板；空=广播 0 / slug|uuid=定向；失败 → 200 + stdout）
→ 构造 model.Message（Ext 三件：`hook`=id 归因 / **`payload`=原始 body 整存**（入站全保留——mapping 未引用
  的事件字段不 drop，同 bark ext_params/gotify extras 的 JSON 整存惯例，出站按需 unmarshal）/ `priority`=mapping.priority 渲染值）
→ ingest 落桶 → fanout 照常（与门无关，按设备投递）
→ 响应一律 200 {"code":0}
```

**为什么所有成功路径都返 `{"code":0}`**：memos 判定投递成功 = `2xx` 且 body JSON `code == 0`；
空 body 的裸 200 会被记为投递失败（json.Unmarshal 空 body 报错）——污染源端失败信号。
其他源（GitHub 等）只看 2xx，此响应体无害。

**401 vs 200 的界线**：只有"验签失败"用 401（让遵守重试语义的源端停手）；验签之后的
一切（filter miss / 提取失败 / device 失效）都是 200——源端重试救不了这些，重试只会造成通知风暴。

**失败形态 × 响应 × 日志道速查**（一处看全，别再拼 §4.2/§4.3/§6 三处）：

| 失败形态 | HTTP | 日志道 | 含义 |
|---|---|---|---|
| 验签失败（含时钟漂移） | 401 | fileOnly（带 delta） | 安全事件/配置错 |
| filter 不匹配 | 200 `{"code":0}` | fileOnly（带观察值） | **正常运转**（源发别的事件） |
| body 不是 JSON | 200 | stdout | 源端行为异常 |
| 主体提取失败（title/body） | 200 | stdout | **模板腐烂**（源端改形状）——最坏形态，必须留屏 |
| 装饰提取失败（url/priority） | 200 | 无（省略照发） | 不是失败 |
| device 失效（slug/uuid 不在） | 200 | stdout | 设备删了/模板 device 过期 |

## 7. 启动自检（两道关）

加载每个插件时，在内存里跑两道关，任一失败 = fatal：

1. **secret 可解析**：`type != none` 时环境变量已设且格式合法
2. **examples 干跑**：对每条 example 用真引擎跑 filter + mapping 段（验签段不跑——
   secret 是部署者的，模板作者无法预签名），产出与 `expect` 逐字比对

自检意味着：**插件集 = 引擎的回归测试集**。引擎将来改语义，全世界插件启动即红——
向前兼容不靠自觉，靠启动 fatal。

## 8. 表达力逃生门

白名单刻意封顶（不追求图灵完备——模板想表达一切就会长成一门编程语言：语法坑/安全面/调试地狱）。
表达不了的（数组循环、事件名决定文案、回查源端 API…）= **写 Go 皮**：新文件照 `ntfy.go` 的壳
（`registerXxxRoutes` + guard + 一行注册），核心零改。这是架构文档早就许诺的路，不是插件系统的失败。

## 9. known limitations

- 重试型源（Svix 退避横跨数天）超过 5min 去重窗 → 可能重复通知（通知幂等要求低，接受）
- **源端有意重发型**（uptime-kuma resendInterval 重发告警 / GitHub 手动 redelivery）无 webhook-id 去重 → 必然重复通知（这是 feature，知情接受）
- **零重发型**（Immich fire-and-forget 等）→ Hotify 宕机瞬间的事件即丢、源端不留痕——通知场景可接受，知情接受
- 时钟漂移 > 5min → standard-webhooks 全量 401（401 log 带 delta，一眼可诊）
- 单 filter 单 mapping：一个源多事件要不同文案 → v1 不支持（将来 schema 一次性演进，模板外置改版无兼容负担）
- 无热加载（重启生效）
- v0:{ts}:{body} 型签名（Slack）不支持（hmac 族只签裸 body）

## 10. 翻译指引（把一个 webhook 桥翻译成插件）

**产出物=双件套，缺一不可**（插件有两个受众：引擎读字段，部署者读步骤——零配置在 webhook 机制下
不可能，最少配置 2 项：源端指过来 + 密钥给 Hotify，说明的价值就是讲成可照抄的动作）：

1. **模板 YAML**（给引擎）：§2 全字段
2. **部署说明**（给使用者，v1 形式 = YAML 文件头注释，单文件自包含——**读者是人+AI 双读者**：
   动作粒度精确到可照抄，AI 不需要理解就能执行，人不需要懂规则就能跟着做；刻意不拆独立 .md，
   两文件迟早漂移。**引用规则条文时句子必须自含结论**——条目号（§N）只作深入线索，这份文件可能被
   单独分发，断链不算错但每句话单独读必须成立），四件套：
   a. **Hotify 侧**：放哪个目录（**docker 部署必带挂载行 `./hooks:/data/hooks`**）+ 环境变量名（值从哪来）+ 重启
   b. **源端侧**：去源端哪里配、URL 填什么、**凡源端配置会影响 body 形状或鉴权形态的**（模板型 body/预设选择/订阅事件范围/自定义 header/method）都**给可直接照抄的原文**——捕获型源也有配置岔路（uptime-kuma 的 json/form/custom 三预设、GitHub 的 json/form 二选一），锁定配置=插件 wire 契约的一部分。**源端若有 SSRF 私网防护必给放行 env**（自托管 Hotify 几乎必在私网——memos `MEMOS_ALLOW_PRIVATE_WEBHOOKS` / healthchecks `INTEGRATIONS_ALLOW_PRIVATE_IPS`，通病）。UI 表单填法为主；无头场景读者可自查源端 API 等价路径
   c. **验证一步**：怎么触发一个真事件、确认收到——**前置**：至少一台设备已 onboard（0 设备时链路全绿但没人收）；真事件难造时给降级配方（按 wire 形态 curl 一条）
   d. **排障段**：日志在哪（本机=工作目录 `hotify.log`；**docker=`/data/hotify.log`，`docker logs` 只见启动行和 `[hooks] delivered`，filter miss/401 要进 volume 看**）；探针 404 双形态（body=`unknown hook`=插件没加载/目录挂错；body=`not found`=请求形状错如用了 GET）；验证判据行=`[hooks] <id> delivered`（stdout，`docker logs` 可见）

**全自动模式（给 AI 作者的授权）**：目标不是"交付文件"是"**能用**"——你不只是写插件：

1. 写双件套（上面的模板+部署说明）
2. **装**：YAML 放进 hooks/ + secret 写进环境变量 + 重启 server（自托管可直达时自己做；
   不可达时给用户精确指令）
3. **源端配置**（按凭证分岔）：
   - 有源端 API 凭证（如 GitHub repo token、memos 账号）→ 直接调 API 建 webhook、
     取签名密钥、写进 env——全自动到底
   - 无凭证 → 停在这步，把"点哪里/抄哪个值"压成 ≤2 条可照抄指令给用户，完成后继续
4. **验证**：触发一个真事件（源端 Test 按钮/造一条真数据），确认消息落桶（`[hooks] … delivered`）
   或手机收到通知。**全绿才算完成**——装上但没验过 = 未完成。

给 AI / 人类读者的操作步骤：

1. **读源端的发送侧**（优先级：源端源码 > 官方 API 文档 > 桥的实现；⚠️ **文档缺席 ≠ 功能不存在**——
   Immich 的 webhook 在 v3 源码里而文档站至今无此页，只查文档会得出"没有 webhook"的假阴性；
   嫌疑源找不到 webhook 时 grep 源码里的 `webhook/hmac/signature/trigger` 关键词再下结论）。
   顺带问**事件量级**（per-item 逐条发还是聚合？首次全量会来多少条？——Immich 每照片一发，
   首次备份=风暴，部署说明必须预警）。回答四个问题：
   a. 它怎么签名请求？（四族里哪族：三 header=standard-webhooks / 单 HMAC header=hmac / 裸 token=static-token / 什么都没有=none）
   b. payload 里哪个字段区分事件类型？**判别字段在 header 的源**（GitHub 的 `X-GitHub-Event`）：filter 只能读 JSON body，写不了——正确姿势=源端订阅配置只勾目标事件（部署契约的一部分）+ mapping 引用目标事件**独有字段**兜底（别的事件来了提取失败自然静默）。
   c. 通知正文应该取哪些字段？
   d. 事件样本长什么样？（真实样本，用于 examples）
2. 写 YAML：`id` 起名 → `verify` 选族 → `filter` 填事件判别字段（**用 equals 精确匹配确切事件名**，别移植桥的子串/模糊判断）→ `mapping` 拼标题正文 → `device` 默认 `""`——桥若是"单设备 token 投递"语义，保持广播默认并在模板注释里告知部署者可改 slug/uuid 恢复单设备语义
3. 用真实样本填 `examples`（含期望产出；至少 1 条正样本。有 filter 的源加 1 条 filter-miss 负样本；
   无 filter 的源可加提取失败负样本（可选）——`pass: false` = 整条管道不产出通知，见 §5。
   **无真实失败路径的源（所有引用字段恒存在）可不带负样本——禁止为凑负样本编造 payload**）
4. 放入 `hooks/`，设环境变量，重启——自检红 = 按报错修，绿 = 装好了
5. 端到端验证：源端触发一个真事件，手机收到通知
