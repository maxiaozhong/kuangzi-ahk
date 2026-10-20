#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "NotifyCenter.ahk"
#Include "QuickLaunch.ahk"
#Include "Actions.ahk"
#Include "ActionBindings.ahk"
#Include "Theme.ahk"
#Include "HotkeyCapture.ahk"
#Include "SettingsValidator.ahk"
#Include "SettingsViews.ahk"

class SettingsCenter {
    host := 0
    capture := 0
    views := 0

    SettingsGui := ""
    Ctrls := Map()
    SavePending := false
    InputWasVisible := false

    static LIST_PAGES := Map(
        "SearchEngines", SettingsTabSearch,
        "WordTable", SettingsTabLaunch,
        "CapsLockActions", SettingsTabQuickKey,
        "GlobalHotkeyRows", SettingsTabHotkeyTable,
        "VoiceRoutes", SettingsTabVoice)

    __New(host) {
        this.host := host
        this.capture := HotkeyCapture(this)
        this.views := SettingsViews(this)
        this.BuildSettingsGui()
    }

    BuildSettingsGui() {
        SG := this.SettingsGui := Gui("+MinimizeBox -MaximizeBox", this.host.AppName " - 设置中心 v" this.host.AppVersion)
        SG.SetFont("s9", "Microsoft YaHei")
        SG.OnEvent("Close", ObjBindMethod(this, "CloseSettings"))

        TAB_H := Min(500, SysGet(79) - 100)
        this.views.BuildAll(SG, TAB_H)

        C := this.Ctrls
        BTN_Y := 10 + TAB_H + 10
        BTN_W := 110, BTN_GAP := 10
        BTN_X := SettingsViews.TAB_X + Round((SettingsViews.TAB_W - (BTN_W * 2 + BTN_GAP)) / 2)
        SaveBtn := SG.Add("Button", "w" BTN_W " x" BTN_X " y" BTN_Y " Default", "保存并应用")
        C["SaveMsg"] := SG.Add("Text", "x" BTN_X " y" BTN_Y - 25 " w200 h20 c" Theme.COLOR_OK " Hidden", "✅ 设置已保存")
        SaveBtn.OnEvent("Click", ObjBindMethod(this, "SaveSettings"))
        CancelBtn := SG.Add("Button", "w" BTN_W " x" (BTN_X + BTN_W + BTN_GAP) " y" BTN_Y, "取消")
        CancelBtn.OnEvent("Click", ObjBindMethod(this, "CloseSettings"))
    }

    CloseSettings(*) {
        this.capture.CancelCapture()
        this.SavePending := false
        this.SettingsGui.Hide()
        if (this.InputWasVisible)
            this.host.ToggleMainGui()
        if (ConfigManager.FirstRun) {
            this.host.FirstRunShow()
            ConfigManager.FirstRun := false
        }
    }

    AfterSaveClose() {
        if (!this.SavePending)
            return
        this.SavePending := false
        this.SettingsGui.Hide()
        if (this.InputWasVisible)
            this.host.ToggleMainGui()
        else if (ConfigManager.FirstRun)
            SetTimer(ObjBindMethod(this.host, "ToggleMainGui"), -1)
        ConfigManager.FirstRun := false
    }

    ShowSettings(*) {
        this.InputWasVisible := this.host.IsMainVisible()
        if (this.InputWasVisible)
            this.host.HideMain()
        ConfigManager.Load()
        for k, ctrl in this.Ctrls {
            if (k = "SaveMsg" || k = "GlobalHkMsg" || k = "InputHkMsg" || !ConfigManager.Config.Has(k) || !IsObject(ctrl))
                continue
            if (SettingsCenter.LIST_PAGES.Has(k)) {
                SettingsCenter.LIST_PAGES[k].ReloadFromConfig()
                continue
            }
            if (k = "EnterActionNormal" || k = "EnterActionTurbo") {
                ctrl.Choose(SettingsTabInput.EnterActionToLabel(ConfigManager.Get(k)))
            } else if (k = "ConfirmFallback") {
                ctrl.Choose(SettingsTabInput.TextActionToLabel(ConfigManager.Get(k)))
            } else if (k = "NotePeriod") {
                ctrl.Choose(SettingsTabNote.PeriodToLabel(ConfigManager.Get("NotePeriod", "day")))
            } else if (k = "SearchEngine") {
                cur := ConfigManager.Get(k)
                if (cur != "" && ConfigManager.EngineMap.Has(cur))
                    ctrl.Choose(cur)
            } else if (HotkeyCapture.IsCaptureKey(k)) {
                this.capture.SetHotkeyBtn(k, ConfigManager.Get(k))
            } else
                continue
        }
        tools := ConfigManager.Get("InputBarTools", ConfigManager.GetDefaultInputBarTools())
        for t in Actions.All() {
            key := "InputBar_" t.id
            if (this.Ctrls.Has(key) && IsObject(this.Ctrls[key]))
                this.Ctrls[key].Value := Utils.ArrContains(tools, t.id) ? 1 : 0
        }
        this.SettingsGui.Show()
        this.SettingsGui.GetPos(&gx, &gy, &gw, &gh)
        workAreaBottom := SysGet(79)
        if (gy + gh > workAreaBottom) {
            newY := Max(0, workAreaBottom - gh - 10)
            this.SettingsGui.Move(gx, newY)
        }
    }

