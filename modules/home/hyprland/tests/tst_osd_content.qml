import QtQuick
import QtTest
import "../quickshell/osd" as State

TestCase {
  id: tests
  name: "OsdContent"
  when: windowShown
  visible: true
  width: 680
  height: 300

  // Optional artifact output for a scratch harness. Normal tests grab in memory.
  property string screenshotDirectory: ""
  property var themeValues

  Rectangle {
    anchors.fill: parent
    color: "#242830"
  }

  Component {
    id: contentComponent
    State.OsdContent {
      x: 24
      y: 24
      transformOrigin: Item.TopLeft
    }
  }

  function initTestCase() {
    // Use the actual Theme values without importing the shell singleton/runtime.
    // Only its Quickshell-specific object declaration is adapted for QtTest.
    const request = new XMLHttpRequest();
    request.open("GET", Qt.resolvedUrl("../quickshell/Theme.qml"), false);
    request.send();
    verify(request.responseText.includes("Singleton {"));
    themeValues = Qt.createQmlObject(request.responseText
        .replace("pragma Singleton", "")
        .replace("import Quickshell", "")
        .replace("Singleton {", "QtObject {"), tests, "TestTheme");
    verify(themeValues !== null);
  }

  function node(id, name, virtual = false, muted = false, volume = 0.5) {
    const result = {id: id, name: name, description: name, ready: true, isSink: false};
    if (!virtual)
      result.audio = {volume: volume, muted: muted};
    return result;
  }

  function content(properties = {}) {
    const item = createTemporaryObject(contentComponent, tests, Object.assign({
      theme: themeValues,
      sink: node(1, "Desktop speakers"),
      source: node(2, "USB Microphone"),
      outputGlyph: "\uf025", // Injected unchanged sink glyph, as in the shell.
      event: {kind: "volume"}
    }, properties));
    verify(item !== null);
    return item;
  }

  function test_render_data() {
    const states = [
      {tag: "volume-zero", event: {kind: "volume"}, sink: node(1, "Speakers", false, false, 0)},
      {tag: "volume-half", event: {kind: "volume"}},
      {tag: "volume-full", event: {kind: "volume"}, sink: node(1, "Speakers", false, false, 1)},
      {tag: "volume-muted", event: {kind: "volume"}, sink: node(1, "Speakers", false, true)},
      {tag: "input-native", event: {kind: "input"}},
      {tag: "input-virtual", event: {kind: "input"}, source: node(2, "EasyEffects Source", true)},
      {tag: "output", event: {kind: "output"}},
      {tag: "input-unavailable", event: {kind: "input"}, source: null},
      {tag: "output-unavailable", event: {kind: "output"}, sink: null},
      {tag: "volume-unavailable", event: {kind: "volume"}, sink: null},
      {tag: "input-long", event: {kind: "input"}, source: node(2, "Studio microphone — USB interface with a deliberately very long device description that must wrap and elide safely", true)},
      {tag: "output-long", event: {kind: "output"}, sink: node(1, "UnbrokenDeviceName".repeat(12))},
      {tag: "microphone-muted", event: {kind: "microphone"}, source: node(2, "USB Microphone", false, true)},
      {tag: "microphone-snapshot", event: {kind: "microphone", value: 75, muted: true}, source: null},
      {tag: "microphone-error", event: {kind: "microphone", value: -1, muted: false, text: "Microphone mute failed: permission denied"}},
      {tag: "brightness", event: {kind: "brightness", value: 65}},
      {tag: "brightness-error", event: {kind: "brightness-error", value: -1, text: "Display unavailable"}}
    ];
    let rows = [];
    for (const scale of [1, 1.5])
      rows = rows.concat(states.map(state => Object.assign({}, state, {
        tag: state.tag + (scale === 1 ? "-native" : "-large"), scale: scale
      })));
    return rows;
  }

  function inside(item, child) {
    const topLeft = child.mapToItem(item, 0, 0);
    verify(topLeft.x >= 0 && topLeft.y >= 0, child.objectName + " starts inside panel");
    verify(topLeft.x + child.width <= item.width + 0.1, child.objectName + " fits horizontally");
    verify(topLeft.y + child.height <= item.height + 0.1, child.objectName + " fits vertically");
  }

  function test_render(data) {
    const properties = {event: data.event, scale: data.scale};
    if (data.sink !== undefined)
      properties.sink = data.sink;
    if (data.source !== undefined)
      properties.source = data.source;
    const item = content(properties);
    verify(waitForRendering(item));
    const label = findChild(item, "label");
    const meter = findChild(item, "meter");
    const volume = findChild(item, "volumeIcon");
    const microphone = findChild(item, "microphoneIcon");
    compare(label.visible, item.showLabel);
    compare(meter.visible, item.showMeter);
    compare(volume.visible, item.kind === "volume");
    compare(microphone.visible, item.kind === "input" || item.kind === "microphone");
    if (label.visible) {
      inside(item, label);
      verify(label.lineCount <= 3);
      verify(label.paintedWidth <= label.width + 1, "Text does not overflow its reserved width");
      compare(item.width, themeValues.osdWidth);
    } else {
      compare(item.label, "");
      compare(item.width, themeValues.osdVolumeWidth);
      compare(item.height, themeValues.osdIconSize + themeValues.osdPadding * 2
          + (meter.visible ? themeValues.osdPadding + themeValues.osdTrackHeight : 0));
    }
    if (meter.visible) {
      inside(item, meter);
      inside(item, findChild(item, "meterFill"));
    }
    if (volume.visible)
      inside(item, volume);
    if (microphone.visible)
      inside(item, microphone);
    if (item.kind === "input") {
      compare(meter.visible, false);
      compare(item.label, item.available ? item.source.description : "Microphone unavailable");
    }
    if (item.kind === "output")
      compare(findChild(item, "glyph").text, item.outputGlyph);

    const image = grabImage(tests);
    verify(image.width >= tests.width);
    // Verify actual pixels, not just presence of a QML object.
    const icon = volume.visible ? volume : microphone.visible ? microphone : findChild(item, "glyph");
    const point = icon.mapToItem(tests, 0, 0);
    let bright = 0;
    for (let y = Math.ceil(point.y); y < Math.floor(point.y + icon.height * data.scale); y++)
      for (let x = Math.ceil(point.x); x < Math.floor(point.x + icon.width * data.scale); x++)
        if (image.red(x, y) > 180)
          bright++;
    verify(bright > 10, "Production icon must actually render");
    if (screenshotDirectory)
      image.save(screenshotDirectory + "/" + data.tag + ".png");
  }

  function test_meter_is_interruptible_and_clamped() {
    const item = content();
    const meter = findChild(item, "meter");
    compare(meter.level, 50);
    item.sink = node(1, "Speakers", false, false, 1);
    wait(40);
    verify(meter.level > 50 && meter.level < 100);
    item.sink = node(1, "Speakers", false, false, 0.1);
    tryCompare(meter, "level", 10, 250);
    item.sink = node(1, "Speakers", false, true, 2);
    tryCompare(meter, "level", 100, 250);
    compare(findChild(item, "meterFill").color, themeValues.sliderFillMuted);
    item.sink = node(1, "Speakers", false, false, -1);
    tryCompare(meter, "level", 0, 250);
  }

  function test_muted_microphone_is_a_red_icon_only() {
    const item = content({
      event: {kind: "microphone"},
      source: node(2, "USB Microphone", false, true)
    });
    const microphone = findChild(item, "microphoneIcon");
    const label = findChild(item, "label");
    const meter = findChild(item, "meter");

    for (const event of [{kind: "microphone"}, {kind: "microphone", value: 75, muted: true}]) {
      item.event = event;
      verify(!label.visible);
      verify(!meter.visible);
      verify(microphone.visible);
      verify(findChild(item, "microphoneMuteCross").visible);
      compare(microphone.foreground, themeValues.statusError);
      const position = microphone.mapToItem(item, 0, 0);
      compare(position.x + microphone.width / 2, item.width / 2);
    }

    item.event = {kind: "microphone", value: 75, muted: false};
    verify(!label.visible);
    verify(meter.visible);
    verify(!findChild(item, "microphoneMuteCross").visible);
    compare(microphone.foreground, themeValues.foreground);

    item.source = node(2, "USB Microphone", false, false);
    item.event = {kind: "microphone"};
    verify(!label.visible);
    verify(meter.visible);
    compare(item.label, "");
    compare(microphone.foreground, themeValues.foreground);

    item.event = {kind: "input"};
    verify(label.visible);
    compare(item.label, "USB Microphone");
    compare(microphone.foreground, themeValues.foreground);

    item.event = {kind: "microphone", value: -1, muted: true, text: "Mute failed"};
    verify(label.visible);
    compare(item.label, "Mute failed");
  }

  function test_live_devices_and_completed_snapshots() {
    const item = content({event: {kind: "input"}});
    item.source = node(3, "New virtual microphone", true);
    compare(item.label, "New virtual microphone");
    verify(!item.failed);
    item.source = item.sink;
    compare(item.label, "Microphone unavailable");
    verify(item.failed);
    item.source = node(4, "Fallback name", true);
    item.source = Object.assign({}, item.source, {description: ""});
    compare(item.label, "Fallback name");

    item.event = {kind: "microphone", value: 75, muted: true};
    item.source = node(5, "Another microphone", false, false, 0.2);
    compare(item.value, 75);
    compare(item.muted, true);
    verify(!item.failed);
    verify(findChild(item, "microphoneMuteCross").visible);
    item.event = {kind: "microphone"};
    compare(item.value, 20);
    compare(item.muted, false);
    verify(!findChild(item, "microphoneMuteCross").visible);
    item.source = null;
    compare(item.label, "Microphone unavailable");
    compare(item.showMeter, false);
  }
}
