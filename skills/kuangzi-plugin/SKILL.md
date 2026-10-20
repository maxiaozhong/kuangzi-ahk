---
name: kuangzi-plugin
description: 框子插件安装技能（kuangzi-plugin）。当用户说"帮我装插件/安装xx插件/装个计算插件/计算器插件/卸载插件/删除插件/更新插件/升级插件"，或要求安装、卸载、更新框子（kuangzi）插件时使用。按 下载 Release 附件→校验 manifest→解压→验证 流程操作 ~/.kuangzi/data/kuangzi-app/plugins/ 目录。框子 CLI 命令执行请用 kuangzi-cli 技能，本技能只管插件文件操作。
---

# 框子插件安装技能（kuangzi-plugin）

> 本技能供智能体（ZCode 等）为用户安装/卸载/更新框子插件。
> 插件结构与契约的权威定义见《插件开发文档》（仓库 `doc/plugin-dev.md`），本技能是安装操作手册——结构与本文不一致时，以文档为准。

## 核心事实

- 插件安装目录：`~/.kuangzi/data/kuangzi-app/plugins/<插件id>/`（Windows 即 `C:\Users\<用户>\.kuangzi\data\kuangzi-app\plugins\<插件id>\`）
- 每个插件一个子目录，**目录名必须等于 manifest 的 id**，不一致时宿主拒绝加载（状态显示"无效"）
- 插件目录内程序与 `data.json`（插件自己的用户数据）混放——**更新插件时只覆盖代码文件，绝不碰 data.json**（学 Obsidian 的升级规矩，靠规矩不靠目录隔离）
- 框子主程序运行中安装/卸载：**须让宿主重扫一次**才生效——「设置 → 插件 Tab → 刷新」，或重启宿主（宿主只在启动与点刷新两处扫描，没有文件监控）。智能体场景走重启：`taskkill /IM kuangzi.exe /F` 后启动 `<安装目录>\kuangzi.exe`

## 插件来源

**推荐：经 skill 安装**——用户说"帮我装 xx 插件"时，插件文件从这两个官方渠道取：

- **Release 附件**：`https://gitee.com/maxiaozhong/kuangzi-ahk/releases`，附件名形如 `plugin-kuangzi-jisuan-v*.zip`（**内含编译好的 exe，开箱即用，用户无需装 AutoHotkey**）
- **仓库源码**：公开仓 `plugins-src/<插件id>/` 目录整体复制（如框子计算 = `plugins-src/kuangzi-jisuan/`，这条路只有源码，需用户装有 AHK v2）

其它插件由各自作者发布（源码/exe/zip 都可能），安装方式以插件自己的说明为准。框子AI 等作者的独立插件见其独立仓库。

## 安装流程（通用四步）

1. **获取插件文件**：按插件说明下载（Release 附件 / 作者给的任意渠道）。Release 附件用浏览器打开下载，或 curl：
   ```
   curl -L -o %TEMP%\plugin.zip <附件地址>
   ```
2. **校验 manifest**：解压后先读 `manifest.json`——必须有 `id`、`entry`（`exe` 或 `source` 至少一个）、`actions`（至少一项）。**exe 入口的插件开箱即用；source 源码入口的插件需要用户机器装有 AutoHotkey v2**（没有则装上后宿主重扫，或建议用户找该插件的 exe 版）
3. **落位**：整个插件目录复制到 `~/.kuangzi/data/kuangzi-app/plugins/<id>/`（目录名=manifest id；zip 解压后若多包了一层，取含 manifest.json 的那层）
4. **验证**：让宿主重扫（刷新或重启），然后跑插件的动作词验证，如：
   ```
   kuangzi go "计算 1+2" --json   → {"ok":true,"text":"3"}
   ```

## 示例：安装框子官方计算插件

```
用户：帮我装计算插件

智能体执行：
1. 浏览器打开 https://gitee.com/maxiaozhong/kuangzi-ahk/releases，
   下载最新 plugin-kuangzi-jisuan-v*.zip
   （无附件时备选：从公开仓 plugins-src\kuangzi-jisuan\ 取源码，需用户装有 AHK v2）
2. 解压，读 manifest.json：id=kuangzi-jisuan，
   entry.exe=kuangzi-jisuan.exe + entry.source=main.ahk（exe 优先，用户无需 AHK 环境），
   actions=[calculate]，keywords=[计算, js] ✓
3. 整个目录复制到 C:\Users\<用户>\.kuangzi\data\kuangzi-app\plugins\kuangzi-jisuan\
4. 提示用户：设置→插件Tab→刷新（或重启框子）
5. kuangzi go "计算 1+1" --json → {"ok":true,"text":"2"} ✓
6. 告知用法：输入 计算 1+1 直接算；输入 js 开计算器窗口（含历史）
```

## 卸载

1. 删除 `~/.kuangzi/data/kuangzi-app/plugins/<id>/` 整个目录
   （若用户想保留插件数据留作重装，可先把 `data.json` 挪出来——插件数据都在这一个文件里）
2. 宿主重扫生效

## 更新

= 卸载 + 安装，但**保留 `data.json`**：
1. 把旧目录的 `data.json` 暂存
2. 删旧目录、放新版
3. `data.json` 放回新目录
4. 宿主重扫，验证动作词

## 注意事项

- 目录名 ≠ manifest id → 宿主拒绝加载；先读 manifest 再落位
- `data.json` 是插件的用户数据（历史/配置），删插件前问用户要不要留
- 用户说"插件无效/不显示"→ 先查：目录名对不对 → manifest id 对不对 → exe 入口文件在不在 → 宿主重扫了没有
- 想给框子写插件的用户：指到仓库 `doc/plugin-dev.md`（协议+manifest 字段表），官方计算插件源码就是模板
