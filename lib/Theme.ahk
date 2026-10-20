#Requires AutoHotkey v2.0

class Theme {
    static COLOR_WIN_BG := "D1D5DB"
    static COLOR_PANEL  := "FFFFFF"
    static COLOR_TEXT   := "1F2937"
    static COLOR_ICON   := "9CA3AF"
    static COLOR_BADGE  := "1F2937"
    static COLOR_HINT   := "9CA3AF"
    static COLOR_ERR    := "CC0000"
    static COLOR_OK     := "00AA00"

    static NORMAL_W := 600, NORMAL_H := 200
    static TURBO_W  := 300, TURBO_H  := 48
    static TURBO_PAD := 12

    static PAD := 24
    static EDIT_BOTTOM_GAP := 90
    static BTN_ROW_GAP := 42

    static BTN_SIZE := 34
    static BTN_GAP  := 38
    static BTN_CLUSTER_GAP := 6
    static TOOLBAR_MAX := 9

    static FONT := "Microsoft YaHei"
    static FONT_EDIT := "s13"
    static FONT_ICON := "s16"
    static FONT_ICON_EMOJI := "s13"
    static FONT_BADGE := "s9"
    static FONT_SETTINGS := "s9"

    static SET_PAGE_X := 15
    static SET_PAGE_Y := 45
    static SET_PAGE_W := 620
    static SET_PAGE_H := 420
    static SET_LIST_X := 25
    static SET_LIST_W := 590
    static SET_BTN_W := 110
    static SET_BTN_H := 26
    static SET_BTN_GAP := 10
    static SET_BTN_INSET := 12
    static SET_LIST_INSET := 12

    static SetBtnY() => Theme.SET_PAGE_Y + Theme.SET_PAGE_H - Theme.SET_BTN_INSET - Theme.SET_BTN_H
    static SetListBottom() => Theme.SetBtnY() - Theme.SET_LIST_INSET

    static SetBtnX(n) => Theme.SET_LIST_X + n * (Theme.SET_BTN_W + Theme.SET_BTN_GAP)

    static ICON_FONT := "Segoe Fluent Icons"

    static IconNeedsIconFont(s) {
        if (Type(s) != "String")
            return false
        Loop Parse s {
            c := Ord(A_LoopField)
            if (c >= 0xE000 && c <= 0xF8FF)
                return true
        }
        return false
    }
}
