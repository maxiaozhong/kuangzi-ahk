#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "QuickLaunch.ahk"
#Include "EntryExecutor.ahk"
#Include "QuickSearch.ahk"
#Include "QuickNote.ahk"
#Include "Actions.ahk"
#Include "NotifyCenter.ahk"
#Include "Lexicon.ahk"

class VoiceRouter {
    static Host := 0

    static _trace := ""

    static Clean(text) {
        text := RegExReplace(text, "[。，、！？\.\,\!\?\s]+", "")
        text := RegExReplace(text, "(吧|呢|啊|呀|哦|哈|一下)$", "")
        return Trim(text)
    }

    static Process(text) {
        ConfigManager.EnsureLoaded()
        t := VoiceRouter.Analyze(text)
        return VoiceRouter.Run(t)
    }

    static Analyze(text) {
        s := VoiceRouter.Clean(text)
        t := { stage: "clean", raw: text, cleaned: s, winner: "", rest: "", second: "" }
        if (s = "")
            return t

        cands := Lexicon.FindIn(s)
        vr := ConfigManager.VoiceRouteMap
        for k, e in vr {
            p := InStr(s, k)
            if (p > 0) {
                tgt := (Type(e) = "Object" && e.HasOwnProp("target")) ? e.target : ""
                prm := (Type(e) = "Object" && e.HasOwnProp("param")) ? e.param : ""
                rsc := (Type(e) = "Object" && e.HasOwnProp("rescan")) ? e.rescan : true
                cands.Push({ src: "route", word: k, pos: p, len: StrLen(k)
                    , kind: (tgt = "launch") ? 1 : 0, prio: 1
                    , target: tgt, param: prm, rescan: rsc, entry: e })
            }
        }
        winN := ConfigManager.Get("VoiceWindow", 6)
        best := ""
        for c in cands {
            if (c.pos > winN)
                continue
            if (c.HasOwnProp("kind") = false)
                c.kind := 0
            if (best = "" || c.kind < best.kind
                || (c.kind = best.kind && (c.pos < best.pos
                    || (c.pos = best.pos && (c.len > best.len
                        || (c.len = best.len && Utils.ObjGet(c, "prio", 0) > Utils.ObjGet(best, "prio", 0)))))))
                best := c
        }
        if (best = "") {
            t.stage := "fallback"
            return t
        }

        raw := Trim(SubStr(s, best.pos + best.len))
        t.restRaw := raw
        rest := VoiceRouter._TrimFillers(raw, VoiceRouter._EntryFillers(best.entry))

        if (best.kind = 0) {
            t.stage := "hit"
            t.winner := best, t.rest := rest
            return t
        }
        if (best.rescan != false && rest != "") {
            s2 := VoiceRouter._FindSecond(rest)
            if (s2 != "") {
                t.stage := "second"
                t.winner := best, t.rest := rest, t.second := s2
                return t
            }
        }
        t.stage := "hit"
        t.winner := best, t.rest := rest
        return t
    }

    static _FindSecond(rest) {
        cands := Lexicon.FindIn(rest)
        vr := ConfigManager.VoiceRouteMap
        for k, e in vr {
            tgt := (Type(e) = "Object" && e.HasOwnProp("target")) ? e.target : ""
            if (tgt = "launch")
                continue
            p := InStr(rest, k)
            if (p > 0)
                cands.Push({ src: "route", word: k, pos: p, len: StrLen(k)
                    , kind: 0, target: tgt, prio: 1
                    , param: (Type(e) = "Object" && e.HasOwnProp("param")) ? e.param : ""
                    , rescan: true, entry: e })
        }
        best := ""
        for c in cands {
            if (c.HasOwnProp("kind") = false)
                c.kind := 0
            if (best = "" || c.pos < best.pos
                || (c.pos = best.pos && (c.len > best.len
                    || (c.len = best.len && Utils.ObjGet(c, "prio", 0) > Utils.ObjGet(best, "prio", 0)))))
                best := c
        }
        return best
    }

