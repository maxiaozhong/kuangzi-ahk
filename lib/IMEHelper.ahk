#Requires AutoHotkey v2.0

class IMEHelper {
    static EnsureIME(switchKey) {
        if (switchKey = "")
            return true
        try {
            Send(switchKey)
            Sleep 50
            return true
        } catch {
            return false
        }
    }
}
