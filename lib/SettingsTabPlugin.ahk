#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "NotifyCenter.ahk"
#Include "PluginManager.ahk"
#Include "Actions.ahk"

class SettingsTabPlugin {
    static Build(SG, Tabs, tabIndex, host) {
        C := host.Ctrls
        Tabs.UseTab(tabIndex)
        yPos := Theme.SET_PAGE_Y

        SG.Add("GroupBox", "x" Theme.SET_PAGE_X " y" yPos " w" Theme.SET_PAGE_W " h" Theme.SET_PAGE_H, "已安装插件")
        yPos += 28

        DIAG_H := 70, DIAG_GAP := 8
        LV_H := Theme.SetListBottom() - yPos - DIAG_GAP - DIAG_H

        lv := SG.Add("ListView", "x" Theme.SET_LIST_X " y" yPos " w" Theme.SET_LIST_W " h" LV_H " Grid -Multi NoSortHdr", ["名称", "ID", "版本", "状态", "关键词", "操作"])
        lv.ModifyCol(1, 100), lv.ModifyCol(2, 120), lv.ModifyCol(3, 55), lv.ModifyCol(4, 70), lv.ModifyCol(5, 155), lv.ModifyCol(6, 60)
        C["PluginList"] := lv
        this._FillList(lv)

        yPos += LV_H + DIAG_GAP
        diag := SG.Add("Text", "x" Theme.SET_LIST_X " y" yPos " w" Theme.SET_LIST_W " h" DIAG_H " c" Theme.COLOR_HINT, "选中插件查看诊断详情")
        C["PluginDiag"] := diag
        lv.OnEvent("DoubleClick", ObjBindMethod(this, "_OnListDblClick", host))
        lv.OnEvent("ItemSelect", ObjBindMethod(this, "_OnSelect", host))

        BTN_Y := Theme.SetBtnY()
        SG.Add("Button", "x" Theme.SetBtnX(0) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "启用/禁用").OnEvent("Click", ObjBindMethod(this, "_Toggle", host))
        SG.Add("Button", "x" Theme.SetBtnX(1) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "刷新").OnEvent("Click", ObjBindMethod(this, "_Refresh", host))
        SG.Add("Button", "x" Theme.SetBtnX(2) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "打开插件目录").OnEvent("Click", ObjBindMethod(this, "_OpenRoot", host))
        SG.Add("Button", "x" Theme.SetBtnX(3) " y" BTN_Y " w" Theme.SET_BTN_W " h" Theme.SET_BTN_H, "打开数据目录").OnEvent("Click", ObjBindMethod(this, "_OpenData", host))
    }

    static _FillList(lv) {
        lv.Delete()
        pids := []
        for pid, p in PluginManager.PluginsById
            pids.Push(pid)
        Utils.SortBy(pids, (pid) => pid)
        for pid in pids {
            p := PluginManager.PluginsById[pid]
            kws := ""
            for gid, a in PluginManager.ActionsById {
                if (a.pluginId = pid) {
                    for kw in a.keywords
                        kws .= (kws = "" ? "" : "、") kw
                }
            }
            lv.Add("", p.icon " " p.name, pid, p.version, this._StatusText(p.status), kws, "设置")
        }
    }

    static _StatusText(s) {
        switch s {
            case "ok": return "✓ 可用"
            case "disabled": return "已禁用"
            case "invalid": return "✕ 无效"
            case "incompatible": return "✕ 不兼容"
            case "no_entry": return "✕ 入口缺失"
            case "no_runtime": return "✕ 无解释器"
            default: return s
        }
    }

    static _OnSelect(host, lv, *) {
        row := lv.GetNext(0)
        if (!row)
            return
        pid := lv.GetText(row, 2)
        if (!PluginManager.PluginsById.Has(pid))
            return
        p := PluginManager.PluginsById[pid]
        txt := p.name " v" p.version "（" p.author "）`n" p.description
        perm := PluginManager.PermissionText(p)
        txt .= "`n`n权限声明：" (perm != "" ? perm : "未声明任何权限")
        if (p.diagnostics.Length > 0) {
            txt .= "`n`n诊断："
            for d in p.diagnostics
                txt .= "`n[" d.severity "] " d.msg
        }
        host.Ctrls["PluginDiag"].Value := txt
    }

    static _Toggle(host, *) {
        lv := host.Ctrls["PluginList"]
        row := lv.GetNext(0)
        if (!row) {
            NotifyCenter.Send("info", "插件管理", "请先在列表中选中一个插件")
            return
        }
        pid := lv.GetText(row, 2)
        if (!PluginManager.PluginsById.Has(pid))
            return
        lst := []
        for v in ConfigManager.Get("DisabledPlugins", [])
            lst.Push(v)
        if (Utils.ArrContains(lst, pid)) {
            newList := []
            for v in lst
                if (v != pid)
                    newList.Push(v)
            ConfigManager.Set("DisabledPlugins", newList)
        } else {
            lst.Push(pid)
            ConfigManager.Set("DisabledPlugins", lst)
        }
        ConfigManager.Save()
        this._ApplyAndRebuild(host)
    }

    static _OnListDblClick(host, lv, row) {
        if (!row)
            return
        pid := lv.GetText(row, 2)
        if (!PluginManager.PluginsById.Has(pid))
            return
        PluginManager.OpenSettings(pid)
    }

    static _Refresh(host, *) {
        this._ApplyAndRebuild(host)
    }

    static _ApplyAndRebuild(host) {
        PluginManager.CancelAll()
        PluginManager._ahkCacheValid := false
        PluginManager.Scan()
        ActionBindings.RebuildPluginActions()
        this._FillList(host.Ctrls["PluginList"])
        host.Ctrls["PluginDiag"].Value := "选中插件查看诊断详情"
        host.host.input.Rebuild()
    }

    static _OpenRoot(host, *) {
        root := PluginManager.PluginsRoot()
        if !DirExist(root)
            DirCreate(root)
        try Run(root)
    }
    static _OpenData(host, *) {
        this._OpenRoot(host)
    }
}
