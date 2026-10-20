#Requires AutoHotkey v2.0
#Include "Utils.ahk"
#Include "ConfigManager.ahk"
#Include "QuickNote.ahk"
#Include "NotifyCenter.ahk"
#Include "Theme.ahk"
#Include "Actions.ahk"
#Include "Presentation.ahk"
#Include "AttachHelper.ahk"

class MainInput {
    host := 0
    gui := 0
    InputRowsFn := 0

    Bg := "", EditCtrl := ""
    BtnHwnds := [], BtnLabels := Map()
    _modeCtrls := [], _hoverHwnd := 0, _guardFn := 0
    _ctxMenu := 0
    HandCursor := 0

    pendingImages := []
    pendingFiles := []
    _attachSeq := 0
    _attachImgBtn := 0, _attachFileBtn := 0
    _attachImgNum := 0, _attachFileNum := 0
    _slotNearX := 0, _slotFarX := 0, _slotY := 0

    InputHistory := [], HistoryIndex := 0

    _draftRev := 0
    _pendingRev := -1

    DraftRev() {
        return this._draftRev
    }

    DraftUnchanged(rev) {
        return (rev = this._draftRev)
    }

    PendingDraftUnchanged() {
        return (this._pendingRev >= 0 && this.DraftUnchanged(this._pendingRev))
    }

    ConsumePendingRev() {
        this._pendingRev := -1
    }

    _TouchDraft() {
        this._draftRev += 1
    }

    __New(gui, host) {
        this.gui := gui
        this.host := host
        this.HandCursor := DllCall("LoadCursor", "Ptr", 0, "Ptr", 32649, "Ptr")
        OnMessage(0x0201, ObjBindMethod(this, "WM_LBUTTONDOWN"))
        OnMessage(0x0200, ObjBindMethod(this, "OnBtnMouseMove"))
        this.gui.Opt("+E0x10")
        this.gui.OnEvent("DropFiles", (gui, ctrl, files, x, y) => this._OnDropFiles(files))
        this._BuildContextMenu()
        this.Rebuild()
    }

    _BuildContextMenu() {
        ctx := Menu()
        order := ["openNote", "openDir", "settings", "mode", "hide"]
        ctxSet := Map()
        for a in Presentation.For(Presentation.ContextMenu)
            ctxSet[a.id] := a
        for id in order {
            if (!ctxSet.Has(id))
                continue
            ctx.Add(ctxSet[id].label, this._MakeToolClick(ctxSet[id]))
        }
        this._ctxMenu := ctx
        this.gui.OnEvent("ContextMenu", (*) => ctx.Show())
    }

