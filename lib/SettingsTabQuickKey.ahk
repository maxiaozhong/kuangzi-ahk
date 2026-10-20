#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "Theme.ahk"
#Include "ConfigManager.ahk"
#Include "NotifyCenter.ahk"
#Include "Actions.ahk"
#Include "Presentation.ahk"

class SettingsTabQuickKey {
    static _Entries := []
    static _List := ""

    static Build(SG, Tabs, i, center) {
        C := center.Ctrls
        Tabs.UseTab(i)
        yPos := Theme.SET_PAGE_Y
        SG.Add("GroupBox", "x" Theme.SET_PAGE_X " y" yPos " w" Theme.SET_PAGE_W " h" Theme.SET_PAGE_H, "一键直达 (CapsLock+1~2 个字母)")
        yPos += 28

        LV_H := Theme.SetListBottom() - yPos
        lv := SG.Add("ListView", "x" Theme.SET_LIST_X " y" yPos " w" Theme.SET_LIST_W " h" LV_H " -Multi NoSortHdr Grid", ["快捷键", "来源", "动作"])
        lv.ModifyCol(1, 90), lv.ModifyCol(2, 150), lv.ModifyCol(3, 330)
        lv.OnEvent("DoubleClick", (lvObj, row) => SettingsTabQuickKey._EditEntry(center, row))
        SettingsTabQuickKey._List := lv

        BTN_Y := Theme.SetBtnY()
        SG.Add("Button", "x" Theme.SetBtnX(0) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "添加...").OnEvent("Click", (*) => SettingsTabQuickKey._AddEntry(center))
        SG.Add("Button", "x" Theme.SetBtnX(1) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "恢复默认").OnEvent("Click", (*) => SettingsTabQuickKey._ResetList(center))

        SettingsTabQuickKey._LoadFromConfig()
        SettingsTabQuickKey._Redraw()
    }

    static _LoadFromConfig() {
        arr := []
        for s in ConfigManager.Get("CapsLockActions", [])
            arr.Push({ key: SettingsTabQuickKey._Field(s, "key")
                , action: SettingsTabQuickKey._Field(s, "action")
                , locked: SettingsTabQuickKey._Field(s, "locked") })
        SettingsTabQuickKey._Entries := arr
    }

    static _Field(s, name) {
        return Utils.ObjGet(s, name)
    }

    static _KeyLabel(k) {
        static NAMES := Map("space", "Space", ".", ".", "/", "/", "``", "·", ",", ",")
        return NAMES.Has(k) ? NAMES[k] : k
    }

    static ReloadFromConfig() {
        SettingsTabQuickKey._LoadFromConfig()
        SettingsTabQuickKey._Redraw()
    }

    static _Resolve(actionId) {
        s := Actions.SplitId(actionId)
        a := Actions.Get(actionId)
        if (a != "") {
            src := "内置动作"
            if (a.HasOwnProp("plugin") && a.plugin) {
                plug := PluginManager.PluginsById.Has(s.owner) ? PluginManager.PluginsById[s.owner] : ""
                src := plug != "" ? plug.name : "插件"
            } else if (s.ns = "word")
                src := "快捷启动"
            else if (s.ns = "eng")
                src := "快捷搜索"
            return { source: src, label: Presentation.ActionLabel(actionId), ok: true }
        }
        if (s.ns = "word" && ConfigManager.WordMap.Has(s.name))
            return { source: "快捷启动", label: Presentation.ActionLabel(actionId), ok: true }
        if (s.ns = "eng" && ConfigManager.EngineMap.Has(s.name))
            return { source: "快捷搜索", label: Presentation.ActionLabel(actionId), ok: true }
        return { source: "未知", label: actionId, ok: false }
    }

    static _Redraw() {
        lv := SettingsTabQuickKey._List
        if (!IsObject(lv))
            return
        lv.Delete()
        for e in SettingsTabQuickKey._Entries {
            r := SettingsTabQuickKey._Resolve(e.action)
            lbl := r.ok ? r.label : "🚫 " r.label
            src := e.locked ? r.source " 🔒" : r.source
            lv.Add("", SettingsTabQuickKey._KeyLabel(e.key), src, lbl)
        }
        lv.ModifyCol(1, 90), lv.ModifyCol(2, 150), lv.ModifyCol(3, 330)
    }

