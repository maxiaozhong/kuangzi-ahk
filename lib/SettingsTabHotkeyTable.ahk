#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "Theme.ahk"
#Include "ConfigManager.ahk"
#Include "NotifyCenter.ahk"
#Include "Actions.ahk"
#Include "HotkeyCapture.ahk"
#Include "Presentation.ahk"

class SettingsTabHotkeyTable {
    static _Entries := []
    static _List := ""

    static FIXED_ROWS := [
        { configKey: "ToggleHotkey",      label: "唤起输入框", domain: "any", note: "全局唤起/隐藏输入框" },
        { configKey: "VoiceLaunchHotkey", label: "智慧语音",   domain: "any", note: "长按说话，松手执行（四环节编排）" }
    ]

    static LOCKED_ROWS := [
        { key: "Esc",        label: "隐藏输入框",           domain: "input" },
        { key: "^v",         label: "粘贴（图片·文件转附件）", domain: "input" },
        { key: "^m",         label: "切换输入框模式",        domain: "input" },
        { key: "^Up/^Down",  label: "翻历史记录",           domain: "input" },
        { key: "+CapsLock",  label: "大写锁定（系统行为）",   domain: "any" }
    ]

    static DOMAIN_LABELS := Map("clip", "剪贴板", "select", "选中", "input", "应用框内", "any", "全局")
    static DOMAIN_KEYS := ["clip", "select", "input", "any"]

    static _DomLabel(dom) => SettingsTabHotkeyTable.DOMAIN_LABELS.Has(dom) ? SettingsTabHotkeyTable.DOMAIN_LABELS[dom] : dom

    static _LabelToDom(lbl) {
        for k, v in SettingsTabHotkeyTable.DOMAIN_LABELS {
            if (v = lbl)
                return k
        }
        return "clip"
    }

    static _DomIndex(dom) {
        for i, k in SettingsTabHotkeyTable.DOMAIN_KEYS {
            if (k = dom)
                return i
        }
        return 1
    }

    static _CaptureMode(dom) => (dom = "input") ? "input" : "global"

    static Build(SG, Tabs, i, center) {
        C := center.Ctrls
        Tabs.UseTab(i)
        yPos := Theme.SET_PAGE_Y
        SG.Add("GroupBox", "x" Theme.SET_PAGE_X " y" yPos " w" Theme.SET_PAGE_W " h" Theme.SET_PAGE_H, "快捷键总表")
        yPos += 28

        LV_H := Theme.SetListBottom() - yPos
        lv := SG.Add("ListView", "x" Theme.SET_LIST_X " y" yPos " w" Theme.SET_LIST_W " h" LV_H " -Multi NoSortHdr Grid", ["快捷键", "消费域", "来源", "动作"])
        lv.ModifyCol(1, 130), lv.ModifyCol(2, 85), lv.ModifyCol(3, 55), lv.ModifyCol(4, 310)
        lv.OnEvent("DoubleClick", (lvObj, row) => SettingsTabHotkeyTable._EditEntry(center, row))
        SettingsTabHotkeyTable._List := lv

        BTN_Y := Theme.SetBtnY()
        SG.Add("Button", "x" Theme.SetBtnX(0) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "添加...").OnEvent("Click", (*) => SettingsTabHotkeyTable._AddEntry(center))
        SG.Add("Button", "x" Theme.SetBtnX(1) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "恢复默认").OnEvent("Click", (*) => SettingsTabHotkeyTable._ResetList(center))

        SettingsTabHotkeyTable._LoadFromConfig()
        SettingsTabHotkeyTable._Redraw()
    }

    static _BuildEntries(freeRows) {
        arr := []
        for r in SettingsTabHotkeyTable.LOCKED_ROWS
            arr.Push({ type: "locked", key: r.key, label: r.label, domain: r.domain })
        for r in SettingsTabHotkeyTable.FIXED_ROWS {
            arr.Push({ type: "fixed", configKey: r.configKey, label: r.label
                , domain: r.domain, key: ConfigManager.Get(r.configKey, "")
                , note: r.note })
        }
        for s in freeRows {
            arr.Push({ type: "free"
                , key: SettingsTabHotkeyTable._Field(s, "key")
                , domain: SettingsTabHotkeyTable._Field(s, "domain")
                , action: SettingsTabHotkeyTable._Field(s, "action") })
        }
        return arr
    }

    static _LoadFromConfig() {
        SettingsTabHotkeyTable._Entries := SettingsTabHotkeyTable._BuildEntries(ConfigManager.Get("GlobalHotkeyRows", []))
    }

    static _Field(s, name) {
        return Utils.ObjGet(s, name)
    }

