#Requires AutoHotkey v2.0
#SingleInstance Off
;@Ahk2Exe-SetCompanyName 框子
;@Ahk2Exe-SetProductName 框子卸载
;@Ahk2Exe-SetVersion 0.2.261019
;@Ahk2Exe-SetDescription 框子卸载器（交互与静默双模式）
;@Ahk2Exe-SetMainIcon icon.ico

; ==========================================
; 框子 - 卸载器（kuangzi-uninstall）
;
; 为什么它是独立进程，而不是宿主自己卸：
;   宿主自删必须写一个批处理延时删——已实测两个致命坑：bat 用 LF 行尾会让 cmd 解析错乱
;   （只有最后一行能执行）、bat 用 UTF-8 编码会让中文路径变乱码（三个中文名 .lnk 全删不掉）。
;   而且宿主退出之后，没有任何进程能给用户反馈。独立卸载器两个问题都没有。
;
; 双模式：
;   人（双击 / 设置页按钮 / 开始菜单）→ 确认窗 + 结果窗，默认保留数据
;   agent → --no-confirm [--purge-data] [--json] [--out=<路径>]
;
; 红线（安装态目录约定）：
;   · 程序只动 A_ScriptDir 自己（= <品牌根>\app\<自己的目录>）；app / data 两层的
;     根与兄弟目录一概不碰，即使某层已空也不删。
;   · 数据目录 ~/.kuangzi/data/kuangzi-app 默认保留，--purge-data 才整体删除。
;   · 笔记库（VaultPath）任何情况下都不碰——本文件连它的路径都不读。
;
; 自删收尾刻意用"一条命令行"而不是批处理文件：命令行参数走 CreateProcessW 是 Unicode，
; 中文路径无编码问题；落成文件才会踩 GBK 解析那个坑。
; ==========================================
#Include "lib\JSON.ahk"
#Include "lib\AppPaths.ahk"

; 退出码：0 成功 / 1 部分失败 / 2 源码模式守卫 / 3 用户取消
ExitCode := 0
try
    ExitCode := Uninstaller.Main(A_Args)
catch as e
    ExitCode := 1
ExitApp(ExitCode)

class Uninstaller {
    ; ===== 入口 =====
    static Main(argv) {
        opts := this.ParseArgs(argv)
        if (opts.help) {
            this.PrintHelp()
            return 0
        }

        St := { opts: opts, done: [], failed: [] }

        ; 源码模式守卫：A_ScriptDir 在开发态指向仓库，真删就是灾难
        if (!A_IsCompiled) {
            this.Report(St, false, "当前是源码运行模式，为避免误删仓库源码，不执行卸载。`n`n"
                . "如需清理，请手动删除配置目录与启动项。")
            return 2
        }

        St.installDir := A_ScriptDir

        ; ---- 确认 ----
        if (!opts.noConfirm) {
            c := this.Confirm()
            if (!c.ok) {
                this.Report(St, true, "已取消，什么都没做。")
                return 3
            }
            opts.purgeData := c.purge
        }

        ; ---- 干活 ----
        this.CloseHost(St)
        this.RemoveShortcuts(St)
        this.RemoveRegistry(St)
        this.RemoveFromPath(St)
        if (opts.purgeData)
            this.PurgeData(St)

        ok := (St.failed.Length = 0)
        this.Report(St, ok, "")
        this.SelfDestruct()
        return ok ? 0 : 1
    }

    ; ===== 参数 =====
    static ParseArgs(argv) {
        o := { noConfirm: false, purgeData: false, json: false, out: "", help: false }
        for a in argv {
            switch a {
                case "--no-confirm", "-y": o.noConfirm := true
                case "--purge-data":        o.purgeData := true
                case "--json":              o.json := true
                case "--help", "-h", "/?":  o.help := true
                default:
                    if (SubStr(a, 1, 6) = "--out=")
                        o.out := SubStr(a, 7)
            }
        }
        return o
    }

