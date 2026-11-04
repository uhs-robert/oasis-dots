import QtQuick

// A browse card's or list row's body: the provider's component given the item, its query match and whether it is
// selected.
Loader {
    id: root

    property var result: ({ item: {}, positions: [] })
    property bool is_selected: false

    Binding {
        target: root.item
        property: "entry"
        value: root.result.item
        when: root.status === Loader.Ready
    }

    Binding {
        target: root.item
        property: "positions"
        value: root.result.positions
        when: root.status === Loader.Ready
    }

    Binding {
        target: root.item
        property: "selected"
        value: root.is_selected
        when: root.status === Loader.Ready
    }
}
