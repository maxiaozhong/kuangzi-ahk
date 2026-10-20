#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "Actions.ahk"
#Include "NotifyCenter.ahk"
#Include "EntryExecutor.ahk"

global PickerDraft := { Draft: 0, Unchanged: 0 }

class QuickLaunch {
    static OnCompleted := 0
    static QuietPick := false
    static Headless := false
    static _pickerRev := -1

    static Ask(word, rest, deep := false) {
        entry := ""
        if ConfigManager.WordMap.Has(word)
            entry := ConfigManager.WordMap[word]
        else {
            ci := this.FindAppCI(word)
            if (ci != "") {
                word := ci
                entry := ConfigManager.WordMap[ci]
            }
        }
        if (entry != "" && rest = "" && QuickLaunch._WordRejects(entry))
            return ""
        if (entry != "")
            return { word: word, rest: rest, entry: entry }
        if (!deep)
            return ""
        cands := []
        for k, e in ConfigManager.WordMap {
            if (InStr(k, word))
                cands.Push({ key: k, entry: e })
        }
        if (cands.Length = 1)
            return { word: cands[1].key, rest: rest, entry: cands[1].entry }
        if (cands.Length >= 2)
            return { word: word, rest: rest, entry: "", cands: cands }
        return ""
    }

    static _WordRejects(entry) {
        if (Type(entry) != "Object" || entry.type != "action")
            return false
        if (entry.HasOwnProp("home"))
            return false
        tgt := entry.HasOwnProp("target") ? entry.target : ""
        a := Actions.Get(tgt)
        return (a != "" && a.HasOwnProp("textAction") && a.textAction)
    }

    static Execute(input) {
        ConfigManager.EnsureLoaded()
        if (input = "")
            return Utils.ResErr("", "launch", true)

        word := input, rest := ""
        SpacePos := InStr(input, " ")
        if (SpacePos) {
            word := Trim(SubStr(input, 1, SpacePos - 1))
            rest := Trim(SubStr(input, SpacePos + 1))
        }

        m := this.Ask(word, rest, true)
        if (m != "" && m.HasOwnProp("cands")) {
            this.ShowAppPicker(m.cands, rest)
            return Utils.ResPending("launch")
        }

        if (m = "") {
            if (rest = "") {
                e := QuickSearch.FindEngineCI(word)
                if (e != "" && e.HasOwnProp("home"))
                    return this.RunTarget(e.home)
            }
            return Utils.ResErr(word, "launch", false, "ERR_NO_APP")
        }
        return EntryExecutor.Execute(m.entry, m.word, m.rest)
    }

    static RunTarget(target) {
        TargetPath := this.ResolveAppPath(target)

        if (InStr(TargetPath, "://") || SubStr(StrLower(TargetPath), 1, 4) = "www.") {
            try {
                Run(TargetPath)
                return Utils.ResOk("run")
            } catch as e {
                return Utils.ResErr(TargetPath "`n`n" e.Message, "run", false, "ERR_APP_RUN")
            }
        }

        SplitPath(TargetPath, &exeName, , &ext)
        if (exeName != "" && ext = ".exe") {
            DetectHiddenWindows(true)
            hwnd := WinExist("ahk_exe " exeName)
            if (hwnd) {
                try {
                    if (WinGetMinMax("ahk_id " hwnd) = -1)
                        WinRestore("ahk_id " hwnd)
                    WinShow("ahk_id " hwnd)
                    WinActivate("ahk_id " hwnd)
                    WinWaitActive("ahk_id " hwnd,, 2)
                    DetectHiddenWindows(false)
                    return Utils.ResOk("run")
                } catch {
                }
            }
            DetectHiddenWindows(false)
        }

        try {
            Run(TargetPath)
            if (exeName != "" && ext = ".exe") {
                try WinWait("ahk_exe " exeName,, 3)
                try WinActivate("ahk_exe " exeName)
            }
            return Utils.ResOk("run")
        } catch as e {
            return Utils.ResErr(TargetPath "`n`n" e.Message, "run", false, "ERR_APP_RUN")
        }
    }

    static FindAppCI(cmd) {
        for k, v in ConfigManager.WordMap {
            if (StrCompare(k, cmd) = 0)
                return k
        }
        return ""
    }

    static GetUniqueKeyword(base) {
        ConfigManager.EnsureLoaded()
        if (this.FindAppCI(base) = "")
            return base
        i := 2
        while (this.FindAppCI(base i) != "")
            i++
        return base i
    }

    static ShowAppPicker(cands, rest := "") {
        if (this.Headless)
            return
        this._pickerRev := this._DraftRevNow()
        m := Menu()
        for c in cands {
            if (c.HasOwnProp("entry"))
                m.Add(c.key, ObjBindMethod(this, "PickerLaunch", c.entry, c.key, rest))
            else
                m.Add(c.key, ObjBindMethod(this, "PickerRunTarget", c.target))
        }
        m.Show()
    }

    static _DraftRevNow() {
        fn := PickerDraft.Draft
        return fn ? fn.Call() : -1
    }

    static _PickerDraftUnchanged() {
        fn := PickerDraft.Unchanged
        return (fn && this._pickerRev >= 0) ? fn.Call(this._pickerRev) : false
    }

    static PickerRunTarget(target, *) {
        res := this.RunTarget(target)
        if (this.QuietPick || !this._PickerDraftUnchanged()) {
            this.QuietPick := false
            NotifyCenter.FromResult(res)
            return
        }
        if (this.OnCompleted)
            (this.OnCompleted)(res)
    }

    static PickerLaunch(entry, key, rest := "", *) {
        res := EntryExecutor.Execute(entry, key, rest)
        if (this.QuietPick || !this._PickerDraftUnchanged()) {
            this.QuietPick := false
            NotifyCenter.FromResult(res)
            return
        }
        if (this.OnCompleted)
            (this.OnCompleted)(res)
    }

    static ResolveAppPath(path) {
        static A_Vars := Map(
            "A_Desktop", A_Desktop, "A_MyDocuments", A_MyDocuments,
            "A_UserProfile", EnvGet("USERPROFILE"), "A_AppData", A_AppData, "A_Temp", A_Temp)
        if RegExMatch(path, "^A_\w+$", &m) && A_Vars.Has(m[0])
            return A_Vars[m[0]]
        if RegExMatch(path, '^(A_\w+)\\(.+)$', &m) && A_Vars.Has(m[1])
            return A_Vars[m[1]] "\" m[2]
        return path
    }
}

Actions.RegisterRoute("run", "打开", "▶", (c) => QuickLaunch.RunTarget(c.param))
