#Requires AutoHotkey v2.0
#SingleInstance Off
;@Ahk2Exe-SetCompanyName 框子
;@Ahk2Exe-SetProductName 框子安装
;@Ahk2Exe-SetVersion 0.2.261019
;@Ahk2Exe-SetDescription 框子安装器（交互与静默双模式）
;@Ahk2Exe-SetMainIcon icon.ico

; ==========================================
; 框子 - 安装器（kuangzi-setup）
;
; 双模式：
;   人（双击）→ 单页向导：安装位置 + 三个勾选 + 安装
;   智能体     → --silent --dir <路径> --json
;
; 装什么：把内嵌的三个成品释放到 <安装目录>，再写系统状态。
;   安装目录默认 ~/.kuangzi/app/kuangzi-app ——品牌根下的**程序层**，与数据层
;   data/kuangzi-app/ 同名成对；数据位置不随安装位置变（安装位置仍可自定义）。
;
; **内嵌的三个成品来自 build\**（由 tools\build.ps1 先行编译，产物不入版本管理）。
;   build.ps1 把安装器排在编译清单最后一行，就是为了保证嵌入的是新成品。
;   FileInstall 的 Source 参数**必须是字面量**（AHK 限制），故下面三条只能逐条写、不能循环。
;
; 写哪些系统状态（全在 HKCU / 用户目录，**不需要管理员权限**）：
;   · 开始菜单  %APPDATA%\...\Start Menu\Programs\框子\  （框子.lnk + 卸载框子.lnk）
;   · 开机自启  %A_Startup%\框子.lnk                       （可选）
;   · 用户 PATH HKCU\Environment\Path                      （可选；改完广播 WM_SETTINGCHANGE）
;   · 卸载项    HKCU\...\CurrentVersion\Uninstall\kuangzi
;
; PATH 的安全口径（实测得出）：
;   AHK 的 RegRead **不会**展开 REG_EXPAND_SZ；RegWrite 显式指定 "REG_EXPAND_SZ" 能保住类型。
;   所以原值里的 %USERPROFILE% 之类不会被烧成硬路径。写入一律带类型，不要用默认类型。
; ==========================================
#Include "lib\JSON.ahk"
#Include "lib\AppInfo.ahk"
#Include "lib\AppPaths.ahk"
#Include "lib\Theme.ahk"

; 退出码：0 成功 / 1 部分失败 / 2 源码模式守卫 / 3 用户取消
ExitCode := 0
try
    ExitCode := Setup.Main(A_Args)
catch as e
    ExitCode := 1
ExitApp(ExitCode)

