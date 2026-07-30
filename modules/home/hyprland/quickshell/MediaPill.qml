import QtQuick
import Quickshell
import Quickshell.Services.Mpris

BarPill {
  id: root

  // Prefer whatever is actually playing; fall back to the first controllable
  // player so a paused track still shows.
  readonly property var player: {
    const players = Mpris.players.values.filter(candidate => candidate.canControl);
    return players.find(candidate => candidate.isPlaying) ?? players[0] ?? null;
  }

  readonly property string title: root.player?.trackTitle ?? ""
  readonly property string artist: root.player?.trackArtist ?? ""

  visible: root.player !== null && root.title !== ""
  // Waybar only appended the status glyph while paused.
  text: root.player?.isPlaying ? ` ${root.title} | ${root.artist} ` : ` ${root.title} | ${root.artist} ${Icons.mediaPaused} `
  tooltipText: root.player?.identity ?? ""

  onClicked: {
    if (root.player?.canTogglePlaying)
      root.player.isPlaying = !root.player.isPlaying;
  }

  onScrolled: steps => {
    if (steps > 0)
      root.player?.next();
    else
      root.player?.previous();
  }
}
