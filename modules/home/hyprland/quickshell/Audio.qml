import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Row {
  id: root
  spacing: Theme.spacing

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource

  // Without a tracker the nodes are unbound and their volume/muted values are
  // silently invalid rather than merely stale.
  PwObjectTracker {
    objects: [root.sink, root.source]
  }

  function percent(node: var): int {
    return Math.round((node?.audio?.volume ?? 0) * 100);
  }

  function adjust(node: var, steps: int) {
    if (!node?.audio)
      return;
    node.audio.volume = Math.max(0, Math.min(1, node.audio.volume + steps * Theme.volumeStep / 100));
  }

  BarPill {
    id: sinkPill

    readonly property int volume: root.percent(root.sink)
    readonly property bool bluetooth: (root.sink?.properties?.["device.api"] ?? "") === "bluez5"

    // Waybar picked the headphone glyph off the active port; approximate it
    // from the node description, which is what the port name feeds into.
    readonly property bool headphones: /head(phone|set)/i.test(root.sink?.description ?? "")

    readonly property string levelIcon: {
      if (sinkPill.headphones)
        return Icons.headphones;
      const levels = Icons.volumeLevels;
      return levels[Math.min(Math.floor(sinkPill.volume * levels.length / 100), levels.length - 1)];
    }

    visible: root.sink !== null
    // Waybar's format / format-bluetooth / format-muted, spacing included.
    text: {
      if (root.sink?.audio?.muted)
        return ` ${sinkPill.volume}% ${Icons.volumeMuted} `;
      if (sinkPill.bluetooth)
        return ` ${sinkPill.volume}% ${sinkPill.levelIcon}  ${Icons.headphones}  `;
      return ` ${sinkPill.volume}% ${sinkPill.levelIcon} `;
    }
    tooltipText: root.sink?.description ?? ""

    onClicked: Quickshell.execDetached(["pavucontrol"])
    onRightClicked: {
      if (root.sink?.audio)
        root.sink.audio.muted = !root.sink.audio.muted;
    }
    onScrolled: steps => root.adjust(root.sink, steps)
  }

  BarPill {
    id: sourcePill

    readonly property int volume: root.percent(root.source)

    visible: root.source !== null
    text: root.source?.audio?.muted ? ` ${sourcePill.volume}% ${Icons.micMuted}  ` : ` ${sourcePill.volume}% ${Icons.micOn} `
    tooltipText: root.source?.description ?? ""

    onClicked: Quickshell.execDetached(["pavucontrol", "-t", "4"])
    onRightClicked: {
      if (root.source?.audio)
        root.source.audio.muted = !root.source.audio.muted;
    }
    onScrolled: steps => root.adjust(root.source, steps)
  }
}
