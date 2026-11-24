-- Keyzen options: the Edit Mode settings dialog (click the frame while Edit Mode is open)
-- and the panel under Interface -> AddOns -> Keyzen. Everything is also reachable via /keyzen.

local ADDON, ns = ...

-------------------------------------------------------------------------------
-- Widgets
-------------------------------------------------------------------------------
local function CheckBox(parent, label, tooltip, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    cb:SetHitRectInsets(0, -text:GetStringWidth() - 4, 0, 0)
    cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return cb
end

local function Slider(parent, label, minV, maxV, step, get, set, fmt, width)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetWidth(width or 180)
    -- the template's own labels have no parentKey on every client; use our own
    for _, r in ipairs({ s:GetRegions() }) do if r:GetObjectType() == "FontString" then r:SetText("") end end
    local low = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 2, 0); low:SetText(minV)
    local high = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -2, 0); high:SetText(maxV)
    local text = s:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("BOTTOM", s, "TOP", 0, 2)
    fmt = fmt or "%s"
    s:SetScript("OnShow", function(self)
        self.loading = true; self:SetValue(get()); self.loading = false
        text:SetText(label .. ": " .. fmt:format(get()))
    end)
    s:SetScript("OnValueChanged", function(self, v)
        text:SetText(label .. ": " .. fmt:format(v))
        if not self.loading then set(v) end
    end)
    return s
end

local function Button(parent, label, onClick, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetText(label)
    b:SetSize(width or 140, 22)
    b:SetScript("OnClick", onClick)
    return b
end

-------------------------------------------------------------------------------
-- Shared setting definitions
-------------------------------------------------------------------------------
local function AddSettingControls(parent, anchor, compact)
    local db = ns.db
    local w = compact and 150 or 180
    local scale = Slider(parent, "Scale", 0.5, 2, 0.05,
        function() return db.scale end, function(v) db.scale = v; ns.Layout() end, "%.2f", w)
    scale:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 8, -24)

    local size = Slider(parent, "Key size", 24, 64, 1,
        function() return db.cellSize end, function(v) db.cellSize = math.floor(v); ns.Layout() end, "%d", w)
    size:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, -34)

    local gap = Slider(parent, "Key padding", 0, 12, 0.5,
        function() return db.gap end, function(v) db.gap = v; ns.Layout() end, "%.1f", w)
    gap:SetPoint("TOPLEFT", size, "BOTTOMLEFT", 0, -34)

    local rowGap = Slider(parent, "Row padding", 0, 24, 0.5,
        function() return db.rowGap end, function(v) db.rowGap = v; ns.Layout() end, "%.1f", w)
    rowGap:SetPoint("TOPLEFT", gap, "BOTTOMLEFT", 0, -34)

    local alpha = Slider(parent, "Opacity", 0.1, 1, 0.05,
        function() return db.alpha end, function(v) db.alpha = v; ns.Layout() end, "%.2f", w)
    alpha:SetPoint("TOPLEFT", rowGap, "BOTTOMLEFT", 0, -34)

    local last = alpha
    local function Next(cb, gapY)
        cb:SetPoint("TOPLEFT", last, "BOTTOMLEFT", last == alpha and -8 or 0, gapY or -2)
        last = cb
        return cb
    end

    -- which parts of the keypad to draw
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", alpha, "BOTTOMLEFT", -8, -18)
    header:SetText("Show")
    last = header
    for _, section in ipairs(ns.SECTIONS) do
        Next(CheckBox(parent, section.label, nil,
            function() return db.sections[section.key] ~= false end,
            function(v) db.sections[section.key] = v; ns.Layout(); ns.Refresh() end), -2)
    end

    Next(CheckBox(parent, compact and "Lefty (mirrored)" or "Lefty Keyzen (mirrored, right-hand model)",
        "Use the mirrored layout of the right-handed Keyzen.",
        function() return db.lefty end, function(v) db.lefty = v; ns.Layout() end), -10)

    Next(CheckBox(parent, compact and "Always show empty keys" or "Always show empty keys (like 'Always Show Buttons')",
        "Draw keys that have nothing on them outside Edit Mode.",
        function() return db.showEmpty end, function(v) db.showEmpty = v; ns.Refresh() end))

    Next(CheckBox(parent, compact and "Show key text" or "Show key text on buttons", nil,
        function() return db.showKeys end, function(v) db.showKeys = v; ns.Refresh() end))

    Next(CheckBox(parent, "Hide bar art", "Hides the emblem art inside empty keys, like the action bar option.",
        function() return db.hideBarArt end, function(v) db.hideBarArt = v; ns.Refresh() end))

    Next(CheckBox(parent, compact and "Claim empty keys" or "Claim the keys of empty slots too",
        "When enabled, a Keyzen key with nothing on it does nothing instead of falling through to the Blizzard action bars.",
        function() return db.bindEmpty end, function(v) db.bindEmpty = v; ns.Refresh() end))

    Next(CheckBox(parent, compact and "Follow spell ranks" or "Follow new spell ranks automatically",
        "When you learn a higher rank of a spell that is on a key, the key switches to the new rank.",
        function() return db.autoRank end, function(v) db.autoRank = v end))

    return last
