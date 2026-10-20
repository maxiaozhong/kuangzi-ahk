#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "JSON.ahk"
#Include "AppInfo.ahk"

class PluginManager {
    static PluginsById := Map()
    static ActionsById := Map()
    static KeywordMap := Map()
    static Diagnostics := []

    static API_VERSION := 1
    static PLUGIN_ROOT := ""

    static STATUS_OK := "ok"
    static STATUS_DISABLED := "disabled"
    static STATUS_INVALID := "invalid"
    static STATUS_INCOMPATIBLE := "incompatible"
    static STATUS_NO_ENTRY := "no_entry"
    static STATUS_NO_RUNTIME := "no_runtime"
    static STATUS_NO_ACTIONS := "no_actions"

    static PluginsRoot() {
        if (this.PLUGIN_ROOT = "")
            this.PLUGIN_ROOT := AppPaths.PluginsDir()
        return this.PLUGIN_ROOT
    }
    static PluginDataDir(id) {
        return this.PluginsRoot() "\" id
    }

    static Scan() {
        this.PluginsById := Map()
        this.ActionsById := Map()
        this.KeywordMap := Map()
        this.Diagnostics := []
        disabled := this._DisabledList()
        root := this.PluginsRoot()

        if !DirExist(root)
            return

        dirs := []
        Loop Files root "\*", "D"
            dirs.Push(A_LoopFileFullPath)
        for d in dirs
            this._ScanOne(d, disabled)

        this._ResolveKeywordConflicts()
    }

