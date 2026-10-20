#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "NotifyCenter.ahk"
#Include "Theme.ahk"
#Include "Actions.ahk"
#Include "HotkeyCapture.ahk"
#Include "SettingsTabVoice.ahk"
#Include "SettingsTabSearch.ahk"
#Include "SettingsTabLaunch.ahk"
#Include "SettingsTabQuickKey.ahk"
#Include "SettingsTabPlugin.ahk"
#Include "SettingsTabHotkeyTable.ahk"
#Include "SettingsTabNote.ahk"
#Include "SettingsTabSystem.ahk"
#Include "SettingsTabToolbar.ahk"
#Include "SettingsTabInput.ahk"
#Include "Presentation.ahk"

class SettingsViews {
    host := 0
    Ctrls := 0

    static TAB_X := 10
    static TAB_W := 650

    __New(host) {
        this.host := host
        this.Ctrls := host.Ctrls
    }

    BuildAll(SG, tabH) {
        Tabs := SG.Add("Tab3", "x" SettingsViews.TAB_X " y10 w" SettingsViews.TAB_W " h" tabH, ["笔记设置", "系统设置", "闪窗设置", "快捷搜索", "快捷启动", "一键直达", "智慧语音", "快捷键", "工具条", "插件"])
        SettingsTabNote.Build(SG, Tabs, 1, this.host)
        SettingsTabSystem.Build(SG, Tabs, 2, this.host)
        SettingsTabInput.Build(SG, Tabs, 3, this.host)
        SettingsTabSearch.Build(SG, Tabs, 4, this.host)
        SettingsTabLaunch.Build(SG, Tabs, 5, this.host)
        SettingsTabQuickKey.Build(SG, Tabs, 6, this.host)
        SettingsTabVoice.Build(SG, Tabs, 7, this.host)
        SettingsTabHotkeyTable.Build(SG, Tabs, 8, this.host)
        SettingsTabToolbar.Build(SG, Tabs, 9, this.host)
        SettingsTabPlugin.Build(SG, Tabs, 10, this.host)
        Tabs.UseTab()
    }

    RefreshAppShortcutsText() {
        SettingsTabLaunch.ReloadFromConfig()
    }

    RefreshSearchEnginesText() {
        SettingsTabSearch.ReloadFromConfig()
        SettingsTabInput.RefreshEngineDropdowns(this.Ctrls)
    }

}
