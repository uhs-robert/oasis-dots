import QtQuick
import qs.styles.goldeneye.widgets as Goldeneye

// GoldenEye: Settings as a round watch. Only the `layout` part is given, so the section list, backdrop and panel art
// parts are unused; the drawing is in Goldeneye.SettingsWatch. See Default.qml for the slot contract.
QtObject {
    readonly property Component layout: Component {
        Goldeneye.SettingsWatch {}
    }
}
