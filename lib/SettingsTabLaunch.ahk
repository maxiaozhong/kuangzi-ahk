#Requires AutoHotkey v2.0
#Include "JSON.ahk"
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "Theme.ahk"
#Include "NotifyCenter.ahk"
#Include "SettingsListPage.ahk"

class SettingsTabLaunch extends SettingsListPage {
    static _Entries := Map()
    static _List := ""

    static ConfigKey := "WordTable"
    static Columns := [["关键词", 160], ["描述", 400]]

    static Build(SG, Tabs, i, center) {
        C := center.Ctrls

        Tabs.UseTab(i)
        yPos := Theme.SET_PAGE_Y
        SG.Add("GroupBox", "x" Theme.SET_PAGE_X " y" yPos " w" Theme.SET_PAGE_W " h" Theme.SET_PAGE_H, "快捷启动")
        yPos += 28
        SG.Add("Text", "x" Theme.SET_LIST_X " y" yPos " w200", "触发前缀字符 (如 @，不要为空):")
        C["AppPrefix"] := SG.Add("Edit", "x" (Theme.SET_LIST_X + 210) " y" yPos - 3 " w100 vAppPrefix", ConfigManager.Get("AppPrefix"))
        yPos += 34

        LV_H := Theme.SetListBottom() - yPos
        lv := SG.Add("ListView", "x" Theme.SET_LIST_X " y" yPos " w" Theme.SET_LIST_W " h" LV_H " -Multi NoSortHdr Grid", ["关键词", "描述"])
        lv.ModifyCol(1, 160), lv.ModifyCol(2, 400)
        lv.OnEvent("DoubleClick", (lvObj, row) => SettingsTabLaunch._EditEntry(center, row))
        SettingsTabLaunch._List := lv

        BTN_Y := Theme.SetBtnY()
        SG.Add("Button", "x" Theme.SetBtnX(0) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "添加...").OnEvent("Click", (*) => SettingsTabLaunch._AddEntry(center))
        SG.Add("Button", "x" Theme.SetBtnX(1) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "恢复默认").OnEvent("Click", (*) => SettingsTabLaunch._ResetList(center))

        SettingsTabLaunch._LoadFromConfig()
        SettingsTabLaunch._Redraw()
    }

    static _DescOf(v) {
        if (Type(v) != "Map" && Type(v) != "Object")
            return v
        d := Utils.ObjGet(v, "desc")
        return (d != "") ? d : SettingsTabLaunch._RunTargetOf(v)
    }

    static _RunTargetOf(v) {
        if (Utils.ObjGet(v, "type", "run") != "run")
            return ""
        return Utils.ObjGet(v, "target")
    }

    static RowValues(k, v) {
        d := SettingsTabLaunch._DescOf(v)
        return [k, d = "" ? "—" : d]
    }

