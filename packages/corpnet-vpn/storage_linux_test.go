package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

func TestStateCompatibility(t *testing.T) {
	t.Run("Python version one state loads without migration", func(t *testing.T) {
		content := `{
			"version": 1,
			"owner": {"pid": 123, "start": "456", "boot": "synthetic-boot", "tun": "tun0"},
			"baseline": [
				{"dst": "default", "gateway": "192.0.2.1", "dev": "eth0", "metric": "100",
				 "protocol": "16", "flags": [], "unknown": {"large": 12345678901234567890}},
				{"dst": "10.0.0.0/8", "type": "blackhole", "nexthops": [{"dev": "eth1"}]}
			],
			"owned": [
				{"dst": "203.0.113.0/24", "dev": "tun0", "metric": 0, "scope": 253, "protocol": 242, "flags": []},
				{"dst": "198.51.100.0/24", "dev": "eth0", "gateway": "192.0.2.1", "prefsrc": "192.0.2.10",
				 "metric": 100, "scope": 0, "protocol": 242, "flags": ["onlink"]}
			],
			"transaction": null
		}`

		saved, err := decodeState([]byte(content))
		requireNoError(t, err)

		requireEqual(t, saved.Owner, testOwner)
		requireEqual(t, saved.Owned[0].Flags, []string{})
		requireEqual(t, saved.Owned[0].Gateway, "")
		requireEqual(t, saved.Owned[0].Prefsrc, "")
		requireEqual(t, saved.Baseline[0]["metric"], "100")
		requireEqual(t, saved.Baseline[0]["unknown"].(map[string]any)["large"], json.Number("12345678901234567890"))

		want, err := decodeJSON([]byte(content), "synthetic")
		requireNoError(t, err)

		requireJSONEqual(t, saved, want)

		saved.Transaction = &transaction{[]route{}, saved.Owned}

		reloaded, err := decodeState(encodeTestJSON(t, saved))
		requireNoError(t, err)

		requireEqual(t, reloaded.Transaction.Before, []route{})
		requireEqual(t, reloaded.Transaction.After, saved.Owned)
	})

	t.Run("state schema requires exact fields and strict types", func(t *testing.T) {
		base := &state{Version: 1, Owner: testOwner, Baseline: testBaseline(), Owned: mustDesired(t, testPolicy(t), testBaseline())}
		cases := []struct {
			name   string
			change func(map[string]any)
		}{
			{"unknown field", func(m map[string]any) {
				m["extra"] = true
			}},
			{"missing transaction", func(m map[string]any) {
				delete(m, "transaction")
			}},
			{"string version", func(m map[string]any) {
				m["version"] = "1"
			}},
			{"boolean version", func(m map[string]any) {
				m["version"] = true
			}},
			{"float version", func(m map[string]any) {
				m["version"] = json.Number("1.0")
			}},
			{"null baseline", func(m map[string]any) {
				m["baseline"] = nil
			}},
			{"scalar baseline row", func(m map[string]any) {
				m["baseline"] = []any{true}
			}},
			{"invalid baseline prefix", func(m map[string]any) {
				m["baseline"] = []any{routeRow{"dst": "192.0.2.1/24"}}
			}},
			{"null ownership", func(m map[string]any) {
				m["owned"] = nil
			}},
			{"invalid transaction", func(m map[string]any) {
				m["transaction"] = map[string]any{"before": []any{}}
			}},
			{"null transaction routes", func(m map[string]any) {
				m["transaction"] = map[string]any{"before": nil, "after": []any{}}
			}},
		}

		for _, test := range cases {
			t.Run(test.name, func(t *testing.T) {
				value, err := decodeJSON(encodeTestJSON(t, base), "synthetic")
				requireNoError(t, err)

				object := value.(map[string]any)

				test.change(object)

				if _, err := decodeState(encodeTestJSON(t, object)); err == nil {
					t.Fatal("accepted invalid state")
				}
			})
		}

		for _, test := range []struct {
			key   string
			value any
		}{
			{"pid", "123"}, {"pid", true}, {"pid", json.Number("123.0")}, {"pid", 0}, {"pid", -1},
			{"start", 456}, {"start", ""}, {"start", "-1"}, {"boot", 3}, {"tun", "unsafe\nname"},
		} {
			value, err := decodeJSON(encodeTestJSON(t, base), "synthetic")
			requireNoError(t, err)

			object := value.(map[string]any)
			object["owner"].(map[string]any)[test.key] = test.value

			if _, err := decodeState(encodeTestJSON(t, object)); err == nil {
				t.Fatalf("accepted invalid owner %s", test.key)
			}
		}
	})

	t.Run("owned descriptors must be canonical protocol 242 with array flags", func(t *testing.T) {
		original := mustDesired(t, testPolicy(t), testBaseline())[0]

		for _, test := range []struct {
			name   string
			change func(map[string]any)
		}{
			{"missing metric", func(m map[string]any) {
				delete(m, "metric")
			}},
			{"missing flags", func(m map[string]any) {
				delete(m, "flags")
			}},
			{"null flags", func(m map[string]any) {
				m["flags"] = nil
			}},
			{"informational flags", func(m map[string]any) {
				m["flags"] = []string{"linkdown"}
			}},
			{"duplicate flags", func(m map[string]any) {
				m["flags"] = []string{"onlink", "onlink"}
			}},
			{"string metric", func(m map[string]any) {
				m["metric"] = "0"
			}},
			{"string protocol", func(m map[string]any) {
				m["protocol"] = "242"
			}},
			{"float scope", func(m map[string]any) {
				m["scope"] = json.Number("253.0")
			}},
			{"foreign protocol", func(m map[string]any) {
				m["protocol"] = 4
			}},
			{"extra table", func(m map[string]any) {
				m["table"] = "main"
			}},
			{"extra type", func(m map[string]any) {
				m["type"] = "unicast"
			}},
			{"empty gateway", func(m map[string]any) {
				m["gateway"] = ""
			}},
			{"null source", func(m map[string]any) {
				m["prefsrc"] = nil
			}},
			{"host destination", func(m map[string]any) {
				m["dst"] = "203.0.113.1"
			}},
		} {
			t.Run(test.name, func(t *testing.T) {
				value, err := decodeJSON(encodeTestJSON(t, original), "synthetic")
				requireNoError(t, err)

				row := value.(map[string]any)

				test.change(row)

				if _, err := decodeOwned([]any{row}); err == nil {
					t.Fatal("accepted noncanonical owned route")
				}
			})
		}
	})
}

