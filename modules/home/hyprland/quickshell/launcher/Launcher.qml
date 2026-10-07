import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "Logic.js" as Logic

Scope {
  id: root

  property bool ready: false
  property bool picker: false
  property string prompt: ""
  property var lines: []
  property int revision: 0
  property int resultRevision: -1
  property bool resultOk: false
  property string resultText: ""
  property string errorText: ""
  property bool busy: false
  property bool closing: false
  property bool announced: false
  property string requestId: ""
  property string hidingId: ""
  property var activeClient: null
  property double sequence: 0
  readonly property var search: searchLoader.item
  readonly property string queryText: search ? search.text : ""
  property string screenName: ""
  readonly property string focusedScreenName: Hyprland.focusedMonitor?.name ?? ""
  readonly property var launchScreen: Logic.screenForLaunch(Quickshell.screens, screenName, (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "") !== "")
  property var appRows: []
  readonly property var route: Logic.routeQuery(queryText, picker, appRows.length)
  readonly property bool math: route.math
  readonly property var rows: picker ? Logic.pickerRows(lines, queryText) : math ? [] : appRows
  property int selected: rows.length ? 0 : -1

  function rebuildApps() {
    // Read live entries only here; appRows retains plain data, not QObjects.
    const next = ready && !picker ? Logic.applicationRows(DesktopEntries.applications.values, queryText) : [];
    if (JSON.stringify(next) !== JSON.stringify(appRows))
      appRows = next;
  }

  onReadyChanged: rebuildApps()
  onQueryTextChanged: rebuildApps()

  Connections {
    target: DesktopEntries
    function onApplicationsChanged() {
      Qt.callLater(root.rebuildApps);
    }
  }

  function send(message) {
    if (activeClient && ready && !closing && requestId) {
      message.id = requestId;
      writePeer(activeClient, message);
    }
  }

  function writePeer(peer, message) {
    if (peer && peer.connected) {
      peer.write(JSON.stringify(message) + "\n");
      peer.flush();
    }
  }

  function rejectPeer(peer) {
    writePeer(peer, {
      type: "error",
      id: peer.requestId,
      message: "Launcher request rejected: busy or invalid request"
    });
    peer.connected = false;
  }

  function admitPeer(peer) {
    if (!peer.connected || peer.handled)
      return;

    peer.handled = true;
    if (activeClient || hidingId) {
      rejectPeer(peer);
      return;
    }

    sequence++;
    peer.requestId = String(sequence);
    activeClient = peer;
    requestId = peer.requestId;
    writePeer(peer, {
      type: "admit",
      version: 1,
      id: peer.requestId
    });
  }

  function disconnectPeer(peer) {
    if (activeClient !== peer)
      return;

    activeClient = null;
    if (requestId || hidingId)
      hide(peer.requestId);
  }

  function receivePeer(peer, data) {
    if (activeClient !== peer || data.length > 8 * 1024 * 1024) {
      rejectPeer(peer);
      return;
    }

    let message;
    try {
      message = JSON.parse(data);
    } catch (error) {
      rejectPeer(peer);
      return;
    }

    if (!message || typeof message !== "object" || Array.isArray(message) ||
        typeof message.type !== "string" || typeof message.id !== "string") {
      rejectPeer(peer);
      return;
    }
    if (message.id !== peer.requestId)
      return;

    if (message.type === "init") {
      if (peer.initialized || hidingId ||
          typeof message.picker !== "boolean" ||
          typeof message.prompt !== "string" || message.prompt.length > 1024 ||
          typeof message.query !== "string" || message.query.length > 4096 ||
          message.query.includes("\0") || !Array.isArray(message.lines) ||
          message.lines.length > 10000 || (!message.picker && message.lines.length) ||
          (message.picker && message.query !== "")) {
        rejectPeer(peer);
        return;
      }

      let size = 0;
      for (const line of message.lines) {
        if (typeof line !== "string" || line.includes("\n") || line.length > 16384) {
          rejectPeer(peer);
          return;
        }
        size += line.length + 1;
      }
      if (size > 1024 * 1024 + 1) {
        rejectPeer(peer);
        return;
      }

      peer.initialized = true;
      closing = false;
      screenName = focusedScreenName;
      picker = message.picker;
      prompt = message.prompt;
      lines = message.lines;
      searchLoader.active = true;
      search.text = message.query;
      ready = true;
      return;
    }

    if (data.length > 64 * 1024) {
      rejectPeer(peer);
      return;
    }
    if (message.type === "hide") {
      hide(message.id);
      return;
    }
    if (!ready || closing)
      return;

    if (message.type === "result" && Number.isInteger(message.revision) &&
        typeof message.ok === "boolean" && typeof message.text === "string") {
      if (message.revision === revision) {
        resultRevision = message.revision;
        resultOk = message.ok;
        resultText = message.text;
      }
    } else if (message.type === "error" && typeof message.text === "string") {
      busy = false;
      errorText = message.text;
    } else {
      rejectPeer(peer);
    }
  }

  function hide(id) {
    closing = true;
    announced = false;
    ready = false;
    revision++;
    debounce.stop();
    hidingId = id;
    requestId = "";
    Qt.inputMethod.reset();
    searchLoader.active = false;
    lines = [];
    prompt = "";
    resultOk = false;
    resultRevision = -1;
    resultText = "";
    errorText = "";
    appRows = [];
    selected = -1;
    list.contentY = 0;
    busy = false;
    picker = false;
    screenName = "";
    Qt.callLater(ackHidden);
  }

  function ackHidden() {
    if (hidingId && !overlay.backingWindowVisible) {
      const id = hidingId;
      hidingId = "";
      writePeer(activeClient, {
        type: "hidden",
        id: id
      });
    }
  }

  function dismiss() {
    send({
      type: "cancel"
    });
    closing = true;
  }

  function changed() {
    revision++;
    resultOk = false;
    resultRevision = -1;
    resultText = "";
    errorText = "";
    debounce.stop();
    if (!ready || !announced || picker || closing)
      return;
    send({
      type: "query",
      revision: revision,
      text: route.text,
      raw: queryText
    });
    if (route.hasExpression)
      debounce.restart();
  }

  function activate() {
    if (!ready || busy)
      return;
    if (math) {
      if (resultOk && resultRevision === revision) {
        busy = true;
        send({
          type: "copy",
          revision: revision
        });
      }
    } else if (selected >= 0 && selected < rows.length) {
      busy = true;
      const row = rows[selected];
      send(picker ? {
        type: "select",
        index: row.index
      } : {
        type: "launch",
        desktopId: row.id
      });
    }
  }

  function move(delta) {
    selected = Logic.navigate(selected, delta, rows.length);
    list.positionViewAtIndex(selected, ListView.Contain);
  }

  onRowsChanged: selected = rows.length ? 0 : -1
  // Catalog updates can change the route without changing the search text.
  onRouteChanged: changed()
  onFocusedScreenNameChanged: {
    if (ready && !screenName)
      screenName = focusedScreenName;
  }

  Timer {
    id: debounce
    interval: 150
    onTriggered: root.send({
      type: "calculate",
      revision: root.revision
    })
  }

  SocketServer {
    id: server
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-launcher-daemon/control.sock"
    active: true
    onActiveStatusChanged: {
      if (!active) {
        console.error("Launcher socket server stopped");
      }
    }

    handler: Socket {
      id: peer
      property bool handled: false
      property bool initialized: false
      property string requestId: ""

      Component.onCompleted: root.admitPeer(peer)
      onConnectionStateChanged: {
        if (connected)
          root.admitPeer(peer);
        else
          root.disconnectPeer(peer);
      }
      onError: {
        console.error("Launcher client transport failed");
        connected = false;
        root.disconnectPeer(peer);
      }

      property Timer admissionTimeout: Timer {
        interval: 8000
        running: peer.connected && root.activeClient === peer && !peer.initialized
        onTriggered: root.rejectPeer(peer)
      }

      parser: SplitParser {
        splitMarker: "\n"
        onRead: data => root.receivePeer(peer, data)
      }
    }
  }

  PanelWindow {
    id: overlay
    visible: root.ready && root.launchScreen !== null
    screen: root.launchScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "launcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    onBackingWindowVisibleChanged: {
      if (!backingWindowVisible) {
        root.ackHidden();
      } else if (root.ready && !root.announced) {
        root.announced = true;
        search.forceActiveFocus();
        search.selectAll();
        root.send({
          type: "ready"
        });
        root.changed();
      }
    }

    Item {
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }

      Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(620, overlay.width - 40)
        height: Math.min(510, overlay.height - 40)
        radius: 18
        color: "#dc141416"
        border.color: "#22ffffff"
        border.width: 1

        MouseArea {
          anchors.fill: parent
        }

        Column {
          anchors.fill: parent
          anchors.margins: 20
          spacing: 12

          Text {
            width: parent.width
            text: root.math ? "Calculator" : root.prompt
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: "#d4d7de"
            font.family: "Inter"
            font.pixelSize: 14
          }

          Rectangle {
            width: parent.width
            height: 44
            radius: 10
            color: "#10ffffff"

            Loader {
              id: searchLoader
              active: false
              anchors.fill: parent
              anchors.margins: 12
              sourceComponent: TextInput {
                color: "#edf1f7"
                font.family: "Inter"
                font.pixelSize: 17
                clip: true
                focus: true
                enabled: !root.busy
                maximumLength: 4096
                selectByMouse: true
                Keys.onEscapePressed: root.dismiss()
                Keys.onReturnPressed: root.activate()
                Keys.onEnterPressed: root.activate()
                Keys.onUpPressed: root.move(-1)
                Keys.onDownPressed: root.move(1)
                Keys.onPressed: event => {
                  if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
                    root.move(event.key === Qt.Key_PageDown ? 7 : -7);
                    event.accepted = true;
                  }
                }
              }
            }
          }

          Item {
            width: parent.width
            height: Math.max(40, panel.height - 164)

            ListView {
              id: list
              anchors.fill: parent
              visible: !root.math
              model: root.rows
              clip: true
              spacing: 4
              currentIndex: root.selected
              delegate: Rectangle {
                required property var modelData
                required property int index
                width: list.width
                height: 42
                radius: 10
                color: index === root.selected ? "#18ffffff" : "transparent"

                Image {
                  id: icon
                  anchors.left: parent.left
                  anchors.leftMargin: 10
                  anchors.verticalCenter: parent.verticalCenter
                  width: root.picker ? 0 : 26
                  height: width
                  visible: !root.picker
                  source: modelData.icon ? Quickshell.iconPath(modelData.icon, "application-x-executable") : ""
                }

                Text {
                  anchors.left: icon.right
                  anchors.right: parent.right
                  anchors.margins: 10
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.text
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: "#edf1f7"
                  font.family: "Inter"
                  font.pixelSize: 16
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    root.selected = index;
                    root.activate();
                  }
                }
              }
            }

            Rectangle {
              id: resultRow
              readonly property bool selected: root.math && root.resultOk && root.resultRevision === root.revision
              width: parent.width
              height: Math.min(parent.height, Math.max(42, resultLabel.implicitHeight + 16))
              radius: 10
              color: selected ? "#18ffffff" : "transparent"
              visible: root.math || !root.rows.length
              clip: true

              Text {
                id: resultLabel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 8
                leftPadding: resultIcon.visible ? resultIcon.width + 12 : 0
                text: root.math ? (root.resultText || (root.route.hasExpression ? "" : "Enter an expression after =")) : "No matches"
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 10
                color: root.math && root.resultText && !root.resultOk ? "#ff8888" : "#edf1f7"
                font.family: "Inter"
                font.pixelSize: root.math ? 22 : 16
              }

              Image {
                id: resultIcon
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: 10
                anchors.topMargin: 11
                width: 22
                height: 22
                visible: resultRow.selected
                source: Quickshell.iconPath("accessories-calculator")
              }

              MouseArea {
                anchors.fill: parent
                enabled: resultRow.selected && !root.busy
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.activate()
              }
            }
          }

          Text {
            width: parent.width
            text: root.errorText || (root.busy ? "Working..." : root.math ? "Click or Enter: copy result    Escape: cancel" : root.picker ? "Enter: select    Escape: cancel" : "Enter: launch    No match: calculate    =: force    Esc: cancel")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.errorText ? "#ff8888" : "#7f838c"
            font.family: "Inter"
            font.pixelSize: 12
          }
        }
      }
    }
  }
}
