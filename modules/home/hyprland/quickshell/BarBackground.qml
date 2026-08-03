import QtQuick
import QtQuick.Shapes

// The bar's plate. The two corners on its desktop-facing edge are cut in with a
// concave superellipse quadrant — the inverse of the curve Hyprland rounds a
// window with — so the space the bar leaves behind reads as a rounded edge
// rather than a hard rectangle.
//
// Those cut-ins are drawn *past* the edge of the strip the bar reserves, which
// is why its surface has to overhang that strip by Theme.barCornerRadius.
//
// One closed path, not a rectangle plus two corner pieces: the fill is
// translucent, so anywhere two shapes abutted, their antialiased edges would
// composite to less than a full pixel of colour and leave a visible seam.
Shape {
  id: root

  // Samples per quadrant. The parametrisation below packs them where the curve
  // actually bends, so the chord error stays far below a pixel at any radius
  // the bar would plausibly use.
  readonly property int segments: 24

  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    fillColor: Theme.barBackground
    strokeWidth: -1

    PathPolyline { path: root.outline() }
  }

  // The plate's outline, walked clockwise from the corner furthest from the
  // desktop. Expressed with the bar at the top and mirrored at the end, so the
  // curve only has to be worked out once.
  function outline() {
    const w = root.width;
    const h = root.height;
    // Clamped so a degenerate size — the first frame, a very narrow screen —
    // cannot fold the path back on itself.
    const r = Math.min(Theme.barCornerRadius, w / 2, h);
    // Hyprland rounds windows on |x|^p + |y|^p = r^p, and (cos t, sin t) raised
    // to 2/p traces exactly that curve.
    const e = 2 / Theme.barCornerPower;

    const points = [Qt.point(0, 0), Qt.point(w, 0)];

    // Down the right screen edge, then back up onto the plate around the corner
    // a window would have rounded off.
    for (let i = 0; i <= root.segments; i++) {
      const t = (i / root.segments) * (Math.PI / 2);
      points.push(Qt.point(w - r + r * Math.pow(Math.cos(t), e), h - r * Math.pow(Math.sin(t), e)));
    }

    // Across the plate's inner edge, then back down to the left screen edge.
    for (let i = 0; i <= root.segments; i++) {
      const t = (i / root.segments) * (Math.PI / 2);
      points.push(Qt.point(r - r * Math.pow(Math.sin(t), e), h - r * Math.pow(Math.cos(t), e)));
    }

    points.push(Qt.point(0, 0));

    return Theme.barAtBottom ? points.map(p => Qt.point(p.x, h - p.y)) : points;
  }
}
