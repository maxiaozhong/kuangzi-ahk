#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "PluginManager.ahk"

class NotifyCenter {
    static Presets := Map(
        "note_success",   { level: "success", icon: "✓", color: "10B981", sound: "*64", shake: false, duration: 1800, title: "速记成功", center: false },
        "todo_success",   { level: "success", icon: "✓", color: "3B82F6", sound: "*64", shake: false, duration: 1800, title: "待办已添加", center: false },
        "image_success", { level: "success", icon: "🖼", color: "8B5CF6", sound: "*64", shake: false, duration: 1800, title: "含图片，已写入速记", center: false },
        "action_success", { level: "success", icon: "▶", color: "6366F1", sound: "",    shake: false, duration: 1500, title: "已打开", center: false },
        "plugin_success", { level: "success", icon: "🧩", color: "8B5CF6", sound: "",    shake: false, duration: 2500, title: "插件结果", center: true, sticky: true },
        "info",           { level: "info",    icon: "i", color: "6B7280", sound: "",    shake: false, duration: 2000, title: "提示", center: false },
        "scan_success",   { level: "success", icon: "✓", color: "10B981", sound: "*64", shake: false, duration: 2000, title: "扫描成功", center: true },
        "warning",        { level: "warning", icon: "!", color: "F59E0B", sound: "*48", shake: false, duration: 3000, title: "警告", center: true },
        "error",          { level: "error",   icon: "✕", color: "EF4444", sound: "*16", shake: false, duration: 4000, title: "失败", center: true }
    )

    static History := []
    static _toasts := []
    static MAX_TOASTS := 4
    static MAX_HISTORY := 50
    static HistoryGui := ""
    static ToastW := 300, ToastH := 62, Margin := 20, Gap := 8, BottomOffset := 60

    static ErrorCodes := Map(
        "ERR_FILE_LOCKED",   "日记文件被锁定，请关闭 Obsidian 后重试",
        "ERR_FILE_WRITE",    "写入日记失败，输入内容已保留",
        "ERR_NOTE_CREATE",   "无法创建或读取日记文件",
        "ERR_NOTE_OPEN",     "无法打开日记文件",
        "ERR_DIR_OPEN",      "无法打开笔记目录",
        "ERR_NO_ENGINE",     "未找到搜索引擎快捷词，请到设置中检查配置",
        "ERR_SEARCH_URL",    "无法打开搜索链接",
        "ERR_NO_APP",        "未找到快捷启动项，请到设置中检查配置",
        "ERR_APP_RUN",       "无法打开目标程序",
        "ERR_SEND",          "按键发送失败，请检查按键串写法",
        "ERR_CALC",          "算式无法解析，请检查格式",
        "ERR_TEMPLATE",      "模板文件读取失败",
        "ERR_VOICE_CMD",     "未知语音命令"
    )

    static FromResult(res) {
        if (!IsObject(res) || res.pending)
            return
        if (res.ok) {
            switch res.action {
                case "empty": return
                case "note":  this.Send("note_success")
                case "todo":  this.Send("todo_success")
                case "image": this.Send("image_success")
                case "search", "ai", "fy", "launch", "open": this.Send("action_success")
                case "plugin": this.Send("plugin_success", "", res.text)
            }
        } else {
            if (res.silent)
                return
            msg := ""
            if (res.code != "" && this.ErrorCodes.Has(res.code))
                msg := this.ErrorCodes[res.code]
            if (res.msg != "")
                msg := (msg != "") ? (msg "`n`n" res.msg) : res.msg
            if (msg = "")
                msg := "未知错误"
            this.Send("error", "", msg)
        }
    }
    static Send(type, title := "", msg := "", shakeHwnd := 0) {
        if (!this.Presets.Has(type))
            type := "info"
        p := this.Presets[type]
        if (p.level = "warning" || p.level = "error")
            this._WriteLog(p.level, (title != "") ? title : p.title, msg)
        if (!ConfigManager.Get("NotifyEnabled", 1))
            return
        if (p.shake && shakeHwnd)
            this.Shake(shakeHwnd)
        text := (title != "") ? title : p.title
        this._AddHistory(p.level, text, msg)
        if (ConfigManager.Get("NotifySound", 1) && p.sound != "")
            this._PlaySound(p.sound)
        this._ShowToast(type, text, msg)
    }

