package main

import (
	"encoding/json"
	"fmt"
	"net/netip"
	"strings"
	"testing"
)

func TestSelection(t *testing.T) {
	t.Run("native longest prefix routing works in both directions", func(t *testing.T) {
		data, err := makePolicy([]string{"203.0.113.0/24", "203.0.113.0/26"}, []string{"203.0.113.0/25"})
		requireNoError(t, err)

		routes, err := desiredRoutes(data, testBaseline(), "tun0")
		requireNoError(t, err)

		for address, want := range map[string]string{
			"203.0.113.1": "tun0", "203.0.113.65": "eth0", "203.0.113.129": "tun0",
		} {
			requireEqual(t, lookupRoute(t, routeRows(t, routes), address)["dev"], want)
		}
	})

	t.Run("broad exclusions preserve more specific LAN routes", func(t *testing.T) {
		baseline := testBaseline()
		baseline[1]["dev"] = "lan0"

		data, err := makePolicy([]string{"203.0.113.0/24"}, []string{"192.0.0.0/16"})
		requireNoError(t, err)

		routes, err := desiredRoutes(data, baseline, "tun0")
		requireNoError(t, err)

		requireEqual(t, lookupRoute(t, append(baseline, routeRows(t, routes)...), "192.0.2.20")["dev"], "lan0")
	})

	t.Run("exclusions retain selected next hop attributes", func(t *testing.T) {
		data, err := makePolicy([]string{"203.0.113.0/24"}, []string{"198.51.100.0/24", "192.0.2.128/25"})
		requireNoError(t, err)

		baseline := testBaseline()
		baseline[0]["flags"] = []string{"onlink"}

		routes, err := desiredRoutes(data, baseline, "tun0")
		requireNoError(t, err)

		connected, gateway := routes[1], routes[2]

		requireEqual(t, connected.Gateway, "")
		requireEqual(t, connected.Scope, uint32(253))
		requireEqual(t, gateway.Gateway, "192.0.2.1")
		requireEqual(t, gateway.Prefsrc, "192.0.2.10")
		requireEqual(t, gateway.Metric, uint32(100))
		requireEqual(t, gateway.Flags, []string{"onlink"})
	})

	t.Run("longest normal prefix precedes metric", func(t *testing.T) {
		baseline := append(testBaseline(),
			routeRow{"dst": "198.51.100.0/24", "gateway": "192.0.2.2", "dev": "eth0", "metric": 500},
			routeRow{"dst": "198.51.100.0/24", "gateway": "192.0.2.3", "dev": "eth0", "metric": 600})

		routes, err := desiredRoutes(testPolicy(t), baseline, "tun0")
		requireNoError(t, err)

		requireEqual(t, routes[1].Gateway, "192.0.2.2")
		requireEqual(t, routes[1].Metric, uint32(500))
	})

	t.Run("unsupported and ambiguous next hops fail with context", func(t *testing.T) {
		for _, test := range []struct {
			name string
			rows []routeRow
			want string
		}{
			{"missing", nil, "no normal route"},
			{"multipath", []routeRow{{"dst": "default", "dev": "eth0", "nexthops": []any{}}}, "unsupported route fields"},
			{"link down", []routeRow{{"dev": "eth0", "flags": []string{"linkdown"}}}, "no normal route"},
			{"dead", []routeRow{{"dev": "eth0", "flags": []string{"dead"}}}, "no normal route"},
			{"unknown flag", []routeRow{{"dev": "eth0", "flags": []string{"unsupported"}}}, "unsupported route flags"},
			{"ambiguous", []routeRow{{"dev": "eth0", "gateway": "192.0.2.1"}, {"dev": "eth0", "gateway": "192.0.2.2"}}, "ambiguous"},
		} {
			t.Run(test.name, func(t *testing.T) {
				_, err := desiredRoutes(testPolicy(t), test.rows, "tun0")
				requireError(t, err, test.want)
			})
		}
	})

	t.Run("down next hops are skipped even when more specific", func(t *testing.T) {
		for _, flag := range []string{"linkdown", "dead"} {
			rows := append(testBaseline(), routeRow{
				"dst": "198.51.100.0/24", "dev": "eth0", "gateway": "192.0.2.2", "flags": []string{flag},
			})

			routes, err := desiredRoutes(testPolicy(t), rows, "tun0")
			requireNoError(t, err)

			requireEqual(t, routes[1].Gateway, "192.0.2.1")
		}
	})

	t.Run("unrelated raw baseline attributes are not rejected", func(t *testing.T) {
		rows := append(testBaseline(), routeRow{
			"dst": "10.0.0.0/8", "type": "blackhole", "nexthops": []any{}, "private": map[string]any{"nested": true},
		})

		_, err := desiredRoutes(testPolicy(t), rows, "tun0")
		requireNoError(t, err)
	})
}

