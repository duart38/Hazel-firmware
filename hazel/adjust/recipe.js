// Adjusting a recipe on the camera: which settings the adjust view offers, how they read from and
// write to recipe text, and how they show. Plain ES5 (the camera's Qt 5.5), no camera objects, so
// the tests run it unchanged in Qt 5.5 itself (camera-lib/test/run-qt55.sh).
// Written by Claude (Claude Code); see notes/17-on-camera-adjust.md.
//
// Recipe text is "key = value" lines and "#" lines, the first "#" line being the recipe's name
// (the same text the app writes and the live-view hook reads). Changing a setting changes only
// its own line, so notes, unknown keys and the order of lines survive an edit.
.pragma library

// Only what live view shows can be adjusted on the camera: sharpness, colour fringing and noise
// reduction are under a pixel at screen size or photos-only, so they stay in the app. So does the
// colour mixer (24 values), which needs the app's colour chips to make sense.
//
// kind: "value" one number on a scale; "tint" a colour-grading line, hue and amount; "filter" a
// black-and-white filter, a choice of six. Values are the engine's own (-1..1 or 0..1); the screen
// shows them on the app's familiar scale of four either way (shown = value * 4).
var SETTINGS = [
    {key: "brightness",       name: "Brightness",      group: "tone",    kind: "value", min: -1, max: 1},
    {key: "contrast",         name: "Contrast",        group: "tone",    kind: "value", min: -1, max: 1},
    {key: "highlights",       name: "Highlights",      group: "tone",    kind: "value", min: -1, max: 1},
    {key: "shadows",          name: "Shadows",         group: "tone",    kind: "value", min: -1, max: 1},
    {key: "dynamic_range",    name: "Dynamic range",   group: "tone",    kind: "value", min: 0,  max: 1},
    {key: "fade",             name: "Fade",            group: "tone",    kind: "value", min: 0,  max: 1},

    {key: "saturation",       name: "Colour",          group: "colour",  kind: "value", min: -1, max: 1},
    {key: "vibrance",         name: "Vibrance",        group: "colour",  kind: "value", min: -1, max: 1},
    // named in the order the scale runs, left (-) to right (+)
    {key: "shift_red",        name: "Cyan – Red",       group: "colour", kind: "value", min: -1, max: 1, ends: ["#19c3d2", "#e0402a"]},
    {key: "shift_blue",       name: "Yellow – Blue",    group: "colour", kind: "value", min: -1, max: 1, ends: ["#e8c21a", "#2f6fe0"]},
    {key: "colour_depth",     name: "Colour depth",    group: "colour",  kind: "value", min: 0,  max: 1},
    {key: "grade_shadows",    name: "Shadow tint",     group: "colour",  kind: "tint"},
    {key: "grade_highlights", name: "Highlight tint",  group: "colour",  kind: "tint"},

    {key: "mono_mix",         name: "Filter",          group: "mono",    kind: "filter"},
    {key: "tone_warm",        name: "Cool – Warm",      group: "mono",   kind: "value", min: -1, max: 1, ends: ["#6f9be0", "#e0a35a"]},
    {key: "tone_magenta",     name: "Green – Magenta",  group: "mono",   kind: "value", min: -1, max: 1, ends: ["#5fbf6a", "#d65fb8"]},
    {key: "grade_shadows",    name: "Shadow tint",     group: "mono",    kind: "tint"},
    {key: "grade_highlights", name: "Highlight tint",  group: "mono",    kind: "tint"},

    {key: "clarity",          name: "Clarity",         group: "texture", kind: "value", min: 0,  max: 1},
    {key: "grain",            name: "Grain",           group: "texture", kind: "value", min: 0,  max: 1},
    {key: "grain_size",       name: "Grain size",      group: "texture", kind: "value", min: 0,  max: 1},
    {key: "vignette",         name: "Vignette",        group: "texture", kind: "value", min: -1, max: 1},
    {key: "halation",         name: "Halation",        group: "texture", kind: "value", min: 0,  max: 1}
];

var GROUP_NAMES = {tone: "Tone", colour: "Colour", mono: "B&W", texture: "Texture"};

