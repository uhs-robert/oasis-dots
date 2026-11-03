import QtQuick
import qs.core
import qs.theme

// One label of the window segment (the app or the path) that plays Style.dir_anim when its text changes. The width
// takes the new text at once, so neighbouring islands never slide; only the drawing inside it animates.
Item {
    id: root

    property string text: ""
    property color color: Style.bar_fg
    property string font_family: Style.bar_font_family
    property int font_size: Style.bar_font_size
    property int elide: Text.ElideNone
    property string mode: Style.dir_anim

    // 0 to 1 through the animation; every mode draws from it, and 1 is the plain label.
    property real progress: 1
    property string last_text: ""

    readonly property var durations: ({ fade: 180, slide: 220, stepped: 240, flicker: 260, scramble: 360, wipe: 260 })
    // Long paths type faster, so no change takes more than 400 ms.
    readonly property int duration: root.mode === "type" ? Math.min(400, 25 * root.text.length) : (root.durations[root.mode] || 0)
    readonly property bool animates: PowerSource.on_ac && root.visible && root.duration > 0
    readonly property bool running: root.progress < 1

    implicitWidth: measure.implicitWidth
    implicitHeight: measure.implicitHeight

    onTextChanged: root.play()
    Component.onCompleted: root.last_text = root.text

    function play() {
        // A refresh can hand back the same text; only a change plays.
        if (root.text === root.last_text) return;
        root.last_text = root.text;
        run.stop();
        root.progress = 1;
        if (!root.animates || root.text === "") return;
        root.progress = 0;
        run.start();
    }

    // The scramble's random characters change twelve times through the animation rather than every frame, so each
    // tick reads as a step. Separators stay real so the path's shape shows from the first frame.
    function scrambled(t) {
        const step = Math.floor(t * 12) / 12;
        const settled = Math.floor(step * root.text.length);
        const pool = "#%&*+=<>?0123456789ABCDEF";
        let out = root.text.substring(0, settled);
        for (let i = settled; i < root.text.length; i++) {
            const c = root.text[i];
            out += "/~ .-_".indexOf(c) >= 0 ? c : pool[Math.floor(Math.random() * pool.length)];
        }
        return out;
    }

    readonly property string drawn_text: {
        if (!root.running) return root.text;
        if (root.mode === "type") return root.text.substring(0, Math.ceil(root.progress * root.text.length));
        if (root.mode === "scramble") return root.scrambled(root.progress);
        return root.text;
    }

    readonly property real drawn_opacity: {
        if (!root.running) return 1;
        if (root.mode === "fade" || root.mode === "slide") return root.progress;
        // Four shades, like a palette fade on a console with no alpha.
        if (root.mode === "stepped") return Math.min(3, Math.floor(root.progress * 4)) / 3;
        if (root.mode === "flicker") return [0.15, 1, 0.3, 1, 0.6, 1][Math.min(5, Math.floor(root.progress * 6))];
        return 1;
    }

    NumberAnimation {
        id: run
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.duration
        easing.type: root.mode === "fade" || root.mode === "slide" ? Easing.OutCubic : root.mode === "wipe" ? Easing.InOutQuad : Easing.Linear
    }

    // On battery, or once the label hides, a running animation jumps to its end.
    onAnimatesChanged: if (!root.animates && run.running) {
        run.stop();
        root.progress = 1;
    }

    Text {
        id: measure
        visible: false
        text: root.text
        font.family: root.font_family
        font.pixelSize: root.font_size
    }

    Item {
        id: clipper
        height: root.height
        width: root.mode === "wipe" && root.running ? root.width * root.progress : root.width
        clip: root.mode === "wipe" && root.running

        Text {
            id: label
            x: root.mode === "slide" && root.running ? -8 * (1 - root.progress) : 0
            width: root.width
            anchors.verticalCenter: parent.verticalCenter
            elide: root.elide
            text: root.drawn_text
            opacity: root.drawn_opacity
            color: root.color
            font.family: root.font_family
            font.pixelSize: root.font_size
        }
    }

    Rectangle {
        visible: root.mode === "type" && root.running
        x: Math.min(root.width, label.contentWidth + 1)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(2, Math.round(root.font_size * 0.5))
        height: root.font_size
        color: root.color
    }

    Rectangle {
        visible: root.mode === "wipe" && root.running
        x: clipper.width
        width: 2
        height: root.height
        color: Style.accent_color
    }
}
