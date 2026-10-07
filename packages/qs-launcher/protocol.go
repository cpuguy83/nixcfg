package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"
)

const (
	inputLimit   = 1024 * 1024
	lineLimit    = 16 * 1024
	recordLimit  = 10000
	messageLimit = 64 * 1024
	uploadLimit  = 8 * 1024 * 1024
	outputLimit  = 16 * 1024
	startTimeout = 8 * time.Second
	jobTimeout   = 3 * time.Second
	protocol     = 1
)

type message map[string]any

func integer(value any) (int64, bool) {
	n, ok := value.(json.Number)
	if !ok {
		return 0, false
	}

	value64, err := n.Int64()
	return value64, err == nil
}

func stringField(m message, key string) string {
	value, _ := m[key].(string)
	return value
}

func records(reader io.Reader) ([]string, error) {
	data, err := io.ReadAll(io.LimitReader(reader, inputLimit+1))
	if err != nil {
		return nil, errors.New("cannot read launcher input")
	}
	if len(data) > inputLimit {
		return nil, errors.New("input exceeds 1 MiB")
	}
	if !utf8.Valid(data) {
		return nil, errors.New("input is not valid UTF-8")
	}
	if len(data) == 0 {
		return []string{}, nil
	}

	lines := strings.Split(string(data), "\n")
	if lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	if len(lines) > recordLimit {
		return nil, errors.New("input exceeds 10000 records")
	}

	for _, line := range lines {
		if len(line) > lineLimit {
			return nil, errors.New("record exceeds 16 KiB")
		}
	}

	return lines, nil
}

type transport struct {
	conn   net.Conn
	reader *bufio.Reader
}

func newTransport(conn net.Conn) *transport {
	return &transport{conn: conn, reader: bufio.NewReader(conn)}
}

// The first byte may wait for a human; once a frame starts it must finish promptly.
func (t *transport) receive(limit int, initialTimeout time.Duration) (message, error) {
	deadline := time.Time{}
	if initialTimeout > 0 {
		deadline = time.Now().Add(initialTimeout)
	}
	if err := t.conn.SetReadDeadline(deadline); err != nil {
		return nil, errors.New("launcher transport failed")
	}

	first, err := t.reader.ReadByte()
	if err != nil {
		return nil, errors.New("launcher transport closed or timed out")
	}

	frameDeadline := time.Now().Add(startTimeout)
	if !deadline.IsZero() && deadline.Before(frameDeadline) {
		frameDeadline = deadline
	}
	if err := t.conn.SetReadDeadline(frameDeadline); err != nil {
		return nil, errors.New("launcher transport failed")
	}

	raw := []byte{first}
	for raw[len(raw)-1] != '\n' {
		chunk, err := t.reader.ReadSlice('\n')
		if len(raw)+len(chunk) > limit {
			return nil, errors.New("launcher message exceeds its limit")
		}

		raw = append(raw, chunk...)
		if err != nil && err != bufio.ErrBufferFull {
			return nil, errors.New("launcher transport closed or timed out")
		}
	}

	if !validJSONUnicode(raw) {
		return nil, errors.New("invalid launcher message")
	}

	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var m message
	if err := decoder.Decode(&m); err != nil || m == nil {
		return nil, errors.New("invalid launcher message")
	}

	var extra any
	if decoder.Decode(&extra) != io.EOF {
		return nil, errors.New("invalid launcher message")
	}

	return m, nil
}

// encoding/json replaces malformed Unicode rather than rejecting it.
func validJSONUnicode(raw []byte) bool {
	if !utf8.Valid(raw) {
		return false
	}

	for i := 0; i < len(raw); i++ {
		if raw[i] != '\\' {
			continue
		}

		i++
		if i >= len(raw) || raw[i] != 'u' {
			continue
		}
		if i+4 >= len(raw) {
			return false
		}

		n, err := strconv.ParseUint(string(raw[i+1:i+5]), 16, 16)
		if err != nil {
			return false
		}

		i += 4
		if n >= 0xdc00 && n <= 0xdfff {
			return false
		}
		if n >= 0xd800 && n <= 0xdbff {
			if i+6 >= len(raw) || raw[i+1] != '\\' || raw[i+2] != 'u' {
				return false
			}

			low, err := strconv.ParseUint(string(raw[i+3:i+7]), 16, 16)
			if err != nil || low < 0xdc00 || low > 0xdfff {
				return false
			}

			i += 6
		}
	}

	return true
}

func (t *transport) send(m message, limit int) error {
	data, err := json.Marshal(m)
	if err != nil || len(data)+1 > limit {
		return errors.New("launcher message exceeds its limit")
	}

	data = append(data, '\n')
	if err := t.conn.SetWriteDeadline(time.Now().Add(startTimeout)); err != nil {
		return errors.New("launcher transport failed")
	}

	for len(data) > 0 {
		n, err := t.conn.Write(data)
		if err != nil || n == 0 {
			return errors.New("launcher transport failed")
		}

		data = data[n:]
	}

	return nil
}

func runtimePath(name string) (string, error) {
	value := os.Getenv("QS_LAUNCHER_" + name)
	if !filepath.IsAbs(value) {
		return "", errors.New("missing absolute runtime path: " + name)
	}

	return value, nil
}

func sameUser(conn *net.UnixConn) bool {
	raw, err := conn.SyscallConn()
	if err != nil {
		return false
	}

	var credentials *syscall.Ucred
	var credentialErr error
	err = raw.Control(func(fd uintptr) {
		credentials, credentialErr = syscall.GetsockoptUcred(int(fd), syscall.SOL_SOCKET, syscall.SO_PEERCRED)
	})

	return err == nil && credentialErr == nil && credentials.Uid == uint32(os.Getuid())
}

func controlPath() (string, error) {
	root := os.Getenv("XDG_RUNTIME_DIR")
	if !filepath.IsAbs(root) {
		return "", errors.New("launcher service requires XDG_RUNTIME_DIR")
	}

	directory := filepath.Join(root, "qs-launcher-daemon")
	var info syscall.Stat_t
	if err := syscall.Lstat(directory, &info); err != nil {
		return "", err
	}
	if info.Mode&syscall.S_IFMT != syscall.S_IFDIR || info.Mode&07777 != 0700 || info.Uid != uint32(os.Getuid()) {
		return "", errors.New("launcher service directory is not private")
	}

	return filepath.Join(directory, "control.sock"), nil
}
