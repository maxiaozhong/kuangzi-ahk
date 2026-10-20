#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "Theme.ahk"
#Include "ConfigManager.ahk"
#Include "NotifyCenter.ahk"
#Include "Actions.ahk"
#Include "HotkeyCapture.ahk"
#Include "Presentation.ahk"
#Include "VoiceRouter.ahk"
#Include "PluginManager.ahk"
#Include "SettingsListPage.ahk"

class SettingsTabVoice extends SettingsListPage {
    static _Entries := Map()
    static _List := ""

    static Columns := [["语音词", 84], ["角色", 58], ["动作来源", 66], ["动作", 208], ["兜底", 62], ["专属废话", 90]]

    static SOURCES := ["内置", "快捷搜索", "快捷启动", "插件"]

    static Build(SG, Tabs, i, center) {
        Tabs.UseTab(i)
        yPos := Theme.SET_PAGE_Y
        SG.Add("GroupBox", "x" Theme.SET_PAGE_X " y" yPos " w" Theme.SET_PAGE_W " h" Theme.SET_PAGE_H, "语音词（长按 " HotkeyCapture.FormatHotkeyLabel(ConfigManager.Get("VoiceLaunchHotkey", "RControl")) " 说话）")
        yPos += 22

        LV_H := Theme.SetListBottom() - yPos
        lv := SG.Add("ListView", "x" Theme.SET_LIST_X " y" yPos " w" Theme.SET_LIST_W " h" LV_H " -Multi NoSortHdr Grid"
            , ["语音词", "角色", "动作来源", "动作", "兜底", "专属废话"])
        SettingsTabVoice._List := lv
        lv.OnEvent("DoubleClick", (lvObj, row) => SettingsTabVoice._EditEntry(center, row))

        BTN_Y := Theme.SetBtnY()
        SG.Add("Button", "x" Theme.SetBtnX(0) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "新增").OnEvent("Click", (*) => SettingsTabVoice._EditEntry(center, 0))
        SG.Add("Button", "x" Theme.SetBtnX(1) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "修改").OnEvent("Click", (*) => SettingsTabVoice._EditSelected(center))
        SG.Add("Button", "x" Theme.SetBtnX(2) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "删除").OnEvent("Click", (*) => SettingsTabVoice._DeleteSelected())
        SG.Add("Button", "x" Theme.SetBtnX(3) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "恢复默认").OnEvent("Click", (*) => SettingsTabVoice._ResetList(center))
        SG.Add("Button", "x" (Theme.SET_PAGE_X + Theme.SET_PAGE_W - 10 - Theme.SET_BTN_W) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "配置面板...").OnEvent("Click", (*) => SettingsTabVoice._EditConfig(center))

        SettingsTabVoice._LoadFromConfig()
        SettingsTabVoice._Redraw()
    }

    static _LoadFromConfig() {
        m := Map()
        for k, v in ConfigManager.Get("VoiceRoutes") {
            if (Type(v) = "Map" || (Type(v) = "Object" && v.HasOwnProp("target")))
                m[k] := SettingsTabVoice._NormEntry(v)
        }
        SettingsTabVoice._Entries := m
    }

    static _NormEntry(v) {
        f := Utils.ObjGet(v, "fillers", [])
        return { target: Utils.ObjGet(v, "target")
            , param: Utils.ObjGet(v, "param")
            , rescan: Utils.ObjGet(v, "rescan", true)
            , fillers: (Type(f) = "Array") ? f : [] }
    }

    static GetEntriesForSave() {
        m := Map()
        for k, e in SettingsTabVoice._Entries {
            o := { target: e.target }
            if (e.param != "")
                o.param := e.param
            o.rescan := e.rescan
            if (Type(e.fillers) = "Array" && e.fillers.Length > 0)
                o.fillers := e.fillers
            m[k] := o
        }
        return m
    }

