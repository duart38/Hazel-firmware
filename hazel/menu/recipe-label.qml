// The name of the recipe in use, on the live view (back screen and viewfinder) and on the info
// screen, drawn the way the camera draws its own readouts: its font, white with a thin black
// outline, no background. On the camera as /tmp/x1d/menu/recipe-label.qml; filmgui.c creates it
// once at start-up under the interface's main item.
//
// The interface builds its two windows (back screen, viewfinder) in the background after start-up,
// so this waits for each and adds a label to it. It reads the camera's own items to decide when to
// show: the live-view overlay (only while its readouts are showing, so the info button hides ours
// too) and the info screen. Nothing of the camera's is changed. The name is the active slot's, from
// /tmp/x1d/slots/names; with the film look off, or "Recipe name" off on the Extras page, there is
// no label.
//
// In playback, a photo shown on its own gets the name of the recipe it was developed with, in a tab
// on the bottom bar; tapping it picks another recipe for that photo. The playback hook
// (playhook.c) lists the names of the photos it reads in /tmp/x1d/play-names, and rewrites the
// photo's sidecar when this asks for the photo again (the photo itself is never changed).
import QtQuick 2.4
import com.hasselblad.video 1.0
import com.hasselblad.bodysync 1.0
import "qrc:///common"
// the popup and its base live across the info screen's folders: import the ones it does
import "qrc:/components/popups"
import "qrc:/components/controls"
import "qrc:/controlscreen"