    static PrintHelp() {
        t := "框子卸载器`n`n"
            . "用法：kuangzi-uninstall.exe [选项]`n`n"
            . "  --no-confirm     跳过确认，直接卸载（供智能体调用）`n"
            . "  --purge-data     同时删除配置与插件（~/.kuangzi/data/kuangzi-app 整个目录）`n"
            . "  --json           结果输出为 JSON`n"
            . "  --out=<路径>     JSON 结果写入该文件（默认写到 %TEMP%）`n"
            . "  --help           显示本帮助`n`n"
            . "退出码：0 成功 / 1 部分失败 / 2 源码模式 / 3 用户取消`n`n"
            . "注意：笔记库不会被删除；默认保留配置与插件（需 --purge-data 才删）。"
        MsgBox(t, "框子卸载器", 0x40)
    }

    ; ===== 确认窗（阻塞等待用户操作）=====
    static Confirm() {
        res := { ok: false, purge: false }
        g := Gui("+AlwaysOnTop -MinimizeBox", "卸载框子")
        g.SetFont("s9", "Microsoft YaHei")
        g.Add("Text", "x18 y15 w370", "将卸载框子，并删除：")
        g.Add("Text", "x28 y40 w360", "· 程序文件（整个 " A_ScriptDir "）")
        g.Add("Text", "x28 y62 w360", "· 开始菜单与开机自启的快捷方式")
        g.Add("Text", "x28 y84 w360", "· 注册表中的卸载项")
        g.Add("Text", "x18 y116 w370 c008000", "你的笔记不会被删除。")
        chk := g.Add("CheckBox", "x28 y142 w350", "同时删除配置与插件（以后重新安装会回到初始状态）")
        okBtn := g.Add("Button", "x200 y180 w82 h26 Default", "卸载")
        noBtn := g.Add("Button", "x290 y180 w82 h26", "取消")
        okBtn.OnEvent("Click", (*) => (res.ok := true, res.purge := (chk.Value = 1), g.Destroy()))
        noBtn.OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        g.OnEvent("Close", (*) => g.Destroy())
        g.Show("w410 h225")
        WinWaitClose("ahk_id " g.Hwnd)   ; Show 非阻塞，必须等窗口真关掉
        return res
    }

    ; ===== 关闭宿主 =====
    ; 不依赖 exe 命名：枚举安装目录下的 exe，杀掉除自己以外的进程。
    ; 固定 WaitClose 超时会在边界误报"未退出"（进程随后其实死了）。
    ; 改为"温和关闭 → 强杀 → 10 秒轮询 ProcessExist"以终态定成败。
    static CloseHost(St) {
        if (!DirExist(St.installDir))
            return
        me := A_ScriptName
        Loop Files, St.installDir "\*.exe" {
            if (A_LoopFileName = me)
                continue
            if (!ProcessExist(A_LoopFileName))
                continue
            try {
                ProcessClose(A_LoopFileName)          ; 温和关（GUI 走正常退出路径）
                if (ProcessWaitClose(A_LoopFileName, 3) = 0)
                    ProcessClose(A_LoopFileName)      ; 强杀兜底
                ; 终态轮询：10×0.5s，期间消失即成功——避免固定超时的边界误报
                gone := false
                Loop 10 {
                    if (!ProcessExist(A_LoopFileName)) {
                        gone := true
                        break
                    }
                    Sleep(500)
                }
                if (gone)
                    St.done.Push("已关闭进程 " A_LoopFileName)
                else
                    St.failed.Push("进程迟迟未退出：" A_LoopFileName)
            } catch as e {
                St.failed.Push("关闭进程失败 " A_LoopFileName "：" e.Message)
            }
        }
    }