    static _ResetList(center) {
        msg := "恢复默认将清除你自定义的全部语音路由。`n`n列表会重置为出厂路由，点「保存并应用」后不可恢复。确定恢复？"
        if (center.host.TopMsgBox(msg, "恢复默认", 0x4 + 0x30) != "Yes")
            return
        m := Map()
        for k, v in ConfigManager.GetDefaultVoiceRoutes() {
            if (Type(v) = "Map" || (Type(v) = "Object" && v.HasOwnProp("target")))
                m[k] := SettingsTabVoice._NormEntry(v)
        }
        SettingsTabVoice._Entries := m
        SettingsTabVoice._Redraw()
    }

    static _TargetId(target, param) {
        if (target = "search" && param != "" && ConfigManager.EngineMap.Has(param))
            return "eng." param
        return target
    }

    static _SourceLabel(id) {
        ns := Actions.SplitId(id).ns
        if (ns = "plugin")
            return "插件"
        if (ns = "eng")
            return "快捷搜索"
        if (ns = "word")
            return "快捷启动"
        return "内置"
    }

    static _RoleLabel(t) => (t = "launch") ? "修饰词" : "指令词"

    static RowValues(k, e) {
        t := Utils.ObjGet(e, "target", "")
        p := Utils.ObjGet(e, "param", "")
        id := SettingsTabVoice._TargetId(t, p)
        fb := (t = "launch") ? Presentation.ActionLabel((p = "") ? "none" : p) : ""
        return [k, SettingsTabVoice._RoleLabel(t), SettingsTabVoice._SourceLabel(id), Presentation.ActionLabel(id), fb
            , SettingsTabVoice._JoinFillers(Utils.ObjGet(e, "fillers", []))]
    }

    static _JoinFillers(arr) {
        if (Type(arr) != "Array" || arr.Length = 0)
            return ""
        out := ""
        for fw in arr
            out .= (out = "" ? "" : "、") fw
        return out
    }

    static _IndexOf(arr, v) {
        for n, x in arr {
            if (x = v)
                return n
        }
        return 1
    }

    static _EditSelected(center) {
        row := SettingsTabVoice._List.GetNext()
        if (row = 0) {
            NotifyCenter.Send("warning", "语音词", "先在列表里选一行")
            return
        }
        SettingsTabVoice._EditEntry(center, row)
    }

    static _DeleteSelected() {
        row := SettingsTabVoice._List.GetNext()
        if (row = 0) {
            NotifyCenter.Send("warning", "语音词", "先在列表里选一行")
            return
        }
        key := SettingsTabVoice._List.GetText(row, 1)
        if (!SettingsTabVoice._Entries.Has(key))
            return
        if (MsgBox("删除语音词「" key "」？保存并应用后不可撤销。", "框子 · 智慧语音", "YesNo Icon!") != "Yes")
            return
        SettingsTabVoice._Entries.Delete(key)
        SettingsTabVoice._Redraw()
    }