// The black-and-white filters, as the app has them: how much red, green and blue light count.
var FILTERS = [
    {name: "Neutral", mix: [0.35, 0.55, 0.10], colour: "#bdbdbd"},
    {name: "Yellow",  mix: [0.45, 0.50, 0.05], colour: "#e8c21a"},
    {name: "Orange",  mix: [0.58, 0.39, 0.03], colour: "#ec7a1c"},
    {name: "Red",     mix: [0.70, 0.28, 0.02], colour: "#d83a2a"},
    {name: "Green",   mix: [0.20, 0.75, 0.05], colour: "#4fae54"},
    {name: "Blue",    mix: [0.15, 0.35, 0.50], colour: "#3d74d8"}
];

// One dial click: half a step on the shown scale of four; a tint's hue turns 10 degrees.
var STEP = 0.125;
var HUE_STEP = 10;

function lines(text) {
    return String(text || "").replace(/\r/g, "").split("\n");
}

function keyOf(line) {
    var t = line.replace(/^\s+/, "");
    if (t.charAt(0) === "#") return "";
    var eq = t.indexOf("=");
    return eq > 0 ? t.substring(0, eq).replace(/\s+$/, "") : "";
}

// The value text of the last line with this key (the engine's reader lets a later line win), or null.
function rawValue(text, key) {
    var found = null;
    lines(text).forEach(function (line) {
        if (keyOf(line) === key) found = line.substring(line.indexOf("=") + 1).replace(/^\s+|\s+$/g, "");
    });
    return found;
}

function numbers(raw) {
    if (raw === null) return [];
    return raw.split(",").map(function (part) { return parseFloat(part); });
}

function clamp(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; }

