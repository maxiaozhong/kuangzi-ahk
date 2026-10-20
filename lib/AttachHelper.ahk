#Requires AutoHotkey v2.0
#Include "ConfigManager.ahk"
#Include "PathModel.ahk"

class AttachHelper {
    static CATS := Map(
        "image", { exts: ["png", "jpg", "jpeg", "bmp", "gif", "webp", "avif", "svg"], sub: "" },
        "media", { exts: ["mp4", "mov", "avi", "mkv", "webm", "mp3", "wav", "m4a", "flac"], sub: "media" },
        "doc",   { exts: ["pdf", "doc", "docx", "md"], sub: "doc" }
    )

    static MaxMB() {
        v := ConfigManager.Get("AttachMaxMB", 200)
        return (Type(v) = "Integer" && v > 0) ? v : 200
    }

    static Attach(srcPath) {
        cat := this._Classify(srcPath)
        if (cat = "")
            return ""

        try {
            sizeMB := FileGetSize(srcPath) / 1048576
            if (sizeMB > this.MaxMB())
                return "__OVERSIZE__"
        } catch {
            return ""
        }

        fileName := this._Materialize(srcPath, cat)
        if (fileName = "")
            return ""
        return this.MakeRef(cat, fileName)
    }

    static AttachClipboard() {
        if (this.HasImage()) {
            fileName := this.SaveClipboardImage()
            return (fileName != "") ? [this.MakeRef("image", fileName)] : ""
        }
        if (this.HasFiles()) {
            files := this.GetClipboardFiles()
            if (files.Length = 0)
                return ""
            refs := []
            for filePath in files {
                ref := this.Attach(filePath)
                if (ref != "" && ref != "__OVERSIZE__")
                    refs.Push(ref)
            }
            return (refs.Length > 0) ? refs : ""
        }
        return Trim(A_Clipboard)
    }

    static MakeRef(cat, fileName) {
        sub := this.CATS[cat].sub
        rel := ConfigManager.Get("ImageFolder", "attachments")
        if (sub != "")
            rel .= "/" sub
        rel .= "/" fileName
        return rel
    }

    static HasImage() {
        return DllCall("IsClipboardFormatAvailable", "UInt", 8, "Int")
    }

    static HasFiles() {
        return DllCall("IsClipboardFormatAvailable", "UInt", 15, "Int")
    }

    static GetClipboardFiles() {
        files := []
        if !DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)
            return files
        hDrop := DllCall("GetClipboardData", "UInt", 15, "Ptr")
        if (hDrop) {
            fileCount := DllCall("shell32\DragQueryFileW", "Ptr", hDrop, "UInt", 0xFFFFFFFF, "Ptr", 0, "UInt", 0)
            Loop fileCount {
                bufSize := DllCall("shell32\DragQueryFileW", "Ptr", hDrop, "UInt", A_Index - 1, "Ptr", 0, "UInt", 0) + 1
                buf := Buffer(bufSize * 2)
                DllCall("shell32\DragQueryFileW", "Ptr", hDrop, "UInt", A_Index - 1, "Ptr", buf, "UInt", bufSize)
                filePath := StrGet(buf, "UTF-16")
                if (this._Classify(filePath) != "")
                    files.Push(filePath)
            }
        }
        DllCall("CloseClipboard")
        return files
    }

    static SaveClipboardImage() {
        saveDir := this._GetSaveDir("image")
        if (saveDir = "")
            return ""

        fileName := this._MakeFileName(saveDir, "png")
        fullPath := saveDir "\" fileName

        psPath := StrReplace(StrReplace(fullPath, "\", "\\"), "'", "''")
        psScript := "Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; if ($([System.Windows.Forms.Clipboard]::ContainsImage())) { $img = [System.Windows.Forms.Clipboard]::GetImage(); $img.Save('" psPath "', [System.Drawing.Imaging.ImageFormat]::Png); $img.Dispose(); }"

        try {
            RunWait('powershell -NoProfile -Command "' psScript '"', , "Hide")
        } catch {
            return ""
        }

        if FileExist(fullPath)
            return fileName
        return ""
    }

    static Classify(path) {
        return this._Classify(path)
    }

    static AttachDir(cat) {
        ConfigManager.EnsureLoaded()
        dir := PathModel.AttachDir()
        sub := this.CATS[cat].sub
        if (sub != "")
            dir .= "\" sub
        return dir
    }

    static _Classify(path) {
        SplitPath(path, , , &ext)
        ext := StrLower(ext)
        if (ext = "")
            return ""
        for cat, c in this.CATS {
            for validExt in c.exts {
                if (ext = validExt)
                    return cat
            }
        }
        return ""
    }

    static _Materialize(srcPath, cat) {
        if !FileExist(srcPath)
            return ""
        saveDir := this._GetSaveDir(cat)
        if (saveDir = "")
            return ""

        SplitPath(srcPath, &srcFileName, , &ext)
        ext := StrLower(ext)

        srcDir := RegExReplace(srcPath, "\\[^\\]+$", "")
        if (StrLower(srcDir) = StrLower(saveDir))
            return srcFileName

        fileName := this._MakeFileName(saveDir, ext)
        destPath := saveDir "\" fileName
        try {
            FileCopy(srcPath, destPath, 1)
            return fileName
        } catch {
            return ""
        }
    }

    static _GetSaveDir(cat) {
        ConfigManager.EnsureLoaded()
        if (PathModel.Vault() = "")
            return ""
        dir := PathModel.AttachDir()
        sub := this.CATS[cat].sub
        if (sub != "")
            dir .= "\" sub
        if !DirExist(dir) {
            try DirCreate(dir)
            catch
                return ""
        }
        return dir
    }

    static _MakeFileName(saveDir, ext) {
        baseName := FormatTime(, "yyyyMMdd_HHmmss")
        fileName := baseName "." ext
        seq := 2
        while FileExist(saveDir "\" fileName) {
            fileName := baseName "_" seq "." ext
            seq++
        }
        return fileName
    }
}