    static ReloadFromConfig() {
        SettingsTabHotkeyTable._LoadFromConfig()
        SettingsTabHotkeyTable._Redraw()
    }

    static _ActionLabel(actionId) {
        for r in Presentation.RESERVED {
            if (actionId = r.id)
                return { label: r.label, ok: true }
        }
        if (Actions.Get(actionId) != "")
            return { label: Presentation.ActionLabel(actionId), ok: true }
        return { label: actionId, ok: false }
    }

    static _ActionSource(actionId) {
        s := Actions.SplitId(actionId)
        if (s.ns = "word")
            return "词表"
        if (s.ns = "eng")
            return "引擎"
        if (s.ns = "plugin")
            return "插件"
        return "内置"
    }

    static _ActionCandidates(dom, selectId := "") {
        return Presentation.HotkeyDomainOptions(dom, selectId)
    }

    static _Redraw() {
        lv := SettingsTabHotkeyTable._List
        if (!IsObject(lv))
            return
        lv.Delete()
        for e in SettingsTabHotkeyTable._Entries {
            if (e.type = "fixed") {
                lv.Add("", HotkeyCapture.FormatHotkeyLabel(e.key), SettingsTabHotkeyTable._DomLabel(e.domain), "内置", e.label (e.key = "" ? "（未设置）" : ""))
            } else if (e.type = "free") {
                r := SettingsTabHotkeyTable._ActionLabel(e.action)
                lbl := r.ok ? r.label : "🚫 " r.label
                lv.Add("", HotkeyCapture.FormatHotkeyLabel(e.key), SettingsTabHotkeyTable._DomLabel(e.domain), SettingsTabHotkeyTable._ActionSource(e.action), lbl)
            } else {
                lv.Add("", HotkeyCapture.FormatHotkeyLabel(e.key), SettingsTabHotkeyTable._DomLabel(e.domain) " 🔒", "内置", e.label)
            }
        }
        lv.ModifyCol(1, 130), lv.ModifyCol(2, 85), lv.ModifyCol(3, 55), lv.ModifyCol(4, 310)
    }

    static _EditEntry(center, row := 0) {
        e := (row > 0 && row <= SettingsTabHotkeyTable._Entries.Length)
            ? SettingsTabHotkeyTable._Entries[row] : ""
        if (e = "")
            return
        if (e.type = "fixed")
            SettingsTabHotkeyTable._EditFixed(center, e)
        else if (e.type = "free")
            SettingsTabHotkeyTable._EditFree(center, e, false)
        else
            SettingsTabHotkeyTable._ViewLocked(center, e)
    }

    static _EditFixed(center, e) {
        g := Gui("+Owner" center.SettingsGui.Hwnd " -MinimizeBox +AlwaysOnTop", e.label)
        g.SetFont("s9", "Microsoft YaHei")
        g.Add("Text", "x15 y18 w60", "快捷键:")
        btn := g.Add("Button", "x85 y14 w160 h26", HotkeyCapture.FormatHotkeyLabel(e.key))
        g.Add("Text", "x255 y18 w150", "（点击录制）")
        g.Add("Text", "x15 y56 w60", "动作:")
        g.Add("Text", "x85 y56 w240 c" Theme.COLOR_TEXT, e.label)
        tip := Utils.AddWrapText(g, "x15 y84 w360 c" Theme.COLOR_HINT
            , e.note "；录制：按修饰键组合（智慧语音支持裸键如 右Ctrl）；Esc 取消，Backspace/Delete 清除")
        tip.GetPos(, , &tw, &th)
        msgY := 84 + th + 6
        msg := g.Add("Text", "x15 y" msgY " w360 h18 c" Theme.COLOR_ERR, "")
        btnY := msgY + 26
        okBtn := g.Add("Button", "x85 y" btnY " w80 h26 Default", "保存")
        cancelBtn := g.Add("Button", "x175 y" btnY " w80 h26", "取消")
        g.Show("w400 h" (btnY + 36))

        configKey := e.configKey
        btn.OnEvent("Click", (*) => center.capture.StartHotkeyCapture(configKey, btn, "global", "global", msg))
        okBtn.OnEvent("Click", (*) => (
            center.capture.CancelCapture(),
            ConfigManager.Set(configKey, center.capture.HkValues.Has(configKey) ? center.capture.HkValues[configKey] : e.key),
            g.Destroy(),
            SettingsTabHotkeyTable._LoadFromConfig(),
            SettingsTabHotkeyTable._Redraw()))
        cancelBtn.OnEvent("Click", (*) => (center.capture.CancelCapture(), g.Destroy(),
            SettingsTabHotkeyTable._LoadFromConfig(), SettingsTabHotkeyTable._Redraw()))
        g.OnEvent("Escape", (*) => (center.capture.CancelCapture(), g.Destroy(),
            SettingsTabHotkeyTable._LoadFromConfig(), SettingsTabHotkeyTable._Redraw()))
        g.OnEvent("Close", (*) => (center.capture.CancelCapture(), g.Destroy(),
            SettingsTabHotkeyTable._LoadFromConfig(), SettingsTabHotkeyTable._Redraw()))
    }