    Rebuild() {
        this.ClearHover()
        for c in this._modeCtrls {
            try DllCall("DestroyWindow", "Ptr", c.Hwnd)
        }
        this._modeCtrls := []
        this.Bg := "", this.EditCtrl := "", this.BtnHwnds := [], this.BtnLabels := Map()
        this._attachImgBtn := 0, this._attachFileBtn := 0
        this._attachImgNum := 0, this._attachFileNum := 0
        this._slotNearX := 0, this._slotFarX := 0, this._slotY := 0
        this.gui.Show("Hide")

        isTurbo := ConfigManager.Get("TurboMode")

        if (isTurbo) {
            w := Theme.TURBO_W, h := Theme.TURBO_H, pad := Theme.TURBO_PAD
            this.Bg := this.gui.Add("Text", "x1 y1 w" w-2 " h" h-2 " Background" Theme.COLOR_PANEL)
            this.EditCtrl := this.gui.Add("Edit", "x" pad " y" pad " w" w-2*pad " h" h-2*pad " -VScroll -E0x200 Background" Theme.COLOR_PANEL " c" Theme.COLOR_TEXT)
            SendMessage(0x1501, 1, StrPtr(""), this.EditCtrl.Hwnd)
            this.EditCtrl.SetFont(Theme.FONT_EDIT, Theme.FONT)
            this.EditCtrl.OnEvent("ContextMenu", (*) => this._ctxMenu.Show())
            this.EditCtrl.OnEvent("Change", (*) => this._TouchDraft())
            this.BtnHwnds := []
            this._modeCtrls := [this.Bg, this.EditCtrl]
        } else {
            w := Theme.NORMAL_W, h := Theme.NORMAL_H
            this.Bg := this.gui.Add("Text", "x1 y1 w" w-2 " h" h-2 " Background" Theme.COLOR_PANEL)
            this.EditCtrl := this.gui.Add("Edit", "x" Theme.PAD " y" Theme.PAD " w" w-2*Theme.PAD " h" h-Theme.EDIT_BOTTOM_GAP " -VScroll -E0x200 Background" Theme.COLOR_PANEL " c" Theme.COLOR_TEXT)
            this.EditCtrl.SetFont(Theme.FONT_EDIT, Theme.FONT)
            this.EditCtrl.OnEvent("ContextMenu", (*) => this._ctxMenu.Show())
            this.EditCtrl.OnEvent("Change", (*) => this._TouchDraft())
            btnY := h - Theme.BTN_ROW_GAP
            this.BtnHwnds := []
            this.BtnLabels := Map()
            this._modeCtrls := [this.Bg, this.EditCtrl]

            btnX := Theme.PAD
            addBtn := this.gui.Add("Text", "x" btnX " y" btnY " w" Theme.BTN_SIZE " h" Theme.BTN_SIZE " Center c" Theme.COLOR_ICON " Background" Theme.COLOR_PANEL, "➕")
            this._ApplyIconFont(addBtn, "➕")
            addBtn.OnEvent("Click", (*) => this._PickAttachments())
            this.BtnHwnds.Push(addBtn.Hwnd)
            this.BtnLabels[addBtn.Hwnd] := "添加附件"
            this._modeCtrls.Push(addBtn)
            for a in Presentation.ToolbarShown() {
                btnX += Theme.BTN_GAP
                btn := this.gui.Add("Text", "x" btnX " y" btnY " w" Theme.BTN_SIZE " h" Theme.BTN_SIZE " Center c" Theme.COLOR_ICON " Background" Theme.COLOR_PANEL, a.icon)
                this._ApplyIconFont(btn, a.icon)
                this.BtnLabels[btn.Hwnd] := a.label
                btn.OnEvent("Click", this._MakeToolClick(a))
                this.BtnHwnds.Push(btn.Hwnd)
                this._modeCtrls.Push(btn)
            }

            C_GAP := Theme.BTN_CLUSTER_GAP
            sendX  := w - Theme.PAD - Theme.BTN_SIZE
            voiceX := sendX - Theme.BTN_SIZE - C_GAP
            nearX := voiceX - Theme.BTN_SIZE - C_GAP
            farX  := nearX  - Theme.BTN_SIZE - C_GAP
            this._slotNearX := nearX, this._slotFarX := farX, this._slotY := btnY
            fileIcon := Chr(0xE723)
            this._attachFileBtn := this.gui.Add("Text", "x" nearX " y" btnY " w" Theme.BTN_SIZE " h" Theme.BTN_SIZE " Center c" Theme.COLOR_ICON " Background" Theme.COLOR_PANEL, fileIcon)
            this._ApplyIconFont(this._attachFileBtn, fileIcon)
            this._attachFileBtn.OnEvent("Click", (*) => this._ShowAttachManager("file"))
            this._modeCtrls.Push(this._attachFileBtn)
            this._attachFileNum := this._NewAttachBadge(nearX, btnY, (*) => this._ShowAttachManager("file"))
            imageIcon := Chr(0xE8B9)
            this._attachImgBtn := this.gui.Add("Text", "x" nearX " y" btnY " w" Theme.BTN_SIZE " h" Theme.BTN_SIZE " Center c" Theme.COLOR_ICON " Background" Theme.COLOR_PANEL, imageIcon)
            this._ApplyIconFont(this._attachImgBtn, imageIcon)
            this._attachImgBtn.OnEvent("Click", (*) => this._ShowAttachManager("image"))
            this._modeCtrls.Push(this._attachImgBtn)
            this._attachImgNum := this._NewAttachBadge(nearX, btnY, (*) => this._ShowAttachManager("image"))
            voiceAction := Actions.Get("voice")
            VoiceBtn := this.gui.Add("Text", "x" voiceX " y" btnY " w" Theme.BTN_SIZE " h" Theme.BTN_SIZE " Center c" Theme.COLOR_ICON " Background" Theme.COLOR_PANEL, voiceAction.icon)
            this._ApplyIconFont(VoiceBtn, voiceAction.icon)
            VoiceBtn.OnEvent("Click", this._MakeToolClick(voiceAction))
            this.BtnHwnds.Push(VoiceBtn.Hwnd)
            this.BtnLabels[VoiceBtn.Hwnd] := voiceAction.label
            this._modeCtrls.Push(VoiceBtn)
            sendIcon := Chr(0xE724)
            SendBtn := this.gui.Add("Text", "x" sendX " y" btnY " w" Theme.BTN_SIZE " h" Theme.BTN_SIZE " Center c" Theme.COLOR_ICON " Background" Theme.COLOR_PANEL, sendIcon)
            this._ApplyIconFont(SendBtn, sendIcon)
            SendBtn.OnEvent("Click", (*) => this._RouteSubmit("submit"))
            this.BtnHwnds.Push(SendBtn.Hwnd)
            this.BtnLabels[SendBtn.Hwnd] := "发送"
            this._modeCtrls.Push(SendBtn)
            this._RefreshAttachSlots()
        }
    }

