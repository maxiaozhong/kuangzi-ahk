#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "QuickSearch.ahk"
#Include "QuickLaunch.ahk"
#Include "Actions.ahk"
#Include "PluginManager.ahk"

class Lexicon {
    static Host := 0

    static BUILTIN := Map(
        "搜索",       { type: "action", target: "search"   },
        "待办",       { type: "action", target: "todo"     },
        "速记",       { type: "action", target: "note"     },
        "日记",       { type: "action", target: "openNote" },
        "目录",       { type: "action", target: "openDir"  },
        "书签",       { type: "action", target: "bookmark" },
        "应用|软件",  { type: "action", target: "localapp" },
        "path",       { type: "action", target: "path"     },
        "新建",       { type: "action", target: "newNote"  })

    static _Expanded := false

    static BuiltinMap() {
        if (Lexicon._Expanded != false)
            return Lexicon._Expanded
        m := Map()
        for k, e in Lexicon.BUILTIN {
            Loop Parse, k, "|" {
                key := Trim(A_LoopField)
                if (key != "")
                    m[key] := e
            }
        }
        Lexicon._Expanded := m
        return m
    }

    static Split(input) {
        s := Trim(input), word := s, rest := ""
        if (p := InStr(s, " ")) {
            word := Trim(SubStr(s, 1, p - 1))
            rest := Trim(SubStr(s, p + 1))
        }
        return { word: word, rest: rest }
    }

    static AskBuiltin(word, rest) {
        bm := this.BuiltinMap()
        if (!bm.Has(word))
            return ""
        e := bm[word]
        if (rest != "")
            return { word: word, rest: rest, entry: e }
        a := Actions.Get(e.target)
        if (a = "")
            return { word: word, rest: rest, entry: e }
        if (a.HasOwnProp("textAction") && a.textAction) {
            if (a.HasOwnProp("allowEmpty") && a.allowEmpty)
                return { word: word, rest: rest, entry: e }
            if (a.HasOwnProp("engineCfg") && ActionBindings._EngineHasHome(a.engineCfg, ""))
                return { word: word, rest: rest, entry: e }
            return ""
        }
        return { word: word, rest: rest, entry: e }
    }

    static Match(input, deep := false) {
        ConfigManager.EnsureLoaded()
        parts := this.Split(input)
        word := parts.word, rest := parts.rest
        if (word = "")
            return ""

        m := this.AskBuiltin(word, rest)
        if (m != "")
            return { src: "builtin", word: m.word, rest: m.rest, entry: m.entry }

        m := QuickSearch.Ask(word, rest)
        if (m != "")
            return { src: "engine", word: m.word, rest: m.rest, entry: m.entry }

        m := QuickLaunch.Ask(word, rest, deep)
        if (m != "")
            return { src: "word", word: m.word, rest: m.rest, entry: m.entry
                , cands: m.HasOwnProp("cands") ? m.cands : unset }

        m := PluginManager.Ask(word, rest)
        if (m != "")
            return { src: "plugin", word: m.word, rest: m.rest, entry: m.entry }

        return ""
    }

    static Resolve(input, source := "route", deep := false) {
        m := this.Match(input, deep)
        if (m = "")
            return ""

        res := ""
        if (m.src = "builtin")
            res := EntryExecutor.Execute(m.entry, m.word, m.rest, this.Host)
        else if (m.src = "engine")
            res := this._RunEngine(m)
        else if (m.src = "word")
            res := this._RunWord(m)
        else if (m.src = "plugin")
            res := PluginManager.InvokeByDecision(m.entry, m.rest, source, m.word)

        if (IsObject(res) && res.ok && res.action = "empty")
            return Utils.ResOk("empty", m.word)
        return res
    }

    static ResolveSearchBody(body) {
        ConfigManager.EnsureLoaded()
        b := Trim(body)
        if (b = "")
            return ""
        parts := this.Split(b)
        e := QuickSearch.FindEngineCI(parts.word)
        if (e != "")
            return this._RunEngine({ src: "engine", word: parts.word, rest: parts.rest
                , entry: e }, true)
        return Actions.Run("search", { text: b, host: this.Host })
    }

    static _RunEngine(m, force := false) {
        if (m.rest != "")
            return Actions.Run("search", { text: m.rest, param: m.word, host: this.Host })
        if (m.entry.HasOwnProp("home"))
            return QuickLaunch.RunTarget(m.entry.home)
        if (force)
            return QuickSearch.ExecuteEntry(m.entry, "", "search")
        return ""
    }

    static _RunWord(m) {
        if (m.HasOwnProp("cands")) {
            if (!QuickLaunch.Headless)
                QuickLaunch.ShowAppPicker(m.cands, m.rest)
            return Utils.ResPending("launch")
        }
        return EntryExecutor.Execute(m.entry, m.word, m.rest, this.Host)
    }

    static FindIn(sentence) {
        ConfigManager.EnsureLoaded()
        out := []
        bm := this.BuiltinMap()
        for k, e in bm {
            p := InStr(sentence, k)
            if (p > 0)
                out.Push({ src: "builtin", word: k, pos: p, len: StrLen(k), entry: e })
        }
        for k, e in ConfigManager.EngineMap {
            p := InStr(sentence, k)
            if (p > 0)
                out.Push({ src: "engine", word: k, pos: p, len: StrLen(k), entry: e })
        }
        for k, e in ConfigManager.WordMap {
            p := InStr(sentence, k)
            if (p > 0)
                out.Push({ src: "word", word: k, pos: p, len: StrLen(k), entry: e })
        }
        for k, gid in PluginManager.KeywordMap {
            p := InStr(sentence, k)
            if (p > 0)
                out.Push({ src: "plugin", word: k, pos: p, len: StrLen(k), entry: gid })
        }
        return out
    }
}
