#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "NotifyCenter.ahk"

class VoiceCapture {
    static _active := false
    static _sinkGui := 0
    static TIMEOUT_MS := 2500

    static Begin(onDone) {
        if (this._active)
            return
        imeKey := ConfigManager.Get("IMEVoiceHotkey")
        if (imeKey = "" || StrLen(imeKey) < 3) {
            NotifyCenter.Send("warning", "智慧语音失败", "输入法语音快捷键未配置或格式错误")
            return
        }
        sendSeq := Utils.ConvertHotkeyToSend(imeKey)
        if (sendSeq = "") {
            NotifyCenter.Send("warning", "智慧语音失败", "输入法语音快捷键转换失败：" imeKey)
            return
        }

        this._active := true
        A_Clipboard := ""

        sinkGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale")
        sinkGui.BackColor := "000000"
        sinkBtn := sinkGui.Add("Button", "x0 y0 w10 h10", "Sink")
        sinkGui.Show("x0 y0 w10 h10 NoActivate")
        WinSetTransparent(0, sinkGui.Hwnd)
        DllCall("SetForegroundWindow", "Ptr", sinkGui.Hwnd)
        sinkBtn.Focus()
        this._sinkGui := sinkGui

        Send(sendSeq)

        waitKey := this._ExtractWaitKey(ConfigManager.Get("VoiceLaunchHotkey", "RControl"))
        KeyWait(waitKey)

        Send(sendSeq)

        text := this._WaitClipboardText()
        this._Finish(text, onDone)
    }

    static _ExtractWaitKey(hk) {
        if (hk = "")
            return "RControl"
        rest := hk
        while (rest != "" && InStr("^!+#<>", SubStr(rest, 1, 1)))
            rest := SubStr(rest, 2)
        if (rest = "")
            return "RControl"
        return rest
    }

    static _WaitClipboardText() {
        start := A_TickCount
        while (A_TickCount - start < this.TIMEOUT_MS) {
            t := A_Clipboard
            if (t != "" && t != "h" && t != "H")
                return t
            Sleep 30
        }
        return ""
    }

    static _Finish(text, cb) {
        this._active := false
        if (this._sinkGui) {
            try this._sinkGui.Destroy()
            this._sinkGui := 0
        }
        if (cb)
            cb(text)
    }
}
