import QtQuick

// Pinned-open, first section of the panel (§9.5/§9.9/§12 stage 2, stage 6):
// device volume/mute and default-device selection via Quickshell's own
// PipeWire service, plus — stage 6 — the `audio-mode` latency tier and the
// iD4 input-monitor rows. The monitor rows are the actual fix for the
// original complaint: with headphones plugged into the iD4, there was
// previously no way to stop your own mic being piped into them.
ControlCenterSection {
  id: root

  glyph: AudioState.sinkIcon(AudioState.sink)
  title: "Audio"
  // Collapsible, but open by default and independent of the
  // VPN/Bluetooth/Network accordion below — those are mutually exclusive
  // because any one of them can be tall; Audio is the section you glance at
  // most, so collapsing it should be a deliberate act rather than a side
  // effect of opening something else. Its state persists across panel opens,
  // the same way `expandedSection` does.
  collapsible: true
  expanded: ControlCenter.audioExpanded
  onHeaderClicked: ControlCenter.audioExpanded = !ControlCenter.audioExpanded

  // The picker carries its own "Output"/"Input" label and sits above its
  // slider, rather than a separate heading line sitting above both. Two
  // fewer lines, and the name is attached to the control instead of floating
  // over a slider that could belong to either half.
  ControlCenterPicker {
    width: parent.width
    pickerId: "audio-output"
    title: "Output"
    label: AudioState.sink?.description ?? "No output device"
    currentId: AudioState.sink?.id ?? -1
    options: AudioState.sinks.map(node => ({
          id: node.id,
          label: node.description
        }))

    onSelected: id => {
      const node = AudioState.sinks.find(candidate => candidate.id === id);
      if (node)
        AudioState.setDefaultSink(node);
    }
  }

  ControlCenterSlider {
    width: parent.width
    glyph: AudioState.sinkIcon(AudioState.sink)
    value: AudioState.sink?.audio?.volume ?? 0
    muted: AudioState.sink?.audio?.muted ?? false
    enabled: AudioState.sink !== null

    onMuteToggled: AudioState.toggleMute(AudioState.sink)
    onMoved: value => AudioState.setVolume(AudioState.sink, value)
  }

  ControlCenterPicker {
    width: parent.width
    pickerId: "audio-input"
    title: "Input"
    label: AudioState.source?.description ?? "No input device"
    currentId: AudioState.source?.id ?? -1
    options: AudioState.sources.map(node => ({
          id: node.id,
          label: node.description
        }))

    onSelected: id => {
      const node = AudioState.sources.find(candidate => candidate.id === id);
      if (node)
        AudioState.setDefaultSource(node);
    }
  }

  ControlCenterSlider {
    width: parent.width
    glyph: (AudioState.source?.audio?.muted ?? false) ? Icons.micMuted : Icons.micOn
    value: AudioState.source?.audio?.volume ?? 0
    muted: AudioState.source?.audio?.muted ?? false
    enabled: AudioState.source !== null

    onMuteToggled: AudioState.toggleMute(AudioState.source)
    onMoved: value => AudioState.setVolume(AudioState.source, value)
  }

  // Latency tier (§9.5 rework). Hidden entirely on a host with no
  // `mine.audio` wired up (I5): AUDIO_MODE_BIN/AUDIO_MODE_CONFIG both arrive
  // empty there and AudioState.available reflects it, so this never renders
  // controls that can never do anything real.
  //
  // Reworked per direct user feedback that the previous index-snapped
  // Custom slider (reachable only after picking a "Custom" segment) was
  // "extremely awkward". The rate selector and the quantum slider are now
  // always visible and always show the current effective pair, whichever
  // tier produced it. There is no "enter Custom" step any more: Custom is
  // what `audio-mode status` reports whenever the live pair matches no
  // declared tier (§5.3), so dragging the slider or picking a rate just
  // applies a pair and lets the next poll report whatever that resolves to
  // — including lighting a declared tier's segment back up for free if the
  // drag happens to land exactly on one.
  Column {
    id: latencyColumn
    width: parent.width
    spacing: 4
    visible: AudioState.available

    // Effective daemon-reported window the quantum slider must span (§5.2).
    // Falls back to the descriptor's own extremes only while the daemon has
    // never reported a real window at all — every control below already
    // disables itself in that state (`AudioState.modeAvailable` is false),
    // this only keeps the log2 maths finite while it does.
    readonly property int minQuantum: AudioState.currentMinQuantum ?? (AudioState.quantums[0] ?? 32)
    readonly property int maxQuantum: AudioState.currentMaxQuantum ?? (AudioState.quantums[AudioState.quantums.length - 1] ?? 2048)

    // Powers of two inside [minQuantum, maxQuantum] — the slider's magnetic
    // detents. Computed from the daemon's own live window rather than read
    // off `mine.audio.quantums` directly: that list is UI seed data (§7),
    // this is the daemon's live answer, and the two are not guaranteed to
    // be the same set.
    readonly property var detents: {
      const result = [];
      if (latencyColumn.maxQuantum < latencyColumn.minQuantum)
        return result;
      let value = Math.pow(2, Math.ceil(Math.log2(Math.max(1, latencyColumn.minQuantum))));
      while (value <= latencyColumn.maxQuantum) {
        result.push(value);
        value *= 2;
      }
      return result;
    }

    // log2(quantum) position, 0..1, across [minQuantum, maxQuantum]. Log2
    // rather than linear: 32..2048 is six-plus octaves, and a linear track
    // gives the bottom octave (32->64) about 1.5% of the width while the top
    // octave alone (1024->2048) gets as much room as everything below it
    // combined — almost certainly the other reason the old slider felt
    // awkward. Log2 gives every octave equal width, so doubling the quantum
    // always looks like the same size step, at either end of the range.
    function quantumToFraction(quantum: real): real {
      const lo = Math.log2(latencyColumn.minQuantum);
      const hi = Math.log2(latencyColumn.maxQuantum);
      if (hi <= lo)
        return 0;
      const clampedQuantum = Math.max(latencyColumn.minQuantum, Math.min(latencyColumn.maxQuantum, quantum));
      return (Math.log2(clampedQuantum) - lo) / (hi - lo);
    }

    function fractionToQuantum(fraction: real): int {
      const lo = Math.log2(latencyColumn.minQuantum);
      const hi = Math.log2(latencyColumn.maxQuantum);
      const clamped = Math.max(0, Math.min(1, fraction));
      return Math.round(Math.pow(2, lo + clamped * (hi - lo)));
    }

    // Magnetic capture width around each detent, expressed as a fraction of
    // one octave rather than a fixed pixel count — because the mapping
    // above is log2, every octave occupies an equal fraction of the track
    // regardless of how many octaves the daemon's live window happens to
    // span. 15% of an octave on either side of a detent is wide enough to
    // reliably land on it despite normal mouse imprecision (on this panel's
    // ~230px track over six octaves, roughly +/-6px out of ~38px per octave
    // — comparable to the handle's own radius) while leaving the remaining
    // 70% of each octave fully continuous: most of the track is never
    // snapped at all, only the immediate neighbourhood of a power of two.
    readonly property real detentCaptureFraction: 0.15

    function snapToDetent(quantum: int): int {
      if (latencyColumn.detents.length === 0)
        return quantum;
      const targetFraction = latencyColumn.quantumToFraction(quantum);
      const octaveCount = Math.max(1, Math.log2(latencyColumn.maxQuantum) - Math.log2(latencyColumn.minQuantum));
      const captureWidth = latencyColumn.detentCaptureFraction / octaveCount;
      let nearest = quantum;
      let bestDiff = Infinity;
      for (let i = 0; i < latencyColumn.detents.length; i++) {
        const detent = latencyColumn.detents[i];
        const diff = Math.abs(targetFraction - latencyColumn.quantumToFraction(detent));
        if (diff < bestDiff) {
          bestDiff = diff;
          nearest = detent;
        }
      }
      return bestDiff <= captureWidth ? nearest : quantum;
    }

    // In-flight slider state: `dragging` is true from the moment the
    // pointer is pressed on the track until the value is applied on
    // release, and `liveQuantum` is the continuous (possibly
    // detent-snapped) value the pointer is currently over. Both are plain
    // local state, not written to AudioState, because nothing is applied
    // until release — see quantumSlider.commit() below.
    property bool dragging: false
    property int liveQuantum: 0

    // What every readout in this block displays: the in-flight value while
    // dragging, otherwise whatever AudioState last confirmed the daemon
    // accepted. This is what makes the number and the meter track the drag
    // live, then drop back to the applied value the instant the pointer is
    // released — before the next poll has even landed — rather than
    // optimistically pretending the drag's value already took effect.
    readonly property int displayQuantum: latencyColumn.dragging ? latencyColumn.liveQuantum : (AudioState.currentQuantum ?? latencyColumn.minQuantum)
    readonly property var displayRate: AudioState.currentRate ?? (AudioState.rates[0] ?? 48000)
    readonly property var displayPeriodMs: (latencyColumn.displayRate ?? 0) ? (latencyColumn.displayQuantum / latencyColumn.displayRate * 1000) : null

    // "48 kHz", "44.1 kHz" — trailing ".0" stripped so a whole-number rate
    // does not show a spurious decimal.
    function rateLabel(rate: int): string {
      const khz = (rate / 1000).toFixed(1).replace(/\.0$/, "");
      return `${khz} kHz`;
    }

    ControlCenterGroup {
      width: parent.width
      text: "Sampling"
      expanded: ControlCenter.samplingExpanded
      onToggled: ControlCenter.samplingExpanded = !ControlCenter.samplingExpanded


      // The numbers stay visible without a tooltip (§9.5), and update live
      // while dragging via `displayQuantum`/`displayRate`/`displayPeriodMs`.
      // Labelled "dynamic default" whenever nothing is forced (Normal): that
      // pair is the daemon's own moving target, not a value the user picked,
      // so pretending a fixed number like 1024 was "chosen" would be
      // dishonest (§4/§9.5's Normal-has-no-quantum requirement).
      Text {
        text: {
          if (!AudioState.modeAvailable)
            return "PipeWire is not running";
          const framesRate = `${latencyColumn.displayQuantum} frames @ ${latencyColumn.displayRate} Hz`;
          const ms = latencyColumn.displayPeriodMs !== null ? `${latencyColumn.displayPeriodMs.toFixed(2)} ms` : "—";
          const dynamic = (!latencyColumn.dragging && !AudioState.currentForced) ? " (dynamic default)" : "";
          return `${framesRate}${dynamic} · ${ms}`;
        }
        color: Theme.foregroundDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 4
      }

      // Declared tiers only — no "Custom" entry. Custom is a result of the
      // rate/quantum controls below, never a state to click into, so there is
      // nothing for a fourth segment to do; when the live pair matches none
      // of these, none of them lights up, which is the honest answer to
      // "which preset is this" when the answer is "none of them".
      ControlCenterSegments {
        width: parent.width
        options: AudioState.latencyModes.map(mode => ({
                id: mode.id,
                label: mode.label
              }))
        currentId: AudioState.currentModeId
        // Disabled for the whole round trip of a setter, not just until its
        // own Process exits — see AudioState.settingLatency.
        enabled: AudioState.modeAvailable && !AudioState.settingLatency

        onSelected: id => AudioState.setLatencyMode(id)
      }

      // Rate + quantum controls: always visible, always showing the current
      // effective pair. They used to be revealed only after picking a
      // "Custom" segment that no longer exists (§9.5 rework). Changing either
      // applies a forced pair through `AudioState.setCustomLatency`, which is
      // what naturally reclassifies the tier as Custom on the next poll
      // (`audio-mode status` resolves by exact pair match, §5.3) with no
      // separate "enter Custom" step required.
      Column {
        width: parent.width
        spacing: 6

        ControlCenterSegments {
          width: parent.width
          options: AudioState.rates.map(rate => ({
                  id: String(rate),
                  label: latencyColumn.rateLabel(rate)
                }))
          currentId: String(latencyColumn.displayRate ?? "")
          enabled: AudioState.modeAvailable && !AudioState.settingLatency

          onSelected: id => AudioState.setCustomLatency(AudioState.currentQuantum ?? latencyColumn.minQuantum, Number(id))
        }

        // Quantum slider: continuous across the daemon's live
        // clock.min-quantum/max-quantum window rather than snapped to
        // `mine.audio.quantums`' seven stops — an index-snapped slider could
        // only ever reach those seven values, which is almost certainly why
        // it felt awkward. The powers of two in that window remain magnetic
        // detents (see `latencyColumn.snapToDetent`/`detentCaptureFraction`
        // above) so a drag near one still lands on it exactly, but every
        // value in between stays reachable.
        Item {
          id: quantumSlider
          width: parent.width
          implicitHeight: Theme.sliderHeight
          height: implicitHeight
          enabled: AudioState.modeAvailable && !AudioState.settingLatency
          opacity: quantumSlider.enabled ? 1 : 0.4

          // Applies the given quantum through the same setter/re-poll path
          // every other latency control uses, then clears `dragging` so
          // `displayQuantum` immediately drops back to `AudioState
          // .currentQuantum` (still the pre-drag value until the poll lands)
          // rather than optimistically assuming the drag's value already
          // took effect — apply-then-verify (§5.4), not apply-then-assume.
          function commit(quantum: int): void {
            latencyColumn.dragging = false;
            AudioState.setCustomLatency(quantum, latencyColumn.displayRate);
          }

          // Live, in-flight position: called on press and on every drag
          // step, never on release. Nothing is applied here — this only
          // moves the handle and updates `latencyColumn.liveQuantum` so the
          // readout and the meter track the drag as it happens, before
          // anything is actually applied.
          function seek(mouseX: real): void {
            if (track.width <= 0)
              return;
            const fraction = Math.max(0, Math.min(1, mouseX / track.width));
            latencyColumn.liveQuantum = latencyColumn.snapToDetent(latencyColumn.fractionToQuantum(fraction));
          }

          Row {
            anchors.fill: parent
            spacing: Theme.rowSpacing

            Item {
              id: track
              width: quantumSlider.width - frameLabel.width - Theme.rowSpacing
              height: parent.height
              anchors.verticalCenter: parent.verticalCenter

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Theme.sliderTrackHeight
                radius: height / 2
                color: Theme.sliderTrack
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: track.width * latencyColumn.quantumToFraction(latencyColumn.displayQuantum)
                height: Theme.sliderTrackHeight
                radius: height / 2
                color: Theme.sliderFill
              }

              // Detent tick marks — purely informational, showing where a
              // drag magnetically snaps (`latencyColumn.detentCaptureFraction`
              // above explains the capture width). The track between ticks
              // stays fully continuous.
              Repeater {
                model: latencyColumn.detents

                Rectangle {
                  id: detentTick
                  required property var modelData

                  width: 2
                  height: Theme.sliderTrackHeight
                  radius: 1
                  color: Theme.foregroundDim
                  anchors.verticalCenter: parent.verticalCenter
                  x: Math.max(0, Math.min(track.width - width, track.width * latencyColumn.quantumToFraction(detentTick.modelData) - width / 2))
                }
              }

              Rectangle {
                width: Theme.sliderHandleSize
                height: Theme.sliderHandleSize
                radius: width / 2
                color: Theme.sliderHandle
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(track.width - width, track.width * latencyColumn.quantumToFraction(latencyColumn.displayQuantum) - width / 2))
              }

              MouseArea {
                anchors.fill: parent
                // Load-bearing, same reasoning as ControlCenterSlider's own
                // track MouseArea (§9.9): without this a diagonal drag
                // starting here is stolen by the panel's Flickable.
                preventStealing: true

                onPressed: mouse => {
                  latencyColumn.dragging = true;
                  quantumSlider.seek(mouse.x);
                }
                onPositionChanged: mouse => {
                  if (pressed)
                    quantumSlider.seek(mouse.x);
                }
                // Covers both a real drag and a plain click-to-seek: a click
                // with no movement still ran `seek()` once on press, so
                // `liveQuantum` already holds the clicked position by the
                // time this fires. Applied exactly once, here, on release —
                // never mid-drag.
                onReleased: quantumSlider.commit(latencyColumn.liveQuantum)
                onCanceled: latencyColumn.dragging = false
              }
            }

            Text {
              id: frameLabel
              width: 84
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              text: `${latencyColumn.displayQuantum} frames`
              color: Theme.foregroundDim
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize - 2
            }
          }
        }
      }
    }
  }

  // Monitor rows (§9.5, stage 6) — one per iD4 input-monitor loopback. This
  // is the actual off switch the whole stage exists for: on/off is mute,
  // never volume-to-zero (§2.2), since WirePlumber persists mute across a
  // PipeWire restart for free and unmuting restores whatever level was set.
  //
  // The heading carries an explanation because "Mic" and "DI" alone do not
  // say what the control does — the rows look like another pair of input
  // volumes rather than a routing switch that decides whether you hear
  // yourself in the headphones.
  ControlCenterGroup {
    width: parent.width
    visible: AudioState.inputMonitors.length > 0
    text: "Monitoring"
    expanded: ControlCenter.monitoringExpanded
    onToggled: ControlCenter.monitoringExpanded = !ControlCenter.monitoringExpanded

    Repeater {
      model: AudioState.inputMonitors

      Column {
        id: monitorRow

        required property var modelData
        // Bound, not cached (I6): resolved live against Pipewire.nodes.values
        // by node.name every time this binding re-evaluates, so a replug or a
        // PipeWire restart is picked up automatically rather than needing the
        // panel reopened.
        readonly property var node: AudioState.monitorNode(monitorRow.modelData.id)

        width: parent.width
        // Label row and its slider are two halves of one control, so they sit
        // closer to each other than the section's own `spacing` puts successive
        // monitors — that difference is what makes the pairs read as pairs.
        spacing: 6

        // Label + mute toggle share one row; the slider gets its own full-width
        // row below instead of squeezing into this row's trailing slot next to
        // the label column — that left it a ~28px track, nowhere near usable.
        // A full `width: parent.width` row gives it the same room the output/
        // input sliders above already get.
        ControlCenterRow {
          width: parent.width
          label: monitorRow.modelData.label
          // I5: an unplugged iD4 dims the row and says so, rather than making
          // it vanish (reads as a broken feature) or throwing. The wording
          // names the usual cause: the loopbacks are created by PipeWire at
          // startup, so a freshly-switched config does not have them until
          // PipeWire restarts.
          sublabel: monitorRow.node ? "" : "not available — restart PipeWire or reconnect the device"
          dimmed: monitorRow.node === null
          enabled: monitorRow.node !== null

          ControlCenterToggle {
            checked: !(monitorRow.node?.audio?.muted ?? true)
            onToggled: AudioState.toggleMute(monitorRow.node)
          }
        }

        ControlCenterSlider {
          width: parent.width
          value: monitorRow.node?.audio?.volume ?? 0
          muted: monitorRow.node?.audio?.muted ?? true
          enabled: monitorRow.node !== null

          onMuteToggled: AudioState.toggleMute(monitorRow.node)
          onMoved: value => AudioState.setVolume(monitorRow.node, value)
        }
      }
    }
  }

  // EasyEffects preset selector (§9.5). Hidden entirely on a host with no
  // EasyEffects service wired up (I5): `EASYEFFECTS_PRESET` arrives empty
  // there and `EffectsState.available` reflects it, the same host-wiring
  // gate `AudioState.available`/`VpnState.available` already use.
  ControlCenterGroup {
    width: parent.width
    visible: EffectsState.available
    text: "Effects"
    expanded: ControlCenter.effectsExpanded
    onToggled: ControlCenter.effectsExpanded = !ControlCenter.effectsExpanded

    // A preset type with no presets must not render an empty picker (I5) —
    // this machine's own "output" has zero presets today, so that path is
    // the live case here, not a hypothetical.
    ControlCenterPicker {
      width: parent.width
      visible: EffectsState.inputPresets.length > 0
      pickerId: "effects-input"
      title: "Input"
      label: EffectsState.inputCurrent ?? "No preset loaded"
      // Preset names are strings, not ids with a separate label — the name
      // is used as its own id, matching how the picker's `currentId` is
      // compared against `options[].id` below.
      currentId: EffectsState.inputCurrent
      options: EffectsState.inputPresets.map(name => ({
              id: name,
              label: name
            }))

      onSelected: name => EffectsState.load("input", name)
    }

    ControlCenterPicker {
      width: parent.width
      visible: EffectsState.outputPresets.length > 0
      pickerId: "effects-output"
      title: "Output"
      label: EffectsState.outputCurrent ?? "No preset loaded"
      currentId: EffectsState.outputCurrent
      options: EffectsState.outputPresets.map(name => ({
              id: name,
              label: name
            }))

      onSelected: name => EffectsState.load("output", name)
    }
  }
}
