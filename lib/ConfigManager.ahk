#Requires AutoHotkey v2.0
#Include "JSON.ahk"
#Include "AppPaths.ahk"

class ConfigManager {
    static Config := Map()
    static ConfigFile := ""
    static EngineMap := Map()
    static WordMap := Map()
    static VoiceRouteMap := Map()
    static FirstRun := false
    static IsInitialized := false
    static _DirtyKeys := Map()
    static _Loading := false
    static OnCachesRebuilt := 0
    static DiskStamp := ""
    static Init(configPath := "") {
        if (configPath != "") {
            this.ConfigFile := configPath
        } else {
            this.ConfigFile := AppPaths.ConfigFile()
            this._EnsureWritable()
        }
        this.FirstRun := !FileExist(this.ConfigFile)
        this.Load()
        this.IsInitialized := true
    }

    static _EnsureWritable() {
        root := AppPaths.DataRoot()
        probe := AppPaths.WriteProbe()
        try {
            DirCreate(root)
            FileAppend("1", probe, "UTF-8-RAW")
            FileDelete(probe)
        } catch as e {
            msg := "无法使用配置目录：`n" root "`n`n" e.Message
            msg .= "`n`n请检查该目录的权限，或用你的 Windows 账户登录后重试。"
            throw Error(msg)
        }
    }

    static EnsureLoaded() {
        if (!this.IsInitialized && !this._Loading)
            this.Init()
    }

    static DiskStampOf() {
        if (this.ConfigFile = "" || !FileExist(this.ConfigFile))
            return ""
        try
            return FileGetTime(this.ConfigFile, "M") "|" FileGetSize(this.ConfigFile)
        catch
            return ""
    }

    static ReloadIfDiskChanged() {
        if (!this.IsInitialized || this._Loading)
            return false
        stamp := this.DiskStampOf()
        if (stamp = "" || stamp = this.DiskStamp)
            return false
        this.Load()
        return true
    }

    static Get(key, default := "") {
        this.EnsureLoaded()
        return this.Config.Has(key) ? this.Config[key] : default
    }

    static Set(key, value) {
        this.EnsureLoaded()
        this.Config[key] := value
        this._DirtyKeys[key] := true
    }

    static LastLoadError := ""
    static Load() {
        Defaults := this.GetDefaults()
        this._Loading := true
        this.LastLoadError := ""
        this.Config := Map()
        if FileExist(this.ConfigFile) {
            try {
                jsonText := FileRead(this.ConfigFile, "UTF-8")
                parsed := JSON.parse(jsonText)
                if (Type(parsed) != "Map" || parsed.Count = 0)
                    throw Error("配置内容无法识别（不是合法的配置对象）")
                needSave := false
                for k, v in parsed {
                    val := v
                    this.Config[k] := val
                }
                for k, v in Defaults {
                    if (!this.Config.Has(k))
                        this.Config[k] := v, needSave := true
                }
                if (this.Config.Has("WordTable") && Type(this.Config["WordTable"]) = "Map") {
                    known := this.Config.Has("KnownDefaultWords") && Type(this.Config["KnownDefaultWords"]) = "Array"
                        ? this.Config["KnownDefaultWords"] : []
                    knownSet := Map()
                    for w in known
                        knownSet[w] := true
                    changed := false
                    for dk, dv in this.GetDefaultWordTable() {
                        if (!this.Config["WordTable"].Has(dk) && !knownSet.Has(dk)) {
                            this.Config["WordTable"][dk] := dv, changed := true
                            knownSet[dk] := true
                        }
                    }
                    newKnown := []
                    for w in knownSet
                        newKnown.Push(w)
                    this.Config["KnownDefaultWords"] := newKnown
                    if (changed)
                        needSave := true
                }
                if needSave
                    this.Save()
            } catch as e {
                this.LastLoadError := "配置文件内容损坏，已按默认值重建：`n" this.ConfigFile "`n" e.Message
                bak := this.ConfigFile ".bak-" FormatTime(, "yyyyMMdd-HHmmss")
                try {
                    FileMove(this.ConfigFile, bak, 1)
                } catch {
                    this.LastLoadError .= "`n⚠ 原文件备份失败，损坏内容已被覆盖。"
                }
                for k, v in Defaults
                    this.Config[k] := v
                this.Save()
            }
        } else {
            for k, v in Defaults
                this.Config[k] := v
            this.Save()
        }
        this._NormalizeInputKeySlots()
        this._NormalizeGlobalHotkeyRows()
        this._Loading := false
        this.Config["DateTimeFormat"] := this.Config["DateFormat"] " " this.Config["TimeFormat"]
        this.RebuildEngineCache()
        this.RebuildWordCache()
        this.RebuildVoiceRouteCache()
        if (this.OnCachesRebuilt)
            this.OnCachesRebuilt()
        this.DiskStamp := this.DiskStampOf()
    }