end

-------------------------------------------------------------------------------
-- Edit Mode dialog: built from the same pieces as Blizzard's EditModeSystemSettingsDialog
-- (DialogBorderTranslucentTemplate, GameFontHighlightLarge title, UIPanelCloseButton,
-- rows of GameFontHighlightMedium label + MinimalSliderWithSteppersTemplate, 32px check
-- buttons, 330x28 UIPanelButtonTemplate buttons). It is movable and not attached to the frame.
-------------------------------------------------------------------------------
local dialog
local ROW_H, ROW_SPACING, ROW_W = 32, 2, 343

local function RoundToStep(v, minV, step)
    local n = math.floor((v - minV) / step + 0.5)
    local r = minV + n * step
    return tonumber(("%.4f"):format(r))
end

-- Slider row. Uses Blizzard's steppered slider when the client has it, else the classic one.
local function SliderRow(parent, label, minV, maxV, step, get, set, fmt)
    fmt = fmt or "%s"
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(ROW_W, ROW_H)
    row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    row.Label:SetSize(100, ROW_H)
    row.Label:SetJustifyH("LEFT")
    row.Label:SetPoint("LEFT")
    row.Label:SetText(label)

    local steps = math.floor((maxV - minV) / step + 0.5)
    local function format(v)
        local r = RoundToStep(v, minV, step)
        if type(fmt) == "function" then return fmt(r) end
        return fmt:format(r)
    end

    if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
        slider:SetSize(200, ROW_H)
        slider:SetPoint("LEFT", row.Label, "RIGHT", 5, 0)
        local formatters = {}
        local right = MinimalSliderWithSteppersMixin.Label.Right
        local okF, f = pcall(function() return CreateMinimalSliderFormatter(right, format) end)
        formatters[right] = (okF and type(f) == "function") and f or format
        row.Slider = slider
        row.Refresh = function()
            row.loading = true
            slider:Init(get(), minV, maxV, steps, formatters)
            row.loading = false
        end
        slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
            if not row.loading then set(RoundToStep(v, minV, step)) end
        end, row)
    else
        local s = Slider(row, label, minV, maxV, step, get, set, type(fmt) == "string" and fmt or "%.2f", 200)
        s:SetPoint("LEFT", row.Label, "RIGHT", 5, 0)
        row.Refresh = function() s:GetScript("OnShow")(s) end
    end
    return row
end

local function CheckRow(parent, label, tooltip, get, set)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(ROW_W, ROW_H)
    local cb = CreateFrame("CheckButton", nil, row)
    cb:SetSize(32, 32)
    cb:SetPoint("LEFT", -5, 0)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    row.Label:SetSize(300, ROW_H)
    row.Label:SetJustifyH("LEFT")
    row.Label:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    row.Label:SetText(label)
    cb:SetHitRectInsets(0, -row.Label:GetStringWidth() - 5, 0, 0)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    row.Refresh = function() cb:SetChecked(get()) end
    return row
end

