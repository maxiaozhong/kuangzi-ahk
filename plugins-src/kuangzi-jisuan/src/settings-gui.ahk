#Requires AutoHotkey v2.0

PluginShowSettingsGui(standalone := true) {
    d := PluginLoadData()
    opt := "+AlwaysOnTop -MinimizeBox"
    if (!standalone && PluginMainGuiHwnd())
        opt .= " +Owner" PluginMainGuiHwnd()
    g := Gui(opt, "框子计算 - 设置")
    quit := standalone ? (*) => ExitApp(0) : (*) => g.Destroy()
    g.SetFont("s10", "Microsoft YaHei")
    chk := g.Add("Checkbox", "x20 y20 w260", " 保存历史记录")
    chk.Value := d.settings.saveHistory ? 1 : 0
    g.Add("Text", "x20 y56", "最多保存条数：")
    ed := g.Add("Edit", "x120 y52 w70 Number")
    ed.Value := String(d.settings.maxHistory)
    g.Add("Text", "x20 y84", "结果通知样式：")
    cbo := g.Add("DDL", "x120 y80 w160", ["居中弹窗（常驻，点击关闭）", "右下角轻提示（自动消失）"])
    cbo.Choose(d.settings.notifyStyle = "toast" ? 2 : 1)
    btnSave := g.Add("Button", "x120 y124 w80 Default", "保存")
    btnCancel := g.Add("Button", "x210 y124 w80", "取消")
    btnSave.OnEvent("Click", (*) => DoSave())
    btnCancel.OnEvent("Click", quit)
    g.OnEvent("Escape", quit)
    g.OnEvent("Close", quit)
    g.Show("w320 h168")
    if (standalone)
        Persistent()

    DoSave() {
        n := Trim(ed.Value)
        if (!IsNumber(n) || n + 0 < 1 || n + 0 > 10000) {
            MsgBox("条数须为 1~10000 的数字", "框子计算 - 设置", 48)
            return
        }
        d.settings.saveHistory := chk.Value ? true : false
        d.settings.maxHistory := n + 0
        d.settings.notifyStyle := (cbo.Value = 2) ? "toast" : "center"
        while (d.history.Length > d.settings.maxHistory)
            d.history.RemoveAt(1)
        PluginSaveData(d)
        quit()
    }
}