    static _NormalizeInputKeySlots(slots := 0) {
        if (slots = 0)
            slots := this.Config.Has("InputKeySlots") ? this.Config["InputKeySlots"] : this.GetDefaultInputKeySlots()
        out := []
        for s in slots {
            if (Type(s) = "Map")
                out.Push({ key: s.Has("key") ? s["key"] : "", action: s.Has("action") ? s["action"] : "" })
            else
                out.Push(s)
        }
        if (slots = 0)
            this.Config["InputKeySlots"] := out
        return out
    }

    static _NormalizeGlobalHotkeyRows() {
        if (!this.Config.Has("GlobalHotkeyRows"))
            return
        this.Config["GlobalHotkeyRows"] := this._NormalizeHotkeyRows(this.Config["GlobalHotkeyRows"])
    }

    static _NormalizeHotkeyRows(rows) {
        out := []
        for r in rows {
            if (Type(r) = "Map")
                out.Push({ key: r.Has("key") ? r["key"] : "", domain: r.Has("domain") ? r["domain"] : "", action: r.Has("action") ? r["action"] : "" })
            else
                out.Push({ key: r.HasOwnProp("key") ? r.key : "", domain: r.HasOwnProp("domain") ? r.domain : "", action: r.HasOwnProp("action") ? r.action : "" })
        }
        return out
    }

    static LastError := ""
    static Save(showError := false) {
        try {
            if (!this._Loading && this._DirtyKeys.Count > 0 && FileExist(this.ConfigFile)) {
                try {
                    disk := JSON.parse(FileRead(this.ConfigFile, "UTF-8"))
                    for k, v in this.Config {
                        if (!this._DirtyKeys.Has(k) && disk.Has(k))
                            this.Config[k] := disk[k]
                    }
                    for k, v in disk {
                        if (!this.Config.Has(k))
                            this.Config[k] := v
                    }
                    this._NormalizeInputKeySlots()
                    this._NormalizeGlobalHotkeyRows()
                    this.RebuildEngineCache()
                    this.RebuildWordCache()
                    this.RebuildVoiceRouteCache()
                    if (this.OnCachesRebuilt)
                        this.OnCachesRebuilt()
                } catch {
                }
            }
            this.Config["DateTimeFormat"] := this.Get("DateFormat") " " this.Get("TimeFormat")
            jsonText := JSON.stringify(this.Config, , "  ")
            FileObj := FileOpen(this.ConfigFile, "w", "UTF-8-RAW")
            FileObj.Write(jsonText)
            FileObj.Close()
            this._DirtyKeys := Map()
            this.LastError := ""
            this.DiskStamp := this.DiskStampOf()
            return true
        } catch as e {
            this.LastError := "配置保存失败：" this.ConfigFile " | " e.Message
            return false
        }
    }

    static _NormEntry(v) {
        if (Type(v) = "String")
            return (v = "") ? "" : { type: "run", target: v }
        if (Type(v) != "Map" && Type(v) != "Object")
            return ""
        if (Type(v) = "Map") {
            if (!v.Has("target") || Type(v["target"]) != "String" || v["target"] = "")
                return ""
            e := { type: v.Has("type") ? v["type"] : "run", target: v["target"] }
            for f in ["param", "home", "icon", "cat", "desc"] {
                if (v.Has(f) && Type(v[f]) = "String" && v[f] != "")
                    e.%f% := v[f]
            }
            if (v.Has("show") && Type(v["show"]) = "Integer" && v["show"] = 1 && !v.Has("display"))
                e.display := { toolbar: true }
            if (v.Has("display") && Type(v["display"]) = "Map")
                e.display := this._NormDisplay(v["display"])
            return this._ValidateEntry(e)
        }
        if (!v.HasOwnProp("target") || Type(v.target) != "String" || v.target = "")
            return ""
        if (v.HasOwnProp("display"))
            v.display := this._NormDisplay(v.display)
        return this._ValidateEntry(v)
    }

    static DISPLAY_KEYS := Map("toolbar", 1, "slots", 1, "textTargets", 1, "quickKey", 1, "fallback", 1, "voice", 1, "any", 1)
    static _NormDisplay(d) {
        out := {}
        for k, val in (Type(d) = "Map" ? d : (Type(d) = "Object" ? d.OwnProps() : "")) {
            if (!this.DISPLAY_KEYS.Has(k))
                continue
            if (val = true || val = 1)
                out.%k% := true
            else if (val = false || val = 0)
                out.%k% := false
        }
        return out
    }