class Setup {
    ; ===== 入口 =====
    static Main(argv) {
        opts := this.ParseArgs(argv)
        if (opts.help) {
            this.PrintHelp()
            return 0
        }

        St := { opts: opts, done: [], failed: [] }

        if (!A_IsCompiled) {
            this.Report(St, false, "当前是源码运行模式，无法安装（内嵌的成品只有编译后才存在）。`n`n"
                . "开发期请直接在仓库里跑源码；要出安装包请先跑 tools\build.ps1。")
            return 2
        }

        ; ---- 定安装目录 ----
        defDir := this.DefaultDir()
        if (opts.silent) {
            opts.dir    := (opts.dir != "") ? opts.dir : defDir
        } else {
            c := this.Wizard(defDir, opts)
            if (!c.ok) {
                this.Report(St, true, "已取消，什么都没做。")
                return 3
            }
            opts.dir          := c.dir
            opts.autostart    := c.autostart
            opts.addPath      := c.addPath
            opts.desktop      := c.desktop
            opts.startApp     := c.startApp
        }
        St.dir := RTrim(opts.dir, "\")

        ; ---- 可写性自检：目录建得出 ≠ 写得进（只读挂载/安全软件保护都要在这里拦住）----
        if (!this.EnsureWritable(St.dir)) {
            this.Report(St, false, "无法写入安装目录：`n" St.dir "`n`n请换一个位置，或用你自己的账户重试。")
            return 1
        }

        ; ---- 干活 ----
        this.DeployFiles(St)
        this.CreateShortcuts(St)
        if (opts.autostart)
            this.EnableAutostart(St)
        if (opts.addPath)
            this.AddToPath(St)
        this.WriteUninstallEntry(St)

        ok := (St.failed.Length = 0)
        this.Report(St, ok, "")
        if (ok && opts.startApp) {
            try Run('"' St.dir "\kuangzi.exe" '"')
        }
        return ok ? 0 : 1
    }

    ; ===== 默认安装目录 =====
    ; 与路径出口同源（AppPaths 是唯一真相源）；安装位置可在向导或 --dir 里自定义。
    static DefaultDir() {
        return AppPaths.AppDir()
    }

    ; ===== 参数 =====
    static ParseArgs(argv) {
        o := { silent: false, dir: "", autostart: true, addPath: true, desktop: false
             , startApp: true, json: false, out: "", help: false }
        for a in argv {
            switch a {
                case "--silent", "-s":  o.silent := true
                case "--no-autostart":  o.autostart := false
                case "--no-path":       o.addPath := false
                case "--desktop":       o.desktop := true
                case "--no-start":      o.startApp := false
                case "--json":          o.json := true
                case "--help", "-h", "/?": o.help := true
                default:
                    if (SubStr(a, 1, 6) = "--dir=")
                        o.dir := SubStr(a, 7)
                    else if (SubStr(a, 1, 6) = "--out=")
                        o.out := SubStr(a, 7)
            }
        }
        return o
    }

    static PrintHelp() {
        t := "框子安装器`n`n"
            . "用法：kuangzi-setup.exe [选项]`n`n"
            . "  --silent            静默安装（用默认值，供智能体调用）`n"
            . "  --dir=<路径>        指定安装目录`n"
            . "  --no-autostart      不设开机自启`n"
            . "  --no-path           不把安装目录加入用户 PATH`n"
            . "  --desktop           创建桌面快捷方式`n"
            . "  --no-start          装完不启动框子`n"
            . "  --json              结果输出为 JSON`n"
            . "  --out=<路径>        JSON 结果写入该文件（默认写到 %TEMP%）`n"
            . "  --help              显示本帮助`n`n"
            . "默认安装到：" this.DefaultDir() "`n"
            . "退出码：0 成功 / 1 部分失败 / 2 源码模式 / 3 用户取消"
        MsgBox(t, "框子安装器", 0x40)
    }

    ; ===== 向导（阻塞等用户操作）=====
    static Wizard(defDir, opts) {
        res := { ok: false, dir: defDir, autostart: true, addPath: true, desktop: false, startApp: true }
        g := Gui("+AlwaysOnTop -MinimizeBox", "安装框子")
        g.SetFont("s9", "Microsoft YaHei")
        g.Add("Text", "x18 y15 w430", "安装位置：")
        dirEdit := g.Add("Edit", "x18 y40 w430", defDir)
        browse := g.Add("Button", "x456 y39 w82 h25", "浏览…")
        ckAuto := g.Add("CheckBox", "x18 y80 w420", "开机自动启动")
        ckAuto.Value := 1
        ckPath := g.Add("CheckBox", "x18 y104 w420", "把安装目录加入用户 PATH（之后可在终端直接用 kuangzi-cli）")
        ckPath.Value := 1
        ckDesk := g.Add("CheckBox", "x18 y128 w420", "创建桌面快捷方式")
        ckStart := g.Add("CheckBox", "x18 y152 w420", "装完后立即启动框子")
        ckStart.Value := 1
        okBtn := g.Add("Button", "x300 y190 w82 h26 Default", "安装")
        noBtn := g.Add("Button", "x390 y190 w72 h26", "取消")

        browse.OnEvent("Click", (*) => PickDir())
        okBtn.OnEvent("Click", (*) => (
            res.dir          := Trim(dirEdit.Value),
            res.autostart    := (ckAuto.Value = 1),
            res.addPath      := (ckPath.Value = 1),
            res.desktop      := (ckDesk.Value = 1),
            res.startApp     := (ckStart.Value = 1),
            res.ok           := (res.dir != ""),
            g.Destroy()))
        noBtn.OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        g.OnEvent("Close", (*) => g.Destroy())
        g.Show("w558 h232")
        WinWaitClose("ahk_id " g.Hwnd)
        return res

        PickDir() {
            sel := DirSelect(dirEdit.Value, 3, "选择安装目录")
            if (sel != "")
                dirEdit.Value := sel
        }
    }

    ; ===== 释放三个成品 =====
    ; FileInstall 的 Source 必须是字面量 → 三条只能逐条写。
    ; Dest 可以是运行时变量；Dest 所在目录必须先存在。
    static DeployFiles(St) {
        d := St.dir
        try {
            FileInstall "build\kuangzi.exe",           d "\kuangzi.exe",           1
            FileInstall "build\kuangzi-cli.exe",       d "\kuangzi-cli.exe",       1
            FileInstall "build\kuangzi-uninstall.exe", d "\kuangzi-uninstall.exe", 1
        } catch as e {
            St.failed.Push("释放程序文件失败：" e.Message)
            return
        }
        nReleased := 0
        for n in ["kuangzi.exe", "kuangzi-cli.exe", "kuangzi-uninstall.exe"] {
            if (FileExist(d "\" n))
                nReleased++
            else
                St.failed.Push("未生成 " n)
        }
        ; kuangzi.cmd（Windows 终端）+ kuangzi（Git Bash）双转发器：kuangzi 命令 → kuangzi-cli.exe。
        ; 为什么不直接改名 CLI：主程序叫 kuangzi.exe（GUI），裸敲 kuangzi 会弹 GUI 无终端输出；
        ; CLI 是 GUI 子系统 exe，终端直呼无回显（管道下正常）——转发器是 Console/脚本，
        ; 人在终端里敲 kuangzi 有回显，智能体管道调用不受影响。
        ; bash 版（无扩展名）：Git Bash/MSYS 按 PATHEXT 规则先命中同名无扩展名脚本，实测优先于 .exe/.cmd。
        try {
            cmd := "@echo off`r`n`"%~dp0kuangzi-cli.exe`" %*`r`nexit /b %ERRORLEVEL%"
            FileAppend(cmd, d "\kuangzi.cmd", "UTF-8-RAW")
            sh := "#!/bin/bash`ndir=$(cd `"$(dirname `"$0`")`" && pwd)`nexec `"$dir/kuangzi-cli.exe`" `"$@`"`n"
            FileAppend(sh, d "\kuangzi", "UTF-8-RAW")
        } catch as e {
            St.failed.Push("生成命令转发器失败：" e.Message)
        }
        if (nReleased = 3)
            St.done.Push("程序文件就绪")
    }

    ; ===== 快捷方式 =====
    static CreateShortcuts(St) {
        d := St.dir
        smDir := A_AppData "\Microsoft\Windows\Start Menu\Programs\框子"
        try {
            DirCreate(smDir)
            FileCreateShortcut(d "\kuangzi.exe", smDir "\框子.lnk", d)
            FileCreateShortcut(d "\kuangzi-uninstall.exe", smDir "\卸载框子.lnk", d)
            St.done.Push("已建开始菜单快捷方式")
        } catch as e {
            St.failed.Push("开始菜单快捷方式失败：" e.Message)
        }
        if (St.opts.desktop) {
            try {
                FileCreateShortcut(d "\kuangzi.exe", A_Desktop "\框子.lnk", d)
                St.done.Push("已建桌面快捷方式")
            } catch as e {
                St.failed.Push("桌面快捷方式失败：" e.Message)
            }
        }
    }

    static EnableAutostart(St) {
        try {
            FileCreateShortcut(St.dir "\kuangzi.exe", A_Startup "\框子.lnk", St.dir)
            St.done.Push("已设开机自启")
        } catch as e {
            St.failed.Push("设置开机自启失败：" e.Message)
        }
    }

    ; ===== 用户 PATH =====
    static AddToPath(St) {
        consts := "HKCU\Environment"
        cur := RegRead(consts, "Path", "")
        target := RTrim(St.dir, "\")
        for seg in StrSplit(cur, ";") {
            if (RTrim(Trim(seg), "\") = target)
                return   ; 已在（幂等）
        }
        newVal := (cur = "") ? target : (RTrim(cur, ";") ";" target)
        try {
            ; 必须带类型：实测 RegRead 不展开 REG_EXPAND_SZ、RegWrite 指定类型可保持，
            ; 所以原值里的 %USERPROFILE% 之类不会被烧成硬路径。用默认类型会降级成 REG_SZ。
            RegWrite(newVal, "REG_EXPAND_SZ", consts, "Path")
            this.BroadcastEnvChange()
            St.done.Push("已把安装目录加入用户 PATH")
        } catch as e {
            St.failed.Push("写入 PATH 失败：" e.Message)
        }
    }

    ; 广播 WM_SETTINGCHANGE，否则**已经打开的**终端读不到新 PATH（新开的才生效）
    static BroadcastEnvChange() {
        DllCall("SendMessageTimeoutW", "Ptr", 0xFFFF, "UInt", 0x1A, "Ptr", 0
            , "Str", "Environment", "UInt", 0x2, "UInt", 5000, "Ptr*", 0)
    }

    ; ===== 注册表卸载项 =====
    static WriteUninstallEntry(St) {
        k := "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\kuangzi"
        exe := St.dir "\kuangzi-uninstall.exe"
        try {
            RegWrite(AppInfo.name,    "REG_SZ", k, "DisplayName")
            RegWrite(AppInfo.version, "REG_SZ", k, "DisplayVersion")
            RegWrite("框子",           "REG_SZ", k, "Publisher")
            RegWrite(exe,             "REG_SZ", k, "DisplayIcon")
            RegWrite(St.dir,          "REG_SZ", k, "InstallLocation")
            RegWrite('"' exe '"',     "REG_SZ", k, "UninstallString")
            ; 静默卸载命令 —— 智能体入口，用 Windows 自己的标准字段
            RegWrite('"' exe '" --no-confirm --json', "REG_SZ", k, "QuietUninstallString")
            St.done.Push("已写注册表卸载项")
        } catch as e {
            St.failed.Push("写注册表卸载项失败：" e.Message)
        }
    }

    ; ===== 可写性自检 =====
    static EnsureWritable(dir) {
        probe := dir "\.write-probe"
        try {
            DirCreate(dir)
            FileAppend("1", probe, "UTF-8-RAW")
            FileDelete(probe)
            return true
        } catch {
            return false
        }
    }

    ; ===== 结果上报 =====
    static Report(St, ok, note) {
        if (St.opts.json) {
            obj := Map("ok", ok
                , "installDir", St.HasOwnProp("dir") ? St.dir : ""
                , "note", note
                , "done", St.done, "failed", St.failed)
            txt := JSON.stringify(obj, 0)
            out := (St.opts.out != "") ? St.opts.out : (A_Temp "\kuangzi-setup-result.json")
            jerr := ""
            try {
                ; FileOpen("w") 覆盖写；FileAppend 是追加，而 FileDelete 对不存在文件会抛错
                fo := FileOpen(out, "w", "UTF-8")
                fo.Write(txt)
                fo.Close()
            } catch as e {
                jerr := e.Message
            }
            try {
                FileAppend(txt "`n", "*", "UTF-8")
                if (jerr != "")
                    FileAppend("[警告] JSON 结果文件写入失败（" out "）：" jerr "`n", "*", "UTF-8")
            }
            return
        }
        if (note != "") {
            MsgBox(note, "框子安装器", 0x30)
            return
        }
        body := "装到：" (St.HasOwnProp("dir") ? St.dir : "") "`n"
        for s in St.done
            body .= "· " s "`n"
        for s in St.failed
            body .= "！" s "`n"
        MsgBox(body, ok ? "框子已安装" : "安装完成（有未完成项）", ok ? 0x40 : 0x30)
    }
}