    RefreshAppShortcutsText() => this.views.RefreshAppShortcutsText()

    RefreshSearchEnginesText() => this.views.RefreshSearchEnginesText()

    SaveSettings(*) {
        this.capture.CancelCapture()
        if !SettingsValidator.Validate(this.Ctrls, this.capture.HkValues)
            return
        oldHotkeys := Map(
            "ToggleHotkey", ConfigManager.Get("ToggleHotkey"),
            "VoiceLaunchHotkey", ConfigManager.Get("VoiceLaunchHotkey")
        )
        oldRows := ConfigManager.Get("GlobalHotkeyRows", [])

        for k, ctrl in this.Ctrls {
            if (SettingsCenter.LIST_PAGES.Has(k))
                continue
            if (k = "SaveMsg" || k = "GlobalHkMsg" || k = "InputHkMsg" || !ConfigManager.Config.Has(k) || !IsObject(ctrl))
                continue
            if (HotkeyCapture.IsCaptureKey(k)) {
                ConfigManager.Set(k, this.capture.HkValues.Has(k) ? this.capture.HkValues[k] : "")
                continue
            }
            if (k = "EnterActionNormal" || k = "EnterActionTurbo")
                val := SettingsTabInput.EnterLabelToAction(ctrl.Text)
            else if (k = "ConfirmFallback")
                val := SettingsTabInput.TextActionLabelToValue(ctrl.Text)
            else if (k = "NotePeriod")
                val := SettingsTabNote.LabelToPeriod(ctrl.Text)
            else if (k = "SearchEngine")
                val := ctrl.Text
            else
                val := ctrl.Value
            ConfigManager.Set(k, val)
        }

        for key, page in SettingsCenter.LIST_PAGES
            ConfigManager.Set(key, page.GetEntriesForSave())

        toolbarTools := []
        for t in Actions.All() {
            key := "InputBar_" t.id
            if (this.Ctrls.Has(key) && this.Ctrls[key].Value)
                toolbarTools.Push(t.id)
        }
        ConfigManager.Set("InputBarTools", toolbarTools)

        if !ConfigManager.Save(true) {
            NotifyCenter.Send("error", "设置保存失败", ConfigManager.LastError)
            return
        }
        ConfigManager.RebuildEngineCache()
        ConfigManager.RebuildWordCache()

        autostartWanted := this.Ctrls["AutoStart"].Value
        ShortcutPath := A_Startup "\" this.host.AppName ".lnk"
        if A_IsCompiled {
            autostartTarget := AppPaths.InstallExe()
            if (autostartTarget = "")
                autostartTarget := A_ScriptFullPath
            try {
                if (autostartWanted) {
                    if FileExist(ShortcutPath)
                        FileDelete(ShortcutPath)
                    FileCreateShortcut(autostartTarget, ShortcutPath, A_ScriptDir)
                } else {
                    if FileExist(ShortcutPath)
                        FileDelete(ShortcutPath)
                }
            } catch as e {
                NotifyCenter.Send("warning", "自启设置失败", "其他设置已保存 | " e.Message)
            }
        }

        this.host.OnSettingsChanged(oldHotkeys, oldRows)

        this.SavePending := true
        this.Ctrls["SaveMsg"].Visible := true
        SetTimer(() => this.Ctrls["SaveMsg"].Visible := false, -500)
        SetTimer(ObjBindMethod(this, "AfterSaveClose"), -500)
    }
}