    static _ValidateEntry(e) {
        if (!e.HasOwnProp("type"))
            e.type := "run"
        if (e.type != "run" && e.type != "action" && e.type != "search")
            return ""
        if (e.type = "search" && !InStr(e.target, "%s"))
            return ""
        return e
    }

    static _RebuildWordMap(cfgKey, defaultFn) {
        m := Map()
        raw := this.Config.Has(cfgKey) ? this.Config[cfgKey] : defaultFn()
        for k, v in raw {
            e := this._NormEntry(v)
            if (e = "")
                continue
            Loop Parse, k, "|" {
                key := Trim(A_LoopField)
                if (key != "")
                    m[key] := e
            }
        }
        return m
    }

    static RebuildWordCache() {
        this.WordMap := this._RebuildWordMap("WordTable", this.GetDefaultWordTable)
    }

    static RebuildEngineCache() {
        this.EngineMap := Map()
        engines := this.Config["SearchEngines"]
        for k, v in engines {
            e := this._NormEntry(v)
            if (e = "")
                continue
            Loop Parse, k, "|" {
                key := Trim(A_LoopField)
                if (key != "")
                    this.EngineMap[key] := e
            }
        }
    }

    static RebuildVoiceRouteCache() {
        this.VoiceRouteMap := Map()
        routes := this.Config.Has("VoiceRoutes") ? this.Config["VoiceRoutes"] : this.GetDefaultVoiceRoutes()
        for k, v in routes {
            if (Type(v) = "Map") {
                if (!v.Has("target"))
                    continue
                v := { target: v["target"], param: v.Has("param") ? v["param"] : ""
                    , rescan: v.Has("rescan") ? v["rescan"] : true
                    , fillers: v.Has("fillers") ? v["fillers"] : [] }
            }
            if (Type(v) = "Object" && v.HasOwnProp("target") && v.target != "")
                this.VoiceRouteMap[k] := v
        }
    }

    static GetDefaults() {
        return Map(
            "_version", 1,
            "ToggleHotkey", "!Space",
            "VaultPath", EnvGet("OneDrive") "\框子笔记库",
            "NoteFolder", "kuangzi-data\{dev}",
            "ArchiveDir", "kuangzi-data\archive",
            "DateFormat", "yyyy-MM-dd",
            "NotePeriod", "day",
            "WeekFormat", "{start}",
            "MonthFormat", "yyyy-MM",
            "TemplatePath", "",
            "TargetHeader", "## 框子速记",
            "TargetTodoHeader", "## 框子待办",
            "NoteMetaEnabled", 0,
            "TimeFormat", "HH:mm:ss",
            "DateTimeFormat", "yyyy-MM-dd HH:mm:ss",
            "SearchPrefix", "/",
            "SearchEngines", this.GetDefaultSearchEngines(),
            "SearchEngine", "百度",
            "AppPrefix", "@",
            "PluginPrefix", "$",
            "WordTable", this.GetDefaultWordTable(),
            "InputBarTools", this.GetDefaultInputBarTools(),
            "AlwaysShow", 0,
            "TurboMode", 0,
            "EnterActionNormal", "newline",
            "EnterActionTurbo", "submit",
            "ConfirmFallback", "note",
            "InputKeySlots", this.GetDefaultInputKeySlots(),
            "VoiceLaunchHotkey", "RControl",
            "IMEVoiceHotkey", ">!h",
            "IMEHoldHotkey", "RAlt",
            "VoiceRoutes", this.GetDefaultVoiceRoutes(),
            "VoiceFillerWords", this.GetDefaultFillerWords(),
            "VoiceWindow", 6,
            "VoiceFallbackAction", "search",
            "GlobalHotkeyRows", this.GetDefaultHotkeyRows(),
            "CapsLockActions", this.GetDefaultCapsLockActions(),
            "WinX", 0,
            "WinY", 0,
            "NotifyEnabled", 1,
            "NotifySound", 1,
            "ImageFolder", "attachments",
            "DeviceId", A_UserName
        )
    }

    static GetDefaultInputKeySlots() {
        return [
            { key: "^Enter",  action: "submit" },
            { key: "+Enter",  action: "newline" },
            { key: "^+Enter", action: "todo" },
            { key: "!Enter",  action: "search" }
        ]
    }

    static GetDefaultHotkeyRows() {
        rows := [
            { key: "^!z", domain: "select", action: "note" },
            { key: "^!x", domain: "clip", action: "note" },
            { key: "^!c", domain: "clip", action: "eng.豆包" }
        ]
        for s in this.GetDefaultInputKeySlots()
            rows.Push({ key: s.key, domain: "input", action: s.action })
        return rows
    }

