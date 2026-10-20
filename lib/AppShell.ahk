#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "Router.ahk"
#Include "QuickNote.ahk"
#Include "QuickLaunch.ahk"
#Include "NotifyCenter.ahk"
#Include "Theme.ahk"
#Include "Actions.ahk"
#Include "AttachHelper.ahk"
#Include "AppInfo.ahk"
#Include "MainInput.ahk"
#Include "SettingsCenter.ahk"
#Include "QuickAppDialog.ahk"
#Include "SystemTray.ahk"
#Include "VoiceRouter.ahk"
#Include "VoiceCapture.ahk"
#Include "CapsLockHotkeys.ahk"
#Include "PluginManager.ahk"

class AppShell {
    static AppName => AppInfo.name
    static AppVersion => AppInfo.version

    static MainGui := ""
    static _pendingCenter := 0
    static OnRouteSubmit := 0
    static _InputCriterion := 0

    static input := 0, settings := 0, quickApp := 0, tray := 0

    static Run(configPath := "") {
        try {
            ConfigManager.Init(configPath)
        } catch as e {
            MsgBox(e.Message, this.AppName " - 无法启动", 16)
            ExitApp(1)
        }
        if (ConfigManager.LastLoadError != "")
            MsgBox(ConfigManager.LastLoadError, this.AppName " - 配置已重建", 48)
        this.Init(ObjBindMethod(Router, "Route"))
        this.BindGlobalHotkeys()
        if (ConfigManager.FirstRun)
            SetTimer(ObjBindMethod(this, "ShowSettings"), -1)
    }

    static Init(routeCallback) {
        ConfigManager.EnsureLoaded()
        this.OnRouteSubmit := routeCallback
        A_IconTip := this.AppName

        ActionBindings.RegisterCore()
        PluginManager.SweepStaleTasks()
        PluginManager.Scan()
        ActionBindings.RebuildPluginActions()
        PluginManager.OnTaskDone := (t) => this._OnPluginTaskDone(t)
        PluginManager.HostContext := (want) => this._PluginHostContext(want)
        ActionBindings.RebuildWordActions()

        this.BuildMainGui()

        this.input    := MainInput(this.MainGui, this)
        this.settings := SettingsCenter(this)
        this.quickApp := QuickAppDialog(this)
        this.tray     := SystemTray(this)
        this.tray.Init()

        this.input.InputRowsFn := ObjBindMethod(this, "_InputRows")

        this.BindInputHotkeys()

        QuickLaunch.OnCompleted := ObjBindMethod(this.input, "HandleRouteResult")

        PickerDraft.Draft := ObjBindMethod(this.input, "DraftRev")
        PickerDraft.Unchanged := ObjBindMethod(this.input, "DraftUnchanged")

        VoiceRouter.Host := this
        Lexicon.Host := this
    }

    static BuildMainGui() {
        this.OwnerDummy := Gui("-Caption")
        this.MainGui := Gui("-Caption +AlwaysOnTop +Owner" this.OwnerDummy.Hwnd, this.AppName)
        this.MainGui.BackColor := Theme.COLOR_WIN_BG
        this.MainGui.Show("Hide")
        this.ApplyModernShadowAndCorners(this.MainGui.Hwnd)
    }

    static ApplyModernShadowAndCorners(hwnd) {
        AppShell.NCProc := CallbackCreate(AppShell_NCCalcProc, "Ptr", 6)
        DllCall("Comctl32\SetWindowSubclass", "Ptr", hwnd, "Ptr", AppShell.NCProc, "Ptr", 1, "Ptr", 0)
        style := DllCall("User32\GetWindowLongW", "Ptr", hwnd, "Int", -16, "Int")
        DllCall("User32\SetWindowLongW", "Ptr", hwnd, "Int", -16, "Int", style | 0xC40000)
        DllCall("User32\SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x37)
        try {
            attr := 2
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "Int", 33, "Int*", attr, "Int", 4)
        }
    }