    ; ===== 快捷方式 =====
    static RemoveShortcuts(St) {
        targets := [
            A_Desktop "\框子.lnk",
            A_AppData "\Microsoft\Windows\Start Menu\Programs\框子\框子.lnk",
            A_AppData "\Microsoft\Windows\Start Menu\Programs\框子\卸载框子.lnk",
            A_AppData "\Microsoft\Windows\Start Menu\Programs\框子.lnk",
            A_Startup "\框子.lnk",
            A_Startup "\kuangzi.cmd"
        ]
        for p in targets
            this._DeleteFile(p, St)
        ; 开始菜单的"框子"文件夹，空了才删（非空说明用户往里放了东西）
        smDir := A_AppData "\Microsoft\Windows\Start Menu\Programs\框子"
        if (DirExist(smDir) && this._IsDirEmpty(smDir))
            try DirDelete(smDir, 0)
    }

    ; ===== 注册表卸载项 =====
    static RemoveRegistry(St) {
        key := "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\kuangzi"
        ; AHK v2 没有 RegKeyExist（实测：它会被当变量解析报「not been assigned」）。
        ; 键不存在时 RegDeleteKey 抛 "(2) 系统找不到指定的文件"——那属于"本来就没有"，不算失败。
        try {
            RegDeleteKey(key)
            St.done.Push("已删除注册表卸载项")
        } catch {
            ; 键不存在 = 无需删除
        }
    }

