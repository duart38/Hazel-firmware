// The Extras page in the camera's settings menu: our additions (the film look, recipe slots,
// debug logging). On the camera as /tmp/x1d/menu/film-menu.js.
//
// Our copy of MenuItemImporter.js (see filmgui.c) includes this right after the camera's own menu
// file, in the same scope, so it can extend that file's lists. If anything here throws, only this
// include fails and the stock menus still appear.
//
// Each switch writes one of the control files the live-view hook already reads, so it does exactly
// what the matching x.sh command does, and like everything else it's gone after a restart.
// The recipe rows list the slots in /tmp/x1d/slots/names (card/slots.sh fills it from the card);
// picking one writes its name to /tmp/x1d/active, which slots.sh turns into the live recipe.
// Debug logging writes /tmp/x1d/debug, which debug.sh follows. Every choice made here is also
// logged ("film-menu.js: ...") to the interface's journal, which debug logging keeps.

var FILM_DIR = "/tmp/x1d";
// switches that outlast a restart without slots.sh copying them (read by recipe-label.qml)
var FILM_KEEP = "/media/data/x1d";
var FILM_SLOTS = ["C1", "C2", "C3", "C4", "C5", "C6", "C7"];

// The page's values live on one small Qt object: the menu's checkboxes read and write a named
// property on their "proxy" and redraw when it changes. The camera's settings store would keep
// values across restarts, so it's deliberately not used. The object is kept on guiconfig so every
// menu screen shares it; where Qt won't allow that, each screen makes its own and reads the files.
var filmState = (function () {
    try {
        if (guiconfig.filmState) {
            guiconfig.filmState.reload();
            return guiconfig.filmState;
        }
    } catch (e) {}
    var slotProperties = FILM_SLOTS.map(function (slot) {
        return '    property bool slot' + slot + ': false\n' +
               '    onSlot' + slot + 'Changed: pick("' + slot + '", slot' + slot + ')\n';
    }).join('');
    var state = Qt.createQmlObject(
        'import QtQuick 2.0\n' +
        'QtObject {\n' +
        '    id: film\n' +
        '    property string dir\n' +
        '    property string keep\n' +
        '    property bool filmLook: true\n' +
        '    property bool filmTemperatures: true\n' +
        '    property bool filmRecipeName: true\n' +
        '    property bool filmDebug: false\n' +
        '    property string active\n' +
        // "b4239c5, 2026-10-03" from the card setup's VERSION ("Hazel b4239c5 built 2026-10-03")
        '    property string version\n' +
        // [{slot: "C3", name: "Warm print"}, ...], only the slots that have a recipe
        '    property var names: []\n' +
        '    property int loaded: 0\n' +
        '    readonly property int parts: 5\n' +
        slotProperties +
        '    function save(name, text) {\n' +
        '        var request = new XMLHttpRequest()\n' +
        '        request.open("PUT", "file://" + (name.charAt(0) === "/" ? name : dir + "/" + name))\n' +
        '        request.send(text)\n' +
        '    }\n' +
        '    function read(name, apply) {\n' +
        '        var request = new XMLHttpRequest()\n' +
        '        request.onreadystatechange = function () {\n' +
        '            if (request.readyState === XMLHttpRequest.DONE) apply(request.responseText)\n' +
        '        }\n' +
        '        request.open("GET", "file://" + (name.charAt(0) === "/" ? name : dir + "/" + name))\n' +
        '        request.send()\n' +
        '    }\n' +
        '    function load(name, apply) { read(name, function (text) { apply(text); loaded++ }) }\n' +
        '    function readNames() {\n' +
        '        read("slots/names", function (text) {\n' +
        '            var list = []\n' +
        '            text.split("\\n").forEach(function (line) {\n' +
        '                var tab = line.indexOf("\\t")\n' +
        '                var slot = tab < 0 ? line : line.substring(0, tab)\n' +
        '                if (/^C[1-7]$/.test(slot)) list.push({slot: slot, name: tab < 0 ? "" : line.substring(tab + 1)})\n' +
        '            })\n' +
        '            names = list\n' +
        '        })\n' +
        '    }\n' +
        '    function reload() {\n' +
        '        loaded = 0\n' +
        '        load("look", function (text) { filmLook = text.charAt(0) === "f" })\n' +
        '        load("overlay", function (text) { filmTemperatures = text.indexOf("off") !== 0 })\n' +
        '        load("active", function (text) { show(text.trim()) })\n' +
        '        load("debug", function (text) { filmDebug = text.indexOf("on") === 0 })\n' +
        '        load(keep + "/recipename", function (text) { filmRecipeName = text.indexOf("off") !== 0 })\n' +
        '        readNames()\n' +
        '        read("VERSION", function (text) { version = text.trim().replace(/^Hazel\\s+/, "").replace(/\\s+built\\s+/, ", ") })\n' +
        '    }\n' +
        // tick the chosen slot's row and clear the others; while loading, and for every row but
        // the new one, the change handlers write nothing back
        '    function show(slot) {\n' +
        '        active = slot\n' +
        '        for (var i = 1; i <= 7; i++) film["slotC" + i] = ("C" + i) === slot\n' +
        '    }\n' +
        // the rows behave like radio buttons: picking one clears the others and turns the film
        // look on; unticking the chosen one ticks it again
        '    function pick(slot, on) {\n' +
        '        if (loaded < parts) return\n' +
        '        if (on && slot !== active) {\n' +
        '            console.log("film-menu.js: picked slot " + slot)\n' +
        '            show(slot)\n' +
        '            save("active", slot + "\\n")\n' +
        '            filmLook = true\n' +
        '        } else if (!on && slot === active) {\n' +
        '            film["slot" + slot] = true\n' +
        '        }\n' +
        '    }\n' +
        '    function set(name, value) {\n' +
        '        console.log("film-menu.js: " + name + " " + value.trim())\n' +
        '        save(name, value)\n' +
        '    }\n' +
        '    onFilmLookChanged: if (loaded >= parts) set("look", filmLook ? "f\\n" : "n\\n")\n' +
        '    onFilmTemperaturesChanged: if (loaded >= parts) set("overlay", filmTemperatures ? "on\\n" : "off\\n")\n' +
        '    onFilmDebugChanged: if (loaded >= parts) set("debug", filmDebug ? "on\\n" : "off\\n")\n' +
        '    onFilmRecipeNameChanged: if (loaded >= parts) set(keep + "/recipename", filmRecipeName ? "on\\n" : "off\\n")\n' +
        // the menu opening is when slots.sh re-reads the card: pick up new names without a restart
        '    property QtObject poll: Timer { interval: 2000; repeat: true; running: true; onTriggered: readNames() }\n' +
        '}\n', guiconfig, "film-menu");
    state.dir = FILM_DIR;
    state.keep = FILM_KEEP;
    state.reload();
    try {
        guiconfig.filmState = state;
    } catch (e) {}
    return state;
})();

