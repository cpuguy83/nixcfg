import QtQuick
import QtTest
import "../quickshell/launcher/Logic.js" as Logic

TestCase {
  name: "Launcher"

  function test_picker_preserves_indices() {
    const rows = Logic.pickerRows(["same", "", " same ", "same", "=1+2"], "same");
    compare(rows.map(row => row.index), [0, 2, 3]);
    compare(rows.map(row => row.text), ["same", " same ", "same"]);
    compare(Logic.pickerRows(["", ""], "").map(row => row.index), [0, 1]);
    compare(Logic.pickerRows(["=1+2"], "=")[0].text, "=1+2");
  }

  function test_apps_search_metadata_and_sort_deterministically() {
    const entries = [
      {
        id: "z",
        name: "Alpha",
        genericName: "Editor",
        keywords: ["code"]
      },
      {
        id: "hidden",
        name: "Alpha",
        noDisplay: true
      },
      {
        id: "b",
        name: "beta",
        genericName: "Terminal",
        keywords: ["shell"]
      },
      {
        id: "a",
        name: "alpha",
        genericName: "Writer",
        keywords: ["text"]
      }
    ];
    compare(Logic.applicationRows(entries, "").map(row => row.id), ["a", "z", "b"]);
    compare(Logic.applicationRows(entries, "alpha code").map(row => row.id), ["z"]);
    compare(Logic.applicationRows(entries, "TERMINAL").map(row => row.id), ["b"]);
    compare(Logic.applicationRows(entries, "text").map(row => row.id), ["a"]);
    compare(Logic.applicationRows(entries, "missing"), []);
  }

  function test_navigation_stays_in_bounds() {
    compare(Logic.navigate(0, -1, 10), 0);
    compare(Logic.navigate(2, 7, 10), 9);
    compare(Logic.navigate(9, 7, 10), 9);
    compare(Logic.navigate(8, -7, 10), 1);
    compare(Logic.navigate(0, 1, 0), -1);
  }

  function test_apps_win_unless_calculation_is_forced() {
    for (const query of ["1+2", "2 m to cm", "x", "ordinary search"]) {
      compare(Logic.routeQuery(query, false, 1).math, false);
      compare(Logic.routeQuery(query, false, 1).text, "");
      compare(Logic.routeQuery(query, false, 0).math, true);
      compare(Logic.routeQuery(query, false, 0).text, query);
      compare(Logic.routeQuery("=" + query, false, 1).math, true);
    }
  }

  function test_blank_and_picker_queries_never_evaluate() {
    for (const query of ["", " ", "\t"]) {
      compare(Logic.routeQuery(query, false, 0).math, false);
      compare(Logic.routeQuery(query, false, 0).hasExpression, false);
    }
    for (const query of ["", "1+2", "=1+2", "=", "x"]) {
      compare(Logic.routeQuery(query, true, 0).math, false);
      compare(Logic.routeQuery(query, true, 0).hasExpression, false);
      compare(Logic.routeQuery(query, true, 0).text, "");
    }
    compare(Logic.routeQuery("= ", false, 1).math, true);
    compare(Logic.routeQuery("= ", false, 1).hasExpression, false);
  }

  function test_catalog_changes_reroute_unchanged_text() {
    const query = "1+2";
    const entry = {
      id: "calculator-app",
      name: query
    };
    compare(Logic.routeQuery(query, false, Logic.applicationRows([], query).length).math, true);
    compare(Logic.routeQuery(query, false, Logic.applicationRows([entry], query).length).math, false);
    compare(Logic.routeQuery(query, false, Logic.applicationRows([], query).length).math, true);
    compare(Logic.routeQuery("=" + query, false, 1).math, true);
  }

  function test_hyprland_waits_for_the_focused_monitor() {
    const screens = [
      {
        name: "left"
      },
      {
        name: "right"
      }
    ];
    compare(Logic.screenForLaunch(screens, "", true), null);
    compare(Logic.screenForLaunch(screens, "right", true), screens[1]);
    compare(Logic.screenForLaunch(screens, "", false), screens[0]);
    compare(Logic.screenForLaunch([], "", false), null);
  }

  function test_unset_signature_uses_the_fallback_screen() {
    const screens = [
      {
        name: "HEADLESS-1"
      }
    ];
    for (const signature of [null, undefined, ""]) {
      compare(Logic.screenForLaunch(screens, "", (signature ?? "") !== ""), screens[0]);
    }
    compare(Logic.screenForLaunch(screens, "", ("hyprland-instance" ?? "") !== ""), null);
  }
}
