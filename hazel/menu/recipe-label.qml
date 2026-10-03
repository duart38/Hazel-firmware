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
import QtQuick 2.0
import com.hasselblad.video 1.0
import com.hasselblad.bodysync 1.0
import "qrc:///common"

Item {
    id: hazel
    readonly property int maxChars: 16
    property string recipeName: ""
    // the temperature readout (filmhook.c) sits top centre, where a long name would run into it
    property bool readoutShown: true

    GlobalConstants { id: constants }

    // longer names keep their first maxChars - 3 characters, then "..."
    function capped(name) {
        if (name.length <= maxChars) return name;
        return name.substring(0, maxChars - 3).replace(/\s+$/, "") + "...";
    }

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
            if (shown.indexOf("off") === 0) { recipeName = ""; return; }
            read("/tmp/x1d/look", function (look) {
                if (look.charAt(0) !== "f") { recipeName = ""; return; }
                read("/tmp/x1d/active", function (active) {
                    var slot = active.trim();
                    read("/tmp/x1d/slots/names", function (names) {
                        var name = "";
                        names.split("\n").forEach(function (line) {
                            var tab = line.indexOf("\t");
                            if (tab > 0 && line.substring(0, tab) === slot) name = line.substring(tab + 1).trim();
                        });
                        recipeName = capped(name);
                    });
                });
            });
        });
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
            function find(item) {
                for (var i = 0; i < item.children.length; i++) {
                    var child = item.children[i];
                    if (child === holder) continue;
                    if (!liveView && typeof child.infoVisible === "boolean" && typeof child.sizeFactor === "number")
                        liveView = child;
                    if (!infoScreen && child.objectName === "ControlScreen_root")
                        infoScreen = child;
                    find(child);
                }
            }
            // the viewfinder window has no info screen: stop looking for one after a minute. A live
            // view overlay that gets rebuilt reads as null again, and the search restarts.
            property int searches: 0
            Timer {
                interval: 1000; repeat: true; triggeredOnStart: true
                running: !holder.liveView || (!holder.infoScreen && holder.searches < 60)
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
            Timer {
                interval: 300; repeat: true; running: true
                onTriggered: {
                    var atMain = BodySync.currentState === BodySync.MAIN;
                    holder.showOnLiveView = atMain && holder.liveView !== null && holder.liveView.visible
                                        && holder.liveView.infoVisible && VideoControl.videoMode === VideoControl.View;
                    holder.showOnInfoScreen = atMain && holder.infoScreen !== null && holder.infoScreen.visible
                                          && VideoControl.videoMode === VideoControl.Off;
                    holder.view = holder.views[configstore.LiveViewOverlayIndex] || "";
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
                text: holder.hazel ? holder.hazel.recipeName : ""
                font.family: constants.cameraControlTextFontName
                font.pixelSize: constants.evfTextSize * holder.sizeFactor * (holder.underIso ? 0.8 : 1)
                color: constants.cameraViewNormalTextColor
                style: Text.Outline
                styleColor: "black"
            }

            // info screen: left-aligned with the EV readout, in the empty strip just above it (the
            // screen is 640 x 480 and laid out in fixed pixels, so these are too)
            Text {
                visible: holder.showOnInfoScreen && text !== ""
                x: 14
                y: 293 - height / 2
                text: holder.hazel ? holder.hazel.recipeName : ""
                font.family: constants.cameraControlTextFontName
                font.pixelSize: 24
                color: constants.itemColor
            }
        }
    }
}
