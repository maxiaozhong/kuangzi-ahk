#Requires AutoHotkey v2.0
#Include "ConfigManager.ahk"

class SettingsListPage {
    static _LoadFromConfig() {
        m := Map()
        for k, v in ConfigManager.Get(this.ConfigKey)
            m[k] := v
        this._Entries := m
    }

    static ReloadFromConfig() {
        this._LoadFromConfig()
        this._Redraw()
    }

    static _Redraw() {
        lv := this._List
        if (!IsObject(lv))
            return
        lv.Delete()
        for k, v in this._Entries
            lv.Add("", this.RowValues(k, v)*)
        for idx, c in this.Columns
            lv.ModifyCol(idx, c[2])
    }

    static GetEntriesForSave() => this._Entries
}
