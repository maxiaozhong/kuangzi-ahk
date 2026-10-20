#Requires AutoHotkey v2.0

#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "CliCore.ahk"

CliEngine(args) => CliDict("SearchEngines", "engine", args)
CliWord(args) => CliDict("WordTable", "word", args)

CliDict(table, cmd, args) {
    ConfigManager.EnsureLoaded()
    p := DictParseArgs(args, 2)
    sub := (p.pos.Length >= 1) ? p.pos[1] : "list"
    switch sub {
        case "list":   return DictList(table, cmd)
        case "add":    return DictAdd(table, cmd, p)
        case "remove": return DictRemove(table, cmd, p)
        case "rename": return DictRename(table, cmd, p)
        default:
            return DictUsageFail(cmd)
    }
}

DictParseArgs(args, from) {
    pos := [], opt := Map()
    i := from
    while (i <= args.Length) {
        a := args[i]
        if (SubStr(a, 1, 2) != "--") {
            pos.Push(a), i++
            continue
        }
        body := SubStr(a, 3)
        if (body = "json" || body = "force") {
            opt[body] := "true", i++
            continue
        }
        eq := InStr(body, "=")
        if (eq) {
            opt[SubStr(body, 1, eq - 1)] := SubStr(body, eq + 1), i++
            continue
        }
        opt[body] := (i < args.Length) ? args[i + 1] : ""
        i += 2
    }
    return { pos: pos, opt: opt }
}

DictList(table, cmd) {
    tbl := ConfigManager.Get(table)
    rows := []
    for k, v in tbl
        rows.Push(Map(
            "word", k,
            "type", Utils.ObjGet(v, "type", (table = "SearchEngines") ? "search" : "run"),
            "target", DictTargetOf(v),
            "home", Utils.ObjGet(v, "home"),
            "desc", Utils.ObjGet(v, "desc")))

    if (JsonMode) {
        Out(JsonOut(Map("ok", "true", "count", rows.Length, "entries", rows)))
        return 0
    }
    label := DictLabel(table)
    if (rows.Length = 0) {
        Out("（空）" label "表里没有任何条目；用 kuangzi " cmd " add 添加")
        return 0
    }
    Out("共 " rows.Length " 条" label "（词 → 目标）：")
    for r in rows {
        d := r["desc"]
        Out("  " r["word"] " → " r["target"] (d = "" ? "" : "    # " d))
    }
    return 0
}

DictAdd(table, cmd, p) {
    if (p.pos.Length < 3)
        return DictUsageFail(cmd)
    if (p.pos.Length > 3)
        return DictFail("目标里含空格要用引号包起来（多出的参数：" p.pos[4] "）", "E_USAGE")

    word := Trim(p.pos[2])
    target := Trim(p.pos[3])
    type := p.opt.Has("type") ? p.opt["type"] : ((table = "SearchEngines") ? "search" : "run")

    if (word = "")
        return DictUsageFail(cmd)
    if (target = "")
        return DictFail("目标不能为空", "E_USAGE")
    if (type != "run" && type != "action" && type != "search")
        return DictFail("--type 只认 run / action / search，收到：" type, "E_USAGE")
    if (table = "SearchEngines" && type != "search")
        return DictFail("搜索引擎表的条目固定 type=search（target 里用 %s 占位搜索词）", "E_USAGE")
    if (type = "search" && !InStr(target, "%s"))
        return DictFail("search 型的 target 必须含 %s（搜索词占位，例：https://example.com/s?q=%s）", "E_USAGE")

    tbl := ConfigManager.Get(table)
    force := p.opt.Has("force")
    if (tbl.Has(word) && !force)
        return DictFail("「" word "」已存在；要覆盖加 --force，或先 kuangzi " cmd " remove " word, "E_EXISTS")

    entry := { type: type, target: target }
    if (p.opt.Has("desc") && p.opt["desc"] != "")
        entry.desc := p.opt["desc"]
    if (p.opt.Has("home") && p.opt["home"] != "")
        entry.home := p.opt["home"]
    if (p.opt.Has("icon") && p.opt["icon"] != "")
        entry.icon := p.opt["icon"]

    val := entry
    if (type = "run" && !entry.HasOwnProp("desc") && !entry.HasOwnProp("home") && !entry.HasOwnProp("icon"))
        val := target

    if (ConfigManager._NormEntry(val) = "")
        return DictFail("条目校验未过（type/target 结构不合法）", "E_FAIL")

    tbl[word] := val
    ConfigManager.Set(table, tbl)
    if (!ConfigManager.Save(true))
        return DictFail("配置保存失败：" ConfigManager.LastError, "E_FAIL")

    if (JsonMode) {
        Out(JsonOut(Map("ok", "true", "action", cmd ".add", "word", word, "target", target
            , "type", type, "config", ConfigManager.ConfigFile)))
        return 0
    }
    Out("✅ 已添加" DictLabel(table) "「" word "」→ " target)
    Out("   已写入：" ConfigManager.ConfigFile)
    Out("   宿主运行中：下次唤起输入框时自动重载生效")
    return 0
}

