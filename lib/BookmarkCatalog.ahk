#Requires AutoHotkey v2.0
#Include "JSON.ahk"

class BookmarkCatalog {
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
        for k, v in this._map {
            if (InStr(v, word))
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
        this._ScanFile(EnvGet("LocalAppData") "\Microsoft\Edge\User Data\Default\Bookmarks")
        this._ScanFile(EnvGet("LocalAppData") "\Google\Chrome\User Data\Default\Bookmarks")
    }

    static _ScanFile(path) {
        if !FileExist(path)
            return
        try {
            data := JSON.parse(FileRead(path, "UTF-8"))
            if (Type(data) = "Map" && data.Has("roots")) {
                for _, root in data["roots"]
                    this._Walk(root)
            }
        } catch {
        }
    }

    static _Walk(node) {
        if (Type(node) != "Map" || !node.Has("children"))
            return
        for child in node["children"] {
            if (child.Has("type")) {
                if (child["type"] = "url" && child.Has("name") && child.Has("url")) {
                    name := child["name"]
                    if (name != "" && !this._map.Has(name))
                        this._map[name] := child["url"]
                } else if (child["type"] = "folder") {
                    this._Walk(child)
                }
            }
        }
    }
}
