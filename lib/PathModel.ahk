#Requires AutoHotkey v2.0
#Include "ConfigManager.ahk"

class PathModel {
    static DATA_ROOT_NAME := "kuangzi-data"
    static ARCHIVE_NAME   := "archive"
    static ATTACH_NAME    := "attachments"

    static Vault() => ConfigManager.Get("VaultPath")

    static DataRoot() => this.Vault() "\" this.DATA_ROOT_NAME

    static DeviceRoot() {
        rel := ConfigManager.Get("NoteFolder", this.DATA_ROOT_NAME "\{dev}")
        if (rel = "")
            return this.Vault()
        return this.Vault() "\" StrReplace(rel, "{dev}", ConfigManager.Get("DeviceId"))
    }

    static AttachDir() => this.DeviceRoot() "\" ConfigManager.Get("ImageFolder", this.ATTACH_NAME)

    static ArchiveDir() => this.Vault() "\" ConfigManager.Get("ArchiveDir", this.DATA_ROOT_NAME "\" this.ARCHIVE_NAME)
    static ArchiveAttachDir() => this.ArchiveDir() "\" this.ATTACH_NAME

    static NoteFile(p := "") => this.DeviceRoot() "\" this.PeriodName(p) ".md"

    static Partitions() {
        out := []
        root := this.DataRoot()
        if !DirExist(root)
            return out
        loop files root "\*", "D"
            out.Push(A_LoopFileFullPath)
        return out
    }

    static PeriodName(period := "", dateFormat := "", weekFormat := "", monthFormat := "", at := "") {
        ConfigManager.EnsureLoaded()
        ts := (at != "") ? at : A_Now
        period := (period != "") ? period : ConfigManager.Get("NotePeriod", "day")
        dateFormat := this._StripTypeWord((dateFormat != "") ? dateFormat : ConfigManager.Get("DateFormat"))
        result := ""
        if (period = "week") {
            weekFormat := this._StripTypeWord((weekFormat != "") ? weekFormat : ConfigManager.Get("WeekFormat"))
            wday := Integer(FormatTime(ts, "WDay"))
            offset := (wday = 1) ? 6 : wday - 2
            Monday := DateAdd(ts, -offset, "Days")
            base := FormatTime(Monday, dateFormat)
            if (InStr(weekFormat, "{start}")) {
                base := StrReplace(weekFormat, "{start}", FormatTime(Monday, dateFormat))
                base := StrReplace(base, "{end}", FormatTime(DateAdd(Monday, 6, "Days"), dateFormat))
            }
            result := base "_week"
        } else if (period = "month") {
            monthFormat := this._StripTypeWord((monthFormat != "") ? monthFormat : ConfigManager.Get("MonthFormat"))
            base := ""
            if (monthFormat != "") {
                try base := FormatTime(ts, monthFormat)
                catch
                    base := ""
            }
            result := (base = "" ? FormatTime(ts, "yyyy-MM") : base) "_month"
        } else
            result := FormatTime(ts, dateFormat) "_day"

        if (result = "" || RegExMatch(result, '[\\/:*?"<>|]'))
            result := FormatTime(ts, "yyyy-MM-dd") "_day"
        return result
    }

    static _StripTypeWord(fmt) {
        if (fmt = "")
            return fmt
        return RegExReplace(fmt, "i)(?:'_day'|'_week'|'_month'|_day|_week|_month)$")
    }

    static ValidateDeviceId(id) {
        if (Trim(id) = "")
            return "设备标识不能为空"
        if (id = this.ARCHIVE_NAME)
            return "设备标识不得为保留名 archive"
        if RegExMatch(id, '[\\/:*?"<>|]')
            return "设备标识含非法字符 \ / : * ? 引号 或尖括号"
        return ""
    }
}
