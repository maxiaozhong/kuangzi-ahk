#Requires AutoHotkey v2.0
#Include "NotifyCenter.ahk"
#Include "HotkeyCapture.ahk"
#Include "PathModel.ahk"
#Include "QuickNote.ahk"
#Include "JSON.ahk"
#Include "Actions.ahk"
#Include "CapsLockHotkeys.ahk"
#Include "Presentation.ahk"

#Include "SettingsTabNote.ahk"
#Include "SettingsTabLaunch.ahk"
#Include "SettingsTabSearch.ahk"
#Include "SettingsTabQuickKey.ahk"
#Include "SettingsTabVoice.ahk"
#Include "SettingsTabHotkeyTable.ahk"

class SettingsValidator {
    static Validate(ctrls, hkValues) {
        vaultPath := Trim(ctrls["VaultPath"].Value)
        searchPrefix := Trim(ctrls["SearchPrefix"].Value)
        dateFmt := ConfigManager.Get("DateFormat")
        timeFmt := ConfigManager.Get("TimeFormat")
        targetHeader := ConfigManager.Get("TargetHeader")
        todoHeader := ConfigManager.Get("TargetTodoHeader")

        if (vaultPath = "") {
            NotifyCenter.Send("warning", "设置错误", "笔记库目录不能为空")
            return false
        }

        if (dateFmt = "") {
            NotifyCenter.Send("warning", "设置错误", "日期格式不能为空")
            return false
        }
        try FormatTime(, dateFmt)
        catch {
            NotifyCenter.Send("warning", "设置错误", "日期格式无效：" dateFmt)
            return false
        }

        if (timeFmt = "") {
            NotifyCenter.Send("warning", "设置错误", "时间格式不能为空")
            return false
        }
        try FormatTime(, timeFmt)
        catch {
            NotifyCenter.Send("warning", "设置错误", "时间格式无效：" timeFmt)
            return false
        }

        period := ctrls.Has("NotePeriod") ? SettingsTabNote.LabelToPeriod(ctrls["NotePeriod"].Text) : ConfigManager.Get("NotePeriod", "day")
        if (period = "week") {
            weekFmt := ConfigManager.Get("WeekFormat")
            if !InStr(weekFmt, "{start}") {
                NotifyCenter.Send("warning", "设置错误", "周格式必须包含 {start}（如 {start}_week）")
                return false
            }
        } else if (period = "month") {
            monthFmt := ConfigManager.Get("MonthFormat")
            try FormatTime(, monthFmt)
            catch {
                NotifyCenter.Send("warning", "设置错误", "月格式无效：" monthFmt)
                return false
            }
        }

        if (period != "day") {
            try {
                fileName := PathModel.PeriodName(period, dateFmt
                    , ConfigManager.Get("WeekFormat"), ConfigManager.Get("MonthFormat"))
            } catch {
                fileName := ""
            }
            if (fileName = "" || RegExMatch(fileName, '[\\/:*?"<>|]')) {
                NotifyCenter.Send("warning", "设置错误", "当前周期格式生成的文件名无效：" (fileName = "" ? "（空）" : fileName) " | 不能含 \ / : * ? 感叹号引号及尖括号")
                return false
            }
        }

        if !RegExMatch(targetHeader, "^#{1,6}\s+.+") {
            NotifyCenter.Send("warning", "设置错误", "速记目标标题必须是 Markdown 标题，例如：## 框子速记")
            return false
        }

        if !RegExMatch(todoHeader, "^#{1,6}\s+.+") {
            NotifyCenter.Send("warning", "设置错误", "待办目标标题必须是 Markdown 标题，例如：## 框子待办")
            return false
        }

        if (searchPrefix = "") {
            NotifyCenter.Send("warning", "设置错误", "搜索触发前缀不能为空")
            return false
        }

        appPrefix := Trim(ctrls["AppPrefix"].Value)
        if (appPrefix = "") {
            NotifyCenter.Send("warning", "设置错误", "快捷启动前缀不能为空")
            return false
        }

        wordEntries := SettingsTabLaunch.GetEntriesForSave()
        for wk, wv in wordEntries {
            wt := (Type(wv) = "Map") ? (wv.Has("type") ? wv["type"] : "") : (Type(wv) = "Object" && wv.HasOwnProp("type") ? wv.type : "")
            if (wt = "action") {
                wtgt := (Type(wv) = "Map") ? (wv.Has("target") ? wv["target"] : "") : (wv.HasOwnProp("target") ? wv.target : "")
                a := Actions.Get(wtgt)
                if (a = "" || a.kind = "entry") {
                    NotifyCenter.Send("warning", "设置错误", "词表 action 型 target 无效：" wk)
                    return false
                }
            }
        }
        if (wordEntries.Count = 0) {
            NotifyCenter.Send("warning", "设置错误", "词表至少需要一条")
            return false
        }

        validEngineCount := 0
        engineKeys := Map()
        for ek, ev in SettingsTabSearch.GetEntriesForSave() {
            if (Type(ev) = "String") {
                if (!InStr(ev, "%s")) {
                    NotifyCenter.Send("warning", "设置错误", "引擎 URL 必须含 %s（搜索词占位）：" ek)
                    return false
                }
            } else if (Type(ev) = "Map" || Type(ev) = "Object") {
                tgt := (Type(ev) = "Map") ? (ev.Has("target") ? ev["target"] : "") : (ev.HasOwnProp("target") ? ev.target : "")
                if (tgt = "" || !InStr(tgt, "%s")) {
                    NotifyCenter.Send("warning", "设置错误", "引擎 target 必须含 %s（搜索词占位）：" ek)
                    return false
                }
            } else {
                NotifyCenter.Send("warning", "设置错误", "引擎值不合法：" ek)
                return false
            }
            Loop Parse, ek, "|" {
                key := Trim(A_LoopField)
                if (key != "")
                    engineKeys[key] := true
            }
            validEngineCount += 1
        }

        if (validEngineCount = 0) {
            NotifyCenter.Send("warning", "设置错误", "至少需要配置一个搜索引擎")
            return false
        }

        seenKeys := Map()
        for s in SettingsTabQuickKey.GetEntriesForSave() {
            letter := StrLower(Trim(s.key))
            isSymbol := CapsLockHotkeys.SYMBOL_KEYS.Has(letter)
            if (!isSymbol && !RegExMatch(letter, "^[a-z]{1,2}$")) {
                NotifyCenter.Send("warning", "设置错误", "一键直达快捷键无效：" letter " | 必须是 1~2 个字母 a-z")
                return false
            }
            if (seenKeys.Has(letter)) {
                NotifyCenter.Send("warning", "设置错误", "一键直达快捷键重复：" letter)
                return false
            }
            seenKeys[letter] := true
            if (s.locked)
                continue
            act := Actions.Get(s.action)
            if (act = "") {
                if (Actions.SplitId(s.action).ns = "plugin")
                    continue
                NotifyCenter.Send("warning", "设置错误", "一键直达动作不存在：" s.action)
                return false
            }
            if (act.kind = "entry") {
                NotifyCenter.Send("warning", "设置错误", "一键直达不能引用入口类动作：" s.action)
                return false
            }
        }

        for vk, ve in SettingsTabVoice.GetEntriesForSave() {
            actId := ve.HasOwnProp("target") ? ve.target : ""
            actParam := ve.HasOwnProp("param") ? ve.param : ""
            if (actId = "")
                continue
            act := Actions.Get(actId)
            if (act = "") {
                if (Actions.SplitId(actId).ns = "plugin")
                    continue
                NotifyCenter.Send("warning", "设置错误", "语音路由动作不存在：" actId "（口语词 " vk "）| 请在编辑弹窗重新选择动作")
                return false
            }
            if (act.kind = "entry") {
                NotifyCenter.Send("warning", "设置错误", "语音路由不能引用入口类动作：" actId "（口语词 " vk "）| 请选具体动作（防套娃）")
                return false
            }
            if (actParam != "") {
                if (actId = "search") {
                    if (!engineKeys.Has(actParam)) {
                        NotifyCenter.Send("warning", "设置错误", "语音路由引擎未登记：" actParam "（口语词 " vk "）| 请先在「快捷搜索」页添加该引擎")
                        return false
                    }
                } else if (actId = "launch") {
                    fb := Actions.Get(actParam)
                    if (fb = "" || fb.kind = "entry") {
                        NotifyCenter.Send("warning", "设置错误", "launch 的兜底动作无效：" actParam "（口语词 " vk "）| 必须是具体动作 id（如 search）")
                        return false
                    }
                }
            }
        }

        hkList := []
        for hkKey in HotkeyCapture.GLOBAL_HK_KEYS {
            hkVal := hkValues.Has(hkKey) ? hkValues[hkKey] : ""
            if (hkVal != "")
                hkList.Push(hkVal)
        }

        rowKeys := Map()
        for hkVal in hkList
            rowKeys[hkVal] := "固定行"
        rows := SettingsTabHotkeyTable.GetEntriesForSave()
        for i, r in rows {
            if (r.key = "")
                continue
            mode := (r.domain = "input") ? "input" : "global"
            if !HotkeyCapture.IsAllowedHotkey(r.key, mode) {
                NotifyCenter.Send("warning", "快捷键错误", "第 " i " 行键形无效：" HotkeyCapture.FormatHotkeyLabel(r.key)
                    " | 剪贴板/选中/全局域=带修饰符组合（或裸修饰键），应用框内域=修饰符+Enter/NumpadEnter")
                return false
            }
            if (rowKeys.Has(r.key)) {
                NotifyCenter.Send("warning", "快捷键冲突", HotkeyCapture.FormatHotkeyLabel(r.key) " | 第 " i " 行与" rowKeys[r.key] "键位重复")
                return false
            }
            rowKeys[r.key] := "第 " i " 行"
            if (r.action = "")
                continue
            if (r.domain = "input") {
                if (r.action != "submit" && r.action != "newline") {
                    ok := false
                    for a in Presentation.For(Presentation.Slots) {
                        if (a.id = r.action) {
                            ok := true
                            break
                        }
                    }
                    if !ok {
                        NotifyCenter.Send("warning", "快捷键错误", "第 " i " 行动作不在键位槽候选内：" r.action)
                        return false
                    }
                }
            } else if (r.domain = "any") {
                if (!Presentation.CanConsume(r.action, Presentation.Global)) {
                    NotifyCenter.Send("warning", "快捷键错误", "第 " i " 行动作不在全局热键候选内：" r.action)
                    return false
                }
            } else {
                ok := false
                for a in Presentation.TextActionOptions(r.action) {
                    if (a.value = r.action) {
                        ok := true
                        break
                    }
                }
                if !ok {
                    NotifyCenter.Send("warning", "快捷键错误", "第 " i " 行动作不在文本动作候选内：" r.action "（可能是已禁用插件的引用）")
                    return false
                }
            }
        }
        i := 1
        while (i <= hkList.Length) {
            j := i + 1
            while (j <= hkList.Length) {
                if (hkList[i] = hkList[j]) {
                    NotifyCenter.Send("warning", "快捷键冲突", HotkeyCapture.FormatHotkeyLabel(hkList[i]) " | 请确保各全局快捷键互不相同")
                    return false
                }
                j += 1
            }
            i += 1
        }

        return true
    }