    _ApplyIconFont(btn, icon) {
        if (Theme.IconNeedsIconFont(icon))
            btn.SetFont(Theme.FONT_ICON, Theme.ICON_FONT)
        else
            btn.SetFont(Theme.FONT_ICON_EMOJI, Theme.FONT)
    }

    _NewAttachBadge(slotX, btnY, handler) {
        b := this.gui.Add("Text", "x" (slotX + Theme.BTN_SIZE - 18) " y" (btnY - 6) " w20 h16 Center c" Theme.COLOR_BADGE " Background" Theme.COLOR_PANEL, "")
        b.SetFont(Theme.FONT_BADGE, Theme.FONT)
        b.OnEvent("Click", handler)
        this._modeCtrls.Push(b)
        return b
    }

    _MakeToolClick(a) {
        return (*) => this._RunAction(a, "toolbar")
    }

    _RunAction(a, source := "toolbar") {
        if (this.HasPendingAttachments() && !(a.HasOwnProp("textAction") && a.textAction)) {
            NotifyCenter.Send("warning", "附件不受支持", "「" a.label "」不消费附件——草稿与暂存已保留（速记/待办可用附件）")
            return
        }
        imgs := [], files := []
        if (this.HasPendingAttachments())
            this._TakePending(&imgs, &files)
        res := Actions.Run(a.id, { text: this.EditCtrl.Value, host: this.host, source: source, images: imgs, files: files })
        if (res = "")
            return
        if (IsObject(res) && res.pending) {
            if (res.action = "plugin")
                this._pendingRev := this.DraftRev()
            return
        }
        if (IsObject(res) && res.action = "")
            return
        if (IsObject(res) && res.ok && imgs.Length + files.Length > 0
            && (res.action = "note" || res.action = "todo" || res.action = "image"))
            this.ConsumePending(imgs, files)
        else if (IsObject(res) && !res.ok && imgs.Length + files.Length > 0)
            NotifyCenter.Send("warning", "附件未消费", "执行未成功，暂存附件已保留，可重试或改用速记")
        this.HandleRouteResult(res)
    }

    _RouteSubmit(mode) {
        imgs := [], files := []
        if (this.HasPendingAttachments())
            this._TakePending(&imgs, &files)
        res := this.host.Route(this.EditCtrl.Value, mode, imgs, files)
        if (IsObject(res) && res.ok && imgs.Length + files.Length > 0
            && (res.action = "note" || res.action = "todo" || res.action = "image"))
            this.ConsumePending(imgs, files)
        else if (IsObject(res) && !res.ok && imgs.Length + files.Length > 0)
            NotifyCenter.Send("warning", "附件未消费", "提交未成功，暂存附件已保留，可重试")
        this.HandleRouteResult(res)
    }