func TestAtomicStorage(t *testing.T) {
	t.Run("atomic policy writes retain mode and schema", func(t *testing.T) {
		dir := t.TempDir()

		path := filepath.Join(dir, "policy.json")

		writeTestFile(t, path, "previous policy")

		requireNoError(t, atomicJSON(path, testPolicy(t), 0644, false))

		actual, err := loadPolicy(path)
		requireNoError(t, err)

		requireEqual(t, actual, testPolicy(t))

		info, err := os.Stat(path)
		requireNoError(t, err)

		requireEqual(t, info.Mode().Perm(), os.FileMode(0644))

		entries, err := os.ReadDir(dir)
		requireNoError(t, err)

		requireEqual(t, len(entries), 1)

		if !strings.HasSuffix(readTestFile(t, path), "\n") {
			t.Fatal("missing JSON line terminator")
		}
	})

	t.Run("encoding failure preserves the destination and removes only its temporary", func(t *testing.T) {
		dir := t.TempDir()

		path := filepath.Join(dir, "policy.json")

		writeTestFile(t, path, "previous policy")

		if err := atomicJSON(path, make(chan int), 0644, false); err == nil {
			t.Fatal("expected encoding failure")
		}

		requireEqual(t, readTestFile(t, path), "previous policy")

		entries, err := os.ReadDir(dir)
		requireNoError(t, err)

		requireEqual(t, len(entries), 1)
	})

	t.Run("failed replacement leaves existing contents intact", func(t *testing.T) {
		dir := t.TempDir()

		destination := filepath.Join(dir, "destination")
		requireNoError(t, os.Mkdir(destination, 0700))

		writeTestFile(t, filepath.Join(destination, "previous"), "previous policy")

		if err := atomicJSON(destination, testPolicy(t), 0644, false); err == nil {
			t.Fatal("expected rename failure")
		}

		requireEqual(t, readTestFile(t, filepath.Join(destination, "previous")), "previous policy")

		entries, err := os.ReadDir(dir)
		requireNoError(t, err)

		requireEqual(t, len(entries), 1)
	})

	t.Run("root owned writes enforce ownership", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "policy.json")

		writeTestFile(t, path, "previous policy")

		err := atomicJSON(path, testPolicy(t), 0644, true)

		if os.Geteuid() != 0 {
			if err == nil {
				t.Fatal("unprivileged root ownership unexpectedly succeeded")
			}

			requireEqual(t, readTestFile(t, path), "previous policy")

			return
		}

		requireNoError(t, err)

		info, err := os.Stat(path)
		requireNoError(t, err)

		stat := info.Sys().(*syscall.Stat_t)

		requireEqual(t, stat.Uid, uint32(0))
		requireEqual(t, stat.Gid, uint32(0))
	})
}

