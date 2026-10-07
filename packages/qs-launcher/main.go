package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"
	"unicode/utf8"
)

func arguments(argv []string) (bool, string, error) {
	if len(argv) == 0 {
		return false, "Applications", nil
	}

	if len(argv) == 1 && argv[0] == "--dmenu" {
		return true, "Select", nil
	}

	if len(argv) == 3 && argv[0] == "--dmenu" && argv[1] == "--prompt" {
		if len(argv[2]) > 1024 || !utf8.ValidString(argv[2]) {
			return false, "", errors.New("prompt exceeds 1024 bytes or is not valid UTF-8")
		}
		return true, argv[2], nil
	}

	return false, "", errors.New("usage: qs-launcher [--dmenu [--prompt TEXT]]")
}

func request(ctx context.Context, picker bool, prompt string, lines []string, output io.Writer) (int, error) {
	deadline := time.Now().Add(startTimeout)
	var conn *net.UnixConn
	for {
		path, err := controlPath()
		if err == nil {
			dialer := net.Dialer{Deadline: deadline}
			var channel net.Conn
			channel, err = dialer.DialContext(ctx, "unix", path)
			if err == nil {
				conn = channel.(*net.UnixConn)
				break
			}
		}

		if !errors.Is(err, syscall.ENOENT) && !errors.Is(err, syscall.ECONNREFUSED) {
			return 2, errors.New("launcher service is unavailable")
		}
		if !time.Now().Before(deadline) {
			return 2, errors.New("launcher service is unavailable")
		}

		select {
		case <-ctx.Done():
			return 1, ctx.Err()
		case <-time.After(50 * time.Millisecond):
		}
	}

	defer conn.Close()
	stop := context.AfterFunc(ctx, func() { conn.Close() })
	defer stop()

	if !sameUser(conn) {
		return 2, errors.New("launcher peer UID mismatch")
	}

	channel := newTransport(conn)
	admit, err := channel.receive(messageLimit, startTimeout)
	if err != nil {
		return 2, err
	}
	if stringField(admit, "type") == "error" {
		return 2, errors.New("launcher admission failed: another launcher is open or restarting")
	}

	id := stringField(admit, "id")
	version, valid := integer(admit["version"])
	if stringField(admit, "type") != "admit" || !valid || version != protocol || id == "" {
		return 2, errors.New("launcher service protocol mismatch")
	}

	sessionCtx, cancel := context.WithCancel(ctx)
	s := newSession(sessionCtx, channel, id, picker, prompt, lines)
	readerDone := make(chan struct{})
	go func() {
		defer close(readerDone)
		s.readUI(cancel)
	}()

	defer func() {
		cancel()
		conn.Close()
		<-readerDone
		s.stopJobs()
		s.lines = nil
		s.query, s.expression, s.prompt = "", "", ""
	}()

	code, index, err := s.run()
	if err != nil {
		return 2, err
	}

	if err := s.close(); err != nil {
		return 2, err
	}

	if picker && code == 0 {
		if index == nil || *index < 0 || *index >= int64(len(lines)) {
			return 2, errors.New("invalid selection index")
		}

		if _, err := io.WriteString(output, lines[*index]+"\n"); err != nil {
			return 2, errors.New("cannot write launcher selection")
		}
	}

	return code, nil
}

func runCLI(ctx context.Context, argv []string, input io.Reader, output io.Writer) (int, error) {
	picker, prompt, err := arguments(argv)
	if err != nil {
		return 2, err
	}

	lines := []string{}
	if picker {
		lines, err = records(input)
		if err != nil {
			return 2, err
		}
		if len(lines) == 0 {
			return 1, nil
		}
	}

	code, err := request(ctx, picker, prompt, lines, output)
	if ctx.Err() != nil {
		return 1, nil
	}

	return code, err
}

func main() {
	if err := syscall.Setrlimit(syscall.RLIMIT_CORE, &syscall.Rlimit{}); err != nil {
		fmt.Fprintln(os.Stderr, "qs-launcher: cannot disable core dumps")
		os.Exit(2)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	code, err := runCLI(ctx, os.Args[1:], os.Stdin, os.Stdout)
	if ctx.Err() != nil {
		code = 1
	} else if err != nil {
		fmt.Fprintln(os.Stderr, "qs-launcher: "+err.Error())
		code = 2
	}

	stop()
	os.Exit(code)
}