    static _ScanOne(dir, disabled) {
        id := ""
        SplitPath(dir, &id)
        plugin := { id: id, name: id, version: "", author: "", description: ""
            , icon: "", settings: false, dir: dir, dataDir: this.PluginDataDir(id)
            , entry: "", status: this.STATUS_INVALID, diagnostics: [] }
        this.PluginsById[id] := plugin

        if !RegExMatch(id, "^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$")
            return this._Diag(plugin, "error", "E_PLUGIN_ID", "插件目录名非法（只允许小写字母、数字、连字符）")

        mf := dir "\manifest.json"
        if !FileExist(mf)
            return this._Diag(plugin, "error", "E_PLUGIN_MANIFEST_MISSING", "缺少 manifest.json")
        try {
            text := FileRead(mf, "UTF-8")
            while (SubStr(text, 1, 1) = Chr(0xFEFF))
                text := SubStr(text, 2)
            m := JSON.parse(text)
        } catch as e {
            return this._Diag(plugin, "error", "E_PLUGIN_MANIFEST_BAD", "manifest.json 解析失败：" e.Message)
        }
        if (Type(m) != "Map")
            return this._Diag(plugin, "error", "E_PLUGIN_MANIFEST_BAD", "manifest 根必须是 JSON 对象")

        for k in ["id", "name", "version", "minHostVersion", "author", "description"]
            if (!m.Has(k) || m[k] = "" || Type(m[k]) != "String")
                return this._Diag(plugin, "error", "E_PLUGIN_MANIFEST_FIELD", "manifest 缺少或非法字段：" k)
        if (m["id"] != id)
            return this._Diag(plugin, "error", "E_PLUGIN_ID", "manifest id 与目录名不一致（" m["id"] " vs " id "）")

        if (!m.Has("apiVersion") || m["apiVersion"] != this.API_VERSION)
            return this._Diag(plugin, "error", "E_PLUGIN_API", "apiVersion 不支持（要求 " this.API_VERSION "）")
        if (this._VerCmp(m["minHostVersion"], AppInfo.version) > 0) {
            plugin.status := this.STATUS_INCOMPATIBLE
            return this._Diag(plugin, "error", "E_PLUGIN_HOSTVER", "需要宿主 ≥" m["minHostVersion"] "（当前 " AppInfo.version "）")
        }

        plugin.name := m["name"], plugin.version := m["version"]
        plugin.author := m["author"], plugin.description := m["description"]
        plugin.icon := m.Has("icon") ? m["icon"] : ""
        plugin.settings := m.Has("settings") ? !!m["settings"] : false
        plugin.permissions := this._NormPermissions(m)

        entry := this._ResolveEntry(dir, m, plugin)
        if (entry = "")
            return

        if (Utils.ArrContains(disabled, id)) {
            plugin.status := this.STATUS_DISABLED
            return
        }

        if (!m.Has("actions") || Type(m["actions"]) != "Array" || m["actions"].Length = 0)
            return this._Diag(plugin, "error", "E_PLUGIN_ACTIONS", "actions 缺失或为空")
        seenAction := Map()
        nRegistered := 0
        for a in m["actions"] {
            if (Type(a) != "Map")
                return this._Diag(plugin, "error", "E_PLUGIN_ACTION_FIELD", "动作必须是对象")
            for k in ["id", "label"]
                if (!a.Has(k) || a[k] = "" || Type(a[k]) != "String")
                    return this._Diag(plugin, "error", "E_PLUGIN_ACTION_FIELD", "动作缺少或非法字段：" k)
            if !RegExMatch(a["id"], "^[a-z0-9][a-z0-9-]*$")
                return this._Diag(plugin, "error", "E_PLUGIN_ACTION_FIELD", "动作 ID 非法（只允许小写字母、数字、连字符）：" a["id"])
            if (seenAction.Has(a["id"]))
                return this._Diag(plugin, "error", "E_PLUGIN_ACTION_DUP", "动作 ID 重复：" a["id"])
            seenAction[a["id"]] := true
            if (InStr(a["label"], m["name"]) || InStr(m["name"], a["label"]))
                this._Diag(plugin, "warning", "W_PLUGIN_LABEL_DUP"
                    , "动作 label 与插件名重复：" a["label"] "（显示时会拼成「" m["name"] " · " a["label"] "」）", a["id"])
            gid := "plugin." id "." a["id"]
            this.ActionsById[gid] := {
                id: gid, pluginId: id, actionId: a["id"],
                label: a["label"],
                icon: a.Has("icon") && a["icon"] != "" ? a["icon"] : plugin.icon,
                keywords: this._NormKeywords(a.Has("keywords") ? a["keywords"] : []),
                textAction: a.Has("textAction") ? !!a["textAction"] : false,
                allowEmpty: a.Has("allowEmpty") ? !!a["allowEmpty"] : false,
                display: this._NormActionDisplay(a),
                supportsGui: a.Has("supportsGui") ? !!a["supportsGui"] : false
            }
            nRegistered++
        }
        if (nRegistered = 0)
            return this._Diag(plugin, "error", "E_PLUGIN_ACTIONS", "无可注册动作")
        plugin.status := this.STATUS_OK
    }

    static _ResolveEntry(dir, m, plugin) {
        exeRel := (m.Has("entry") && Type(m["entry"]) = "Map" && m["entry"].Has("exe")) ? m["entry"]["exe"] : ""
        srcRel := (m.Has("entry") && Type(m["entry"]) = "Map" && m["entry"].Has("source")) ? m["entry"]["source"] : ""
        if (exeRel = "" && srcRel = "") {
            plugin.status := this.STATUS_NO_ENTRY
            this._Diag(plugin, "error", "E_PLUGIN_ENTRY", "entry.exe 与 entry.source 至少需要一个")
            return ""
        }
        exePath := ""
        if (exeRel != "") {
            exePath := this._SafeJoin(dir, exeRel)
            if (exePath = "" || !FileExist(exePath)) {
                if (srcRel = "") {
                    plugin.status := this.STATUS_NO_ENTRY
                    this._Diag(plugin, "error", "E_PLUGIN_ENTRY", "exe 入口缺失：" exeRel)
                    return ""
                }
                this._Diag(plugin, "warning", "W_PLUGIN_ENTRY", "exe 入口无效（" exeRel "），改用源码入口")
                exePath := ""
            }
        }
        if (exePath != "") {
            plugin.entry := "exe:" exePath
            return plugin.entry
        }
        srcPath := this._SafeJoin(dir, srcRel)
        if (srcPath = "" || !FileExist(srcPath)) {
            plugin.status := this.STATUS_NO_ENTRY
            this._Diag(plugin, "error", "E_PLUGIN_ENTRY", "源码入口缺失：" srcRel)
            return ""
        }
        ahk := this.FindAhkV2(plugin)
        if (ahk = "") {
            plugin.status := this.STATUS_NO_RUNTIME
            return ""
        }
        plugin.entry := "ahk:" ahk "|" srcPath
        return plugin.entry
    }

