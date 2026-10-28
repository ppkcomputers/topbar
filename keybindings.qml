import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

ShellRoot {
    ListModel {
        id: bindingModel
    }

    Process {
        id: readBindingsProc
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/hyprland.lua"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || text.trim() === "") {
                    console.log("[ERROR] hyprland.lua returned empty content.");
                    return;
                }

                let lines = text.split("\n");
                let matchCount = 0;

                console.log("\n==============================================");
                console.log("   DEBUG: STARTING DETAILED KEYBINDING DUMP");
                console.log("==============================================");

                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();

                    if (line.startsWith("--") || !line.includes("bind")) continue;

                    let openParen = line.indexOf("(");
                    let closeParen = line.lastIndexOf(")");
                    if (openParen === -1 || closeParen === -1) continue;

                    let argsStr = line.substring(openParen + 1, closeParen).trim();
                    let firstComma = argsStr.indexOf(",");
                    if (firstComma === -1) continue;

                    let rawShortcut = argsStr.substring(0, firstComma).trim();
                    let rawAction = argsStr.substring(firstComma + 1).trim();

                    let cleanShortcut = rawShortcut
                    .replace(/\.\./g, " ")
                    .replace(/["']/g, "")
                    .replace(/\+/g, " ")
                    .replace(/\s+/g, " ")
                    .trim();

                    let parts = cleanShortcut.split(" ");
                    let formattedParts = [];
                    for (let p = 0; p < parts.length; p++) {
                        let part = parts[p].trim();
                        if (!part) continue;

                        if (part.toLowerCase() === "mainmod" || part.toLowerCase() === "super") {
                            formattedParts.push("Super");
                        } else {
                            formattedParts.push(part.toUpperCase());
                        }
                    }
                    let shortcut = formattedParts.join(" + ");

                    let appName = "";
                    let cleanAction = rawAction.replace(/["']/g, "").trim();

                    if (cleanAction.includes(".qml")) {
                        let qmlMatch = cleanAction.match(/\/([A-Za-z0-9_\-]+)\.qml/);
                        if (qmlMatch) {
                            let fileName = qmlMatch[1];
                            appName = fileName.charAt(0).toUpperCase() + fileName.slice(1) + " OSD";
                        } else {
                            appName = "Custom OSD";
                        }
                    }
                    else if (cleanAction.includes("exec_cmd")) {
                        let execInner = "";
                        let execMatch = cleanAction.match(/exec_cmd\s*\(\s*([^)]+)\)/);
                        if (execMatch) {
                            execInner = execMatch[1].trim();
                        }

                        if (execInner === "browser") appName = "Brave Browser";
                        else if (execInner === "terminal") appName = "Terminal";
                        else if (execInner === "filemanager") appName = "Files";
                        else if (execInner.includes("wallpaper") || execInner.includes("wall")) appName = "Wallpaper Select";
                        else if (execInner.includes("volume") || execInner.includes("vol")) appName = "Volume Control";
                        else if (execInner.includes("bright") || execInner.includes("backlight")) appName = "Brightness Control";
                        else {
                            let baseName = execInner.split("/").pop().replace(/\.(sh|py|lua)$/, "");
                            appName = baseName.charAt(0).toUpperCase() + baseName.slice(1);
                        }
                    }
                    else if (cleanAction.includes("scratchpad")) {
                        let scratchMatch = cleanAction.match(/scratchpad\s*\(\s*([A-Za-z0-9_]+)/);
                        let scratchVar = scratchMatch ? scratchMatch[1] : "";
                        appName = scratchVar
                        ? "Toggle " + scratchVar.charAt(0).toUpperCase() + scratchVar.slice(1) + " Scratch"
                        : "Toggle Scratchpad";
                    }
                    else {
                        let cleanFunc = cleanAction.replace(/hl\.(dsp\.)?/, "").replace(/\(.*\)/, "").trim();

                        if (cleanFunc.toLowerCase().includes("volume_up")) appName = "Volume Up";
                        else if (cleanFunc.toLowerCase().includes("volume_down")) appName = "Volume Down";
                        else if (cleanFunc.toLowerCase().includes("volume_mute")) appName = "Mute Audio";
                        else if (cleanFunc.toLowerCase().includes("mic_mute") || cleanFunc.toLowerCase().includes("micmute")) appName = "Mute Mic";
                        else if (cleanFunc.toLowerCase().includes("brightness_up")) appName = "Brightness Up";
                        else if (cleanFunc.toLowerCase().includes("brightness_down")) appName = "Brightness Down";
                        else if (cleanFunc.toLowerCase().includes("kill") || cleanFunc.toLowerCase().includes("close")) appName = "Close Window";
                        else {
                            appName = cleanFunc.replace(/_/g, " ");
                            appName = appName.charAt(0).toUpperCase() + appName.slice(1);
                        }
                    }

                    if (appName === "App" || appName === "") {
                        appName = cleanAction
                        .replace(/hl\.(dsp\.)?/, "")
                        .replace(/[\(\)'"]/g, "")
                        .trim();
                        appName = appName.charAt(0).toUpperCase() + appName.slice(1);
                    }

                    if (shortcut && appName) {
                        matchCount++;
                        console.log(`[OSD DISPLAYING] ${appName.padEnd(25)} = ${shortcut}`);
                        bindingModel.append({ "app": appName, "shortcut": shortcut });
                    }
                }

                console.log("==============================================");
                console.log(`   TOTAL SENT TO OSD: ${matchCount} bindings`);
                console.log("==============================================\n");
            }
        }
    }

    PanelWindow {
        id: window
        anchors.top: true
        anchors.right: true
        exclusiveZone: 0
        implicitHeight: 500
        implicitWidth: 420
        color: "transparent"

        Rectangle {
            id: body
            x: window.implicitWidth
            y: 10
            width: window.implicitWidth - 20
            height: window.implicitHeight - 20
            radius: 10
            color: Qt.rgba(0, 0, 0, 0.9)
            border.width: 2
            border.color: "#535337"

            Behavior on x {
                NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
            }

            // --- HEADER ROW (TITLE & CLOSE BUTTON) ---
            Item {
                id: header
                width: parent.width - 30
                height: 24
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: 15
                anchors.leftMargin: 15

                Text {
                    text: "System Keybindings"
                    color: "#7c7c53"
                    font.pixelSize: 14
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Tactile Close Button
                Button {
                    id: closeButton
                    width: 24
                    height: 24
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    transform: Scale {
                        origin.x: closeButton.width / 2
                        origin.y: closeButton.height / 2
                        xScale: closeButton.pressed ? 0.85 : 1.0
                        yScale: closeButton.pressed ? 0.85 : 1.0

                        Behavior on xScale { NumberAnimation { duration: 60 } }
                        Behavior on yScale { NumberAnimation { duration: 60 } }
                    }

                    background: Rectangle {
                        radius: 4
                        color: closeButton.pressed ? "#2d2d1e" : (closeButton.hovered ? "#1f1f14" : "transparent")
                        border.width: closeButton.hovered ? 1 : 0
                        border.color: "#535337"
                    }

                    contentItem: Text {
                        text: "✕"
                        color: closeButton.pressed || closeButton.hovered ? "#dddddd" : "#7c7c53"
                        font.pixelSize: 12
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        Qt.quit(); // Closes the window cleanly
                    }
                }
            }

            // --- DIVIDER LINE ---
            Rectangle {
                id: divider
                width: parent.width - 30
                height: 1
                color: "#535337"
                opacity: 0.4
                anchors.top: header.bottom
                anchors.left: parent.left
                anchors.topMargin: 10
                anchors.leftMargin: 15
            }

            // --- SCROLLABLE LIST CONTAINER ---
            ListView {
                id: list
                width: parent.width - 30
                anchors.top: divider.bottom
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.topMargin: 12
                anchors.bottomMargin: 15
                anchors.leftMargin: 15
                model: bindingModel
                clip: true
                spacing: 8

                delegate: Row {
                    width: list.width
                    spacing: 8

                    Text {
                        text: model.app + ": "
                        color: "#dddddd"
                        font.pixelSize: 13
                        width: 220
                        elide: Text.ElideRight
                    }

                    Text {
                        text: model.shortcut
                        color: "#7c7c53"
                        font.bold: true
                        font.pixelSize: 13
                    }
                }
            }
        }

        Timer {
            interval: 80
            running: true
            onTriggered: body.x = 10
        }
    }
}
