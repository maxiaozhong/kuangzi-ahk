#Requires AutoHotkey v2.0
#Include "JSON.ahk"
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "Theme.ahk"
#Include "NotifyCenter.ahk"
#Include "SettingsListPage.ahk"

class SettingsTabSearch extends SettingsListPage {
    static _Entries := Map()
    static _List := ""

    static ConfigKey := "SearchEngines"
    static Columns := [["关键词", 160], ["描述", 400]]

    static Build(SG, Tabs, i, center) {
        C := center.Ctrls

        Tabs.UseTab(i)
        yPos := Theme.SET_PAGE_Y
        SG.Add("GroupBox", "x" Theme.SET_PAGE_X " y" yPos " w" Theme.SET_PAGE_W " h" Theme.SET_PAGE_H, "快捷搜索")
        yPos += 28
        SG.Add("Text", "x" Theme.SET_LIST_X " y" yPos " w200", "触发前缀字符 (如 /，不要为空):")
        C["SearchPrefix"] := SG.Add("Edit", "x" (Theme.SET_LIST_X + 210) " y" yPos - 3 " w100 vSearchPrefix", ConfigManager.Get("SearchPrefix"))
        yPos += 34

        LV_H := Theme.SetListBottom() - yPos
        lv := SG.Add("ListView", "x" Theme.SET_LIST_X " y" yPos " w" Theme.SET_LIST_W " h" LV_H " -Multi NoSortHdr Grid", ["关键词", "描述"])
        lv.ModifyCol(1, 160), lv.ModifyCol(2, 400)
        lv.OnEvent("DoubleClick", (lvObj, row) => SettingsTabSearch._EditEntry(center, row))
        SettingsTabSearch._List := lv

        BTN_Y := Theme.SetBtnY()
        SG.Add("Button", "x" Theme.SetBtnX(0) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "添加...").OnEvent("Click", (*) => SettingsTabSearch._AddEntry(center))
        SG.Add("Button", "x" Theme.SetBtnX(1) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "恢复默认").OnEvent("Click", (*) => SettingsTabSearch._ResetList(center))

        SettingsTabSearch._LoadFromConfig()
        SettingsTabSearch._Redraw()
    }

    static _DescOf(v) {
        if (Type(v) != "Map" && Type(v) != "Object")
            return v
        d := Utils.ObjGet(v, "desc")
        return (d != "") ? d : Utils.ObjGet(v, "target")
    }

    static RowValues(k, v) {
        d := SettingsTabSearch._DescOf(v)
        return [k, d = "" ? "—" : d]
    }

    static _EditEntry(center, row := 0) {
        lv := SettingsTabSearch._List
        origKey := "", origVal := ""
        if (row > 0) {
            origKey := lv.GetText(row, 1)
            if (SettingsTabSearch._Entries.Has(origKey))
                origVal := SettingsTabSearch._Entries[origKey]
            else
                return
        }

        g := Gui("+Owner" center.SettingsGui.Hwnd " -MinimizeBox +AlwaysOnTop", row > 0 ? "编辑搜索引擎" : "添加搜索引擎")
        g.SetFont("s9", "Microsoft YaHei")
        g.Add("Text", "x15 y15 w60", "关键词:")
        kw := g.Add("Edit", "x85 y12 w300", origKey)
        g.Add("Text", "x15 y50 w60", "值:")
        val := g.Add("Edit", "x85 y47 w300 h110 Multi", SettingsTabSearch._ValToText(origVal))
        tip := Utils.AddWrapText(g, "x15 y165 w370 c" Theme.COLOR_HINT, '完整写法 {"type":"search","target":"URL 含 %s","home":"首页","desc":"列表描述"}；纯 URL=run 糖')
        tip.GetPos(, , &tw, &th)

        btnY := 165 + th + 8
        okBtn := g.Add("Button", "x85 y" btnY " w80 h26 Default", row > 0 ? "保存" : "添加")
        cancelBtn := g.Add("Button", "x175 y" btnY " w80 h26", "取消")
        delBtn := ""
        if (row > 0)
            delBtn := g.Add("Button", "x265 y" btnY " w80 h26", "删除")
        g.Show("w400 h" (btnY + 36))
        kw.Focus()

        okBtn.OnEvent("Click", (*) => DoCommit())
        cancelBtn.OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        g.OnEvent("Close", (*) => g.Destroy())
        if (IsObject(delBtn))
            delBtn.OnEvent("Click", (*) => (SettingsTabSearch._Entries.Delete(origKey), g.Destroy(), SettingsTabSearch._Redraw()))

        DoCommit() {
            newKey := Trim(kw.Value)
            if (newKey = "") {
                NotifyCenter.Send("warning", "快捷搜索", "关键词不能为空")
                return
            }
            if (newKey != origKey && SettingsTabSearch._Entries.Has(newKey)) {
                NotifyCenter.Send("warning", "快捷搜索", "关键词已存在：" newKey)
                return
            }
            valText := Trim(val.Value)
            if (valText = "") {
                NotifyCenter.Send("warning", "快捷搜索", "值不能为空")
                return
            }
            newVal := ""
            if (SubStr(valText, 1, 1) = "{") {
                try
                    parsed := JSON.parse(valText)
                catch as e {
                    NotifyCenter.Send("warning", "快捷搜索", "值不是合法 JSON：" e.Message)
                    return
                }
                if (Type(parsed) != "Map" || !parsed.Has("target")) {
                    NotifyCenter.Send("warning", "快捷搜索", "值缺 target 字段")
                    return
                }
                if (parsed.Has("type") && parsed["type"] = "search" && !InStr(parsed["target"], "%s")) {
                    NotifyCenter.Send("warning", "快捷搜索", "search 型 target 必含 %s（搜索词占位）")
                    return
                }
                normalized := ConfigManager._NormEntry(parsed)
                if (normalized = "") {
                    NotifyCenter.Send("warning", "快捷搜索", "值不合法（缺 target 或校验未过）")
                    return
                }
                newVal := parsed
            } else {
                newVal := valText
            }

            if (origKey != "")
                SettingsTabSearch._Entries.Delete(origKey)
            SettingsTabSearch._Entries[newKey] := newVal
            g.Destroy()
            SettingsTabSearch._Redraw()
        }
    }

    static _AddEntry(center) {
        SettingsTabSearch._EditEntry(center, 0)
    }

    static _ValToText(v) {
        if (Type(v) = "Map" || Type(v) = "Object")
            return SettingsTabSearch._ObjToJson(v)
        return (v = "") ? '{"type":"search","target":"https://…%s"}' : v
    }

    static _ObjToJson(o) {
        return JSON.stringify(o, 0, "")
    }

    static _ResetList(center) {
        msg := "恢复默认将清除你自定义的全部搜索引擎。`n`n列表会重置为出厂引擎表，点「保存并应用」后不可恢复。确定恢复？"
        if (center.host.TopMsgBox(msg, "恢复默认", 0x4 + 0x30) != "Yes")
            return
        m := Map()
        for k, v in ConfigManager.GetDefaultSearchEngines()
            m[k] := v
        SettingsTabSearch._Entries := m
        SettingsTabSearch._Redraw()
    }

}
