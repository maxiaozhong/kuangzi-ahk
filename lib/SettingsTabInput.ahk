#Requires AutoHotkey v2.0

#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "Theme.ahk"
#Include "Presentation.ahk"
#Include "SettingsTabHotkeyTable.ahk"

class SettingsTabInput {
    static ENTER_ACTION_OPTIONS := [
        { label: "换行", value: "newline" },
        { label: "提交", value: "submit" }
    ]

    static Build(SG, Tabs, i, center) {
        SET_ROW_H := 28
        C := center.Ctrls

        Tabs.UseTab(i)
        L_X := 25, L_CTRL_W := 150
        R_LBL_W := 120, R_CTRL_X := 155

        yPos := 45
        SG.Add("GroupBox", "x15 y" yPos " w620 h178", "Enter 与兜底")
        yPos += 28

        enterOptions := []
        for opt in SettingsTabInput.ENTER_ACTION_OPTIONS
            enterOptions.Push(opt.label)

        SG.Add("Text", "w95 x" L_X " y" yPos+3, "普通模式:")
        C["EnterActionNormal"] := SG.Add("DropDownList", "w" L_CTRL_W " x" L_X+100 " y" yPos " vEnterActionNormal Choose1", enterOptions)
        yPos += SET_ROW_H

        SG.Add("Text", "w95 x" L_X " y" yPos+3, "极速模式:")
        C["EnterActionTurbo"] := SG.Add("DropDownList", "w" L_CTRL_W " x" L_X+100 " y" yPos " vEnterActionTurbo Choose1", enterOptions)
        yPos += SET_ROW_H

        SG.Add("Text", "w95 x" L_X " y" yPos+3, "提交兜底:")
        fallbackOptions := []
        for opt in Presentation.SubmitFallbackOptions(ConfigManager.Get("ConfirmFallback"))
            fallbackOptions.Push(opt.label)
        C["ConfirmFallback"] := SG.Add("DropDownList", "w" L_CTRL_W " x" L_X+100 " y" yPos " vConfirmFallback Choose1", fallbackOptions)
        yPos += SET_ROW_H

        SG.Add("Text", "x25 y" yPos+8 " w570 0x10")
        yPos += 30

        SG.Add("Button", "x25 y" yPos " w100 h24", "速记编辑习惯").OnEvent("Click", (*) => SettingsTabInput.ApplyEditorPreset(center))
        SG.Add("Button", "x130 y" yPos " w100 h24", "搜索聊天习惯").OnEvent("Click", (*) => SettingsTabInput.ApplyChatPreset(center))

        yPos := 45 + 178 + 8
        SG.Add("GroupBox", "x15 y" yPos " w620 h80", "动作引擎")
        yPos += 28

        SG.Add("Text", "w" R_LBL_W " x" L_X " y" yPos+3, "搜索动作引擎:")
        engOpts := []
        for ek in ConfigManager.EngineMap
            engOpts.Push(ek)
        C["SearchEngine"] := SG.Add("DropDownList", "w110 x" R_CTRL_X " y" yPos " vSearchEngine Choose1", engOpts)
        cur := ConfigManager.Get("SearchEngine")
        if (cur != "" && ConfigManager.EngineMap.Has(cur))
            C["SearchEngine"].Choose(cur)
    }

    static RefreshEngineDropdowns(Ctrls) {
        ddl := Ctrls.Has("SearchEngine") ? Ctrls["SearchEngine"] : ""
        if (!IsObject(ddl))
            return
        cur := ddl.Text
        ddl.Delete()
        opts := []
        for ek in ConfigManager.EngineMap
            opts.Push(ek)
        ddl.Add(opts)
        ddl.Choose(cur != "" && ConfigManager.EngineMap.Has(cur) ? cur : opts[1])
    }

    static ApplyEditorPreset(center) {
        C := center.Ctrls
        C["EnterActionNormal"].Choose(SettingsTabInput.EnterActionToLabel("newline"))
        C["EnterActionTurbo"].Choose(SettingsTabInput.EnterActionToLabel("submit"))
        C["ConfirmFallback"].Choose(SettingsTabInput.TextActionToLabel("note"))
        SettingsTabHotkeyTable.ApplySlotDefaults()
    }

    static ApplyChatPreset(center) {
        C := center.Ctrls
        C["EnterActionNormal"].Choose(SettingsTabInput.EnterActionToLabel("submit"))
        C["EnterActionTurbo"].Choose(SettingsTabInput.EnterActionToLabel("submit"))
        C["ConfirmFallback"].Choose(SettingsTabInput.TextActionToLabel("search"))
        SettingsTabHotkeyTable.ApplySlotDefaults()
    }

    static _OptToLabel(opts, v, dflt) {
        for opt in opts {
            if (opt.value = v)
                return opt.label
        }
        return dflt
    }

    static _OptLabelToValue(opts, label, dflt) {
        for opt in opts {
            if (opt.label = label)
                return opt.value
        }
        return dflt
    }

    static EnterActionToLabel(action) => SettingsTabInput._OptToLabel(SettingsTabInput.ENTER_ACTION_OPTIONS, action, "换行")
    static EnterLabelToAction(label) => SettingsTabInput._OptLabelToValue(SettingsTabInput.ENTER_ACTION_OPTIONS, label, "newline")

    static TextActionToLabel(v) => SettingsTabInput._OptToLabel(Presentation.SubmitFallbackOptions(), v, "速记")
    static TextActionLabelToValue(label) => SettingsTabInput._OptLabelToValue(Presentation.SubmitFallbackOptions(), label, "note")
}
