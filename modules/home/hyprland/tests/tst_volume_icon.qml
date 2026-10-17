import QtQuick
import QtTest
import "../quickshell/osd" as State

TestCase {
  id: tests
  name: "VolumeIcon"
  when: windowShown
  visible: true
  width: 120
  height: 120

  Rectangle {
    anchors.fill: parent
    color: "black"
  }

  Component {
    id: iconComponent
    State.VolumeIcon {}
  }

  Component {
    id: rowComponent
    Row {
      spacing: 12
      State.VolumeIcon {
        objectName: "icon"
        width: 20
        height: 20
      }
      Text {
        objectName: "label"
        text: "Volume"
      }
    }
  }

  function icon(properties = {}) {
    const result = createTemporaryObject(iconComponent, tests, properties);
    verify(result !== null);
    return result;
  }

  function test_progression_data() {
    return [
      {
        tag: "negative",
        volume: -20,
        expected: [0, 0, 0]
      },
      {
        tag: "zero",
        volume: 0,
        expected: [0, 0, 0]
      },
      {
        tag: "first-partial",
        volume: 10,
        expected: [0.3, 0, 0]
      },
      {
        tag: "first-full",
        volume: 100 / 3,
        expected: [1, 0, 0]
      },
      {
        tag: "second-partial",
        volume: 50,
        expected: [1, 0.5, 0]
      },
      {
        tag: "second-full",
        volume: 200 / 3,
        expected: [1, 1, 0]
      },
      {
        tag: "third-partial",
        volume: 90,
        expected: [1, 1, 0.7]
      },
      {
        tag: "full",
        volume: 100,
        expected: [1, 1, 1]
      },
      {
        tag: "overamplified",
        volume: 150,
        expected: [1, 1, 1]
      },
      {
        tag: "not-a-number",
        volume: NaN,
        expected: [0, 0, 0]
      }
    ];
  }

  function test_progression(data) {
    const item = icon({
      volumePercent: data.volume
    });
    for (let i = 0; i < 3; i++)
      fuzzyCompare(findChild(item, "wave" + i).opacity, data.expected[i], 0.00001);
    verify(!findChild(item, "muteCross").visible);
  }

  function test_continuous_updates_and_mute() {
    const item = icon();
    for (let volume = 0; volume <= 100; volume++) {
      item.volumePercent = volume;
      let total = 0;
      for (let i = 0; i < 3; i++)
        total += findChild(item, "wave" + i).opacity;
      fuzzyCompare(total, volume * 3 / 100, 0.00001);
    }
    item.muted = true;
    verify(findChild(item, "muteCross").visible);
    for (const volume of [100, 50, 0, -10, 150]) {
      item.volumePercent = volume;
      for (let i = 0; i < 3; i++)
        compare(findChild(item, "wave" + i).opacity, 0);
    }
    item.volumePercent = 50;
    item.muted = false;
    verify(!findChild(item, "muteCross").visible);
    compare(findChild(item, "wave1").opacity, 0.5);
  }

  function test_layout_invariant() {
    const item = icon();
    compare(item.width, 24);
    compare(item.height, 24);
    const row = createTemporaryObject(rowComponent, tests);
    verify(row !== null);
    const sized = findChild(row, "icon");
    const label = findChild(row, "label");
    tryCompare(label, "x", 32);
    const rowWidth = row.width;
    for (const volume of [-10, 0, 10, 50, 100, 150]) {
      for (const muted of [false, true]) {
        for (const target of [item, sized]) {
          target.volumePercent = volume;
          target.muted = muted;
          compare(target.implicitWidth, 24);
          compare(target.implicitHeight, 24);
        }
        compare(item.width, 24);
        compare(item.height, 24);
        compare(sized.width, 20);
        compare(sized.height, 20);
        compare(label.x, 32);
        compare(row.width, rowWidth);
      }
    }
  }

  function snapshot(item) {
    verify(waitForRendering(item));
    return grabImage(item); // In-memory only; no image files.
  }

  function test_shapes_render() {
    const item = icon({
      width: 96,
      height: 96
    });
    let image = snapshot(item);
    verify(image.red(32, 48) > 240, "The fixed speaker renders at zero");
    for (const x of [56, 72, 88])
      compare(image.red(x, 48), 0);

    // The midpoint of each arc brightens continuously, not just its QML property.
    for (let i = 0; i < 3; i++) {
      const x = 56 + i * 16;
      item.volumePercent = (i + 0.5) * 100 / 3;
      image = snapshot(item);
      verify(image.red(x, 48) > 90 && image.red(x, 48) < 180, "Half-lit arc " + i);
      item.volumePercent = (i + 1) * 100 / 3;
      image = snapshot(item);
      verify(image.red(x, 48) > 240, "Fully lit arc " + i);
      verify(image.red(32, 48) > 240, "Speaker stays unchanged");
    }

    item.muted = true;
    image = snapshot(item);
    verify(image.red(68, 48) > 240, "Mute cross renders");
    // Sample the middle arc away from the cross's antialiased edge.
    for (const point of [[56, 48], [70, 36], [88, 48]])
      compare(image.red(point[0], point[1]), 0);
    verify(image.red(32, 48) > 240);

    item.foreground = "red";
    image = snapshot(item);
    verify(image.red(32, 48) > 240);
    compare(image.green(32, 48), 0);
    compare(image.blue(32, 48), 0);
  }
}
