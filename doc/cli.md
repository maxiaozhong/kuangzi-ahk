# 框子 CLI 手册

> `kuangzi` 命令行接口：无界面、跑完即退，供智能体（ZCode 等）与脚本调用。与 GUI 版共享同一份配置和日记库。
>
> 智能体用户优先读仓库 `skills/kuangzi-cli/SKILL.md`（同一内容的操作视角）；本文是完整参考手册。

## 前置条件

- 已安装框子 GUI 版并完成首次运行（配置创建权在 GUI 首跑；CLI 不独立建配置，未安装时报"框子未安装"）
  - 例外说明：CLI 可以**改写**已有配置里的搜索引擎表与快捷启动词表（`engine` / `word` 命令），但不新建配置、不动其它键
- `kuangzi` 已在 PATH（安装器勾选"加入 PATH"即自动配好）

连通性验证（零副作用）：

```bash
kuangzi --version
# → kuangzi cli v0.2.261017
```

## 语法

```
kuangzi <命令> [参数] [--json]
```

`--json` 是全局标志，可放任意位置；智能体调用建议始终带上。

## 命令一览

> 以下命令表由 `kuangzi --help` 输出生成，二者不一致时以 `--help` 为准。

| 命令 | 用法 | 说明 |
|---|---|---|
| note | `kuangzi note "文本"` | 速记（写入今日日记，多行保留） |
| todo | `kuangzi todo "文本"` | 待办（写入今日日记） |
| note / todo（无文本） | `kuangzi note [--date D] [--scope S]` | 查询态：按日期查该节内容 |
| note / todo -（stdin） | `echo "文本" \| kuangzi note -` | 从 stdin 读文本（多行/特殊字符首选，不碰剪贴板） |
| clip | `kuangzi clip [note\|todo]` | 剪贴板内容提交（默认 note；兼容通道，stdin 更优） |
| daily | `kuangzi daily [--date D]` | 每日聚合：一次返回该日期速记+待办（默认今天） |
| todos | `kuangzi todos [--days N] [--open\|--done] [--scope S]` | 查询待办（默认不限时间/全部范围） |
| done | `kuangzi done <关键词>` | 完成待办：全库扫描匹配的未完成项，翻转为 [x] |
| tag | `kuangzi tag <标签>` | 查含指定标签的行（#前须空白；精确匹配） |
| tags | `kuangzi tags` | 标签地图：范围内所有标签+次数 |
| find | `kuangzi find <关键词>` | 全文行检索（子串匹配不区分大小写；自定义区/历史手写全靠它） |
| archive | `kuangzi archive [--week\|--month] [--go]` | 归档：跨设备合并上周期及以前的日记进归档区（默认按月，缺省 dry-run，--go 才执行） |
| go | `kuangzi go "内容"` | 智能路由（继承语义：@词启动 / -待办 / /引擎搜索 / $插件词） |
| search | `kuangzi search "词\|查询"` | 搜索：`search 天气`=默认引擎；`search 百度 天气`=指定引擎 |
| open | `kuangzi open "词\|路径\|URL"` | 快捷启动关键词或直接路径/网址 |
| attach | `kuangzi attach "文件路径"` | 附件归档：复制到附件目录（图片/视频/音频/文档）+追加引用到今日日记 |
| send | `kuangzi send "按键串"` | 模拟按键（AHK Send 语法，如 #v、#l） |
| path | `kuangzi path [today\|dir\|config]` | 路径查询；path add/remove/rename/list 管理个人直达挂载 |
| engine | `kuangzi engine [list\|add\|remove\|rename]` | 搜索引擎表管理（词 → URL 模板；add 的 URL 用 `%s` 占位搜索词） |
| word | `kuangzi word [list\|add\|remove\|rename]` | 快捷启动词表管理（词 → 程序/路径/网址/动作 id） |
| today | `kuangzi today` | 打开今日日记 |
| dir | `kuangzi dir` | 打开笔记目录 |
| new | `kuangzi new "文件名"` | 新建笔记（可省略 .md，创建并打开；同名报错不覆盖） |

