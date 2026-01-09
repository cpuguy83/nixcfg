package main

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"sync"
)

// Messenger handles Chrome/Firefox native messaging protocol
// Protocol: 4-byte little-endian length prefix followed by UTF-8 JSON
type Messenger struct {
	reader io.Reader
	writer io.Writer
	mu     sync.Mutex
}

func NewMessenger(r io.Reader, w io.Writer) *Messenger {
	return &Messenger{
		reader: r,
		writer: w,
	}
}

// Receive reads a message from the native messaging input
func (m *Messenger) Receive() (map[string]any, error) {
	// Read 4-byte length prefix (little-endian)
	var length uint32
	if err := binary.Read(m.reader, binary.LittleEndian, &length); err != nil {
		return nil, fmt.Errorf("failed to read message length: %w", err)
	}

	// Sanity check on message size (max 1MB)
	if length > 1024*1024 {
		return nil, fmt.Errorf("message too large: %d bytes", length)
	}

	// Read the JSON payload
	data := make([]byte, length)
	if _, err := io.ReadFull(m.reader, data); err != nil {
		return nil, fmt.Errorf("failed to read message body: %w", err)
	}

	// Parse JSON
	var msg map[string]any
	if err := json.Unmarshal(data, &msg); err != nil {
		return nil, fmt.Errorf("failed to parse message JSON: %w", err)
	}

	return msg, nil
}

// Send writes a message to the native messaging output
func (m *Messenger) Send(msg map[string]any) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	data, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("failed to marshal message: %w", err)
	}

	// Write 4-byte length prefix (little-endian)
	length := uint32(len(data))
	if err := binary.Write(m.writer, binary.LittleEndian, length); err != nil {
		return fmt.Errorf("failed to write message length: %w", err)
	}

	// Write the JSON payload
	if _, err := m.writer.Write(data); err != nil {
		return fmt.Errorf("failed to write message body: %w", err)
	}

	return nil
}