    static GetDefaultSearchEngines() {
        return Map(
            "百度", { type: "search", target: "https://www.baidu.com/s?wd=%s", home: "https://www.baidu.com", desc: "百度搜索，无词开百度首页" },
            "B站", { type: "search", target: "https://search.bilibili.com/all?keyword=%s", home: "https://www.bilibili.com", desc: "哔哩哔哩视频搜索，无词开B站首页" },
            "豆包", { type: "search", target: "https://www.doubao.com/chat/#ask=%s", home: "https://www.doubao.com/chat/", desc: "豆包 AI 对话，直接发问，无词开豆包对话页", icon: "🤖", display: { toolbar: true, slots: true, textTargets: true, fallback: true } },
            "翻译", { type: "search", target: "https://fanyi.baidu.com/#zh/en/%s", home: "https://fanyi.baidu.com", desc: "百度翻译，无词开翻译首页", icon: "🌐", display: { toolbar: true, slots: true, textTargets: true, fallback: true } },
            "谷歌", { type: "search", target: "https://www.google.com/search?q=%s", home: "https://www.google.com", desc: "谷歌搜索，无词开谷歌首页" },
            "GitHub", { type: "search", target: "https://github.com/search?q=%s", home: "https://github.com", desc: "GitHub 代码搜索，无词开 GitHub 首页" },
            "微博", { type: "search", target: "https://s.weibo.com/weibo?q=%s", home: "https://weibo.com", desc: "微博热搜与全文搜索，无词开微博首页" },
            "小红书", { type: "search", target: "https://www.xiaohongshu.com/search_result?keyword=%s", home: "https://www.xiaohongshu.com", desc: "小红书笔记搜索，无词开小红书首页" }
        )
    }

    static GetDefaultInputBarTools() {
        return ["search", "note", "todo", "word.表情面板"]
    }

    static GetDefaultWordTable() {
        return Map(
            "用户目录", { type: "run", target: "A_UserProfile", desc: "当前用户主目录" },
            "下载", { type: "run", target: "A_UserProfile\Downloads", desc: "下载文件夹" },
            "控制面板", { type: "run", target: "control.exe", desc: "Windows 控制面板" },
            "文件管理器", { type: "run", target: "explorer.exe", desc: "Windows 资源管理器" },
            "文档", { type: "run", target: "A_MyDocuments", desc: "我的文档" },
            "新浪网", { type: "run", target: "https://www.sina.com.cn", desc: "新浪门户" },
            "桌面", { type: "run", target: "A_Desktop", desc: "桌面文件夹" },
            "计算器", { type: "run", target: "calc.exe", desc: "Windows 计算器" },
            "任务管理器", { type: "run", target: "taskmgr.exe", desc: "Windows 任务管理器" },
            "设置", { type: "run", target: "ms-settings:", desc: "Windows 系统设置" },
            "回收站", { type: "run", target: "shell:RecycleBinFolder", desc: "回收站" },
            "系统截图", { type: "run", target: "ms-screenclip:", desc: "系统截图工具（框选）" },
            "启动文件夹", { type: "run", target: "shell:Startup", desc: "开机自启文件夹" },
            "高德地图", { type: "run", target: "https://www.amap.com", desc: "高德地图" },
            "剪贴板历史", { type: "action", target: "send", param: "#v", icon: "📋", display: { toolbar: true }, desc: "按下 Win+V 剪贴板历史" },
            "表情面板", { type: "action", target: "send", param: "#.", icon: "😀", display: { toolbar: true }, desc: "按下 Win+. 表情符号面板" },
            "任务视图", { type: "action", target: "send", param: "#{Tab}", desc: "按下 Win+Tab 任务视图" },
            "截全屏", { type: "action", target: "send", param: "#{PrintScreen}", icon: "📷", display: { toolbar: true }, desc: "按下 Win+PrintScreen 全屏截图" }
        )
    }

    static GetDefaultCapsLockActions() {
        return [
            { key: "space", action: "toggleMain", locked: true },
            { key: "/",     action: "openDir",    locked: true },
            { key: "j", action: "word.计算器" }
        ]
    }

    static GetDefaultVoiceRoutes() {
        return Map(
            "打开", { target: "launch", param: "none", rescan: true },
            "启动", { target: "launch", param: "none", rescan: true },
            "运行", { target: "launch", param: "none", rescan: true },
            "框子", { target: "launch", param: "none", rescan: true },
            "框子同学", { target: "launch", param: "none", rescan: true }
        )
    }

    static GetDefaultFillerWords() {
        return ["搜一下", "搜索下", "搜索一下", "搜索", "一下", "一哈", "搜下", "查一下", "查下", "看下", "你说"]
    }
}