// Built each time the page opens (the camera asks for the list then), so it shows the slots the
// card has now.
function extrasSettings() {
    var list = [
        {editType: SettingType.SUBHEADER, name: "filmLiveView",     text1: "Live view"},
        {editType: SettingType.CHECKBOX,  name: "filmLook",         text1: "Film look",           proxy: filmState},
        {editType: SettingType.CHECKBOX,  name: "filmRecipeName",   text1: "Recipe name",         proxy: filmState},
        {editType: SettingType.CHECKBOX,  name: "filmTemperatures", text1: "Temperature readout", proxy: filmState},
    ];
    if (filmState.names.length > 0)
        list.push({editType: SettingType.SUBHEADER, name: "filmRecipe", text1: "Recipe"});
    filmState.names.forEach(function (entry) {
        list.push({editType: SettingType.CHECKBOX, name: "slot" + entry.slot,
                   text1: entry.name ? entry.slot + " - " + entry.name : entry.slot, proxy: filmState});
    });
    list.push({editType: SettingType.SUBHEADER, name: "extrasDebug", text1: "Debug"});
    list.push({editType: SettingType.CHECKBOX,  name: "filmDebug",   text1: "Debug logging", proxy: filmState});
    list.push({editType: SettingType.SUBHEADER, name: "extrasAbout", text1: "About"});
    list.push({editType: SettingType.TEXT,      name: "version",     text1: "Version: ", proxy: filmState});
    return list;
}

// The list name also names the entry's icon: qrc:/icons/extrasSettings.png (filmgui.c adds it). The
// same icon is its tile on the main menu: the camera offers every settings entry under the grid's "+"
// tile and draws a tile as qrc:/icons/<largeIcon>.png. A saved tile outlives a start without Hazel:
// the stock interface skips entries it doesn't know but keeps them in the saved favourites.
(function () {
    var entry = {settingsList: "extrasSettings", itemText: "Hazel", itemFile: "qrc:///settings/SettingsGeneric.qml", largeIcon: "extrasSettings"};
    var at = 0;
    for (var i = 0; i < settingsMenuItems.length; i++)
        if (settingsMenuItems[i].settingsList === "generalSettingsDisplay")
            at = i + 1;
    settingsMenuItems.splice(at, 0, entry);
})();

var stockGetSettingsList = getSettingsList;
getSettingsList = function (settingsName) {
    // the camera's own lists pass straight through
    return settingsName === "extrasSettings" ? extrasSettings() : stockGetSettingsList(settingsName);
};

console.log("film-menu.js: Extras page added");