    static _EditFree(center, e, isNew) {
        origKey := isNew ? "" : e.key
        origDomain := isNew ? "clip" : e.domain
        origAction := isNew ? "" : e.action

        g := Gui("+Owner" center.SettingsGui.Hwnd " -MinimizeBox +AlwaysOnTop", isNew ? "添加快捷键" : "编辑快捷键")
        g.SetFont("s9", "Microsoft YaHei")
        g.Add("Text", "x15 y18 w60", "快捷键:")
        btn := g.Add("Button", "x85 y14 w160 h26", HotkeyCapture.FormatHotkeyLabel(origKey))
        g.Add("Text", "x255 y18 w150", "（点击录制）")
        g.Add("Text", "x15 y56 w60", "消费域:")
        domLabels := []
        for k in SettingsTabHotkeyTable.DOMAIN_KEYS
            domLabels.Push(SettingsTabHotkeyTable._DomLabel(k))
        domDdl := g.Add("DropDownList", "x85 y52 w150", domLabels)
        g.Add("Text", "x15 y94 w60", "动作:")
        actDdl := g.Add("DropDownList", "x85 y90 w300", ["（先选域）"])
        tipText := "剪贴板 = 读现成剪贴板交动作；选中 = 先取当前选中文本再交动作；全局 = 不取内容、直接触发；应用框内 = 仅输入框激活时生效（Enter 系组合键）"
        tip := Utils.AddWrapText(g, "x15 y126 w360 c" Theme.COLOR_HINT, tipText)
        tip.GetPos(, , &tw, &th)
        msgY := 126 + th + 6
        msg := g.Add("Text", "x15 y" msgY " w360 h18 c" Theme.COLOR_ERR, "")
        btnY := msgY + 26
        okBtn := g.Add("Button", "x85 y" btnY " w80 h26 Default", isNew ? "添加" : "保存")
        cancelBtn := g.Add("Button", "x175 y" btnY " w80 h26", "取消")
        delBtn := ""
        if (!isNew)
            delBtn := g.Add("Button", "x265 y" btnY " w80 h26", "删除")
        g.Show("w400 h" (btnY + 36))
        btn.Focus()

        captureKey := "__hotkeyTable"
        curKey := origKey
        center.capture.HkValues[captureKey] := origKey

        domDdl.Choose(SettingsTabHotkeyTable._DomIndex(origDomain))
        RefillActs(origDomain, origAction)

        btn.OnEvent("Click", (*) => center.capture.StartHotkeyCapture(captureKey, btn
            , SettingsTabHotkeyTable._CaptureMode(SettingsTabHotkeyTable._LabelToDom(domDdl.Text)), "global", msg))
        domDdl.OnEvent("Change", (*) => RefillActs(SettingsTabHotkeyTable._LabelToDom(domDdl.Text), ""))
        okBtn.OnEvent("Click", (*) => DoCommit())
        CloseDlg() {
            center.capture.CancelCapture()
            center.capture.HkValues.Delete(captureKey)
            g.Destroy()
        }
        cancelBtn.OnEvent("Click", (*) => CloseDlg())
        g.OnEvent("Escape", (*) => CloseDlg())
        g.OnEvent("Close", (*) => CloseDlg())
        if (IsObject(delBtn))
            delBtn.OnEvent("Click", (*) => ConfirmDelete())

        ConfirmDelete() {
            domLbl := SettingsTabHotkeyTable._DomLabel(origDomain)
            if (center.host.TopMsgBox("确定删除该快捷键？`n`n" HotkeyCapture.FormatHotkeyLabel(origKey)
                "（" domLbl "域）删除后点「保存并应用」生效。", "删除快捷键", 0x4 + 0x30) = "Yes") {
                SettingsTabHotkeyTable._RemoveFree(origKey, origDomain)
                CloseDlg()
                SettingsTabHotkeyTable._Redraw()
            }
        }

        RefillActs(dom, selectId) {
            arr := SettingsTabHotkeyTable._ActionCandidates(dom, selectId)
            labels := []
            for c in arr
                labels.Push(c.label)
            if (labels.Length = 0)
                labels.Push("（无候选）")
            actDdl.Delete()
            actDdl.Add(labels)
            if (selectId != "") {
                for i, c in arr {
                    if (c.id = selectId) {
                        actDdl.Choose(i)
                        return
                    }
                }
            }
            actDdl.Choose(1)
        }

        DoCommit() {
            hk := center.capture.HkValues.Has(captureKey) ? center.capture.HkValues[captureKey] : curKey
            if (hk = "") {
                NotifyCenter.Send("warning", "快捷键", "请先录制快捷键")
                return
            }
            dom := SettingsTabHotkeyTable._LabelToDom(domDdl.Text)
            if (!HotkeyCapture.IsAllowedHotkey(hk, SettingsTabHotkeyTable._CaptureMode(dom))) {
                NotifyCenter.Send("warning", "快捷键", "该键形不适用于「" domDdl.Text "」域（应用框内=带修饰符的 Enter 系；剪贴板/全局=带修饰符组合）")
                return
            }
            for x in SettingsTabHotkeyTable._Entries {
                xk := (x.type = "fixed") ? ConfigManager.Get(x.configKey, "") : x.key
                if (x.type = "locked" || xk = "" || xk != hk)
                    continue
                if (isNew || !(x.type = "free" && x.key = origKey && x.domain = origDomain)) {
                    NotifyCenter.Send("warning", "快捷键", "快捷键已存在：" HotkeyCapture.FormatHotkeyLabel(hk))
                    return
                }
            }
            sel := actDdl.Value
            arr := SettingsTabHotkeyTable._ActionCandidates(dom)
            if (sel < 1 || sel > arr.Length) {
                NotifyCenter.Send("warning", "快捷键", "请选择动作")
                return
            }
            newAction := arr[sel].id
            if (!isNew)
                SettingsTabHotkeyTable._RemoveFree(origKey, origDomain)
            SettingsTabHotkeyTable._Entries.Push({ type: "free", key: hk, domain: dom, action: newAction })
            CloseDlg()
            SettingsTabHotkeyTable._Redraw()
        }
    }

