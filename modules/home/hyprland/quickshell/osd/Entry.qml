import QtQuick

// Per-screen lifetime, independent of other monitors and of the transport.
QtObject {
  id: root

  property var event: null
  property int duration: 1800
  property bool active: false

  function show(event) {
    root.event = event;
    root.active = true;

    expiry.restart();
  }

  property Timer expiry: Timer {
    interval: root.duration
    onTriggered: root.active = false
  }
}