    static _ahkCache := ""
    static _ahkCacheValid := false
    static FindAhkV2(plugin := 0) {
        if (this._ahkCacheValid)
            return this._ahkCache
        this._ahkCache := "", this._ahkCacheValid := true
        cfgPath := ConfigManager.Get("PluginAhkV2Path", "")
        if (cfgPath != "") {
            if (this._VerifyAhkV2(cfgPath))
                return this._ahkCache := cfgPath
            if (plugin)
                this._Diag(plugin, "warning", "W_PLUGIN_AHK_CFG", "配置的解释器路径无效：" cfgPath)
        }
        for cand in ["AutoHotkey64.exe", "AutoHotkey32.exe", "AutoHotkey.exe"] {
            try {
                p := this._WhereInPath(cand)
                if (p != "" && this._VerifyAhkV2(p))
                    return this._ahkCache := p
            } catch {
            }
        }
        for p in ["C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
            , "C:\Program Files\AutoHotkey\v2\AutoHotkey32.exe"
            , "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe"] {
            if (this._VerifyAhkV2(p))
                return this._ahkCache := p
        }
        return ""
    }
    static _VerifyAhkV2(path) {
        if (path = "" || !FileExist(path))
            return false
        try {
            ver := FileGetVersion(path)
            if (ver = "")
                return false
            return SubStr(ver, 1, 1) = "2"
        } catch {
            return false
        }
    }
    static _WhereInPath(name) {
        pathEnv := EnvGet("PATH")
        Loop Parse pathEnv, ";" {
            d := Trim(A_LoopField)
            if (d = "")
                continue
            p := RTrim(d, "\") "\" name
            if FileExist(p)
                return p
        }
        return ""
    }

    static _NormActionDisplay(a) {
        out := {}
        if (a.Has("display") && Type(a["display"]) = "Map") {
            for k, val in a["display"] {
                if (!ConfigManager.DISPLAY_KEYS.Has(k))
                    continue
                if (val = true || val = 1)
                    out.%k% := true
                else if (val = false || val = 0)
                    out.%k% := false
            }
        }
        if (a.Has("showInToolbar") && !!a["showInToolbar"] && !out.HasOwnProp("toolbar"))
            out.toolbar := true
        return out
    }

    static _ResolveKeywordConflicts() {
        cand := Map()
        for gid, a in this.ActionsById {
            for kw in a.keywords {
                if !cand.Has(kw)
                    cand[kw] := []
                cand[kw].Push(gid)
            }
        }
        for kw, gids in cand {
            nk := this._KwKey(kw)
            if (nk = "")
                continue
            if (ConfigManager.WordMap.Has(kw)) {
                for gid in gids
                    this._Diag(this.PluginsById[this.ActionsById[gid].pluginId], "warning", "W_PLUGIN_KW_CORE"
                        , "关键词与词表词相同：裸词让位给词表，$ 前缀可直通：" kw, gid, kw)
            }
            if (gids.Length > 1) {
                for gid in gids
                    this._Diag(this.PluginsById[this.ActionsById[gid].pluginId], "warning", "W_PLUGIN_KW_DUP"
                        , "多插件关键词冲突，该词均不注册：" kw, gid, kw)
                continue
            }
            this.KeywordMap[nk] := gids[1]
        }
    }

    static _NormKeywords(raw) {
        out := []
        if (Type(raw) != "Array")
            return out
        seen := Map()
        for kw in raw {
            if (Type(kw) != "String")
                continue
            Loop Parse kw, "|" {
                k := Trim(A_LoopField)
                if (k = "" || seen.Has(k))
                    continue
                seen[k] := true
                out.Push(k)
            }
        }
        return out
    }

    static PERMISSION_LABELS := Map(
        "read:vault", "读取笔记库",
        "read:config", "读取配置",
        "read:clipboard", "读写剪贴板",
        "read:focused-window", "读前台窗口",
        "network", "联网")
    static SENSITIVE_PERMS := Map("read:clipboard", 1, "read:focused-window", 1)
    static _NormPermissions(m) {
        out := []
        if (!m.Has("permissions") || Type(m["permissions"]) != "Array")
            return out
        seen := Map()
        for p in m["permissions"] {
            if (Type(p) != "String" || !this.PERMISSION_LABELS.Has(p) || seen.Has(p))
                continue
            seen[p] := true
            out.Push(p)
        }
        return out
    }
    static PermissionText(plugin) {
        if (plugin.permissions.Length = 0)
            return ""
        out := ""
        for p in plugin.permissions
            out .= (out = "" ? "" : "、") this.PERMISSION_LABELS[p]
        return out
    }
    static _KwKey(kw) {
        return StrLower(kw)
    }

    static LookupKeyword(word) {
        k := this._KwKey(Trim(word))
        return this.KeywordMap.Has(k) ? this.KeywordMap[k] : ""
    }

    static Ask(word, rest) {
        gid := this.LookupKeyword(word)
        if (gid = "")
            return ""
        if (rest != "")
            return { word: word, rest: rest, entry: gid }
        a := this.GetAction(gid)
        if (a = "")
            return { word: word, rest: rest, entry: gid }
        if (a.allowEmpty || !a.textAction)
            return { word: word, rest: rest, entry: gid }
        return ""
    }

    static GetAction(gid) {
        return this.ActionsById.Has(gid) ? this.ActionsById[gid] : ""
    }
    static PluginActions() {
        pids := []
        for pid, _ in this.PluginsById
            pids.Push(pid)
        out := []
        for pid in this._SortedPids(pids) {
            for gid, a in this.ActionsById
                if (a.pluginId = pid)
                    out.Push(a)
        }
        return out
    }
    static _SortedPids(pids) {
        return Utils.SortBy(pids.Clone(), (pid) => pid)
    }
    static OpenSettings(pluginId) {
        p := this.PluginsById.Has(pluginId) ? this.PluginsById[pluginId] : ""
        if (p = "" || p.status != this.STATUS_OK)
            return Utils.ResErr("插件不可用", "plugin", false, "ERR_PLUGIN_STATE")
        gid := ""
        for aid, a in this.ActionsById {
            if (a.pluginId = pluginId) {
                gid := aid
                break
            }
        }
        if (gid = "")
            return Utils.ResErr("插件无可执行动作", "plugin", false, "ERR_PLUGIN_NO_ACTIONS")
        return this.Invoke(gid, "settings", "open", "settings")
    }

    static ActionLabel(a) {
        return this.PluginsById[a.pluginId].name " · " a.label
    }

    static _DisabledList() {
        lst := ConfigManager.Get("DisabledPlugins", [])
        return (Type(lst) = "Array") ? lst : []
    }
    static _Diag(plugin, severity, code, msg, actionId := "", keyword := "") {
        d := { pluginId: plugin.id, severity: severity, code: code, msg: msg, actionId: actionId, keyword: keyword }
        plugin.diagnostics.Push(d)
        this.Diagnostics.Push(d)
    }
    static _SafeJoin(base, rel) {
        if (Type(rel) != "String" || rel = "")
            return ""
        if (RegExMatch(rel, "^[a-zA-Z]:[\\/]") || SubStr(rel, 1, 2) = "\\" || SubStr(rel, 1, 1) = "/")
            return ""
        p := base "\" rel
        norm := this._NormPath(p)
        baseN := this._NormPath(base)
        if (SubStr(norm, 1, StrLen(baseN) + 1) != baseN "\")
            return ""
        return norm
    }
    static _NormPath(p) {
        parts := StrSplit(p, "\")
        out := []
        for part in parts {
            if (part = "" || part = ".")
                continue
            if (part = "..") {
                if (out.Length > 0)
                    out.Pop()
                continue
            }
            out.Push(part)
        }
        drive := ""
        if (out.Length > 0 && RegExMatch(out[1], "^[a-zA-Z]:$"))
            drive := out.RemoveAt(1) "\"
        return drive . this._JoinArr(out, "\")
    }
    static _JoinArr(arr, sep) {
        s := ""
        for i, v in arr
            s .= (i > 1 ? sep : "") v
        return s
    }
    static _VerCmp(a, b) {
        pa := StrSplit(a, "."), pb := StrSplit(b, ".")
        n := Max(pa.Length, pb.Length)
        Loop n {
            x := (A_Index <= pa.Length && IsNumber(pa[A_Index])) ? pa[A_Index] + 0 : 0
            y := (A_Index <= pb.Length && IsNumber(pb[A_Index])) ? pb[A_Index] + 0 : 0
            if (x > y)
                return 1
            if (x < y)
                return -1
        }
        return 0
    }

    static TASK_PENDING := "pending"
    static TASK_SUCCEEDED := "succeeded"
    static TASK_FAILED := "failed"
    static TASK_TIMEDOUT := "timedOut"
    static TASK_CANCELLED := "cancelled"

    static TASK_TIMEOUT_MS := 15000
    static RESP_MAX_BYTES := 1048576
    static MAX_GLOBAL_TASKS := 4
    static MAX_PLUGIN_TASKS := 2
    static POLL_INTERVAL_MS := 100
    static CLEANUP_GRACE_MS := 60000

    static TasksByRequestId := Map()
    static _pollTimer := 0
    static _cleanupQueue := Map()
    static _cleanupTimer := 0
    static TasksRootOverride := ""
    static OnTaskDone := 0
    static HostContext := 0

    static InvokeByDecision(gid, text, source := "keyword", keyword := "") {
        a := this.GetAction(gid)
        if (a = "")
            return Utils.ResErr("未知插件动作：" gid, "plugin", false, "ERR_PLUGIN_ACTION")
        hasText := (Trim(text) != "")
        if (hasText) {
            if (a.textAction)
                return this.Invoke(gid, text, "execute", source, keyword)
            if (a.supportsGui)
                return this.Invoke(gid, "", "open", source, keyword)
            return Utils.ResErr("该动作不接受文本", "plugin", false, "ERR_PLUGIN_NO_TEXT")
        }
        if (!a.allowEmpty)
            return Utils.ResOk("empty")
        if (a.supportsGui)
            return this.Invoke(gid, "", "open", source, keyword)
        return this.Invoke(gid, "", "execute", source, keyword)
    }

    static Invoke(gid, text, mode := "execute", source := "keyword", keyword := "") {
        a := this.GetAction(gid)
        if (a = "")
            return Utils.ResErr("未知插件动作：" gid, "plugin", false, "ERR_PLUGIN_ACTION")
        plugin := this.PluginsById[a.pluginId]
        if (plugin.status != this.STATUS_OK)
            return Utils.ResErr("插件不可用", "plugin", false, "ERR_PLUGIN_STATE")

        if (this.TasksByRequestId.Count >= this.MAX_GLOBAL_TASKS)
            return Utils.ResErr("插件任务繁忙（全局并发上限），请稍后再试", "plugin", false, "ERR_PLUGIN_BUSY")
        nPlugin := 0
        for _, t in this.TasksByRequestId
            if (t.action.pluginId = a.pluginId && t.state = this.TASK_PENDING)
                nPlugin++
        if (nPlugin >= this.MAX_PLUGIN_TASKS)
            return Utils.ResErr("该插件任务繁忙（单插件并发上限），请稍后再试", "plugin", false, "ERR_PLUGIN_BUSY")

        requestId := FormatTime(, "yyyyMMddHHmmss") "-" Format("{:04X}", Random(0, 0xFFFF))
        taskDir := this.TasksRoot() "\" requestId
        try {
            DirCreate(taskDir)
        } catch as e {
            return Utils.ResErr("任务目录创建失败：" e.Message, "plugin", false, "ERR_PLUGIN_TASK")
        }
        reqPath := taskDir "\request.json"
        respPath := taskDir "\response.json"

        req := Map(
            "protocolVersion", "invoke.v1",
            "requestId", requestId,
            "pluginId", a.pluginId,
            "actionId", gid,
            "mode", mode,
            "keyword", keyword,
            "source", source,
            "text", text,
            "pluginDataDir", plugin.dataDir,
            "locale", this._Locale(),
            "hostVersion", AppInfo.version)
        if (this.HostContext) {
            want := Map()
            for p in plugin.permissions
                if (this.SENSITIVE_PERMS.Has(p))
                    want[p] := true
            try {
                hc := (this.HostContext)(want)
                if (Type(hc) = "Map" && hc.Count > 0)
                    req["hostContext"] := hc
            } catch {
            }
        }
        try {
            f := FileOpen(reqPath, "w", "UTF-8-RAW")
            f.Write(JSON.stringify(req))
            f.Close()
        } catch as e {
            this._RmDir(taskDir)
            return Utils.ResErr("请求文件写入失败：" e.Message, "plugin", false, "ERR_PLUGIN_TASK")
        }

        cmd := this._BuildCmd(plugin.entry, reqPath, respPath)
        if (cmd = "") {
            this._RmDir(taskDir)
            return Utils.ResErr("插件入口不可执行", "plugin", false, "ERR_PLUGIN_ENTRY")
        }
        pid := 0
        try {
            Run(cmd,, "Hide", &pid)
        } catch as e {
            this._RmDir(taskDir)
            return Utils.ResErr("插件进程启动失败：" e.Message, "plugin", false, "ERR_PLUGIN_RUN")
        }

        task := { requestId: requestId, action: a, mode: mode, state: this.TASK_PENDING
            , pid: pid, taskDir: taskDir, reqPath: reqPath, respPath: respPath
            , startedAt: A_TickCount, result: "" }
        this.TasksByRequestId[requestId] := task
        this._EnsurePoll()
        return Utils.ResPending("plugin")
    }

    static _BuildCmd(entry, reqPath, respPath) {
        q := Chr(34)
        if (SubStr(entry, 1, 4) = "exe:")
            return q SubStr(entry, 5) q " --request " q reqPath q " --response " q respPath q
        if (SubStr(entry, 1, 4) = "ahk:") {
            rest := SubStr(entry, 5)
            sep := InStr(rest, "|")
            if (!sep)
                return ""
            ahk := SubStr(rest, 1, sep - 1), src := SubStr(rest, sep + 1)
            return q ahk q " " q src q " --request " q reqPath q " --response " q respPath q
        }
        return ""
    }

    static _EnsurePoll() {
        if (this._pollTimer = 0)
            this._pollTimer := ObjBindMethod(this, "_PollTick")
        SetTimer(this._pollTimer, this.POLL_INTERVAL_MS)
    }
    static _PollTick() {
        anyPending := false
        for _, t in this.TasksByRequestId {
            if (t.state != this.TASK_PENDING) {
                continue
            }
            anyPending := true
            if (FileExist(t.respPath)) {
                this._FinishByResponse(t)
                continue
            }
            if (A_TickCount - t.startedAt > this.TASK_TIMEOUT_MS) {
                this._FinishTask(t, this.TASK_TIMEDOUT
                    , Utils.ResErr("插件执行超时（" (this.TASK_TIMEOUT_MS // 1000) " 秒）", "plugin", false, "ERR_PLUGIN_TIMEOUT"))
                continue
            }
            if (t.pid && !ProcessExist(t.pid)) {
                if (!t.HasOwnProp("exitSeenAt"))
                    t.exitSeenAt := A_TickCount
                else if (A_TickCount - t.exitSeenAt > 500)
                    this._FinishTask(t, this.TASK_FAILED
                        , Utils.ResErr("插件进程异常退出（未产生响应）", "plugin", false, "ERR_PLUGIN_CRASH"))
            }
        }
        if (!anyPending)
            SetTimer(this._pollTimer, 0)
    }

    static _FinishByResponse(t) {
        try {
            size := FileGetSize(t.respPath)
            if (size > this.RESP_MAX_BYTES) {
                this._FinishTask(t, this.TASK_FAILED
                    , Utils.ResErr("插件响应超过大小上限", "plugin", false, "ERR_PLUGIN_RESP_SIZE"))
                return
            }
            text := FileRead(t.respPath, "UTF-8")
        } catch as e {
            this._FinishTask(t, this.TASK_FAILED
                , Utils.ResErr("插件响应读取失败：" e.Message, "plugin", false, "ERR_PLUGIN_RESP_READ"))
            return
        }
        while (SubStr(text, 1, 1) = Chr(0xFEFF))
            text := SubStr(text, 2)
        try {
            r := JSON.parse(text)
        } catch as e {
            this._FinishTask(t, this.TASK_FAILED
                , Utils.ResErr("插件响应不是合法 JSON：" e.Message, "plugin", false, "ERR_PLUGIN_RESP_BAD"))
            return
        }
        if (Type(r) != "Map" || r.Count = 0) {
            this._FinishTask(t, this.TASK_FAILED
                , Utils.ResErr("插件响应不是合法 JSON（解析结果为空）", "plugin", false, "ERR_PLUGIN_RESP_BAD"))
            return
        }
        if (Type(r) != "Map" || !r.Has("protocolVersion") || r["protocolVersion"] != "invoke.v1"
            || !r.Has("requestId") || r["requestId"] != t.requestId
            || !r.Has("actionId") || r["actionId"] != t.action.id) {
            this._FinishTask(t, this.TASK_FAILED
                , Utils.ResErr("插件响应协议校验失败（版本/请求ID/动作ID 不匹配）", "plugin", false, "ERR_PLUGIN_RESP_PROTO"))
            return
        }
        ok := r.Has("ok") ? !!r["ok"] : false
        resText := r.Has("text") && Type(r["text"]) = "String" ? r["text"] : ""
        resMsg := r.Has("msg") && Type(r["msg"]) = "String" ? r["msg"] : ""
        resCode := r.Has("code") && Type(r["code"]) = "String" ? r["code"] : ""
        intent := "notify"
        if (ok && r.Has("intent") && Type(r["intent"]) = "String") {
            v := r["intent"]
            if (v = "fill" || v = "copy" || v = "todo")
                intent := v
            else if (v != "notify" && v != "")
                this._Diag(this.PluginsById[t.action.pluginId], "warning", "W_PLUGIN_INTENT"
                    , "未知 intent 值，按 notify 处理：" v, t.action.id)
        }
        notifyStyle := ""
        if (ok && r.Has("notifyStyle") && Type(r["notifyStyle"]) = "String") {
            sv := r["notifyStyle"]
            if (sv = "center" || sv = "toast")
                notifyStyle := sv
            else if (sv != "")
                this._Diag(this.PluginsById[t.action.pluginId], "warning", "W_PLUGIN_NOTIFY_STYLE"
                    , "未知 notifyStyle 值，按缺省呈现处理：" sv, t.action.id)
        }
        if (ok) {
            res := Utils.ResOk("plugin", resText)
            res.intent := intent
            if (notifyStyle != "")
                res.notifyStyle := notifyStyle
            this._FinishTask(t, this.TASK_SUCCEEDED, res)
        } else {
            res := Utils.ResErr(resMsg, "plugin", false, resCode != "" ? resCode : "ERR_PLUGIN_FAIL")
            this._FinishTask(t, this.TASK_FAILED, res)
        }
    }

    static _FinishTask(t, state, result) {
        if (t.state != this.TASK_PENDING)
            return
        t.state := state
        t.result := result
        if (t.pid) {
            if (t.mode = "execute" || state != this.TASK_SUCCEEDED) {
                try ProcessClose(t.pid)
            }
        }
        this._RmDir(t.taskDir)
        this.TasksByRequestId.Delete(t.requestId)
        if (this.OnTaskDone)
            (this.OnTaskDone)(t)
    }

    static Cancel(requestId) {
        t := this.TasksByRequestId.Has(requestId) ? this.TasksByRequestId[requestId] : ""
        if (t = "" || t.state != this.TASK_PENDING)
            return
        this._FinishTask(t, this.TASK_CANCELLED
            , Utils.ResErr("插件任务已取消", "plugin", true, "ERR_PLUGIN_CANCELLED"))
    }
    static CancelByPlugin(pluginId) {
        for rid, t in this.TasksByRequestId
            if (t.state = this.TASK_PENDING && t.action.pluginId = pluginId)
                this.Cancel(rid)
    }
    static CancelAll() {
        for rid, t in this.TasksByRequestId
            if (t.state = this.TASK_PENDING)
                this.Cancel(rid)
        if (this._pollTimer)
            SetTimer(this._pollTimer, 0)
    }

    static SweepStaleTasks() {
        root := this.TasksRoot()
        if !DirExist(root)
            return
        cutoff := A_Now
        cutoff := DateAdd(cutoff, -1, "days")
        Loop Files root "\*", "D" {
            mtime := FileGetTime(A_LoopFileFullPath, "M")
            if (mtime < cutoff)
                this._RmDir(A_LoopFileFullPath)
        }
    }

    static _Locale() {
        try {
            return StrReplace(DllCall("Kernel32\GetUserDefaultLocaleName", "Ptr", StrPtr(buf := Buffer(85, 0)), "Int", 85, "Int") > 0
                ? StrGet(buf, "UTF-16") : "zh-CN", "_", "-")
        } catch {
            return "zh-CN"
        }
    }
    static TasksRoot() {
        return (this.TasksRootOverride != "") ? this.TasksRootOverride
            : AppPaths.TasksDir()
    }

    static _RmDir(dir) {
        if (this._TryRmDir(dir)) {
            if (this._cleanupQueue.Has(dir))
                this._cleanupQueue.Delete(dir)
            return
        }
        if (!this._cleanupQueue.Has(dir))
            this._cleanupQueue[dir] := A_TickCount
        this._EnsureCleanup()
    }

    static _TryRmDir(dir) {
        if (!DirExist(dir))
            return true
        try {
            DirDelete(dir, 1)
            return !DirExist(dir)
        } catch {
            return false
        }
    }

    static _EnsureCleanup() {
        if (this._cleanupTimer)
            return
        this._cleanupTimer := ObjBindMethod(this, "_CleanupTick")
        SetTimer(this._cleanupTimer, 1000)
    }

    static _CleanupTick() {
        for dir, since in this._cleanupQueue.Clone() {
            if (!this._cleanupQueue.Has(dir))
                continue
            if (this._TryRmDir(dir) || A_TickCount - since > this.CLEANUP_GRACE_MS)
                this._cleanupQueue.Delete(dir)
        }
        if (this._cleanupQueue.Count = 0 && this._cleanupTimer) {
            SetTimer(this._cleanupTimer, 0)
            this._cleanupTimer := 0
        }
    }
}
