set -euo pipefail

# Prints the `Id` of every registered StatusNotifierItem that describes the
# org.kde.StatusNotifierItem interface without an `Activate` method, one per
# line. The bar reads this to decide which tray items must open their menu on a
# left click; see quickshell/TrayActivation.qml for why it cannot ask Quickshell.

readonly WATCHER=org.kde.StatusNotifierWatcher

# An unresponsive tray app must not stall the probe, hence the timeouts. The
# watcher stores each registration as either "service/object" or a bare service
# name, in which case the object path is the one the spec fixes.
entries=$(
  busctl --user --timeout=2 get-property \
    "$WATCHER" /StatusNotifierWatcher "$WATCHER" RegisteredStatusNotifierItems 2>/dev/null |
    grep -o '"[^"]*"' | tr -d '"' || true
)

[ -n "$entries" ] || exit 0

while IFS= read -r entry; do
  case "$entry" in
    */*)
      service="${entry%%/*}"
      object="/${entry#*/}"
      ;;
    *)
      service="$entry"
      object="/StatusNotifierItem"
      ;;
  esac

  members=$(
    busctl --user --timeout=2 introspect "$service" "$object" org.kde.StatusNotifierItem 2>/dev/null |
      grep -w method || true
  )

  # An empty description is not evidence of a missing method: Chromium's tray
  # icon (and so 1Password's) publishes none at all yet does implement
  # `Activate`. Only an interface that describes itself and omits the method
  # counts as menu-only.
  [ -n "$members" ] || continue

  case "$members" in
    *".Activate "*) continue ;;
  esac

  busctl --user --timeout=2 get-property "$service" "$object" org.kde.StatusNotifierItem Id 2>/dev/null |
    sed -n 's/^s "\(.*\)"$/\1/p'
done <<<"$entries"
