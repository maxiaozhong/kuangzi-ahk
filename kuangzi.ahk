#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-SetCompanyName 框子
;@Ahk2Exe-SetProductName 框子
;@Ahk2Exe-SetVersion 0.2.261019
;@Ahk2Exe-SetDescription 全局快捷输入闪窗工具
;@Ahk2Exe-SetMainIcon icon.ico

; ==========================================
; 框子（kuangzi）
; 全局快捷输入：速记/待办/搜索/AI/快捷启动 智能路由
; 双模式：普通模式(600x200) + 极速模式(300x48)，应用内 Ctrl+M 切换
;
; 本文件为组合根入口（Composition Root Entry）。
;
; 作为插件：请勿 #Include 本文件，按需 #Include lib 下模块（加载零副作用）：
;   #Include "lib\ConfigManager.ahk"
;   #Include "lib\QuickNote.ahk"
;   ConfigManager.Init("D:\...\config.json")
;   ^!z::QuickNote.Submit(A_Clipboard, false)   ; 宿主自定绑定，不建 GUI、不抢全局热键
; ==========================================

#Include "lib\JSON.ahk"
#Include "lib\Utils.ahk"
#Include "lib\AppPaths.ahk"
#Include "lib\ConfigManager.ahk"
#Include "lib\QuickNote.ahk"
#Include "lib\QuickSearch.ahk"
#Include "lib\QuickLaunch.ahk"
#Include "lib\Lexicon.ahk"
#Include "lib\Router.ahk"
#Include "lib\NotifyCenter.ahk"
#Include "lib\VoiceRouter.ahk"
#Include "lib\AppShell.ahk"

class Kuangzi {
    ; 独立运行入口：AppShell.Run 内部完成 配置加载 → 建 GUI/托盘/局部热键 → 全局热键 → 首跑引导
    static Run(configPath := "") {
        AppShell.Run(configPath)
    }
}

; 主脚本守卫：被 #Include 时不自启动
; 编译版无条件放行：exe 中 A_LineFile 是编译期烘焙的源码路径，永远 ≠ A_ScriptFullPath(exe 路径)
if (A_IsCompiled || A_LineFile = A_ScriptFullPath)
    Kuangzi.Run()
