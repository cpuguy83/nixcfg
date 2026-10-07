package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestSequentialRequestsPreserveExactOutput(t *testing.T) {
	listener := fakeUI(t, false)

	for index, want := range []string{"\n", " same \n", " same \n", "\x00\n", "last\n"} {
		done := startCLI(context.Background(), []string{"--dmenu"}, "\n same \n same \n\x00\nlast")
		id := strconv.Itoa(index + 1)
		ui, init := admitTest(t, listener, id)
		if init["picker"] != true || init["query"] != "" {
			t.Fatalf("picker initialization: %v", init)
		}

		sendTest(t, ui, message{"type": "ready", "id": id})
		sendTest(t, ui, message{"type": "select", "id": id, "index": index})
		if stringField(receiveTest(t, ui), "type") != "hide" {
			t.Fatal("selection did not request hide")
		}

		select {
		case <-done:
			t.Fatal("client completed before UI reset")
		default:
		}

		sendTest(t, ui, message{"type": "hidden", "id": id})
		result := awaitCLI(t, done)
		if result.err != nil || result.code != 0 || result.output != want {
			t.Fatalf("code=%d, output=%q, err=%v", result.code, result.output, result.err)
		}

		expectEOF(t, ui)
	}
}

func TestAdmissionPrecedesUpload(t *testing.T) {
	listener := fakeUI(t, false)
	done := startCLI(context.Background(), []string{"--dmenu"}, "x\n")
	ui := acceptTest(t, listener)

	ui.conn.SetReadDeadline(time.Now().Add(30 * time.Millisecond))
	var data [1]byte
	n, err := ui.conn.Read(data[:])
	var timeout net.Error
	if n != 0 || !errors.As(err, &timeout) || !timeout.Timeout() {
		t.Fatalf("client sent data before admission: n=%d, error=%v", n, err)
	}

	sendTest(t, ui, message{"type": "error", "message": "busy"})
	result := awaitCLI(t, done)
	if result.code != 2 || result.err == nil || result.output != "" {
		t.Fatalf("busy rejection: %+v", result)
	}
}

func TestAdmissionRejectsInvalidTypes(t *testing.T) {
	listener := fakeUI(t, false)

	for _, admit := range []message{
		{"type": "admit", "version": true, "id": "1"},
		{"type": "admit", "version": json.Number("1.0"), "id": "1"},
		{"type": "admit", "version": 1, "id": 1},
		{"type": "admit", "version": 2, "id": "1"},
		{"type": "admit", "version": 1, "id": ""},
	} {
		done := startCLI(context.Background(), []string{"--dmenu"}, "x\n")
		ui := acceptTest(t, listener)
		sendTest(t, ui, admit)

		result := awaitCLI(t, done)
		if result.code != 2 || result.err == nil || result.output != "" {
			t.Fatalf("invalid admission accepted: %+v", result)
		}
		ui.conn.Close()
	}
}

func TestStaleIDsCannotCompleteNextRequest(t *testing.T) {
	listener := fakeUI(t, false)
	previous := "old"

	for _, id := range []string{"1", "2"} {
		done := startCLI(context.Background(), []string{"--dmenu"}, "x\ny\n")
		ui, _ := admitTest(t, listener, id)

		sendTest(t, ui, message{"type": "select", "id": previous, "index": 1})
		sendTest(t, ui, message{"type": "ready", "id": id})
		sendTest(t, ui, message{"type": "cancel", "id": id})
		hideTest(t, ui, id)

		result := awaitCLI(t, done)
		if result.err != nil || result.code != 1 || result.output != "" {
			t.Fatalf("stale selection completed request: %+v", result)
		}

		expectEOF(t, ui)
		previous = id
	}
}

func TestNormalCancellationSavesRawQuery(t *testing.T) {
	listener := fakeUI(t, true)
	previous := ""

	for i, query := range []string{"  app \t ", ""} {
		done := startCLI(context.Background(), nil, "")
		id := strconv.Itoa(i + 1)
		ui, init := admitTest(t, listener, id)
		if init["query"] != previous {
			t.Fatalf("raw query not restored: %v", init["query"])
		}

		sendTest(t, ui, message{"type": "ready", "id": id})
		sendTest(t, ui, message{"type": "query", "id": id, "revision": 1, "text": "", "raw": query})
		sendTest(t, ui, message{"type": "cancel", "id": id})
		hideTest(t, ui, id)

		result := awaitCLI(t, done)
		if result.code != 1 || result.err != nil {
			t.Fatalf("cancel: %+v", result)
		}
		if got, err := readQuery(); err != nil || got != query {
			t.Fatalf("raw query: %q, %v", got, err)
		}

		expectEOF(t, ui)
		previous = query
	}
}

