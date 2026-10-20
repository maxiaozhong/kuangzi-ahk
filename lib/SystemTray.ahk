#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "QuickNote.ahk"
#Include "NotifyCenter.ahk"
#Include "Actions.ahk"
#Include "Presentation.ahk"

class SystemTray {
    host := 0

    __New(host) {
        this.host := host
    }

    Init() {
        order := [
            "settings", "history", "",
            "add", "newNote", "openNote", "openDir", "",
            "toggleMain", "mode", "alwaysShow", "",
            "quit"
        ]
        traySet := Map()
        for a in Presentation.For(Presentation.Tray)
            traySet[a.id] := a
        A_TrayMenu.Delete()
        for id in order {
            if (id = "") {
                A_TrayMenu.Add()
                continue
            }
            if (!traySet.Has(id))
                continue
            A_TrayMenu.Add(traySet[id].label, ObjBindMethod(this, "_RunTrayAction", id))
        }
        A_TrayMenu.Default := "显示/隐藏输入框"
        A_TrayMenu.ClickCount := 2
        this.Update()
    }

    _RunTrayAction(id, *) {
        a := Actions.Get(id)
        if (a = "")
            return
        res := a.run.Call({ text: "", host: this.host })
        if (IsObject(res) && res.action != "")
            this.host.HandleRes(res)
    }

    Update() {
        Utils.RefreshMenuLabel(A_TrayMenu, ConfigManager.Get("AlwaysShow"), "✓ 常驻", "常驻")
    }
}
