#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "QuickLaunch.ahk"
#Include "LocalAppCatalog.ahk"
#Include "BookmarkCatalog.ahk"

class CatalogHub {
    static MAX_CANDS := 5

    static RunDomain(word, domainClass, domainLabel) {
        res := domainClass.Lookup(Trim(word))
        if (IsObject(res)) {
            out := []
            for c in res
                out.Push(this._PickerItem(c, domainLabel))
            QuickLaunch.ShowAppPicker(out)
            return Utils.ResPending("launch")
        }
        if (res != "")
            return QuickLaunch.RunTarget(res)
        return Utils.ResErr(word, "launch", false, "ERR_NO_APP")
    }

    static _PickerItem(c, domainLabel) {
        label := (c.HasOwnProp("mount") && c.mount != "") ? c.key " (" c.mount ")" : c.key " (" domainLabel ")"
        return { key: label, target: c.target }
    }

    static Lookup(word) {
        if (word = "")
            return ""
        all := []
        this._Collect(word, BookmarkCatalog, "书签", &all)
        this._Collect(word, LocalAppCatalog, "应用", &all)
        if (all.Length = 0)
            return ""
        this._Sort(all)
        if (all.Length = 1)
            return all[1].target
        exact := []
        for c in all {
            if (c.score >= 100)
                exact.Push(c)
        }
        if (exact.Length = 1)
            return exact[1].target
        out := []
        n := all.Length < this.MAX_CANDS ? all.Length : this.MAX_CANDS
        Loop n
            out.Push({ key: all[A_Index].key " (" all[A_Index].domain ")", target: all[A_Index].target })
        return out
    }

    static _Collect(word, domainClass, domainLabel, &all) {
        res := domainClass.Lookup(word)
        if (res = "")
            return
        if (IsObject(res)) {
            for c in res
                all.Push({ key: c.key, target: c.target, domain: domainLabel, score: this._Score(word, c.key) })
        } else {
            all.Push({ key: word, target: res, domain: domainLabel, score: this._Score(word, word) })
        }
    }

    static _Score(word, key) {
        if (StrCompare(word, key) = 0)
            return 100
        if (StrCompare(SubStr(key, 1, StrLen(word)), word) = 0)
            return 80 + Round(StrLen(word) / StrLen(key) * 10)
        return 60 + Round(StrLen(word) / StrLen(key) * 10)
    }

    static _Sort(&arr) {
        Utils.SortBy(arr, (a) => a.score, true)
    }
}
