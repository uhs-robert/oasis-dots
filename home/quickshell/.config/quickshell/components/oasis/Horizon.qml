// home/quickshell/.config/quickshell/components/oasis/Horizon.qml
import QtQuick
import QtQuick.Shapes
import "../../theme"
import "../../services"

// The clock island's desert horizon: a palm at the left, the sun by day or the moon by night riding the line.
Item {
    id: root

    readonly property color sand: Theme.theme_secondary
    readonly property int horizon_y: Math.round(root.height * 0.78)
    readonly property real track_left: 34
    readonly property real track_right: Math.max(root.track_left, root.width - 16)

    // The clock this horizon sits behind lends its time.
    property date date: new Date()
    // In the weather location's clock, the base its sunrise and sunset use; ticks once a minute.
    readonly property int minute_of_day: {
        if (!WeatherState.has_data) return root.date.getHours() * 60 + root.date.getMinutes();
        const d = new Date(root.date.getTime() + WeatherState.utc_offset * 1000);
        return d.getUTCHours() * 60 + d.getUTCMinutes();
    }

    function minutes(hhmm, fallback) {
        const m = /^(\d{1,2}):(\d{2})/.exec(hhmm || "");
        return m ? Number(m[1]) * 60 + Number(m[2]) : fallback;
    }

    readonly property var sky: {
        const now = root.minute_of_day;
        const rise = root.minutes(WeatherState.sunrise, 390);
        const set = Math.max(rise + 1, root.minutes(WeatherState.sunset, 1110));
        if (now >= rise && now < set) return { day: true, f: (now - rise) / (set - rise) };
        const since = now >= set ? now - set : now + 1440 - set;
        return { day: false, f: since / Math.max(1, 1440 - (set - rise)) };
    }
    readonly property real body_x: root.track_left + root.sky.f * (root.track_right - root.track_left)

    Rectangle {
        y: root.horizon_y + 1
        width: root.width
        height: Math.max(0, root.height - y)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(root.sand, 0.08) }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    Rectangle {
        x: 8
        y: root.horizon_y
        width: Math.max(0, root.width - 16)
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.25; color: Qt.alpha(root.sand, 0.45) }
            GradientStop { position: 0.75; color: Qt.alpha(root.sand, 0.45) }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    Shape {
        x: 9
        y: root.horizon_y - 17
        width: 18
        height: 18
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 1.3
            strokeColor: Qt.tint(Theme.bg_core, Qt.alpha(Theme.ok, 0.55))
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            scale: Qt.size(0.9, 0.9)
            PathSvg { path: "M10 19Q9 13 11 7M11 7Q6 4 2 7M11 7Q8 2 4 1.5M11 7Q15 2 18.5 3M11 7Q16 6 18.5 10" }
        }
    }

    Rectangle {
        x: root.body_x - width / 2
        y: root.horizon_y - height / 2
        width: 13
        height: 13
        radius: width / 2
        color: Qt.alpha(root.sand, root.sky.day ? 0.16 : 0.1)
    }

    Rectangle {
        visible: root.sky.day
        x: root.body_x - width / 2
        y: root.horizon_y - height / 2
        width: 7
        height: 7
        radius: width / 2
        color: root.sand
    }

    Shape {
        visible: !root.sky.day
        x: root.body_x - 5
        y: root.horizon_y - 5
        width: 10
        height: 10
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: Qt.tint(root.sand, Qt.alpha(Theme.fg_strong, 0.35))
            scale: Qt.size(0.625, 0.625)
            PathSvg { path: "M11.5 1.94A7 7 0 1 0 11.5 14.06A6.06 6.06 0 0 1 11.5 1.94Z" }
        }
    }

    Shape {
        x: root.body_x - 8
        y: root.horizon_y + 4
        width: 18
        height: 4
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(Theme.info, root.sky.day ? 0.5 : 0.6)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathSvg { path: "M2 1H10M6 3H15" }
        }
    }
}