func TestSessionLossReapsJobsWithoutSaving(t *testing.T) {
	for _, interrupt := range []bool{false, true} {
		name := "socket EOF"
		if interrupt {
			name = "client interruption"
		}

		t.Run(name, func(t *testing.T) {
			listener := fakeUI(t, true)
			if err := saveQuery("previous"); err != nil {
				t.Fatal(err)
			}

			t.Setenv("QS_GO_TEST_HELPER", "1")
			t.Setenv("QS_LAUNCHER_QALC", os.Args[0])
			pidFile := filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), "child-pid")
			t.Setenv("QS_GO_TEST_PID", pidFile)

			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()

			done := startCLI(ctx, nil, "")
			ui, init := admitTest(t, listener, "1")
			if init["query"] != "previous" {
				t.Fatal("query not restored")
			}

			sendTest(t, ui, message{"type": "ready", "id": "1"})
			sendTest(t, ui, message{"type": "query", "id": "1", "revision": 1, "text": "next", "raw": "next"})
			sendTest(t, ui, message{"type": "calculate", "id": "1", "revision": 1})

			var pid int
			until(t, func() bool {
				data, err := os.ReadFile(pidFile)
				if err != nil {
					return false
				}
				pid, err = strconv.Atoi(string(data))
				return err == nil
			})

			if interrupt {
				cancel()
			} else {
				ui.conn.Close()
			}

			result := awaitCLI(t, done)
			wantCode := 2
			if interrupt {
				wantCode = 1
			}
			if result.code != wantCode || result.output != "" || (!interrupt && result.err == nil) {
				t.Fatalf("lost session: %+v", result)
			}
			if err := syscall.Kill(pid, 0); !errors.Is(err, syscall.ESRCH) {
				t.Fatalf("calculator not reaped: %v", err)
			}
			if got, err := readQuery(); err != nil || got != "previous" {
				t.Fatalf("abnormal exit saved query: %q, %v", got, err)
			}
		})
	}
}

func TestQueryRevisionInvalidatesResults(t *testing.T) {
	server, client := socketPair(t)
	s := newSession(context.Background(), newTransport(server), "request", false, "", nil)
	s.revision = 1
	result := "3"
	s.result = &result

	cleaned := make(chan struct{})
	s.calculator = startJob(context.Background(), func(ctx context.Context) jobResult {
		<-ctx.Done()
		close(cleaned)
		return jobResult{revision: 1, ok: true, text: "obsolete"}
	})
	defer s.stopJobs()

	if err := s.handle(message{"type": "query", "revision": json.Number("2"), "text": "", "raw": "app"}); err != nil {
		t.Fatal(err)
	}

	select {
	case <-cleaned:
	default:
		t.Fatal("query did not reap previous job")
	}
	if s.calculator != nil || s.result != nil || s.expression != "" {
		t.Fatal("query retained obsolete calculation")
	}

	if err := s.handle(message{"type": "copy", "revision": json.Number("1")}); err != nil {
		t.Fatal(err)
	}
	if stringField(receiveTest(t, newTransport(client)), "type") != "error" {
		t.Fatal("stale result accepted")
	}

	if err := s.handle(message{"type": "query", "revision": json.Number("2"), "text": "", "raw": ""}); err == nil {
		t.Fatal("non-monotonic revision accepted")
	}
	if err := s.handle(message{"type": "calculate", "revision": true}); err == nil {
		t.Fatal("boolean revision accepted")
	}
}

func TestCalculatorPublishesCurrentRevisionAndCopies(t *testing.T) {
	listener := fakeUI(t, true)
	t.Setenv("QS_GO_TEST_HELPER", "1")
	t.Setenv("QS_LAUNCHER_QALC", os.Args[0])
	t.Setenv("QS_LAUNCHER_COPY", os.Args[0])

	done := startCLI(context.Background(), nil, "")
	ui, _ := admitTest(t, listener, "1")
	sendTest(t, ui, message{"type": "ready", "id": "1"})
	sendTest(t, ui, message{"type": "query", "id": "1", "revision": 7, "text": "=1+2", "raw": "=1+2"})
	sendTest(t, ui, message{"type": "calculate", "id": "1", "revision": 7})

	result := receiveTest(t, ui)
	revision, _ := integer(result["revision"])
	if stringField(result, "type") != "result" || revision != 7 || result["ok"] != true || result["text"] != "3" {
		t.Fatalf("calculator response: %v", result)
	}

	sendTest(t, ui, message{"type": "copy", "id": "1", "revision": 7})
	hideTest(t, ui, "1")
	if result := awaitCLI(t, done); result.err != nil || result.code != 0 || result.output != "" {
		t.Fatalf("calculator copy: %+v", result)
	}
	if got, err := readQuery(); err != nil || got != "=1+2" {
		t.Fatalf("copied query not saved: %q, %v", got, err)
	}
}

