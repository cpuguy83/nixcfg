package main

import (
	"bytes"
	"context"
	"errors"
	"os/exec"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"
)

type boundedOutput struct {
	buffer   bytes.Buffer
	cancel   context.CancelFunc
	exceeded bool
}

func (output *boundedOutput) Write(data []byte) (int, error) {
	if output.buffer.Len()+len(data) > outputLimit {
		output.exceeded = true
		output.cancel()
		return 0, errors.New("command output exceeds 16 KiB")
	}

	return output.buffer.Write(data)
}

func processCommand(ctx context.Context, argv []string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		if errors.Is(err, syscall.ESRCH) {
			return nil
		}

		return err
	}
	cmd.WaitDelay = jobTimeout

	return cmd
}

func command(ctx context.Context, argv []string, data []byte, capture bool, timeout time.Duration) (int, []byte, []byte, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	cmd := processCommand(ctx, argv)
	out := &boundedOutput{cancel: cancel}
	diagnostic := &boundedOutput{cancel: cancel}
	if data != nil {
		cmd.Stdin = bytes.NewReader(data)
	}
	if capture {
		cmd.Stdout, cmd.Stderr = out, diagnostic
	}

	err := cmd.Run()
	if out.exceeded || diagnostic.exceeded {
		return 0, nil, nil, errors.New("command output exceeds 16 KiB")
	}
	if ctx.Err() != nil {
		return 0, nil, nil, errors.New("command canceled or timed out")
	}

	var exitError *exec.ExitError
	if err != nil && !errors.As(err, &exitError) {
		return 0, nil, nil, errors.New("command failed")
	}

	return cmd.ProcessState.ExitCode(), out.buffer.Bytes(), diagnostic.buffer.Bytes(), nil
}

func calculation(code int, out, diagnostic []byte) (bool, string) {
	if !utf8.Valid(out) || !utf8.Valid(diagnostic) {
		return false, "Calculator returned invalid UTF-8"
	}

	result, warning := strings.TrimSpace(string(out)), strings.TrimSpace(string(diagnostic))
	if code != 0 || warning != "" || result == "" || strings.Contains(result, "\n") {
		if warning != "" {
			return false, warning
		}
		if result != "" {
			return false, result
		}
		return false, "Calculation failed"
	}

	lower := strings.ToLower(result)
	if strings.HasPrefix(lower, "error:") || strings.HasPrefix(lower, "warning:") {
		return false, result
	}

	return true, result
}

type jobResult struct {
	revision int64
	ok       bool
	text     string
}

type job struct {
	cancel context.CancelFunc
	done   chan struct{}
	result chan jobResult
}

func startJob(ctx context.Context, work func(context.Context) jobResult) *job {
	ctx, cancel := context.WithCancel(ctx)
	job := &job{cancel: cancel, done: make(chan struct{}), result: make(chan jobResult, 1)}
	go func() {
		defer close(job.done)
		job.result <- work(ctx)
	}()

	return job
}

func stopJob(job **job) {
	if *job == nil {
		return
	}

	(*job).cancel()
	<-(*job).done
	*job = nil
}

func jobResults(job *job) <-chan jobResult {
	if job == nil {
		return nil
	}

	return job.result
}