    static _EditEntry(center, row := 0) {
        origKey := ""
        if (row > 0) {
            dispKey := SettingsTabVoice._List.GetText(row, 1)
            if (SettingsTabVoice._Entries.Has(dispKey))
                origKey := dispKey
        }
        orig := (origKey != "") ? SettingsTabVoice._Entries[origKey]
            : { target: "launch", param: "none", rescan: true, fillers: [] }

        pool := Map()
        pool["内置"] := []
        for a in Actions.All() {
            if (a.kind = "entry")
                continue
            ns := Actions.SplitId(a.id).ns
            if (ns = "plugin" || ns = "eng" || ns = "word")
                continue
            if (!Presentation.CanConsume(a.id, Presentation.Voice))
                continue
            pool["内置"].Push(a.id)
        }
        pool["快捷搜索"] := []
        for ek in ConfigManager.EngineMap
            if (Presentation.CanConsume("eng." ek, Presentation.Voice))
                pool["快捷搜索"].Push("eng." ek)
        pool["快捷启动"] := []
        for wk in ConfigManager.WordMap
            if (Presentation.CanConsume("word." wk, Presentation.Voice))
                pool["快捷启动"].Push("word." wk)
        pool["插件"] := []
        for a in Actions.PLUGINS()
            if (Presentation.CanConsume(a.id, Presentation.Voice))
                pool["插件"].Push(a.id)

        curId := SettingsTabVoice._TargetId(orig.target, orig.param)

        g := Gui("+Owner" center.SettingsGui.Hwnd " -MinimizeBox +AlwaysOnTop"
            , (origKey != "") ? "修改语音词" : "新增语音词")
        g.SetFont("s9", "Microsoft YaHei")
        g.Add("Text", "x15 y18 w70", "语音词:")
        keyEdit := g.Add("Edit", "x90 y15 w250", origKey)
        g.Add("Text", "x15 y52 w70", "动作来源:")
        srcDdl := g.Add("DropDownList", "x90 y49 w150", SettingsTabVoice.SOURCES)
        g.Add("Text", "x15 y86 w70", "动作:")
        actDdl := g.Add("DropDownList", "x90 y83 w320", ["（无候选）"])
        g.Add("Text", "x15 y120 w70", "兜底:")
        fbIds := SettingsTabVoice._FallbackOptions()
        fbLabels := []
        for id in fbIds
            fbLabels.Push(Presentation.ActionLabel(id))
        fbDdl := g.Add("DropDownList", "x90 y117 w320", fbLabels)
        wantFb := (orig.target = "launch" && orig.param != "") ? orig.param : "none"
        fbDdl.Choose(SettingsTabVoice._IndexOf(fbIds, wantFb))
        g.Add("Text", "x15 y150 w430 c" Theme.COLOR_HINT, "找不到时的去向（只有「动作 = launch」用得上）")
        g.Add("Text", "x15 y180 w430", "专属废话（这条词自己额外的，顿号/逗号分隔）:")
        fillerEdit := g.Add("Edit", "x15 y202 w395", SettingsTabVoice._JoinFillers(orig.fillers))
        rescanChk := g.Add("CheckBox", "x15 y234 w395", "二次找词（本词只做授权，后面扫到谁谁干活）")
        rescanChk.Value := (orig.rescan = false) ? 0 : 1
        g.Add("Text", "x15 y258 w430 c" Theme.COLOR_HINT, "例：「打开 计算器」→「打开」只授权，干活的还是词表里的「计算器」")
        okBtn := g.Add("Button", "x225 y286 w80 h26 Default", (origKey != "") ? "保存" : "添加")
        cancelBtn := g.Add("Button", "x315 y286 w80 h26", "取消")
        g.Show("w425 h332")
        keyEdit.Focus()

        curIds := []
        srcDdl.Choose(SettingsTabVoice._SourceLabel(curId))
        RefillActions(srcDdl.Text, curId)
        srcDdl.OnEvent("Change", (*) => RefillActions(srcDdl.Text, ""))
        actDdl.OnEvent("Change", (*) => SyncRescan())
        okBtn.OnEvent("Click", (*) => DoCommit())
        cancelBtn.OnEvent("Click", (*) => g.Destroy())
        g.OnEvent("Escape", (*) => g.Destroy())
        g.OnEvent("Close", (*) => g.Destroy())

        RefillActions(srcName, selectId) {
            src := pool.Has(srcName) ? pool[srcName] : []
            ids := []
            for id in src
                ids.Push(id)
            if (selectId != "" && !Utils.ArrContains(ids, selectId))
                ids.Push(selectId)
            labels := []
            for id in ids
                labels.Push(Presentation.ActionLabel(id))
            if (labels.Length = 0)
                labels.Push("（无候选）")
            actDdl.Delete()
            actDdl.Add(labels)
            actDdl.Choose(SettingsTabVoice._IndexOf(ids, selectId))
            curIds := ids
            SyncRescan()
        }

        SyncRescan() {
            id := (actDdl.Value >= 1 && actDdl.Value <= curIds.Length) ? curIds[actDdl.Value] : ""
            isLaunch := (id = "launch")
            rescanChk.Enabled := isLaunch
            rescanChk.Text := isLaunch
                ? "二次找词（本词只做授权，后面扫到谁谁干活）"
                : "二次找词（仅「启动目标」用得上；本词自己会干活）"
            if (!isLaunch)
                rescanChk.Value := 1
        }

        DoCommit() {
            newKey := Trim(keyEdit.Value)
            if (newKey = "") {
                NotifyCenter.Send("warning", "语音词", "语音词不能为空")
                return
            }
            if (newKey != origKey && SettingsTabVoice._Entries.Has(newKey)) {
                NotifyCenter.Send("warning", "语音词", "语音词已存在：" newKey)
                return
            }
            ids := pool.Has(srcDdl.Text) ? pool[srcDdl.Text] : []
            chosen := (actDdl.Value >= 1 && actDdl.Value <= ids.Length) ? ids[actDdl.Value] : ""
            if (chosen = "") {
                NotifyCenter.Send("warning", "语音词", "请选择动作")
                return
            }
            target := chosen, param := ""
            cs := Actions.SplitId(chosen)
            if (cs.ns = "eng") {
                target := "search"
                param := cs.name
            } else if (chosen = "launch") {
                param := (fbDdl.Value >= 1 && fbDdl.Value <= fbIds.Length) ? fbIds[fbDdl.Value] : "none"
            }
            a := Actions.Get(target)
            if (a = "" || a.kind = "entry") {
                NotifyCenter.Send("warning", "语音词", "动作无效：" target)
                return
            }
            if (origKey != "")
                SettingsTabVoice._Entries.Delete(origKey)
            SettingsTabVoice._Entries[newKey] := { target: target, param: param
                , rescan: (target = "launch") ? (rescanChk.Value = 1) : true
                , fillers: SettingsTabVoice._SplitFillers(fillerEdit.Value) }
            g.Destroy()
            SettingsTabVoice._Redraw()
        }
    }

