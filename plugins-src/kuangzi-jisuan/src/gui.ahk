#Requires AutoHotkey v2.0

PluginMainGuiHwnd() {
    return IsSet(_mainGui) ? _mainGui.Hwnd : 0
}

PluginShowMainGui() {
    global _mainGui
    d := PluginLoadData()
    g := Gui("+AlwaysOnTop", "框子计算")
    _mainGui := g
    g.SetFont("s11", "Microsoft YaHei")
    g.Add("Text", "x14 y16", "算式：")
    ed := g.Add("Edit", "x64 y12 w330")
    btn := g.Add("Button", "x402 y11 w70 Default", "计算")
    out := g.Add("Text", "x14 y50 w460 h24 c0x0EA5E9", "")
    g.Add("Text", "x14 y82", "历史（双击回填）：")
    btnSettings := g.Add("Button", "x324 y78 w72 h22", "设置")
    btnClear := g.Add("Button", "x400 y78 w72 h22", "清空历史")
    lv := g.Add("ListView", "x14 y104 w458 h220 Grid -Multi NoSortHdr", ["时间", "算式", "结果"])
    lv.ModifyCol(1, 120), lv.ModifyCol(2, 190), lv.ModifyCol(3, 120)
    i := d.history.Length
    while (i >= 1) {
        h := d.history[i]
        lv.Add("", h.t, h.expr, h.result)
        i--
    }
    btn.OnEvent("Click", (*) => DoCalc())
    btnSettings.OnEvent("Click", (*) => PluginShowSettingsGui(false))
    btnClear.OnEvent("Click", (*) => ClearHistory())
    lv.OnEvent("DoubleClick", (lvObj, row) => FillFromHistory(row))
    g.OnEvent("Escape", (*) => ExitApp(0))
    g.OnEvent("Close", (*) => ExitApp(0))
    ed.Focus()
    g.Show("w486 h336")
    Persistent()

    DoCalc() {
        r := CalcEvaluate(ed.Value)
        if (r.ok) {
            out.Value := "= " r.text
            A_Clipboard := r.text
            recorded := PluginAppendHistory(d, ed.Value, r.text)
            if (recorded) {
                PluginSaveData(d)
                lv.Insert(1, "", FormatTime(, "yyyy-MM-dd HH:mm"), ed.Value, r.text)
            }
            ed.Value := ""
            ed.Focus()
        } else {
            out.Value := "✕ " r.msg
        }
    }

    ClearHistory() {
        if (d.history.Length = 0) {
            out.Value := "历史已是空的"
            return
        }
        d.history := []
        PluginSaveData(d)
        lv.Delete()
        out.Value := "历史已清空"
    }

    FillFromHistory(row) {
        ed.Value := lv.GetText(row, 2)
        ed.Focus()
    }
}