## 搜索引擎与快捷启动词管理

设置中心里能点出来的两张表，CLI 也能直接改——智能体可以把"以后搜东西用这个站""把这个软件挂到词表"这类口头指令落成配置。

| 表 | 命令 | 配置键 | 条目语义 |
|---|---|---|---|
| 搜索引擎 | `kuangzi engine` | `SearchEngines` | 词 → URL 模板（`%s` 处填搜索词），走 `/词 查询` 与 `search 词 查询` |
| 快捷启动词 | `kuangzi word` | `WordTable` | 词 → 程序/路径/网址/动作，走 `@词`、`open 词`、`go` 兜底 |

两表共用四个子命令，写法一致：

```bash
kuangzi engine list                                    # 列表（缺省子命令即 list）
kuangzi engine add <词> <URL模板> [选项]                 # 加
kuangzi engine remove <词>                              # 删
kuangzi engine rename <旧词> <新词>                       # 改词（目标不变）

kuangzi word list
kuangzi word add <词> <目标> [选项]
kuangzi word remove <词>
kuangzi word rename <旧词> <新词>
```

选项：

| 选项 | 适用 | 说明 |
|---|---|---|
| `--desc <描述>` | 两者 | 设置页列表里显示的描述 |
| `--home <URL>` | 两者 | 只给词不给查询词时打开的首页（search 型用） |
| `--icon <字符>` | 两者 | 按钮图标字符 |
| `--type run\|action\|search` | 仅 word | 条目类型，缺省 `run`；engine 表固定 `search` |
| `--force` | 两者 | 同名已存在时覆盖（缺省报错，不静默覆盖） |

约定与校验：

- **engine 表的 URL 必须含 `%s`**（搜索词占位）；word 表 `--type search` 同样要求，`run`/`action` 不需要
- 词写 `A|B` = 一个条目挂多个触发词（与设置页同款多键语法）
- 目标或词**含空格必须加引号**，否则会被拆成多个参数；命令会直接报用法错误而不是静默存半截路径
- 条目结构与设置页同源，走同一套校验：不合法的类型/目标会被拒绝（exit 3）
- 同名已存在报 `E_EXISTS`（exit 1），词不存在报 `E_NOTFOUND`（exit 1）

示例：

```bash
# 加一个知乎引擎（搜索走 %s，无查询词时开首页）
kuangzi engine add 知乎 "https://www.zhihu.com/search?q=%s" --home https://www.zhihu.com --desc "知乎搜索" --json
# → {"ok":true,"action":"engine.add","word":"知乎","type":"search","target":"...","config":"..."}

# 一个引擎两个触发词
kuangzi engine add "知乎|知" "https://www.zhihu.com/search?q=%s"

# 把程序挂进词表（路径含空格要引号）
kuangzi word add 微信 "D:\Program Files\WeChat\WeChat.exe" --desc "微信桌面版" --json

# 搜索型词条
kuangzi word add 必应 "https://www.bing.com/search?q=%s" --type search

# 列表与清理
kuangzi engine list --json
kuangzi word remove 必应 --json
```

**生效时机**：写入即落盘，宿主（GUI）在下次唤起输入框时自检配置文件指纹并自动重载——不需要重启宿主，也不需要重开设置中心。宿主没在跑时自然无此一说。

## 参数约定

### 日期 `--date`

- 格式一律 `YYYY-MM-DD`（如 `--date 2026-09-17`），非法格式 exit 3
- 缺省 = 今天

### 范围 `--scope`

| 值 | 含义 |
|---|---|
| `local` | 本机写入分区 |
| `devices` | 全部多设备分区 |
| `archive` | 归档区 |
| `all` | 以上全部（**查询缺省值**） |
| `vault` | 整库递归（含库内任意位置的笔记；仅推荐 tag/tags/find 用） |
| `<目录名>` | 指定某个分区（按目录名精确匹配） |

