#Requires AutoHotkey v2.0
#SingleInstance Off
;@Ahk2Exe-SetCompanyName 框子
;@Ahk2Exe-SetProductName 框子CLI
;@Ahk2Exe-SetVersion 0.2.261019
;@Ahk2Exe-SetDescription 框子命令行版（智能体用）
;@Ahk2Exe-SetMainIcon icon.ico

; ==========================================
; 框子 CLI 版（kuangzi CLI）
; 编译：Ahk2Exe，base 用 AHK 安装目录里的 AutoHotkey64.exe（GUI 子系统）。
;       GUI 子系统不附加控制台：管道调用（智能体捕获输出、Git Bash 的伪终端）stdout 正常，
;       只有人在 cmd/PowerShell 里直接敲才无回显（`kuangzi x | more` 可绕过）。
;       终端直敲也要回显需 Console base（PE subsystem=3），当前工具链无此 base，暂不引入。
; 脚本版等效：AutoHotkey64.exe kuangzi-cli.ahk <命令> [参数]
;
; 结构：本文件只做入口（参数解析+命令分发），业务在 lib——
;   CliCore（协议层） / TodoCommands（待办域） / NoteCommands（笔记域）
;   note/todo/go 等直接转发 lib 既有模块
;
; 退出码协议：
;   0 成功 / 1 失败 / 2 多候选（stdout 列出候选） / 3 用法错误
; ==========================================

#Include "lib\Utils.ahk"
#Include "lib\AppInfo.ahk"
#Include "lib\ConfigManager.ahk"
#Include "lib\QuickNote.ahk"
#Include "lib\QuickSearch.ahk"
#Include "lib\QuickLaunch.ahk"
#Include "lib\Router.ahk"
#Include "lib\AttachHelper.ahk"
#Include "lib\JSON.ahk"
#Include "lib\CliCore.ahk"
#Include "lib\TodoCommands.ahk"
#Include "lib\NoteCommands.ahk"
#Include "lib\DictCommands.ahk"
#Include "lib\SearchCommands.ahk"
#Include "lib\SectionCommands.ahk"
#Include "lib\ArchiveCommands.ahk"
#Include "lib\PluginManager.ahk"
#Include "lib\ActionBindings.ahk"

; ===== 参数解析（A_Args 不做引号处理，bash 侧负责）=====
if (A_Args.Length = 0)
    Usage()
; 版本/帮助是零副作用快捷指令（标准 CLI 惯例，供连通性验证）
cmd := A_Args[1]
if (cmd = "--version" || cmd = "-v" || cmd = "version") {
    Out("kuangzi cli v" AppInfo.version)
    ExitApp(0)
}
if (cmd = "--help" || cmd = "-h" || cmd = "help")
    Usage()
; --json 是全局标志：从参数流里摘出（可放任意位置），剩下的才是命令参数
argParts := []
for i, a in A_Args {
    if (i = 1)
        continue
    if (a = "--json")
        JsonMode := true
    else
        argParts.Push(a)
}
arg := ""
for a in argParts
    arg .= (arg = "" ? "" : " ") a

; ===== stdin 通道：arg 为 "-" 时从管道读全文（多行/特殊字符首选通道）=====
if (arg = "-") {
    stdinText := ReadStdinAll()
    if (stdinText = "")
        Fail("stdin 读取失败或内容为空（管道场景专用：echo 文本 | kuangzi note -）")
    arg := RTrim(stdinText, "`r`n `t")
}

CheckInstalled()
; CLI 无窗：菜单类交互全部静默（无窗会话 Menu.Show 永久阻塞），EmitResult 转 E_MULTI 语义
QuickLaunch.Headless := true