DictRemove(table, cmd, p) {
    if (p.pos.Length < 2)
        return DictUsageFail(cmd)
    if (p.pos.Length > 2)
        return DictFail("词里含空格要用引号包起来（多出的参数：" p.pos[3] "）", "E_USAGE")

    word := Trim(p.pos[2])
    tbl := ConfigManager.Get(table)
    if (!tbl.Has(word))
        return DictFail("「" word "」不在表里（kuangzi " cmd " list 看现有词）", "E_NOTFOUND")

    tbl.Delete(word)
    ConfigManager.Set(table, tbl)
    if (!ConfigManager.Save(true))
        return DictFail("配置保存失败：" ConfigManager.LastError, "E_FAIL")

    if (JsonMode) {
        Out(JsonOut(Map("ok", "true", "action", cmd ".remove", "word", word)))
        return 0
    }
    Out("✅ 已移除" DictLabel(table) "「" word "」")
    return 0
}

DictRename(table, cmd, p) {
    if (p.pos.Length < 3)
        return DictUsageFail(cmd)
    if (p.pos.Length > 3)
        return DictFail("词里含空格要用引号包起来（多出的参数：" p.pos[4] "）", "E_USAGE")

    oldWord := Trim(p.pos[2])
    newWord := Trim(p.pos[3])
    if (newWord = "")
        return DictUsageFail(cmd)

    tbl := ConfigManager.Get(table)
    if (!tbl.Has(oldWord))
        return DictFail("「" oldWord "」不在表里（kuangzi " cmd " list 看现有词）", "E_NOTFOUND")
    if (tbl.Has(newWord))
        return DictFail("「" newWord "」已存在，换个词或先移除它", "E_EXISTS")

    tbl[newWord] := tbl[oldWord]
    tbl.Delete(oldWord)
    ConfigManager.Set(table, tbl)
    if (!ConfigManager.Save(true))
        return DictFail("配置保存失败：" ConfigManager.LastError, "E_FAIL")

    if (JsonMode) {
        Out(JsonOut(Map("ok", "true", "action", cmd ".rename", "from", oldWord, "to", newWord)))
        return 0
    }
    Out("✅ 「" oldWord "」→「" newWord "」（目标不变）")
    return 0
}

DictTargetOf(v) {
    if (Type(v) = "String")
        return v
    return Utils.ObjGet(v, "target")
}

DictLabel(table) => (table = "SearchEngines") ? "搜索引擎" : "快捷启动词"

DictFail(msg, code) {
    if (JsonMode)
        Out(JsonOut(Map("ok", "false", "code", code, "msg", msg)))
    else
        Out("❌ " msg)
    return (code = "E_USAGE") ? 3 : 1
}

DictUsageFail(cmd) {
    if (JsonMode)
        return DictFail("用法错误：kuangzi " cmd " list | add <词> <目标> | remove <词> | rename <旧词> <新词>", "E_USAGE")
    DictUsage(cmd)
    return 3
}

DictUsage(cmd) {
    if (cmd = "engine") {
        Out("用法：")
        Out("  kuangzi engine list                        列出全部搜索引擎")
        Out("  kuangzi engine add <词> <URL模板> [选项]    加一个引擎（URL 里用 %s 占位搜索词）")
        Out("  kuangzi engine remove <词>                 删一个引擎")
        Out("  kuangzi engine rename <旧词> <新词>         改引擎词（URL 不变）")
        Out("")
        Out("选项：--home <URL> 无词时打开的首页 | --desc <描述> 列表描述 | --icon <字符> 按钮图标")
        Out("      --force 同名覆盖 | 词写「A|B」= 一个引擎两个触发词")
        Out('例：kuangzi engine add 知乎 "https://www.zhihu.com/search?q=%s" --home https://www.zhihu.com --desc "知乎搜索"')
    } else {
        Out("用法：")
        Out("  kuangzi word list                          列出全部快捷启动词")
        Out("  kuangzi word add <词> <目标> [选项]          加一条（目标=程序/路径/网址/动作）")
        Out("  kuangzi word remove <词>                   删一条")
        Out("  kuangzi word rename <旧词> <新词>            改词（目标不变）")
        Out("")
        Out("选项：--type run|action|search（默认 run） | --desc <描述> 列表描述 | --icon <字符> 图标")
        Out("      --home <URL> search 型无词时的首页 | --force 同名覆盖 | 词写「A|B」= 一词多触发")
        Out('例：kuangzi word add 微信 "D:\Program Files\WeChat\WeChat.exe" --desc "微信桌面版"')
    }
}
