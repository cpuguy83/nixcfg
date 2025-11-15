package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"iter"
	"log/slog"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"

	"github.com/anoopengineer/edidparser/edid"
)

const deviceBase = "/sys/class/drm"

func main() {
	devices, err := detectDevices(deviceBase)
	if err != nil {
		slog.Error("could not detect devices", "error", err)
		os.Exit(1)
	}

	deviceAliases := collectDeviceAliases(deviceBase)

	h := handler{
		dm: newDeviceManager(devices, deviceAliases),
	}

	for _, dev := range devices {
		go dev.Wait()
	}

	listener, err := activatedListener()
	if err != nil {
		slog.Error("failed to acquire listener", "error", err)
		os.Exit(1)
	}

	if listener != nil {
		if err := runSocketServer(listener, h); err != nil {
			slog.Error("socket server failed", "error", err)
			os.Exit(1)
		}
		return
	}

	var ec int
	for msg, err := range messageIter(os.Stdin) {
		if err != nil {
			slog.Error("could not parse message", "error", err)
			var fe *fatalError
			if errors.Is(err, fe) {
				ec = 2
				break
			}
			continue
		}

		if err := h.Handle(msg); err != nil {
			slog.Error("failed to handle message", "error", err)
		}
	}

	os.Exit(ec)
}

func readBrightness(dev *DDCDevice) (int, error) {
	if dev == nil {
		return 0, fmt.Errorf("ddc device not available")
	}
	cur, _, err := dev.ReadVCP(vcpBrightness)
	return int(cur), err
}

type fatalError struct {
	Err error
}

func fatalErr(err error) error {
	return &fatalError{Err: err}
}

func (e *fatalError) Error() string {
	return e.Err.Error()
}

func (e *fatalError) Unwrap() error {
	return e.Err
}

func messageIter(rdr io.Reader) iter.Seq2[*message, error] {
	return func(yield func(*message, error) bool) {
		scanner := bufio.NewScanner(rdr)

		var msg message
		for scanner.Scan() {
			err := msg.UnmarshalText(scanner.Text())
			if !yield(&msg, err) {
				return
			}
		}

		if err := scanner.Err(); err != nil {
			yield(nil, fatalErr(err))
		}
	}
}

type DeviceState struct {
	Dev   *DDCDevice
	EDID  *edid.Edid
	cond  *sync.Cond
	val   int
	Name  string
	Alias []string
	mon   string
}

func (s *DeviceState) Load() error {
	s.cond.L.Lock()
	defer s.cond.L.Unlock()

	v, err := readBrightness(s.Dev)
	if err != nil {
		return err
	}

	s.val = v
	return nil
}

func (s *DeviceState) Add(i int) {
	s.cond.L.Lock()
	s.val += i
	if s.val < 0 {
		s.val = 0
	}

	if s.val > 100 {
		s.val = 100
	}
	s.cond.L.Unlock()
}

func (s *DeviceState) Set(i int) {
	s.cond.L.Lock()
	s.val = i
	s.cond.L.Unlock()
}

func (s *DeviceState) Get() int {
	s.cond.L.Lock()
	i := s.val
	s.cond.L.Unlock()
	return i
}

func (s *DeviceState) SetMonitorAlias(alias string) {
	s.cond.L.Lock()
	s.mon = strings.TrimSpace(alias)
	s.cond.L.Unlock()
}

func (s *DeviceState) monitorTarget() string {
	if s.mon != "" {
		return s.mon
	}
	if len(s.Alias) > 0 {
		return s.Alias[0]
	}
	return s.Name
}

// SetBrightness writes an absolute brightness value using DDC/CI.
// val is typically 0–100, but you can pass the device's full range if known.
func setBrightness(dev *DDCDevice, val int) error {
	if dev == nil {
		return fmt.Errorf("ddc device not available")
	}
	return dev.WriteVCP(vcpBrightness, uint8(val))
}

func (s *DeviceState) Wait() {
	s.cond.L.Lock()
	defer s.cond.L.Unlock()

	for {
		s.cond.Wait()

		slog.Debug("attempting to set brightness", "value", s.val)

		err := setBrightness(s.Dev, s.val)
		if err != nil {
			slog.Error("Could not set brightness", "error", err)
			continue
		}

		prog := fmt.Sprintf("%.2f", float32(s.val)/100)
		// Skip swayosd for now
		args := []string{"--custom-progress", prog, "--custom-icon", "display-brightness-symbolic"}
		if mon := s.monitorTarget(); mon != "" {
			args = append([]string{"--monitor", mon}, args...)
		}

		if dt, err := exec.Command("swayosd-client", args...).CombinedOutput(); err != nil {
			slog.Error("could not show osd", "error", err, "output", string(dt))
			continue
		}

		slog.Debug("set brightness", "brightness", s.val, "progress", prog)
	}
}

func (s *DeviceState) Wake() {
	s.cond.Signal()
}

func (s *DeviceState) Close() {
	if s == nil {
		return
	}
	if s.Dev != nil {
		s.Dev.Close()
	}
}

type Op int

const (
	OpAdd Op = iota
	OpSub
	OpSet
	OpGet
)