; ===== 命令分发 =====
switch cmd {
    case "note", "todo":
        ; 查询态判定：参数流里只有标志（--date/--scope/--days/--json），无位置文本
        hasText := (ParsePositionals(A_Args, 2).Length > 0)
        if (!hasText) {
            ; 查询态：按日期查该节内容
            if (cmd = "note")
                ExitApp(CliNoteQuery(A_Args))
            else
                ExitApp(CliTodoQuery(A_Args))
        }
        if (cmd = "note")
            EmitResult(QuickNote.Submit(arg, false, "cli"))
        else
            EmitResult(QuickNote.Submit(arg, true, "cli"))

    case "clip":
        ; clip [note|todo]：文本取剪贴板，规避命令行转义/长度坑
        mode := (arg = "todo") ? arg : "note"
        clipText := A_Clipboard
        if (Trim(clipText) = "")
            Fail("剪贴板为空或仅空白")
        if (mode = "todo")
            EmitResult(QuickNote.Submit(clipText, true, "clip"))
        else
            EmitResult(QuickNote.Submit(clipText, false, "clip"))

    case "go":
        if (arg = "")
            Usage()
        PluginManager.SweepStaleTasks()
        PluginManager.Scan()
        ActionBindings.RebuildPluginActions()
        ConfigManager.OnCachesRebuilt := ActionBindings.RebuildWordActions.Bind(ActionBindings)
        ActionBindings.RebuildWordActions()
        CliInstallPluginCallback()
        Router.Source := "cli"   ; 同一条智能路由，CLI 进程把触发来源盖为 cli
        res := Router.Route(arg)
        ; 插件任务是 pending：CLI 同步等待终态（同一超时上限）
        if (IsObject(res) && res.pending && res.action = "plugin") {
            res := CliWaitPluginDone()
        }
        EmitResult(res)

    case "search":
        ; search <词> [查询]：显式搜索命令，无前缀歧义（智能体首选，替代已取消的 * 前缀）
        ; "search 百度 天气"=指定引擎；"search 天气"=默认引擎
        ; 与 `/` 对齐——仅给引擎词无查询（如 search 百度）= 开该引擎首页；
        ;   引擎判定走 CI 查找（与四源口径一致）
        if (arg = "")
            Usage()
        sp := InStr(arg, " ")
        firstWord := sp ? Trim(SubStr(arg, 1, sp - 1)) : arg
        eng := QuickSearch.FindEngineCI(firstWord)
        if (eng != "")
            EmitResult(QuickSearch.ExecuteEntry(eng, sp ? Trim(SubStr(arg, sp + 1)) : "", "search"))
        EmitResult(QuickSearch.Execute(ConfigManager.Get("SearchEngine"), arg, "search"))

    case "open":
        if (arg = "")
            Usage()
        ExitApp(CliOpen(arg))

    case "today":
        EmitResult(QuickNote.OpenTodayNote())

    case "dir":
        EmitResult(QuickNote.OpenNoteFolder())

    case "new":
        if (arg = "")
            Usage()
        ExitApp(CliNewNote(arg))

    case "path":
        ; path <子命令> [参数]：arg 首词=子命令，余下=参数（路径可能含空格，余串原样传）
        sub := arg, rest := ""
        sp := InStr(arg, " ")
        if (sp) {
            sub := Trim(SubStr(arg, 1, sp - 1))
            rest := Trim(SubStr(arg, sp + 1))
        }
        ExitApp(CliPath(sub, rest))

    case "engine":
        ; engine list|add|remove|rename：搜索引擎表（词 → URL 模板）
        ExitApp(CliEngine(A_Args))

    case "word":
        ; word list|add|remove|rename：快捷启动词表（词 → 程序/路径/网址/动作）
        ExitApp(CliWord(A_Args))

    case "attach":
        if (arg = "")
            Usage()
        ExitApp(CliAttach(arg))

    case "done":
        if (arg = "")
            Usage()
        ExitApp(CliDone(arg))

    case "todos":
        ExitApp(CliTodos(A_Args))

    case "tag":
        ExitApp(CliTag(A_Args))

    case "tags":
        ExitApp(CliTags(A_Args))

    case "find":
        ExitApp(CliFind(A_Args))

    case "daily":
        ExitApp(CliDaily(A_Args))

    case "send":
        ; send <按键串>：透传模拟按键（AHK Send 语法，如 "#v"、"#l"）
        ; immediate=true：CLI 进程随即退出，延迟定时器等不到触发（见 Utils.SendKeys）
        if (arg = "")
            Usage()
        if (Utils.SendKeys(arg, true))
            EmitResult(Utils.ResOk("send"))
        else
            Fail("按键发送失败")

    case "archive":
        ExitApp(CliArchive(A_Args))

    default:
        if !JsonMode
            Out("未知命令: " cmd)
        Usage()
}
