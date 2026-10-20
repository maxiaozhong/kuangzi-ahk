#Requires AutoHotkey v2.0
#Include "src\calc.ahk"
#Include "src\data.ahk"
#Include "src\gui.ahk"
#Include "src\settings-gui.ahk"

reqPath := "", respPath := ""
i := 1
while (i <= A_Args.Length) {
    if (A_Args[i] = "--request")
        reqPath := A_Args[i + 1], i += 2
    else if (A_Args[i] = "--response")
        respPath := A_Args[i + 1], i += 2
    else
        i += 1
}
if (reqPath = "" || respPath = "")
    ExitApp(3)

req := FileRead(reqPath, "UTF-8")
while (SubStr(req, 1, 1) = Chr(0xFEFF))
    req := SubStr(req, 2)
reqId := PluginReqField(req, "requestId")
actionId := PluginReqField(req, "actionId")
mode := PluginReqField(req, "mode")
text := PluginReqField(req, "text")

if (mode = "open" && text = "settings") {
    PluginWriteResponse(respPath, reqId, actionId, true, "设置已打开", "")
    PluginShowSettingsGui()
} else if (mode = "open") {
    PluginWriteResponse(respPath, reqId, actionId, true, "计算器已打开", "")
    PluginShowMainGui()
} else {
    res := CalcEvaluate(text)
    if (res.ok) {
        d := PluginLoadData()
        PluginAppendHistory(d, text, res.text)
        PluginSaveData(d)
        PluginWriteResponse(respPath, reqId, actionId, true, res.text, "", "copy", d.settings.notifyStyle)
    } else {
        PluginWriteResponse(respPath, reqId, actionId, false, "", res.msg)
    }
    ExitApp(0)
}

PluginWriteResponse(respPath, reqId, actionId, ok, text, msg, intent := "notify", notifyStyle := "") {
    q := Chr(34)
    out := "{"
    out .= q "protocolVersion" q ":" q "invoke.v1" q ","
    out .= q "requestId" q ":" q reqId q ","
    out .= q "actionId" q ":" q actionId q ","
    out .= q "ok" q ":" (ok ? "true" : "false") ","
    out .= q "intent" q ":" q intent q ","
    out .= q "text" q ":" q PluginJsonEscape(text) q ","
    out .= q "msg" q ":" q PluginJsonEscape(msg) q ","
    out .= q "code" q ":" q "" q ","
    if (notifyStyle != "")
        out .= q "notifyStyle" q ":" q notifyStyle q ","
    out .= q "silent" q ":false}"
    tmp := respPath ".tmp"
    f := FileOpen(tmp, "w", "UTF-8-RAW")
    f.Write(out), f.Close()
    FileMove(tmp, respPath, 1)
}

PluginReqField(json, field) {
    q := Chr(34)
    pat := "U)" q field q ":" q "(.*)" q
    if RegExMatch(json, pat, &m)
        return m[1]
    return ""
}