local function CreateEditDialog()
    local db = ns.db
    dialog = CreateFrame("Frame", "KeyzenEditDialog", UIParent)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(200)
    dialog:SetMovable(true)
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dialog:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self.moved = true end)
    dialog:Hide()

    local okBorder = pcall(function()
        dialog.Border = CreateFrame("Frame", nil, dialog, "DialogBorderTranslucentTemplate")
        dialog.Border:SetAllPoints()
    end)
    if not okBorder and BackdropTemplateMixin then
        Mixin(dialog, BackdropTemplateMixin)
        dialog:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    dialog.Title = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    dialog.Title:SetPoint("TOP", 0, -15)
    dialog.Title:SetText("Keyzen")

    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    close:SetScript("OnClick", function() ns.DeselectInEditMode() end)

    dialog.rows = {}
    local function Add(row)
        local prev = dialog.rows[#dialog.rows]
        if prev then row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -ROW_SPACING)
        else row:SetPoint("TOP", dialog.Title, "BOTTOM", 0, -12); row:SetPoint("LEFT", dialog, "LEFT", 20, 0) end
        dialog.rows[#dialog.rows + 1] = row
        return row
    end

    Add(SliderRow(dialog, "Scale", 0.5, 2, 0.05,
        function() return db.scale end, function(v) db.scale = v; ns.Layout() end, "%.2f"))
    Add(SliderRow(dialog, "Key Size", 24, 64, 1,
        function() return db.cellSize end, function(v) db.cellSize = math.floor(v); ns.Layout() end, "%d"))
    Add(SliderRow(dialog, "Key Padding", 0, 12, 0.5,
        function() return db.gap end, function(v) db.gap = v; ns.Layout() end, "%.1f"))
    Add(SliderRow(dialog, "Row Padding", 0, 24, 0.5,
        function() return db.rowGap end, function(v) db.rowGap = v; ns.Layout() end, "%.1f"))
    Add(SliderRow(dialog, "Opacity", 0.1, 1, 0.05,
        function() return db.alpha end, function(v) db.alpha = v; ns.Layout() end,
        function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end))
    for _, section in ipairs(ns.SECTIONS) do
        Add(CheckRow(dialog, "Show " .. section.label, nil,
            function() return db.sections[section.key] ~= false end,
            function(v) db.sections[section.key] = v; ns.Layout(); ns.Refresh() end))
    end
    Add(CheckRow(dialog, "Lefty Keyzen (Mirrored)", "Use the mirrored layout of the right-handed Keyzen.",
        function() return db.lefty end, function(v) db.lefty = v; ns.Layout() end))
    Add(CheckRow(dialog, "Always Show Buttons", "Draw keys that have nothing on them outside Edit Mode.",
        function() return db.showEmpty end, function(v) db.showEmpty = v; ns.Refresh() end))
    Add(CheckRow(dialog, "Show Key Text", nil,
        function() return db.showKeys end, function(v) db.showKeys = v; ns.Refresh() end))
    Add(CheckRow(dialog, "Hide Bar Art", "Hides the emblem art inside empty keys, like the action bar option.",
        function() return db.hideBarArt end, function(v) db.hideBarArt = v; ns.Refresh() end))
    Add(CheckRow(dialog, "Claim Keys Of Empty Slots",
        "A Keyzen key with nothing on it does nothing instead of falling through to the Blizzard action bars.",
        function() return db.bindEmpty end, function(v) db.bindEmpty = v; ns.Refresh() end))
    Add(CheckRow(dialog, "Follow New Spell Ranks",
        "When you learn a higher rank of a spell that is on a key, the key switches to the new rank.",
        function() return db.autoRank end, function(v) db.autoRank = v end))

    local lastRow = dialog.rows[#dialog.rows]
    local resetPos = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    resetPos:SetSize(330, 28)
    resetPos:SetText("Reset To Default Position")
    resetPos:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, -12)
    resetPos:SetScript("OnClick", function() ns.ResetPosition() end)
    local resetKeys = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    resetKeys:SetSize(330, 28)
    resetKeys:SetText("Reset Key Mapping")
    resetKeys:SetPoint("TOPLEFT", resetPos, "BOTTOMLEFT", 0, -2)
    resetKeys:SetScript("OnClick", function() wipe(db.keys); ns.Refresh(); ns.Print("default keys restored.") end)

    -- size like ResizeLayoutFrame with widthPadding/heightPadding 40
    local height = 15 + 20 + 12 + #dialog.rows * (ROW_H + ROW_SPACING) + 12 + 28 + 2 + 28
    dialog:SetSize(ROW_W + 40, height + 40)
end

function ns.PositionEditDialog()
    -- Blizzard parks the dialog on the right of the screen; it stays where the player drags it.
    if not dialog or dialog.moved then return end
    dialog:ClearAllPoints()
    dialog:SetPoint("RIGHT", UIParent, "RIGHT", -40, 60)
end

function ns.ShowEditDialog()
    if not dialog then CreateEditDialog() end
    for _, row in ipairs(dialog.rows) do row.Refresh() end
    ns.PositionEditDialog()
    dialog:Show()
end

function ns.HideEditDialog()
    if dialog then dialog:Hide() end
end

-------------------------------------------------------------------------------
-- Interface options panel
-------------------------------------------------------------------------------
local panel

function ns.SetupOptions()
    if panel then return end
    local db = ns.db
    panel = CreateFrame("Frame")
    panel.name = "Keyzen"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cff7be5e0Keyzen|r")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText("Your Azeron Keyzen on screen. Drag spells, items or macros from your spellbook, bags or " ..
        "macro window onto the keys and press those keys on the Keyzen to use them. Move and resize the frame " ..
        "in Edit Mode, where you can also hover a key and press a keyboard key to change what that Keyzen " ..
        "button is expected to send.\n\nImport the shipped Azeron profile (AzeronProfile folder of the addon) in " ..
        "the Azeron Software so the device sends exactly the keys the addon expects. Slash command: /keyzen")

    local edit = Button(panel, "Open Edit Mode", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        ns.OpenEditMode()
    end)
    edit:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)

    local resetPos = Button(panel, "Reset position", function() ns.ResetPosition() end)
    resetPos:SetPoint("LEFT", edit, "RIGHT", 8, 0)

    local resetKeys = Button(panel, "Reset key mapping", function()
        wipe(db.keys); ns.Refresh(); ns.Print("default keys restored.")
    end)
    resetKeys:SetPoint("LEFT", resetPos, "RIGHT", 8, 0)

    local last = AddSettingControls(panel, edit, false)

    local hidden = CheckBox(panel, "Hide the Keyzen frame",
        "Hides the frame and releases all its keybinds.",
        function() return db.hidden end, function(v) ns.SetHidden(v) end)
    hidden:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "Keyzen")
        Settings.RegisterAddOnCategory(category)
        ns.optionsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function ns.OpenOptions()
    if not panel then ns.SetupOptions() end
    if Settings and Settings.OpenToCategory and ns.optionsCategory then
        Settings.OpenToCategory(ns.optionsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