    HandleRouteResult(res) {
        if (!IsObject(res) || res.pending) {
            if (IsObject(res) && res.pending && res.action = "plugin")
                this._pendingRev := this.DraftRev()
            return
        }
        NotifyCenter.FromResult(res)
        if (res.ok) {
            if (res.action = "empty" || res.action = "none") {
                if (res.action = "empty") {
                    if (res.HasOwnProp("text") && Trim(res.text) != "")
                        NotifyCenter.Send("info", "需要关键词", "「" Trim(res.text) "」后面还需要补充内容")
                    else
                        NotifyCenter.Send("info", "输入为空", "这个按钮需要输入内容后再点击")
                }
                NotifyCenter.Shake(this.gui.Hwnd)
                this.EditCtrl.Focus()
                return
            }
            if (res.action = "send") {
                this.EditCtrl.Focus()
                return
            }
            if (res.action = "note" || res.action = "todo" || res.action = "image")
                this.AddInputHistory(res.text)
            this.EditCtrl.Value := ""
            this._TouchDraft()
            this.host.AfterSubmit()
        } else {
            if (res.silent)
                NotifyCenter.Shake(this.gui.Hwnd)
            try this.EditCtrl.Focus()
        }
    }

    HandleEnterAction(*) {
        action := ConfigManager.Get("TurboMode") ? ConfigManager.Get("EnterActionTurbo") : ConfigManager.Get("EnterActionNormal")
        if (action = "newline")
            Send "{Enter}"
        else
            this._RouteSubmit("submit")
    }

    HandleInputHotkey(hk) {
        if (!this.InputRowsFn)
            return
        for r in (this.InputRowsFn)() {
            if (r.key != hk)
                continue
            if (r.action = "submit") {
                this._RouteSubmit("submit")
                return
            }
            if (r.action = "newline") {
                Send "{Enter}"
                return
            }
            a := Actions.Get(r.action)
            if (a != "" && a.kind != "entry") {
                this._RunAction(a, "slot")
                return
            }
        }
    }

    AddInputHistory(text) {
        if (Trim(text) = "")
            return
        this.InputHistory.Push(text)
        if (this.InputHistory.Length > 20)
            this.InputHistory.RemoveAt(1)
        this.HistoryIndex := this.InputHistory.Length + 1
    }

    NavigateHistoryUp(*) {
        if (this.InputHistory.Length = 0)
            return
        if (this.HistoryIndex > 1)
            this.HistoryIndex -= 1
        else
            this.HistoryIndex := 1
        this.EditCtrl.Value := this.InputHistory[this.HistoryIndex]
        this._TouchDraft()
        Send("{End}")
    }

    NavigateHistoryDown(*) {
        if (this.InputHistory.Length = 0)
            return
        if (this.HistoryIndex < this.InputHistory.Length)
            this.HistoryIndex += 1
        else
            this.HistoryIndex := this.InputHistory.Length
        this.EditCtrl.Value := this.InputHistory[this.HistoryIndex]
        this._TouchDraft()
        Send("{End}")
    }

    PasteClipboardToInput(*) {
        clipText := A_Clipboard
        if (clipText != "")
            this.EditCtrl.Value := this.EditCtrl.Value . clipText
        this._TouchDraft()
        this.EditCtrl.Focus()
        Send("{End}")
    }

    WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
        if (this.gui && this.Bg && (hwnd = this.gui.Hwnd || hwnd = this.Bg.Hwnd))
            PostMessage(0xA1, 2, 0, , "ahk_id " this.gui.Hwnd)
    }

    OnBtnMouseMove(wParam, lParam, msg, hwnd) {
        if (!this.BtnHwnds.Length || !this.HandCursor || !this.gui)
            return
        if (hwnd != this.gui.Hwnd && !DllCall("IsChild", "Ptr", this.gui.Hwnd, "Ptr", hwnd, "Int"))
            return
        onBtn := false
        for h in this.BtnHwnds {
            if (hwnd = h) {
                DllCall("SetCursor", "Ptr", this.HandCursor)
                if (this._hoverHwnd != h) {
                    this._hoverHwnd := h
                    tip := this.BtnLabels.Has(h) ? this.BtnLabels[h] : ""
                    if (tip != "") {
                        MouseGetPos(&mx, &my)
                        ToolTip(tip, mx + 20, my + 28)
                        this._StartHoverGuard()
                    }
                }
                onBtn := true
                break
            }
        }
        if (!onBtn && this._hoverHwnd)
            this.ClearHover()
    }

    _StartHoverGuard() {
        if (!this._guardFn)
            this._guardFn := ObjBindMethod(this, "_HoverGuard")
        SetTimer(this._guardFn, 250)
    }

    _HoverGuard() {
        if (!this._hoverHwnd) {
            SetTimer(this._guardFn, 0)
            return
        }
        h := this._hoverHwnd
        try
            WinGetPos(&bx, &by, &bw, &bh, "ahk_id " h)
        catch {
            this.ClearHover()
            return
        }
        if (!DllCall("User32\IsWindowVisible", "Ptr", this.gui.Hwnd) || !this._CursorInRect(bx, by, bw, bh))
            this.ClearHover()
    }

    _CursorInRect(x, y, w, h) {
        pt := Buffer(8, 0)
        DllCall("User32\GetCursorPos", "Ptr", pt)
        cx := NumGet(pt, 0, "Int"), cy := NumGet(pt, 4, "Int")
        return (cx >= x && cx < x + w && cy >= y && cy < y + h)
    }

    ClearHover() {
        this._hoverHwnd := 0
        if (this._guardFn)
            SetTimer(this._guardFn, 0)
        ToolTip()
    }

    Focus() {
        try this.EditCtrl.Focus()
    }

    Clear() {
        this.EditCtrl.Value := ""
        this._TouchDraft()
        this.ClearPendingAttachments()
    }

    _PickAttachments() {
        files := FileSelect("M", "", "选择要添加的图片 / 附件")
        if (files = "")
            return
        n := 0
        for f in files {
            if (this._StashFile(f))
                n++
        }
        if (n > 0)
            this._RefreshAttachSlots()
        else
            NotifyCenter.Send("warning", "附件未接收", "所选文件不在支持范围（图片/视频/音频/文档）或超出大小上限 " AttachHelper.MaxMB() "MB")
        this.EditCtrl.Focus()
    }

    _OnDropFiles(files) {
        reversed := []
        i := files.Length
        while (i > 0) {
            reversed.Push(files[i])
            i--
        }
        n := 0
        for filePath in reversed {
            if (this._StashFile(filePath))
                n++
        }
        if (n > 0)
            this._RefreshAttachSlots()
        else
            NotifyCenter.Send("warning", "附件未接收", "拖入的文件不在支持范围（图片/视频/音频/文档）或超出大小上限")
        this.EditCtrl.Focus()
    }

    _HandlePaste() {
        if (!WinActive("ahk_id " this.gui.Hwnd))
            return

        if (AttachHelper.HasImage()) {
            fileName := AttachHelper.SaveClipboardImage()
            if (fileName != "") {
                this._attachSeq += 1
                this.pendingImages.Push({ src: AttachHelper.AttachDir("image") "\" fileName, name: fileName, seq: this._attachSeq })
                this._RefreshAttachSlots()
            }
            this.EditCtrl.Focus()
            return
        }
        if (AttachHelper.HasFiles()) {
            files := AttachHelper.GetClipboardFiles()
            n := 0
            for filePath in files {
                if (this._StashFile(filePath))
                    n++
            }
            if (n > 0)
                this._RefreshAttachSlots()
            else
                NotifyCenter.Send("warning", "粘贴文件不支持", "剪贴板中的文件不是支持的格式，或超出大小上限 " AttachHelper.MaxMB() "MB")
            this.EditCtrl.Focus()
            return
        }

        this.PasteClipboardToInput()
    }

    _StashFile(srcPath) {
        cat := AttachHelper.Classify(srcPath)
        if (cat = "")
            return false
        try {
            if (FileGetSize(srcPath) / 1048576 > AttachHelper.MaxMB())
                return false
        } catch {
            return false
        }
        SplitPath(srcPath, &name)
        this._attachSeq += 1
        entry := { src: srcPath, name: name, cat: cat, seq: this._attachSeq }
        if (cat = "image")
            this.pendingImages.Push(entry)
        else
            this.pendingFiles.Push(entry)
        return true
    }

    _RefreshAttachSlots() {
        if (this._attachImgBtn = 0)
            return
        hasImg := this.pendingImages.Length > 0
        hasFil := this.pendingFiles.Length > 0
        imgNear := hasImg
        if (hasImg && hasFil)
            imgNear := (this.pendingImages[1].seq < this.pendingFiles[1].seq)
        if (hasImg) {
            names := ""
            for i, e in this.pendingImages
                names .= (i > 1 ? "`n" : "") "图片" i "：" e.name
            x := imgNear ? this._slotNearX : this._slotFarX
            tip := "暂存图片 " this.pendingImages.Length " 张（点击管理）`n" names
            this._attachImgBtn.Move(x, this._slotY)
            this._SetSlot(this._attachImgBtn, true, tip)
            this._SetBadge(this._attachImgNum, this.pendingImages.Length, x, tip)
        } else {
            this._SetSlot(this._attachImgBtn, false, "")
            this._SetBadge(this._attachImgNum, 0, 0, "")
        }
        if (hasFil) {
            names := ""
            for i, e in this.pendingFiles
                names .= (i > 1 ? "`n" : "") "附件" i "：" e.name
            x := imgNear ? this._slotFarX : this._slotNearX
            tip := "暂存附件 " this.pendingFiles.Length " 个（点击管理）`n" names
            this._attachFileBtn.Move(x, this._slotY)
            this._SetSlot(this._attachFileBtn, true, tip)
            this._SetBadge(this._attachFileNum, this.pendingFiles.Length, x, tip)
        } else {
            this._SetSlot(this._attachFileBtn, false, "")
            this._SetBadge(this._attachFileNum, 0, 0, "")
        }
    }

    _SetBadge(badge, n, slotX, tip) {
        if (n = 0) {
            this._SetSlot(badge, false, "")
            return
        }
        badge.Move(slotX + Theme.BTN_SIZE - 18, this._slotY - 6)
        badge.Text := (n > 99) ? "99+" : String(n)
        this._SetSlot(badge, true, tip)
    }

    _SetSlot(btn, show, tip) {
        DllCall("User32\ShowWindow", "Ptr", btn.Hwnd, "Int", show ? 1 : 0)
        if (show) {
            if (!Utils.ArrContains(this.BtnHwnds, btn.Hwnd))
                this.BtnHwnds.Push(btn.Hwnd)
            this.BtnLabels[btn.Hwnd] := tip
        } else {
            idx := 0
            for i, h in this.BtnHwnds {
                if (h = btn.Hwnd) {
                    idx := i
                    break
                }
            }
            if (idx > 0)
                this.BtnHwnds.RemoveAt(idx)
            if (this.BtnLabels.Has(btn.Hwnd))
                this.BtnLabels.Delete(btn.Hwnd)
        }
    }

    _ShowAttachManager(kind) {
        list := (kind = "image") ? this.pendingImages : this.pendingFiles
        if (list.Length = 0)
            return
        title := (kind = "image") ? "暂存图片" : "暂存附件"
        mg := Gui("+AlwaysOnTop -MinimizeBox +Owner" this.gui.Hwnd, title)
        mg.Opt("+OwnDialogs")
        mg.SetFont("s10", "Microsoft YaHei")
        lv := mg.Add("ListView", "x12 y12 w360 h220 -Multi", ["#", "文件名", "类型"])
        lv.ModifyCol(1, 32), lv.ModifyCol(2, 220), lv.ModifyCol(3, 70)
        for i, e in list
            lv.Add("", i, e.name, e.cat)
        btnDel := mg.Add("Button", "x12 y244 w80", "删除")
        btnAll := mg.Add("Button", "x100 y244 w100", "清空全部")
        btnClose := mg.Add("Button", "x290 y244 w82", "关闭")
        DoDel(row) {
            if (row = 0) {
                MsgBox("请先选中一行", title, 48)
                return
            }
            list.RemoveAt(row)
            lv.Delete()
            for i, e in list
                lv.Add("", i, e.name, e.cat)
            this._RefreshAttachSlots()
            if (list.Length = 0)
                mg.Destroy()
        }
        lv.OnEvent("DoubleClick", (ctrl, row) => DoDel(row))
        btnDel.OnEvent("Click", (*) => DoDel(lv.GetNext()))
        DoClearAll() {
            while (list.Length > 0)
                list.RemoveAt(1)
            this._RefreshAttachSlots()
            mg.Destroy()
        }
        btnAll.OnEvent("Click", (*) => DoClearAll())
        btnClose.OnEvent("Click", (*) => mg.Destroy())
        mg.OnEvent("Escape", (*) => mg.Destroy())
        mg.OnEvent("Close", (*) => mg.Destroy())
        mg.Show("w384 h284")
    }

    ClearPendingAttachments() {
        while (this.pendingImages.Length > 0)
            this.pendingImages.RemoveAt(1)
        while (this.pendingFiles.Length > 0)
            this.pendingFiles.RemoveAt(1)
        this._RefreshAttachSlots()
    }

    HasPendingAttachments() {
        return (this.pendingImages.Length > 0 || this.pendingFiles.Length > 0)
    }

    _TakePending(&imgs, &files) {
        imgs := [], files := []
        for e in this.pendingImages {
            ref := AttachHelper.Attach(e.src)
            if (ref != "" && ref != "__OVERSIZE__")
                imgs.Push(ref)
        }
        for e in this.pendingFiles {
            ref := AttachHelper.Attach(e.src)
            if (ref != "" && ref != "__OVERSIZE__")
                files.Push(ref)
        }
        if (imgs.Length + files.Length = 0 && this.HasPendingAttachments())
            NotifyCenter.Send("warning", "附件未落库", "暂存附件物化失败，已跳过（正文照常提交）")
    }

    ConsumePending(imgs, files) {
        used := Map()
        for r in imgs
            used[r] := true
        for r in files
            used[r] := true
        i := this.pendingImages.Length
        while (i >= 1) {
            ref := AttachHelper.Attach(this.pendingImages[i].src)
            if (used.Has(ref))
                this.pendingImages.RemoveAt(i)
            i--
        }
        i := this.pendingFiles.Length
        while (i >= 1) {
            ref := AttachHelper.Attach(this.pendingFiles[i].src)
            if (used.Has(ref))
                this.pendingFiles.RemoveAt(i)
            i--
        }
        this._RefreshAttachSlots()
    }

    _InsertRefText(refText) {
        fullText := this.EditCtrl.Value
        selRet := SendMessage(0x00B0, 0, 0, this.EditCtrl.Hwnd)
        insertPos := selRet & 0xFFFF

        fence := "``````"
        if (SubStr(refText, 1, 3) = fence)
            refText := "`n" refText

        before := SubStr(fullText, 1, insertPos)
        after := SubStr(fullText, insertPos + 1)
        this.EditCtrl.Value := before . refText . after
        this._TouchDraft()

        this.EditCtrl.Focus()
        newPos := StrLen(before) + StrLen(refText)
        PostMessage 0x00B1, newPos, newPos, this.EditCtrl.Hwnd
        PostMessage 0x00B1, newPos, newPos, this.EditCtrl.Hwnd
    }
}
