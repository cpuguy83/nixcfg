package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestOSDArguments(t *testing.T) {
	for _, tc := range []struct {
		name  string
		event osdEvent
		args  []string
	}{
		{"success", brightnessEvent("DP-1", 42, nil),
			[]string{"DP-1", "42", ""}},
		{"zero", brightnessEvent("", 0, nil),
			[]string{"", "0", ""}},
		{"error", brightnessEvent("--screen ' $(false)\nDP-1", 99, errors.New("--read \"VCP\"\nfailed")),
			[]string{"--screen ' $(false)\nDP-1", "-1", "--read \"VCP\"\nfailed"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			want := append([]string{"-c", "bar", "ipc", "call", "--", "osd", "brightness"}, tc.args...)
			command := func(ctx context.Context, name string, args ...string) *exec.Cmd {
				if name != "qs" || !reflect.DeepEqual(args, want) {
					t.Fatalf("command = %q %q, want qs %q", name, args, want)
				}
				return osdTestCommand(ctx, "ok")
			}
			if err := sendOSD(tc.event, time.Second, command); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestOSDMonitorMapping(t *testing.T) {
	state := &DeviceState{
		Name: "card1-HDMI-A-1", Alias: []string{"HDMI-A-1"},
		cond: sync.NewCond(&sync.Mutex{}),
	}
	check := func(want string) {
		t.Helper()
		for _, err := range []error{nil, errors.New("hardware failed")} {
			if got := brightnessEvent(state.monitorTarget(), 50, err).Screen; got != want {
				t.Fatalf("screen = %q, want %q", got, want)
			}
		}
	}
	check("HDMI-A-1")
	state.SetMonitorAlias(" DP-1 ")
	check("DP-1") // Preserve the display target rather than the DDC back-channel.
	state.SetMonitorAlias("")
	state.Alias = nil
	check("card1-HDMI-A-1")
}

// Re-exec the test binary rather than invoking the live shell or a device.
func osdTestCommand(ctx context.Context, mode string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestOSDChild$")
	cmd.Env = append(os.Environ(), "BRIGHTNESS_OSD_TEST_CHILD="+mode, "GORACE=atexit_sleep_ms=0")
	return cmd
}

func TestOSDChild(t *testing.T) {
	switch os.Getenv("BRIGHTNESS_OSD_TEST_CHILD") {
	case "":
		return
	case "ok":
		fmt.Println("ok")
	case "reject":
		fmt.Println("Error: Invalid brightness value/message")
	case "fail":
		fmt.Fprintln(os.Stderr, "no shell instance")
		os.Exit(3)
	case "block":
		time.Sleep(10 * time.Second)
	}
	os.Exit(0)
}

func TestOSDDeliveryFailure(t *testing.T) {
	for _, tc := range []struct{ mode, want string }{
		{"fail", "no shell instance"},
		{"reject", "shell osd rejected brightness"},
		{"missing", "call shell osd"},
	} {
		t.Run(tc.mode, func(t *testing.T) {
			err := sendOSD(brightnessEvent("", 50, nil), time.Second, func(ctx context.Context, _ string, _ ...string) *exec.Cmd {
				if tc.mode == "missing" {
					return exec.CommandContext(ctx, "/nonexistent/nixcfg-osd-qs")
				}
				return osdTestCommand(ctx, tc.mode)
			})
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("expected %q, got %v", tc.want, err)
			}
		})
	}
}

func TestOSDDeadline(t *testing.T) {
	for _, timeout := range []time.Duration{50 * time.Millisecond, -time.Second} {
		start := time.Now()
		err := sendOSD(brightnessEvent("", 50, nil), timeout, func(ctx context.Context, _ string, _ ...string) *exec.Cmd {
			return osdTestCommand(ctx, "block")
		})
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("expected deadline failure, got %v", err)
		}
		if elapsed := time.Since(start); elapsed > time.Second {
			t.Fatalf("blocked command took %v", elapsed)
		}
	}
}

// Opt-in only: the caller must start the production endpoint in an isolated
// XDG runtime/config, never against the user's live bar.
func TestOSDProductionEndpoint(t *testing.T) {
	if os.Getenv("BRIGHTNESS_OSD_INTEGRATION") != "1" {
		t.Skip("requires isolated production endpoint")
	}
	for _, event := range []osdEvent{
		brightnessEvent("DP-1", 42, nil),
		brightnessEvent("", 0, nil),
		brightnessEvent("--screen ' $(false)\nDP-2", 99, errors.New("--read \"VCP\"\nfailed")),
	} {
		if err := sendOSD(event, time.Second, exec.CommandContext); err != nil {
			t.Fatal(err)
		}
		// The harness records received events, proving exact text preservation.
		data, err := exec.Command("qs", "-c", "bar", "ipc", "call", "probe", "last").Output()
		if err != nil {
			t.Fatal(err)
		}
		var got struct {
			Screen string
			Value  int
			Text   string
		}
		if err := json.Unmarshal(data, &got); err != nil {
			t.Fatal(err)
		}
		if got.Screen != event.Screen || got.Value != event.Value || got.Text != event.Text {
			t.Fatalf("received %s, want %+v", data, event)
		}
	}
	if err := sendOSD(brightnessEvent("DP-1", 101, nil), time.Second, exec.CommandContext); err == nil {
		t.Fatal("endpoint accepted out-of-range brightness")
	}
}
