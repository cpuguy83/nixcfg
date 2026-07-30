pragma Singleton

import Quickshell
import Quickshell.Hyprland

// The window set a bar, the switcher or the overview works on, in
// scrolling-layout order. Shared so none of them can disagree about ordering.
Singleton {
  // Reads Hyprland's properties rather than caching them, so a binding that
  // calls this still registers a dependency on the toplevel list and re-runs
  // when windows come and go.
  function forMonitor(monitor) {
    return forWorkspace(monitor?.activeWorkspace);
  }

  function forWorkspace(workspace) {
    if (!workspace)
      return [];

    return Hyprland.toplevels.values.filter(toplevel => {
      return toplevel.workspace?.id === workspace.id && toplevel.wayland;
    }).sort((a, b) => {
      // The scrolling layout runs columns left to right, so window geometry is
      // the layout order. Panning shifts every window by the same offset, which
      // leaves the relative order intact.
      const posA = a.lastIpcObject?.at ?? [0, 0];
      const posB = b.lastIpcObject?.at ?? [0, 0];
      return (posA[0] - posB[0]) || (posA[1] - posB[1]);
    });
  }

  // Workspaces belonging to a monitor, lowest id first. Hyprland numbers
  // workspaces globally and lets them migrate between monitors, so membership
  // has to be read from the workspace rather than assumed from its id.
  function forMonitorWorkspaces(monitor) {
    if (!monitor)
      return [];

    return Hyprland.workspaces.values.filter(workspace => {
      return workspace.monitor?.name === monitor.name;
    }).sort((a, b) => a.id - b.id);
  }

  // Lowest positive id not already taken, so a new workspace slots into the
  // first gap instead of climbing forever.
  function firstFreeWorkspaceId() {
    const used = Hyprland.workspaces.values.map(workspace => workspace.id);
    for (let id = 1; id < 1000; id++) {
      if (!used.includes(id))
        return id;
    }
    return -1;
  }

  // Union of a workspace's monitor viewport and every window on it, in
  // Hyprland's logical coordinate space. The viewport is always included so a
  // workspace always has a frame to draw even when it holds no windows, and so
  // windows scrolled off the tape read as outside it rather than redefining it.
  function boundsForWorkspace(workspace) {
    const monitor = workspace?.monitor;
    if (!monitor)
      return null;

    // `width`/`height` are the untransformed mode in physical pixels, but window
    // coordinates are logical and post-rotation. The odd transforms are the
    // quarter turns, which swap the axes: DP-2 runs at transform 3 and reports
    // 3840x2160 while actually presenting 2160x3840.
    const scale = monitor.scale > 0 ? monitor.scale : 1;
    const rotated = ((monitor.lastIpcObject?.transform ?? 0) % 2) === 1;
    const viewport = {
      x: monitor.x,
      y: monitor.y,
      width: (rotated ? monitor.height : monitor.width) / scale,
      height: (rotated ? monitor.width : monitor.height) / scale
    };

    let left = viewport.x;
    let top = viewport.y;
    let right = viewport.x + viewport.width;
    let bottom = viewport.y + viewport.height;

    for (const toplevel of forWorkspace(workspace)) {
      const at = toplevel.lastIpcObject?.at;
      const size = toplevel.lastIpcObject?.size;
      if (!at || !size)
        continue;

      left = Math.min(left, at[0]);
      top = Math.min(top, at[1]);
      right = Math.max(right, at[0] + size[0]);
      bottom = Math.max(bottom, at[1] + size[1]);
    }

    return {
      x: left,
      y: top,
      width: Math.max(1, right - left),
      height: Math.max(1, bottom - top),
      viewport: viewport
    };
  }

  // The tape sliced into screenful-sized pages. The scrolling layout makes a
  // workspace wider (or taller) than the monitor, and only one screenful is ever
  // rendered — so a page is the natural unit for "somewhere I could jump to".
  //
  // Pages are anchored on the *current* viewport rather than tiled from the
  // bounds origin, which keeps the live page exactly one page instead of
  // straddling two. Only pages holding a window are returned; an empty page is
  // nothing to look at and has no window to scroll to.
  function pagesForWorkspace(workspace) {
    const bounds = boundsForWorkspace(workspace);
    if (!bounds)
      return [];

    const viewport = bounds.viewport;
    const windows = forWorkspace(workspace);

    // A quarter-turned monitor scrolls down its long edge instead of across, so
    // the page axis follows whichever one actually overflows.
    const vertical = (bounds.height - viewport.height) > (bounds.width - viewport.width);
    const span = vertical ? viewport.height : viewport.width;
    if (span <= 0)
      return [];

    const origin = vertical ? viewport.y : viewport.x;
    const low = vertical ? bounds.y : bounds.x;
    const high = low + (vertical ? bounds.height : bounds.width);

    const first = Math.floor((low - origin) / span);
    const last = Math.floor((high - origin - 1) / span);

    const pages = [];
    for (let index = first; index <= last; index++) {
      const start = origin + index * span;
      const end = start + span;

      // Claimed by the page holding its midpoint, so a window straddling a seam
      // lands in exactly one page rather than none or both.
      const held = windows.filter(toplevel => {
        const at = toplevel.lastIpcObject?.at;
        const size = toplevel.lastIpcObject?.size;
        if (!at || !size)
          return false;

        const mid = vertical ? at[1] + size[1] / 2 : at[0] + size[0] / 2;
        return mid >= start && mid < end;
      });

      if (held.length === 0)
        continue;

      pages.push({
        x: vertical ? viewport.x : start,
        y: vertical ? start : viewport.y,
        width: vertical ? viewport.width : span,
        height: vertical ? span : viewport.height,
        current: index === 0,
        count: held.length,
        address: held[0].address ?? ""
      });
    }

    return pages;
  }

  // `HyprlandToplevel.activated` only follows the IPC event stream, so it reads
  // false for every window until the first `activewindow` arrives. The Wayland
  // flag comes from the compositor with the initial state and is right away.
  function activeIndex(windows) {
    return windows.findIndex(toplevel => toplevel.wayland?.activated);
  }
}
