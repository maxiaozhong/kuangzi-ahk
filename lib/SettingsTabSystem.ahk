#Requires AutoHotkey v2.0

#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "NotifyCenter.ahk"
#Include "Theme.ahk"

class SettingsTabSystem {
    static Build(SG, Tabs, i, center) {
        SET_LBL_X := 25, SET_LBL_W := 120, SET_CTRL_X := 155, SET_CTRL_W := 480, SET_ROW_H := 28, SET_HINT := "c" Theme.COLOR_HINT
        C := center.Ctrls

        Tabs.UseTab(i)
        SYS_H := 128
        yPos := 45
        SG.Add("GroupBox", "x15 y" yPos " w620 h" SYS_H, "系统")
        yPos += 28
        C["AutoStart"] := SG.Add("Checkbox", "x" SET_LBL_X " y" yPos " w420 vAutoStart", " 开机自动启动 (随 Windows 启动隐藏运行)")
        if A_IsCompiled {
            C["AutoStart"].Value := FileExist(A_Startup "\" AppInfo.name ".lnk") ? 1 : 0
        } else {
            C["AutoStart"].Value := 0
            C["AutoStart"].Enabled := false
            C["AutoStart"].Text := " 开机自动启动（源码模式不支持，仅安装版可用）"
        }
        yPos += SET_ROW_H
        SG.Add("Text", "w" SET_LBL_W " x" SET_LBL_X " y" yPos+3, "设备标识:")
        C["DeviceId"] := SG.Add("Edit", "w140 x" SET_CTRL_X " y" yPos " vDeviceId", ConfigManager.Get("DeviceId"))
        SG.Add("Text", "x" SET_CTRL_X+150 " y" yPos+3 " w300 " SET_HINT, "多设备溯源展示用，默认取系统用户名")
        yPos += SET_ROW_H
        SG.Add("Button", "w120 x" SET_LBL_X " y" yPos+6, "卸载程序...").OnEvent("Click", (*) => center.host.Uninstall())
        SG.Add("Button", "w120 x" SET_LBL_X+130 " y" yPos+6, "打开配置文件").OnEvent("Click", (*) => SettingsTabSystem.OpenConfigFile())
        SG.Add("Button", "w130 x" SET_LBL_X+260 " y" yPos+6, "初始化默认配置...").OnEvent("Click", (*) => SettingsTabSystem.ResetConfig(center))
        SG.Add("Button", "w120 x" SET_LBL_X+400 " y" yPos+6, "打开安装目录").OnEvent("Click", (*) => SettingsTabSystem.OpenInstallDir())

        yPos := 45 + SYS_H
        SG.Add("GroupBox", "x15 y" yPos " w620 h76", "通知")
        yPos += 28
        C["NotifyEnabled"] := SG.Add("Checkbox", "x" SET_LBL_X " y" yPos " w420 vNotifyEnabled", " 启用通知（右下角 Toast 提示）")
        C["NotifyEnabled"].Value := ConfigManager.Get("NotifyEnabled")
        yPos += SET_ROW_H
        C["NotifySound"] := SG.Add("Checkbox", "x" SET_LBL_X " y" yPos " w420 vNotifySound", " 通知声音提示")
        C["NotifySound"].Value := ConfigManager.Get("NotifySound")
    }

    static OpenConfigFile(*) {
        if !FileExist(ConfigManager.ConfigFile)
            ConfigManager.Save()
        try {
            Run(ConfigManager.ConfigFile)
        } catch as e {
            NotifyCenter.Send("error", "打开配置失败", e.Message)
        }
    }

    static OpenInstallDir(*) {
        try {
            Run('explorer.exe "' A_ScriptDir '"')
        } catch as e {
            NotifyCenter.Send("error", "打开安装目录失败", e.Message)
        }
    }

    static ResetConfig(center, *) {
        res := center.host.TopMsgBox(
            "将把全部设置恢复为默认值。`n`n当前配置会备份为 config.json.bak-时间戳（同目录），确定继续？",
            center.host.AppName " - 初始化默认配置", 0x4 + 0x30)
        if (res != "Yes")
            return
        if FileExist(ConfigManager.ConfigFile) {
            bak := ConfigManager.ConfigFile ".bak-" FormatTime(, "yyyyMMdd-HHmmss")
            try FileMove(ConfigManager.ConfigFile, bak, 1)
        }
        ConfigManager.Load()
        NotifyCenter.Send("info", "初始化完成", "已恢复默认配置（原配置已备份）。设置页显示为旧值，重新打开设置页查看。")
    }
}