    static GetCurrentGuiSize(&w, &h) {
        if (ConfigManager.Get("TurboMode")) {
            w := Theme.TURBO_W, h := Theme.TURBO_H
        } else {
            w := Theme.NORMAL_W, h := Theme.NORMAL_H
        }
    }

    static ReloadConfigIfChanged() {
        oldHotkeys := Map(
            "ToggleHotkey", ConfigManager.Get("ToggleHotkey"),
            "VoiceLaunchHotkey", ConfigManager.Get("VoiceLaunchHotkey")
        )
        oldRows := ConfigManager.Get("GlobalHotkeyRows", [])
        if (!ConfigManager.ReloadIfDiskChanged())
            return
        this.OnSettingsChanged(oldHotkeys, oldRows)
        NotifyCenter.Send("info", this.AppName, "检测到配置有外部改动，已自动重载")
    }

    static ToggleMainGui(*) {
        visible := DllCall("User32\IsWindowVisible", "Ptr", this.MainGui.Hwnd)
        if (!visible)
            this.ReloadConfigIfChanged()
        if (visible) {
            if (ConfigManager.Get("AlwaysShow"))
                return
            this.HideAndSavePos()
            return
        }
        if (ConfigManager.Get("AlwaysShow") && WinExist("ahk_id " this.MainGui.Hwnd)) {
            this.MainGui.Show()
            this.input.Focus()
            return
        }
        this._ShowMainGui()
    }

