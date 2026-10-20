#Requires AutoHotkey v2.0
#Include "ConfigManager.ahk"

class PathCatalog {
    static _index := false
    static _topIndex := false
    static _scannedMtime := ""

    static PathDir() {
        return AppPaths.PathDir()
    }

    static LnkDir() {
        return this.PathDir() "\lnk"
    }

    static Lookup(word) {
        if (word = "")
            return ""
        this._EnsureFresh()
        res := this._Fold(this._ExactOf(this._index, word))
        if (IsObject(res))
            return res
        if (res != "")
            return res
        res := this._Fold(this._MatchLayer(word, true))
        if (Type(res) = "String" && res != "")
            return res
        if (IsObject(res))
            return res
        res := this._Fold(this._MatchLayer(word, false))
        return res
    }

    static _ExactOf(idx, word) {
        if (idx.Has(word))
            return idx[word]
        for k, v in idx {
            if (StrCompare(k, word) = 0)
                return v
        }
        return []
    }

    static TopEntries() {
        this._EnsureFresh()
        out := []
        for _, ent in this._topIndex
            out.Push(ent)
        return out
    }

    static AddTarget(targetPath) {
        targetPath := Trim(targetPath)
        if (targetPath = "")
            return "路径为空"
        if !FileExist(targetPath)
            return "目标不存在: " targetPath
        SplitPath(targetPath, &name)
        if (name = "")
            return "无法从路径取名字: " targetPath
        if DirExist(targetPath) {
            root := RTrim(this.PathDir(), "\")
            tgt := RTrim(targetPath, "\")
            if (tgt = root || SubStr(tgt, 1, StrLen(root) + 1) = root "\")
                return "不能挂载 path 目录自身或其子目录"
        }
        dir := this.LnkDir()
        if !DirExist(dir)
            DirCreate(dir)
        lnk := dir "\" name ".lnk"
        try {
            FileCreateShortcut(targetPath, lnk)
        } catch as e {
            return "创建快捷方式失败: " e.Message
        }
        this._Invalidate()
        return ""
    }

    static RemoveByWord(word) {
        this._EnsureFresh()
        for _, ent in this._topIndex {
            if (StrCompare(ent.key, word) = 0 && ent.srcFile != "") {
                if (InStr(ent.srcFile, this.LnkDir() "\") != 1)
                    return "词 '" word "' 是手放文件（不在 lnk 子层），请在资源管理器手动删除"
                try {
                    FileDelete(ent.srcFile)
                    this._Invalidate()
                    return ""
                } catch as e {
                    return "删除失败: " e.Message
                }
            }
        }
        return "未找到词: " word
    }

    static RenameMount(oldWord, newWord) {
        this._EnsureFresh()
        for _, ent in this._topIndex {
            if (StrCompare(ent.key, oldWord) = 0 && ent.srcFile != "") {
                if (InStr(ent.srcFile, this.LnkDir() "\") != 1)
                    return "词 '" oldWord "' 是手放文件，请在资源管理器重命名"
                if !DirExist(ent.target)
                    return "词 '" oldWord "' 是文件挂载（词=目标文件名，由身份决定），如需别名请先移除再以目录挂载"
                if (newWord = "" || InStr(newWord, "\") || InStr(newWord, "/"))
                    return "新词非法（空或含路径分隔符）: " newWord
                for k, _ in this._index {
                    if (StrCompare(k, newWord) = 0)
                        return "新词已存在: " newWord
                }
                newLnk := this.LnkDir() "\" newWord ".lnk"
                if (FileExist(newLnk))
                    return "新词已存在: " newWord
                try {
                    FileMove(ent.srcFile, newLnk)
                } catch as e {
                    return "重命名失败: " e.Message
                }
                this._Invalidate()
                return ""
            }
        }
        return "未找到词: " oldWord
    }

    static _EnsureFresh() {
        rootM := this._DirMtime(this.PathDir())
        lnkM := this._DirMtime(this.LnkDir())
        if (this._index = false || rootM "|" lnkM != this._scannedMtime)
            this.Scan()
    }

    static _DirMtime(dir) {
        return DirExist(dir) ? FileGetTime(dir, "M") : ""
    }

    static _Invalidate() {
        this._scannedMtime := ""
    }

    static Scan() {
        idx := Map()
        top := Map()
        root := this.PathDir()
        this._scannedMtime := this._DirMtime(root) "|" this._DirMtime(this.LnkDir())
        this._index := idx
        this._topIndex := top
        if !DirExist(root)
            return
        this._ScanLayer(root, idx, top, true)
        this._ScanLayer(this.LnkDir(), idx, top, false)
    }

    static _ScanLayer(dir, idx, top, isRoot) {
        if !DirExist(dir)
            return
        dirLen := StrLen(dir)
        Loop Files, dir "\*", "R" {
            full := A_LoopFileFullPath
            if (InStr(StrReplace(SubStr(full, dirLen + 2), "\", "/"), "/"))
                continue
            name := A_LoopFileName
            if (SubStr(name, 1, 1) = ".")
                continue
            if (A_LoopFileAttrib ~= "D")
                continue
            if (SubStr(name, -4) = ".lnk") {
                kw := SubStr(name, 1, StrLen(name) - 4)
                if (kw = "")
                    continue
                target := this._ResolveLnk(full)
                if (target = "")
                    continue
                if DirExist(target) {
                    this._AddEntry(idx, top, kw, target, kw, full)
                    this._IndexMount(idx, target, kw)
                } else {
                    tgtName := ""
                    SplitPath(target, &tgtName)
                    this._AddEntry(idx, top, (tgtName != "" ? tgtName : kw), target, "", full)
                }
            } else {
                this._AddEntry(idx, top, name, full, "", full)
            }
        }
    }

    static _IndexMount(idx, mountDir, mountName) {
        mLen := StrLen(mountDir)
        Loop Files, mountDir "\*", "R" {
            full := A_LoopFileFullPath
            if (A_LoopFileAttrib ~= "D")
                continue
            rel := SubStr(full, mLen + 2)
            if (this._Pruned(rel))
                continue
            if (this._DepthOf(rel) > this.MAX_DEPTH)
                continue
            if (SubStr(A_LoopFileName, 1, 1) = ".")
                continue
            this._AddEntry(idx, 0, A_LoopFileName, full, mountName, "")
        }
    }

    static MAX_DEPTH := 8

    static _DepthOf(relPath) {
        n := 0
        Loop Parse, relPath, "\"
            n++
        return n - 1
    }

    static _Pruned(relPath) {
        static PRUNE := Map(
            "node_modules", 1, ".git", 1, "dist", 1, "build", 1
            , ".venv", 1, "__pycache__", 1, "$RECYCLE.BIN", 1, "System Volume Information", 1)
        Loop Parse, relPath, "\"
            if (PRUNE.Has(A_LoopField))
                return true
        return false
    }

    static _ResolveLnk(lnkPath) {
        try {
            FileGetShortcut(lnkPath, &target)
            return (target != "" && FileExist(target)) ? target : ""
        } catch {
            return ""
        }
    }

    static _AddEntry(idx, top, kw, target, mount, srcFile) {
        ent := { key: kw, target: target, mount: mount, srcFile: srcFile }
        if !idx.Has(kw)
            idx[kw] := []
        idx[kw].Push(ent)
        if (IsObject(top) && !top.Has(kw))
            top[kw] := ent
    }

    static _Fold(ents) {
        out := []
        seen := Map()
        for e in ents {
            if (seen.Has(e.target))
                continue
            seen[e.target] := true
            out.Push(e)
        }
        if (out.Length = 0)
            return ""
        if (out.Length = 1)
            return out[1].target
        return out
    }

    static _MatchLayer(word, prefixOnly) {
        cands := []
        wLen := StrLen(word)
        for k, ent in this._index {
            hit := prefixOnly
                ? (StrCompare(SubStr(k, 1, wLen), word) = 0)
                : (InStr(k, word) != 0)
            if (hit) {
                for e in ent
                    cands.Push(e)
            }
        }
        if (prefixOnly) {
            i := 2
            while (i <= cands.Length) {
                v := cands[i], j := i - 1
                while (j >= 1 && StrLen(cands[j].key) > StrLen(v.key))
                    cands[j + 1] := cands[j], j--
                cands[j + 1] := v
                i++
            }
        }
        return cands
    }
}
