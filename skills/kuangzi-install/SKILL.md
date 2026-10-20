---
name: kuangzi-install
description: 框子（kuangzi）安装技能。当用户说"帮我装框子/安装kuangzi/装一下框子/升级框子/更新框子"，或发给智能体框子仓库链接并要求安装时使用。流程：测 kuangzi-cli --version 判定初次安装/升级/已最新（版本号四态）→ 从用户所给仓库的 Releases 下载 kuangzi-setup-v*.exe → 静默安装（--silent --desktop --json，升级时带 --dir 原位覆盖）→ 验证 → 把该仓库 skills/ 下的技能装入智能体自己的技能目录。装好后日常使用归 kuangzi-cli 技能，本技能只管装。
---

# 框子安装技能（kuangzi-install）

## 这是什么

给智能体的框子宿主安装/升级手册。用户初次场景通常是"一个仓库链接 + 帮我装"——本技能覆盖从链接到能用的全链路，装完即闭环。

一句话定位：**只管装和升，装好之后的使用归 kuangzi-cli 技能。**

## 前置事实（写死在流程里的契约）

- 发布渠道：**用户所给仓库的 Releases 页**（即 `<仓库地址>/releases`，取 `releases/latest` 里最新那条）；Gitee 与 GitHub 各有一份同名发布，用户给哪个就用哪个，两个都没有时再问用户要地址
- 安装包名形如 `kuangzi-setup-v<版本>.exe`，版本号编在文件名里（离线可认版本）
- 静默安装：`kuangzi-setup.exe --silent --desktop --json`（用户级安装，无需管理员权限）
- **`--desktop` 必须显式给**：静默模式默认只建开始菜单快捷方式，**不建桌面图标**；只有用户明说不要桌面图标时才省掉
- 安装器 JSON 结果：`{"ok":1,"done":[...],"failed":[...],"installDir":"..."}`
- 默认安装目录：`~/.kuangzi/app/kuangzi-app/`；**安装位置可自定义**（`--dir`），不要假设默认路径
- 探活命令：`kuangzi-cli.exe --version`（别用裸 `kuangzi`：Windows 终端按 PATHEXT 命中 GUI 宿主 kuangzi.exe，弹窗无输出）

## 流程总纲（版本四态分流）

```
kuangzi-cli.exe --version
│
├─ 命令不存在 → 【初次安装】
├─ 版本 < Release 版本 → 【升级】（原位覆盖）
├─ 版本 = Release 版本 → 【已最新】（只补装技能，不动程序）
└─ 版本 > Release 版本 → 【本地超前】（不降级，如实告知）
```

**版本比较规则**：版本形如 `0.2.261017`（主.次.日期），**按点分段转数值比较，禁止字符串比较**——`"0.2.9"` 按字符串比会大于 `"0.2.261017"`（`9 > 2`），必误判。

**判活口径**：用命令而不是注册表——PATH 是装器写入的实际安装目录，命令通 = 装了且文件在；注册表只能证明"装过"（手删目录后残留）。

## 第一步：探测当前状态

```bash
kuangzi-cli.exe --version
# 输出 "kuangzi cli v0.2.261017" → 已安装，提取版本号进入四态分流
# "命令未找到" → 初次安装
```

注意：刚装完的那次会话里 PATH 可能未刷新（装器写的是注册表，已开终端不生效）——**判断"装没装过"建议命令与注册表双查**：命令通不等于命令不在 PATH（装过但会话旧）。命令不通时补查注册表 `HKCU\...\Uninstall\kuangzi` 有无 `InstallLocation`，有值 = 裁过的安装，按升级路径走（见下）。

## 第二步：下载安装包

从用户所给仓库的 Releases 最新页（`<仓库地址>/releases/latest`）找 `kuangzi-setup-v*.exe` 附件下载，或用平台 API 定位（`<owner>/<repo>` 即用户所给地址的路径部分）：

```bash
# Gitee 仓
curl -s https://gitee.com/api/v5/repos/<owner>/<repo>/releases/latest
# GitHub 仓
curl -s https://api.github.com/repos/<owner>/<repo>/releases/latest
# 取 assets[].browser_download_url 中形如 kuangzi-setup-v*.exe 的那个
curl -L -o "%TEMP%\kuangzi-setup.exe" <browser_download_url>
```

## 第三步：执行安装（按四态）

### 初次安装

```bash
"%TEMP%\kuangzi-setup.exe" --silent --desktop --json
```

装完安装器会自动启动宿主（默认行为）。JSON 的 `installDir` 即安装目录，后续验证走该路径下的 `kuangzi-cli.exe`。

`done` 里应能看到四项：程序文件就绪、已建开始菜单快捷方式、**已建桌面快捷方式**、已设开机自启（重装时「加入 PATH」一项会因幂等而省略，属正常）。

### 升级（版本 < Release）

先取实际安装路径再原位覆盖，**两步缺一不可**：

1. 取实际安装路径（注册表 InstallLocation，装器每次安装都会更新）：
   ```bash
   reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\kuangzi" /v InstallLocation
   ```
