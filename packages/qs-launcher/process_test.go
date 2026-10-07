package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestCalculatorDecoding(t *testing.T) {
	for _, test := range []struct {
		name            string
		code            int
		out, diagnostic string
		ok              bool
	}{
		{"conversion", 0, "200 cm\n", "", true},
		{"symbolic", 0, "x", "", true},
		{"exit failure", 1, "partial", "", false},
		{"stderr warning", 0, "3", "warning", false},
		{"multiline", 0, "Warning: approximate\n3", "", false},
		{"diagnostic", 0, "ERROR: invalid", "", false},
		{"empty", 0, "", "", false},
		{"invalid encoding", 0, "\xff", "", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			ok, _ := calculation(test.code, []byte(test.out), []byte(test.diagnostic))
			if ok != test.ok {
				t.Fatalf("copyable=%v, want %v", ok, test.ok)
			}
		})
	}
}

func TestSubprocessLimits(t *testing.T) {
	t.Setenv("QS_GO_TEST_HELPER", "1")

	for _, stream := range []string{"stdout", "stderr"} {
		t.Run(stream+" over limit", func(t *testing.T) {
			_, _, _, err := command(context.Background(), []string{os.Args[0], stream, "16385"}, nil, true, jobTimeout)
			if err == nil || !strings.Contains(err.Error(), "exceeds") {
				t.Fatalf("output bound: %v", err)
			}
		})
	}

	code, out, diagnostic, err := command(context.Background(), []string{os.Args[0], "stdout", "16384"}, nil, true, jobTimeout)
	if err != nil || code != 0 || len(out) != outputLimit || len(diagnostic) != 0 {
		t.Fatalf("exact output limit: code=%d, out=%d, err=%v", code, len(out), err)
	}
}

func TestSubprocessCancellationReaps(t *testing.T) {
	t.Setenv("QS_GO_TEST_HELPER", "1")

	for _, cancelEarly := range []bool{false, true} {
		t.Run(fmt.Sprintf("explicit cancellation %v", cancelEarly), func(t *testing.T) {
			root := testRuntime(t, false)
			pidFile := filepath.Join(root, "child-pid")
			t.Setenv("QS_GO_TEST_PID", pidFile)

			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()

			done := make(chan error, 1)
			timeout := 150 * time.Millisecond
			if cancelEarly {
				timeout = jobTimeout
			}

			go func() {
				_, _, _, err := command(ctx, []string{os.Args[0], "sleep"}, nil, true, timeout)
				done <- err
			}()

			var pid int
			until(t, func() bool {
				data, err := os.ReadFile(pidFile)
				if err != nil {
					return false
				}

				pid, err = strconv.Atoi(string(data))
				return err == nil
			})

			if cancelEarly {
				cancel()
			}

			if err := <-done; err == nil {
				t.Fatal("unfinished child reported success")
			}
			if err := syscall.Kill(pid, 0); !errors.Is(err, syscall.ESRCH) {
				t.Fatalf("child not reaped: %v", err)
			}
		})
	}
}

func TestCopyHandoffUsesStdin(t *testing.T) {
	t.Setenv("QS_GO_TEST_HELPER", "1")

	code, _, _, err := command(context.Background(), []string{os.Args[0], "stdin"}, []byte("200 cm"), false, jobTimeout)
	if err != nil || code != 0 {
		t.Fatalf("clipboard handoff: code=%d, error=%v", code, err)
	}
}

func helperProcess() int {
	if len(os.Args) < 2 {
		return 2
	}

	switch os.Args[1] {
	case "stdout", "stderr":
		size, err := strconv.Atoi(os.Args[2])
		if err != nil {
			return 2
		}

		var output io.Writer = os.Stdout
		if os.Args[1] == "stderr" {
			output = os.Stderr
		}

		_, err = io.WriteString(output, strings.Repeat("x", size))
		if err != nil {
			return 2
		}

	case "sleep":
		return helperSleep()

	case "stdin":
		data, err := io.ReadAll(os.Stdin)
		if err != nil || string(data) != "200 cm" {
			return 2
		}

	case "--type":
		data, err := io.ReadAll(os.Stdin)
		if err != nil || string(data) != "3" || strings.Join(os.Args[1:], " ") != "--type text/plain;charset=utf-8" {
			return 2
		}

	case "--defaults":
		if os.Getenv("QS_GO_TEST_PID") != "" {
			return helperSleep()
		}
		fmt.Fprintln(os.Stdout, "3")

	case "app":
		if strings.Join(os.Args[1:], " ") != "app -t service -- nested-app.desktop.desktop" {
			return 2
		}

	default:
		return 2
	}

	return 0
}

func helperSleep() int {
	if err := os.WriteFile(os.Getenv("QS_GO_TEST_PID"), []byte(strconv.Itoa(os.Getpid())), 0600); err != nil {
		return 2
	}

	time.Sleep(30 * time.Second)
	return 0
}

func until(t *testing.T, ready func() bool) {
	t.Helper()

	deadline := time.Now().Add(2 * time.Second)
	for !ready() {
		if time.Now().After(deadline) {
			t.Fatal("test condition timed out")
		}

		time.Sleep(time.Millisecond)
	}
}
