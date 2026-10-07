package main

import (
	"encoding/json"
	"fmt"
	"net/netip"
	"os/exec"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

const (
	protocol  = 242
	batchSize = 128
)

type routeRow = map[string]any

type route struct {
	Dst      string   `json:"dst"`
	Dev      string   `json:"dev"`
	Metric   uint32   `json:"metric"`
	Scope    uint32   `json:"scope"`
	Protocol uint32   `json:"protocol"`
	Flags    []string `json:"flags"`
	Gateway  string   `json:"gateway,omitempty"`
	Prefsrc  string   `json:"prefsrc,omitempty"`
}

var devicePattern = regexp.MustCompile(`^[a-zA-Z0-9_.:@-]{1,15}$`)

func device(value string) error {
	if !devicePattern.MatchString(value) {
		return fmt.Errorf("route device: unsupported interface name")
	}

	return nil
}

func number(value any, context string) (uint32, error) {
	var text string

	switch value := value.(type) {
	case string:
		text = value

	case json.Number:
		text = string(value)

	case uint32:
		return value, nil

	case int:
		text = strconv.Itoa(value)

	default:
		return 0, fmt.Errorf("%s: expected a nonnegative integer", context)
	}

	if !decimal(text) {
		return 0, fmt.Errorf("%s: expected a nonnegative integer", context)
	}

	result, err := strconv.ParseUint(text, 10, 32)
	if err != nil {
		return 0, fmt.Errorf("%s: integer out of range", context)
	}

	return uint32(result), nil
}

func field(row routeRow, key string, fallback any) any {
	if value, ok := row[key]; ok {
		return value
	}

	return fallback
}

func routePrefix(row routeRow, context string) (netip.Prefix, error) {
	value, ok := field(row, "dst", "default").(string)
	if !ok {
		return netip.Prefix{}, fmt.Errorf("%s: expected a canonical IPv4 prefix", context)
	}

	if value == "default" {
		value = "0.0.0.0/0"
	}

	return network(value, context)
}

func routeFlags(row routeRow) ([]string, bool) {
	value, ok := row["flags"]
	if !ok {
		return []string{}, true
	}

	if flags, ok := value.([]string); ok {
		return flags, flags != nil
	}

	return stringList(value)
}

func routeSpec(row routeRow, context string) (route, error) {
	for key := range row {
		switch key {
		case "dst", "dev", "gateway", "prefsrc", "metric", "scope", "protocol", "flags", "type", "table":

		default:
			return route{}, fmt.Errorf("%s: unsupported route fields", context)
		}
	}

	table := field(row, "table", "main")
	if field(row, "type", "unicast") != "unicast" ||
		(table != "main" && table != json.Number("254") && table != 254) {
		return route{}, fmt.Errorf("%s: expected a unicast main-table route", context)
	}

	flags, ok := routeFlags(row)
	if !ok {
		return route{}, fmt.Errorf("%s: unsupported route flags", context)
	}

	result := route{Flags: []string{}}

	for _, flag := range flags {
		if flag != "onlink" && flag != "linkdown" && flag != "dead" {
			return route{}, fmt.Errorf("%s: unsupported route flags", context)
		}
	}

	if slices.Contains(flags, "onlink") {
		result.Flags = []string{"onlink"}
	}

	prefix, err := routePrefix(row, context)
	if err != nil {
		return route{}, err
	}

	result.Dst = prefix.String()
	result.Dev, _ = row["dev"].(string)

	if err := device(result.Dev); err != nil {
		return route{}, err
	}

	scope := field(row, "scope", "global")

	if text, ok := scope.(string); ok {
		if n, ok := map[string]int{"global": 0, "universe": 0, "link": 253, "host": 254}[text]; ok {
			scope = n
		}
	}

	proto := field(row, "protocol", 0)

	if text, ok := proto.(string); ok {
		if n, ok := map[string]int{"kernel": 2, "boot": 3, "static": 4, "dhcp": 16}[text]; ok {
			proto = n
		}
	}

	result.Metric, err = number(field(row, "metric", 0), context)
	if err != nil {
		return route{}, err
	}

	result.Scope, err = number(scope, context)
	if err != nil {
		return route{}, err
	}

	result.Protocol, err = number(proto, context)
	if err != nil {
		return route{}, err
	}

	for key, out := range map[string]*string{"gateway": &result.Gateway, "prefsrc": &result.Prefsrc} {
		if value, ok := row[key]; ok {
			text, _ := value.(string)

			ip, err := netip.ParseAddr(text)
			if err != nil || !ip.Is4() {
				return route{}, fmt.Errorf("%s: invalid IPv4 %s", context, key)
			}

			*out = ip.String()
		}
	}

	return result, nil
}

func sameRoute(a, b route) bool {
	return a.Dst == b.Dst && a.Dev == b.Dev && a.Metric == b.Metric &&
		a.Scope == b.Scope && a.Protocol == b.Protocol && a.Gateway == b.Gateway &&
		a.Prefsrc == b.Prefsrc && slices.Equal(a.Flags, b.Flags)
}

func equivalent(a, b route) bool {
	a.Protocol = b.Protocol

	return sameRoute(a, b)
}

func containsRoute(rows []route, target route) bool {
	return slices.ContainsFunc(rows, func(row route) bool {
		return sameRoute(row, target)
	})
}

func privateProtocol(row routeRow) bool {
	switch value := row["protocol"].(type) {
	case string:
		return value == "242"

	case json.Number:
		return value == "242"

	case uint32:
		return value == protocol

	case int:
		return value == protocol
	}

	return false
}

func normalBaseline(rows []routeRow, tun string) []routeRow {
	result := make([]routeRow, 0, len(rows))

	for _, row := range rows {
		if row["dev"] != tun && !privateProtocol(row) {
			result = append(result, row)
		}
	}

	return result
}

func desiredRoutes(data policy, baseline []routeRow, tun string) ([]route, error) {
	if err := device(tun); err != nil {
		return nil, err
	}

	desired := make([]route, 0, len(data.Includes)+len(data.Excludes))

	for _, prefix := range data.Includes {
		desired = append(desired, route{
			Dst: prefix, Dev: tun, Scope: 253, Protocol: protocol, Flags: []string{},
		})
	}

	type candidate struct {
		prefix  netip.Prefix
		row     routeRow
		ordinal int
	}

	normal := make([]candidate, 0, len(baseline))

	for i, row := range baseline {
		flags, _ := routeFlags(row)
		if row["dev"] == tun || privateProtocol(row) ||
			slices.Contains(flags, "linkdown") || slices.Contains(flags, "dead") {
			continue
		}

		prefix, err := routePrefix(row, fmt.Sprintf("baseline route %d", i+1))
		if err != nil {
			return nil, err
		}

		normal = append(normal, candidate{prefix, row, i + 1})
	}

	for i, prefix := range data.Excludes {
		context := fmt.Sprintf("exclude entry %d", i+1)

		subnet, err := network(prefix, context)
		if err != nil {
			return nil, err
		}

		bestBits := -1
		var bestMetric uint32
		var selected []candidate

		for _, item := range normal {
			if item.prefix.Bits() > subnet.Bits() || !item.prefix.Contains(subnet.Addr()) {
				continue
			}

			metric, err := number(field(item.row, "metric", 0), context)
			if err != nil {
				return nil, err
			}

			if item.prefix.Bits() > bestBits || (item.prefix.Bits() == bestBits && metric < bestMetric) {
				bestBits, bestMetric = item.prefix.Bits(), metric
				selected = nil
			}

			if item.prefix.Bits() == bestBits && metric == bestMetric {
				selected = append(selected, item)
			}
		}

		if len(selected) == 0 {
			return nil, fmt.Errorf("%s: no normal route covers the whole prefix", context)
		}

		var chosen route

		for j, item := range selected {
			spec, err := routeSpec(item.row, fmt.Sprintf("%s, baseline route %d", context, item.ordinal))
			if err != nil {
				return nil, err
			}

			if j > 0 && !equivalent(chosen, spec) {
				return nil, fmt.Errorf("%s: ambiguous normal next hop", context)
			}

			chosen = spec
		}

		chosen.Dst, chosen.Protocol = prefix, protocol

		desired = append(desired, chosen)
	}

	return desired, nil
}

func exactRoutes(routes []route, rows []routeRow) ([]route, error) {
	prefixes := make(map[string]bool, len(routes))

	for _, row := range routes {
		prefixes[row.Dst] = true
	}

	result := make([]route, 0)

	for i, row := range rows {
		context := fmt.Sprintf("current route %d", i+1)

		prefix, err := routePrefix(row, context)
		if err != nil {
			return nil, err
		}

		if prefixes[prefix.String()] {
			spec, err := routeSpec(row, context)
			if err != nil {
				return nil, err
			}

			result = append(result, spec)
		}
	}

	return result, nil
}

type routeKernel interface {
	routes() ([]routeRow, error)
	change(string, []route) error
}

type kernel struct {
	run commandRunner
}

func runKernelCommand(args []string, stage string, env map[string]string, input string) (string, error) {
	cmd := exec.Command(args[0], args[1:]...)

	cmd.Stdin = strings.NewReader(input)

	output, err := cmd.Output()
	if err != nil {
		if exit, ok := err.(*exec.ExitError); ok {
			return "", fmt.Errorf("%s failed (exit %d)", stage, exit.ExitCode())
		}

		return "", fmt.Errorf("%s: system operation failed", stage)
	}

	return string(output), nil
}

func (k kernel) routes() ([]routeRow, error) {
	output, err := k.run([]string{"ip", "-N", "-j", "-4", "route", "show", "table", "main"},
		"IPv4 main-table snapshot", nil, "")
	if err != nil {
		return nil, err
	}

	value, err := decodeJSON([]byte(output), "ip route snapshot")
	if err != nil {
		return nil, err
	}

	list, ok := value.([]any)
	if !ok {
		return nil, fmt.Errorf("ip returned an invalid route list")
	}

	rows := make([]routeRow, 0, len(list))

	for _, value := range list {
		row, ok := value.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("ip returned an invalid route list")
		}

		rows = append(rows, row)
	}

	return rows, nil
}

