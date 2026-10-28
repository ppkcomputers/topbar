import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Io

ShellRoot {
    id: root

    property bool barVisible: false
    property bool btConnected: false
    property string btDeviceName: "No Device"
    property string clipboardRawText: ""

    // Phone / OBS / scrcpy state
    property bool phoneConnected: false
    property string phoneName: "No Phone"
    property bool obsRunning: false
    property bool scrcpyRunning: false
    property bool cameraAlreadyOpen: false
    property bool alreadyTriggered: false

    onBarVisibleChanged: {
        console.log("[TOPBAR DEBUG] barVisible changed to:", barVisible)
        if (barVisible) {
            root.alreadyTriggered = false   // allow fresh start every time OSD opens
            btCheckProcess.running = true
            btStatusProcess.running = true
            adbCheckProcess.running = true
            obsCheckProcess.running = true
            scrcpyStatusProcess.running = true
            cameraStatusProcess.running = true
        }
    }

    // --- BLUETOOTH CHECK ---
    Process {
        id: btCheckProcess
        command: [
            "bash",
            "-c",
            "echo '[BT STAGE] 1. Powering on Bluetooth adapter...'; " +
            "bluetoothctl power on; " +
            "echo '[BT STAGE] 2. Activating agent...'; " +
            "bluetoothctl agent on; " +
            "bluetoothctl default-agent; " +
            "echo '[BT STAGE] 3. Starting 3s background scan for new devices...'; " +
            "timeout 3 bluetoothctl scan on > /dev/null 2>&1 & " +
            "sleep 3; " +
            "echo '[BT STAGE] 4. Scanning device list...'; " +
            "for mac in $(bluetoothctl devices | awk '{print $2}'); do " +
            "    echo '[BT STAGE] Found MAC: ' $mac; " +
            "    if ! bluetoothctl info \"$mac\" | grep -q 'Paired: yes'; then " +
            "        echo '[BT STAGE] -> Pairing device: ' $mac; " +
            "        bluetoothctl pair \"$mac\"; " +
            "    else " +
            "        echo '[BT STAGE] -> Already paired: ' $mac; " +
            "    fi; " +
            "    if ! bluetoothctl info \"$mac\" | grep -q 'Trusted: yes'; then " +
            "        echo '[BT STAGE] -> Trusting device: ' $mac; " +
            "        bluetoothctl trust \"$mac\"; " +
            "    else " +
            "        echo '[BT STAGE] -> Already trusted: ' $mac; " +
            "    fi; " +
            "    echo '[BT STAGE] -> Connecting device: ' $mac; " +
            "    bluetoothctl connect \"$mac\"; " +
            "done; " +
            "echo '[BT STAGE] 5. Bluetooth check sequence complete.'"
        ]

        stdout: SplitParser {
            onRead: data => console.log(data.trim())
        }

        stderr: SplitParser {
            onRead: data => console.log("[BT STDERR]:", data.trim())
        }

        onExited: (exitCode, exitStatus) => {
            console.log("[BT STAGE] Process exited with code:", exitCode);
            btStatusProcess.running = true;
        }
    }

    Process {
        id: btStatusProcess
        command: [
            "python3",
            "-c",
            "import subprocess, re;\n" +
            "try:\n" +
            "    res = subprocess.run(['wpctl', 'status'], capture_output=True, text=True, timeout=2)\n" +
            "    for line in res.stdout.splitlines():\n" +
            "        if 'bluez5' in line.lower():\n" +
            "            clean = re.sub(r'\\x1b\\[[0-9;]*m', '', line)\n" +
            "            clean = re.sub(r'^[│├└─\\s0-9\\*\\.]+', '', clean)\n" +
            "            clean = re.sub(r'[bluez5]', '', clean).strip()\n" +
            "            if clean:\n" +
            "                print('CONNECTED:' + clean)\n" +
            "                exit(0)\n" +
            "    print('DISCONNECTED')\n" +
            "except Exception as e:\n" +
            "    print('DISCONNECTED')"
        ]

        stdout: SplitParser {
            onRead: data => {
                let status = data.trim();
                console.log("[TOPBAR DEBUG] btStatusProcess raw stdout:", status);

                if (status.startsWith("CONNECTED:")) {
                    root.btConnected = true;
                    root.btDeviceName = status.replace("CONNECTED:", "").trim();
                } else {
                    root.btConnected = false;
                    root.btDeviceName = "Disconnected";
                }
            }
        }

        stderr: SplitParser {
            onRead: data => console.log("[BT STATUS STDERR]:", data.trim())
        }
    }

    // --- ADB PHONE CHECK ---
    Process {
        id: adbCheckProcess
        command: [
            "bash",
            "-c",
            "devices=$(adb devices | grep -w 'device$' | awk '{print $1}'); " +
            "if [ -n \"$devices\" ]; then " +
            "  first=$(echo \"$devices\" | head -n1); " +
            "  name=$(adb -s \"$first\" shell getprop ro.product.model 2>/dev/null | tr -d '\\r'); " +
            "  if [ -z \"$name\" ]; then name=\"Android\"; fi; " +
            "  echo \"CONNECTED:$name\"; " +
            "else " +
            "  echo \"DISCONNECTED\"; " +
            "fi"
        ]

        stdout: SplitParser {
            onRead: data => {
                let status = data.trim();
                if (status.startsWith("CONNECTED:")) {
                    root.phoneConnected = true;
                    root.phoneName = status.replace("CONNECTED:", "").trim();
                } else {
                    root.phoneConnected = false;
                    root.phoneName = "No Phone";
                    root.alreadyTriggered = false;
                }
                tryTriggerScrcpy();
            }
        }

        stderr: SplitParser {
            onRead: data => console.log("[ADB STDERR]:", data.trim())
        }
    }

    // --- OBS CHECK ---
    Process {
        id: obsCheckProcess
        command: [
            "bash",
            "-c",
            "if pgrep -x obs >/dev/null || pgrep -x obs-studio >/dev/null; then echo RUNNING; else echo STOPPED; fi"
        ]

        stdout: SplitParser {
            onRead: data => {
                let running = (data.trim() === "RUNNING");
                if (root.obsRunning && !running) {
                    root.alreadyTriggered = false;
                }
                root.obsRunning = running;
                tryTriggerScrcpy();
            }
        }

        stderr: SplitParser {
            onRead: data => console.log("[OBS STDERR]:", data.trim())
        }
    }

    // --- SCRCPY ALREADY RUNNING? ---
    Process {
        id: scrcpyStatusProcess
        command: [
            "bash",
            "-c",
            "if pgrep -x scrcpy >/dev/null; then echo RUNNING; else echo STOPPED; fi"
        ]

        stdout: SplitParser {
            onRead: data => {
                let running = (data.trim() === "RUNNING");
                if (root.scrcpyRunning && !running) {
                    root.alreadyTriggered = false;
                }
                root.scrcpyRunning = running;
                tryTriggerScrcpy();
            }
        }
    }

    // --- CAMERA ALREADY OPEN? (Open Camera) ---
    Process {
        id: cameraStatusProcess
        command: [
            "bash",
            "-c",
            "act=$(adb shell dumpsys activity activities 2>/dev/null | grep -o 'mResumedActivity:.*' | head -n1); " +
            "if echo \"$act\" | grep -qiE 'opencamera|net.sourceforge.opencamera'; then " +
            "  echo OPEN; " +
            "else " +
            "  echo CLOSED; " +
            "fi"
        ]

        stdout: SplitParser {
            onRead: data => {
                root.cameraAlreadyOpen = (data.trim() === "OPEN");
                tryTriggerScrcpy();
            }
        }

        stderr: SplitParser {
            onRead: data => console.log("[CAMERA STATUS ERR]:", data.trim())
        }
    }

    function tryTriggerScrcpy() {
        if (!root.barVisible || !root.phoneConnected || !root.obsRunning)
            return;

        if (root.alreadyTriggered) {
            return;
        }

        // Always do a clean start when OSD is opened
        console.log("[SCRCPY] Starting clean Open Camera + scrcpy sequence");
        root.alreadyTriggered = true;   // prevent re-entry
        killScrcpyProcess.running = true;
    }

    // --- KILL STALE SCRCPY & LAUNCH CLEAN ---
    Process {
        id: killScrcpyProcess
        command: ["killall", "scrcpy"]
        onExited: {
            cameraOpenProcess.running = true;
        }
    }

    // --- OPEN OPEN CAMERA + SWITCH TO FRONT ---
    Process {
        id: cameraOpenProcess
        command: [
            "bash",
            "-c",
            "adb shell am start -n net.sourceforge.opencamera/.MainActivity && " +
            "sleep 2.0 && " +
            "adb shell input tap 500 1337"
        ]

        stdout: SplitParser { onRead: data => console.log("[CAMERA]", data.trim()) }
        stderr: SplitParser { onRead: data => console.log("[CAMERA ERR]", data.trim()) }

        onExited: {
            if (!root.scrcpyRunning) {
                console.log("[CAMERA] finished, launching headless scrcpy sink");
                scrcpyProcess.running = true;
            }
            cameraStatusProcess.running = true;
            scrcpyStatusProcess.running = true;
        }
    }

    // --- SCRCPY (headless sink) ---
    Process {
        id: scrcpyProcess
        command: [
            "scrcpy",
            "--v4l2-sink=/dev/video0",
            "--no-audio",
            "--no-control",
            "--no-window"
        ]

        stdout: SplitParser { onRead: data => console.log("[SCRCPY OUT]", data.trim()) }
        stderr: SplitParser { onRead: data => console.log("[SCRCPY ERR]", data.trim()) }

        onStarted: {
            console.log("[SCRCPY] started silently");
            root.scrcpyRunning = true;
            root.alreadyTriggered = true;
        }
        onExited: {
            console.log("[SCRCPY] exited");
            root.scrcpyRunning = false;
            root.alreadyTriggered = false;
        }
    }

    // --- CLIPBOARD ---
    Process {
        id: fetchClipboardProcess
        command: ["wl-paste", "--no-newline"]

        stdout: SplitParser {
            splitMarker: "\0"
            onRead: data => {
                let cleanData = data.trim();
                if (cleanData !== "" && cleanData !== root.clipboardRawText) {
                    root.clipboardRawText = cleanData;
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: fetchClipboardProcess.running = true
    }

    Process {
        id: openClipboardProcess
        property string rawClipboardData: ""

        command: [
            "bash",
            "-c",
            "ITEM=\"$1\"; " +
            "CLEAN=$(echo \"$ITEM\" | head -n 1 | sed -E 's|^file://||'); " +
            "CLEAN=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' \"$CLEAN\" 2>/dev/null || echo \"$CLEAN\"); " +
            "if [ -e \"$CLEAN\" ]; then " +
            "    xdg-open \"$CLEAN\"; " +
            "else " +
            "    TMPFILE=\"/tmp/quickshell_clipboard.txt\"; " +
            "    echo \"$ITEM\" > \"$TMPFILE\"; " +
            "    xdg-open \"$TMPFILE\"; " +
            "fi",
            "_",
            rawClipboardData
        ]

        stdout: SplitParser { onRead: data => {} }
        stderr: SplitParser { onRead: data => {} }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            btStatusProcess.running = true
            if (root.barVisible) {
                adbCheckProcess.running = true
                obsCheckProcess.running = true
                scrcpyStatusProcess.running = true
                cameraStatusProcess.running = true
            }
        }
    }

    PwObjectTracker {
        id: pwTracker
        objects: {
            let list = [];
            if (Pipewire.defaultAudioSink) list.push(Pipewire.defaultAudioSink);
            if (Pipewire.defaultAudioSource) list.push(Pipewire.defaultAudioSource);
            return list;
        }
    }

    Process {
        id: openKeybindings
        command: ["quickshell", "-p", Quickshell.env("HOME") + "/.config/Quickshell/Keybindings/keybindings.qml"]
    }

    Process {
        id: killKeybindings
        command: ["pkill", "-f", "keybindings.qml"]
    }

    FileView {
        id: toggleFile
        path: "/tmp/topbar_visible_" + Quickshell.env("USER")
        watchChanges: true
        printErrors: false

        onLoaded: {
            let content = text().trim();
            root.barVisible = (content === "1");
        }

        onLoadFailed: {
            root.barVisible = true;
        }

        onFileChanged: {
            reload()
        }
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: toggleFile.reload()
    }

    // --- PREVIEW OVERLAY ---
    PanelWindow {
        id: previewOverlay

        anchors {
            top: true
            right: true
        }

        margins.top: 52
        margins.right: 140

        implicitWidth: 300
        implicitHeight: 300
        color: "transparent"
        visible: clipMouse.containsMouse && clipboardContainer.isImage

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.95)
            border.color: "#535337"
            border.width: 1
            radius: 8

            Image {
                anchors.fill: parent
                anchors.margins: 10
                fillMode: Image.PreserveAspectFit
                source: clipboardContainer.isImage ? "file://" + clipboardContainer.rawPath : ""
                asynchronous: true
                smooth: true
                mipmap: true
            }
        }
    }

    PanelWindow {
        id: window

        anchors {
            top: true
            left: true
            right: true
        }

        exclusiveZone: 0
        implicitHeight: root.barVisible ? 48 : 0
        color: "transparent"

        Rectangle {
            id: body
            x: 0
            y: root.barVisible ? 0 : -48
            width: parent.width
            height: 48

            color: Qt.rgba(0, 0, 0, 0.75)
            border.width: 1
            border.color: "#535337"

            Behavior on y {
                NumberAnimation {
                    duration: 350
                    easing.type: Easing.OutCubic
                }
            }

            Item {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20

                // LEFT: DATE / TIME
                Row {
                    id: dateTimeWidget
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    Text {
                        id: clockText
                        color: "#a5a25e"
                        font.pixelSize: 13
                        font.bold: true
                        font.family: "Monospace"
                        anchors.verticalCenter: parent.verticalCenter

                        readonly property var holidays: {
                            "01-01": ["Global Family Day 🌍", "New Year's Day 🇿🇦"],
                            "03-08": ["International Women's Day ♀️"],
                            "03-21": ["Human Rights Day 🇿🇦"],
                            "04-22": ["Earth Day 🌲"],
                            "04-27": ["Freedom Day 🇿🇦"],
                            "05-01": ["Workers' Day 🇿🇦"],
                            "06-05": ["World Environment Day 🍃"],
                            "06-16": ["Youth Day 🇿🇦"],
                            "07-15": ["World Youth Skills Day 🛠"],
                            "07-18": ["Nelson Mandela Day 🇿🇦"],
                            "08-09": ["National Women's Day 🇿🇦"],
                            "09-21": ["International Day of Peace 🕊"],
                            "09-24": ["Heritage Day 🇿🇦"],
                            "10-04": ["World Animal Day 🐾"],
                            "12-10": ["Human Rights Day ⚖️"],
                            "12-16": ["Day of Reconciliation 🇿🇦"],
                            "12-25": ["Christmas Day 🎄", "Christmas Day 🇿🇦"],
                            "12-26": ["Day of Goodwill 🇿🇦"]
                        }

                        function updateTime() {
                            let date = new Date();
                            let timeString = date.toLocaleTimeString(Qt.locale(), "HH:mm:ss");
                            let dateString = date.toLocaleDateString(Qt.locale(), "dd.MM.yyyy");

                            let mm = String(date.getMonth() + 1).padStart(2, '0');
                            let dd = String(date.getDate()).padStart(2, '0');
                            let holidayKey = `${mm}-${dd}`;

                            let holidayText = "";
                            if (holidays[holidayKey]) {
                                holidayText = " - " + holidays[holidayKey].join(", ");
                            }

                            text = `${timeString}  |  ${dateString}${holidayText}`;
                        }

                        Component.onCompleted: updateTime()

                        Timer {
                            interval: 1000
                            running: true
                            repeat: true
                            onTriggered: clockText.updateTime()
                        }
                    }
                }

                // CENTER: VOLUME
                Row {
                    anchors.centerIn: parent
                    spacing: 20

                    Row {
                        spacing: 8
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            text: "SYS"
                            color: "#a5a25e"
                            font.pixelSize: 11
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Slider {
                            id: sysSlider
                            width: 140
                            anchors.verticalCenter: parent.verticalCenter
                            from: 0.0
                            to: 1.0

                            value: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
                            ? Pipewire.defaultAudioSink.audio.volume
                            : 0.5

                            background: Rectangle {
                                x: sysSlider.leftPadding
                                y: sysSlider.topPadding + sysSlider.availableHeight / 2 - height / 2
                                implicitHeight: 4
                                width: sysSlider.availableWidth
                                height: implicitHeight
                                radius: 2
                                color: "#222222"

                                Rectangle {
                                    width: sysSlider.visualPosition * parent.width
                                    height: parent.height
                                    color: "#535337"
                                    radius: 2
                                }
                            }

                            handle: Rectangle {
                                x: sysSlider.leftPadding + sysSlider.visualPosition * (sysSlider.availableWidth - width)
                                y: sysSlider.topPadding + sysSlider.availableHeight / 2 - height / 2
                                implicitWidth: 12
                                implicitHeight: 12
                                radius: 6
                                color: sysSlider.pressed ? "#7c7c53" : "#535337"
                            }

                            onMoved: {
                                if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) {
                                    Pipewire.defaultAudioSink.audio.volume = value;
                                }
                            }
                        }

                        Text {
                            text: Math.round(sysSlider.value * 100) + "%"
                            color: "#a5a25e"
                            font.pixelSize: 13
                            font.bold: true
                            width: 35
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Rectangle { width: 1; height: 20; color: "#333332"; anchors.verticalCenter: parent.verticalCenter }

                    Row {
                        spacing: 8
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            text: "MIC"
                            color: "#a5a25e"
                            font.pixelSize: 11
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Slider {
                            id: micSlider
                            width: 140
                            anchors.verticalCenter: parent.verticalCenter
                            from: 0.0
                            to: 1.0

                            value: (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio)
                            ? Pipewire.defaultAudioSource.audio.volume
                            : 0.5

                            background: Rectangle {
                                x: micSlider.leftPadding
                                y: micSlider.topPadding + micSlider.availableHeight / 2 - height / 2
                                implicitHeight: 4
                                width: micSlider.availableWidth
                                height: implicitHeight
                                radius: 2
                                color: "#222222"

                                Rectangle {
                                    width: micSlider.visualPosition * parent.width
                                    height: parent.height
                                    color: "#7c7c53"
                                    radius: 2
                                }
                            }

                            handle: Rectangle {
                                x: micSlider.leftPadding + micSlider.visualPosition * (micSlider.availableWidth - width)
                                y: micSlider.topPadding + micSlider.availableHeight / 2 - height / 2
                                implicitWidth: 12
                                implicitHeight: 12
                                radius: 6
                                color: micSlider.pressed ? "#9c9c6d" : "#7c7c53"
                            }

                            onMoved: {
                                if (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio) {
                                    Pipewire.defaultAudioSource.audio.volume = value;
                                }
                            }
                        }

                        Text {
                            text: Math.round(micSlider.value * 100) + "%"
                            color: "#a5a25e"
                            font.pixelSize: 13
                            font.bold: true
                            width: 35
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // RIGHT SIDE
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    // Clipboard
                    Item {
                        id: clipboardContainer
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(clipboardText.implicitWidth, 140)
                        height: clipboardText.implicitHeight
                        visible: root.clipboardRawText !== ""

                        property string rawPath: {
                            let text = root.clipboardRawText.split("\n")[0].trim();
                            try { text = decodeURIComponent(text); } catch(e) {}
                            return text.replace(/^file:\/\//, "");
                        }

                        property string displayName: {
                            let parts = rawPath.split("/");
                            return parts[parts.length - 1];
                        }

                        property bool isImage: {
                            let clean = rawPath.toLowerCase();
                            return clean.endsWith(".png") || clean.endsWith(".jpg") ||
                            clean.endsWith(".jpeg") || clean.endsWith(".webp") ||
                            clean.endsWith(".gif") || clean.endsWith(".bmp") ||
                            clean.endsWith(".svg") || clean.endsWith(".ico") ||
                            clean.endsWith(".avif");
                        }

                        Text {
                            id: clipboardText
                            width: parent.width
                            text: (clipboardContainer.isImage ? "🖼️ " : "📋 ") + clipboardContainer.displayName
                            color: clipMouse.containsMouse ? "#ffffff" : "#a5a25e"
                            font.pixelSize: 11
                            font.bold: true
                            font.underline: clipMouse.containsMouse
                            elide: Text.ElideRight
                            maximumLineCount: 1

                            Behavior on color {
                                ColorAnimation { duration: 100 }
                            }
                        }

                        MouseArea {
                            id: clipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.clipboardRawText !== "") {
                                    openClipboardProcess.rawClipboardData = root.clipboardRawText;
                                    openClipboardProcess.running = true;
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: 1
                        height: 20
                        color: "#333332"
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.clipboardRawText !== ""
                    }

                    // Phone status
                    Row {
                        spacing: 6
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: root.phoneConnected ? "#3b82f6" : "#ef4444"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: root.phoneName
                            color: "#a5a25e"
                            font.pixelSize: 11
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Bluetooth status
                    Row {
                        spacing: 6
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: root.btConnected ? "#3b82f6" : "#ef4444"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: root.btDeviceName
                            color: "#a5a25e"
                            font.pixelSize: 11
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // KEYS button
                    Button {
                        id: keysButton
                        anchors.verticalCenter: parent.verticalCenter

                        transform: Scale {
                            id: buttonScale
                            origin.x: keysButton.width / 2
                            origin.y: keysButton.height / 2
                            xScale: keysButton.pressed ? 0.92 : 1.0
                            yScale: keysButton.pressed ? 0.92 : 1.0

                            Behavior on xScale {
                                NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                            }
                            Behavior on yScale {
                                NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                            }
                        }

                        background: Rectangle {
                            implicitWidth: 60
                            implicitHeight: 28
                            radius: 4
                            color: keysButton.pressed || openKeybindings.running ? "#3d3d29" : "#1a1a1a"
                            border.width: 1
                            border.color: keysButton.pressed || openKeybindings.running ? "#9c9c6d" : "#535337"

                            Behavior on color {
                                ColorAnimation { duration: 100 }
                            }
                        }

                        contentItem: Text {
                            text: "⌨ KEYS"
                            color: "#a5a25e"
                            font.pixelSize: 11
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter

                            topPadding: keysButton.pressed ? 1 : 0

                            Behavior on topPadding {
                                NumberAnimation { duration: 50 }
                            }
                        }

                        onClicked: {
                            if (openKeybindings.running) {
                                killKeybindings.running = true;
                            } else {
                                openKeybindings.running = true;
                            }
                        }
                    }
                }
            }
        }
    }
}