// The recipe's name: its first "#" line, as the app and slots.sh read it.
function nameOf(text) {
    var all = lines(text);
    for (var i = 0; i < all.length; i++) {
        var t = all[i].replace(/^\s+/, "");
        if (t.charAt(0) === "#") return t.replace(/^#+\s*/, "").replace(/\s+$/, "");
    }
    return "";
}

function isMono(text) {
    var mono = rawValue(text, "mono"), film = rawValue(text, "film");
    return (mono !== null && parseInt(mono, 10) !== 0) || (film !== null && film.split(/\s/)[0] === "silver");
}

// What the adjust view lists for this recipe, in groups: Tone, then Colour or B&W, then Texture.
function groupsFor(text) {
    var mono = isMono(text);
    var order = ["tone", mono ? "mono" : "colour", "texture"];
    return order.map(function (id) {
        return {
            id: id,
            name: GROUP_NAMES[id],
            settings: SETTINGS.filter(function (s) { return s.group === id; })
        };
    });
}

// A setting's value in the recipe: a number for "value", {hue, amount} for "tint", a filter
// index for "filter" (-1 when the recipe's mix is none of the six).
function settingValue(text, setting) {
    var raw = rawValue(text, setting.key);
    if (setting.kind === "tint") {
        var t = numbers(raw);
        if (t.length < 2 || isNaN(t[0]) || isNaN(t[1])) return {hue: 0, amount: 0};
        return {hue: ((t[0] % 360) + 360) % 360, amount: clamp(t[1], 0, 1)};
    }
    if (setting.kind === "filter") {
        var m = numbers(raw);
        if (m.length !== 3) return 0;
        var sum = m[0] + m[1] + m[2];
        if (!(sum > 0)) return 0;
        for (var i = 0; i < FILTERS.length; i++) {
            var f = FILTERS[i].mix, d = 0;
            for (var c = 0; c < 3; c++) d += Math.abs(m[c] / sum - f[c]);
            if (d < 0.02) return i;
        }
        return -1;
    }
    var v = raw === null ? 0 : parseFloat(raw);
    return isNaN(v) ? 0 : clamp(v, setting.min, setting.max);
}

function number(v) {
    var r = Math.round(v * 1000) / 1000;
    return String(r === 0 ? 0 : r);
}

function valueText(setting, value) {
    if (setting.kind === "tint") return number(value.hue) + ", " + number(value.amount);
    if (setting.kind === "filter") return FILTERS[value].mix.map(number).join(", ");
    return number(value);
}

function isDefault(setting, value) {
    if (setting.kind === "tint") return value.amount === 0;
    if (setting.kind === "filter") return value === 0;
    return value === 0;
}

// The text with one setting changed. Its line is rewritten where it is (a second line with the
// same key is dropped); a setting the recipe didn't have is added after the last setting, unless
// it is being set to its default, when the text stays as it was.
function withValue(text, setting, value) {
    var all = lines(text), out = [], done = false, lastSetting = -1;
    var line = setting.key + " = " + valueText(setting, value);
    for (var i = 0; i < all.length; i++) {
        if (keyOf(all[i]) === setting.key) {
            if (!done) out.push(line);
            done = true;
            continue;
        }
        out.push(all[i]);
        if (keyOf(all[i]) !== "") lastSetting = out.length - 1;
    }
    if (!done && !isDefault(setting, value)) out.splice(lastSetting + 1, 0, line);
    var result = out.join("\n");
    return result.charAt(result.length - 1) === "\n" || result === "" ? result : result + "\n";
}

// The text with its name (first "#" line) replaced, or added at the top.
function withName(text, name) {
    var all = lines(text);
    for (var i = 0; i < all.length; i++) {
        if (all[i].replace(/^\s+/, "").charAt(0) === "#") {
            all[i] = "# " + name;
            return all.join("\n");
        }
    }
    return "# " + name + "\n" + String(text || "");
}

// One dial click (+1 or -1) on a value; for a tint, which: "hue" or "amount".
function stepped(setting, value, clicks, which) {
    if (setting.kind === "tint") {
        var t = {hue: value.hue, amount: value.amount};
        if (which === "hue") t.hue = ((Math.round((t.hue + clicks * HUE_STEP) / HUE_STEP) * HUE_STEP) % 360 + 360) % 360;
        else t.amount = clamp(Math.round((t.amount + clicks * STEP) / STEP) * STEP, 0, 1);
        return t;
    }
    if (setting.kind === "filter") {
        var at = value < 0 ? 0 : value + clicks;
        return clamp(at, 0, FILTERS.length - 1);
    }
    // a value off the step grid (set finely in the app) moves to the next grid step first
    var steps = value / STEP, whole = Math.round(steps);
    var next = Math.abs(steps - whole) < 1e-6 ? whole + clicks : clicks > 0 ? Math.ceil(steps) : Math.floor(steps);
    return clamp(next * STEP, setting.min, setting.max);
}

// How the screen shows a value: "+1.5", "-0.5", "0" on the scale of four; "Red" for a filter.
function shown(setting, value) {
    // bindings can ask with the last setting's value for a moment while the setting changes
    if ((setting.kind === "tint") !== (typeof value === "object")) return "";
    if (setting.kind === "filter") return FILTERS[value] ? FILTERS[value].name : "Custom";
    if (setting.kind === "tint") return value.amount === 0 ? "Off" : String(Math.round(value.hue)) + "°  " + shown({kind: "value", min: 0}, value.amount);
    var s = Math.round(value * 4 * 10) / 10;
    if (s === 0) return "0";
    var t = s.toFixed(1);
    return setting.min < 0 && s > 0 ? "+" + t : t;
}

function sameValue(setting, a, b) {
    if (setting.kind === "tint") return (a.amount === 0 && b.amount === 0) || (a.hue === b.hue && a.amount === b.amount);
    return a === b;
}

// Which settings differ between two recipe texts (keys of the settings this recipe lists).
function changed(saved, text) {
    var keys = {};
    groupsFor(text).forEach(function (group) {
        group.settings.forEach(function (s) {
            if (!sameValue(s, settingValue(saved, s), settingValue(text, s))) keys[s.key] = true;
        });
    });
    return keys;
}

function anyChanged(saved, text) {
    return Object.keys(changed(saved, text)).length > 0;
}

// A name for a copy saved to a new slot: "Gold 200 edit", then "Gold 200 edit 2", ...
function copyName(name, taken) {
    var base = (name || "Recipe").replace(/ edit( \d+)?$/, "") + " edit";
    var candidate = base;
    for (var n = 2; taken.indexOf(candidate) >= 0; n++) candidate = base + " " + n;
    return candidate.substring(0, 28);
}

// The slot whose name this is, case aside ("" for none). names: [{slot, name}]
function slotCalled(names, name) {
    var wanted = String(name || "").toLowerCase();
    for (var i = 0; i < names.length; i++) if (names[i].name.toLowerCase() === wanted) return names[i].slot;
    return "";
}

// The hook's adjusting file (filmhook.c, read_adjusting) and adjust.sh's request file both end
// with this line, so a reader can tell a whole file from one still being written.
var END = "# end of recipe\n";

function adjustingFile(text) {
    var t = String(text || "");
    if (t !== "" && t.charAt(t.length - 1) !== "\n") t += "\n";
    return "adjusting\n" + t + END;
}

// action: "use", "discard", or "save C3"
function requestFile(action, text) {
    var t = String(text || "");
    if (t !== "" && t.charAt(t.length - 1) !== "\n") t += "\n";
    return action + "\n" + t + END;
}