    static _ValidateEntryLine(val, lineNo, tableName) {
        try
            e := JSON.parse(val)
        catch {
            NotifyCenter.Send("warning", "设置错误", tableName " 第 " lineNo " 行 JSON 无法解析：" val)
            return false
        }
        if (Type(e) != "Map" || !e.Has("target") || Type(e["target"]) != "String" || e["target"] = "") {
            NotifyCenter.Send("warning", "设置错误", tableName " 第 " lineNo " 行缺少非空 target：" val)
            return false
        }
        etype := e.Has("type") ? e["type"] : "run"
        if (etype != "run" && etype != "action" && etype != "search") {
            NotifyCenter.Send("warning", "设置错误", tableName " 第 " lineNo " 行 type 非法（run/action/search）：" val)
            return false
        }
        if (etype = "search" && !InStr(e["target"], "%s")) {
            NotifyCenter.Send("warning", "设置错误", tableName " 第 " lineNo " 行 search 型 target 必含 %s：" val)
            return false
        }
        if (etype = "action") {
            a := Actions.Get(e["target"])
            if (a = "" || a.kind = "entry") {
                NotifyCenter.Send("warning", "设置错误", tableName " 第 " lineNo " 行未知或禁用动作 id：" e["target"])
                return false
            }
        }
        for f in ["home", "param", "icon", "cat"] {
            if (e.Has(f) && (Type(e[f]) != "String" || e[f] = "")) {
                NotifyCenter.Send("warning", "设置错误", tableName " 第 " lineNo " 行 " f " 须为非空字符串：" val)
                return false
            }
        }
        if (e.Has("display")) {
            d := e["display"]
            if (Type(d) != "Map") {
                NotifyCenter.Send("warning", "设置错误", tableName ' 第 ' lineNo ' 行 display 须为对象（如 {"toolbar":true}）：' val)
                return false
            }
            avail := ""
            for dk2 in ConfigManager.DISPLAY_KEYS
                avail .= (avail = "" ? "" : "/") . dk2
            for dk, dv in d {
                if (!ConfigManager.DISPLAY_KEYS.Has(dk)) {
                    NotifyCenter.Send("warning", "设置错误", tableName " 第 " lineNo " 行 display 键非法（" dk "，可用：" avail "）：" val)
                    return false
                }
                if (Type(dv) != "Integer") {
                    NotifyCenter.Send("warning", "设置错误", tableName " 第 " lineNo " 行 display." dk " 须为布尔：" val)
                    return false
                }
            }
        }
        return true
    }
}
