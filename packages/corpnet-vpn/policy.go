package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io"
	"math/bits"
	"net/netip"
	"os"
	"slices"
	"strconv"
	"strings"
	"unicode/utf16"
	"unicode/utf8"
)

const policyPath = "/etc/msft-vpn/corpnet-routes.json"

type policy struct {
	Version  int      `json:"version"`
	Includes []string `json:"includes"`
	Excludes []string `json:"excludes"`
}

func network(value, context string) (netip.Prefix, error) {
	fail := func() (netip.Prefix, error) {
		return netip.Prefix{}, fmt.Errorf("%s: expected a canonical IPv4 prefix", context)
	}

	address, mask, hasMask := strings.Cut(value, "/")

	ip, err := netip.ParseAddr(address)
	if err != nil || !ip.Is4() {
		return fail()
	}

	length := 32

	if hasMask {
		if strings.Contains(mask, ".") {
			m, err := netip.ParseAddr(mask)
			if err != nil || !m.Is4() {
				return fail()
			}

			b := m.As4()
			n := uint32(b[0])<<24 | uint32(b[1])<<16 | uint32(b[2])<<8 | uint32(b[3])

			// Try a netmask first, then its inverse as a host mask.
			length = bits.OnesCount32(n)

			if n != ^uint32(0)<<(32-length) {
				n = ^n
				length = bits.OnesCount32(n)

				if n != ^uint32(0)<<(32-length) {
					return fail()
				}
			}
		} else {
			if !decimal(mask) {
				return fail()
			}

			length, err = strconv.Atoi(mask)
			if err != nil || length > 32 {
				return fail()
			}
		}
	}

	prefix := netip.PrefixFrom(ip, length)
	if prefix != prefix.Masked() {
		return fail()
	}

	return prefix, nil
}

func decimal(value string) bool {
	if value == "" {
		return false
	}

	for _, c := range value {
		if c < '0' || c > '9' {
			return false
		}
	}

	return true
}

func makePolicy(includes, excludes []string) (policy, error) {
	result := policy{Version: 1}

	for _, section := range []struct {
		name string
		in   []string
		out  *[]string
	}{
		{"includes", includes, &result.Includes},
		{"excludes", excludes, &result.Excludes},
	} {
		prefixes := make(map[netip.Prefix]bool)

		for i, value := range section.in {
			context := fmt.Sprintf("%s entry %d", section.name, i+1)

			prefix, err := network(value, context)
			if err != nil {
				return policy{}, err
			}

			if prefix.String() != value {
				return policy{}, fmt.Errorf("%s: noncanonical CIDR", context)
			}

			prefixes[prefix] = true
		}

		ordered := make([]netip.Prefix, 0, len(prefixes))

		for prefix := range prefixes {
			ordered = append(ordered, prefix)
		}

		slices.SortFunc(ordered, func(a, b netip.Prefix) int {
			if cmp := a.Addr().Compare(b.Addr()); cmp != 0 {
				return cmp
			}

			return a.Bits() - b.Bits()
		})

		*section.out = make([]string, 0, len(ordered))

		for _, prefix := range ordered {
			*section.out = append(*section.out, prefix.String())
		}
	}

	if len(result.Includes) == 0 {
		return policy{}, fmt.Errorf("policy has no IPv4 includes")
	}

	conflicts := 0

	for _, prefix := range result.Includes {
		if slices.Contains(result.Excludes, prefix) {
			conflicts++
		}
	}

	if conflicts != 0 {
		return policy{}, fmt.Errorf("policy has %d identical include/exclude prefixes", conflicts)
	}

	return result, nil
}

// Decode numbers without a float conversion: persisted identities and kernel
// attributes have different contracts, and both must keep their original types.
func decodeJSON(content []byte, stage string) (any, error) {
	if !utf8.Valid(content) {
		return nil, fmt.Errorf("%s: invalid JSON", stage)
	}

	decoder := json.NewDecoder(bytes.NewReader(content))
	decoder.UseNumber()

	var value any

	if err := decoder.Decode(&value); err != nil {
		return nil, fmt.Errorf("%s: invalid JSON", stage)
	}

	if err := decoder.Decode(new(any)); err != io.EOF {
		return nil, fmt.Errorf("%s: invalid JSON", stage)
	}

	return value, nil
}

func exactKeys(object map[string]any, keys ...string) bool {
	if len(object) != len(keys) {
		return false
	}

	for _, key := range keys {
		if _, ok := object[key]; !ok {
			return false
		}
	}

	return true
}

func stringList(value any) ([]string, bool) {
	list, ok := value.([]any)
	if !ok {
		return nil, false
	}

	result := make([]string, 0, len(list))

	for _, value := range list {
		text, ok := value.(string)
		if !ok {
			return nil, false
		}

		result = append(result, text)
	}

	return result, true
}