**查询默认全量**：全部分区 + 不限时间；收窄才带 `--scope` / `--days`。周期文件（日/周/月）与设备分区对查询透明——按条目自身时间戳过滤。

### 时间窗 `--days`

- `--days N` = 最近 N 天（含今天）；缺省 0 = 不限
- 适用于 todos / tag / tags / find

## 输出协议（JSON 契约）

`--json` 时输出**单行无 BOM JSON**（jq 友好）：

| 场景 | 形态 | 退出码 |
|---|---|---|
| 成功 | `{"ok":true,"action":"note","path":"日记完整路径"}` | 0 |
| 失败 | `{"ok":false,"code":"E_FAIL","msg":"原因"}` | 1 |
| 多候选 | `{"ok":false,"code":"E_MULTI","candidates":["A","B"]}` | 2 |
| 用法错误 | `{"ok":false,"code":"E_USAGE","msg":"原因"}` | 3 |

退出码契约（永久不变）：**0 成功 / 1 失败 / 2 多候选 / 3 用法错误**。

### 错误码

| code | 退出码 | 含义与动作 |
|---|---|---|
| `E_FAIL` | 1 | 一般失败，读 `msg` 判断是否值得重试 |
| `E_SILENT` | 1 | 静默失败（设计如此，勿重试） |
| `E_MULTI` | 2 | 多候选，`candidates` 列候选 → 换精确词重试 |
| `E_USAGE` | 3 | 用法错误 → 修正命令，勿原样重试 |

引擎级错误 `code` 可能是 `ERR_*`（GUI 错误码体系），按未知码处理、读 `msg` 即可。

### 字段约定

- `ok`：布尔
- 写操作成功必带 `path`（落盘文件全路径）
- 列表查询带 `count` 与结果数组
- 条目字段：`date`（条目日期，查询按它过滤）、`time`（时间戳）、`text`（正文）、`done`（待办状态）
- `device` / `scopeDirs`：来源标识（多设备目录名因用户而异）
- `path today` 额外带 `exists`（今日日记是否已创建）

### 示例

```bash
# 写入
kuangzi note "下班买菜" --json
# → {"ok":true,"action":"note","path":"D:\\...\\2026-10-17_day.md","text":"下班买菜"}

# 查询
kuangzi todo --date 2026-10-15 --json
# → {"ok":true,"count":3,"date":"2026-10-15","items":[{time,text,done,device}...]}

# 完成待办（多候选时 exit 2 列候选，换精确词重试）
kuangzi done 买菜 --json

# 每日聚合（AI 做"今天记了啥"总结的取数入口）
kuangzi daily --json

# 归档（先 dry-run 看计划，确认后 --go）
kuangzi archive --month --json
kuangzi archive --month --go --json
```

## stdin 通道

多行/长文本/特殊字符首选，无转义坑：

```bash
echo "第一行
第二行" | kuangzi note - --json
```

**管道须 UTF-8**：Git Bash 原生满足；PowerShell 先 `$OutputEncoding=[Text.Encoding]::UTF8`；cmd 的 `echo 中文` 走 GBK 会乱码落盘，勿用。

## 数据布局（直读文件时才需要）

- 配置：`~/.kuangzi/data/kuangzi-app/config.json`（`VaultPath`=库根，`DeviceId`=本机分区名）
- 写入分区：`<VaultPath>/kuangzi-data/<设备标识>/`，其下周期文件（`2026-10-17_day.md`，连字符=名字、下划线=字段拼接）与 `attachments/`
- 归档分区：`<VaultPath>/kuangzi-data/archive/`
- **`kuangzi-data/` 下所有子目录读取端全扫、完全平权**——CLI 查询已自动覆盖
- 文件内部：一个周期文件一个一级标题 + 待办/速记两个二级节（节标题是配置键，默认 `## 框子待办` / `## 框子速记`）；条目 = 行首时间戳 + 缩进正文 + 可选 meta 块
- **按节取内容一律用节查询命令**（程序按配置键定位最可靠）；直读只用于语义检索
