// home/quickshell/.config/quickshell/services/ZoomIpc.qml
import Quickshell.Io

IpcHandler {
    target: "zoom"

    function start(): void {
        Zoom.start();
    }

    function stop(): void {
        Zoom.stop();
    }

    function step(delta: int): void {
        Zoom.step(delta);
    }

    function size(delta: int): void {
        Zoom.size(delta);
    }

    function full(): void {
        Zoom.toggle_full();
    }
}