    static _ViewLocked(center, e) {
        g := Gui("+Owner" center.SettingsGui.Hwnd " -MinimizeBox +AlwaysOnTop", "只读快捷键")
        g.SetFont("s9", "Microsoft YaHei")
        g.Add("Text", "x15 y18 w60", "快捷键:")
        g.Add("Text", "x85 y18 w240", HotkeyCapture.FormatHotkeyLabel(e.key) " 🔒")
        g.Add("Text", "x15 y56 w60", "动作:")
        g.Add("Text", "x85 y56 w240", e.label)
        Utils.AddWrapText(g, "x15 y84 w360 c" Theme.COLOR_HINT, "窗口操作/安全阀键位由产品定义，只展示不可配置")
        okBtn := g.Add("Button", "x85 y128 w80 h26 Default", "关闭")
        okBtn.OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        g.OnEvent("Close", (*) => g.Destroy())
        g.Show("w400 h170")
    }

    static _RemoveFree(key, domain) {
        out := []
        removed := false
        for e in SettingsTabHotkeyTable._Entries {
            if (!removed && e.type = "free" && e.key = key && e.domain = domain) {
                removed := true
                continue
            }
            out.Push(e)
        }
        SettingsTabHotkeyTable._Entries := out
    }

    static _AddEntry(center) {
        SettingsTabHotkeyTable._EditFree(center, "", true)
    }

    static _ResetList(center) {
        msg := "恢复默认将清除你自定义的全部快捷键自由行（剪贴板 / 选中 / 应用框内 / 全局四域）。`n`n固定行与展示行不受影响。确定恢复？"
        if (center.host.TopMsgBox(msg, "恢复默认", 0x4 + 0x30) != "Yes")
            return
        for r in SettingsTabHotkeyTable.FIXED_ROWS {
            def := ""
            for k, v in ConfigManager.GetDefaults() {
                if (k = r.configKey) {
                    def := v
                    break
                }
            }
            ConfigManager.Set(r.configKey, def)
        }
        SettingsTabHotkeyTable._Entries := SettingsTabHotkeyTable._BuildEntries(ConfigManager.GetDefaultHotkeyRows())
        SettingsTabHotkeyTable._Redraw()
    }

    static ApplySlotDefaults() {
        out := []
        for e in SettingsTabHotkeyTable._Entries {
            if (e.type = "free" && e.domain = "input")
                continue
            out.Push(e)
        }
        for s in ConfigManager.GetDefaultInputKeySlots()
            out.Push({ type: "free", key: s.key, domain: "input", action: s.action })
        SettingsTabHotkeyTable._Entries := out
        SettingsTabHotkeyTable._Redraw()
    }

    static GetEntriesForSave() {
        out := []
        for e in SettingsTabHotkeyTable._Entries {
            if (e.type = "free")
                out.Push({ key: e.key, domain: e.domain, action: e.action })
        }
        return out
    }
}
