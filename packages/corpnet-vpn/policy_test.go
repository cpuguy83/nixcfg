package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"unicode/utf16"
)

func TestDottedMasks(t *testing.T) {
	for length := 0; length <= 32; length++ {
		t.Run(fmt.Sprintf("prefix %d accepts its netmask and hostmask", length), func(t *testing.T) {
			mask := net.CIDRMask(length, 32)
			prefix, err := network("0.0.0.0/"+net.IP(mask).String(), "test mask")
			requireNoError(t, err)

			requireEqual(t, prefix.Bits(), length)

			for i := range mask {
				mask[i] = ^mask[i]
			}

			expected := length

			// All-zero and all-one values are interpreted as netmasks first.
			if length == 0 || length == 32 {
				expected = 32 - length
			}

			prefix, err = network("0.0.0.0/"+net.IP(mask).String(), "test mask")
			requireNoError(t, err)

			requireEqual(t, prefix.Bits(), expected)
		})
	}

	t.Run("a broad hostmask retains nonzero network addresses", func(t *testing.T) {
		prefix, err := network("254.0.0.0/1.255.255.255", "test mask")
		requireNoError(t, err)

		requireEqual(t, prefix.String(), "254.0.0.0/7")
	})
}

func TestPolicy(t *testing.T) {
	t.Run("namespaces and case preserve both sections and deduplicate", func(t *testing.T) {
		data, err := xmlPolicy(strings.NewReader(testXML))
		requireNoError(t, err)

		requireEqual(t, data, testPolicy(t))

		data, err = xmlPolicy(strings.NewReader("\ufeff<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + testXML))
		requireNoError(t, err)

		requireEqual(t, data, testPolicy(t))

		data, err = xmlPolicy(strings.NewReader(strings.ReplaceAll(testXML, "route", "Route")))
		requireNoError(t, err)

		requireEqual(t, data, testPolicy(t))
	})

	t.Run("prefixes sort numerically by address then prefix length", func(t *testing.T) {
		data, err := makePolicy([]string{
			"203.0.113.128/25", "203.0.113.0/25", "203.0.113.0/24",
			"10.0.0.0/8", "2.0.0.0/8", "203.0.113.0/24",
		}, nil)
		requireNoError(t, err)

		requireEqual(t, data.Includes, []string{
			"2.0.0.0/8", "10.0.0.0/8", "203.0.113.0/24", "203.0.113.0/25", "203.0.113.128/25",
		})

		if data.Excludes == nil {
			t.Fatal("empty excludes must encode as an array")
		}
	})

	t.Run("dotted netmasks and hostmasks become canonical prefixes", func(t *testing.T) {
		for _, mask := range []string{"24", "255.255.255.0", "0.0.0.255", "024"} {
			t.Run(mask, func(t *testing.T) {
				data, err := xmlPolicy(strings.NewReader(strings.ReplaceAll(testXML, "<mask>24</mask>", "<mask>"+mask+"</mask>")))
				requireNoError(t, err)

				requireEqual(t, data, testPolicy(t))
			})

			t.Run("standard XML encodings retain profile compatibility", func(t *testing.T) {
				for _, order := range []binary.ByteOrder{binary.LittleEndian, binary.BigEndian} {
					text := `<?xml version="1.0" encoding="UTF-16"?>` + testXML

					units := utf16.Encode([]rune(text))

					content := make([]byte, 2+2*len(units))

					order.PutUint16(content, 0xfeff)

					for i, unit := range units {
						order.PutUint16(content[2+2*i:], unit)
					}

					for _, content := range [][]byte{content, content[2:]} {
						data, err := xmlPolicy(bytes.NewReader(content))
						requireNoError(t, err)

						requireEqual(t, data, testPolicy(t))
					}
				}

				for _, encoding := range []string{"ASCII", "US-ASCII", "ISO-8859-1"} {
					content := []byte(`<?xml version="1.0" encoding="` + encoding + `"?>` + testXML)

					if encoding == "ISO-8859-1" {
						content = bytes.Replace(content, []byte("<clientconfig>"),
							[]byte("<clientconfig><description>synthetic caf\xe9</description>"), 1)
					}

					data, err := xmlPolicy(bytes.NewReader(content))
					requireNoError(t, err)

					requireEqual(t, data, testPolicy(t))
				}

				for _, content := range [][]byte{
					{0xff, 0xfe, 0x3c}, {0xff, 0xfe, 0x00, 0xd8}, {0xfe, 0xff, 0xdc, 0, 0, 0x3c},
					[]byte(`<?xml version="1.0" encoding="ASCII"?>` + "<profile>caf\xe9</profile>"),
					[]byte(`<?xml version="1.0" encoding="unsupported-private"?>` + testXML),
				} {
					_, err := xmlPolicy(bytes.NewReader(content))
					requireError(t, err, "XML is malformed")
				}
			})
		}

		for value, want := range map[string]string{
			"0.0.0.0/0.0.0.0": "0.0.0.0/0", "192.0.2.1/255.255.255.255": "192.0.2.1/32",
			"192.0.2.1": "192.0.2.1/32",
		} {
			got, err := network(value, "synthetic")
			requireNoError(t, err)

			requireEqual(t, got.String(), want)
		}
	})

	t.Run("invalid XML preserves the previous policy without logging values", func(t *testing.T) {
		cases := map[string]string{
			"exclusions alone":   strings.ReplaceAll(testXML, "includeroutes", "unused"),
			"IPv6":               strings.ReplaceAll(testXML, "203.0.113.0", "2001:db8::"),
			"host bits":          strings.ReplaceAll(testXML, "203.0.113.0", "203.0.113.1"),
			"identical prefixes": strings.ReplaceAll(testXML, "198.51.100.0", "203.0.113.0"),
			"missing mask":       strings.ReplaceAll(testXML, "<mask>24</mask>", ""),
			"invalid mask":       strings.ReplaceAll(testXML, "<mask>24</mask>", "<mask>33</mask>"),
			"noncontiguous mask": strings.ReplaceAll(testXML, "<mask>24</mask>", "<mask>255.0.255.0</mask>"),
			"duplicate field":    strings.ReplaceAll(testXML, "<mask>24</mask>", "<mask>24</mask><mask>24</mask>"),
			"unknown field":      strings.ReplaceAll(testXML, "<mask>24</mask>", "<mask>24</mask><private>hidden</private>"),
			"nested field":       strings.ReplaceAll(testXML, "<mask>24</mask>", "<mask><value>24</value></mask>"),
			"unknown entry":      strings.ReplaceAll(testXML, "<route>", "<entry>"),
			"malformed":          "<profile>",
			"multiple roots":     testXML + "<other/>",
			"trailing content":   testXML + "private trailing content",
			"leading content":    "private leading content" + testXML,
		}

		for name, text := range cases {
			t.Run(name, func(t *testing.T) {
				dir := t.TempDir()

				path, output := filepath.Join(dir, "profile.xml"), filepath.Join(dir, "policy.json")

				writeTestFile(t, path, text)

				writeTestFile(t, output, "previous policy")

				var logs bytes.Buffer

				command := cli{output: &logs, errors: &logs}

				status := command.run([]string{"import", path, "--output", output})

				requireEqual(t, status, 1)
				requireEqual(t, readTestFile(t, output), "previous policy")

				for _, private := range []string{"203.0.113", "2001:db8", "hidden", "private trailing"} {
					if strings.Contains(logs.String(), private) {
						t.Fatal("private value logged")
					}
				}
			})
		}
	})

	t.Run("JSON requires exact fields types and canonical CIDRs", func(t *testing.T) {
		for _, content := range []string{
			`[]`, `null`, `{}`, `{"version":1,"includes":["203.0.113.0/24"]}`,
			`{"version":1,"includes":["203.0.113.0/24"],"excludes":[],"token":"private"}`,
			`{"version":"1","includes":["203.0.113.0/24"],"excludes":[]}`,
			`{"version":true,"includes":["203.0.113.0/24"],"excludes":[]}`,
			`{"version":1.0,"includes":["203.0.113.0/24"],"excludes":[]}`,
			`{"version":2,"includes":["203.0.113.0/24"],"excludes":[]}`,
			`{"version":1,"includes":null,"excludes":[]}`,
			`{"version":1,"includes":["203.0.113.0/24"],"excludes":null}`,
			`{"version":1,"includes":[3],"excludes":[]}`,
			`{"version":1,"includes":[],"excludes":[]}`,
			`{"version":1,"includes":["203.0.113.0/255.255.255.0"],"excludes":[]}`,
			`{"version":1,"includes":["203.0.113.1"],"excludes":[]}`,
			`{"version":1,"includes":["203.0.113.0/24"],"excludes":[]} true`,
		} {
			if _, err := jsonPolicy([]byte(content)); err == nil {
				t.Fatalf("accepted invalid policy: %s", content)
			}
		}

		data, err := jsonPolicy([]byte(`{"excludes": [], "includes": ["203.0.113.0/24"], "version": 1}`))
		requireNoError(t, err)

		requireEqual(t, data.Includes, []string{"203.0.113.0/24"})
	})
}

func TestServerPolicy(t *testing.T) {
	t.Run("server prefixes merge before conflict validation", func(t *testing.T) {
		env := map[string]string{
			"CISCO_SPLIT_INC": "1", "CISCO_SPLIT_EXC": "1",
			"CISCO_SPLIT_INC_0_ADDR": "203.0.113.128", "CISCO_SPLIT_INC_0_MASKLEN": "25",
			"CISCO_SPLIT_INC_0_MASK": "255.255.255.128",
			"CISCO_SPLIT_EXC_0_ADDR": "198.51.100.128", "CISCO_SPLIT_EXC_0_MASK": "255.255.255.128",
		}

		data, err := serverPolicy(testPolicy(t), env)
		requireNoError(t, err)

		requireEqual(t, len(data.Includes), 2)
		requireEqual(t, len(data.Excludes), 2)

		env["CISCO_SPLIT_EXC_0_ADDR"] = "203.0.113.128"

		_, err = serverPolicy(testPolicy(t), env)
		requireError(t, err, "identical")
	})

	t.Run("invalid server fields fail instead of being discarded", func(t *testing.T) {
		for _, env := range []map[string]string{
			{"CISCO_SPLIT_INC": "-1"}, {"CISCO_SPLIT_INC": ""}, {"CISCO_SPLIT_EXC": "1"},
			{"CISCO_SPLIT_INC": "1", "CISCO_SPLIT_INC_0_ADDR": "203.0.113.0",
				"CISCO_SPLIT_INC_0_MASKLEN": "24", "CISCO_SPLIT_INC_0_MASK": "255.255.0.0"},
		} {
			if _, err := serverPolicy(testPolicy(t), env); err == nil {
				t.Fatal("accepted invalid server fields")
			}
		}
	})

	t.Run("pushed DNS becomes deduplicated tunnel host routes", func(t *testing.T) {
		data, err := serverPolicy(testPolicy(t), map[string]string{"INTERNAL_IP4_DNS": "198.51.100.53  192.0.2.53 198.51.100.53"})
		requireNoError(t, err)

		requireEqual(t, data.Includes, []string{"192.0.2.53/32", "198.51.100.53/32", "203.0.113.0/24"})
	})

	t.Run("mixed-family DNS adds only IPv4 host routes", func(t *testing.T) {
		data, err := serverPolicy(testPolicy(t), map[string]string{
			"INTERNAL_IP4_DNS": "2001:db8::53 198.51.100.53 2001:db8::54",
		})
		requireNoError(t, err)

		requireEqual(t, data.Includes, []string{"198.51.100.53/32", "203.0.113.0/24"})
	})

	t.Run("IPv6-only DNS leaves the IPv4 policy unchanged", func(t *testing.T) {
		data, err := serverPolicy(testPolicy(t), map[string]string{
			"INTERNAL_IP4_DNS": "2001:db8::53 2001:db8::54",
		})
		requireNoError(t, err)

		requireEqual(t, data, testPolicy(t))
	})

	t.Run("conflicts report all sources without exposing addresses", func(t *testing.T) {
		data, err := makePolicy([]string{"203.0.113.0/24"}, []string{"198.51.100.53/32"})
		requireNoError(t, err)

		_, err = serverPolicy(data, map[string]string{
			"CISCO_SPLIT_INC":           "2",
			"CISCO_SPLIT_INC_0_ADDR":    "198.51.100.53",
			"CISCO_SPLIT_INC_0_MASKLEN": "32",
			"CISCO_SPLIT_INC_1_ADDR":    "198.51.100.53",
			"CISCO_SPLIT_INC_1_MASKLEN": "32",
			"CISCO_SPLIT_EXC":           "1",
			"CISCO_SPLIT_EXC_0_ADDR":    "198.51.100.53",
			"CISCO_SPLIT_EXC_0_MASKLEN": "32",
			"INTERNAL_IP4_DNS":          "198.51.100.53",
		})
		requireError(t, err, "1 identical")
		requireError(t, err, "/32 include=[gateway split, DNS host] exclude=[gateway split]")

		if strings.Contains(err.Error(), "198.51.100.53") {
			t.Fatal("conflict diagnostic exposed a private address")
		}
	})

	t.Run("gateway rules override exact profile conflicts in both directions", func(t *testing.T) {
		data, err := makePolicy(
			[]string{"192.0.2.0/24", "203.0.113.0/24"},
			[]string{"198.51.100.53/32"},
		)
		requireNoError(t, err)

		result, err := serverPolicy(data, map[string]string{
			"CISCO_SPLIT_INC":           "1",
			"CISCO_SPLIT_INC_0_ADDR":    "198.51.100.53",
			"CISCO_SPLIT_INC_0_MASKLEN": "32",
			"CISCO_SPLIT_EXC":           "1",
			"CISCO_SPLIT_EXC_0_ADDR":    "203.0.113.0",
			"CISCO_SPLIT_EXC_0_MASKLEN": "24",
		})
		requireNoError(t, err)

		requireEqual(t, result.Includes, []string{"192.0.2.0/24", "198.51.100.53/32"})
		requireEqual(t, result.Excludes, []string{"203.0.113.0/24"})
	})

	t.Run("unequal overlapping prefixes keep their original routing semantics", func(t *testing.T) {
		data, err := makePolicy(
			[]string{"203.0.113.0/24"},
			[]string{"198.51.100.128/25"},
		)
		requireNoError(t, err)

		result, err := serverPolicy(data, map[string]string{
			"CISCO_SPLIT_INC":           "1",
			"CISCO_SPLIT_INC_0_ADDR":    "198.51.100.0",
			"CISCO_SPLIT_INC_0_MASKLEN": "24",
			"CISCO_SPLIT_EXC":           "1",
			"CISCO_SPLIT_EXC_0_ADDR":    "203.0.113.128",
			"CISCO_SPLIT_EXC_0_MASKLEN": "25",
		})
		requireNoError(t, err)

		requireEqual(t, result.Includes, []string{"198.51.100.0/24", "203.0.113.0/24"})
		requireEqual(t, result.Excludes, []string{"198.51.100.128/25", "203.0.113.128/25"})
	})

	t.Run("pushed DNS validates addresses and exact conflicts", func(t *testing.T) {
		data, err := makePolicy([]string{"203.0.113.0/24"}, []string{"198.51.100.53/32"})
		requireNoError(t, err)

		for value, message := range map[string]string{
			"198.51.100.53": "identical", "192.0.2.53/32": "invalid IP address",
			"not-an-address": "invalid IP address", "2001:db8::53 malformed": "invalid IP address",
		} {
			_, err := serverPolicy(data, map[string]string{"INTERNAL_IP4_DNS": value})
			requireError(t, err, message)
		}
	})
}

const testXML = `<AzureVPNProfile xmlns="urn:synthetic"><clientconfig>
<includeroutes>
<route><destination>203.0.113.0</destination><mask>24</mask></route>
<route><destination>203.0.113.0</destination><mask>24</mask></route>
</includeroutes>
<excluderoutes><route><destination>198.51.100.0</destination><mask>24</mask></route></excluderoutes>
</clientconfig></AzureVPNProfile>`

func testPolicy(t *testing.T) policy {
	t.Helper()

	data, err := makePolicy([]string{"203.0.113.0/24"}, []string{"198.51.100.0/24"})
	requireNoError(t, err)

	return data
}

func requireNoError(t *testing.T, err error) {
	t.Helper()

	if err != nil {
		t.Fatal(err)
	}
}

func requireError(t *testing.T, err error, contains string) {
	t.Helper()

	if err == nil || !strings.Contains(err.Error(), contains) {
		t.Fatalf("expected error containing %q, got %v", contains, err)
	}
}

func requireEqual(t *testing.T, actual, expected any) {
	t.Helper()

	if !reflect.DeepEqual(actual, expected) {
		t.Fatalf("got %#v, want %#v", actual, expected)
	}
}

func writeTestFile(t *testing.T, path, content string) {
	t.Helper()

	requireNoError(t, os.WriteFile(path, []byte(content), 0600))
}

func readTestFile(t *testing.T, path string) string {
	t.Helper()

	content, err := os.ReadFile(path)
	requireNoError(t, err)

	return string(content)
}

func encodeTestJSON(t *testing.T, value any) []byte {
	t.Helper()

	content, err := json.Marshal(value)
	requireNoError(t, err)

	return content
}