    static Log(level, text, detail := "") {
        if (level = "info")
            return
        if (level = "debug" && !ConfigManager.Get("LogDebug", 0))
            return
        this._WriteLog(level, text, detail)
    }

    static _logPathCache := ""
    static _LogPath() {
        if (this._logPathCache = "") {
            logDir := AppPaths.LogsDir()
            try {
                DirCreate(logDir)
                this._logPathCache := logDir "\app.log"
            } catch {
                this._logPathCache := A_Temp "\kuangzi-app.log"
            }
        }
        return this._logPathCache
    }

    static _WriteLog(level, text, detail := "") {
        logPath := this._LogPath()
        try {
            if FileExist(logPath) {
                try {
                    fsize := FileGetSize(logPath)
                    if (fsize > 1048576) {
                        oldPath := RegExReplace(logPath, "\.log$", "") ".old.log"
                        if FileExist(oldPath)
                            FileDelete(oldPath)
                        FileMove(logPath, oldPath, 1)
                    }
                } catch {
                }
            }
        } catch {
        }
        logLine := FormatTime(, "yyyy-MM-dd HH:mm:ss")
                 . "." A_MSec
                 . " [" StrUpper(level) "] " text
        if (detail != "")
            logLine .= " | " detail
        f := ""
        try {
            f := FileOpen(logPath, "a", "UTF-8")
            f.Write(logLine "`n")
        } catch {
        } finally {
            if (f)
                try f.Close()
        }
    }

    static Shake(hwnd) {
        if (!hwnd)
            return
        try {
            WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            for off in [6, -6, 5, -5, 3, -3] {
                WinMove(x + off, y, , , "ahk_id " hwnd)
                Sleep(30)
            }
            WinMove(x, y, , , "ahk_id " hwnd)
        } catch {
        }
    }

