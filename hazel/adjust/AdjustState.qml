// What the on-camera adjust flow knows and does, shared by its views on the back screen and in
// the viewfinder (AdjustView.qml). No camera objects here: the host (Adjust.qml on the camera, the
// test harness on the Mac) gives it the folder it works in and tells it about the keys.
// Written by Claude (Claude Code); see notes/17-on-camera-adjust.md.
//
// Files, all in `dir` (/tmp/x1d on the camera):
//   reads   look, active, recipe, slots/names, slots/<slot>.txt
//   writes  adjusting       the recipe being adjusted, for the live-view hook (filmhook.c); written
//                           on every change, so the picture follows the dial
//           adjust-request  what to do when leaving: use, save <slot> or discard (adjust.sh does
//                           it: the recipe file, the slot, the card, then "done" into adjusting)
import QtQuick 2.4
import "recipe.js" as Recipe

QtObject {
    id: st

    property string dir: "/tmp/x1d"
    // closed, list (the settings), adjust (one setting over the picture), done (save or not),
    // name (the keyboard, for a recipe saved as new)
    property string mode: "closed"
    property bool ready: false

    property string slot: ""
    property string name: ""
    property string saved: ""
    property string text: ""
    property var names: []
    property var groups: []
    property int group: 0
    property int row: 0
    property int doneRow: 0
    // for a tint: which of its two scales the dial moved last ("hue" or "amount")
    property string axis: "amount"
    property bool comparing: false
    property bool lookOn: false
    // the hook has been told about this session (so leaving must tell it it's over)
    property bool told: false

    // the keyboard: the name typed so far, the next letter capital, the key the dials are on
    property string typed: ""
    property bool shift: false
    property int keyRow: 0
    property int keyCol: 0
    readonly property int nameMax: 28
    // ten columns a row; a key wider than one says how many it spans
    readonly property var keyRows: [
        "1234567890".split("").map(function (c) { return {id: "char", ch: c, span: 1}; }),
        "qwertyuiop".split("").map(function (c) { return {id: "char", ch: c, span: 1}; }),
        "asdfghjkl'".split("").map(function (c) { return {id: "char", ch: c, span: 1}; }),
        [{id: "shift", span: 1}].concat("zxcvbnm-".split("").map(function (c) { return {id: "char", ch: c, span: 1}; }),
                                        [{id: "delete", span: 1}]),
        [{id: "back", span: 2}, {id: "clear", span: 2}, {id: "space", span: 3}, {id: "save", span: 3}]
    ]
    readonly property string typedName: typed.replace(/^\s+|\s+$/g, "").replace(/\s+/g, " ")
    // another slot already called this (saving is still allowed; the hint says so)
    // in recipe.js: written here as a block binding beside freeSlot's, Qt 5.5 handed freeSlot this
    // one's answer ("Save as new · C5")
    readonly property string nameTakenBy: Recipe.slotCalled(names, typedName)

    readonly property var setting: groups.length > 0 && groups[group] ? groups[group].settings[row] : null
    readonly property var value: setting ? Recipe.settingValue(text, setting) : 0
    readonly property var savedValue: setting ? Recipe.settingValue(saved, setting) : 0
    readonly property var changedKeys: saved !== "" ? Recipe.changed(saved, text) : ({})
    readonly property bool edited: Object.keys(changedKeys).length > 0
    readonly property string freeSlot: {
        var taken = names.map(function (n) { return n.slot; });
        for (var i = 1; i <= 7; i++) if (taken.indexOf("C" + i) < 0) return "C" + i;
        return "";
    }
    readonly property var doneChoices: [
        {id: "save", text: slot ? "Save to " + slot + " · " + name : "Save", enabled: slot !== ""},
        {id: "saveNew", text: freeSlot ? "Save as new · " + freeSlot : "Save as new · all slots in use", enabled: freeSlot !== ""},
        {id: "use", text: "Use without saving", enabled: true},
        {id: "discard", text: "Discard changes", enabled: true}
    ]

    signal opened()
    signal closed()

    function path(name) { return "file://" + (name.charAt(0) === "/" ? name : dir + "/" + name); }
    function read(name, apply) {
        var request = new XMLHttpRequest();
        request.onreadystatechange = function () {
            if (request.readyState === XMLHttpRequest.DONE) apply(request.responseText || "");
        };
        request.open("GET", path(name));
        request.send();
    }
    function write(name, body) {
        var request = new XMLHttpRequest();
        request.open("PUT", path(name));
        request.send(body);
    }

    // Is the film look on, and which recipe: for the entry button
    function refresh() {
        read("look", function (look) { lookOn = look.charAt(0) === "f"; });
        // another slot picked since: the edits kept from last time were that slot's, so the mark
        // must not show them as this one's (the next open reads the new slot afresh anyway)
        if (mode !== "closed" || saved === "") return;
        read("active", function (active) {
            var now = /^C[1-7]/.test(active.trim()) ? active.trim().substring(0, 2) : "";
            if (mode === "closed" && now !== slot) { saved = ""; text = ""; }
        });
    }

    function open() {
        if (mode !== "closed") return;
        ready = false;
        read("active", function (active) {
            slot = /^C[1-7]/.test(active.trim()) ? active.trim().substring(0, 2) : "";
            read("slots/names", function (list) {
                var parsed = [];
                list.split("\n").forEach(function (line) {
                    var tab = line.indexOf("\t");
                    var s = tab < 0 ? line : line.substring(0, tab);
                    if (/^C[1-7]$/.test(s)) parsed.push({slot: s, name: tab < 0 ? "" : line.substring(tab + 1).trim()});
                });
                names = parsed;
                read(slot ? "slots/" + slot + ".txt" : "recipe", function (slotText) {
                    read("recipe", function (live) {
                        saved = slotText !== "" ? slotText : live;
                        // what live view shows now, edits kept from last time included
                        text = live !== "" ? live : slotText;
                        name = Recipe.nameOf(saved).replace(/ \(edited\)$/, "") || slot || "Recipe";
                        groups = Recipe.groupsFor(text);
                        if (group >= groups.length) group = 0;
                        if (row >= groups[group].settings.length) row = 0;
                        comparing = false;
                        told = false;
                        ready = true;
                        mode = "list";
                        console.log("adjust: open " + (slot || "-") + " " + name);
                        opened();
                    });
                });
            });
        });
    }

    function tellHook(recipe) {
        write("adjusting", Recipe.adjustingFile(recipe));
        told = true;
    }

    function setValue(v) {
        text = Recipe.withValue(text, setting, v);
        tellHook(text);
    }

    // one dial click; axis "h" (left/right) or "v" (up/down), the two wheels
    function dial(clicks, wheel) {
        if (!ready) return;
        if (mode === "list") {
            var r = row + clicks, g = group;
            while (r >= groups[g].settings.length) {
                if (g === groups.length - 1) { r = groups[g].settings.length - 1; break; }
                r -= groups[g].settings.length;
                g++;
            }
            while (r < 0) {
                if (g === 0) { r = 0; break; }
                g--;
                r += groups[g].settings.length;
            }
            group = g;
            row = r;
        } else if (mode === "adjust") {
            if (setting.kind === "tint") axis = wheel === "h" ? "hue" : "amount";
            var next = Recipe.stepped(setting, value, clicks, axis);
            if (!Recipe.sameValue(setting, next, value) || setting.kind === "tint") setValue(next);
        } else if (mode === "name") {
            if (wheel === "h") stepKey(clicks);
            else moveKeyRow(clicks);
        } else if (mode === "done") {
            var d = doneRow + clicks;
            while (d >= 0 && d < doneChoices.length && !doneChoices[d].enabled) d += clicks > 0 ? 1 : -1;
            if (d >= 0 && d < doneChoices.length) doneRow = d;
        }
    }

    function showGroup(g) {
        if (g < 0 || g >= groups.length) return;
        group = g;
        row = 0;
    }

    function pick(g, r) {
        group = g;
        row = r;
        axis = "amount";
        mode = "adjust";
    }

    // SELECT (the AF-D button, or a tap): into a setting, back out of it, or the choice made
    function select() {
        if (mode === "list") pick(group, row);
        else if (mode === "adjust") mode = "list";
        else if (mode === "done") finish(doneChoices[doneRow].id);
        else if (mode === "name") press(keyRows[keyRow][keyCol]);
    }

    // MENU: one level back; from the list, to the save question (or straight out, nothing changed)
    function back() {
        if (mode === "name") mode = "done";
        else if (mode === "adjust" || mode === "done") mode = "list";
        else if (mode === "list") done();
    }

    function done() {
        if (!edited) { leave(told ? "use" : ""); return; }
        doneRow = 0;
        mode = "done";
    }

    function reset() {
        if (mode !== "adjust" || !setting) return;
        if (setting.kind === "tint") setValue({hue: value.hue, amount: 0});
        else if (setting.kind === "filter") setValue(0);
        else setValue(0);
    }

    function compare(on) {
        if (mode !== "adjust" || comparing === on) return;
        comparing = on;
        tellHook(on ? saved : text);
    }

    function finish(choice) {
        if (choice === "save" && slot) {
            text = Recipe.withName(text, name);
            saved = text;
            leave("save " + slot);
        } else if (choice === "saveNew" && freeSlot) {
            var taken = names.map(function (n) { return n.name; });
            typed = Recipe.copyName(name, taken);
            shift = false;
            // on Save: the suggested name is one press away
            keyRow = keyRows.length - 1;
            keyCol = keyRows[keyRow].length - 1;
            mode = "name";
        } else if (choice === "use") {
            leave("use");
        } else if (choice === "discard") {
            text = saved;
            leave("discard");
        }
    }

    // ---- the keyboard ----
    // the column a key starts at, counting spans
    function keyStart(r, c) {
        var x = 0;
        for (var i = 0; i < c; i++) x += keyRows[r][i].span;
        return x;
    }

    // the front wheel: key by key, on into the next row at the end of one
    function stepKey(clicks) {
        var r = keyRow, c = keyCol + clicks;
        while (c >= keyRows[r].length) {
            if (r === keyRows.length - 1) { c = keyRows[r].length - 1; break; }
            c -= keyRows[r].length;
            r++;
        }
        while (c < 0) {
            if (r === 0) { c = 0; break; }
            r--;
            c += keyRows[r].length;
        }
        keyRow = r;
        keyCol = c;
    }

    // the rear wheel: a row up or down, onto the key under the middle of this one
    function moveKeyRow(clicks) {
        var r = Math.max(0, Math.min(keyRows.length - 1, keyRow + clicks));
        if (r === keyRow) return;
        var middle = keyStart(keyRow, keyCol) + keyRows[keyRow][keyCol].span / 2;
        var c = 0;
        while (c < keyRows[r].length - 1 && keyStart(r, c) + keyRows[r][c].span <= middle) c++;
        keyRow = r;
        keyCol = c;
    }

    function type(ch) {
        if (typed.length >= nameMax) return;
        if (ch === " " && (typed === "" || typed.charAt(typed.length - 1) === " ")) return;
        typed += shift ? ch.toUpperCase() : ch;
        shift = false;
    }

    function press(k) {
        if (!k) return;
        if (k.id === "char") type(k.ch);
        else if (k.id === "space") type(" ");
        else if (k.id === "shift") shift = !shift;
        else if (k.id === "delete") { typed = typed.substring(0, typed.length - 1); shift = typed === ""; }
        else if (k.id === "clear") { typed = ""; shift = true; }
        else if (k.id === "back") back();
        else if (k.id === "save") saveNamed();
    }

    // a tap: the dials' place follows the finger
    function tapKey(r, c) {
        keyRow = r;
        keyCol = c;
        press(keyRows[r][c]);
    }

    function saveNamed() {
        if (typedName === "" || !freeSlot) return;
        text = Recipe.withName(text, typedName);
        leave("save " + freeSlot);
    }

    // Out of the way (a half press, Play, live view ending): whatever is on screen stays on screen
    function hide() {
        if (mode === "closed") return;
        leave(told || edited ? "use" : "");
    }

    function leave(action) {
        if (action !== "") {
            var body = action === "use" && edited ? Recipe.withName(text, name + " (edited)") : text;
            write("adjust-request", Recipe.requestFile(action, body));
            console.log("adjust: " + action);
        }
        comparing = false;
        mode = "closed";
        closed();
    }

    // The keys, by the camera's names for them (its KeyMapsWedge.js). On the camera the host sets
    // keys to {match: <the camera's own Keys.js pressedFn>}; without it, the X1D's keys as listed
    // there, for the harness.
    property var keys: null
    function keyIs(name, k) {
        if (keys && keys.match) return keys.match(name, k);
        var map = {
            LEFT: [Qt.Key_Left], RIGHT: [Qt.Key_Right], UP: [Qt.Key_Up], DOWN: [Qt.Key_Down],
            SELECT: [Qt.Key_Enter, Qt.Key_Return, Qt.Key_F3, Qt.Key_D],
            MENU: [Qt.Key_F1], BROWSE: [Qt.Key_F5], ESCAPE: [Qt.Key_Escape],
            HALFPRESS: [Qt.Key_A]
        };
        return (map[name] || []).indexOf(k) >= 0;
    }

    // The grip's buttons, when its microcontroller reports them (bodysync btnGripMenu,
    // btnGripHalfpress), come out of bodystate-daemon as F10 and F12. The X1D's own map has Menu
    // and the half press on its GPIO buttons (F1, A) and knows neither, so they are matched here
    // by code: whichever path a press takes, it does the same.
    readonly property int gripMenuKey: Qt.Key_F10
    readonly property int gripHalfPressKey: Qt.Key_F12

    // true when the key was ours
    function key(k) {
        if (mode === "closed") return false;
        if (keyIs("HALFPRESS", k) || k === gripHalfPressKey || keyIs("BROWSE", k)) { hide(); return false; }
        if (keyIs("LEFT", k)) dial(-1, "h");
        else if (keyIs("RIGHT", k)) dial(1, "h");
        else if (keyIs("UP", k)) dial(-1, "v");
        else if (keyIs("DOWN", k)) dial(1, "v");
        else if (keyIs("SELECT", k)) select();
        else if (keyIs("MENU", k) || k === gripMenuKey || keyIs("ESCAPE", k)) back();
        return true;
    }
}
