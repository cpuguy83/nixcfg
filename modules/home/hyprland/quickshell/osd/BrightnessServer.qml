import QtQuick
import Quickshell.Io
import "Logic.js" as Logic

// Built-in IPC endpoint, not a per-connection SocketServer. Quickshell 0.3.0
// retains SocketServer handlers after disconnect; no handlers are allocated here.
QtObject {
  id: root
  signal received(var event)

  property IpcHandler endpoint: IpcHandler {
    target: "osd"
    // An explicit reply lets brightnessd distinguish validation failure from
    // successful delivery. Empty screen is the normal focused-screen fallback.
    function brightness(screen: string, value: int, message: string): string {
      try {
        root.received(Logic.brightnessEvent(screen, value, message));
        return "ok";
      } catch (error) {
        return String(error);
      }
    }
  }
}
