#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "QuickLaunch.ahk"
#Include "Actions.ahk"

class EntryExecutor {
    static Execute(entry, word, rest, host := 0) {
        switch entry.type {
            case "run":
                return QuickLaunch.RunTarget(entry.target)
            case "action":
                if (rest = "" && entry.HasOwnProp("home"))
                    return QuickLaunch.RunTarget(entry.home)
                res := Actions.Run(entry.target, { text: rest, param: entry.HasOwnProp("param") ? entry.param : "", host: host })
                if (IsObject(res))
                    return res
                return Utils.ResErr(word, "launch", false, "ERR_NO_APP")
            case "search":
                if (rest = "" && entry.HasOwnProp("home"))
                    return QuickLaunch.RunTarget(entry.home)
                url := StrReplace(entry.target, "%s", Utils.UriEncode(rest))
                res := QuickLaunch.RunTarget(url)
                return res.ok ? res : Utils.ResErr(word, "search", false, "ERR_ENGINE")
        }
        return Utils.ResErr(word, "launch", false, "ERR_NO_APP")
    }
}