    static _Candidates() {
        groups := Map()
        groups["内置动作"] := []
        groups["快捷启动"] := []
        groups["快捷搜索"] := []
        for a in Actions.All() {
            if (a.kind = "entry" || a.HasOwnProp("plugin"))
                continue
            ns := Actions.SplitId(a.id).ns
            if (ns = "word" || ns = "eng")
                continue
            if (Presentation.CanConsume(a.id, Presentation.QuickKey))
                groups["内置动作"].Push({ label: Presentation.ActionLabel(a.id), id: a.id })
        }
        for word, e in ConfigManager.WordMap {
            if (Presentation.CanConsume("word." word, Presentation.QuickKey))
                groups["快捷启动"].Push({ label: Presentation.ActionLabel("word." word), id: "word." word })
        }
        for word, e in ConfigManager.EngineMap {
            if (Presentation.CanConsume("eng." word, Presentation.QuickKey))
                groups["快捷搜索"].Push({ label: Presentation.ActionLabel("eng." word), id: "eng." word })
        }
        for a in Actions.PLUGINS() {
            if (!Presentation.CanConsume(a.id, Presentation.QuickKey))
                continue
            s := Actions.SplitId(a.id)
            plug := PluginManager.PluginsById.Has(s.owner) ? PluginManager.PluginsById[s.owner] : ""
            gname := "插件 · " (plug != "" ? plug.name : s.owner)
            if (!groups.Has(gname))
                groups[gname] := []
            groups[gname].Push({ label: Presentation.ActionLabel(a.id), id: a.id })
        }
        return groups
    }

