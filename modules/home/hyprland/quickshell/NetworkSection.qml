import QtQuick
import Quickshell
import Quickshell.Networking

// Network section (control-center.md sec. 9.7, stage 5 - the plan's
// highest-risk stage: scanner latch, passphrase focus, SSID dedup). All state
// lives in `NetworkState` (§10 I2's corollary: a section holds no state the
// rest of the system can observe) - this is a pure view over it plus
// `Networking` itself.
ControlCenterSection {
  id: root

  // Threaded down from ControlCenter.qml's own per-screen root Item so an
  // open passphrase field several levels below can explicitly hand focus
  // back to it once it gives up its own - see ControlCenterField's own
  // `focusFallback` doc for why that cannot happen implicitly.
  property Item focusFallback: null

  readonly property var wifi: NetworkState.wifiDevice
  readonly property var wired: NetworkState.wiredDevice
  readonly property var connectedNetwork: NetworkState.sortedNetworks.find(net => net.connected) ?? null

  function isOpenSecurity(security) {
    return security === WifiSecurityType.Open || security === WifiSecurityType.Owe;
  }

  // "connected" expands to Disconnect/Forget; "known" and "open" connect
  // immediately with no inline expansion; "psk" expands to an inline
  // passphrase field; anything else (Wpa2Eap/WpaEap/Wpa3SuiteB192/
  // DynamicWep/Leap, and defensively "Unknown") expands to the enterprise
  // notice - never a silent `connect()` attempt on a security type this
  // panel cannot actually complete (U-1 style: default to the safer branch).
  function rowKind(net) {
    if (net.connected)
      return "connected";
    if (net.known)
      return "known";
    if (root.isOpenSecurity(net.security))
      return "open";
    switch (net.security) {
    case WifiSecurityType.Sae:
    case WifiSecurityType.Wpa2Psk:
    case WifiSecurityType.WpaPsk:
    case WifiSecurityType.StaticWep:
      return "psk";
    default:
      return "enterprise";
    }
  }

  // `hasLink` is carrier-detect only ("cable plugged in"), not connectivity -
  // a cable into a dead switch or a disconnected-but-plugged device reads as
  // linked with no traffic actually reaching anywhere. `connected` is
  // NetworkManager's own connectivity signal for the device, so that is what
  // drives the glyph/summary/colour here; `hasLink` stays as the extra
  // "Unplugged" detail on the wired row below.
  glyph: {
    if (root.wired?.connected)
      return Icons.ethernet;
    if (root.connectedNetwork)
      return NetworkState.signalGlyph(root.connectedNetwork.signalStrength);
    return Icons.wifiOff;
  }
  title: "Network"
  expanded: ControlCenter.expandedSection === "network"
  onHeaderClicked: ControlCenter.expandedSection = root.expanded ? "" : "network"

  // I5: no network devices enumerated at all hides the whole section rather
  // than rendering a shell that can never report anything real.
  visible: Networking.devices.values.length > 0

  summary: {
    if (root.wired?.connected)
      return `Wired · ${root.wired.name}`;
    if (root.connectedNetwork)
      return `${NetworkState.signalGlyph(root.connectedNetwork.signalStrength)} ${root.connectedNetwork.name}`;
    return "Offline";
  }
  summaryColor: (root.wired?.connected || root.connectedNetwork) ? Theme.foregroundDim : Theme.statusError

  // Wired device (name, address, link speed, up/down), when the machine has
  // an ethernet adapter at all. `linkSpeed` is unitless in the shipped
  // qmltypes; NetworkManager's own device-speed property (which this almost
  // certainly wraps) is documented in Mb/s, so that is what is shown.
  // Informational only (§9.7) — no click handler. This row previously called
  // `disconnect()` on click, which also blocks NetworkManager autoconnect
  // until the device is explicitly reactivated; on a wired-only machine that
  // takes it offline with no affordance in this row to get back.
  ControlCenterRow {
    width: parent.width
    visible: root.wired !== null
    glyph: Icons.ethernet
    label: root.wired?.name ?? ""
    sublabel: root.wired ? (root.wired.hasLink ? `${root.wired.address} · ${root.wired.linkSpeed} Mb/s` : "Unplugged") : ""
    dimmed: root.wired !== null && !root.wired.hasLink
  }

  // The radio switch itself, independent of whether a WifiDevice currently
  // enumerates - `Networking.wifiEnabled`/`wifiHardwareEnabled` are global
  // backend properties, not per-device (confirmed against the shipped
  // qmltypes).
  ControlCenterRow {
    width: parent.width
    visible: root.wifi !== null
    label: "Wi-Fi"
    sublabel: Networking.wifiHardwareEnabled ? "" : "Blocked by hardware switch"
    enabled: Networking.wifiHardwareEnabled

    ControlCenterToggle {
      checked: Networking.wifiEnabled
      onToggled: value => Networking.wifiEnabled = value
    }
  }

  // No "Rescan" button (§9.7): `NetworkState`'s own Binding is the only thing
  // that ever writes `wifiDevice.scannerEnabled`, latched to this section
  // being the expanded one with the panel open - reopening this section
  // resumes scanning on its own.
  Repeater {
    model: NetworkState.sortedNetworks

    Column {
      id: networkDelegate

      required property var modelData

      width: parent.width
      readonly property string kind: root.rowKind(networkDelegate.modelData)
      readonly property bool isOpen: ControlCenter.openPicker === networkDelegate.modelData.name
      property string failureReason: ""

      // The one path both the Enter key and the Join button submit through
      // (they used to diverge: Join cleared `NetworkState.pendingPassphrase`
      // before calling connectWithPsk, Enter did not, so an Enter-submitted
      // join left the plaintext PSK sitting in the singleton until the panel
      // closed). Clearing here, in both cases, before handing the secret to
      // connectWithPsk means a failed join has already lost the passphrase
      // (I9 outranks the convenience of leaving it there to retry) - the
      // failure message below says so explicitly.
      function joinWithPassphrase(psk) {
        NetworkState.pendingPassphrase = "";
        networkDelegate.modelData.connectWithPsk(psk);
      }

      visible: root.wifi !== null

      ControlCenterRow {
        width: parent.width
        glyph: NetworkState.signalGlyph(networkDelegate.modelData.signalStrength)
        label: networkDelegate.modelData.name
        sublabel: {
          const parts = [WifiSecurityType.toString(networkDelegate.modelData.security)];
          if (networkDelegate.modelData.known)
            parts.push("Saved");
          return parts.join(" · ");
        }

        // known/open|owe connect immediately with nothing to expand;
        // everything else (connected, psk, enterprise) toggles this row's
        // own inline expander, exclusively via `ControlCenter.openPicker`
        // (I7) - opening one row's expander closes any other that was open.
        onClicked: {
          if (networkDelegate.kind === "known" || networkDelegate.kind === "open") {
            networkDelegate.modelData.connect();
            return;
          }
          ControlCenter.openPicker = networkDelegate.isOpen ? "" : networkDelegate.modelData.name;
        }

        Text {
          visible: !root.isOpenSecurity(networkDelegate.modelData.security)
          text: Icons.lock
          color: Theme.foregroundDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSize - 4
        }
      }

      Item {
        id: expandClip

        width: parent.width
        height: networkDelegate.isOpen ? (expandLoader.item?.implicitHeight ?? 0) : 0
        clip: true

        Behavior on height {
          NumberAnimation {
            duration: Theme.sectionExpandDuration
            easing.type: Easing.OutCubic
          }
        }

        Loader {
          id: expandLoader
          width: expandClip.width
          active: networkDelegate.isOpen
          sourceComponent: {
            switch (networkDelegate.kind) {
            case "connected":
              return connectedExpander;
            case "psk":
              return pskExpander;
            case "enterprise":
              return enterpriseExpander;
            default:
              return null;
            }
          }
        }
      }

      Component {
        id: connectedExpander

        Column {
          width: expandLoader.width

          ControlCenterRow {
            width: parent.width
            label: "Disconnect"
            onClicked: {
              networkDelegate.modelData.disconnect();
              ControlCenter.openPicker = "";
            }
          }

          ControlCenterRow {
            width: parent.width
            label: "Forget"
            onClicked: {
              networkDelegate.modelData.forget();
              ControlCenter.openPicker = "";
            }
          }
        }
      }

      Component {
        id: pskExpander

        Column {
          width: expandLoader.width

          // Reset once per fresh open rather than on every failed attempt -
          // otherwise a stale error from a previous, already-abandoned
          // attempt at this same network would flash back up the instant the
          // row is reopened, before the user has done anything this time.
          Component.onCompleted: networkDelegate.failureReason = ""

          Item {
            width: parent.width
            height: Theme.fieldHeight

            ControlCenterField {
              id: pskField

              anchors {
                left: parent.left
                right: parent.right
                leftMargin: Theme.rowPaddingH
                rightMargin: Theme.rowPaddingH
                verticalCenter: parent.verticalCenter
              }

              placeholder: "Password"
              text: NetworkState.pendingPassphrase
              focusFallback: root.focusFallback

              // The one authoritative copy is `NetworkState.pendingPassphrase`
              // (I9): every keystroke mirrors into it immediately, and it
              // reaches only `connectWithPsk()`, via `joinWithPassphrase()`
              // above - never a Process argv, a file, or a log.
              onTextChanged: NetworkState.pendingPassphrase = text
              onAccepted: networkDelegate.joinWithPassphrase(pskField.text)
            }
          }

          ControlCenterRow {
            width: parent.width
            label: "Join"
            enabled: NetworkState.pendingPassphrase.length > 0
            // Same path as pressing Enter in the field above
            // (`joinWithPassphrase()`) so both submit routes clear
            // `NetworkState.pendingPassphrase` identically (I9).
            onClicked: networkDelegate.joinWithPassphrase(NetworkState.pendingPassphrase)
          }

          Text {
            width: parent.width
            visible: networkDelegate.failureReason !== ""
            text: networkDelegate.failureReason
            color: Theme.statusError
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            wrapMode: Text.WordWrap
            leftPadding: Theme.rowPaddingH
            rightPadding: Theme.rowPaddingH
          }
        }
      }

      Component {
        id: enterpriseExpander

        Column {
          width: expandLoader.width

          Text {
            width: parent.width
            text: "Requires enterprise setup"
            color: Theme.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            wrapMode: Text.WordWrap
            leftPadding: Theme.rowPaddingH
            rightPadding: Theme.rowPaddingH
          }

          ControlCenterRow {
            width: parent.width
            label: "Open nmtui..."
            onClicked: Quickshell.execDetached(["ghostty", "-e", "nmtui"])
          }
        }
      }

      // Surfaces a failed attempt inline rather than silently doing nothing.
      // Both submit paths clear `NetworkState.pendingPassphrase` before the
      // attempt even resolves (via `joinWithPassphrase()` above), so there is
      // never a live copy to protect by the time a failure can happen (I9) -
      // this just re-asserts the row stays open and reports the failure,
      // with the password already gone and needing to be retyped.
      Connections {
        target: networkDelegate.modelData
        function onConnectionFailed(reason) {
          networkDelegate.failureReason = `${ConnectionFailReason.toString(reason)} — retype the password and try again.`;
          if (networkDelegate.kind === "psk")
            ControlCenter.openPicker = networkDelegate.modelData.name;
        }
      }
    }
  }
}
