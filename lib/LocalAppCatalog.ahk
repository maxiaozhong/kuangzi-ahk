#Requires AutoHotkey v2.0

class LocalAppCatalog {
    static _map := false
    static _scanned := false

    static Lookup(word) {
        if (word = "")
            return ""
        if (!this._scanned)
            this.Scan()
        if (this._map.Has(word))
            return this._map[word]
        for k, v in this._map {
            if (StrCompare(k, word) = 0)
                return v
        }
        cands := []
        for k, v in this._map {
            if (StrCompare(SubStr(k, 1, StrLen(word)), word) = 0)
                cands.Push({ key: k, target: v })
        }
        if (cands.Length = 1)
            return cands[1].target
        if (cands.Length > 1)
            return cands
        for k, v in this._map {
            if (InStr(k, word))
                cands.Push({ key: k, target: v })
        }
        if (cands.Length = 1)
            return cands[1].target
        if (cands.Length > 1)
            return cands
        return ""
    }

    static Scan() {
        this._map := Map()
        this._scanned := true
        this._ScanDir(A_ProgramsCommon)
        this._ScanDir(A_Programs)
    }

    static _ScanDir(dir) {
        if !DirExist(dir)
            return
        Loop Files, dir "\*.lnk", "R" {
            name := StrReplace(A_LoopFileName, ".lnk", "")
            if (name = "" || this._map.Has(name))
                continue
            try {
                FileGetShortcut(A_LoopFilePath, &target)
                if (target = "")
                    continue
                exeName := ""
                SplitPath(target, &exeName)
                if (RegExMatch(exeName, "i)^unins|^uninstall|^help"))
                    continue
                this._map[name] := target
            } catch {
            }
        }
    }
}
