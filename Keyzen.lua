-- Keyzen: draws the Azeron Keyzen on screen with the default action bar art. Drop a spell /
-- item / macro on a key and the key becomes a keybind for it (secure action buttons +
-- override bindings, combat safe). Position and size are edited through Blizzard's Edit Mode.

local ADDON, ns = ...

local Keyzen = CreateFrame("Frame", "KeyzenFrame", UIParent)
ns.frame = Keyzen

local BUTTON_PREFIX = "KeyzenButton"   -- visible button: mouse clicks, acts on release
local PROXY_PREFIX  = "KeyzenKey"      -- hidden secure button: what the keybind clicks
local db, cdb                     -- account settings / per-character slots
local buttons = {}                -- code -> button frame
local editMode = false            -- Blizzard Edit Mode is open
local bindingsDirty, attributesDirty = false, false
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local VERSION = GetMeta and GetMeta(ADDON, "Version") or "dev"

local DEFAULTS = {
    lefty      = false,
    scale      = 1.0,
    alpha      = 1.0,
    cellSize   = 45,     -- Blizzard action buttons are 45x45
    gap        = 2,      -- horizontal padding between keys (Blizzard's default "Icon Padding")
    rowGap     = 2,      -- vertical padding between rows (raise it to line up with stacked bars)
    showEmpty  = true,   -- draw empty keys outside Edit Mode ("Always show buttons")
    showKeys   = true,   -- show the key text on each button
    hideBarArt = true,   -- Blizzard's "Hide Bar Art": no emblem art inside empty keys
    bindEmpty  = false,  -- also claim keys of empty slots (blocks the Blizzard bars on those keys)
    autoRank   = true,   -- follow new spell ranks automatically
    hidden     = false,
    sections   = { fingers = true, dpad = true, side = true },  -- which parts of the keypad to draw
    point      = { "BOTTOM", "UIParent", "BOTTOM", 300, 12 },
    keys       = {},     -- code -> WoW key string (overrides ns.DEFAULT_KEYS); false = no key
}
ns.DEFAULTS = DEFAULTS

local function Print(msg, ...)
    print("|cff7be5e0Keyzen:|r " .. tostring(msg), ...)
end
ns.Print = Print

-------------------------------------------------------------------------------
-- API shims (the Forever client has the C_* namespaces, but stay defensive)
-------------------------------------------------------------------------------
local function SpellInfo(idOrName)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(idOrName)
        if info then return info.name, info.iconID, info.spellID end
    elseif GetSpellInfo then
        local name, _, icon, _, _, _, spellID = GetSpellInfo(idOrName)
        return name, icon, spellID
    end
end

local function SpellTexture(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellTexture then return GetSpellTexture(id) end
end

local function SpellCooldown(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local c = C_Spell.GetSpellCooldown(id)
        if c then return c.startTime, c.duration, c.isEnabled, c.modRate end
        return
    end
    if GetSpellCooldown then return GetSpellCooldown(id) end
end

local function SpellUsable(id)
    if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(id) end
    if IsUsableSpell then return IsUsableSpell(id) end
    return true, false
end

local function SpellInRange(id, name)
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, r = pcall(C_Spell.IsSpellInRange, id, "target")
        if ok then return r end
    end
    if IsSpellInRange and name then
        local r = IsSpellInRange(name, "target")
        if r == nil then return nil end
        return r == 1
    end
end

local function IsKnownSpell(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(id) then return true end
    return false
end

local function ItemName(id)
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
    if GetItemInfo then return (GetItemInfo(id)) end
end

local function ItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    if GetItemIcon then return GetItemIcon(id) end
end

local function ItemCount(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, false, true) end
    if GetItemCount then return GetItemCount(id, false, true) end
    return 0
end

local function ItemCooldown(id)
    if C_Item and C_Item.GetItemCooldown then return C_Item.GetItemCooldown(id) end
    if GetItemCooldown then return GetItemCooldown(id) end
end

local function ItemUsable(id)
    if C_Item and C_Item.IsUsableItem then return C_Item.IsUsableItem(id) end
    if IsUsableItem then return IsUsableItem(id) end
    return true, false
end

local function ItemInRange(id)
    local f = (C_Item and C_Item.IsItemInRange) or IsItemInRange
    if not f then return nil end
    local ok, r = pcall(f, id, "target")
    if not ok then return nil end
    if r == 1 then return true elseif r == 0 then return false end
    return r
end

local function PickupSpellID(id)
    if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(id) elseif PickupSpell then PickupSpell(id) end
end

local function PickupItemID(id)
    if C_Item and C_Item.PickupItem then C_Item.PickupItem(id) elseif PickupItem then PickupItem(id) end
end

local function CVarBool(name, default)
    if GetCVarBool then
        local ok, v = pcall(GetCVarBool, name)
        if ok and v ~= nil then return v and true or false end
    end
    return default
end

-- Keys WoW refuses to bind; they are shown but never claimed.
local UNBINDABLE = { ESCAPE = true }

-- Midnight-era clients (Forever included) hand addons "secret" values for combat-sensitive
-- data such as cooldowns. A secret value can be passed on to widgets but any comparison or
-- arithmetic on it is a Lua error, so every such value is checked before it is inspected.
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

-- Blizzard's "Lock Action Bars": dragging an action off a bar needs the pickup modifier.
local function CanPickUp()
    if editMode then return true end
    if not CVarBool("lockActionBars", true) then return true end
    if IsModifiedClick and IsModifiedClick("PICKUPACTION") then return true end
    return false
end

-- Set an atlas when the client has it, otherwise fall back to a classic texture file.
local function SetAtlasOr(tex, atlas, file, ...)
    local ok = pcall(tex.SetAtlas, tex, atlas)
    if ok and tex:GetAtlas() == atlas then return true end
    if file then tex:SetTexture(file, ...) end
    return false
end

-------------------------------------------------------------------------------
-- Settings helpers
-------------------------------------------------------------------------------
local function InitDB()
    KeyzenDB = KeyzenDB or {}
    for k, v in pairs(DEFAULTS) do
        if KeyzenDB[k] == nil then
            if type(v) == "table" then
                local t = {}
                for kk, vv in pairs(v) do t[kk] = vv end
                KeyzenDB[k] = t
            else
                KeyzenDB[k] = v
            end
        end
    end
    if (KeyzenDB.layoutVersion or 1) < 3 then
        -- early versions used other sizes; match Blizzard's action buttons (45px, padding 2)
        KeyzenDB.cellSize, KeyzenDB.gap = DEFAULTS.cellSize, DEFAULTS.gap
        KeyzenDB.layoutVersion = 3
    end
    for k, v in pairs(DEFAULTS.sections) do
        if KeyzenDB.sections[k] == nil then KeyzenDB.sections[k] = v end
    end
    KeyzenCharDB = KeyzenCharDB or {}
    KeyzenCharDB.slots = KeyzenCharDB.slots or {}
    db, cdb = KeyzenDB, KeyzenCharDB
    ns.db, ns.cdb = db, cdb
end

local function GetKey(code)
    local k = db.keys[code]
    if k == nil then return ns.DEFAULT_KEYS[code] end
    if k == false then return nil end
    return k
end
ns.GetKey = GetKey

-- Short key text, the way Blizzard shows it on action buttons ("s-1", "c-1", "a-1").
-- Blizzard's own abbreviation still spells out "Up Arrow" and "Space", which does not fit
-- on a button, so the long names are shortened here.
local SHORT_KEYS = {
    SPACE = "Spc", UP = "Up", DOWN = "Dn", LEFT = "Lt", RIGHT = "Rt",
    PAGEUP = "PgU", PAGEDOWN = "PgD", BACKSPACE = "Bks", INSERT = "Ins", DELETE = "Del",
    HOME = "Hm", END = "End", TAB = "Tab", ENTER = "Ent", ESCAPE = "Esc", CAPSLOCK = "Cap",
    MOUSEWHEELUP = "WUp", MOUSEWHEELDOWN = "WDn", NUMPADPLUS = "N+", NUMPADMINUS = "N-",
    NUMPADMULTIPLY = "N*", NUMPADDIVIDE = "N/", NUMPADDECIMAL = "N.", PRINTSCREEN = "PrS",
}
local function KeyLabel(key)
    if not key then return "" end
    local mods, base = key:match("^(.-)([^%-]+)$")
    if base == "" or base == nil then base = "-"; mods = key:sub(1, -2) end
    local text = SHORT_KEYS[base] or base:gsub("^NUMPAD", "N"):gsub("^BUTTON", "M")
    mods = mods:gsub("ALT%-", "a-"):gsub("CTRL%-", "c-"):gsub("SHIFT%-", "s-")
    return mods .. text
end

-------------------------------------------------------------------------------
-- Slot data (what is on a key)
-------------------------------------------------------------------------------
-- slot = { kind = "spell"|"item"|"macro", id = number, name = string }

local function SlotIcon(slot)
    if not slot then return nil end
    if slot.kind == "spell" then return SpellTexture(slot.id) or SpellTexture(slot.name) end
    if slot.kind == "item" then return ItemIcon(slot.id) end
    if slot.kind == "macro" then
        local _, icon = GetMacroInfo(slot.name)
        return icon
    end
end

local function SlotFromCursor()
    local kind, a, b, c = GetCursorInfo()
    if not kind then return nil end
    if kind == "spell" then
        local spellID = c or a
        local name = SpellInfo(spellID)
        if not name then return nil end
        return { kind = "spell", id = spellID, name = name }
    elseif kind == "item" then
        return { kind = "item", id = a, name = ItemName(a) or ("item:" .. a) }
    elseif kind == "macro" then
        local name = GetMacroInfo(a)
        if not name then return nil end
        return { kind = "macro", id = a, name = name }
    elseif kind == "mount" then
        if C_MountJournal and C_MountJournal.GetMountInfoByID then
            local name, spellID = C_MountJournal.GetMountInfoByID(a)
            if spellID then return { kind = "spell", id = spellID, name = name } end
        end
        return nil, "Mounts from the mount journal are not supported here; drag the mount spell from your spellbook instead."
    elseif kind == "companion" then
        if GetCompanionInfo then
            local _, name, spellID = GetCompanionInfo(b, a)
            if spellID then return { kind = "spell", id = spellID, name = name } end
        end
        return nil, "That companion could not be resolved to a spell."
    elseif kind == "petaction" then
        return nil, "Pet abilities are not supported. Use a macro (/cast Growl) instead."
    end
    return nil, "Cannot place a '" .. tostring(kind) .. "' here."
end

local function PickupSlot(slot)
    if not slot then return end
    if slot.kind == "spell" then PickupSpellID(slot.id)
    elseif slot.kind == "item" then PickupItemID(slot.id)
    elseif slot.kind == "macro" then
        local idx = GetMacroIndexByName and GetMacroIndexByName(slot.name) or slot.id
        if idx and idx > 0 then PickupMacro(idx) end
    end
end

-------------------------------------------------------------------------------
-- Button visuals and secure attributes
-------------------------------------------------------------------------------
local function ApplyAttributesTo(frame, slot)
    -- The plain "type" attribute is used (not "type1") so that modified bindings such as
    -- SHIFT-1 still resolve; "*type2" = "" keeps right-click inert.
    frame:SetAttribute("type", nil)
    frame:SetAttribute("*type2", "")
    frame:SetAttribute("spell", nil)
    frame:SetAttribute("item", nil)
    frame:SetAttribute("macro", nil)
    if not slot then return end
    if slot.kind == "spell" then
        frame:SetAttribute("type", "spell")
        frame:SetAttribute("spell", slot.id)
    elseif slot.kind == "item" then
        frame:SetAttribute("type", "item")
        frame:SetAttribute("item", "item:" .. slot.id)
    elseif slot.kind == "macro" then
        frame:SetAttribute("type", "macro")
        frame:SetAttribute("macro", slot.name)
    end
end

local function ApplyAttributes(btn)
    -- Only called out of combat. The visible button and its key proxy carry the same action.
    local slot = cdb.slots[btn.code]
    ApplyAttributesTo(btn, slot)
    ApplyAttributesTo(btn.proxy, slot)
end

local function UpdateCooldown(btn)
    local slot = cdb.slots[btn.code]
    if not slot or slot.kind == "macro" then btn.cooldown:Clear(); return end
    local start, duration, enable, modRate
    if slot.kind == "spell" then start, duration, enable, modRate = SpellCooldown(slot.id)
    else start, duration, enable = ItemCooldown(slot.id) end
    if IsSecret(start) or IsSecret(duration) or IsSecret(enable) or IsSecret(modRate) then
        -- In combat the numbers are secret: they cannot be inspected, only shown.
        if not IsSecret(modRate) and modRate == nil then
            btn.cooldown:SetCooldown(start, duration)
        else
            btn.cooldown:SetCooldown(start, duration, modRate)
        end
        return
    end
    if enable == false or enable == 0 or not start or not duration or duration <= 0 then
        btn.cooldown:Clear()
    else
        btn.cooldown:SetCooldown(start, duration, modRate or 1)
    end
end

local HOTKEY_COLOR = ACTIONBAR_HOTKEY_FONT_COLOR or { r = 0.6, g = 0.6, b = 0.6 }
local RANGE_COLOR  = RED_FONT_COLOR or { r = 1, g = 0.1, b = 0.1 }

local function UpdateState(btn)
    -- Same rules as Blizzard's action buttons: icon tint for usable / no power, hotkey text
    -- turns red when the target is out of range.
    local slot = cdb.slots[btn.code]
    if not slot then return end
    local usable, noPower, inRange = true, false, nil
    if slot.kind == "spell" then
        usable, noPower = SpellUsable(slot.id)
        inRange = SpellInRange(slot.id, slot.name)
    elseif slot.kind == "item" then
        usable, noPower = ItemUsable(slot.id)
        inRange = ItemInRange(slot.id)
        local count = ItemCount(slot.id)
        if IsSecret(count) then btn.Count:SetText("")
        else btn.Count:SetText(count > 1 and count or "") end
    end
    -- secret in combat: leave the colouring alone rather than inspect the values
    if IsSecret(usable) then usable = true end
    if IsSecret(noPower) then noPower = false end
    if IsSecret(inRange) then inRange = nil end
    local icon = btn.icon
    if usable then icon:SetVertexColor(1, 1, 1)
    elseif noPower then icon:SetVertexColor(0.5, 0.5, 1.0)
    else icon:SetVertexColor(0.4, 0.4, 0.4) end
    if inRange == false then btn.HotKey:SetTextColor(RANGE_COLOR.r, RANGE_COLOR.g, RANGE_COLOR.b)
    else btn.HotKey:SetTextColor(HOTKEY_COLOR.r, HOTKEY_COLOR.g, HOTKEY_COLOR.b) end
end

local function UpdateButtonLook(btn)
    local slot = cdb.slots[btn.code]
    local key = GetKey(btn.code)
    btn.HotKey:SetText(db.showKeys and KeyLabel(key) or "")
    btn.HotKey:SetTextColor(HOTKEY_COLOR.r, HOTKEY_COLOR.g, HOTKEY_COLOR.b)
    btn.Name:SetText("")
    btn.SlotArt:SetShown(not db.hideBarArt)
    if slot then
        btn.icon:SetTexture(SlotIcon(slot) or "Interface\\Icons\\INV_Misc_QuestionMark")
        btn.icon:Show()
        btn:SetAlpha(1)
        UpdateCooldown(btn)
        UpdateState(btn)
    else
        btn.icon:Hide()
        btn.icon:SetVertexColor(1, 1, 1)
        btn.Count:SetText("")
        btn.cooldown:Clear()
        if editMode then
            btn:SetAlpha(1)
            if not key then btn.Name:SetText("no key") end
        else
            btn:SetAlpha(db.showEmpty and 1 or 0)
        end
    end
end

local function UpdateAll()
    for _, btn in pairs(buttons) do UpdateButtonLook(btn) end
end

-------------------------------------------------------------------------------
-- Bindings (override bindings owned by KeyzenFrame; cleared/re-applied as one set)
-------------------------------------------------------------------------------
local function IsCodeShown(code)
    local section = ns.SECTION_OF[code]
    return section == nil or db.sections[section] ~= false
end
ns.IsCodeShown = IsCodeShown

local function ApplyBindings()
    if InCombatLockdown() then bindingsDirty = true; return end
    bindingsDirty = false
    ClearOverrideBindings(Keyzen)
    if db.hidden then return end
    for _, code in ipairs(ns.BUTTON_CODES) do
        local key = GetKey(code)
        if key and not UNBINDABLE[key] and IsCodeShown(code) and (db.bindEmpty or cdb.slots[code]) then
            -- the key clicks the hidden proxy, which honours "cast on key down" like a Blizzard bar
            SetOverrideBindingClick(Keyzen, true, key, PROXY_PREFIX .. code, "LeftButton")
        end
    end
end

local function ApplyAttributesAll()
    if InCombatLockdown() then attributesDirty = true; return end
    attributesDirty = false
    for _, btn in pairs(buttons) do ApplyAttributes(btn) end
end

local function Refresh()
    ApplyAttributesAll()
    ApplyBindings()
    UpdateAll()
end
ns.Refresh = Refresh

-------------------------------------------------------------------------------
-- Slot mutation
-------------------------------------------------------------------------------
local function SetSlot(code, slot)
    cdb.slots[code] = slot
    local btn = buttons[code]
    if btn then
        if not InCombatLockdown() then ApplyAttributes(btn) else attributesDirty = true end
        UpdateButtonLook(btn)
    end
    ApplyBindings()
end

local function PlaceFromCursor(btn)
    if InCombatLockdown() then Print("Cannot change keys while in combat."); return false end
    local slot, err = SlotFromCursor()
    if not slot then
        if err then Print(err) end
        return false
    end
    local old = cdb.slots[btn.code]
    ClearCursor()
    SetSlot(btn.code, slot)
    if old then PickupSlot(old) end   -- swap: previous content goes to the cursor
    return true
end

local function SetKey(code, key)
    -- key: string in WoW binding syntax, or false for "no key"
    if key then
        for _, other in ipairs(ns.BUTTON_CODES) do
            if other ~= code and GetKey(other) == key then
                db.keys[other] = false
                if buttons[other] then UpdateButtonLook(buttons[other]) end
                Print(("%s was moved from %s to %s."):format(key, ns.NAMES[other] or other, ns.NAMES[code] or code))
            end
        end
    end
    if key == ns.DEFAULT_KEYS[code] then db.keys[code] = nil else db.keys[code] = key end
    if buttons[code] then UpdateButtonLook(buttons[code]) end
    ApplyBindings()
end
ns.SetKey = SetKey

-------------------------------------------------------------------------------
-- Tooltip
-------------------------------------------------------------------------------
local function ShowTooltip(btn)
    local slot = cdb.slots[btn.code]
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    if slot then
        if slot.kind == "spell" then GameTooltip:SetSpellByID(slot.id)
        elseif slot.kind == "item" then GameTooltip:SetItemByID(slot.id)
        else GameTooltip:SetText(slot.name, 1, 1, 1); GameTooltip:AddLine("Macro", 0.7, 0.7, 0.7) end
        GameTooltip:AddLine(" ")
    end
    local key = GetKey(btn.code)
    GameTooltip:AddDoubleLine("Keyzen: " .. (ns.NAMES[btn.code] or btn.code), key or "no key", 0.48, 0.9, 0.88, 1, 0.82, 0)
    if editMode then
        GameTooltip:AddLine("Press a key to change what this Keyzen button sends (ESC = none).", 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- Key capture (Edit Mode: hover a button and press a key)
-------------------------------------------------------------------------------
local IGNORED_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true }

local function OnKeyDown(self, key)
    if not editMode or IGNORED_KEYS[key] then return end
    if key == "ESCAPE" then
        SetKey(self.code, false)
        Print(("%s: key removed."):format(ns.NAMES[self.code] or self.code))
    else
        local mods = ""
        if IsAltKeyDown() then mods = mods .. "ALT-" end
        if IsControlKeyDown() then mods = mods .. "CTRL-" end
        if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
        SetKey(self.code, mods .. key)
        Print(("%s is now bound to %s."):format(ns.NAMES[self.code] or self.code, mods .. key))
    end
    ShowTooltip(self)
end

-------------------------------------------------------------------------------
-- Button creation: same art as Blizzard's ActionButtonTemplate (Dragonflight style)
-------------------------------------------------------------------------------
local ART = {
    normal     = "UI-HUD-ActionBar-IconFrame",
    pushed     = "UI-HUD-ActionBar-IconFrame-Down",
    highlight  = "UI-HUD-ActionBar-IconFrame-Mouseover",
    background = "UI-HUD-ActionBar-IconFrame-Background",
    slot       = "ui-hud-actionbar-iconframe-slot",
    mask       = "UI-HUD-ActionBar-IconFrame-Mask",
}

local function SizeArt(btn, size)
    -- The icon frame atlases are 46x45 for a 45x45 button and hang off the top-left corner.
    local w = size * 46 / 45
    for _, tex in ipairs({ btn:GetNormalTexture(), btn:GetPushedTexture(), btn:GetHighlightTexture() }) do
        if tex then
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT")
            tex:SetSize(w, size)
        end
    end
    if btn.IconMask then btn.IconMask:SetSize(w, size) end
    btn.HotKey:SetSize(size - 8, 10)
end

local function CreateKeyButton(code)
    local btn = CreateFrame("CheckButton", BUTTON_PREFIX .. code, Keyzen, "SecureActionButtonTemplate")
    btn.code = code
    btn:RegisterForDrag("LeftButton")
    -- Mouse clicks act on release, exactly like Blizzard's bars treat a real mouse press. A press
    -- that turns into a drag therefore never casts. Only the secure code can flag a "real" mouse
    -- press, so the addon forces it with the useOnKeyDown attribute instead.
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("useOnKeyDown", false)
    btn:EnableMouse(true)

    -- Hidden proxy for the keybind: follows the "cast on key down" setting like a Blizzard bar
    -- and shows the press on the visible button.
    local proxy = CreateFrame("Button", PROXY_PREFIX .. code, Keyzen, "SecureActionButtonTemplate")
    proxy:RegisterForClicks("AnyDown", "AnyUp")
    proxy:SetSize(1, 1)
    proxy:SetPoint("CENTER", btn, "CENTER")
    proxy:EnableMouse(false)
    proxy:SetScript("PreClick", function(_, _, down) if down then btn:SetButtonState("PUSHED") end end)
    proxy:SetScript("PostClick", function(_, _, down) if not down then btn:SetButtonState("NORMAL") end end)
    btn.proxy = proxy

    -- slot art behind the icon (what you see on an empty button)
    btn.SlotBackground = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    btn.SlotBackground:SetAllPoints()
    local modern = SetAtlasOr(btn.SlotBackground, ART.background, nil)
    btn.SlotArt = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
    btn.SlotArt:SetAllPoints()
    SetAtlasOr(btn.SlotArt, ART.slot, "Interface\\Buttons\\UI-EmptySlot-Disabled")
    if not modern then btn.SlotBackground:SetColorTexture(0, 0, 0, 0.5) end

    btn.icon = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    btn.icon:SetAllPoints()
    if modern and btn.CreateMaskTexture then
        btn.IconMask = btn:CreateMaskTexture()
        btn.IconMask:SetPoint("CENTER", btn.icon, "CENTER")
        if SetAtlasOr(btn.IconMask, ART.mask, nil) then
            btn.icon:AddMaskTexture(btn.IconMask)
        else
            btn.IconMask = nil
        end
    end
    if not modern then btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end

    btn.cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cooldown:SetPoint("TOPLEFT", btn.icon, "TOPLEFT", 3, -3)
    btn.cooldown:SetPoint("BOTTOMRIGHT", btn.icon, "BOTTOMRIGHT", -3, 3)
    btn.cooldown:SetDrawEdge(false)
    btn.cooldown:SetDrawBling(false)
    btn.cooldown:SetSwipeColor(0, 0, 0, 0.64)
    btn.cooldown:SetHideCountdownNumbers(not CVarBool("countdownForCooldowns", true))

    btn.Name = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    btn.Name:SetSize(36, 10)
    btn.Name:SetPoint("BOTTOM", 0, 2)

    -- Blizzard keeps HotKey and Count in a high-level overlay so they draw above the frame art
    local overlay = CreateFrame("Frame", nil, btn)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(btn:GetFrameLevel() + 5)
    btn.HotKey = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    btn.HotKey:SetJustifyH("RIGHT")
    btn.HotKey:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -5)
    btn.Count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.Count:SetJustifyH("RIGHT")
    btn.Count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -5, 5)

    if modern then
        btn:SetNormalAtlas(ART.normal)
        btn:SetPushedAtlas(ART.pushed)
        btn:SetHighlightAtlas(ART.highlight)
        btn:GetNormalTexture():SetDrawLayer("OVERLAY")
        btn:GetPushedTexture():SetDrawLayer("OVERLAY")
    else
        btn:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
        btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    end

    btn:SetScript("PreClick", function(self, button, down)
        if InCombatLockdown() then return end
        if GetCursorInfo() then
            -- Something is on the cursor: this click places it, it must not cast.
            self.placing = true
            self:SetAttribute("type", nil)
        end
    end)
    btn:SetScript("PostClick", function(self, button, down)
        if self.placing then
            self.placing = nil
            if not PlaceFromCursor(self) and not InCombatLockdown() then ApplyAttributesTo(self, cdb.slots[self.code]) end
        end
        self:SetChecked(false)
    end)
    btn:SetScript("OnReceiveDrag", function(self)
        if GetCursorInfo() then PlaceFromCursor(self) end
    end)
    btn:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local slot = cdb.slots[self.code]
        if slot and CanPickUp() then
            PickupSlot(slot)
            SetSlot(self.code, nil)
        elseif editMode and not slot then
            ns.BeginDrag()
            Keyzen.moving = true
        end
    end)
    btn:SetScript("OnDragStop", function(self)
        if Keyzen.moving then Keyzen.moving = nil; ns.FinishDrag() end
    end)
    btn:SetScript("OnEnter", function(self)
        ShowTooltip(self)
        if editMode then self:EnableKeyboard(true) end
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self:EnableKeyboard(false)
    end)
    btn:SetScript("OnKeyDown", OnKeyDown)
    btn:EnableKeyboard(false)

    buttons[code] = btn
    return btn
end

-------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------
local function ParseGrid(rows)
    local cells = {}  -- code -> {col, row, w, h}
    for r, line in ipairs(rows) do
        local c = 0
        for tok in line:gmatch("b(%d+)") do
            local code = tonumber(tok)
            local cell = cells[code]
            if not cell then
                cells[code] = { col = c, row = r - 1, w = 1, h = 1 }
            else
                cell.w = math.max(cell.w, c - cell.col + 1)
                cell.h = math.max(cell.h, r - cell.row)
            end
            c = c + 1
        end
    end
    return cells
end

local PAD = 0   -- no padding: the frame edge is the button edge, like a Blizzard bar

function ns.Layout()
    local size, gap, rowGap = db.cellSize, db.gap, db.rowGap or db.gap
    local cells = ParseGrid(db.lefty and ns.GRID.lefty or ns.GRID.standard)
    local step, stepY = size + gap, size + rowGap

    -- Only the enabled sections are drawn; the frame shrinks to the bounding box of what is
    -- shown, so "finger keys only" is exactly 6 keys wide.
    local minCol, minRow, maxCol, maxRow = math.huge, math.huge, -math.huge, -math.huge
    for _, code in ipairs(ns.BUTTON_CODES) do
        local cell = cells[code]
        if cell and IsCodeShown(code) then
            minCol, maxCol = math.min(minCol, cell.col), math.max(maxCol, cell.col)
            minRow, maxRow = math.min(minRow, cell.row), math.max(maxRow, cell.row)
        end
    end
    if minCol == math.huge then minCol, minRow, maxCol, maxRow = 0, 0, 0, 0 end
    local cols, rows = maxCol - minCol + 1, maxRow - minRow + 1

    Keyzen:SetSize(cols * step - gap + PAD * 2, rows * stepY - rowGap + PAD * 2)
    Keyzen:SetScale(db.scale)
    Keyzen:SetAlpha(db.alpha)

    for _, code in ipairs(ns.BUTTON_CODES) do
        local btn = buttons[code] or CreateKeyButton(code)
        local cell = cells[code]
        btn:ClearAllPoints()
        if cell and IsCodeShown(code) then
            btn:SetSize(size, size)
            SizeArt(btn, size)
            btn:SetPoint("TOPLEFT", Keyzen, "TOPLEFT", PAD + (cell.col - minCol) * step, -(PAD + (cell.row - minRow) * stepY))
            btn:Show()
        else
            btn:Hide()
        end
    end

    if Keyzen.Selection then Keyzen.Selection:SetAllPoints() end
    UpdateAll()
end

function ns.SavePosition()
    local point, rel, relPoint, x, y = Keyzen:GetPoint(1)
    local relName = rel and rel.GetName and rel:GetName()
    if point and (rel == nil or rel == UIParent or relName) then
        -- anchored to UIParent or to a named frame (after snapping to a Blizzard bar)
        db.point = { point, relName or "UIParent", relPoint, x, y }
    else
        -- unnamed relative frame: store the centre in UIParent space instead
        local cx, cy = Keyzen:GetCenter()
        db.point = { "CENTER", "UIParent", "BOTTOMLEFT", cx, cy }
    end
end

function ns.RestorePosition()
    local p = db.point
    local rel = (p[2] and _G[p[2]]) or UIParent
    if type(rel) ~= "table" or not rel.GetObjectType then rel = UIParent end
    Keyzen:ClearAllPoints()
    Keyzen:SetPoint(p[1], rel, p[3], p[4], p[5])
end

function ns.ResetPosition()
    db.point = { unpack(DEFAULTS.point) }
    ns.RestorePosition()
end

-------------------------------------------------------------------------------
-- Edit Mode integration: a Blizzard-style selection overlay while Edit Mode is open
-------------------------------------------------------------------------------
local selection = CreateFrame("Frame", "KeyzenFrameSelection", Keyzen, NineSliceUtil and "NineSliceCodeTemplate" or nil)
Keyzen.Selection = selection
selection:SetAllPoints()
selection:SetFrameStrata("MEDIUM")
selection:SetFrameLevel(1000)
selection:SetToplevel(true)
selection:EnableMouse(true)
selection:RegisterForDrag("LeftButton")
selection:Hide()
selection.isSelected = false

selection.Fill = selection:CreateTexture(nil, "BACKGROUND")
selection.Fill:SetAllPoints()
selection.Fill:SetColorTexture(0.1, 0.6, 1, 0.25)
selection.Label = selection:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
selection.Label:SetAllPoints()
selection.Label:SetText("Keyzen")

local function ApplySelectionKit(kit)
    local ok = false
    if NineSliceUtil and NineSliceUtil.ApplyLayout and EditModeSystemSelectionLayout then
        ok = pcall(NineSliceUtil.ApplyLayout, selection, EditModeSystemSelectionLayout, kit)
    end
    selection.Fill:SetShown(not ok)
end

-- Snapping. Blizzard's EditModeMagnetismManager works on frames that carry the
-- EditModeSystemMixin helpers (selection rect, side checks, snap offsets), so those
-- methods are copied onto the Keyzen frame. Only methods the frame does not already
-- have are added, so no widget API is overridden.
local magnetismReady = false
local function PrepareMagnetism()
    if magnetismReady then return end
    if type(EditModeSystemMixin) ~= "table" or not EditModeMagnetismManager then return end
    for k, v in pairs(EditModeSystemMixin) do
        if type(v) == "function" and Keyzen[k] == nil then Keyzen[k] = v end
    end
    Keyzen.isSelected, Keyzen.isHighlighted, Keyzen.isLocked = false, true, false
    Keyzen.snappedFrames = Keyzen.snappedFrames or {}
    magnetismReady = Keyzen.GetScaledSelectionSides ~= nil and Keyzen.SnapToFrame ~= nil
end

local function RegisterMagnetic(on)
    if not magnetismReady then return end
    if on then pcall(EditModeMagnetismManager.RegisterFrame, EditModeMagnetismManager, Keyzen)
    else pcall(EditModeMagnetismManager.UnregisterFrame, EditModeMagnetismManager, Keyzen) end
end

local function ShowHighlighted()
    selection.isSelected = false
    Keyzen.isSelected = false
    ApplySelectionKit("editmode-actionbar-highlight")
    selection.Label:Show()
    selection:Show()
    RegisterMagnetic(true)   -- other HUD elements can snap to us while we are not selected
    if ns.HideEditDialog then ns.HideEditDialog() end
end

local function ShowSelected()
    selection.isSelected = true
    Keyzen.isSelected = true
    ApplySelectionKit("editmode-actionbar-selected")
    selection.Label:Hide()
    selection:Show()
    RegisterMagnetic(false)  -- never snap to ourselves
    if ns.ShowEditDialog then ns.ShowEditDialog() end
end
ns.DeselectInEditMode = function() if editMode and selection.isSelected then ShowHighlighted() end end

function ns.BeginDrag()
    RegisterMagnetic(false)
    Keyzen:StartMoving()
    if magnetismReady and EditModeManagerFrame and EditModeManagerFrame.SetSnapPreviewFrame then
        pcall(EditModeManagerFrame.SetSnapPreviewFrame, EditModeManagerFrame, Keyzen)
    end
end

function ns.FinishDrag()
    if EditModeManagerFrame and EditModeManagerFrame.ClearSnapPreviewFrame then
        pcall(EditModeManagerFrame.ClearSnapPreviewFrame, EditModeManagerFrame)
    end
    Keyzen:StopMovingOrSizing()
    if magnetismReady and EditModeManagerFrame and EditModeManagerFrame.IsSnapEnabled
        and EditModeManagerFrame:IsSnapEnabled() then
        pcall(EditModeMagnetismManager.ApplyMagnetism, EditModeMagnetismManager, Keyzen)
    end
    ns.SavePosition()
    if not selection.isSelected then RegisterMagnetic(true) end
    if ns.PositionEditDialog then ns.PositionEditDialog() end
end

selection:SetScript("OnMouseDown", function(self)
    if not self.isSelected then
        ShowSelected()
        if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
            pcall(EditModeManagerFrame.ClearSelectedSystem, EditModeManagerFrame)
        end
    end
end)
selection:SetScript("OnDragStart", function() ns.BeginDrag() end)
selection:SetScript("OnDragStop", function() ns.FinishDrag() end)
selection:SetScript("OnEnter", function()
    GameTooltip:SetOwner(selection, "ANCHOR_TOP")
    GameTooltip:SetText("Keyzen", 1, 1, 1)
    GameTooltip:AddLine("Drag to move. Click for size, scale and layout settings.", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Hover a key and press a keyboard key to change what that Keyzen button sends.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)
selection:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function OnEditModeEnter()
    if editMode then return end
    editMode = true
    PrepareMagnetism()
    Keyzen:Show()
    ShowHighlighted()
    UpdateAll()
end

local function OnEditModeExit()
    if not editMode then return end
    editMode = false
    RegisterMagnetic(false)
    selection:Hide()
    selection.isSelected = false
    Keyzen.isSelected = false
    if ns.HideEditDialog then ns.HideEditDialog() end
    for _, btn in pairs(buttons) do btn:EnableKeyboard(false) end
    Keyzen:SetShown(not db.hidden)
    UpdateAll()
end
ns.IsEditMode = function() return editMode end

local function HookEditMode()
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Enter", OnEditModeEnter, Keyzen)
        EventRegistry:RegisterCallback("EditMode.Exit", OnEditModeExit, Keyzen)
    end
    local m = EditModeManagerFrame
    if m then
        -- belt and braces for clients that do not fire the registry events
        m:HookScript("OnShow", function() if m.IsEditModeActive == nil or m:IsEditModeActive() then OnEditModeEnter() end end)
        m:HookScript("OnHide", function() if not (m.IsEditModeActive and m:IsEditModeActive()) then OnEditModeExit() end end)
        if m.SelectSystem then
            hooksecurefunc(m, "SelectSystem", function() ns.DeselectInEditMode() end)
        end
        if m.IsEditModeActive and m:IsEditModeActive() then OnEditModeEnter() end
    end
end

function ns.OpenEditMode()
    if InCombatLockdown() then Print("Edit Mode is not available in combat."); return end
    if EditModeManagerFrame then
        if ShowUIPanel then ShowUIPanel(EditModeManagerFrame) else EditModeManagerFrame:Show() end
    else
        -- very old client without Edit Mode: fall back to a plain unlocked state
        if editMode then OnEditModeExit() else OnEditModeEnter() end
        Print(editMode and "unlocked (no Edit Mode on this client). /keyzen edit again to lock." or "locked.")
    end
end

function ns.SetHidden(hidden)
    db.hidden = hidden and true or false
    Keyzen:SetShown(editMode or not db.hidden)
    ApplyBindings()
end

-------------------------------------------------------------------------------
-- Spell rank upkeep (Classic style ranks: follow the newest rank of a spell by name)
-------------------------------------------------------------------------------
local function RefreshRanks()
    if not db.autoRank then return end
    local changed = false
    for code, slot in pairs(cdb.slots) do
        if slot.kind == "spell" and slot.name then
            local _, _, newID = SpellInfo(slot.name)
            if newID and newID ~= slot.id and IsKnownSpell(newID) then
                slot.id = newID
                changed = true
            end
        end
    end
    if changed then Refresh() end
end

-------------------------------------------------------------------------------
-- Frame setup and events
-------------------------------------------------------------------------------
Keyzen:SetMovable(true)
Keyzen:SetClampedToScreen(true)
Keyzen:SetFrameStrata("MEDIUM")

local throttle = 0
Keyzen:SetScript("OnUpdate", function(self, elapsed)
    throttle = throttle + elapsed
    if throttle < 0.15 then return end
    throttle = 0
    for code in pairs(cdb.slots) do
        local btn = buttons[code]
        if btn and btn:IsShown() then UpdateState(btn) end
    end
end)

local events = {}

function events.ADDON_LOADED(name)
    if name ~= ADDON then return end
    InitDB()
    Keyzen:UnregisterEvent("ADDON_LOADED")
end

function events.PLAYER_LOGIN()
    ns.Layout()
    ns.RestorePosition()
    Keyzen:SetShown(not db.hidden)
    Refresh()
    RefreshRanks()
    HookEditMode()
    if ns.SetupOptions then ns.SetupOptions() end
end

function events.PLAYER_ENTERING_WORLD()
    Refresh()
end

function events.PLAYER_REGEN_ENABLED()
    if attributesDirty then ApplyAttributesAll() end
    if bindingsDirty then ApplyBindings() end
    UpdateAll()
end

local function CooldownEvent() for _, btn in pairs(buttons) do UpdateCooldown(btn) end end
events.SPELL_UPDATE_COOLDOWN = CooldownEvent
events.BAG_UPDATE_COOLDOWN = CooldownEvent
events.ACTIONBAR_UPDATE_COOLDOWN = CooldownEvent

local function StateEvent() for code in pairs(cdb.slots) do if buttons[code] then UpdateState(buttons[code]) end end end
events.SPELL_UPDATE_USABLE = StateEvent
events.PLAYER_TARGET_CHANGED = StateEvent
events.BAG_UPDATE_DELAYED = StateEvent

events.SPELLS_CHANGED = RefreshRanks
events.LEARNED_SPELL_IN_TAB = RefreshRanks
events.UPDATE_MACROS = function() ApplyAttributesAll(); UpdateAll() end
events.CVAR_UPDATE = function(cvar)
    if cvar == "countdownForCooldowns" then
        for _, btn in pairs(buttons) do btn.cooldown:SetHideCountdownNumbers(not CVarBool("countdownForCooldowns", true)) end
    end
end
events.UPDATE_BINDINGS = function() ApplyBindings() end

for ev in pairs(events) do pcall(Keyzen.RegisterEvent, Keyzen, ev) end
Keyzen:SetScript("OnEvent", function(self, event, ...)
    local h = events[event]
    if h then h(...) end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
local function Usage()
    Print("v" .. tostring(VERSION) .. " commands:")
    print("  /keyzen            - open Edit Mode (move the frame, click it for settings)")
    print("  /keyzen config     - open the options panel")
    print("  /keyzen show|hide")
    print("  /keyzen lefty      - toggle the mirrored (right-hand) Keyzen layout")
    print("  /keyzen keys       - list which WoW key each Keyzen button sends")
    print("  /keyzen key <button> <KEY>  - e.g. /keyzen key 18 SPACE   (button numbers: /keyzen keys)")
    print("  /keyzen resetkeys  - restore the default key mapping (matches the shipped Azeron profile)")
    print("  /keyzen reset      - reset position, scale and size")
    print("  /keyzen clear      - remove all spells from the keys (this character)")
end

SLASH_KEYZEN1, SLASH_KEYZEN2 = "/keyzen", "/kz"
SlashCmdList.KEYZEN = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = rest or ""
    if cmd == "" or cmd == "edit" or cmd == "unlock" or cmd == "lock" then ns.OpenEditMode()
    elseif cmd == "config" or cmd == "options" then if ns.OpenOptions then ns.OpenOptions() else Usage() end
    elseif cmd == "show" then ns.SetHidden(false)
    elseif cmd == "hide" then ns.SetHidden(true)
    elseif cmd == "toggle" then ns.SetHidden(not db.hidden)
    elseif cmd == "scale" then
        local v = tonumber(rest); if v then db.scale = math.max(0.5, math.min(2, v)); ns.Layout() else Usage() end
    elseif cmd == "alpha" then
        local v = tonumber(rest); if v then db.alpha = math.max(0.1, math.min(1, v)); ns.Layout() else Usage() end
    elseif cmd == "size" then
        local v = tonumber(rest); if v then db.cellSize = math.max(24, math.min(64, math.floor(v))); ns.Layout() else Usage() end
    elseif cmd == "lefty" then db.lefty = not db.lefty; ns.Layout(); Print(db.lefty and "lefty layout." or "standard layout.")
    elseif cmd == "keys" then
        Print("button -> key  (|cffff8080*|r = changed from default)")
        for _, code in ipairs(ns.BUTTON_CODES) do
            local key = GetKey(code)
            print(("  %2d  %-16s %s%s"):format(code, ns.NAMES[code] or "", key or "-", db.keys[code] ~= nil and " |cffff8080*|r" or ""))
        end
    elseif cmd == "key" then
        local code, key = rest:match("^(%d+)%s+(%S+)$")
        code = tonumber(code)
        if code and buttons[code] and key then
            key = key:upper()
            if key == "NONE" or key == "-" then SetKey(code, false) else SetKey(code, key) end
            Print(("%s -> %s"):format(ns.NAMES[code] or code, GetKey(code) or "no key"))
        else Usage() end
    elseif cmd == "resetkeys" then wipe(db.keys); Refresh(); Print("default keys restored.")
    elseif cmd == "reset" then
        db.scale, db.alpha, db.cellSize, db.gap, db.rowGap = DEFAULTS.scale, DEFAULTS.alpha, DEFAULTS.cellSize, DEFAULTS.gap, DEFAULTS.rowGap
        ns.Layout(); ns.ResetPosition()
    elseif cmd == "clear" then
        if InCombatLockdown() then Print("not in combat.") return end
        wipe(cdb.slots); Refresh(); Print("all keys cleared.")
    else Usage() end
end
