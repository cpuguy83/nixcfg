import QtQuick

// Expandable tile for one section of the panel (§9.4/§9.9): a header (leading
// glyph, title, right-aligned summary, chevron) plus a clipped body that
// animates open/closed. `body` is a default property alias, so a caller
// writes `ControlCenterSection { ControlCenterRow { ... } }` and the row just
// becomes the body — the same way children of a plain Column read.
Column {
  id: root

  property string glyph: ""
  property string title: ""
  property string summary: ""
  // Lets a section colour its own status (e.g. VPN's connected/connecting
  // state, §9.6) rather than always reading as neutral dimmed text. Defaults
  // to the plain colour every other section already used before this
  // existed.
  property color summaryColor: Theme.foregroundDim
  property bool expanded: false

  // Audio (stage 2) is pinned open and never collapses (§9.7). Rather than
  // special-case "the Audio section" by name anywhere, the header itself
  // just stops being clickable and hides its chevron.
  property bool collapsible: true

  // Optional control embedded in the header itself, left of the chevron
  // (e.g. the Bluetooth/WiFi power toggle, stage 3+) — usable without
  // expanding the section, mirroring macOS Control Center. A Component
  // rather than a plain child Item: a second default property is not legal
  // in QML, and `body` already claims that slot.
  property Component headerAccessory: null

  // Accordion members (stage 3+) key `expanded` off `ControlCenter.expandedSection`
  // via an inline binding, so clicking the header must never write `expanded`
  // directly — that would sever the binding the same way a Timer writing
  // `adapter.discovering` alongside a Binding would (§10 I2). The header
  // click is emitted instead; the caller decides what it means.
  signal headerClicked

  default property alias body: bodyColumn.data

  Rectangle {
    id: header

    width: root.width
    height: Theme.sectionHeaderHeight
    radius: Theme.sectionRadius
    color: root.expanded ? Theme.sectionBackgroundExpanded : headerMouse.containsMouse ? Theme.itemHover : Theme.sectionBackground

    Row {
      id: leading

      anchors {
        left: parent.left
        leftMargin: Theme.sectionPadding
        verticalCenter: parent.verticalCenter
      }
      spacing: Theme.sectionSpacing

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.glyph !== ""
        text: root.glyph
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
      }
    }

    Text {
      id: summaryLabel

      anchors {
        left: leading.right
        leftMargin: Theme.sectionSpacing
        right: root.headerAccessory !== null ? accessory.left : chevron.left
        rightMargin: Theme.sectionSpacing
        verticalCenter: parent.verticalCenter
      }
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      text: root.summary
      color: root.summaryColor
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize - 2
    }

    Text {
      id: chevron

      anchors {
        right: parent.right
        rightMargin: Theme.sectionPadding
        verticalCenter: parent.verticalCenter
      }
      visible: root.collapsible
      text: Icons.menuSubmenu
      rotation: root.expanded ? 90 : 0
      color: Theme.foregroundDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize - 4
    }

    MouseArea {
      id: headerMouse

      anchors.fill: parent
      hoverEnabled: true
      enabled: root.collapsible
      onClicked: root.headerClicked()
    }

    // Declared after `headerMouse` so it stacks on top and claims its own
    // clicks (e.g. flipping a power toggle must never also fire
    // `headerClicked` and expand the section) — the same ordering trick
    // `ControlCenterRow`'s trailing slot uses over its own row click area.
    Loader {
      id: accessory

      anchors {
        right: chevron.left
        rightMargin: Theme.sectionSpacing
        verticalCenter: parent.verticalCenter
      }
      active: root.headerAccessory !== null
      sourceComponent: root.headerAccessory
    }
  }

  Item {
    id: bodyClip

    width: root.width
    height: root.expanded ? bodyColumn.implicitHeight : 0
    clip: true

    // Matches Switcher.qml's carousel timing (140ms OutCubic) so every
    // animated surface in the shell moves at the same rate.
    Behavior on height {
      NumberAnimation {
        duration: Theme.sectionExpandDuration
        easing.type: Easing.OutCubic
      }
    }

    Column {
      id: bodyColumn

      width: bodyClip.width
      // Without this every child sat flush against the next — sliders touching
      // pickers touching headings — which read as one undifferentiated block.
      spacing: Theme.sectionSpacing
      topPadding: Theme.sectionSpacing
      bottomPadding: Theme.sectionPadding
    }
  }
}