func jsonPolicy(content []byte) (policy, error) {
	value, err := decodeJSON(content, "policy")
	if err != nil {
		return policy{}, err
	}

	object, ok := value.(map[string]any)
	if !ok || !exactKeys(object, "version", "includes", "excludes") {
		return policy{}, fmt.Errorf("policy: invalid schema")
	}

	if object["version"] != json.Number("1") {
		return policy{}, fmt.Errorf("policy: unsupported version")
	}

	includes, incOK := stringList(object["includes"])

	excludes, excOK := stringList(object["excludes"])
	if !incOK || !excOK {
		return policy{}, fmt.Errorf("policy: expected route lists")
	}

	return makePolicy(includes, excludes)
}

func loadPolicy(path string) (policy, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return policy{}, err
	}

	return jsonPolicy(content)
}

type xmlElement struct {
	XMLName  xml.Name
	Text     string       `xml:",chardata"`
	Children []xmlElement `xml:",any"`
}

func xmlPolicy(reader io.Reader) (policy, error) {
	content, err := io.ReadAll(reader)
	if err != nil {
		return policy{}, err
	}

	content, encoding, err := xmlUTF8(content)
	if err != nil {
		return policy{}, err
	}

	decoder := xml.NewDecoder(bytes.NewReader(content))

	decoder.CharsetReader = func(charset string, input io.Reader) (io.Reader, error) {
		charset = strings.ToLower(charset)
		if encoding != "" && (charset == "utf-16" || charset == encoding) {
			return input, nil
		}

		if charset != "ascii" && charset != "us-ascii" && charset != "iso-8859-1" {
			return nil, fmt.Errorf("unsupported XML encoding")
		}

		content, err := io.ReadAll(input)
		if err != nil {
			return nil, err
		}

		var text strings.Builder

		for _, b := range content {
			if charset != "iso-8859-1" && b >= utf8.RuneSelf {
				return nil, fmt.Errorf("invalid ASCII XML")
			}

			text.WriteRune(rune(b))
		}

		return strings.NewReader(text.String()), nil
	}

	var root xmlElement

	for root.XMLName.Local == "" {
		token, err := decoder.Token()
		if err != nil {
			return policy{}, fmt.Errorf("XML is malformed")
		}

		switch token := token.(type) {
		case xml.StartElement:
			if err := decoder.DecodeElement(&root, &token); err != nil {
				return policy{}, fmt.Errorf("XML is malformed")
			}

		case xml.Comment, xml.ProcInst, xml.Directive:

		case xml.CharData:
			if strings.Trim(string(token), " \t\r\n") != "" {
				return policy{}, fmt.Errorf("XML is malformed")
			}

		default:
			return policy{}, fmt.Errorf("XML is malformed")
		}
	}

	for {
		token, err := decoder.Token()
		if err == io.EOF {
			break
		}

		if err != nil {
			return policy{}, fmt.Errorf("XML is malformed")
		}

		switch token := token.(type) {
		case xml.Comment, xml.ProcInst:

		case xml.CharData:
			if strings.Trim(string(token), " \t\r\n") != "" {
				return policy{}, fmt.Errorf("XML is malformed")
			}

		default:
			return policy{}, fmt.Errorf("XML is malformed")
		}
	}

	sections := map[string][]string{"includeroutes": {}, "excluderoutes": {}}
	var walk func(xmlElement) error

	walk = func(container xmlElement) error {
		name := strings.ToLower(container.XMLName.Local)

		if _, ok := sections[name]; ok {
			for i, entry := range container.Children {
				context := fmt.Sprintf("XML %s entry %d", name, i+1)

				if !strings.EqualFold(entry.XMLName.Local, "route") {
					return fmt.Errorf("%s: expected route element", context)
				}

				fields := make(map[string]string)

				for _, child := range entry.Children {
					key := strings.ToLower(child.XMLName.Local)
					_, duplicate := fields[key]
					if (key != "destination" && key != "mask") || duplicate || len(child.Children) != 0 {
						return fmt.Errorf("%s: unsupported or duplicate route field", context)
					}

					fields[key] = strings.TrimSpace(child.Text)
				}

				if len(fields) != 2 {
					return fmt.Errorf("%s: destination and mask required", context)
				}

				prefix, err := network(fields["destination"]+"/"+fields["mask"], context)
				if err != nil {
					return err
				}

				sections[name] = append(sections[name], prefix.String())
			}
		}

		for _, child := range container.Children {
			if err := walk(child); err != nil {
				return err
			}
		}

		return nil
	}

	if err := walk(root); err != nil {
		return policy{}, err
	}

	return makePolicy(sections["includeroutes"], sections["excluderoutes"])
}

