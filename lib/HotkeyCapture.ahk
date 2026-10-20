#Requires AutoHotkey v2.0

class HotkeyCapture {
    host := 0
    Ctrls := 0

    HkValues := Map()
    CaptureState := 0
    MsgCtrl := 0

    static GLOBAL_HK_KEYS := ["ToggleHotkey", "VoiceLaunchHotkey"]

    __New(host) {
        this.host := host
        this.Ctrls := host.Ctrls
    }

    static IsCaptureKey(k) {
        static captureKeys := Map(
            "ToggleHotkey", 1, "VoiceLaunchHotkey", 1,
            "IMEVoiceHotkey", 1, "IMEHoldHotkey", 1
        )
        if (captureKeys.Has(k))
            return true
        return RegExMatch(k, "^KeySlot\d+$")
    }

    StartHotkeyCapture(configKey, btn, mode, group, msgCtrl := 0, *) {
        this.CancelCapture()
        old := this.HkValues.Has(configKey) ? this.HkValues[configKey] : ""
        ih := InputHook()
        ih.KeyOpt("{All}", "N")
        ih.OnKeyDown := ObjBindMethod(this, "OnCaptureKeyDown")
        ih.OnKeyUp := ObjBindMethod(this, "OnCaptureKeyUp")
        this.MsgCtrl := msgCtrl
        this.CaptureState := { key: configKey, btn: btn, ih: ih, mode: mode, group: group, old: old }
        btn.Text := "请按键..."
        this.ClearCaptureMsg(group)
        ih.Start()
    }

    CancelCapture(restore := true) {
        if (!this.CaptureState)
            return
        state := this.CaptureState
        this.CaptureState := 0
        try state.ih.Stop()
        if (restore)
            state.btn.Text := HotkeyCapture.FormatHotkeyLabel(state.old)
        this.ClearCaptureMsg(state.group)
    }

    FinishCapture(hk) {
        if (!this.CaptureState)
            return
        state := this.CaptureState
        if (hk = "") {
            this.CaptureState := 0
            try state.ih.Stop()
            this.SetHotkeyBtn(state.key, "", state.btn)
            this.ClearCaptureMsg(state.group)
            return
        }
        if (!HotkeyCapture.IsAllowedHotkey(hk, state.mode)) {
            this.ShowCaptureMsg(state.group, "不支持该按键：" HotkeyCapture.FormatHotkeyLabel(hk) "，请重新按键（Esc 取消）")
            return
        }
        conflictKey := this.FindConflict(state.group, hk, state.key)
        if (conflictKey != "") {
            this.ShowCaptureMsg(state.group, "与「" HotkeyCapture.GetHotkeyLabel(conflictKey) "」冲突：" HotkeyCapture.FormatHotkeyLabel(hk) "，请重新按键（Esc 取消）")
            return
        }
        this.CaptureState := 0
        try state.ih.Stop()
        this.SetHotkeyBtn(state.key, hk, state.btn)
        this.ClearCaptureMsg(state.group)
    }

    OnCaptureKeyDown(ih, vk, sc) {
        if (!this.CaptureState)
            return
        if (vk = 0x1B) {
            this.CancelCapture()
            return
        }
        if (vk = 0x08 || vk = 0x2E) {
            this.FinishCapture("")
            return
        }
        mods := ""
        lCtrl := GetKeyState("LControl", "P"), rCtrl := GetKeyState("RControl", "P")
        lAlt := GetKeyState("LAlt", "P"), rAlt := GetKeyState("RAlt", "P")
        lShift := GetKeyState("LShift", "P"), rShift := GetKeyState("RShift", "P")
        lWin := GetKeyState("LWin", "P"), rWin := GetKeyState("RWin", "P")
        if (lCtrl || rCtrl)
            mods .= (rCtrl && !lCtrl) ? ">^" : (lCtrl && !rCtrl) ? "<^" : "^"
        if (lAlt || rAlt)
            mods .= (rAlt && !lAlt) ? ">!" : (lAlt && !rAlt) ? "<!" : "!"
        if (lShift || rShift)
            mods .= (rShift && !lShift) ? ">+" : (lShift && !rShift) ? "<+" : "+"
        if (lWin || rWin)
            mods .= (rWin && !lWin) ? ">#" : (lWin && !rWin) ? "<#" : "#"
        if (HotkeyCapture._IsModVk(vk)) {
            if (!this.CaptureState.HasOwnProp("bareArmed"))
                this.CaptureState.bareArmed := vk
            else
                this.CaptureState.DeleteProp("bareArmed")
            this.CaptureState.btn.Text := "录制中：" HotkeyCapture.FormatHotkeyLabel(mods (this.CaptureState.HasOwnProp("bareArmed") ? HotkeyCapture._BareModName(this.CaptureState.bareArmed) : ""))
            return
        }
        if (this.CaptureState.HasOwnProp("bareArmed"))
            this.CaptureState.DeleteProp("bareArmed")
        keyName := GetKeyName(Format("vk{:X}", vk))
        if (keyName = "")
            return
        this.FinishCapture(mods keyName)
    }

