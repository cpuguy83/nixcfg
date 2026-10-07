package main

import (
	"context"
	"errors"
	"strings"
	"time"
)

// One client goroutine owns all mutable session state and both job lifetimes.
// The UI reader only routes immutable messages by request ID.
type session struct {
	ctx        context.Context
	ui         *transport
	id         string
	picker     bool
	prompt     string
	lines      []string
	messages   chan message
	failed     chan struct{}
	revision   int64
	query      string
	expression string
	result     *string
	calculator *job
	action     *job
	ready      bool
	done       bool
	code       int
	index      *int64
}

func newSession(ctx context.Context, ui *transport, id string, picker bool, prompt string, lines []string) *session {
	return &session{
		ctx: ctx, ui: ui, id: id, picker: picker, prompt: prompt, lines: lines,
		revision: -1, messages: make(chan message, 16), failed: make(chan struct{}),
	}
}

func (s *session) send(m message) error {
	m["id"] = s.id
	limit := messageLimit
	if stringField(m, "type") == "init" {
		limit = uploadLimit
	}

	return s.ui.send(m, limit)
}

func (s *session) readUI(cancel context.CancelFunc) {
	defer cancel()
	defer close(s.failed)

	for {
		m, err := s.ui.receive(messageLimit, 0)
		if err != nil {
			return
		}
		if stringField(m, "id") != s.id {
			continue
		}

		select {
		case s.messages <- m:
		case <-s.ctx.Done():
			return
		}
	}
}

func (s *session) handle(m message) error {
	switch stringField(m, "type") {
	case "ready":
		s.ready = true
	case "cancel":
		s.done, s.code = true, 1
	case "select":
		index, valid := integer(m["index"])
		if !s.picker || !valid || index < 0 || index >= int64(len(s.lines)) {
			return errors.New("invalid selection index")
		}

		s.done, s.code, s.index = true, 0, &index

	case "query":
		revision, valid := integer(m["revision"])
		text, validText := m["text"].(string)
		raw, validRaw := m["raw"].(string)
		if s.picker || !valid || revision <= s.revision || !validText || !validRaw {
			return errors.New("invalid calculator query")
		}
		if err := validateQuery(raw); err != nil {
			return err
		}
		if text != "" && text != raw {
			return errors.New("calculator query does not match raw input")
		}

		s.revision = revision
		s.query, s.expression, s.result = raw, strings.TrimPrefix(text, "="), nil
		stopJob(&s.calculator)

	case "calculate":
		if s.picker {
			return errors.New("unexpected launcher message")
		}

		revision, valid := integer(m["revision"])
		if !valid {
			return errors.New("invalid calculator revision")
		}

		if revision == s.revision && strings.TrimSpace(s.expression) != "" {
			stopJob(&s.calculator)

			expression := s.expression
			s.calculator = startJob(s.ctx, func(ctx context.Context) jobResult {
				result := jobResult{revision: revision, text: "Calculator failed, timed out, or exceeded its output limit"}
				path, err := runtimePath("QALC")
				if err != nil {
					return result
				}

				code, out, diagnostic, err := command(ctx, []string{
					path, "--defaults", "--terse", "-s", "save definitions off", "-m", "500", "--", expression,
				}, nil, true, jobTimeout)
				if err == nil {
					result.ok, result.text = calculation(code, out, diagnostic)
				}

				return result
			})
		}

	case "copy":
		if s.picker {
			return errors.New("unexpected launcher message")
		}

		revision, valid := integer(m["revision"])
		if !valid {
			return errors.New("invalid calculator revision")
		}
		if revision != s.revision || s.result == nil {
			return s.send(message{"type": "error", "text": "Wait for the current calculation"})
		}

		if s.action == nil {
			path, err := runtimePath("COPY")
			if err != nil {
				return err
			}

			s.activate([]string{path, "--type", "text/plain;charset=utf-8"}, []byte(*s.result))
		}

	case "launch":
		entry, valid := m["desktopId"].(string)
		if s.picker || !valid || entry == "" || strings.ContainsAny(entry, "/\x00\n:") {
			return errors.New("invalid desktop entry ID")
		}

		if s.action == nil {
			path, err := runtimePath("UWSM")
			if err != nil {
				return err
			}

			s.activate([]string{path, "app", "-t", "service", "--", entry + ".desktop"}, nil)
		}

	default:
		return errors.New("unexpected launcher message")
	}

	return nil
}

func (s *session) activate(argv []string, data []byte) {
	s.action = startJob(s.ctx, func(ctx context.Context) jobResult {
		// wl-copy's surviving owner must not inherit captured output pipes.
		code, _, _, err := command(ctx, argv, data, data == nil, jobTimeout)
		return jobResult{ok: err == nil && code == 0}
	})
}

func (s *session) stopJobs() {
	s.revision++
	s.result = nil

	stopJob(&s.calculator)
	stopJob(&s.action)
}

func (s *session) run() (int, *int64, error) {
	if !s.picker {
		query, err := readQuery()
		if err != nil {
			return 2, nil, err
		}
		s.query = query
	}

	if err := s.send(message{
		"type": "init", "picker": s.picker, "prompt": s.prompt,
		"lines": s.lines, "query": s.query,
	}); err != nil {
		return 2, nil, err
	}

	timer := time.NewTimer(startTimeout)
	defer timer.Stop()
	readyDeadline := timer.C

	for {
		if s.ready && s.done {
			s.stopJobs()

			// Reaping may take time; do not save after a disconnect during cleanup.
			select {
			case <-s.failed:
				return 2, nil, errors.New("launcher UI failed")
			case <-s.ctx.Done():
				return 2, nil, s.ctx.Err()
			default:
			}

			if !s.picker {
				if err := saveQuery(s.query); err != nil {
					return 2, nil, err
				}
			}

			return s.code, s.index, nil
		}

		select {
		case m := <-s.messages:
			if s.done && stringField(m, "type") != "ready" {
				continue
			}

			if err := s.handle(m); err != nil {
				return 2, nil, err
			}

			if s.ready {
				timer.Stop()
				readyDeadline = nil
			}

		case result := <-jobResults(s.calculator):
			stopJob(&s.calculator)
			if result.revision == s.revision {
				if result.ok {
					s.result = &result.text
				}

				if err := s.send(message{
					"type": "result", "revision": result.revision, "ok": result.ok, "text": result.text,
				}); err != nil {
					return 2, nil, err
				}
			}

		case result := <-jobResults(s.action):
			stopJob(&s.action)
			if result.ok {
				s.done, s.code = true, 0
			} else if err := s.send(message{"type": "error", "text": "Launch or copy failed; try again"}); err != nil {
				return 2, nil, err
			}

		case <-s.failed:
			return 2, nil, errors.New("launcher UI failed")
		case <-s.ctx.Done():
			return 2, nil, s.ctx.Err()
		case <-readyDeadline:
			return 2, nil, errors.New("launcher UI did not become ready")
		}
	}
}

func (s *session) close() error {
	s.stopJobs()
	defer func() {
		s.lines = nil
		s.query, s.expression, s.prompt = "", "", ""
	}()

	if err := s.send(message{"type": "hide"}); err != nil {
		return err
	}

	timer := time.NewTimer(startTimeout)
	defer timer.Stop()

	for {
		select {
		case m := <-s.messages:
			if stringField(m, "type") == "hidden" {
				return nil
			}
		case <-s.failed:
			return errors.New("launcher UI failed")
		case <-s.ctx.Done():
			return s.ctx.Err()
		case <-timer.C:
			return errors.New("launcher UI did not reset")
		}
	}
}
