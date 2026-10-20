#Requires AutoHotkey v2.0

#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "PathModel.ahk"
#Include "Theme.ahk"

class SettingsTabNote {
    static PERIOD_OPTIONS := ["按日", "按周", "按月"]

    static Build(SG, Tabs, i, center) {
        SET_LBL_X := 25, SET_LBL_W := 75, SET_CTRL_X := 105
        C := center.Ctrls

        Tabs.UseTab(i)
        yPos := 45
        SG.Add("GroupBox", "x15 y" yPos " w620 h170", "笔记库与写入")
        yPos += 32

        SG.Add("Text", "w" SET_LBL_W " x" SET_LBL_X " y" yPos+3, "笔记库目录:")
        C["VaultPath"] := SG.Add("Edit", "w290 x" SET_CTRL_X " y" yPos " vVaultPath", ConfigManager.Get("VaultPath"))
        SG.Add("Button", "w55 x" SET_CTRL_X+295 " y" yPos-1, "浏览").OnEvent("Click", (*) => SettingsTabNote.SelectVaultPath(center))
        yPos += 34

        SG.Add("Text", "w" SET_LBL_W " x" SET_LBL_X " y" yPos+3, "模板路径:")
        C["TemplatePath"] := SG.Add("Edit", "w290 x" SET_CTRL_X " y" yPos " vTemplatePath", ConfigManager.Get("TemplatePath"))
        SG.Add("Button", "w55 x" SET_CTRL_X+295 " y" yPos-1, "浏览").OnEvent("Click", (*) => SettingsTabNote.SelectTemplatePath(center))
        yPos += 34

        SG.Add("Text", "w" SET_LBL_W " x" SET_LBL_X " y" yPos+3, "日记周期:")
        C["NotePeriod"] := SG.Add("DropDownList", "w110 x" SET_CTRL_X " y" yPos " vNotePeriod Choose1", SettingsTabNote.PERIOD_OPTIONS)
        C["NotePeriod"].Choose(SettingsTabNote.PeriodToLabel(ConfigManager.Get("NotePeriod", "day")))
        yPos += 34

        C["NoteMetaEnabled"] := SG.Add("Checkbox", "x" SET_LBL_X " y" yPos " w480 vNoteMetaEnabled", " 记录来源（速记/待办携带来源标记，供工作台统计）")
        C["NoteMetaEnabled"].Value := ConfigManager.Get("NoteMetaEnabled", 0) ? 1 : 0
    }

    static PeriodToLabel(p) => (p = "week") ? "按周" : (p = "month") ? "按月" : "按日"
    static LabelToPeriod(l) => (l = "按周") ? "week" : (l = "按月") ? "month" : "day"

    static SelectVaultPath(center) {
        selectedFolder := DirSelect("*" center.Ctrls["VaultPath"].Value, 3, "选择笔记库目录")
        if (selectedFolder != "")
            center.Ctrls["VaultPath"].Value := selectedFolder
    }

    static SelectTemplatePath(center) {
        vault := PathModel.Vault()
        cur := Trim(center.Ctrls["TemplatePath"].Value)
        startDir := (vault != "" && InStr(FileExist(vault), "D")) ? vault : ""
        if (cur != "") {
            abs := RegExMatch(cur, "^[A-Za-z]:") || (SubStr(cur, 1, 1) = "\")
            p := abs ? cur : vault "\" cur
            SplitPath(p, , &dir)
            if (dir != "" && InStr(FileExist(dir), "D"))
                startDir := dir
        }
        sel := FileSelect(3, startDir, "选择模板文件", "Markdown (*.md)")
        if (sel = "")
            return
        center.Ctrls["TemplatePath"].Value := (vault != "" && InStr(sel, vault "\") = 1)
            ? SubStr(sel, StrLen(vault) + 2)
            : sel
    }
}
