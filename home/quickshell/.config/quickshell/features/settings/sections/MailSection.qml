import QtQuick
import qs.features.settings
import qs.features.mail

RowsSection {
    id: root

    function on_off(key) {
        return { values: () => ["on", "off"], text: v => v, value: () => MailSettings[key] ? "on" : "off", set: v => MailSettings.set(key, v === "on") };
    }

    footer_hint: "j/k move · " + root.layout_hint + "H/L change · Enter list · h/Esc sections · q close"
    rows: [
        Object.assign({ label: "Check every", desc: "Seconds between unread counts from Thunderbird. Needs DesertBird's bridge and folder sharing turned on." }, {
            values: () => MailSettings.choices.interval_s,
            text: v => v + " s",
            value: () => MailSettings.interval_s,
            set: v => MailSettings.set("interval_s", v)
        }),
        Object.assign({ label: "Skip trash", desc: "Leave unread mail in trash folders out of the count." }, root.on_off("skip_trash")),
        Object.assign({ label: "Skip junk", desc: "Leave unread mail in junk and spam folders out of the count." }, root.on_off("skip_junk")),
        Object.assign({ label: "Show headers", desc: "Show the sender, subject and date of the newest unread mail in the popup. Needs header sharing on in DesertBird. Hidden while recording, sharing the screen or locked." }, root.on_off("mail_preview"))
    ]
}
