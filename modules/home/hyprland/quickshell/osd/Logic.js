// The typed IPC method admits only brightness, never audio control.
function brightnessEvent(screen, value, message) {
  if (typeof screen !== "string" || typeof message !== "string")
    throw new Error("Invalid brightness OSD fields");
  if (!Number.isInteger(value) || !((value >= 0 && value <= 100 && message === "") || (value === -1 && message !== "")))
    throw new Error("Invalid brightness value/message");
  return {kind: value === -1 ? "brightness-error" : "brightness", screen: screen, value: value, text: message};
}

function microphoneEvent(output) {
  const match = /^Volume: ([0-9]+(?:\.[0-9]+)?)( \[MUTED\])?$/.exec(output.trim());
  if (!match || !Number.isFinite(Number(match[1])))
    throw new Error("Invalid wpctl volume response");
  return {kind: "microphone", value: Math.round(Number(match[1]) * 100), muted: !!match[2], text: ""};
}

function screenName(screens, requested, focused) {
  return screens.find(screen => screen.name === requested)?.name
      ?? screens.find(screen => screen.name === focused)?.name
      ?? screens[0]?.name ?? "";
}

function audioReady(node) {
  return !!(node?.ready && node.audio && node.name !== "auto_null");
}

function outputKey(node) {
  return audioReady(node) ? String(node.id) + ":" + node.name : "unavailable";
}

// Device identity is independent of volume access: virtual sources may have
// no .audio. Never mistake a sink (including the dummy output) for an input.
function sourceReady(node, sink) {
  return !!(node?.ready && Number.isInteger(node.id) && node.id > 0
      && node.name && node.name !== "auto_null" && !node.isSink
      && node.id !== sink?.id);
}

function inputKey(node, sink) {
  return sourceReady(node, sink) ? String(node.id) + ":" + node.name : "unavailable";
}