    static Run(t) {
        if (t.stage = "clean" || (t.stage = "fallback" && t.cleaned = ""))
            return Utils.ResOk("empty")

        if (t.stage = "fallback") {
            fb := ConfigManager.Get("VoiceFallbackAction", "search")
            if (fb = "" || fb = "none")
                return Utils.ResOk("none")
            return Actions.Run(fb, { text: t.cleaned, host: this.Host, source: "voice" })
        }

        w := t.winner
        if (t.stage = "second") {
            s2 := t.second
            res := VoiceRouter._DispatchWord(s2, s2rest(t.cleaned, s2))
            if (IsObject(res) && res.ok)
                VoiceRouter._Echo(s2.word, res)
            return res
        }

        if (w.src = "route") {
            res := VoiceRouter._RunRoute(w, t.rest)
            if (IsObject(res) && res.ok && res.action != "empty")
                VoiceRouter._Echo(w.word, res)
            return res
        }
        res := VoiceRouter._DispatchWord(w, t.rest)
        if (IsObject(res) && res.ok && res.action != "empty")
            VoiceRouter._Echo(w.word, res)
        return res

        s2rest(full, s2) {
            r := Trim(SubStr(full, s2.pos + s2.len))
            return VoiceRouter._TrimFillers(r, VoiceRouter._EntryFillers(s2.entry))
        }
    }

    static _DispatchWord(c, rest) {
        switch c.src {
            case "builtin":
                return EntryExecutor.Execute(c.entry, c.word, rest, Lexicon.Host)
            case "engine":
                if (rest != "")
                    return Actions.Run("search", { text: rest, param: c.word, host: Lexicon.Host, source: "voice" })
                if (c.entry.HasOwnProp("home"))
                    return QuickLaunch.RunTarget(c.entry.home)
                return ""
            case "word":
                return EntryExecutor.Execute(c.entry, c.word, rest, Lexicon.Host)
            case "plugin":
                return PluginManager.InvokeByDecision(c.entry, rest, "voice", c.word)
        }
        return Utils.ResErr(c.word, "voice", false, "ERR_VOICE_CMD")
    }

    static _RunRoute(w, rest) {
        id := w.target
        a := Actions.Get(id)
        if (a = "" || a.kind = "entry")
            return Utils.ResErr(id, "", false, "ERR_VOICE_CMD")
        if (!a.HasOwnProp("textAction") && VoiceRouter.Host = 0)
            return Utils.ResErr(id, "", false, "ERR_VOICE_CMD")
        return Actions.Run(id, { text: rest, param: w.param, host: VoiceRouter.Host, source: "voice" })
    }

    static _Echo(word, res) {
        brief := (res.HasOwnProp("text") && Trim(res.text) != "") ? "「" Trim(res.text) "」" : ""
        label := Map("note", "记入速记", "todo", "记入待办", "search", "已搜索"
            , "run", "已打开", "launch", "已启动", "send", "已执行按键")
        act := (res.action != "" && label.Has(res.action)) ? label[res.action] : "已执行"
        NotifyCenter.Send("info", "语音 · " act, word (brief != "" ? " " brief : ""))
    }

    static _TrimFillers(rest, extra := []) {
        words := []
        for fw in ConfigManager.Get("VoiceFillerWords", ConfigManager.GetDefaultFillerWords())
            words.Push(fw)
        for fw in extra
            words.Push(fw)
        fillerWords := VoiceRouter._SortByLenDesc(words)
        loop {
            changed := false
            for fw in fillerWords {
                if (fw != "" && SubStr(rest, 1, StrLen(fw)) = fw) {
                    rest := Trim(SubStr(rest, StrLen(fw) + 1))
                    changed := true
                    break
                }
            }
            if (!changed)
                break
        }
        rest := RegExReplace(rest, "(吧|呢|啊|呀|哦|哈|一下)$", "")
        return Trim(rest)
    }

    static _EntryFillers(entry) {
        f := Utils.ObjGet(entry, "fillers", [])
        return (Type(f) = "Array") ? f : []
    }

    static TraceSteps(text) {
        t := VoiceRouter.Analyze(text)
        t.fallback := ConfigManager.Get("VoiceFallbackAction", "search")
        return t
    }

    static _SortByLenDesc(arr) {
        out := []
        for v in arr
            out.Push(v)
        return Utils.SortBy(out, (k) => StrLen(k), true)
    }
}

Actions.RegisterRoute("voiceRoute", "智能语音路由", "🗣", (c) => VoiceRouter.Process(c.text))