    static _ShowMainGui() {
        this.GetCurrentGuiSize(&curW, &curH)

        MouseGetPos(&mouseX, &mouseY)
        curMonitor := 1
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &mLeft, &mTop, &mRight, &mBottom)
            if (mouseX >= mLeft && mouseX < mRight && mouseY >= mTop && mouseY < mBottom) {
                curMonitor := A_Index
                break
            }
        }
        MonitorGetWorkArea(curMonitor, &WL, &WT, &WR, &WB)

        if (this._pendingCenter) {
            pc := this._pendingCenter
            this._pendingCenter := 0
            centerX := pc.x + pc.w / 2
            centerY := pc.y + pc.h / 2
            PosX := Round(centerX - curW / 2)
            PosY := Round(centerY - curH / 2)
            if (PosX < WL)
                PosX := WL
            if (PosY < WT)
                PosY := WT
            if (PosX + curW > WR)
                PosX := WR - curW
            if (PosY + curH > WB)
                PosY := WB - curH
        } else if (IsNumber(ConfigManager.Get("WinX")) && IsNumber(ConfigManager.Get("WinY")) && ConfigManager.Get("WinX") > 0 && ConfigManager.Get("WinY") > 0) {
            WinX := ConfigManager.Get("WinX"), WinY := ConfigManager.Get("WinY")
            if (WinX >= WL && (WinX + curW) <= WR && WinY >= WT && (WinY + curH) <= WB) {
                PosX := WinX
                PosY := WinY
            } else {
                PosX := WL + (WR - WL - curW) / 2
                PosY := WB - curH - 150
            }
        } else {
            PosX := WL + (WR - WL - curW) / 2
            PosY := WB - curH - 150
        }

        this.MainGui.Show("x" PosX " y" PosY " w" curW " h" curH)
        dpi := DllCall("User32\GetDpiForWindow", "Ptr", this.MainGui.Hwnd, "UInt")
        if (!dpi)
            dpi := 96
        WinMove(PosX, PosY, Round(curW * dpi / 96), Round(curH * dpi / 96), "ahk_id " this.MainGui.Hwnd)
        this.input.Focus()
    }

    static HideAndSavePos(*) {
        if !DllCall("User32\IsWindowVisible", "Ptr", this.MainGui.Hwnd)
            return
        WinGetPos(&X, &Y, &W, &H, "ahk_id " this.MainGui.Hwnd)
        this.MainGui.Hide()
        this.input.ClearHover()
        if (X != "" && Y != "" && (X != ConfigManager.Get("WinX") || Y != ConfigManager.Get("WinY"))) {
            ConfigManager.Set("WinX", X)
            ConfigManager.Set("WinY", Y)
            ConfigManager.Save()
        }
    }

    static _OnPluginTaskDone(t) {
        if (t.mode = "execute")
            this._RenderPluginResult(t.result)
        this.ConsumePendingRev()
        if (this.PendingDraftUnchangedSafe())
            this.AfterSubmit()
    }

    static PendingDraftUnchangedSafe() {
        return (this.input && this.input.HasProp("_pendingRev")) ? this.input.PendingDraftUnchanged() : false
    }

    static ConsumePendingRev() {
        if (this.input && this.input.HasProp("_pendingRev"))
            this.input.ConsumePendingRev()
    }

    static _TouchDraftSafe() {
        if (this.input && this.input.HasProp("_draftRev"))
            this.input._TouchDraft()
    }

    static _RenderPluginResult(res) {
        intent := (res.HasOwnProp("intent") && res.intent != "notify") ? res.intent : "notify"
        if (intent != "notify" && res.text = "")
            intent := "notify"
        style := (res.HasOwnProp("notifyStyle") && res.notifyStyle = "toast") ? "toast" : "center"
        switch intent {
            case "fill":
                if (!this.input || !this.input.PendingDraftUnchanged()) {
                    NotifyCenter.Send("plugin_success", "插件结果", SubStr(res.text, 1, 80))
                    return
                }
                this._ShowMainGui()
                this.input.EditCtrl.Value := res.text
                this._TouchDraftSafe()
                this.input.Focus()
                return
            case "copy":
                A_Clipboard := res.text
                if (style = "toast")
                    NotifyCenter.Send("info", "框子", "已复制：" SubStr(res.text, 1, 50))
                else
                    NotifyCenter.Send("plugin_success", "已复制到剪贴板", res.text)
                return
            case "todo":
                r := QuickNote.Submit(res.text, true, "plugin")
                if (!r.ok)
                    NotifyCenter.Send("error", "框子", "记待办失败：" r.msg)
                return
        }
        if (style = "toast" && intent = "notify")
            NotifyCenter.Send(res.ok ? "info" : "error", "框子", res.text != "" ? res.text : res.msg)
        else
            NotifyCenter.FromResult(res)
    }

    static _PluginHostContext(want) {
        hc := Map()
        if (this.MainGui && WinExist("ahk_id " this.MainGui.Hwnd)) {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " this.MainGui.Hwnd)
            hc["window"] := Map("x", wx, "y", wy, "w", ww, "h", wh)
        } else {
            mx := ConfigManager.Get("WinX", ""), my := ConfigManager.Get("WinY", "")
            if (mx != "" && my != "") {
                this.GetCurrentGuiSize(&gw, &gh)
                hc["window"] := Map("x", mx, "y", my, "w", gw, "h", gh)
            }
        }
        mon := 1
        if (hc.Has("window")) {
            w := hc["window"]
            Loop MonitorGetCount() {
                MonitorGet(A_Index, &mL, &mT, &mR, &mB)
                if (w["x"] >= mL && w["x"] < mR && w["y"] >= mT && w["y"] < mB) {
                    mon := A_Index
                    break
                }
            }
        }
        MonitorGet(mon, &mL, &mT, &mR, &mB)
        scale := 1
        try {
            hMon := DllCall("User32\MonitorFromPoint", "Int64", (mR - mL) / 2 + (mB - mT) / 2 * 0x100000000, "UInt", 2)
            dpi := DllCall("Shcore\GetDpiForMonitor", "Ptr", hMon, "Int", 0, "Ptr*", dm := 0, "Ptr*", dd := 0, "UInt")
            if (!dpi && dm)
                scale := Round(dm / 96, 2)
        } catch {
        }
        hc["screen"] := Map("w", mR - mL, "h", mB - mT, "scale", scale)
        if (want.Has("read:focused-window")) {
            fw := WinExist("A")
            if (fw) {
                title := "", exe := ""
                try title := WinGetTitle("ahk_id " fw)
                try exe := WinGetProcessName("ahk_id " fw)
                hc["focused"] := Map("title", title, "exe", exe)
            }
        }
        if (want.Has("read:clipboard")) {
            clip := Map("text", "", "hasImage", false, "truncated", false)
            try {
                t := A_Clipboard
                if (StrLen(t) > 4096) {
                    t := SubStr(t, 1, 4096)
                    clip["truncated"] := true
                }
                clip["text"] := t
            } catch {
            }
            try clip["hasImage"] := DllCall("User32\IsClipboardFormatAvailable", "UInt", 2, "Int")
            hc["clipboard"] := clip
        }
        return hc
    }

    static AfterSubmit() {
        if (ConfigManager.Get("AlwaysShow")) {
            this.input.Clear()
            this.input.Focus()
        } else {
            this.input.Clear()
            this.HideAndSavePos()
        }
    }

    static SaveOldGuiPos() {
        if !DllCall("User32\IsWindowVisible", "Ptr", this.MainGui.Hwnd)
            return
        WinGetPos(&X, &Y, &W, &H, "ahk_id " this.MainGui.Hwnd)
        this._pendingCenter := { x: X, y: Y, w: W, h: H }
    }

    static SwitchMode(targetTurbo) {
        ConfigManager.EnsureLoaded()
        if (ConfigManager.Get("TurboMode") != targetTurbo) {
            this.SaveOldGuiPos()
            oldTurbo := ConfigManager.Get("TurboMode")
            ConfigManager.Set("TurboMode", targetTurbo)
            if !ConfigManager.Save(true) {
                ConfigManager.Set("TurboMode", oldTurbo)
                NotifyCenter.Send("error", "模式切换失败", ConfigManager.LastError)
                return
            }
            wasVisible := this.MainGui && DllCall("User32\IsWindowVisible", "Ptr", this.MainGui.Hwnd)
            this.input.Rebuild()
            this.tray.Update()
            if (wasVisible) {
                this._ShowMainGui()
                return
            }
        }
        this.ToggleMainGui()
    }

    static CycleMode(*) {
        this.SwitchMode(!ConfigManager.Get("TurboMode"))
    }

    static ToggleTurboMode(*) {
        this.SwitchMode(!ConfigManager.Get("TurboMode"))
    }

    static ToggleAlwaysShow(*) {
        ConfigManager.Set("AlwaysShow", ConfigManager.Get("AlwaysShow") ? 0 : 1)
        ConfigManager.Save()
        this.tray.Update()
        if (ConfigManager.Get("AlwaysShow"))
            this.ToggleMainGui()
    }

    static VoiceInput(*) {
        imeKey := ConfigManager.Get("IMEVoiceHotkey")
        if (imeKey = "" || StrLen(imeKey) < 3)
            return
        sendSeq := Utils.ConvertHotkeyToSend(imeKey)
        if (sendSeq = "")
            return
        if WinActive("ahk_id " this.MainGui.Hwnd) {
            Sleep 100
            Send(sendSeq)
            return
        }
        this.SwitchMode(ConfigManager.Get("TurboMode"))
        Sleep 200
        Send(sendSeq)
    }

    static VoiceLaunch(*) {
        if (VoiceCapture._active)
            return
        VoiceCapture.Begin(ObjBindMethod(this, "_OnVoiceCaptured"))
    }

    static _OnVoiceCaptured(text) {
        if (text = "") {
            NotifyCenter.Send("info", "智慧语音", "未识别到语音内容或识别超时")
            NotifyCenter.Log("warning", "智慧语音", "取字超时，剪贴板未收到内容")
            return
        }
        res := VoiceRouter.Process(text)
        NotifyCenter.FromResult(res)
    }

    static ClipboardAction(action := "note") {
        res := Actions.Run("clipSmart", { param: action, host: this })
        if (IsObject(res))
            this.input.HandleRouteResult(res)
    }

    static GrabSelection() {
        saved := ClipboardAll()
        A_Clipboard := ""
        SendInput "^c"
        if (!ClipWait(0.3)) {
            A_Clipboard := saved
            return ""
        }
        text := Trim(A_Clipboard)
        if (text = "") {
            A_Clipboard := saved
            return ""
        }
        return text
    }

    static SelectionAction(action := "") {
        if (action = "")
            return
        text := this.GrabSelection()
        if (text = "") {
            NotifyCenter.Send("warning", "没有选中内容", "请先选中文字，再按该快捷键")
            return
        }
        res := Actions.Run(action, { text: text, source: "selection", host: this })
        if (IsObject(res))
            this.input.HandleRouteResult(res)
    }

    static ClipboardSmart(param := "note") {
        if (!AttachHelper.HasImage() && !AttachHelper.HasFiles() && Trim(A_Clipboard) = "") {
            NotifyCenter.Send("warning", "剪贴板为空", "请先复制内容，再使用剪贴板快捷键")
            return Utils.ResPending("clipSmart")
        }
        ref := AttachHelper.AttachClipboard()
        if (!IsObject(ref) && ref = "") {
            if (AttachHelper.HasFiles())
                NotifyCenter.Send("warning", "剪贴板文件不支持", "剪贴板中的文件不是支持的格式（图片/视频/音频/文档），或超出大小上限 " AttachHelper.MaxMB() "MB")
            else
                NotifyCenter.Send("error", "", "附件保存失败，请重试")
            return Utils.ResPending("clipSmart")
        }
        a := Actions.Get(param)
        if (a = "" || a.kind = "entry")
            param := "note"
        if (IsObject(ref)) {
            imgs := [], fls := []
            for r in ref {
                if (InStr(r, "/media/") || InStr(r, "/doc/"))
                    fls.Push(r)
                else
                    imgs.Push(r)
            }
            return Actions.Run(param, { text: "", source: "clipboard", images: imgs, files: fls })
        }
        return Actions.Run(param, { text: ref, source: "clipboard" })
    }

    static NewNote(*) {
        QuickNote.NewNote()
    }

    static QuickLaunchAction(action := "") {
        if (action = "")
            return
        res := Actions.Run(action, { text: "", host: this, source: "quickKey" })
        if (res = "" || res.pending)
            return
        NotifyCenter.FromResult(res)
    }

    static _IsMainActive(*) {
        return this.MainGui && WinActive("ahk_id " this.MainGui.Hwnd)
    }

    static BindInputHotkeys() {
        if (!this._InputCriterion)
            this._InputCriterion := ObjBindMethod(this, "_IsMainActive")
        HotIf(this._InputCriterion)
        Hotkey("Enter", (*) => this.input.HandleEnterAction(), "On")
        for r in this._InputRows() {
            if (r.key != "")
                this._RegisterSlotHotkey(r.key)
        }
        Hotkey("^m", ObjBindMethod(this, "CycleMode"), "On")
        Hotkey("^Up", (*) => this.input.NavigateHistoryUp(), "On")
        Hotkey("^Down", (*) => this.input.NavigateHistoryDown(), "On")
        Hotkey("^v", (*) => this.input._HandlePaste(), "On")
        Hotkey("Esc", ObjBindMethod(this, "HideAndSavePos"), "On")
        HotIf()
    }

    static _RowField(row, name) {
        return Utils.ObjGet(row, name)
    }

    static _InputRows() {
        out := []
        for r in ConfigManager.Get("GlobalHotkeyRows", []) {
            if (this._RowField(r, "domain") != "input")
                continue
            out.Push({ key: this._RowField(r, "key"), action: this._RowField(r, "action") })
        }
        return out
    }

    static RebindInputKeySlots(oldRows) {
        if (!this._InputCriterion)
            this._InputCriterion := ObjBindMethod(this, "_IsMainActive")
        HotIf(this._InputCriterion)
        if (IsObject(oldRows)) {
            for r in oldRows {
                rk := this._RowField(r, "key")
                if (rk != "" && this._RowField(r, "domain") = "input")
                    try Hotkey(rk, "Off")
            }
        }
        for r in this._InputRows() {
            if (r.key != "")
                this._RegisterSlotHotkey(r.key)
        }
        HotIf()
    }

    static _RegisterSlotHotkey(key) {
        try Hotkey(key, (*) => this.input.HandleInputHotkey(key), "On")
    }

    static _MakeClipHandler(action) {
        return (*) => AppShell.ClipboardAction(action)
    }

    static _BindClipRows(oldRows := "") {
        this._ClipFailedKeys := []
        if (IsObject(oldRows)) {
            for r in oldRows {
                rk := this._RowField(r, "key")
                if (rk != "" && this._RowField(r, "domain") = "clip")
                    try Hotkey(rk, "Off")
            }
        }
        for r in ConfigManager.Get("GlobalHotkeyRows", []) {
            rk := this._RowField(r, "key")
            ra := this._RowField(r, "action")
            if (this._RowField(r, "domain") != "clip" || rk = "")
                continue
            try Hotkey(rk, this._MakeClipHandler(ra), "On")
            catch as e {
                this._ClipFailedKeys.Push(rk)
                NotifyCenter.Log("warning", "快捷键注册失败", rk "（" ra "）：" e.Message)
            }
        }
    }

    static _BindAnyRows(oldRows := "") {
        if (IsObject(oldRows)) {
            for r in oldRows {
                rk := this._RowField(r, "key")
                if (rk != "" && this._RowField(r, "domain") = "any")
                    try Hotkey(rk, "Off")
            }
        }
        for r in ConfigManager.Get("GlobalHotkeyRows", []) {
            rk := this._RowField(r, "key")
            ra := this._RowField(r, "action")
            if (this._RowField(r, "domain") != "any" || rk = "")
                continue
            try Hotkey(rk, this._MakeAnyHandler(ra), "On")
            catch as e
                NotifyCenter.Log("warning", "快捷键注册失败", rk "（" ra "）：" e.Message)
        }
    }

    static _BindSelectRows(oldRows := "") {
        if (IsObject(oldRows)) {
            for r in oldRows {
                rk := this._RowField(r, "key")
                if (rk != "" && this._RowField(r, "domain") = "select")
                    try Hotkey(rk, "Off")
            }
        }
        for r in ConfigManager.Get("GlobalHotkeyRows", []) {
            rk := this._RowField(r, "key")
            ra := this._RowField(r, "action")
            if (this._RowField(r, "domain") != "select" || rk = "")
                continue
            try Hotkey(rk, this._MakeSelectHandler(ra), "On")
            catch as e
                NotifyCenter.Log("warning", "快捷键注册失败", rk "（" ra "）：" e.Message)
        }
    }

    static _MakeSelectHandler(action) {
        return (*) => AppShell.SelectionAction(action)
    }

    static _MakeAnyHandler(action) {
        return (*) => AppShell.AnyHotkeyAction(action)
    }

    static AnyHotkeyAction(action := "") {
        if (action = "")
            return
        res := Actions.Run(action, { text: "", host: this, source: "hotkey" })
        if (res = "" || res.pending)
            return
        NotifyCenter.FromResult(res)
    }

    static BindGlobalHotkeys() {
        if (ConfigManager.Get("ToggleHotkey")) {
            try Hotkey(ConfigManager.Get("ToggleHotkey"), ObjBindMethod(this, "ToggleMainGui"), "On")
        }
        this._BindClipRows()
        this._BindSelectRows()
        this._BindAnyRows()
        if (ConfigManager.Get("VoiceLaunchHotkey")) {
            try Hotkey(ConfigManager.Get("VoiceLaunchHotkey"), ObjBindMethod(this, "VoiceLaunch"), "On")
        }

        try CapsLockHotkeys.Register(this)
    }

    static RebindHotkey(oldKey, newKey, handler, configKey, fallback, showMsg := true) {
        if (oldKey = newKey)
            return
        if (oldKey)
            try Hotkey(oldKey, "Off")
        if (newKey) {
            try Hotkey(newKey, handler, "On")
            catch {
                if (showMsg)
                    NotifyCenter.Send("error", "快捷键错误", "快捷键格式被占用或不支持，已恢复" fallback)
                ConfigManager.Set(configKey, fallback)
                ConfigManager.Save()
                if (fallback)
                    Hotkey(fallback, handler, "On")
            }
        }
    }

    static Route(text, mode, imgs := [], files := []) {
        if (!this.OnRouteSubmit)
            return ""
        return (this.OnRouteSubmit)(text, mode, imgs, files)
    }

    static HandleRes(res) {
        this.input.HandleRouteResult(res)
    }

    static IsMainVisible() {
        return DllCall("User32\IsWindowVisible", "Ptr", this.MainGui.Hwnd)
    }
    static HideMain() {
        this.MainGui.Hide()
    }

    static ShowSettings(*) {
        this.settings.ShowSettings()
    }

    static ShowQuickAppDialog(*) {
        this.quickApp.ShowQuickAppDialog()
    }
    static ShowQuickSearchDialog(*) {
        this.quickApp.ShowQuickSearchDialog()
    }
    static ShowBatchAppDialog(*) {
        this.quickApp.ShowBatchAppDialog()
    }

    static FirstRunShow() {
        this.input.Rebuild()
        this.ToggleMainGui()
    }

    static SyncAppShortcuts() {
        this.settings.RefreshAppShortcutsText()
    }

    static SyncSearchEngines() {
        this.settings.RefreshSearchEnginesText()
    }

    static OnSettingsChanged(oldHotkeys, oldRows := "") {
        this.input.Rebuild()
        this.tray.Update()
        this.RebindInputKeySlots(oldRows)
        this.RebindHotkey(oldHotkeys["ToggleHotkey"], ConfigManager.Get("ToggleHotkey"), ObjBindMethod(this, "ToggleMainGui"), "ToggleHotkey", "", false)
        this.RebindHotkey(oldHotkeys["VoiceLaunchHotkey"], ConfigManager.Get("VoiceLaunchHotkey"), ObjBindMethod(this, "VoiceLaunch"), "VoiceLaunchHotkey", "RControl", false)
        this._BindClipRows(oldRows)
        this._BindSelectRows(oldRows)
        this._BindAnyRows(oldRows)

        try CapsLockHotkeys.ReRegisterQuickKeys(this)
    }

    static TopMsgBox(Text, Title := "", Options := 0) {
        tops := []
        guis := [this.MainGui]
        for g in this.quickApp.GetTopmostGuis()
            guis.Push(g)
        for g in guis {
            if (g && g.Hwnd && DllCall("User32\IsWindowVisible", "Ptr", g.Hwnd)) {
                g.Opt("-AlwaysOnTop")
                tops.Push(g)
            }
        }
        try res := MsgBox(Text, Title, Options)
        finally {
            for g in tops
                g.Opt("+AlwaysOnTop")
        }
        return res
    }

    static Quit(*) {
        PluginManager.CancelAll()
        ExitApp()
    }

    static Uninstall(*) {
        if !A_IsCompiled {
            MsgBox("当前是源码运行模式，没有安装过，也无需卸载。`n`n如需清理，请手动删除配置目录与启动项。"
                , this.AppName " - 源码模式", 48)
            return
        }
        exe := A_ScriptDir "\" AppInfo.pinyin "-uninstall.exe"
        if !FileExist(exe) {
            MsgBox("找不到卸载器：`n" exe "`n`n可改用开始菜单的「卸载" this.AppName "」，或系统「应用和功能」。"
                , this.AppName " - 卸载", 48)
            return
        }
        PluginManager.CancelAll()
        Run('"' exe '"')
        ExitApp()
    }
}

AppShell_NCCalcProc(hwnd, uMsg, wParam, lParam, idSubclass, refData) {
    if (uMsg = 0x83)
        return 0
    return DllCall("Comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

Actions.RegisterRoute("clipSmart", "智能剪贴板路由", "📋", (c) => AppShell.ClipboardSmart(c.param), 0)
