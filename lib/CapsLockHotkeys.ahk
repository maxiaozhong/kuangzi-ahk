#Requires AutoHotkey v2.0
#Include "ConfigManager.ahk"
#Include "QuickNote.ahk"

class CapsLockHotkeys {
    static _quickKeys := []
    static _map := Map()
    static _prefixes := Map()
    static _pending := ""
    static _token := 0
    static _host := 0
    static _WAIT_MS := 400

    static SYMBOL_KEYS := Map("space", "Space", ".", ".", "/", "/", "``", "``", ",", ",")

    static Register(host) {
        CapsLockHotkeys._host := host
        CapsLockHotkeys._ApplyQuickKeys()

        Hotkey("+CapsLock", (*) => CapsLockHotkeys._ToggleCapsLock(), "On")
    }

    static ReRegisterQuickKeys(host) {
        CapsLockHotkeys._host := host
        CapsLockHotkeys._ResetPending()
        CapsLockHotkeys._ApplyQuickKeys()
    }

    static ParseActions(actions) {
        result := Map()
        prefixes := Map()
        for s in actions {
            if (Type(s) != "Object" && Type(s) != "Map")
                continue
            key := StrLower(Trim(Type(s) = "Map" ? (s.Has("key") ? s["key"] : "") : (s.HasOwnProp("key") ? s.key : "")))
            act := Trim(Type(s) = "Map" ? (s.Has("action") ? s["action"] : "") : (s.HasOwnProp("action") ? s.action : ""))
            if (key = "" || act = "")
                continue
            result[key] := act
            if (StrLen(key) = 2)
                prefixes[SubStr(key, 1, 1)] := true
        }
        return { map: result, prefixes: prefixes }
    }

    static RegisteredLetters(keyMap, reserved) {
        letters := Map()
        for key, keyword in keyMap {
            len := StrLen(key)
            if (len < 1 || len > 2)
                continue
            Loop len {
                ch := SubStr(key, A_Index, 1)
                if (!reserved.Has(ch))
                    letters[ch] := true
            }
        }
        return letters
    }

    static _ApplyQuickKeys() {
        raw := ConfigManager.Get("CapsLockActions")
        actions := CapsLockHotkeys._NormalizeActions(raw)
        if (actions !== raw) {
            ConfigManager.Set("CapsLockActions", actions)
            ConfigManager.Save()
        }
        parsed := CapsLockHotkeys.ParseActions(actions)
        CapsLockHotkeys._map := parsed.map
        CapsLockHotkeys._prefixes := parsed.prefixes

        for hk in CapsLockHotkeys._quickKeys
            try Hotkey(hk, "Off")
        CapsLockHotkeys._quickKeys := []

        for key, act in CapsLockHotkeys._map {
            if (!CapsLockHotkeys.SYMBOL_KEYS.Has(key))
                continue
            hk := "CapsLock & " CapsLockHotkeys.SYMBOL_KEYS[key]
            try {
                Hotkey(hk, CapsLockHotkeys._MakeDispatchHandler(act), "On")
                CapsLockHotkeys._quickKeys.Push(hk)
            }
        }

        reserved := Map("space", 1, ".", 1, "/", 1, "``", 1, ",", 1)
        for letter, _ in CapsLockHotkeys.RegisteredLetters(CapsLockHotkeys._map, reserved) {
            hk := "CapsLock & " letter
            try {
                Hotkey(hk, CapsLockHotkeys._MakeLetterHandler(letter), "On")
                CapsLockHotkeys._quickKeys.Push(hk)
            }
        }
    }

    static _NormalizeActions(raw) {
        presets := Map(
            "space", "toggleMain",
            "/", "openDir")
        out := []
        if (Type(raw) = "Array") {
            for s in raw {
                if (Type(s) != "Object" && Type(s) != "Map")
                    continue
                k := StrLower(Trim(Type(s) = "Map" ? (s.Has("key") ? s["key"] : "") : (s.HasOwnProp("key") ? s.key : "")))
                a := Trim(Type(s) = "Map" ? (s.Has("action") ? s["action"] : "") : (s.HasOwnProp("action") ? s.action : ""))
                lk := Type(s) = "Map" ? (s.Has("locked") ? !!s["locked"] : false) : (s.HasOwnProp("locked") ? !!s.locked : false)
                if (k = "" || a = "")
                    continue
                if (presets.Has(k)) {
                    a := presets[k]
                    lk := true
                }
                out.Push({ key: k, action: a, locked: lk })
            }
        } else if (Type(raw) = "Map") {
            m := raw
            for k, v in m {
                k := StrLower(Trim(k))
                if (k = "" || Type(v) != "String" || v = "")
                    continue
                if (InStr(v, "."))
                    out.Push({ key: k, action: v })
                else if (ConfigManager.WordMap.Has(v))
                    out.Push({ key: k, action: "word." v })
                else if (ConfigManager.EngineMap.Has(v))
                    out.Push({ key: k, action: "eng." v })
                else
                    out.Push({ key: k, action: v })
            }
        }
        for pk, pa in presets {
            has := false
            for s in out {
                if (s.key = pk) {
                    has := true
                    break
                }
            }
            if (!has)
                out.Push({ key: pk, action: pa, locked: true })
        }
        return out
    }

    static _MakeLetterHandler(head) {
        return (*) => CapsLockHotkeys._OnLetter(head)
    }

    static _MakeDispatchHandler(act) {
        return (*) => CapsLockHotkeys._Dispatch(act)
    }

    static _OnLetter(letter) {
        if (CapsLockHotkeys._pending != "") {
            first := CapsLockHotkeys._pending
            combo := first . letter
            CapsLockHotkeys._ResetPending()
            if (CapsLockHotkeys._map.Has(combo)) {
                CapsLockHotkeys._Dispatch(CapsLockHotkeys._map[combo])
                return
            }
            if (CapsLockHotkeys._map.Has(first))
                CapsLockHotkeys._Dispatch(CapsLockHotkeys._map[first])
        }

        if (CapsLockHotkeys._prefixes.Has(letter)) {
            CapsLockHotkeys._pending := letter
            CapsLockHotkeys._token += 1
            token := CapsLockHotkeys._token
            SetTimer(() => CapsLockHotkeys._Flush(token), -CapsLockHotkeys._WAIT_MS)
            return
        }

        if (CapsLockHotkeys._map.Has(letter))
            CapsLockHotkeys._Dispatch(CapsLockHotkeys._map[letter])
    }

    static _Flush(token, *) {
        if (token != CapsLockHotkeys._token)
            return
        if (CapsLockHotkeys._pending = "")
            return
        letter := CapsLockHotkeys._pending
        CapsLockHotkeys._pending := ""
        if (CapsLockHotkeys._map.Has(letter))
            CapsLockHotkeys._Dispatch(CapsLockHotkeys._map[letter])
    }

    static _ResetPending() {
        CapsLockHotkeys._token += 1
        CapsLockHotkeys._pending := ""
    }

    static _Dispatch(actionId) {
        if (actionId = "" || !CapsLockHotkeys._host)
            return
        CapsLockHotkeys._host.QuickLaunchAction(actionId)
    }

    static _ToggleCapsLock() {
        SetCapsLockState(!GetKeyState("CapsLock", "T"))
    }
}
