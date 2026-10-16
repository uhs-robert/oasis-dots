import QtQuick
import qs.theme

// The popup's two-digit position in the style's title_index, drawn before its title.
Text {
    id: root

    property var st: Style.for_item(root)
    property string name: ""
    readonly property int position: root.st.title_index.indexOf(root.name)
    // Room the title leaves for the index; zero when the name is not listed.
    // implicitWidth is read even while hidden: Text lays out lazily, and a first read after startup emits
    // implicitWidthChanged from inside this binding (and title_tab's height) and logs a binding loop.
    readonly property real space: {
        const text_width = root.implicitWidth;
        return root.visible ? text_width + 12 : 0;
    }

    visible: root.position >= 0
    text: String(root.position + 1).padStart(2, "0")
    color: root.st.text_accent
    font.family: root.st.number_font
    font.weight: Font.ExtraLight
    font.pixelSize: root.st.fs(8)
}