Item {
    id: hazel
    property string recipeName: ""
    // the recipes on the card, [{slot: "C1", name: "Gritty black and white"}, ...], and the active slot
    property var recipes: []
    property string activeSlot: ""
    // the temperature readout (filmhook.c) sits top centre, where a long name would run into it
    property bool readoutShown: true
    // "Recipe name" on the Extras page, for playback too
    property bool namesShown: true
    // playback: {"/SD1/DCIM/100HASBL/B0000028.look": "Gold 200", ...}, and a recipe just picked for a
    // photo, shown until the hook has the photo's new sidecar
    property var playNames: ({})
    property string pendingPath: ""
    property string pendingName: ""
    property int relooks: 0

    GlobalConstants { id: constants }

    function read(path, apply) {
        var request = new XMLHttpRequest();
        request.onreadystatechange = function () {
            if (request.readyState === XMLHttpRequest.DONE) apply(request.responseText || "");
        };
        request.open("GET", "file://" + path);
        request.send();
    }

    // shown unless switched off on the Extras page ("Recipe name") or the film look is off
    function refresh() {
        read("/tmp/x1d/overlay", function (text) { readoutShown = text.indexOf("off") !== 0 });
        read("/media/data/x1d/recipename", function (shown) {
            namesShown = shown.indexOf("off") !== 0;
            if (!namesShown) { recipeName = ""; return; }
            read("/tmp/x1d/look", function (look) {
                if (look.charAt(0) !== "f") { recipeName = ""; return; }
                read("/tmp/x1d/active", function (active) {
                    var slot = active.trim();
                    read("/tmp/x1d/slots/names", function (names) {
                        var name = "", list = [];
                        names.split("\n").forEach(function (line) {
                            var tab = line.indexOf("\t");
                            if (tab <= 0) return;
                            var entry = {slot: line.substring(0, tab), name: line.substring(tab + 1).trim()};
                            if (!/^C[1-7]$/.test(entry.slot)) return;
                            list.push(entry);
                            if (entry.slot === slot) name = entry.name;
                        });
                        recipes = list;
                        activeSlot = slot;
                        recipeName = name;
                    });
                });
            });
        });
    }

    // the way the Hazel page picks a recipe: slots.sh makes the slot in /tmp/x1d/active the live one
    function pick(slot) {
        var request = new XMLHttpRequest();
        request.open("PUT", "file:///tmp/x1d/active");
        request.send(slot + "\n");
        console.log("recipe-label.qml: picked slot " + slot);
        refresh();
    }

    // Playback: a recipe for one photo. The hook rewrites the photo's sidecar when it is next asked
    // for the photo, so this writes what to put in it, then asks for the photo under a new address
    // ("#hazel<n>": QML keeps pictures by address, and would show the old one again).
    function relook(path, slot, name, photo) {
        pendingPath = path;
        pendingName = name;
        function send(body) {
            var request = new XMLHttpRequest();
            request.onreadystatechange = function () {
                if (request.readyState !== XMLHttpRequest.DONE || !photo) return;
                photo.source = String(photo.source).split("#")[0] + "#hazel" + (++relooks);
            };
            request.open("PUT", "file:///tmp/x1d/relook.txt");
            request.send(path + "\n" + body);
            console.log("recipe-label.qml: " + name + " for " + path);
        }
        if (slot === "") send("look = none\n");
        else read("/tmp/x1d/slots/" + slot + ".txt", send);
    }

    Timer {
        interval: 400; repeat: true; running: true
        onTriggered: {
            if (BodySync.currentState !== BodySync.PLAY) return;
            hazel.read("/tmp/x1d/play-names", function (text) {
                var names = {};
                text.split("\n").forEach(function (line) {
                    var tab = line.indexOf("\t");
                    if (tab > 0) names[line.substring(0, tab)] = line.substring(tab + 1);
                });
                hazel.playNames = names;
                if (hazel.pendingPath && names[hazel.pendingPath] === hazel.pendingName) hazel.pendingPath = "";
            });
        }
    }

    property var attached: ({})
    function attach() {
        for (var i = 0; i < parent.children.length; i++) {
            var loader = parent.children[i];
            var which = loader.objectName === "TouchWindow_loader" ? "screen"
                      : loader.objectName === "EVFWindow_Loader" ? "viewfinder" : "";
            if (!which || attached[which] || !loader.item || !loader.item.contentItem) continue;
            label.createObject(loader.item.contentItem, {hazel: hazel});
            attached[which] = true;
            console.log("recipe-label.qml: added to the " + which);
        }
    }

    Timer {
        interval: 1000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: { hazel.refresh(); hazel.attach(); }
    }

    Component {
        id: label
        Item {
            id: holder
            property Item hazel
            anchors.fill: parent
            z: 1000
            readonly property real sizeFactor: Math.min(width / 1024.0, height / 728.0)

            // the camera's own items in this window, found once they exist
            property Item liveView: null
            property Item infoScreen: null
            property Item browseLoader: null
            function find(item) {
                for (var i = 0; i < item.children.length; i++) {
                    var child = item.children[i];
                    if (child === holder) continue;
                    if (!liveView && typeof child.infoVisible === "boolean" && typeof child.sizeFactor === "number")
                        liveView = child;
                    if (!infoScreen && child.objectName === "ControlScreen_root")
                        infoScreen = child;
                    if (!browseLoader && child.objectName === "media_browse_loader")
                        browseLoader = child;
                    find(child);
                }
            }
            // the viewfinder window has no info screen: stop looking for one after a minute. A live
            // view overlay that gets rebuilt reads as null again, and the search restarts.
            property int searches: 0
            Timer {
                interval: 1000; repeat: true; triggeredOnStart: true
                running: !holder.liveView || ((!holder.infoScreen || !holder.browseLoader) && holder.searches < 60)
                onTriggered: { holder.searches++; holder.find(holder.parent); }
            }

            // Polled rather than bound: the interface's state objects don't all announce changes,
            // so a binding on them never updated (the label stayed hidden on the info screen).
            property bool showOnLiveView: false
            property bool showOnInfoScreen: false
            // the live-view views the info button cycles through, in the camera's order
            // (configstore.LiveViewOverlayIndex; the overlay's own list, Histogram left out there too)
            readonly property var views: ["Natural", "Info", "Grid", "SpiritLevel", "HTS"]
            property string view: ""
            // views that draw in the top left corner, or the temperature readout at the top: the label
            // goes under the ISO readout instead
            readonly property var topLeftTaken: ["SpiritLevel"]
            readonly property bool underIso: topLeftTaken.indexOf(view) >= 0 || (hazel !== null && hazel.readoutShown)

            // A name wider than its space loses whole words from the end, then gets "..."; a single
            // word that is still too wide is cut inside. Measured, so each place shows what fits.
            function fit(name, metrics, maxWidth) {
                metrics.text = name;
                if (metrics.width <= maxWidth) return name;
                var words = name.split(" ");
                while (words.length > 1) {
                    words.pop();
                    var shorter = words.join(" ").replace(/[\s,;:-]+$/, "") + "...";
                    metrics.text = shorter;
                    if (metrics.width <= maxWidth) return shorter;
                }
                for (var n = name.length - 1; n > 0; n--) {
                    metrics.text = name.substring(0, n) + "...";
                    if (metrics.width <= maxWidth) return metrics.text;
                }
                return "";
            }
            // Live view: up to the temperature readout (top centre) or, without it, to the ISO
            // readout; under ISO, half the width. Info screen: the empty strip above EV, to about
            // the middle (it is 640 wide and laid out in fixed pixels).
            readonly property real liveViewSpace: underIso ? width * 0.5
                                                : width * 0.68 - liveViewText.margin
            readonly property real infoScreenSpace: 318
            readonly property real playbackSpace: 320
            property string liveViewName: ""
            property string infoScreenName: ""
            property string playbackName: ""
            TextMetrics { id: liveViewMetrics; font: liveViewText.font }
            TextMetrics { id: infoScreenMetrics; font: infoScreenText.font }
            TextMetrics { id: playbackMetrics; font: playbackText.font }
            function refit() {
                var name = hazel ? hazel.recipeName : "";
                liveViewName = fit(name, liveViewMetrics, liveViewSpace);
                infoScreenName = fit(name, infoScreenMetrics, infoScreenSpace);
                playbackName = fit(photoRecipe, playbackMetrics, playbackSpace);
            }

            // Playback, one photo at a time: the photo on screen (the camera's Photo item, with its
            // address in the imagestore), its sidecar's path, the recipe it has, and the bottom bar
            // of the camera's overlay, which the tab sits on and hides with
            property bool atPlayback: false
            property Item photo: null
            property Item bottomBar: null
            property string photoPath: ""
            readonly property string photoRecipe: !hazel || !hazel.namesShown || photoPath === "" ? ""
                : hazel.pendingPath === photoPath ? hazel.pendingName : (hazel.playNames[photoPath] || "")
            property point barAt: Qt.point(0, 0)
            property bool showOnPlayback: false
            function search(item, test, depth) {
                if (!item || depth < 0) return null;
                if (test(item)) return item;
                for (var i = 0; i < item.children.length; i++) {
                    var found = search(item.children[i], test, depth - 1);
                    if (found) return found;
                }
                return null;
            }
            function findPlayback() {
                var view = browseLoader ? browseLoader.item : null;
                // the camera's popup puts the body in its menu state while open
                atPlayback = (BodySync.currentState === BodySync.PLAY || playbackPicker !== null)
                          && view !== null && view.visible && view.state === "list";
                var list = null, current = null, overlay = null;
                if (atPlayback)
                    for (var i = 0; i < view.children.length && !list; i++)
                        // the one-photo list, not the grid of nine (which has a current item too)
                        if (view.children[i].visible && view.children[i].orientation === ListView.Horizontal) list = view.children[i];
                current = list ? list.currentItem : null;
                photo = search(current, function (item) {
                    return String(item.source || "").indexOf("image://imagestore/preview/") === 0 }, 5);
                overlay = search(current, function (item) { return String(item).indexOf("MetaDataOverlay") === 0 }, 4);
                bottomBar = null;
                for (var k = 0; overlay && k < overlay.children.length; k++) {
                    var child = overlay.children[k];
                    if (child.color !== undefined && child.y > overlay.height / 2 && child.height < 80) { bottomBar = child; break; }
                }
                // "image://imagestore/preview/SD1/DCIM/100HASBL/B0000028.3FR#hazel2" -> "/SD1/DCIM/100HASBL/B0000028.look"
                var address = photo ? String(photo.source).split("#")[0].substring("image://imagestore/preview".length) : "";
                photoPath = address.lastIndexOf(".") > 0 ? address.substring(0, address.lastIndexOf(".")) + ".look" : "";
                if (bottomBar) barAt = bottomBar.mapToItem(holder, 0, 0);
                showOnPlayback = photo !== null && bottomBar !== null && overlay.visible && overlay.opacity > 0
                              && bottomBar.visible && bottomBar.opacity > 0;
            }
            Timer {
                interval: 300; repeat: true; running: true
                onTriggered: {
                    var atMain = BodySync.currentState === BodySync.MAIN;
                    holder.showOnLiveView = atMain && holder.liveView !== null && holder.liveView.visible
                                        && holder.liveView.infoVisible && VideoControl.videoMode === VideoControl.View;
                    holder.showOnInfoScreen = atMain && holder.infoScreen !== null && holder.infoScreen.visible
                                          && VideoControl.videoMode === VideoControl.Off;
                    holder.view = holder.views[configstore.LiveViewOverlayIndex] || "";
                    holder.findPlayback();
                    holder.refit();
                    holder.closedPicker();
                }
            }

            // live view: top left, on the line of the ISO readout opposite, with the battery's margin;
            // right-aligned under the ISO readout in views that use the top left corner
            Text {
                id: liveViewText
                visible: holder.showOnLiveView && text !== ""
                readonly property real margin: holder.sizeFactor * constants.liveViewBorderNormalMargin
                readonly property real isoLine: holder.sizeFactor * (constants.liveViewBorderNormalMargin + 25 + 8)
                x: holder.underIso ? holder.width - width - margin : margin
                y: holder.underIso ? isoLine + height * 0.6 : isoLine - height / 2
                text: holder.liveViewName
                font.family: constants.cameraControlTextFontName
                font.pixelSize: constants.evfTextSize * holder.sizeFactor * (holder.underIso ? 0.8 : 1)
                color: constants.cameraViewNormalTextColor
                style: Text.Outline
                styleColor: "black"

                // the name and a margin around it, like the camera's tappable readouts
                MouseArea {
                    enabled: parent.visible
                    anchors.fill: parent
                    anchors.margins: -20 * holder.sizeFactor
                    preventStealing: true
                    onClicked: holder.openPicker(true)
                }
            }

            // Tapping the name opens the camera's own list popup (the one ISO and shutter speed use),
            // so it scrolls with the dial and closes like theirs. On the info screen it goes in the
            // screen's popup slot; the slot is the camera's, so once ours closes it is emptied
            // again, or leaving the next stock popup would restore ours. The X1D's live view has no
            // popup slot (its readouts can't be tapped), so there the popup is made on this
            // label's own layer, which outlives live view, removed once it closes, and closed if
            // live view ends under it.
            function findNamed(item, name) {
                if (!item) return null;
                if (item.objectName === name) return item;
                for (var i = 0; i < item.children.length; i++) {
                    var found = findNamed(item.children[i], name);
                    if (found) return found;
                }
                return null;
            }
            readonly property var pickerNames: hazel ? hazel.recipes.map(function (r) { return r.name || r.slot }) : []
            property Item pickerSlot: null
            property Item livePicker: null
            property Item playbackPicker: null
            property Item focusBefore: null
            function fitPickerText(picker) {
                var list = findNamed(picker, "popup_listSelector");
                if (list) list.itemFontSizeBase = 20;
            }
            function openPicker(onLiveView) {
                if (pickerNames.length === 0 || pickerSlot || livePicker) return;
                if (onLiveView) {
                    livePicker = recipePicker.createObject(holder, {width: holder.width, height: holder.height});
                    if (!livePicker) return;
                    fitPickerText(livePicker);
                    livePicker.forceActiveFocus();
                    return;
                }
                var slot = findNamed(infoScreen, "ControlScreen_popupLoader");
                var screenStates = findNamed(infoScreen, "ControlScreen_states");
                // the camera leaves this slot active while empty: busy means something is loaded
                if (!slot || !screenStates || slot.status !== Loader.Null) return;
                pickerSlot = slot;
                slot.sourceComponent = recipePicker;
                slot.active = true;
                screenStates.state = "popup";
                fitPickerText(slot.item);
            }
            // playback: on this label's layer too, with "Film look off" after the slots
            function openPlaybackPicker() {
                if (pickerNames.length === 0 || playbackPicker || livePicker || pickerSlot || !photo) return;
                focusBefore = photo.parent;
                playbackPicker = playbackPickerComponent.createObject(holder, {
                    width: holder.width, height: holder.height, photo: photo, path: photoPath,
                    current: photoRecipe, choices: pickerNames.concat([lookOff])});
                if (!playbackPicker) return;
                fitPickerText(playbackPicker);
                playbackPicker.forceActiveFocus();
            }
            readonly property string lookOff: "Film look off"
            function closedPicker() {
                if (playbackPicker && playbackPicker.visible && !atPlayback) playbackPicker.close();
                if (playbackPicker && !playbackPicker.visible) {
                    // closing, the popup hands the body back to the main screen's state, where the
                    // dial would no longer turn through photos
                    if (atPlayback) BodySync.currentState = BodySync.PLAY;
                    if (focusBefore) focusBefore.forceActiveFocus();
                    focusBefore = null;
                    playbackPicker.destroy();
                    playbackPicker = null;
                }
                if (livePicker && livePicker.visible && VideoControl.videoMode !== VideoControl.View)
                    livePicker.close();
                if (livePicker && !livePicker.visible) {
                    // focus first: removing the item that has it leaves the window with none
                    if (liveView) liveView.forceActiveFocus();
                    livePicker.destroy();
                    livePicker = null;
                }
                if (pickerSlot && !(pickerSlot.item && pickerSlot.item.visible)) {
                    pickerSlot.active = false;
                    pickerSlot.sourceComponent = null;
                    pickerSlot = null;
                }
            }
            Component {
                id: recipePicker
                PopupListSelector {
                    objectName: "hazelRecipePicker"
                    popupAnchor.leftMargin: 40
                    popupAnchor.rightMargin: 40
                    isToLeft: false
                    model: holder.pickerNames
                    currentlySelectedValue: {
                        for (var i = 0; i < holder.hazel.recipes.length; i++)
                            if (holder.hazel.recipes[i].slot === holder.hazel.activeSlot) return holder.pickerNames[i];
                        return "";
                    }
                    onSelectedValueChanged: {
                        var i = holder.pickerNames.indexOf(value);
                        if (i >= 0) holder.hazel.pick(holder.hazel.recipes[i].slot);
                    }
                }
            }

            Component {
                id: playbackPickerComponent
                PopupListSelector {
                    objectName: "hazelPlaybackPicker"
                    property Item photo
                    property string path
                    property string current
                    property var choices: []
                    popupAnchor.leftMargin: 40
                    popupAnchor.rightMargin: 40
                    isToLeft: false
                    model: choices
                    currentlySelectedValue: current
                    onSelectedValueChanged: {
                        if (value === current) return;
                        var i = holder.pickerNames.indexOf(value);
                        holder.hazel.relook(path, i >= 0 ? holder.hazel.recipes[i].slot : "", value, photo);
                    }
                }
            }

            // playback: a tab on the left of the overlay's bottom bar, in the bar's colour, so the
            // two read as one; it shows and hides with the bar
            Item {
                id: playbackTab
                visible: holder.showOnPlayback && playbackText.text !== ""
                x: holder.barAt.x
                y: holder.barAt.y - height
                width: playbackText.width + 28
                height: 40
                // the bar is see-through by its opacity, which would fade the name too
                Rectangle {
                    anchors.fill: parent
                    color: holder.bottomBar ? holder.bottomBar.color : "transparent"
                    opacity: holder.bottomBar ? holder.bottomBar.opacity : 0
                }
                Text {
                    id: playbackText
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: holder.playbackName
                    font.family: constants.cameraControlTextFontName
                    font.pixelSize: 24
                    color: playbackTap.pressed ? constants.highlightItemColor : constants.itemColor
                }
                MouseArea {
                    id: playbackTap
                    enabled: parent.visible
                    anchors.fill: parent
                    anchors.topMargin: -12
                    anchors.rightMargin: -12
                    preventStealing: true
                    onClicked: holder.openPlaybackPicker()
                }
            }

            // info screen: left-aligned with the EV readout, in the empty strip just above it (the
            // screen is 640 x 480 and laid out in fixed pixels, so these are too)
            Text {
                id: infoScreenText
                visible: holder.showOnInfoScreen && text !== ""
                x: 14
                y: 293 - height / 2
                text: holder.infoScreenName
                font.family: constants.cameraControlTextFontName
                font.pixelSize: 24
                color: tap.pressed ? constants.highlightItemColor : constants.itemColor

                // the whole strip above EV, from the screen's edge to just past the name
                MouseArea {
                    id: tap
                    enabled: parent.visible
                    x: -parent.x
                    y: -(parent.y - 272)
                    width: parent.x + parent.width + 20
                    height: 312 - 272
                    onClicked: holder.openPicker(false)
                }
            }
        }
    }
}
