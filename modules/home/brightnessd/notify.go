package main

import (
	"context"
	"fmt"
	"log/slog"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

const notifyTimeout = 250 * time.Millisecond

// Only brightness crosses IPC; audio control stays inside the shell.
type osdEvent struct {
	Value  int
	Text   string
	Screen string
}

func brightnessEvent(mon string, val int, err error) osdEvent {
	event := osdEvent{Value: val, Screen: mon}
	if err != nil {
		event.Value = -1
		event.Text = err.Error()
	}
	return event
}

func notify(mon string, val int, operationErr error) {
	if err := sendOSD(brightnessEvent(mon, val, operationErr), notifyTimeout, exec.CommandContext); err != nil {
		// Display failure must never change the result of the hardware operation.
		slog.Error("could not show brightness osd", "screen", mon, "error", err)
	}
}

func sendOSD(event osdEvent, timeout time.Duration, command func(context.Context, string, ...string) *exec.Cmd) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	// No shell interpolation: even newlines, quotes and leading dashes are
	// single positional arguments. -- ends CLI option parsing.
	cmd := command(ctx, "qs", "-c", "bar", "ipc", "call", "--", "osd", "brightness",
		event.Screen, strconv.Itoa(event.Value), event.Text)
	// Bound inherited output pipes too if the child fails to close them.
	cmd.WaitDelay = 50 * time.Millisecond
	output, err := cmd.CombinedOutput()
	if ctx.Err() != nil {
		return fmt.Errorf("call shell osd: %w", ctx.Err())
	}
	if err != nil {
		return fmt.Errorf("call shell osd: %w: %s", err, strings.TrimSpace(string(output)))
	}
	if strings.TrimSpace(string(output)) != "ok" {
		return fmt.Errorf("shell osd rejected brightness: %s", strings.TrimSpace(string(output)))
	}
	return nil
}
