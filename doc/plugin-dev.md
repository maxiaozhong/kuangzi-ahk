# 框子插件开发文档

> 插件是框子的扩展机制：独立目录、独立进程、JSON 文件通信。任何能读写文件、能起进程的语言都能写（AHK/Go/Python……）。
>
> 官方演示插件**框子计算**（[Releases](https://gitee.com/maxiaozhong/kuangzi-ahk/releases) 附件 zip）就是按本文协议实现的完整范例——写插件前建议先解压看一遍。

## 总览：插件是什么

```
用户输入 "$计算 1+2" 或点工具条按钮
        ↓
框子宿主（kuangzi.exe / kuangzi.ahk）
        ↓ 写 request.json，启动插件进程
你的插件（任意语言，独立进程）
        ↓ 处理，写 response.json（原子改名）
框子宿主
        ↓ 读响应，按 intent 呈现（通知/剪贴板/…）
用户看到 "3"
```

- **通信**：文件式 JSON（`~/.kuangzi/data/kuangzi-app/plugin-tasks/<requestId>/` 下一个请求文件、一个响应文件），无 IPC、无网络、无动态库——语言无关
- **生命周期**：一次调用一个进程，跑完即退（GUI 类插件可挂住进程，见 mode=open）
- **超时**：单任务 15 秒；响应上限 1 MiB
- **安装目录**：`~/.kuangzi/data/kuangzi-app/plugins/<插件id>/`，目录名必须等于 manifest 的 `id`

## 目录结构

```
my-plugin/
├── manifest.json     ← 插件声明（宿主扫描的唯一入口）
├── main.ahk          ← 入口（或编译成 exe）
├── src/...           ← 你的代码组织自由
└── data.json         ← 插件自己的用户数据（运行时生成；升级不覆盖——见文末规矩）
```

## manifest.json 字段表

```json
{
  "apiVersion": 1,
  "id": "my-plugin",
  "name": "我的插件",
  "version": "1.0.0",
  "minHostVersion": "0.2.0",
  "author": "yourname",
  "description": "一句话说明",
  "icon": "🔧",
  "permissions": [],
  "entry": { "exe": "my-plugin.exe", "source": "main.ahk" },
  "actions": [
    {
      "id": "greet",
      "label": "打招呼",
      "icon": "👋",
      "keywords": ["你好", "hi"],
      "textAction": true,
      "allowEmpty": false,
      "display": { "toolbar": true },
      "supportsGui": false
    }
  ]
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `apiVersion` | ✓ | 协议版本，当前 `1` |
| `id` | ✓ | 全局唯一标识；**安装目录名必须与它一致**（不一致宿主拒绝加载） |
| `entry` | ✓ | 双入口：`exe`（编译产物路径）或 `source`（脚本路径）至少一个；**都填时 exe 优先**。source 跑 AHK 的要求用户装有 AutoHotkey v2；exe 开箱即用 |
| `actions` | ✓ | 动作清单（至少一项），字段见下表 |
| `minHostVersion` | | 宿主版本下限，不满足标记 incompatible |
| `permissions` | | 权限声明：`read:focused-window`（前台窗口信息）/ `read:clipboard`（剪贴板快照）；声明了宿主才在 request 里给对应 hostContext |

### actions[] 字段

| 字段 | 说明 |
|---|---|
| `id` | 动作标识（插件内唯一） |
| `label` / `icon` | 展示名与图标（emoji） |
| `keywords` | 触发词（多个）；与词表/引擎撞词时用户可用 `$你的词` 直通 |
| `textAction` | 吃文本的动作（true=要参数；false=纯触发） |
| `allowEmpty` | 无参数裸词是否可跑（如开面板类） |
| `display` | 出场资格声明，不写=不进任何消费面：`toolbar`（工具条可勾选）/ `slots`（键位槽）/ `textTargets`（文本处置池）/ `quickKey`（一键直达）/ `fallback`（提交兜底池） |
| `supportsGui` | 无参触发时是否以 `mode=open` 调用（开面板类动作用） |

## invoke v1 协议

### 启动参数

宿主以命令行启动你的入口：

```
<你的入口> --request <request.json路径> --response <response.json路径>
```

### request.json（宿主 → 插件）

```json
{
  "protocolVersion": "invoke.v1",
  "requestId": "20261017213000-A1B2",
  "pluginId": "my-plugin",
  "actionId": "my-plugin.greet",
  "mode": "execute",
  "keyword": "你好",
  "source": "route",
  "text": "世界",
  "pluginDataDir": "C:\\Users\\you\\.kuangzi\\data\\kuangzi-app\\plugins\\my-plugin",
  "locale": "zh-CN",
  "hostVersion": "0.2.261017",
  "hostContext": { "focused": { "title": "...", "exe": "..." } }
}
```

| 字段 | 说明 |
|---|---|
| `actionId` | 全局动作 ID（`<插件id>.<动作id>`） |
| `mode` | `execute`（带文本求值）/ `open`（无参开面板；`text` 为 `settings` 时=宿主要你开设置界面） |
| `keyword` / `source` | 命中关键词与触发来源（route/cli/toolbar/slot/quickKey…） |
| `text` | 用户文本（mode=open 时为空） |
| `pluginDataDir` | 插件目录——你的 data.json 应放这里 |
| `hostContext` | 仅当 permissions 声明对应项才有：`focused`（前台窗口 title/exe）、`clipboard`（剪贴板文本快照，4KiB 截断） |

### response.json（插件 → 宿主）

**写法要求**：先写 `<response路径>.tmp` 再**原子改名**为正式名（宿主靠文件出现判断完成；直接写正式名可能被读到半截）。

```json
{
  "protocolVersion": "invoke.v1",
  "requestId": "20261017213000-A1B2",
  "actionId": "my-plugin.greet",
  "ok": true,
  "intent": "notify",
  "text": "你好，世界",
  "msg": "",
  "code": "",
  "notifyStyle": "toast"
}
```

| 字段 | 说明 |
|---|---|
| `requestId` / `actionId` | 原样回传（宿主对账用） |
| `ok` | 成功/失败 |
| `text` | 结果文本（intent 的载荷） |
| `msg` | 失败原因（ok=false 时宿主展示它） |
| `intent` | 结果意图：`notify`（通知中心展示，缺省）/ `copy`（宿主把 text 写进剪贴板）/ `fill`（回填输入框，仅 GUI）/ `todo`（text 记为待办） |
| `notifyStyle` | 呈现样式：`toast`（右下角，自动消失）/ `center`（居中，常驻点关）；不写=宿主缺省 |
| `silent` | true=失败不弹通知（静默） |

## 开发与调试

1. **落位即开发**：把插件目录放进 `~/.kuangzi/data/kuangzi-app/plugins/<id>/`，宿主「设置 → 插件 → 刷新」即加载——不需要注册、不需要编译安装流程
2. **状态排查**：插件 Tab 里每个插件有状态——`invalid`（manifest 坏/目录名不符）、`incompatible`（版本不符）、`no_entry`（入口缺失）、`no_runtime`（source 入口但用户没装 AHK v2）
3. **手动模拟调用**：自己造一对 request/response 文件跑入口，宿主不参与也能调通逻辑
4. **动作词验证**：`kuangzi go "$你的词 参数" --json`

## 分发建议

- **exe 入口开箱即用**（推荐给普通用户）；source 入口要求用户装有 AutoHotkey v2
- 可以两者都声明（`exe` 优先、`source` 兜底）——manifest 双入口就是为这设计的
- 分发渠道自由：zip/Release/git 仓库均可；给智能体用户配一份安装说明（如本仓库 `skills/kuangzi-plugin/` 的格式），AI 就能替用户装

## 规矩（务必遵守）

1. **`data.json` 是用户数据**：插件的设置/历史全放这一个文件，升级覆盖代码文件时**绝不碰它**
2. 只在自己的目录（`pluginDataDir`）与任务临时目录读写；别动宿主配置和日记
3. 超时 15 秒：长任务自己持久化进度、分次调用
4. `requestId`/`actionId` 原样回传；响应用原子改名写出
