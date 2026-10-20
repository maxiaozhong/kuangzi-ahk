#Requires AutoHotkey v2.0

#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "Theme.ahk"
#Include "Presentation.ahk"

class SettingsTabToolbar {
    static Build(SG, Tabs, i, center) {
        C := center.Ctrls

        Tabs.UseTab(i)
        yPos := 45
        SG.Add("GroupBox", "x15 y" yPos " w620 h360", "输入框工具条按钮")
        yPos += 28
        tools := ConfigManager.Get("InputBarTools", ConfigManager.GetDefaultInputBarTools())
        col := 0
        for t in Presentation.For(Presentation.ToolbarPool) {
            chk := SG.Add("Checkbox", "x" (25 + col * 150) " y" yPos " w140 vInputBar_" t.id, " " t.icon " " t.label)
            chk.Value := Utils.ArrContains(tools, t.id) ? 1 : 0
            C["InputBar_" t.id] := chk
            chk.OnEvent("Click", (ctrl, *) => SettingsTabToolbar._EnforceCap(C, ctrl))
            col++
            if (col >= 3) {
                col := 0
                yPos += 30
            }
        }
    }

    static _EnforceCap(C, ctrl) {
        if (!ctrl.Value)
            return
        n := 0
        for k, c in C {
            if (SubStr(k, 1, 9) = "InputBar_" && c.Value)
                n++
        }
        if (n > Theme.TOOLBAR_MAX) {
            ctrl.Value := 0
            NotifyCenter.Send("warning", "工具条已满", "最多勾选 " Theme.TOOLBAR_MAX " 个，再多输入框放不下")
        }
    }
}