    static _EditEntry(center, row := 0) {
        origKey := "", origAction := ""
        isLocked := false
        if (row > 0) {
            dispKey := SettingsTabQuickKey._List.GetText(row, 1)
            for e in SettingsTabQuickKey._Entries {
                if (SettingsTabQuickKey._KeyLabel(e.key) = dispKey) {
                    origKey := e.key
                    origAction := e.action
                    isLocked := !!e.locked
                    break
                }
            }
        }

        groups := SettingsTabQuickKey._Candidates()
        srcOrder := ["内置动作", "快捷启动", "快捷搜索"]
        srcLabels := []
        for s in srcOrder {
            if (groups.Has(s) && groups[s].Length > 0)
                srcLabels.Push(s)
        }
        for g, arr in groups {
            if (InStr(g, "插件 · ") = 1 && arr.Length > 0)
                srcLabels.Push(g)
        }

        g := Gui("+Owner" center.SettingsGui.Hwnd " -MinimizeBox +AlwaysOnTop", row > 0 ? (isLocked ? "出厂键位（只读）" : "编辑一键直达") : "添加一键直达")
        g.SetFont("s9", "Microsoft YaHei")
        g.Add("Text", "x15 y15 w60", "快捷键:")
        keyEdit := g.Add("Edit", "x85 y12 w120 " (isLocked ? "ReadOnly" : ""), origKey)
        g.Add("Text", "x215 y15 w60", isLocked ? "🔒 出厂" : "1~2 字母")
        g.Add("Text", "x15 y50 w60", "来源:")
        srcDdl := g.Add("DropDownList", "x85 y47 w150 " (isLocked ? "Disabled" : ""), srcLabels)
        g.Add("Text", "x15 y88 w60", "动作:")
        actDdl := g.Add("DropDownList", "x85 y85 w300 " (isLocked ? "Disabled" : ""), ["（先选来源）"])
        tipText := isLocked
            ? "出厂键位由产品定义，不可修改（改 GetDefaultCapsLockActions 调整）"
            : "快捷键 1~2 个字母（双字母：先按第一个，0.4 秒内按第二个）；来源→动作 两级选择"
        tip := Utils.AddWrapText(g, "x15 y120 w380 c" Theme.COLOR_HINT, tipText)
        tip.GetPos(, , &tw, &th)
        btnY := 120 + th + 8
        okBtn := g.Add("Button", "x85 y" btnY " w80 h26 Default", isLocked ? "关闭" : (row > 0 ? "保存" : "添加"))
        cancelBtn := g.Add("Button", "x175 y" btnY " w80 h26", "取消")
        delBtn := ""
        if (row > 0 && !isLocked)
            delBtn := g.Add("Button", "x265 y" btnY " w80 h26", "删除")
        g.Show("w400 h" (btnY + 36))
        keyEdit.Focus()

        if (isLocked) {
            curGroup := ""
            for gn, arr in groups {
                for c in arr {
                    if (c.id = origAction)
                        curGroup := gn
                }
            }
            if (curGroup != "") {
                for i, sl in srcLabels {
                    if (sl = curGroup)
                        srcDdl.Choose(i)
                }
                arr := groups[curGroup]
                labels := []
                for c in arr
                    labels.Push(c.label)
                actDdl.Delete(), actDdl.Add(labels)
                for i, c in arr {
                    if (c.id = origAction)
                        actDdl.Choose(i)
                }
            }
            okBtn.OnEvent("Click", (*) => g.Destroy())
            cancelBtn.OnEvent("Click", (*) => g.Destroy())
            g.OnEvent("Escape", (*) => g.Destroy())
            g.OnEvent("Close", (*) => g.Destroy())
            return
        }

        curGroup := ""
        if (origAction != "") {
            for gn, arr in groups {
                for c in arr {
                    if (c.id = origAction)
                        curGroup := gn
                }
            }
        }
        if (curGroup != "" && srcLabels.Length > 0) {
            srcDdl.Choose(curGroup)
            RefillActs(curGroup, origAction)
        } else if (srcLabels.Length > 0) {
            srcDdl.Choose(1)
            RefillActs(srcLabels[1], "")
        }

        srcDdl.OnEvent("Change", (*) => RefillActs(srcDdl.Text, ""))
        okBtn.OnEvent("Click", (*) => DoCommit())
        cancelBtn.OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        g.OnEvent("Close", (*) => g.Destroy())
        if (IsObject(delBtn))
            delBtn.OnEvent("Click", (*) => (SettingsTabQuickKey._RemoveAt(origKey), g.Destroy(), SettingsTabQuickKey._Redraw()))

        RefillActs(groupName, selectId) {
            arr := groups.Has(groupName) ? groups[groupName] : []
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
            newKey := StrLower(Trim(keyEdit.Value))
            if (!RegExMatch(newKey, "^[a-z]{1,2}$")) {
                NotifyCenter.Send("warning", "一键直达", "快捷键须为 1~2 个字母")
                return
            }
            if (newKey != origKey) {
                for e in SettingsTabQuickKey._Entries {
                    if (e.key = newKey) {
                        NotifyCenter.Send("warning", "一键直达", "快捷键已存在：" newKey)
                        return
                    }
                }
            }
            groupName := srcDdl.Text
            arr := groups.Has(groupName) ? groups[groupName] : []
            sel := actDdl.Value
            if (sel < 1 || sel > arr.Length) {
                NotifyCenter.Send("warning", "一键直达", "请选择动作")
                return
            }
            newAction := arr[sel].id
            SettingsTabQuickKey._RemoveAt(origKey)
            SettingsTabQuickKey._Entries.Push({ key: newKey, action: newAction, locked: false })
            g.Destroy()
            SettingsTabQuickKey._Redraw()
        }
    }

    static _RemoveAt(key) {
        if (key = "")
            return
        out := []
        for e in SettingsTabQuickKey._Entries {
            if (e.key != key)
                out.Push(e)
        }
        SettingsTabQuickKey._Entries := out
    }

    static _AddEntry(center) {
        SettingsTabQuickKey._EditEntry(center, 0)
    }

    static _ResetList(center) {
        msg := "恢复默认将清除你自定义的全部一键直达键位。`n`n列表会重置为出厂键位，点「保存并应用」后不可恢复。确定恢复？"
        if (center.host.TopMsgBox(msg, "恢复默认", 0x4 + 0x30) != "Yes")
            return
        arr := []
        for s in ConfigManager.GetDefaultCapsLockActions()
            arr.Push({ key: SettingsTabQuickKey._Field(s, "key")
                , action: SettingsTabQuickKey._Field(s, "action")
                , locked: SettingsTabQuickKey._Field(s, "locked") })
        SettingsTabQuickKey._Entries := arr
        SettingsTabQuickKey._Redraw()
    }

    static GetEntriesForSave() {
        return SettingsTabQuickKey._Entries
    }
}
