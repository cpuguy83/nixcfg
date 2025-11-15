package main

import (
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"os"
	"strconv"
	"time"
)

const systemdFdStart = 3

func activatedListener() (net.Listener, error) {
	listenPid := os.Getenv("LISTEN_PID")
	listenFds := os.Getenv("LISTEN_FDS")
	if listenPid == "" || listenFds == "" {
		return nil, nil
	}

	defer func() {
		os.Unsetenv("LISTEN_PID")
		os.Unsetenv("LISTEN_FDS")
	}()

	pid, err := strconv.Atoi(listenPid)
	if err != nil {
		return nil, fmt.Errorf("invalid LISTEN_PID: %w", err)
	}
	if pid != os.Getpid() {
		return nil, nil
	}

	fdCount, err := strconv.Atoi(listenFds)
	if err != nil {
		return nil, fmt.Errorf("invalid LISTEN_FDS: %w", err)
	}
	if fdCount < 1 {
		return nil, nil
	}

	file := os.NewFile(uintptr(systemdFdStart), "systemd-listener")
	if file == nil {
		return nil, errors.New("could not access systemd listener fd")
	}

	l, err := net.FileListener(file)
	if err != nil {
		return nil, fmt.Errorf("failed to wrap systemd listener: %w", err)
	}

	return l, nil
}

func runSocketServer(listener net.Listener, h handler) error {
	slog.Info("brightnessd waiting for socket connections", "address", listener.Addr())

	for {
		conn, err := listener.Accept()
		if err != nil {
			var ne net.Error
			if errors.As(err, &ne) && ne.Temporary() {
				time.Sleep(100 * time.Millisecond)
				continue
			}
			return err
		}

		go handleConnection(conn, h)
	}
}

func handleConnection(conn net.Conn, h handler) {
	defer conn.Close()

	for msg, err := range messageIter(conn) {
		if err != nil {
			io.WriteString(conn, fmt.Sprintf("ERR %v\n", err))
			var fe *fatalError
			if errors.Is(err, fe) {
				return
			}
			continue
		}

		if err := h.Handle(msg); err != nil {
			io.WriteString(conn, fmt.Sprintf("ERR %v\n", err))
			continue
		}

		if _, err := io.WriteString(conn, "OK\n"); err != nil {
			return
		}
	}
}