    static ShowHistory() {
        if (this.HistoryGui) {
            this.HistoryGui.Show()
            return
        }
        hg := this.HistoryGui := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "通知历史")
        hg.SetFont("s9", "Microsoft YaHei")
        hg.OnEvent("Close", (*) => (this.HistoryGui.Hide(), this.HistoryGui := ""))
        lv := hg.Add("ListView", "x10 y10 w460 h300", ["时间", "级别", "内容", "详情"])
        loop this.History.Length {
            it := this.History[this.History.Length - A_Index + 1]
            lv.Add("", it.time, it.level, it.text, it.detail)
        }
        lv.ModifyCol(1, 70), lv.ModifyCol(2, 64), lv.ModifyCol(3, 130), lv.ModifyCol(4, 180)
        hg.Add("Button", "x10 y318 w100", "清空历史").OnEvent("Click", (*) => (this.History := [], lv.Delete()))
        hg.Show("w480 h355")
    }

    static _ShowToast(type, title, msg) {
        p := this.Presets[type]
        isCenter := p.center

        if (isCenter) {
            for i, t in this._toasts {
                if (t.center) {
                    this._RemoveToast(t)
                    break
                }
            }
        } else {
            while (this._toasts.Length >= this.MAX_TOASTS)
                this._RemoveToast(this._toasts[1])
        }

        w := isCenter ? 360 : this.ToastW
        h := isCenter ? 80 : this.ToastH
        tg := Gui("-Caption +AlwaysOnTop +ToolWindow +DPIScale")
        tg.BackColor := p.color
        tg.SetFont(isCenter ? "s11" : "s10", "Microsoft YaHei")
        clickFn := ObjBindMethod(this, "_OnToastClick")
        bg := tg.Add("Text", "x0 y0 w" w " h" h " c" p.color, "")
        bg.OnEvent("Click", clickFn)
        iconX := isCenter ? 20 : 14
        iconY := isCenter ? 16 : 10
        iconS := isCenter ? 32 : 24
        iconC := tg.Add("Text", "x" iconX " y" iconY " w" iconS " h" iconS " Center cFFFFFF", p.icon)
        iconC.SetFont(isCenter ? "s20 Bold" : "s14 Bold", "Segoe UI Symbol")
        iconC.OnEvent("Click", clickFn)
        titleX := isCenter ? 64 : 48
        titleY := isCenter ? 14 : 9
        titleW := isCenter ? 280 : 236
        titleC := tg.Add("Text", "x" titleX " y" titleY " w" titleW " h18 cFFFFFF", title)
        titleC.SetFont(isCenter ? "s12 Bold" : "Bold")
        titleC.OnEvent("Click", clickFn)
        if (msg != "") {
            msgY := isCenter ? 38 : 29
            msgW := isCenter ? 280 : 242
            msgC := tg.Add("Text", "x" titleX " y" msgY " w" msgW " h28 cF3F4F6", msg)
            msgC.OnEvent("Click", clickFn)
        }

        toast := { gui: tg, type: type, alpha: 0, phase: "in", tickFn: 0, center: isCenter }
        toast.tickFn := ObjBindMethod(this, "_FadeTick", toast)
        this._toasts.Push(toast)

        this._ApplyRound(tg.Hwnd)
        MonitorGetWorkArea(1, &WL, &WT, &WR, &WB)
        if (isCenter) {
            cx := WL + (WR - WL - w) // 2
            cy := WT + (WB - WT - h) // 2
            posX := cx, posY := cy
        } else {
            this._Relayout()
            posX := WR - w - this.Margin
            posY := WB - h - this.Margin - this.BottomOffset
        }
        WinSetTransparent(0, tg.Hwnd)
        tg.Show("x" posX " y" posY " w" w " h" h " NA")
        SetTimer(toast.tickFn, 16)
    }

    static _FadeTick(toast) {
        if (!toast.gui) {
            SetTimer(toast.tickFn, 0)
            return
        }
        hwnd := toast.gui.Hwnd
        if (!WinExist("ahk_id " hwnd)) {
            this._ForgetToast(toast)
            return
        }
        if (toast.phase = "in") {
            toast.alpha += 30
            if (toast.alpha >= 255) {
                WinSetTransparent(255, hwnd)
                toast.phase := "hold"
                SetTimer(toast.tickFn, 0)
                if (this.Presets.Has(toast.type) && this.Presets[toast.type].HasOwnProp("sticky") && this.Presets[toast.type].sticky)
                    return
                holdMs := toast.center ? 1200 : this.Presets[toast.type].duration
                SetTimer(ObjBindMethod(this, "_BeginFadeOut", toast), -holdMs)
                return
            }
            WinSetTransparent(toast.alpha, hwnd)
        } else if (toast.phase = "out") {
            toast.alpha -= 30
            if (toast.alpha <= 0) {
                this._RemoveToast(toast)
                return
            }
            WinSetTransparent(toast.alpha, hwnd)
        }
    }

    static _BeginFadeOut(toast) {
        if (!toast.gui)
            return
        toast.phase := "out"
        SetTimer(toast.tickFn, 16)
    }

    static _OnToastClick(obj, *) {
        gui := (Type(obj) = "Gui") ? obj : obj.Gui
        for toast in this._toasts {
            if (toast.gui = gui) {
                toast.phase := "out"
                SetTimer(toast.tickFn, 16)
                return
            }
        }
    }

    static _RemoveToast(toast) {
        SetTimer(toast.tickFn, 0)
        try toast.gui.Destroy()
        toast.gui := ""
        this._ForgetToast(toast)
        this._Relayout()
    }

    static _ForgetToast(toast) {
        for i, t in this._toasts {
            if (t = toast) {
                this._toasts.RemoveAt(i)
                break
            }
        }
    }

    static _Relayout() {
        n := this._toasts.Length
        if (n = 0)
            return
        MonitorGetWorkArea(1, &WL, &WT, &WR, &WB)
        w := this.ToastW, h := this.ToastH
        for i, toast in this._toasts {
            if (!toast.gui || toast.center)
                continue
            fromBottom := n - i
            x := WR - w - this.Margin
            y := WB - h - this.Margin - this.BottomOffset - fromBottom * (h + this.Gap)
            try toast.gui.Move(x, y, w, h)
        }
    }
    static _ApplyRound(hwnd) {
        try {
            attr := 2
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 33, "Int*", attr, "Int", 4)
        }
    }

    static _PlaySound(alias) {
        try SoundPlay(alias, false)
    }

    static _AddHistory(level, text, detail := "") {
        this.History.Push({ time: FormatTime(, "HH:mm:ss"), level: level, text: text, detail: detail })
        if (this.History.Length > this.MAX_HISTORY)
            this.History.RemoveAt(1)
    }
}