2. 停掉运行中的宿主（**必须**：运行中 exe 被锁，setup 的 FileInstall 覆盖会报"释放程序文件失败"，实测复现）：
   ```bash
   taskkill /IM kuangzi.exe /F 2>nul
   ```
3. 原位覆盖安装：
   ```bash
   "%TEMP%\kuangzi-setup.exe" --silent --desktop --dir=<InstallLocation> --json
   ```
   不带 `--dir` 会装到默认目录，自定义安装的用户会得到双份安装。升级也带 `--desktop`——用户删过桌面图标就顺手补回来，没删过则是幂等覆盖。

### 已最新

程序不动。检查智能体自己的技能目录里有无 kuangzi-cli（及 kuangzi-plugin）技能，缺则补装（见第五步）。

### 本地超前

如实告知用户"本机版本比 Release 新"，不降级不覆盖，收工。

## 卸载（用户说"卸载框子/删掉框子"时）

安装目录里的 `kuangzi-uninstall.exe` 同样支持智能体调用（v0.2.261019 起，宿主运行中也能干净卸载——卸载器自动关进程后自删目录）：

```bash
<installDir>\kuangzi-uninstall.exe --no-confirm --json
# 可选 --purge-data：连配置与插件数据一起删（~/.kuangzi/data/kuangzi-app/ 整目录）
```

- **默认保留数据**（笔记库永远不碰，数据层与笔记库是两个域）；用户明确要"彻底清掉"才加 `--purge-data`，加之前跟用户确认一句
- 运行中的宿主无需先 taskkill——卸载器自己处理（温和关闭→强杀→终态轮询）
- JSON 结果 `ok=1` 即成功；目录由卸载器自删收尾，稍等几秒即净
- 拿 installDir 照样走注册表 InstallLocation，别猜路径
- 卸载后建议把智能体技能目录里的 kuangzi-* 技能一并清掉（或问用户留不留）

## 第四步：验证

```bash
<installDir>\kuangzi-cli.exe --version
# 版本 = Release 版本号 → 成功
```

- 验证走安装器返回的 `installDir` 完整路径（当次会话 PATH 未必已刷新）
- 输出格式 `kuangzi cli v<版本>`，ASCII 安全，判活只用它（`--help` 中文在 GBK 管道下乱码）
- 宿主 GUI 是否驻留：`tasklist /FI "IMAGENAME eq kuangzi.exe"` 应看到进程
- 等几分钟数据层自动建好 `~/.kuangzi/data/kuangzi-app/config.json`（配置创建权在 GUI 首跑，不要替用户写）

## 第五步：技能落盘（闭环关键一步）

装完宿主不算闭环——**把仓库 `skills/` 下的技能复制进智能体自己的技能目录**，下次会话起 "记一下/待办" 原生触发：

- ZCode：`~/.zcode/skills/kuangzi-cli/`（及 `kuangzi-plugin/`、`kuangzi-install/`）
- 其他智能体：各自的技能目录（Claude Code 的 `.claude/skills/` 等），按其规范落位
- 技能来源：克隆或下载**用户所给仓库**的 ZIP 后取 `skills/` 子树
- 已存在同目录时**整目录覆盖**（skill 是随版本演进的，覆盖优于合并）

## 终态检查单

- [ ] `kuangzi-cli.exe --version` 输出 Release 版本
- [ ] 宿主进程在跑（初次装完自动启动；升级装完也会自动启动）
- [ ] 桌面有「框子」图标（`--desktop` 生效的标志；用户明说不要桌面图标时此项跳过）
- [ ] 智能体技能目录已有 kuangzi-cli（日常使用链路就位）
- [ ] 数据层 `~/.kuangzi/data/kuangzi-app/` 已创建（GUI 首跑自动建，等几分钟或用户首次唤起后）
- [ ] 向用户报版本与安装路径

## 常见坑

- **静默装默认没有桌面图标**：`--silent` 只建开始菜单 + 开机自启，桌面图标要显式 `--desktop`（安装器没有 `--no-desktop`，不想给就别带这个参数）。漏了会得到"开始菜单有、桌面没有"的半套结果，用户通常得回头再要求补一次
- **PATH 时效**：装器写注册表 PATH，已开的终端会话不生效——同会话验证一律走完整路径或新进程
- **cmd 裸敲 `kuangzi`**：PATHEXT 顺序命中 GUI 宿主 kuangzi.exe，弹窗且无终端输出——终端里用 `kuangzi-cli.exe`（或 `kuangzi.cmd`）；Git Bash 无扩展名脚本优先命中，无此坑
- **编码**：判活只用 `--version`（ASCII）；`--help` 的中文在 GBK 管道下乱码，是显示问题不是故障
- **升级文件锁**：宿主运行中跑 setup 覆盖必失败（JSON 报"释放程序文件失败"），taskkill 先行；但跑**卸载器**不需要——它自己关进程
- **不要猜安装路径**：默认路径只是默认值，一切以注册表 InstallLocation / 安装器 JSON 的 installDir 为准