func TestKernelBoundary(t *testing.T) {
	t.Run("numeric kernel strings normalize like numeric fields", func(t *testing.T) {
		row, err := routeSpec(routeRow{
			"dst": "default", "dev": "eth0", "metric": "100", "scope": "0", "protocol": "16",
			"flags": []any{"dead", "onlink", "linkdown"},
		}, "synthetic")
		requireNoError(t, err)

		requireEqual(t, row, route{Dst: "0.0.0.0/0", Dev: "eth0", Metric: 100, Protocol: 16, Flags: []string{"onlink"}})

		for _, value := range []any{true, nil, float64(1), "-1", json.Number("1.5"), "4294967296", "1e2"} {
			if _, err := number(value, "synthetic"); err == nil {
				t.Fatalf("accepted invalid number %#v", value)
			}
		}
	})

	t.Run("batch tokens are validated and bounded", func(t *testing.T) {
		routes, err := desiredRoutes(testPolicy(t), testBaseline(), "tun0")
		requireNoError(t, err)

		rows := make([]route, batchSize+1)

		for i := range rows {
			rows[i] = routes[1]
		}

		var batches []string
		k := kernel{func(args []string, stage string, env map[string]string, input string) (string, error) {
			requireEqual(t, args, []string{"ip", "-4", "-batch", "-"})

			batches = append(batches, input)

			return "", nil
		}}
		requireNoError(t, k.change("add", rows))

		requireEqual(t, len(batches), 2)
		requireEqual(t, strings.Count(batches[0], "\n"), 128)
		requireEqual(t, strings.Count(batches[1], "\n"), 1)

		if !strings.Contains(batches[1], "proto 242 via 192.0.2.1 dev eth0 scope 0 metric 100 src 192.0.2.10") {
			t.Fatal("next hop attributes missing")
		}

		rows[0].Dev = "eth0\nroute"
		requireError(t, k.change("add", rows[:1]), "interface name")

		requireEqual(t, len(batches), 2)
	})

	t.Run("only configuration flags are emitted", func(t *testing.T) {
		row := route{Dst: "203.0.113.0/24", Dev: "eth0", Protocol: protocol, Flags: []string{"dead", "onlink", "linkdown"}}
		k := kernel{func(args []string, stage string, env map[string]string, input string) (string, error) {
			if !strings.Contains(input, "onlink") || strings.Contains(input, "dead") || strings.Contains(input, "linkdown") {
				t.Fatal("incorrect route flags")
			}

			return "", nil
		}}
		requireNoError(t, k.change("del", []route{row}))
	})

	t.Run("snapshots preserve raw rows and reject invalid lists", func(t *testing.T) {
		for _, content := range []string{`{}`, `[null]`, `["private"]`, `invalid`} {
			k := kernel{func([]string, string, map[string]string, string) (string, error) {
				return content, nil
			}}

			if _, err := k.routes(); err == nil {
				t.Fatal("accepted invalid snapshot")
			}
		}

		k := kernel{func(args []string, _ string, _ map[string]string, _ string) (string, error) {
			requireEqual(t, args, []string{"ip", "-N", "-j", "-4", "route", "show", "table", "main"})

			return `[{"dst":"default","metric":"100","unknown":{"large":12345678901234567890}}]`, nil
		}}

		rows, err := k.routes()
		requireNoError(t, err)

		requireEqual(t, rows[0]["unknown"].(map[string]any)["large"], json.Number("12345678901234567890"))
	})
}

func testBaseline() []routeRow {
	return []routeRow{
		{"dst": "default", "gateway": "192.0.2.1", "dev": "eth0", "protocol": 16,
			"prefsrc": "192.0.2.10", "metric": 100, "flags": []string{}},
		{"dst": "192.0.2.0/24", "dev": "eth0", "protocol": 2, "scope": "link",
			"prefsrc": "192.0.2.10", "flags": []string{}},
	}
}

func routeRows(t *testing.T, routes []route) []routeRow {
	t.Helper()

	result := make([]routeRow, 0, len(routes))

	for _, route := range routes {
		value, err := decodeJSON(encodeTestJSON(t, route), "synthetic")
		requireNoError(t, err)

		result = append(result, value.(map[string]any))
	}

	return result
}

func lookupRoute(t *testing.T, rows []routeRow, address string) routeRow {
	t.Helper()

	ip := netip.MustParseAddr(address)
	bestBits := -1
	var bestMetric uint32
	var selected routeRow

	for _, row := range rows {
		prefix, err := routePrefix(row, "synthetic")
		requireNoError(t, err)

		metric, err := number(field(row, "metric", 0), "synthetic")
		requireNoError(t, err)

		if prefix.Contains(ip) && (prefix.Bits() > bestBits || (prefix.Bits() == bestBits && metric < bestMetric)) {
			selected, bestBits, bestMetric = row, prefix.Bits(), metric
		}
	}

	if selected == nil {
		t.Fatal(fmt.Sprintf("no synthetic route covers %s", address))
	}

	return selected
}
