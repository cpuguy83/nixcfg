pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Native half of the audio section (.copilot/plans/control-center.md §9.5):
// default sink/source, the pickable device lists, the single tracker that
// makes every node's `.audio`/`.properties` usable (I3), and — stage 6 — the
// `audio-mode` latency-tier process plus the iD4 input-monitor descriptor.
Singleton {
  id: root

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource

  // Bindings over `.values`, never cached: PwNode's identity fields
  // (type/isSink/isStream/...) are `isPropertyConstant: true` and register no
  // dependency of their own (I6) — what actually changes over time is which
  // nodes exist at all, and that is exactly what `.values` notifies on.
  //
  // Filtered on `PwNodeType` rather than `isSink`/`isStream`. The obvious
  // `!isSink && !isStream` reads as "a source", but PipeWire's graph is not
  // only audio: that predicate also matched the webcam (`Video/Source`), both
  // MIDI bridges, EasyEffects' internal Spectrum/Level-Meter filter nodes, and
  // the `Dummy-Driver`/`Freewheel-Driver` pseudo-nodes. Three of those carry no
  // `node.description` at all, so they rendered as blank rows at the top of the
  // input picker. `PwNodeType.AudioSource` is confirmed `Audio | Source` by
  // reading the constants back at runtime (9 === 1 | 8, matching `AudioSink`
  // = 17 = `Audio | Sink` the same way), so the bitwise-AND-equality check
  // below is exactly "has both bits", not a distinct-value comparison that a
  // composite flag would silently fail; `Stream` is excluded so per-app
  // capture streams (and our own monitor loopbacks) never appear as devices.
  //
  // `PwNodeType` itself only recognises PipeWire's canonical `media.class`
  // strings (`Audio/Sink`, `Audio/Source`, ...) and reads as `Untracked` (0)
  // for anything else. EasyEffects' virtual source tags itself
  // `Audio/Source/Virtual` rather than the plain string — confirmed via
  // `pw-cli info` against the live node — so it reads `type === 0` and the
  // bitwise check alone drops it, even though it is a real capture device and
  // the one other EasyEffects node (its sink) is unaffected because that one
  // happens to use the plain `Audio/Sink`. `classHint` is the fallback for
  // exactly that gap: nodes `PwNodeType` left `Untracked` are still admitted
  // if their own `media.class` property starts with the expected prefix.
  function isAudio(node: var, kind: int, classHint: string): bool {
    if ((node.type & kind) === kind && (node.type & PwNodeType.Stream) === 0)
      return true;
    const mediaClass = node.properties?.["media.class"] ?? "";
    return node.type === PwNodeType.Untracked && (mediaClass === classHint || mediaClass.startsWith(`${classHint}/`));
  }

  readonly property var sinks: Pipewire.nodes.values.filter(node => root.isAudio(node, PwNodeType.AudioSink, "Audio/Sink"))
  readonly property var sources: Pipewire.nodes.values.filter(node => root.isAudio(node, PwNodeType.AudioSource, "Audio/Source"))

  // --- Latency tier + iD4 input monitors (stage 6) ---------------------

  // Nix owns both paths; either arrives empty on a host with no
  // `mine.audio.enable` wired up, in which case the whole latency/monitor UI
  // degrades to "not available" (I5) instead of polling a binary or reading
  // a descriptor that does not exist.
  readonly property string bin: Quickshell.env("AUDIO_MODE_BIN") ?? ""
  readonly property bool available: root.bin !== ""

  readonly property string configPath: Quickshell.env("AUDIO_MODE_CONFIG") ?? ""

  property var latencyModes: [] // [{ id, label, quantum, rate }, ...] from the descriptor
  property var inputMonitors: [] // [{ id, label, description, node }, ...] from the descriptor
  property var rates: [] // [44100, 48000, ...] -- Custom picker's rate choices (§9.5)
  property var quantums: [] // [32, 64, ...] -- Custom picker's quantum slider stops

  // One-time, blocking read (component completion, well before a human can
  // click anything) of the descriptor Nix generates from the same
  // `mine.audio.latencyModes`/`inputMonitors` that feed the CLI (§7) — never
  // re-read afterwards, since the descriptor is static for the process
  // lifetime. An empty `path` (AUDIO_MODE_CONFIG unset) is the documented
  // "nothing to load" state, not an error.
  FileView {
    id: descriptorFile

    path: root.configPath
    blockLoading: true

    onLoaded: {
      try {
        const parsed = JSON.parse(descriptorFile.text());
        root.latencyModes = parsed.latencyModes ?? [];
        root.inputMonitors = parsed.inputMonitors ?? [];
        root.rates = parsed.rates ?? [];
        root.quantums = parsed.quantums ?? [];
      } catch (error) {
        root.latencyModes = [];
        root.inputMonitors = [];
        root.rates = [];
        root.quantums = [];
      }
    }

    onLoadFailed: error => {
      root.latencyModes = [];
      root.inputMonitors = [];
      root.rates = [];
      root.quantums = [];
    }
  }

  // audio-mode status fields (§5.2), refreshed every 5s and immediately after
  // setLatencyMode()'s own Process exits. Defaults mirror the CLI's own
  // "unavailable" payload, so an unpolled panel and a PipeWire-down panel
  // read identically.
  property bool modeAvailable: false
  property string currentModeId: "unknown"
  property string currentModeLabel: "Unavailable"
  property var currentQuantum: null
  property var currentRate: null
  property var currentLatencyMs: null
  // Whether the effective (quantum, rate) above is a forced pair or the
  // daemon's own dynamic default -- Normal is unforced, so its slider
  // position must read as "dynamic", not as a value the user chose (§9.5).
  property bool currentForced: false
  // The daemon's *dynamic* default, always reported regardless of which tier
  // is active -- needed to place Normal's marker on the latency meter (§9.5),
  // since Normal's declared (quantum, rate) is the literal (0, 0) "do not
  // force" sentinel (§4), not a real period.
  property var currentDefaultQuantum: null
  property var currentDefaultRate: null
  // The daemon's *live* `clock.min-quantum`/`clock.max-quantum` window
  // (§5.2) -- the quantum slider's actual bounds. Never hardcode 32/2048
  // from `mine.audio.quantums`; that list is UI seed data, this is the
  // daemon's own answer and can differ from it.
  property var currentMinQuantum: null
  property var currentMaxQuantum: null

  // True for the lifetime of a `set` call, cleared only once the poll it
  // triggers actually lands — the same "optimistic flag, cleared by the next
  // poll" shape `VpnState.pending` uses — so the segmented control disables
  // itself for the whole round trip rather than flickering re-enabled a beat
  // before the new mode is visible.
  property bool settingLatency: false

  // Quickshell's Process ignores a `running = true` write while the process
  // is already running — it does not queue. Both `watcher` (below, on every
  // metadata change it observes) and `latencySetter` (on its own exit) call
  // requestPoll(), and either can land while the other's poll is already in
  // flight; without this, that second request would be silently dropped and
  // whatever poll was already running would land instead — for the setter
  // case, clearing `settingLatency` on a pre-change reading and re-enabling
  // the control on stale data. `pollAgain` is what makes a request durable:
  // honoured by `modePoll`'s own `onExited` the moment it is free to run
  // again, rather than being lost.
  property bool pollAgain: false

  function requestPoll() {
    if (!root.available)
      return;
    if (modePoll.running)
      root.pollAgain = true;
    else
      modePoll.running = true;
  }

  // Change notifier, not a poller: `audio-mode watch` (the CLI's own `watch`
  // verb, so this needs neither `pw-metadata` on PATH nor its store path
  // threaded separately — AUDIO_MODE_BIN already covers it) `exec`s
  // `pw-metadata -n settings -m`, which prints the "settings" object's
  // current key/value dump once on start and then one line per change,
  // running until killed. This process never parses metadata into a mode
  // itself — mode resolution, labels, `latencyMs` and min/max all stay in
  // `audio-mode status` (§5.2/§5.3, `modePoll` below), the one place that
  // does it; the watcher only decides *when* to re-run `status`.
  Process {
    id: watcher
    running: root.available
    command: [root.bin, "watch"]

    // The startup dump and every change line both carry the object's own
    // key names (`clock.rate`, `clock.force-quantum`, `log.level`, ...); the
    // "clock." guard is what keeps an unrelated settings key (`log.level`)
    // from triggering a needless re-poll. Matching every `clock.*` key
    // rather than only the two `force-*` ones is deliberate: `set-custom`'s
    // own min/max window and the effective quantum/rate the tooltip shows
    // both come from `clock.min-quantum`/`clock.max-quantum`/`clock.quantum`/
    // `clock.rate` too, so a change there is exactly as poll-worthy.
    stdout: SplitParser {
      splitMarker: "\n"

      onRead: data => {
        if (data.includes("clock."))
          root.requestPoll();
      }
    }

    // `pw-metadata -m` exits the moment the PipeWire daemon it is attached
    // to goes away — restart, crash, logout — confirmed empirically running
    // it against a live `systemctl --user restart pipewire`. Restarting is
    // delayed rather than immediate: reconnecting instantly against a daemon
    // that will not be back for a few seconds would busy-loop forking a new
    // process every time the previous one immediately fails to connect.
    // `restartTimer` is what turns that into a periodic retry instead.
    onExited: restartTimer.restart()
  }

  Timer {
    id: restartTimer
    interval: 3000

    onTriggered: {
      if (root.available)
        watcher.running = true;
    }
  }

  Process {
    id: modePoll
    command: [root.bin, "status"]

    onExited: {
      if (root.pollAgain) {
        root.pollAgain = false;
        modePoll.running = true;
      }
    }

    stdout: StdioCollector {
      id: modeOutput

      onStreamFinished: {
        try {
          const parsed = JSON.parse(modeOutput.text);
          root.modeAvailable = parsed.available ?? false;
          root.currentModeId = parsed.mode ?? "unknown";
          root.currentModeLabel = parsed.label ?? "Unavailable";
          root.currentQuantum = parsed.quantum ?? null;
          root.currentRate = parsed.rate ?? null;
          root.currentLatencyMs = parsed.latencyMs ?? null;
          root.currentForced = parsed.forced ?? false;
          root.currentDefaultQuantum = parsed.defaultQuantum ?? null;
          root.currentDefaultRate = parsed.defaultRate ?? null;
          root.currentMinQuantum = parsed.minQuantum ?? null;
          root.currentMaxQuantum = parsed.maxQuantum ?? null;
        } catch (error) {
          // A broken or partial payload reads as unavailable rather than
          // freezing on stale numbers.
          root.modeAvailable = false;
          root.currentModeId = "unknown";
          root.currentModeLabel = "Unavailable";
          root.currentQuantum = null;
          root.currentRate = null;
          root.currentLatencyMs = null;
          root.currentForced = false;
          root.currentDefaultQuantum = null;
          root.currentDefaultRate = null;
          root.currentMinQuantum = null;
          root.currentMaxQuantum = null;
        }
        root.settingLatency = false;
      }
    }
  }

  // Issues `audio-mode set <id>` as its own Process and re-polls the instant
  // it exits, rather than leaving the segmented control to wait up to the
  // Timer's 5s for the click to visibly land — the same "click, then poll
  // immediately" pattern `VpnState`'s own setters use. A second call is
  // ignored while one is already in flight.
  function setLatencyMode(id: string) {
    if (!root.available || latencySetter.running)
      return;
    root.settingLatency = true;
    latencySetter.command = [root.bin, "set", id];
    latencySetter.running = true;
  }

  // Applies an arbitrary (quantum, rate) pair (§9.5's Custom picker) via
  // `audio-mode set-custom`. Shares `latencySetter` with setLatencyMode()
  // above -- same in-flight guard, same immediate re-poll on exit (including
  // `pollAgain`, so a Timer tick landing mid-call can never drop this
  // request), and the same "verification, not assumption" contract: a
  // rejected pair (outside the daemon's live min/max window, or a rate
  // PipeWire silently discards) surfaces as `currentModeId === "custom"` on
  // the very next poll rather than the UI assuming the click took effect.
  function setCustomLatency(quantum: int, rate: int) {
    if (!root.available || latencySetter.running)
      return;
    root.settingLatency = true;
    latencySetter.command = [root.bin, "set-custom", String(quantum), String(rate)];
    latencySetter.running = true;
  }

  Process {
    id: latencySetter
    onExited: root.requestPoll()
  }

  // Resolves one inputMonitors descriptor entry (by its stable `id`, e.g.
  // "mic") to its live PwNode — never cached, since PwNode's identity fields
  // are `isPropertyConstant` and register no dependency of their own (I6).
  // Reading `Pipewire.nodes.values` here is what makes a binding built on this
  // function re-run as the monitor's loopback node is created (module-loopback
  // starting) or removed (iD4 unplugged, PipeWire restart).
  //
  // Matched by `node.name` first — that is the stable name this repo assigns
  // in `modules/nixos/audio/input-monitors.nix`, and it cannot be changed by
  // editing a display label.
  //
  // Then by `node.description` as a fallback, because `node.name` only becomes
  // the configured value once PipeWire has *restarted* and reloaded the
  // generated drop-in. A `nixos-rebuild switch` does not restart PipeWire —
  // that would cut audio out from under whatever is playing — so between the
  // switch and the next restart the loopbacks are still running under their
  // old PID-derived names (`output.loopback-<pid>-<n>`). Without this fallback
  // the rows sit greyed out for the rest of the session with no indication
  // that anything is wrong beyond "not available", which is exactly what
  // happened in practice.
  //
  // Description is a weaker key (it is a display string, and it is also
  // WirePlumber's persistence key), which is why it is the fallback and not
  // the primary. `capture.props` and `playback.props` share a description, so
  // this deliberately also requires the node be an output stream — the
  // playback side is the one whose mute silences the headphones.
  function monitorNode(id: string): var {
    const monitor = root.inputMonitors.find(entry => entry.id === id);
    if (!monitor)
      return null;

    const nodes = Pipewire.nodes.values;
    return nodes.find(node => node.name === monitor.node) ?? nodes.find(node => node.description === monitor.description && node.isStream && node.isSink) ?? null;
  }

  // Every configured monitor's live node, resolved the same way (I3).
  readonly property var monitorNodes: root.inputMonitors.map(monitor => root.monitorNode(monitor.id)).filter(node => node !== null)

  // An untracked node reports `ready=false`, `volume` 0, `properties` as an
  // *empty* map, and rejects writes outright (I3) — confirmed empirically
  // (headless probe against the live session): `.properties` never resolves
  // no matter how long you wait, only once a `PwObjectTracker` actually
  // references that node. That is exactly why this tracks every node in the
  // graph rather than the curated sink/source/monitor set it used to: the
  // `classHint` fallback in `isAudio()` above needs `.properties` (specifically
  // `media.class`) to classify a node PwNodeType itself left `Untracked`, so a
  // node has to already be tracked *before* `sinks`/`sources` can decide
  // whether it belongs there — a curated "track only what's already known to
  // qualify" list can never break that circle. The cost of tracking
  // everything is negligible in practice: `properties` binds once per node
  // (confirmed via a `propertiesChanged` counter, not a repeating stream),
  // and every one of the non-device nodes this used to exclude (webcam, MIDI
  // bridges, EasyEffects' filter/meter nodes, the Dummy/Freewheel pseudo-nodes)
  // has no `.audio` interface at all, so there is no volume/mute callback
  // stream to subscribe to either.
  PwObjectTracker {
    objects: Pipewire.nodes.values
  }

  // Composite sink glyph, carried over byte-for-byte from the retired
  // `Audio.qml` sink pill: mute wins outright, then a bluetooth sink or a
  // headphone-shaped description collapses to one glyph — the old pill's
  // two-icon bluetooth format has no room on a single bar button (§9.8) —
  // else the volume ramp. Shared so the bar button and the section's own
  // output slider can never drift apart.
  function sinkIcon(node: var): string {
    if (!node)
      return Icons.volumeLevels[0];
    if (node.audio?.muted ?? false)
      return Icons.volumeMuted;

    const bluetooth = (node.properties?.["device.api"] ?? "") === "bluez5";
    const headphones = /head(phone|set)/i.test(node.description ?? "");
    if (bluetooth || headphones)
      return Icons.headphones;

    const levels = Icons.volumeLevels;
    const percent = Math.round((node.audio?.volume ?? 0) * 100);
    return levels[Math.min(Math.floor(percent * levels.length / 100), levels.length - 1)];
  }

  // No-op when the node has no bound `.audio` (unset default, or a node that
  // slipped in ahead of the tracker) — the same guard `Audio.qml` used.
  function toggleMute(node: var) {
    if (node?.audio)
      node.audio.muted = !node.audio.muted;
  }

  function setVolume(node: var, value: real) {
    if (node?.audio)
      node.audio.volume = Math.max(0, Math.min(1, value));
  }

  // Percentage-points per scroll notch, matching the retired pill's `adjust()`.
  function adjustVolume(node: var, steps: int) {
    if (!node?.audio)
      return;
    root.setVolume(node, node.audio.volume + steps * Theme.volumeStep / 100);
  }

  function setDefaultSink(node: var) {
    Pipewire.preferredDefaultAudioSink = node;
  }

  function setDefaultSource(node: var) {
    Pipewire.preferredDefaultAudioSource = node;
  }
}
