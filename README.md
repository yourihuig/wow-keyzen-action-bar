# Keyzen – your Azeron Keyzen on screen (WoW Forever)

Keyzen draws the Azeron Keyzen keypad on your screen. Drag spells, items or macros from
your spellbook, bags or macro window onto the keys. From then on, pressing that key on the
Keyzen uses that spell. No action bars, no keybinding menus: the picture of your keypad *is*
your keybinding setup.

* Works on World of Warcraft **Forever** (interface 16001) and the current retail client.
* Standard and Lefty (mirrored) Keyzen layouts, taken 1:1 from the Azeron Software.
* Cooldowns, item counts, range and usability colouring, tooltips.
* Combat safe: secure action buttons and override bindings; changes are queued until combat ends.
* Spell ranks follow automatically when you learn a higher rank.
* Per-character key contents, account-wide layout and key mapping.

## Install

1. Download or clone this repository and put its contents in a folder named **`Keyzen`** at
   `World of Warcraft\_forever_\Interface\AddOns\Keyzen`
   (for retail: `World of Warcraft\_retail_\Interface\AddOns\Keyzen`). The folder name must be
   `Keyzen`, matching `Keyzen.toc`.
2. In the Azeron Software, import `AzeronProfile\Keyzen-WoW.json`
   (Profiles list → list edit mode → *Import profiles* → pick the .json, tick the profile, confirm).
   The file is in the same format the software writes with *Export selected profiles to .json*.
   Activate the **Keyzen WoW Addon** profile. It makes every Keyzen button send exactly
   the key the addon expects. The thumbstick keeps its WASD movement.
3. Log in, type `/keyzen` to unlock, and drop your spells on the keys. `/keyzen lock` when done.

## Using it

It behaves like a Blizzard action bar:

| Action | How |
| --- | --- |
| Put a spell on a key | drag it from the spellbook / bags / macro window and drop it on the key |
| Move a spell | drag it to another key (the keys swap) |
| Remove a spell | drag it off the key (with *Lock Action Bars* on, hold the pickup modifier, Shift by default, just like the Blizzard bars) |
| Move the frame | open Edit Mode (game menu → Edit Mode, or `/keyzen`), drag the Keyzen frame like any other HUD element |
| Scale, key size, gap, opacity, lefty layout | in Edit Mode click the Keyzen frame; a settings dialog opens next to it |
| Show only part of the keypad | same dialog: *Finger keys* (6 columns, the width of 6 action buttons), *D-pad keys*, *Keys by the stick* |
| Snap to the Blizzard bars | drag it in Edit Mode with snapping enabled; it snaps like any HUD element and bars snap to it |
| Change which key a Keyzen button sends | in Edit Mode hover the button and press the key combination (ESC = no key) |
| Options panel | `/keyzen config` or Interface → AddOns → Keyzen |
| List the key mapping | `/keyzen keys` |

Keys with nothing on them fall through to your normal Blizzard bindings, so you can mix the
Keyzen frame with regular action bars (for example 3 bars of 6 buttons on the left and the
Keyzen on the right). Turn on *Claim the keys of empty slots too* in the options if you would
rather have empty keys do nothing.

The buttons use the default action bar art (slot, icon frame, hotkey and count placement,
range and usability colouring), so the frame blends in with the Blizzard bars.

## Default key mapping

As you look at the keypad (left hand on the device, thumb cluster and stick on the right):

```
 outer  pinky    ring     middle   index    thumb    |------ d-pad / side ------|
  .       .        .        .        .        .        .      UP       .
  .       .      ALT-1    ALT-2    ALT-3      .      LEFT   ALT-4    RIGHT
  .     CTRL-1   CTRL-2   CTRL-3   CTRL-4   CTRL-5     .     DOWN      .
 SHIFT-1 SHIFT-2 SHIFT-3  SHIFT-4  SHIFT-5  SHIFT-6  (stick)   .     ALT-5
  1       2        3        4        5        6      (stick)   .     ALT-6
  .       7        8       TAB     SPACE      .      ALT-7     .       .
```

The profile-switch button and the thumbstick (WASD movement) are left alone by the addon and not drawn.

The same table lives in `Layout.lua` (`ns.DEFAULT_KEYS`) and is what
`tools/make-azeron-profile.js` writes into the Azeron profile. If you change a key in-game
the frame simply expects the new key; update your Azeron profile to match.

## For developers

* `Layout.lua` – the two Keyzen grids (from the Azeron Software mapper), button codes, names, default keys.
* `Keyzen.lua` – frame, secure buttons, drag and drop, bindings, events, slash commands.
* `Options.lua` – the settings panel.
* `tools/make-azeron-profile.js <template.json>` – regenerates `AzeronProfile/Keyzen-WoW.json`
  from any existing Keyzen profile file (structure is copied, keys come from `Layout.lua`).

Button codes (Azeron numbering) in the standard grid:

```
 21  .   .   .   .   .   .  28   .
  .  .   8  12  17   .  29  22  31
  .  3   7  11  16  19   .  30   .
  4  2   6  10  15  42  24  24  20
 36  1   5   9  14  43  24  24  41
  .  37 38  13  18   .  23   .   .
```

21 = profile switch, 24 = thumbstick (not used by the addon).