func (k kernel) change(action string, routes []route) error {
	if action != "add" && action != "del" {
		return fmt.Errorf("unsupported route action")
	}

	for start := 0; start < len(routes); start += batchSize {
		end := min(start+batchSize, len(routes))
		var input strings.Builder

		for _, row := range routes[start:end] {
			// Revalidate the batch boundary, even when callers hold typed routes.
			content, err := json.Marshal(row)
			if err != nil {
				return fmt.Errorf("route batch: invalid descriptor")
			}

			value, err := decodeJSON(content, "route batch")
			if err != nil {
				return err
			}

			row, err = routeSpec(value.(map[string]any), "route batch")
			if err != nil {
				return err
			}

			fmt.Fprintf(&input, "route %s %s table main proto %d", action, row.Dst, row.Protocol)

			if row.Gateway != "" {
				fmt.Fprintf(&input, " via %s", row.Gateway)
			}

			fmt.Fprintf(&input, " dev %s scope %d metric %d", row.Dev, row.Scope, row.Metric)

			if row.Prefsrc != "" {
				fmt.Fprintf(&input, " src %s", row.Prefsrc)
			}

			for _, flag := range row.Flags {
				fmt.Fprintf(&input, " %s", flag)
			}

			input.WriteByte('\n')
		}

		stage := fmt.Sprintf("route %s batch %d (%d entries)", action, start/batchSize+1, end-start)

		if _, err := k.run([]string{"ip", "-4", "-batch", "-"}, stage, nil, input.String()); err != nil {
			return err
		}
	}

	return nil
}