    static _FallbackOptions() {
        out := []
        for o in Presentation.SubmitFallbackOptions()
            out.Push(o.value)
        return out
    }

    static _SplitFillers(text) {
        out := []
        for fw in StrSplit(text, ["、", ",", "，", "|", " ", "`t", "`r", "`n"]) {
            v := Trim(fw)
            if (v != "")
                out.Push(v)
        }
        return out
    }

    static _EditConfig(center) {
        g := Gui("+Owner" center.SettingsGui.Hwnd " -MinimizeBox +AlwaysOnTop", "语音配置面板")
        g.SetFont("s9", "Microsoft YaHei")
        HINT := Theme.COLOR_HINT, ERR := Theme.COLOR_ERR

        curIme := ConfigManager.Get("IMEVoiceHotkey", "")
        curHold := ConfigManager.Get("IMEHoldHotkey", "")
        g.Add("GroupBox", "x15 y12 w440 h126", "输入法语音键（照输入法设置填）")
        g.Add("Text", "x32 y40 w86", "启动语音输入")
        imeBtn := g.Add("Button", "x126 y36 w160 h26", HotkeyCapture.FormatHotkeyLabel(curIme))
        g.Add("Text", "x294 y40 w152 c" HINT, "按一下开、再按一下停")
        imeMsg := g.Add("Text", "x32 y66 w410 h16 c" ERR, "")
        g.Add("Text", "x32 y94 w86", "按住说话")
        holdBtn := g.Add("Button", "x126 y90 w160 h26", HotkeyCapture.FormatHotkeyLabel(curHold))
        g.Add("Text", "x294 y94 w152 c" HINT, "按住说、松手停")
        holdMsg := g.Add("Text", "x32 y120 w410 h16 c" ERR, "")

        fbIds := SettingsTabVoice._FallbackOptions()
        fbLabels := []
        for id in fbIds
            fbLabels.Push(Presentation.ActionLabel(id))
        g.Add("GroupBox", "x15 y146 w440 h96", "语音路由")
        g.Add("Text", "x32 y170 w86", "识别兜底")
        fbDdl := g.Add("DropDownList", "x126 y166 w200", fbLabels)
        fbDdl.Choose(SettingsTabVoice._IndexOf(fbIds, ConfigManager.Get("VoiceFallbackAction", "search")))
        g.Add("Text", "x32 y204 w86", "认词范围")
        winEdit := g.Add("Edit", "x126 y201 w50 Number", String(ConfigManager.Get("VoiceWindow", 6)))
        g.Add("Text", "x184 y204 w258 c" HINT, "句子开头 N 个字内找词（默认 6）")

        g.Add("GroupBox", "x15 y252 w440 h116", "口头语（每行一个，全局打底）")
        fillEdit := g.Add("Edit", "x30 y276 w410 h80 Multi", SettingsTabVoice._FillersText())

        g.Add("GroupBox", "x15 y376 w440 h146", "试跑（会真的执行）")
        testEdit := g.Add("Edit", "x30 y400 w300", "打开帮我搜一下B站")
        g.Add("Button", "x340 y398 w80 h24", "真跑一次").OnEvent("Click"
            , (*) => (outBox.Value := SettingsTabVoice._RunTest(testEdit.Value)))
        outBox := g.Add("Edit", "x30 y432 w410 h78 Multi ReadOnly -WantReturn", "")

        okBtn := g.Add("Button", "x255 y534 w100 h26 Default", "保存")
        cancelBtn := g.Add("Button", "x365 y534 w90 h26", "取消")
        g.Show("w470 h572")
        outBox.Value := "写一句话，点「真跑一次」——会真的执行，不是演练。"

        center.capture.HkValues["IMEVoiceHotkey"] := curIme
        center.capture.HkValues["IMEHoldHotkey"] := curHold
        imeBtn.OnEvent("Click", (*) => center.capture.StartHotkeyCapture("IMEVoiceHotkey", imeBtn, "global", "global", imeMsg))
        holdBtn.OnEvent("Click", (*) => center.capture.StartHotkeyCapture("IMEHoldHotkey", holdBtn, "global", "global", holdMsg))

        CloseDlg() {
            center.capture.CancelCapture()
            center.capture.HkValues.Delete("IMEVoiceHotkey")
            center.capture.HkValues.Delete("IMEHoldHotkey")
            g.Destroy()
        }

        DoSave() {
            n := Trim(winEdit.Value)
            if (n = "" || !IsInteger(n) || n + 0 < 1 || n + 0 > 50) {
                NotifyCenter.Send("warning", "语音配置", "认词范围须为 1-50 的整数")
                return
            }
            ConfigManager.Set("VoiceWindow", n + 0)
            ConfigManager.Set("VoiceFallbackAction"
                , (fbDdl.Value >= 1 && fbDdl.Value <= fbIds.Length) ? fbIds[fbDdl.Value] : "search")
            ConfigManager.Set("VoiceFillerWords", SettingsTabVoice._SplitLines(fillEdit.Value))
            ConfigManager.Set("IMEVoiceHotkey", center.capture.HkValues.Has("IMEVoiceHotkey") ? center.capture.HkValues["IMEVoiceHotkey"] : curIme)
            ConfigManager.Set("IMEHoldHotkey", center.capture.HkValues.Has("IMEHoldHotkey") ? center.capture.HkValues["IMEHoldHotkey"] : curHold)
            ConfigManager.Save()
            NotifyCenter.Send("info", "语音配置", "已保存（全局项为即时落盘）")
            CloseDlg()
        }
        okBtn.OnEvent("Click", (*) => DoSave())
        cancelBtn.OnEvent("Click", (*) => CloseDlg())
        g.OnEvent("Escape", (*) => CloseDlg())
        g.OnEvent("Close", (*) => CloseDlg())
    }