type handler struct {
	dm *DeviceManager
}

type message struct {
	monitor string
	op      Op
	step    int
}

func (m *message) UnmarshalText(data string) error {
	mon, extra, ok := strings.Cut(data, " ")
	if !ok {
		return fmt.Errorf("invalid input looking for monitor: %s", data)
	}

	m.monitor = mon

	op, extra, ok := strings.Cut(extra, " ")
	op = strings.ToLower(op)

	switch op {
	case "+", "add":
		m.op = OpAdd
	case "-", "sub":
		m.op = OpSub
	case "set", "=":
		m.op = OpSet
	case "get":
		m.op = OpGet
	default:
		return fmt.Errorf("invalid operation: %s", op)
	}

	if m.op != OpGet {
		if !ok {
			return fmt.Errorf("invalid input: missing value: %s", data)
		}
		v, err := strconv.ParseInt(extra, 10, 32)
		if err != nil {
			return fmt.Errorf("invalid input: parsing value: %w: %s", err, data)
		}
		m.step = int(v)
	}
	return nil
}

func (h *handler) Handle(msg *message) error {
	state, err := h.dm.Get(msg.monitor)
	if err != nil {
		return fmt.Errorf("could not get device state for %s: %w", msg.monitor, err)
	}

	if state == nil {
		return fmt.Errorf("no device found for monitor %s", msg.monitor)
	}

	switch msg.op {
	case OpAdd:
		state.Add(msg.step)
	case OpSub:
		state.Add(-msg.step)
	case OpGet:
		state.Add(0)
	case OpSet:
		if msg.step < 0 || msg.step > 100 {
			return fmt.Errorf("brightness value out of range (0-100): %d", msg.step)
		}
		state.Set(msg.step)
	}

	state.SetMonitorAlias(msg.monitor)
	state.Wake()

	return nil
}

type DeviceManager struct {
	mu            sync.Mutex
	idx           map[string]*DeviceState
	ali           map[string]string
	deviceAliases map[string][]string
}

func newDeviceManager(devices map[string]*DeviceState, deviceAliases map[string][]string) *DeviceManager {
	dm := &DeviceManager{
		idx:           devices,
		ali:           make(map[string]string),
		deviceAliases: deviceAliases,
	}

	for id, st := range devices {
		dm.addAlias(id, id)
		dm.registerStateAliases(id, st)
	}

	return dm
}

func (m *DeviceManager) Get(id string) (*DeviceState, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	canonical := m.lookupAlias(id)

	d, ok := m.idx[canonical]
	if ok {
		return d, nil
	}

	m.mu.Unlock()
	dev, err := lookupDevice(deviceBase, canonical)
	m.mu.Lock()

	// Handle case where another goroutine added this while we were unlocked
	d, ok = m.idx[canonical]
	if ok {
		if dev != nil {
			dev.Close()
		}
		return d, nil
	}

	if dev != nil {
		if err := dev.Load(); err != nil {
			dev.Close()
			return nil, err
		}
		m.idx[canonical] = dev
		m.addAlias(canonical, canonical)
		m.registerStateAliases(canonical, dev)
	}
	return dev, err
}

func (m *DeviceManager) registerStateAliases(id string, st *DeviceState) {
	if st == nil {
		return
	}
	for _, alias := range st.Alias {
		m.addAlias(alias, id)
	}
	for _, alias := range m.deviceAliases[id] {
		m.addAlias(alias, id)
	}
}

func (m *DeviceManager) addAlias(alias, canonical string) {
	alias = strings.TrimSpace(alias)
	if alias == "" {
		return
	}
	if m.ali == nil {
		m.ali = make(map[string]string)
	}
	key := strings.ToLower(alias)
	if _, ok := m.ali[key]; ok {
		return
	}
	m.ali[key] = canonical
}

func (m *DeviceManager) lookupAlias(id string) string {
	id = strings.TrimSpace(id)
	if id == "" {
		return id
	}
	if m.ali == nil {
		return id
	}
	if canon, ok := m.ali[strings.ToLower(id)]; ok {
		return canon
	}
	return id
}

func newDeviceState(dev *DDCDevice, id *edid.Edid, devPath string, name string) *DeviceState {
	if dev == nil {
		slog.Warn("invalid ddc device for new state", "path", devPath)
	}

	alias := deviceAliases(name)
	slog.Info("device aliases", "name", name, "aliases", alias)

	return &DeviceState{
		Dev:   dev,
		EDID:  id,
		cond:  sync.NewCond(&sync.Mutex{}),
		Name:  name,
		Alias: alias,
	}
}

func deviceAliases(dev string) []string {
	var aliases []string
	dev = strings.TrimSpace(dev)
	if dev == "" {
		return aliases
	}

	aliases = append(aliases, dev)
	if short := trimDevicePrefix(dev); short != "" && short != dev {
		aliases = append(aliases, short)
	}

	return aliases
}

func trimDevicePrefix(dev string) string {
	prefix, exrtra, ok := strings.Cut(dev, "-")
	if !ok {
		return dev
	}

	if strings.HasPrefix(prefix, "card") {
		return exrtra
	}

	return dev
}
