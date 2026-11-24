#!/usr/bin/env node
// Builds AzeronProfile/Keyzen-WoW.json from a template Azeron Keyzen profile and the
// default key mapping in Layout.lua, so the device and the addon always agree.
//
// Usage: node tools/make-azeron-profile.js <template-profile.json> [out.json]
//   template: any Azeron Software Keyzen profile (Storage/DevicesStorage/5098/ProfileStorage/profile_*.json
//             or an exported one). Only its structure, thumbstick and LED settings are kept.

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const root = path.join(__dirname, "..");
const templatePath = process.argv[2];
const outPath = process.argv[3] || path.join(root, "AzeronProfile", "Keyzen-WoW.json");
if (!templatePath) {
  console.error("usage: node tools/make-azeron-profile.js <template-profile.json> [out.json]");
  process.exit(1);
}

// --- read DEFAULT_KEYS out of Layout.lua -------------------------------------------------
const lua = fs.readFileSync(path.join(root, "Layout.lua"), "utf8");
const block = lua.slice(lua.indexOf("ns.DEFAULT_KEYS = {"));
const keys = {};
for (const m of block.matchAll(/\[(\d+)\]\s*=\s*"([^"]+)"/g)) keys[Number(m[1])] = m[2];
if (Object.keys(keys).length !== 32) throw new Error("expected 32 default keys in Layout.lua, got " + Object.keys(keys).length);

// --- WoW binding -> Azeron (DOM code + modifier) -----------------------------------------
const DOM = {
  "0": "Digit0", "1": "Digit1", "2": "Digit2", "3": "Digit3", "4": "Digit4", "5": "Digit5",
  "6": "Digit6", "7": "Digit7", "8": "Digit8", "9": "Digit9",
  SPACE: "Space", TAB: "Tab", ENTER: "Enter", ESCAPE: "Escape", BACKSPACE: "Backspace",
  UP: "ArrowUp", DOWN: "ArrowDown", LEFT: "ArrowLeft", RIGHT: "ArrowRight",
  INSERT: "Insert", DELETE: "Delete", HOME: "Home", END: "End", PAGEUP: "PageUp", PAGEDOWN: "PageDown",
  "-": "Minus", "=": "Equal", "[": "BracketLeft", "]": "BracketRight", "\\": "Backslash",
  ";": "Semicolon", "'": "Quote", ",": "Comma", ".": "Period", "/": "Slash", "`": "Backquote",
};
for (const c of "ABCDEFGHIJKLMNOPQRSTUVWXYZ") DOM[c] = "Key" + c;
for (let i = 1; i <= 24; i++) DOM["F" + i] = "F" + i;
for (let i = 0; i <= 9; i++) DOM["NUMPAD" + i] = "Numpad" + i;
Object.assign(DOM, { NUMPADPLUS: "NumpadAdd", NUMPADMINUS: "NumpadSubtract", NUMPADMULTIPLY: "NumpadMultiply",
  NUMPADDIVIDE: "NumpadDivide", NUMPADDECIMAL: "NumpadDecimal" });
const MODS = { ALT: "AltLeft", CTRL: "ControlLeft", SHIFT: "ShiftLeft" };

function toAzeron(binding) {
  const parts = binding.split("-");
  // a trailing "-" key (e.g. "SHIFT--") splits oddly; rebuild
  let key = parts.pop();
  if (key === "" ) key = "-";
  const mods = parts.filter(Boolean).map((m) => {
    if (!MODS[m]) throw new Error("unknown modifier " + m + " in " + binding);
    return MODS[m];
  });
  if (!DOM[key]) throw new Error("no Azeron code for WoW key '" + key + "' (" + binding + ")");
  return { code: DOM[key], mods };
}

// --- build the profile -------------------------------------------------------------------
// The template may be a raw storage profile (profile_<uuid>.json) or an Azeron export
// ({ version, profiles: [...] }); in the latter case the first profile is used.
let tpl = JSON.parse(fs.readFileSync(templatePath, "utf8"));
if (Array.isArray(tpl.profiles)) tpl = tpl.profiles[0];
if (!tpl || !Array.isArray(tpl.inputs)) throw new Error("template does not look like an Azeron profile");
const profile = JSON.parse(JSON.stringify(tpl)); // deep copy
const now = new Date().toISOString();
const softwareVersion = (tpl.metaData && tpl.metaData.createdBy) || "2.0.3";

// fixed id so re-importing a newer version of the profile can be matched to the old one
profile.id = "5e3d6c8a-7b1f-4c2e-9a4d-a1b2c3d4e5f6";
profile.name = "Keyzen WoW Addon";
profile.isFavorite = false;
profile.isSoftware = true;
profile.profileTags = [];
profile.systemTags = [];
profile.profileIconId = "";            // the Azeron JSON export blanks these too
profile.profileBackgroundImageId = "";
profile.metaData = {
  schemeName: "azeron-profile-v1",
  device: 9, // Keyzen
  createdAt: now,
  createdBy: softwareVersion,
  changedLogs: [{ timestampt: now, softwareVersion, type: "created" }],
};

const KEYBOARD = "1";
const NONE = "11";
let mapped = 0;
for (const input of profile.inputs) {
  const binding = keys[input.id];
  if (binding) {
    const { code, mods } = toAzeron(binding);
    input.types[0] = KEYBOARD;
    input.keyValues = [code, "0", "0", "0"];
    input.metaValues = [mods[0] || "0", mods[1] || "0", mods[2] || "0"];
    mapped++;
  } else if (input.id !== 21 && input.id !== 24 && input.types && input.types[0] === KEYBOARD) {
    // a key the addon does not use: leave it unbound so it cannot collide
    input.types[0] = NONE;
    input.keyValues = ["0", "0", "0", "0"];
    input.metaValues = ["0", "0", "0"];
  }
  // 21 (profile switch) and 24 (thumbstick) are kept exactly as in the template
}

// Azeron Software "Export selected profiles to .json" format: { version, profiles: [...] }
const exportData = { version: softwareVersion, profiles: [profile] };
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(exportData, null, 2) + "\n");
console.log(`wrote ${outPath} (${mapped} keys mapped)`);
for (const id of Object.keys(keys).map(Number).sort((a, b) => a - b)) {
  const { code, mods } = toAzeron(keys[id]);
  console.log(`  b${String(id).padStart(2)}  ${keys[id].padEnd(8)} -> ${mods.concat(code).join(" + ")}`);
}
