.pragma library

// The set of things currently drawing cava, kept as immutable lists so a QML `var` property holding one notifies on
// change. Keyed by the viewer object itself rather than a counter: registering twice is one viewer, and a viewer that
// is destroyed while shown can be removed without knowing how often it registered.

function register(viewers, viewer) {
    return viewers.indexOf(viewer) >= 0 ? viewers : viewers.concat([viewer]);
}

function unregister(viewers, viewer) {
    return viewers.indexOf(viewer) < 0 ? viewers : viewers.filter(v => v !== viewer);
}

function any(viewers) {
    return viewers.length > 0;
}