// Windows profile exports may be UTF-16. encoding/xml only decodes UTF-8;
// convert the XML-standard UTF-16 signatures before parsing its declaration.
func xmlUTF8(content []byte) ([]byte, string, error) {
	var order binary.ByteOrder
	encoding := ""

	switch {
	case bytes.HasPrefix(content, []byte{0xff, 0xfe}):
		order, encoding, content = binary.LittleEndian, "utf-16le", content[2:]

	case bytes.HasPrefix(content, []byte{0xfe, 0xff}):
		order, encoding, content = binary.BigEndian, "utf-16be", content[2:]

	case bytes.HasPrefix(content, []byte{'<', 0, '?', 0}):
		order, encoding = binary.LittleEndian, "utf-16le"

	case bytes.HasPrefix(content, []byte{0, '<', 0, '?'}):
		order, encoding = binary.BigEndian, "utf-16be"

	default:
		return bytes.TrimPrefix(content, []byte{0xef, 0xbb, 0xbf}), "", nil
	}

	if len(content)%2 != 0 {
		return nil, "", fmt.Errorf("XML is malformed")
	}

	var text strings.Builder

	for i := 0; i < len(content); i += 2 {
		r := rune(order.Uint16(content[i : i+2]))
		if utf16.IsSurrogate(r) {
			if i+4 > len(content) {
				return nil, "", fmt.Errorf("XML is malformed")
			}

			r = utf16.DecodeRune(r, rune(order.Uint16(content[i+2:i+4])))
			if r == utf8.RuneError {
				return nil, "", fmt.Errorf("XML is malformed")
			}

			i += 2
		}

		text.WriteRune(r)
	}

	return []byte(text.String()), encoding, nil
}

func serverPolicy(data policy, env map[string]string) (policy, error) {
	gatewayIncludes := make([]string, 0)
	gatewayExcludes := make([]string, 0)

	for _, section := range []struct {
		name string
		out  *[]string
	}{
		{"CISCO_SPLIT_INC", &gatewayIncludes},
		{"CISCO_SPLIT_EXC", &gatewayExcludes},
	} {
		count := "0"

		if value, ok := env[section.name]; ok {
			count = value
		}

		n, err := strconv.Atoi(count)
		if !decimal(count) || err != nil {
			return policy{}, fmt.Errorf("%s: invalid count", section.name)
		}

		for i := 0; i < n; i++ {
			entry := fmt.Sprintf("%s_%d", section.name, i)
			mask, ok := env[entry+"_MASKLEN"]
			if !ok {
				mask = env[entry+"_MASK"]
			}

			prefix, err := network(env[entry+"_ADDR"]+"/"+mask, entry)
			if err != nil {
				return policy{}, err
			}

			if alternate, ok := env[entry+"_MASK"]; ok {
				other, err := network(env[entry+"_ADDR"]+"/"+alternate, entry)
				if err != nil {
					return policy{}, err
				}

				if other != prefix {
					return policy{}, fmt.Errorf("%s: mask and mask length disagree", entry)
				}
			}

			*section.out = append(*section.out, prefix.String())
		}
	}

	// The connected gateway wins only when the profile has the exact same prefix.
	includes := slices.DeleteFunc(slices.Clone(data.Includes), func(prefix string) bool {
		return slices.Contains(gatewayExcludes, prefix)
	})

	excludes := slices.DeleteFunc(slices.Clone(data.Excludes), func(prefix string) bool {
		return slices.Contains(gatewayIncludes, prefix)
	})

	includeSources := make(map[string][]string)
	excludeSources := make(map[string][]string)

	for _, prefix := range includes {
		addRouteSource(includeSources, prefix, "profile")
	}

	for _, prefix := range excludes {
		addRouteSource(excludeSources, prefix, "profile")
	}

	for _, prefix := range gatewayIncludes {
		addRouteSource(includeSources, prefix, "gateway split")
	}

	for _, prefix := range gatewayExcludes {
		addRouteSource(excludeSources, prefix, "gateway split")
	}

	includes = append(includes, gatewayIncludes...)
	excludes = append(excludes, gatewayExcludes...)

	for i, value := range strings.Fields(env["INTERNAL_IP4_DNS"]) {
		ip, err := netip.ParseAddr(value)
		if err != nil {
			return policy{}, fmt.Errorf("INTERNAL_IP4_DNS entry %d: invalid IP address", i+1)
		}

		// OpenConnect exports IPv4 and IPv6 DNS in this same variable.
		if !ip.Is4() {
			continue
		}

		prefix := ip.String() + "/32"
		includes = append(includes, prefix)
		addRouteSource(includeSources, prefix, "DNS host")
	}

	result, err := makePolicy(includes, excludes)
	if err == nil {
		return result, nil
	}

	conflicts := make([]string, 0)

	for prefix, sources := range includeSources {
		excludedBy, ok := excludeSources[prefix]
		if !ok {
			continue
		}

		network, parseErr := netip.ParsePrefix(prefix)
		if parseErr != nil {
			return policy{}, err
		}

		conflicts = append(conflicts, fmt.Sprintf("/%d include=[%s] exclude=[%s]",
			network.Bits(), strings.Join(sources, ", "), strings.Join(excludedBy, ", ")))
	}

	if len(conflicts) == 0 {
		return policy{}, err
	}

	slices.Sort(conflicts)

	return policy{}, fmt.Errorf("%w; %s", err, strings.Join(conflicts, "; "))
}

func addRouteSource(sources map[string][]string, prefix, source string) {
	if !slices.Contains(sources[prefix], source) {
		sources[prefix] = append(sources[prefix], source)
	}
}
