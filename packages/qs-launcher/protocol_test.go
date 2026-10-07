package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestRecordsPreserveIdentity(t *testing.T) {
	for _, test := range []struct {
		name  string
		input string
		want  []string
	}{
		{"empty input", "", []string{}},
		{"blank row", "\n", []string{""}},
		{"trailing blank", "a\n\n", []string{"a", ""}},
		{"duplicates and whitespace", " x \nx\nx\n", []string{" x ", "x", "x"}},
		{"unterminated record", "\t\r\nlast", []string{"\t\r", "last"}},
		{"Unicode and NUL", "snowman \u2603\n\x00\n", []string{"snowman \u2603", "\x00"}},
	} {
		t.Run(test.name, func(t *testing.T) {
			got, err := records(strings.NewReader(test.input))
			if err != nil || !reflect.DeepEqual(got, test.want) {
				t.Fatalf("got %q, %v; want %q", got, err, test.want)
			}
		})
	}
}

func TestInputLimits(t *testing.T) {
	for _, test := range []struct {
		name  string
		data  string
		valid bool
	}{
		{"invalid UTF-8", "\xff", false},
		{"total at limit", strings.Repeat(strings.Repeat("x", lineLimit-1)+"\n", 64), true},
		{"total over limit", strings.Repeat("x", inputLimit+1), false},
		{"row at limit", strings.Repeat("x", lineLimit), true},
		{"row over limit", strings.Repeat("x", lineLimit+1), false},
		{"count at limit", strings.Repeat("\n", recordLimit), true},
		{"count over limit", strings.Repeat("\n", recordLimit+1), false},
	} {
		t.Run(test.name, func(t *testing.T) {
			_, err := records(strings.NewReader(test.data))
			if (err == nil) != test.valid {
				t.Fatalf("valid=%v, error=%v", test.valid, err)
			}
		})
	}
}

func TestPublicArguments(t *testing.T) {
	for _, args := range [][]string{nil, {"--dmenu"}, {"--dmenu", "--prompt", " x "}, {"--dmenu", "--prompt", strings.Repeat("x", 1024)}} {
		if _, _, err := arguments(args); err != nil {
			t.Fatal(err)
		}
	}

	for _, args := range [][]string{{"--bridge"}, {"--daemon"}, {"--help"}, {"--prompt", "x"}, {"--dmenu", "--prompt"}, {"--dmenu", "--prompt", strings.Repeat("x", 1025)}} {
		if _, _, err := arguments(args); err == nil {
			t.Fatal("accepted unsupported arguments")
		}
	}
}

func TestFramesAreBoundedAndStrict(t *testing.T) {
	for _, test := range []struct {
		name, raw string
		valid     bool
	}{
		{"object", "{\"type\":\"ready\"}\n", true},
		{"array", "[]\n", false},
		{"null", "null\n", false},
		{"two objects", "{}{}\n", false},
		{"bad UTF-8", "{\"text\":\"\xff\"}\n", false},
		{"lone surrogate", "{\"text\":\"\\ud800\"}\n", false},
		{"surrogate pair", "{\"text\":\"\\ud83d\\ude00\"}\n", true},
		{"escaped backslash", "{\"text\":\"\\\\ud800\"}\n", true},
		{"no LF", "{}", false},
		{"oversized frame", "{\"text\":\"" + strings.Repeat("x", messageLimit) + "\"}\n", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			server, client := socketPair(t)
			defer client.Close()

			done := make(chan struct{})
			go func() {
				defer close(done)
				defer server.Close()
				io.WriteString(server, test.raw)
			}()

			_, err := newTransport(client).receive(messageLimit, time.Second)
			client.Close()
			<-done

			if (err == nil) != test.valid {
				t.Fatalf("valid=%v, error=%v", test.valid, err)
			}
		})
	}
}

func TestUploadAllowsEscapedRecords(t *testing.T) {
	lines := make([]string, 64)
	for i := range lines {
		lines[i] = strings.Repeat("\x00", lineLimit-1)
	}

	m := message{"type": "init", "id": "1", "picker": true, "prompt": "Pick", "lines": lines, "query": ""}
	raw, err := json.Marshal(m)
	if err != nil || len(raw) <= inputLimit || len(raw) >= uploadLimit {
		t.Fatalf("unexpected escaped size %d: %v", len(raw), err)
	}

	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()

	if err := newTransport(server).send(message{"type": "result", "text": strings.Repeat("\x00", 12000)}, messageLimit); err == nil {
		t.Fatal("ordinary frame accepted upload-sized data")
	}
}

func TestCLIProducesNoOutputOnFailure(t *testing.T) {
	for _, test := range []struct {
		args  []string
		input string
		code  int
	}{
		{[]string{"--dmenu"}, "", 1},
		{[]string{"--dmenu"}, "\xff", 2},
		{[]string{"--bad"}, "", 2},
	} {
		var out bytes.Buffer
		code, err := runCLI(context.Background(), test.args, strings.NewReader(test.input), &out)
		if code != test.code || out.Len() != 0 || (err != nil) != (code == 2) {
			t.Fatalf("code=%d, output=%q, error=%v", code, &out, err)
		}
	}
}

func socketPair(t *testing.T) (net.Conn, net.Conn) {
	t.Helper()

	fds, err := syscall.Socketpair(syscall.AF_UNIX, syscall.SOCK_STREAM|syscall.SOCK_CLOEXEC, 0)
	if err != nil {
		t.Fatal(err)
	}

	var connections [2]net.Conn
	for i, fd := range fds {
		file := os.NewFile(uintptr(fd), "launcher-test-socket")
		defer file.Close()

		connections[i], err = net.FileConn(file)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { connections[i].Close() })
	}

	return connections[0], connections[1]
}

var testScratch string

func TestMain(m *testing.M) {
	if os.Getenv("QS_GO_TEST_HELPER") == "1" {
		os.Exit(helperProcess())
	}

	root := os.Getenv("TMPDIR")
	if root == "" {
		fmt.Fprintln(os.Stderr, "TMPDIR must be set for launcher tests")
		os.Exit(2)
	}

	var err error
	testScratch, err = os.MkdirTemp(root, "nixcfg-qs-go-tests.")
	if err != nil {
		fmt.Fprintln(os.Stderr, "cannot create launcher test scratch")
		os.Exit(2)
	}

	code := m.Run()

	if err := os.RemoveAll(testScratch); err != nil {
		fmt.Fprintln(os.Stderr, "cannot remove launcher test scratch")
		code = 1
	}

	os.Exit(code)
}

func testRuntime(t *testing.T, state bool) string {
	t.Helper()

	root, err := os.MkdirTemp(testScratch, "r")
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("XDG_RUNTIME_DIR", root)

	for _, directory := range []string{"qs-launcher-daemon", "qs-launcher"} {
		if directory == "qs-launcher" && !state {
			continue
		}

		if err := os.Mkdir(filepath.Join(root, directory), 0700); err != nil {
			t.Fatal(err)
		}
	}

	return root
}