func TestCandidate(t *testing.T) {
	t.Run("only owned regular files are read", func(t *testing.T) {
		dir := t.TempDir()

		path := filepath.Join(dir, "candidate")
		requireNoError(t, atomicJSON(path, testPolicy(t), 0600, false))

		data, err := readCandidate(path, os.Getuid(), maxBytes)
		requireNoError(t, err)

		requireEqual(t, data, testPolicy(t))

		_, err = readCandidate(path, os.Getuid()+1, maxBytes)
		requireError(t, err, "owned")
		requireNoError(t, os.Symlink(path, filepath.Join(dir, "symlink")))
		requireNoError(t, syscall.Mkfifo(filepath.Join(dir, "fifo"), 0600))

		for _, name := range []string{"symlink", "fifo", "."} {
			if _, err := readCandidate(filepath.Join(dir, name), os.Getuid(), maxBytes); err == nil {
				t.Fatalf("accepted %s candidate", name)
			}
		}
	})

	t.Run("candidate size limits include the complete read", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "candidate")

		content := encodeTestJSON(t, testPolicy(t))

		writeTestFile(t, path, string(content))

		_, err := readCandidate(path, os.Getuid(), int64(len(content)))
		requireNoError(t, err)

		_, err = readCandidate(path, os.Getuid(), int64(len(content)-1))
		requireError(t, err, "exceeds")
	})

	t.Run("invalid candidate JSON is never treated as a policy", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "candidate")

		for _, content := range []string{`invalid`, `[]`, `{"version":1}`, `{"accessToken":"private"}`} {
			writeTestFile(t, path, content)

			_, err := readCandidate(path, os.Getuid(), maxBytes)
			if err == nil {
				t.Fatal("accepted invalid candidate")
			}

			if strings.Contains(err.Error(), "private") {
				t.Fatal("candidate value leaked")
			}
		}
	})
}

func TestRuntimeLock(t *testing.T) {
	t.Run("runtime directories must be private and root owned", func(t *testing.T) {
		directory := filepath.Join(t.TempDir(), "runtime")
		requireNoError(t, os.Mkdir(directory, 0755))

		lock, err := sessionLock(directory)
		if lock != nil {
			lock.Close()
		}

		requireError(t, err, "root-owned and mode 0700")
		requireNoError(t, os.Chmod(directory, 0700))

		lock, err = sessionLock(directory)

		if os.Geteuid() != 0 {
			requireError(t, err, "root-owned")

			return
		}

		requireNoError(t, err)
		defer lock.Close()

		info, err := lock.Stat()
		requireNoError(t, err)

		requireEqual(t, info.Mode().Perm(), os.FileMode(0600))

		other, err := os.OpenFile(filepath.Join(directory, "lock"), os.O_WRONLY, 0)
		requireNoError(t, err)
		defer other.Close()

		if err := syscall.Flock(int(other.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != syscall.EWOULDBLOCK {
			t.Fatalf("expected exclusive lock contention, got %v", err)
		}

		requireNoError(t, lock.Close())
		requireNoError(t, syscall.Flock(int(other.Fd()), syscall.LOCK_EX|syscall.LOCK_NB))
	})

	t.Run("unsafe runtime failures are reported without file contents", func(t *testing.T) {
		var output bytes.Buffer

		report(&output, &os.PathError{Op: "open", Path: "/private/value", Err: syscall.EACCES})

		if strings.Contains(output.String(), "/private/value") {
			t.Fatal("path leaked")
		}
	})
}