    OnCaptureKeyUp(ih, vk, sc) {
        if (!this.CaptureState)
            return
        if (!this.CaptureState.HasOwnProp("bareArmed") || this.CaptureState.bareArmed != vk)
            return
        state := this.CaptureState
        bareName := HotkeyCapture._BareModName(vk)
        if (bareName = "")
            return
        if (!HotkeyCapture.IsAllowedHotkey(bareName, state.mode)) {
            state.DeleteProp("bareArmed")
            this.ShowCaptureMsg(state.group, "不支持该按键：" bareName "，请重新按键（Esc 取消）")
            return
        }
        conflictKey := this.FindConflict(state.group, bareName, state.key)
        if (conflictKey != "") {
            state.DeleteProp("bareArmed")
            this.ShowCaptureMsg(state.group, "与「" HotkeyCapture.GetHotkeyLabel(conflictKey) "」冲突：" bareName "，请重新按键（Esc 取消）")
            return
        }
        this.CaptureState := 0
        try ih.Stop()
        this.SetHotkeyBtn(state.key, bareName, state.btn)
        this.ClearCaptureMsg(state.group)
    }

    static _IsModVk(vk) {
        return (vk = 0xA0 || vk = 0xA1 || vk = 0xA2 || vk = 0xA3 || vk = 0xA4 || vk = 0xA5 || vk = 0x5B || vk = 0x5C)
    }

    static _BareModName(vk) {
        static m := Map(
            0xA0, "LShift", 0xA1, "RShift",
            0xA2, "LControl", 0xA3, "RControl",
            0xA4, "LAlt", 0xA5, "RAlt",
            0x5B, "LWin", 0x5C, "RWin"
        )
        return m.Has(vk) ? m[vk] : ""
    }

    static IsAllowedHotkey(hk, mode) {
        if (hk = "")
            return true
        static bareMods := Map("LShift",1,"RShift",1,"LControl",1,"RControl",1,"LAlt",1,"RAlt",1,"LWin",1,"RWin",1)
        if (bareMods.Has(hk))
            return (mode != "input")
        mods := "", rest := hk
        while (rest != "" && InStr("^!+#<>", SubStr(rest, 1, 1))) {
            c := SubStr(rest, 1, 1)
            if (c != "<" && c != ">")
                mods .= c
            rest := SubStr(rest, 2)
        }
        if (rest = "")
            return false
        if (mode = "input") {
            if (rest != "Enter" && rest != "NumpadEnter")
                return false
            if (rest = "Enter" && mods = "")
                return false
            return true
        } else {
            return mods != ""
        }
    }

    FindConflict(group, hk, excludeKey) {
        for k, v in this.HkValues {
            if (k = excludeKey || v = "" || v != hk)
                continue
            kIsSlot := RegExMatch(k, "^KeySlot\d+$")
            if ((group = "input") = kIsSlot)
                return k
        }
        return ""
    }

    static GetHotkeyLabel(configKey) {
        static labels := Map(
            "ToggleHotkey", "唤起输入框",
            "VoiceLaunchHotkey", "智慧语音",
            "IMEVoiceHotkey", "输入法语音键·短按",
            "IMEHoldHotkey", "输入法语音键·长按"
        )
        if (labels.Has(configKey))
            return labels[configKey]
        if (RegExMatch(configKey, "^KeySlot(\d+)$", &m))
            return "键位槽 " m[1]
        return configKey
    }
    SetHotkeyBtn(configKey, hk, btn := 0) {
        this.HkValues[configKey] := hk
        label := HotkeyCapture.FormatHotkeyLabel(hk)
        if (IsObject(btn))
            btn.Text := label
        else if (IsObject(this.CaptureState) && this.CaptureState.btn)
            this.CaptureState.btn.Text := label
        if (this.Ctrls.Has(configKey) && IsObject(this.Ctrls[configKey]))
            this.Ctrls[configKey].Text := label
    }

    ShowCaptureMsg(group, msg) {
        if (!IsObject(this.MsgCtrl))
            return
        try
            this.MsgCtrl.Text := msg
    }

    ClearCaptureMsg(group) {
        this.ShowCaptureMsg(group, "")
    }

    static FormatHotkeyLabel(hk) {
        if (hk = "")
            return "未设置"
        static bareLabels := Map(
            "LShift", "左Shift", "RShift", "右Shift",
            "LControl", "左Ctrl", "RControl", "右Ctrl",
            "LAlt", "左Alt", "RAlt", "右Alt",
            "LWin", "左Win", "RWin", "右Win"
        )
        if (bareLabels.Has(hk))
            return bareLabels[hk]
        mods := "", rest := hk
        side := ""
        while (rest != "" && InStr("^!+#<>", SubStr(rest, 1, 1))) {
            c := SubStr(rest, 1, 1)
            rest := SubStr(rest, 2)
            if (c = ">")
                side := "右"
            else if (c = "<")
                side := "左"
            else if (c = "^") {
                mods .= side "Ctrl+", side := ""
            } else if (c = "!") {
                mods .= side "Alt+", side := ""
            } else if (c = "+") {
                mods .= side "Shift+", side := ""
            } else if (c = "#") {
                mods .= side "Win+", side := ""
            }
        }
        if (rest = "")
            return "未设置"
        return mods StrUpper(SubStr(rest, 1, 1)) SubStr(rest, 2)
    }
}