    static _EditEntry(center, row := 0) {
        lv := SettingsTabLaunch._List
        origKey := "", origVal := ""
        if (row > 0) {
            origKey := lv.GetText(row, 1)
            if (SettingsTabLaunch._Entries.Has(origKey))
                origVal := SettingsTabLaunch._Entries[origKey]
            else
                return
        }

        g := Gui("+Owner" center.SettingsGui.Hwnd " -MinimizeBox +AlwaysOnTop", row > 0 ? "编辑词表" : "添加词表")
        g.SetFont("s9", "Microsoft YaHei")
        g.Add("Text", "x15 y15 w60", "关键词:")
        kw := g.Add("Edit", "x85 y12 w300", origKey)
        g.Add("Text", "x15 y50 w60", "写法:")
        styleDdl := g.Add("DropDownList", "x85 y47 w100", ["语法糖", "完整值"])
        isSugar := (Type(origVal) = "String")
        styleDdl.Choose(isSugar || origVal = "" ? 1 : 2)
        g.Add("Text", "x15 y85 w60", "值:")
        val := g.Add("Edit", "x85 y82 w300 h110 Multi", SettingsTabLaunch._ValToText(origVal))
        tip := Utils.AddWrapText(g, "x15 y200 w370 c" Theme.COLOR_HINT, '语法糖=纯目标（URL/路径/exe）；完整值={"type":"run|action|search","target":…,"desc":"列表描述"}；切换写法自动互转')
        tip.GetPos(, , &tw, &th)

        btnY := 200 + th + 8
        okBtn := g.Add("Button", "x85 y" btnY " w80 h26 Default", row > 0 ? "保存" : "添加")
        cancelBtn := g.Add("Button", "x175 y" btnY " w80 h26", "取消")
        delBtn := ""
        if (row > 0)
            delBtn := g.Add("Button", "x265 y" btnY " w80 h26", "删除")
        g.Show("w400 h" (btnY + 36))
        kw.Focus()

        styleDdl.OnEvent("Change", (*) => SwitchStyle())
        okBtn.OnEvent("Click", (*) => DoCommit())
        cancelBtn.OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        g.OnEvent("Close", (*) => g.Destroy())
        if (IsObject(delBtn))
            delBtn.OnEvent("Click", (*) => (SettingsTabLaunch._Entries.Delete(origKey), g.Destroy(), SettingsTabLaunch._Redraw()))

        SwitchStyle() {
            text := Trim(val.Value)
            if (text = "")
                return
            if (styleDdl.Value = 1) {
                if (SubStr(text, 1, 1) = "{") {
                    try
                        parsed := JSON.parse(text)
                    catch
                        return
                    if (Type(parsed) = "Map" && parsed.Has("type") && parsed["type"] = "run" && parsed.Has("target")) {
                        val.Value := parsed["target"]
                        return
                    }
                    NotifyCenter.Send("info", "写法切换", "action/search 型没有语法糖形态，保持完整值")
                    styleDdl.Choose(2)
                }
            } else {
                if (SubStr(text, 1, 1) != "{")
                    val.Value := '{"type":"run","target":' SettingsTabLaunch._Quote(text) '}'
            }
        }

        DoCommit() {
            newKey := Trim(kw.Value)
            if (newKey = "") {
                NotifyCenter.Send("warning", "词表", "关键词不能为空")
                return
            }
            if (newKey != origKey && SettingsTabLaunch._Entries.Has(newKey)) {
                NotifyCenter.Send("warning", "词表", "关键词已存在：" newKey)
                return
            }
            valText := Trim(val.Value)
            if (valText = "") {
                NotifyCenter.Send("warning", "词表", "值不能为空")
                return
            }
            newVal := ""
            if (SubStr(valText, 1, 1) = "{") {
                try
                    parsed := JSON.parse(valText)
                catch as e {
                    NotifyCenter.Send("warning", "词表", "值不是合法 JSON：" e.Message)
                    return
                }
                if (Type(parsed) != "Map" || !parsed.Has("target")) {
                    NotifyCenter.Send("warning", "词表", "值缺 target 字段")
                    return
                }
                if (parsed.Has("type") && parsed["type"] = "search" && !InStr(parsed["target"], "%s")) {
                    NotifyCenter.Send("warning", "词表", "search 型 target 必含 %s（搜索词占位）")
                    return
                }
                if (ConfigManager._NormEntry(parsed) = "") {
                    NotifyCenter.Send("warning", "词表", "值不合法（type/target 校验未过）")
                    return
                }
                newVal := parsed
            } else {
                newVal := valText
            }

            if (origKey != "")
                SettingsTabLaunch._Entries.Delete(origKey)
            SettingsTabLaunch._Entries[newKey] := newVal
            g.Destroy()
            SettingsTabLaunch._Redraw()
        }
    }

    static _AddEntry(center) {
        SettingsTabLaunch._EditEntry(center, 0)
    }

    static _ValToText(v) {
        if (Type(v) = "Map" || Type(v) = "Object")
            return SettingsTabLaunch._ObjToJson(v)
        return (v = "") ? 'https://…（纯目标=语法糖）' : v
    }

    static _ObjToJson(o) {
        return JSON.stringify(o, 0, "")
    }

    static _Quote(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`t", "\t")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`n", "\n")
        return '"' s '"'
    }

    static _ResetList(center) {
        msg := "恢复默认将清除你自定义的全部快捷启动词条。`n`n列表会重置为出厂词表，点「保存并应用」后不可恢复。确定恢复？"
        if (center.host.TopMsgBox(msg, "恢复默认", 0x4 + 0x30) != "Yes")
            return
        m := Map()
        for k, v in ConfigManager.GetDefaultWordTable()
            m[k] := v
        SettingsTabLaunch._Entries := m
        SettingsTabLaunch._Redraw()
    }

}