    static _FillersText() {
        out := ""
        for fw in ConfigManager.Get("VoiceFillerWords", ConfigManager.GetDefaultFillerWords())
            out .= fw "`n"
        return RTrim(out, "`n")
    }

    static _SplitLines(text) {
        out := []
        Loop Parse, text, "`n", "`r" {
            v := Trim(A_LoopField)
            if (v != "")
                out.Push(v)
        }
        return out
    }

    static _JourneyText(text) {
        if (Trim(text) = "")
            return "在上面写一句话，这里会显示它被理解的过程"
        t := VoiceRouter.TraceSteps(text)
        if (t.stage = "clean")
            return "这句话洗净后是空的（只剩标点或语气词），不处理"
        if (t.stage = "fallback")
            return "① 一个词都没认出来`n② 按「兜底」的设定 → " Presentation.ActionLabel(t.fallback)
        w := t.winner
        out := "① 听懂「" w.word "」—— " SettingsTabVoice._KindText(w.kind) "，来自" SettingsTabVoice._SrcText(w.src)
        if (t.rest = "")
            out .= "`n② 后面没有别的内容了"
        else if (Utils.ObjGet(t, "restRaw", "") != t.rest)
            out .= "`n② 去掉口头语，剩下「" t.rest "」"
        else
            out .= "`n② 剩下的内容「" t.rest "」"
        if (t.stage = "second") {
            s2 := t.second
            out .= "`n③ 在剩下的话里又找到「" s2.word "」（" SettingsTabVoice._SrcText(s2.src) "）→ " SettingsTabVoice._GoText(s2)
        } else {
            out .= "`n③ → " SettingsTabVoice._GoText(w)
        }
        return out
    }

