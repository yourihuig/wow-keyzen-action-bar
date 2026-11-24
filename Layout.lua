-- Keyzen layout data.
-- The two grids are the exact "mapper area" grids the Azeron Software (v2.0.3) uses
-- to draw the Keyzen (device type 9). Each token is a button code (b<code>);
-- b24 spans 2x2 cells (the thumbstick), b21 is the profile-switch button.
-- Codes that are not in BUTTON_CODES are empty filler cells in the device shape.

local ADDON, ns = ...

ns.GRID = {
    -- Standard Keyzen: used with the LEFT hand, thumb cluster / stick on the right.
    standard = {
        "b21 b32 b34 b35 b39 b40 b45 b28 b48",
        "b25 b33 b8  b12 b17 b49 b29 b22 b31",
        "b26 b3  b7  b11 b16 b19 b46 b30 b50",
        "b4  b2  b6  b10 b15 b42 b24 b24 b20",
        "b36 b1  b5  b9  b14 b43 b24 b24 b41",
        "b27 b37 b38 b13 b18 b44 b23 b47 b51",
    },
    -- Lefty Keyzen: mirrored, used with the RIGHT hand.
    lefty = {
        "b21 b28 b32 b35 b40 b44 b45 b46 b48",
        "b29 b22 b31 b25 b17 b12 b8  b47 b49",
        "b26 b30 b33 b19 b16 b11 b7  b3  b50",
        "b20 b24 b24 b42 b15 b10 b6  b2  b4",
        "b41 b24 b24 b43 b14 b9  b5  b1  b36",
        "b27 b34 b23 b39 b18 b13 b38 b37 b51",
    },
}

ns.COLS = 9
ns.ROWS = 6

-- The 32 physical keys that can send a keyboard key.
ns.BUTTON_CODES = {
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    22, 23, 28, 29, 30, 31, 36, 37, 38, 41, 42, 43,
}
ns.STICK_CODE  = 24   -- Hall-effect thumbstick (2x2 cells), left alone by the addon (not drawn)
ns.SWITCH_CODE = 21   -- profile switch button, left alone by the addon (not drawn)

-- The keypad in three parts that can be shown independently.
ns.SECTIONS = {
    { key = "fingers", label = "Finger keys",  codes = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 36, 37, 38, 42, 43 } },
    { key = "dpad",    label = "D-pad keys",   codes = { 22, 28, 29, 30, 31 } },
    { key = "side",    label = "Keys by the stick", codes = { 20, 23, 41 } },
}
ns.SECTION_OF = {}
for _, section in ipairs(ns.SECTIONS) do
    for _, code in ipairs(section.codes) do ns.SECTION_OF[code] = section.key end
end

-- Human readable names, used in tooltips while editing.
ns.NAMES = {
    [3]  = "Pinky - top",      [2]  = "Pinky - upper",   [1]  = "Pinky - home",   [37] = "Pinky - bottom",
    [8]  = "Ring - top",       [7]  = "Ring - upper",    [6]  = "Ring - lower",   [5]  = "Ring - home",    [38] = "Ring - bottom",
    [12] = "Middle - top",     [11] = "Middle - upper",  [10] = "Middle - lower", [9]  = "Middle - home",  [13] = "Middle - bottom",
    [17] = "Index - top",      [16] = "Index - upper",   [15] = "Index - lower",  [14] = "Index - home",   [18] = "Index - bottom",
    [4]  = "Outer - upper",    [36] = "Outer - lower",
    [19] = "Thumb - top",      [42] = "Thumb - middle",  [43] = "Thumb - bottom",
    [28] = "D-pad up",         [29] = "D-pad left",      [30] = "D-pad down",     [31] = "D-pad right",    [22] = "D-pad center",
    [20] = "Side - upper",     [41] = "Side - lower",    [23] = "Below stick",
    [21] = "Profile switch",   [24] = "Thumbstick",
}

-- Default WoW key for every Keyzen button. This is the same mapping that ships in
-- AzeronProfile/Keyzen-WoW.json, so out of the box the device and the addon agree.
-- Keys use WoW binding syntax: modifiers in the order ALT-CTRL-SHIFT-, then the key.
-- The player can change any of these in-game (hover a key while unlocked and press a key).
-- Finger keys, row by row as they appear on screen (standard layout, columns left to right:
-- outer, pinky, ring, middle, index, thumb):
--      row 1:            a-1   a-2   a-3
--      row 2:      c-1   c-2   c-3   c-4   c-5
--      row 3: Esc  s-1   s-2   s-3   s-4   s-5
--      row 4: Tab  1     2     3     4     5
--      row 5:      6     7     8     Spc
-- ESCAPE cannot be bound in WoW; that key simply stays Escape (menu / cancel) and is never claimed.
ns.DEFAULT_KEYS = {
    -- row 1 (top)
    [8]  = "ALT-1",   [12] = "ALT-2",   [17] = "ALT-3",
    -- row 2
    [3]  = "CTRL-1",  [7]  = "CTRL-2",  [11] = "CTRL-3",  [16] = "CTRL-4",  [19] = "CTRL-5",
    -- row 3
    [4]  = "ESCAPE",  [2]  = "SHIFT-1", [6]  = "SHIFT-2", [10] = "SHIFT-3", [15] = "SHIFT-4", [42] = "SHIFT-5",
    -- row 4 (home row)
    [36] = "TAB",     [1]  = "1",       [5]  = "2",       [9]  = "3",       [14] = "4",       [43] = "5",
    -- row 5 (bottom)
    [37] = "6",       [38] = "7",       [13] = "8",       [18] = "SPACE",
    -- d-pad
    [28] = "UP",      [29] = "LEFT",    [30] = "DOWN",    [31] = "RIGHT",   [22] = "ALT-4",
    -- keys around the stick
    [20] = "ALT-5",   [41] = "ALT-6",   [23] = "ALT-7",
}
