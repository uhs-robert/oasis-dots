// home/quickshell/.config/quickshell/popups/ClockPopup.qml
import QtQuick
import QtQuick.Layouts
import "../components"
import "../theme"
import "../services"

Popup {
    id: root

    popup_name: "clock"
    implicitWidth: 260
    implicitHeight: 284

    property date today: new Date()
    property int view_year: today.getFullYear()
    property int view_month: today.getMonth()
    property real last_g_ms: 0

    readonly property bool is_open: Popups.open_name === "clock"
    onIs_openChanged: if (is_open) go_today()

    function go_today() {
        const d = new Date();
        today = d;
        view_year = d.getFullYear();
        view_month = d.getMonth();
    }

    function prev_month() {
        if (view_month === 0) {
            view_month = 11;
            view_year -= 1;
        } else {
            view_month -= 1;
        }
    }

    function next_month() {
        if (view_month === 11) {
            view_month = 0;
            view_year += 1;
        } else {
            view_month += 1;
        }
    }

    function is_same_day(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    // ISO-8601 week number.
    function week_number(d) {
        const dt = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day_num = (dt.getUTCDay() + 6) % 7;
        dt.setUTCDate(dt.getUTCDate() - day_num + 3);
        const first_thursday = new Date(Date.UTC(dt.getUTCFullYear(), 0, 4));
        const diff_days = (dt - first_thursday) / 86400000 - 3 + ((first_thursday.getUTCDay() + 6) % 7);
        return 1 + Math.round(diff_days / 7);
    }

    function build_weeks() {
        const first = new Date(view_year, view_month, 1);
        const start_offset = (first.getDay() + 6) % 7;
        const start = new Date(view_year, view_month, 1 - start_offset);
        const weeks = [];
        for (let w = 0; w < 6; w++) {
            const days = [];
            for (let d = 0; d < 7; d++) {
                const cur = new Date(start);
                cur.setDate(start.getDate() + w * 7 + d);
                days.push(cur);
            }
            weeks.push({ week_num: week_number(days[0]), days: days });
        }
        return weeks;
    }

    readonly property var weeks: build_weeks()
    readonly property var weekday_headers: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    Item {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_H) {
                root.prev_month();
                event.accepted = true;
            } else if (event.key === Qt.Key_L) {
                root.next_month();
                event.accepted = true;
            } else if (event.key === Qt.Key_J) {
                root.view_year += 1;
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                root.view_year -= 1;
                event.accepted = true;
            } else if (event.key === Qt.Key_BracketRight) {
                Timezones.cycle(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_BracketLeft) {
                Timezones.cycle(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_T) {
                root.go_today();
                event.accepted = true;
            } else if (event.key === Qt.Key_G) {
                const now = Date.now();
                if (now - root.last_g_ms < 500) {
                    root.go_today();
                    root.last_g_ms = 0;
                } else {
                    root.last_g_ms = now;
                }
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDate(new Date(root.view_year, root.view_month, 1), "MMMM yyyy")
                color: Theme.fg_core
                font.family: Theme.font_family
                font.pixelSize: Theme.popup_font_size
                font.bold: true
            }

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10

                Repeater {
                    model: Timezones.zones

                    Text {
                        id: zone_label
                        required property int index

                        readonly property bool is_active: index === Timezones.index

                        text: Timezones.abbrevs[index] || "..."
                        color: is_active ? Theme.theme_secondary : Theme.fg_muted
                        font.family: Theme.font_family
                        font.pixelSize: Theme.popup_font_size - 2
                        font.bold: is_active
                        font.underline: is_active

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Timezones.index = zone_label.index
                        }
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4

                Text {
                    Layout.preferredWidth: 22
                    text: ""
                }

                Repeater {
                    model: root.weekday_headers

                    Text {
                        required property string modelData

                        Layout.preferredWidth: 24
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Theme.fg_muted
                        font.family: Theme.font_family
                        font.pixelSize: Theme.popup_font_size - 2
                    }
                }
            }

            Repeater {
                model: root.weeks

                RowLayout {
                    required property var modelData

                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4

                    Text {
                        Layout.preferredWidth: 22
                        horizontalAlignment: Text.AlignHCenter
                        text: parent.modelData.week_num
                        color: Theme.fg_dim
                        font.family: Theme.font_family
                        font.pixelSize: Theme.popup_font_size - 2
                    }

                    Repeater {
                        model: parent.modelData.days

                        Text {
                            required property date modelData

                            readonly property bool in_month: modelData.getMonth() === root.view_month
                            readonly property bool is_today: root.is_same_day(modelData, root.today)

                            Layout.preferredWidth: 24
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.getDate()
                            color: is_today ? Theme.theme_accent : (in_month ? Theme.fg_core : Theme.fg_muted)
                            font.family: Theme.font_family
                            font.pixelSize: Theme.popup_font_size - 1
                            font.underline: is_today
                        }
                    }
                }
            }
        }
    }
}