    static _RunTest(text) {
        if (Trim(text) = "")
            return "先写一句话"
        head := SettingsTabVoice._JourneyText(text)
        return head "`n▶ " SettingsTabVoice._ResultText(VoiceRouter.Process(text))
    }

    static _ResultText(res) {
        if (!IsObject(res))
            return "没执行——引擎没认出可执行的东西"
        if (!Utils.ObjGet(res, "ok", false))
            return "没成功：" Utils.ObjGet(res, "msg", "未知原因")
        m := Map("note", "已记入速记", "todo", "已记入待办", "search", "已搜索"
            , "run", "已打开", "launch", "已启动", "send", "已按键"
            , "empty", "空输入，什么都没做", "none", "按设定不处理")
        act := Utils.ObjGet(res, "action", "")
        s := m.Has(act) ? m[act] : "已执行"
        t := Utils.ObjGet(res, "text", "")
        return (t != "") ? (s "：「" t "」") : s
    }

    static _KindText(kind) => (kind = 1) ? "它属于「启动」类，后面的话要再找一轮" : "它能直接干活"

    static _SrcText(src) {
        m := Map("builtin", "内置词", "engine", "快捷搜索", "word", "快捷启动"
            , "plugin", "插件", "route", "专属词")
        return m.Has(src) ? m[src] : src
    }

    static _GoText(c) {
        switch c.src {
            case "route":
                id := SettingsTabVoice._TargetId(Utils.ObjGet(c, "target", ""), Utils.ObjGet(c, "param", ""))
                return "按词条设定的去向执行（" id "）"
            case "builtin":
                return "按它的去向执行（" Utils.ObjGet(c.entry, "target", "?") "）"
            case "engine":
                return "用它去搜索后面的内容"
            case "word":
                ty := (Type(c.entry) = "String") ? "run" : Utils.ObjGet(c.entry, "type", "run")
                return (ty = "action") ? ("执行它指向的动作（" Utils.ObjGet(c.entry, "target", "?") "）") : "打开它"
            case "plugin":
                return "交给插件执行（" c.entry "）"
        }
        return "按它自己的方式执行"
    }
}