    ; ===== 从用户 PATH 移除本安装目录 =====
    ; 与安装器 Setup.AddToPath 对称：装时把 <安装目录> 追加进 HKCU\Environment\Path，
    ; 卸时就得摘掉——否则 PATH 里留一条指向已删目录的死项。
    ; 类型口径同安装器（实测）：RegRead 不展开 REG_EXPAND_SZ、RegWrite 显式指定类型可保持，
    ; 所以原值里的 %USERPROFILE% 之类不会被烧成硬路径。
    ; **没命中就一个字节都不写**：装时用了 --no-path 的话，用户 PATH 原样不动。
    static RemoveFromPath(St) {
        consts := "HKCU\Environment"
        cur := RegRead(consts, "Path", "")
        if (cur = "")
            return
        target := RTrim(St.installDir, "\")
        out := ""
        hit := false
        for seg in StrSplit(cur, ";") {
            if (RTrim(Trim(seg), "\") = target) {
                hit := true
                continue
            }
            out .= (out = "" ? "" : ";") seg
        }
        if (!hit)
            return
        try {
            RegWrite(out, "REG_EXPAND_SZ", consts, "Path")
            this.BroadcastEnvChange()
            St.done.Push("已从用户 PATH 移除 " target)
        } catch as e {
            St.failed.Push("移除 PATH 项失败：" e.Message)
        }
    }

    ; 广播 WM_SETTINGCHANGE，否则**已经打开的**终端仍会用旧 PATH（新开的才生效）
    static BroadcastEnvChange() {
        DllCall("SendMessageTimeoutW", "Ptr", 0xFFFF, "UInt", 0x1A, "Ptr", 0
            , "Str", "Environment", "UInt", 0x2, "UInt", 5000, "Ptr*", 0)
    }

    ; ===== 数据目录（仅 --purge-data）=====
    ; 数据全部住在 AppPaths.DataRoot()（~/.kuangzi/data/kuangzi-app/）一个目录里：
    ; purge = 删它整个目录。品牌根与 app / bin / products 等兄弟条目不属于本域，一概不碰；
    ; 数据根删空后品牌根也不主动删——留空目录的代价近乎为零，
    ; 而"检查为空再删"存在竞态（将来别的产品可能正在往里写）。
    static PurgeData(St) {
        root := AppPaths.DataRoot()
        if (!DirExist(root))
            return
        try {
            DirDelete(root, 1)
            St.done.Push("已删除数据目录 " root)
        } catch as e {
            St.failed.Push("删除失败 " root "：" e.Message)
        }
    }

    ; ===== 结果上报 =====
    static Report(St, ok, note) {
        lines := []
        if (note != "")
            lines.Push(note)
        for s in St.done
            lines.Push("· " s)
        for s in St.failed
            lines.Push("！" s)

        if (St.opts.json)
            this._ReportJson(St, ok, lines)
        else if (note = "")   ; 有 note 的是"没干活"的情形，单独弹一句就够
            this._ReportGui(ok, lines)
        else
            MsgBox(note, "框子卸载器", note = "已取消，什么都没做。" ? 0x40 : 0x30)
    }

    static _ReportGui(ok, lines) {
        body := ""
        for s in lines
            body .= s "`n"
        if (body = "")
            body := "（没有需要处理的内容）`n"
        title := ok ? "框子已卸载" : "卸载完成（有未完成项）"
        tip := ok ? "程序文件将在本窗口关闭后清理干净。"
            : "部分内容未能删除，上面已逐条列出。"
        MsgBox(body "`n" tip, title, ok ? 0x40 : 0x30)
    }

    static _ReportJson(St, ok, lines) {
        obj := Map(
            "ok", ok,
            "installDir", St.HasOwnProp("installDir") ? St.installDir : "",
            "dataDir", AppPaths.DataRoot(),
            "purgedData", St.opts.purgeData,
            "done", St.done,
            "failed", St.failed
        )
        txt := JSON.stringify(obj, 0)
        out := (St.opts.out != "") ? St.opts.out : (A_Temp "\kuangzi-uninstall-result.json")
        jsonErr := ""
        try {
            ; 用 FileOpen("w") 直接覆盖：FileAppend 是追加，而 FileDelete 对不存在的文件会抛错
            ; （实测：(2) 系统找不到指定的文件），所以不能靠"先删再追加"
            fo := FileOpen(out, "w", "UTF-8")
            fo.Write(txt)
            fo.Close()
        } catch as e {
            jsonErr := e.Message   ; 不静默吞：写不出来要让调用方看得见
        }
        ; stdout：从终端调用时可用，智能体可直接读；失败无妨
        try {
            FileAppend(txt "`n", "*", "UTF-8")
            if (jsonErr != "")
                FileAppend("[警告] JSON 结果文件写入失败（" out "）：" jsonErr "`n", "*", "UTF-8")
        }
    }

    ; ===== 自删收尾 =====
    ; 只做一件事：等本进程退出后，递归删掉自己所在的整个目录。
    ; **必须重试，不能只 rmdir 一次** —— 实测：本进程刚退出时 Windows 尚未释放该目录的句柄，
    ;   一次性 rmdir 会把目录内容删光、却删不掉目录本身，留下一个空壳。
    ; 刻意用命令行而非批处理文件（见文件头）：命令行参数走 CreateProcessW 是 Unicode，
    ;   中文路径无编码问题；落成文件才会踩 GBK 解析那个坑。
    static SelfDestruct() {
        dir := A_ScriptDir
        cmd := 'cmd.exe /c for /L %i in (1,1,10) do @('
            . 'ping -n 2 127.0.0.1 >nul & rmdir /s /q "' dir '" 2>nul'
            . ' & if not exist "' dir '" exit)'
        ; 工作目录必须显式设到别处：**用户双击卸载器时 cwd 恰好就是 A_ScriptDir**，
        ; 而"删掉自己所在的当前目录"会被系统拒绝（拒绝访问）。用 A_Temp 绕开。
        Run(cmd, A_Temp, "Hide")
    }

    ; ===== 小工具 =====
    static _DeleteFile(p, St) {
        if (!FileExist(p))
            return
        try {
            FileDelete(p)
            St.done.Push("已删除 " p)
        } catch as e {
            St.failed.Push("删除失败 " p "：" e.Message)
        }
    }

    static _IsDirEmpty(dir) {
        Loop Files, dir "\*", "FD" {
            if (A_LoopFileName != "." && A_LoopFileName != "..")
                return false
        }
        return true
    }
}