func TestApplicationLaunchKeepsDesktopIDSeparate(t *testing.T) {
	listener := fakeUI(t, true)
	t.Setenv("QS_GO_TEST_HELPER", "1")
	t.Setenv("QS_LAUNCHER_UWSM", os.Args[0])

	done := startCLI(context.Background(), nil, "")
	ui, _ := admitTest(t, listener, "1")
	sendTest(t, ui, message{"type": "ready", "id": "1"})
	sendTest(t, ui, message{"type": "query", "id": "1", "revision": 1, "text": "", "raw": "nested"})
	sendTest(t, ui, message{"type": "launch", "id": "1", "desktopId": "nested-app.desktop"})
	hideTest(t, ui, "1")

	if result := awaitCLI(t, done); result.err != nil || result.code != 0 || result.output != "" {
		t.Fatalf("application handoff: %+v", result)
	}
	if got, err := readQuery(); err != nil || got != "nested" {
		t.Fatalf("launch query not saved: %q, %v", got, err)
	}
}

func TestPickerRejectsActions(t *testing.T) {
	s := newSession(context.Background(), nil, "1", true, "Pick", []string{"=1+2", "", " x "})

	for _, kind := range []string{"query", "calculate", "copy", "launch"} {
		if err := s.handle(message{"type": kind}); err == nil {
			t.Fatalf("picker accepted %s", kind)
		}
	}

	for _, index := range []any{true, "0", nil, json.Number("-1"), json.Number("3")} {
		if err := s.handle(message{"type": "select", "index": index}); err == nil {
			t.Fatalf("picker accepted index %v", index)
		}
	}
}

type cliResult struct {
	code   int
	output string
	err    error
}

func startCLI(ctx context.Context, args []string, input string) <-chan cliResult {
	done := make(chan cliResult, 1)
	go func() {
		var output bytes.Buffer
		code, err := runCLI(ctx, args, strings.NewReader(input), &output)
		done <- cliResult{code: code, output: output.String(), err: err}
	}()

	return done
}

func awaitCLI(t *testing.T, done <-chan cliResult) cliResult {
	t.Helper()

	select {
	case result := <-done:
		return result
	case <-time.After(2 * time.Second):
		t.Fatal("client did not finish")
		return cliResult{}
	}
}

func receiveTest(t *testing.T, channel *transport) message {
	t.Helper()

	m, err := channel.receive(uploadLimit, 2*time.Second)
	if err != nil {
		t.Fatal(err)
	}

	return m
}

func sendTest(t *testing.T, channel *transport, m message) {
	t.Helper()

	if err := channel.send(m, uploadLimit); err != nil {
		t.Fatal(err)
	}
}

func fakeUI(t *testing.T, state bool) *net.UnixListener {
	t.Helper()
	testRuntime(t, state)

	path, err := controlPath()
	if err != nil {
		t.Fatal(err)
	}
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0600); err != nil {
		listener.Close()
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })

	return listener
}

func acceptTest(t *testing.T, listener *net.UnixListener) *transport {
	t.Helper()
	listener.SetDeadline(time.Now().Add(2 * time.Second))

	conn, err := listener.AcceptUnix()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	if !sameUser(conn) {
		t.Fatal("same-UID peer rejected")
	}

	return newTransport(conn)
}

func admitTest(t *testing.T, listener *net.UnixListener, id string) (*transport, message) {
	t.Helper()

	ui := acceptTest(t, listener)
	sendTest(t, ui, message{"type": "admit", "version": 1, "id": id})
	init := receiveTest(t, ui)
	if stringField(init, "type") != "init" || stringField(init, "id") != id {
		t.Fatalf("invalid initialization: %v", init)
	}

	return ui, init
}

func hideTest(t *testing.T, ui *transport, id string) {
	t.Helper()

	hide := receiveTest(t, ui)
	if stringField(hide, "type") != "hide" || stringField(hide, "id") != id {
		t.Fatalf("invalid hide: %v", hide)
	}

	sendTest(t, ui, message{"type": "hidden", "id": id})
}

func expectEOF(t *testing.T, ui *transport) {
	t.Helper()
	ui.conn.SetReadDeadline(time.Now().Add(time.Second))

	if _, err := ui.reader.ReadByte(); err != io.EOF {
		t.Fatalf("client retained its connection: %v", err)
	}
	ui.conn.Close()
}
