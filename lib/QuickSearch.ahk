#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "QuickLaunch.ahk"

class QuickSearch {
    static Ask(word, rest) {
        e := QuickSearch.FindEngineCI(word)
        if (e = "")
            return ""
        if (rest != "" || e.HasOwnProp("home"))
            return { word: word, rest: rest, entry: e }
        return ""
    }

    static FindEngineCI(word) {
        if (ConfigManager.EngineMap.Has(word))
            return ConfigManager.EngineMap[word]
        for k, e in ConfigManager.EngineMap {
            if (StrCompare(k, word) = 0)
                return e
        }
        return ""
    }

    static Execute(cmd, query, action := "search") {
        ConfigManager.EnsureLoaded()
        if ConfigManager.EngineMap.Has(cmd)
            return this.ExecuteEntry(ConfigManager.EngineMap[cmd], query, action)
        return Utils.ResErr(cmd, action, false, "ERR_NO_ENGINE")
    }

    static ExecuteEntry(e, query, action := "search") {
        ConfigManager.EnsureLoaded()
        if (Trim(query) = "" && e.HasOwnProp("home"))
            return QuickLaunch.RunTarget(e.home)
        TargetUrl := StrReplace(e.target, "%s", Utils.UriEncode(query))
        try {
            Run(TargetUrl)
            return Utils.ResOk(action)
        } catch as err {
            return Utils.ResErr(TargetUrl "`n`n" err.Message, action, false, "ERR_SEARCH_URL")
        }
    }
}
