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
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"github.com/anoopengineer/edidparser/edid"
	"golang.org/x/exp/io/i2c"
)

const deviceBase = "/sys/class/drm"

const (
	I2C_SLAVE = 0x0703
	I2C_RDWR  = 0x0707
)

type i2c_msg struct {
	addr  uint16
	flags uint16
	len   uint16
	_     [2]byte // padding for 64-bit alignment
	buf   uintptr
}

type i2c_rdwr_ioctl_data struct {
	msgs  uintptr
	nmsgs uint32
}

// i2cWrite performs a raw I2C write using ioctl I2C_RDWR (like ddcutil does)
func i2cWrite(fd uintptr, addr uint16, data []byte) error {
	if len(data) == 0 {
		return fmt.Errorf("empty data")
	}

	msg := i2c_msg{
		addr:  addr,
		flags: 0, // write
		len:   uint16(len(data)),
		buf:   uintptr(unsafe.Pointer(&data[0])),
	}

	msgset := i2c_rdwr_ioctl_data{
		msgs:  uintptr(unsafe.Pointer(&msg)),
		nmsgs: 1,
	}

	ret, _, errno := syscall.Syscall(
		syscall.SYS_IOCTL,
		fd,
		I2C_RDWR,
		uintptr(unsafe.Pointer(&msgset)),
	)

	if errno != 0 {
		return fmt.Errorf("i2c write ioctl failed: errno=%v", errno)
	}

	slog.Debug("i2c write successful", "addr", fmt.Sprintf("0x%02x", addr), "bytes", len(data), "ret", ret)

	return nil
}

// i2cRead performs a raw I2C read using ioctl I2C_RDWR
func i2cRead(fd uintptr, addr uint16, data []byte) error {
	msg := i2c_msg{
		addr:  addr,
		flags: 1, // read
		len:   uint16(len(data)),
		buf:   uintptr(unsafe.Pointer(&data[0])),
	}

	msgset := i2c_rdwr_ioctl_data{
		msgs:  uintptr(unsafe.Pointer(&msg)),
		nmsgs: 1,
	}

	_, _, errno := syscall.Syscall(
		syscall.SYS_IOCTL,
		fd,
		I2C_RDWR,
		uintptr(unsafe.Pointer(&msgset)),
	)

	if errno != 0 {
		return fmt.Errorf("i2c read ioctl failed: %v", errno)
	}

	return nil
}

func appendChecksum(msg []byte) []byte {
	const ddcDestAddr = 0x6e
	chk := byte(ddcDestAddr)
	for _, b := range msg {
		chk ^= b
	}
	return append(msg, chk)
}

func main() {
	devices, err := detectDevices(deviceBase)
	if err != nil {
		slog.Error("could not detect devices", "error", err)
		os.Exit(1)
	}

	connAliases := collectConnectorAliases(deviceBase)

	h := handler{
		dm: newDeviceManager(devices, connAliases),
	}

	for _, dev := range devices {
		go dev.Wait()
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

		h.Handle(msg)
	}

	os.Exit(ec)
}

func readVCP(dev *i2c.Device, vcpCode uint8) (currentValue, maxValue uint8, err error) {
	// DDC/CI Get VCP Feature request
	// Format: [source 0x51][length|0x80][VCP Get 0x01][opcode][checksum]
	frame := []byte{
		0x51,    // Host source address
		0x82,    // Length: 2 payload bytes follow
		0x01,    // MCCS command: Get VCP
		vcpCode, // VCP code to query
	}
	requestMsg := appendChecksum(frame)

	if err := dev.Write(requestMsg); err != nil {
		return 0, 0, fmt.Errorf("failed to write VCP read request: %w", err)
	}

	// DDC/CI response format (typically 11-12 bytes):
	// [src addr 0x6E/6F][length|0x80][VCP reply 0x02][result][opcode][type][max MSB][max LSB][cur MSB][cur LSB][checksum]
	// Give monitor more time to respond (some monitors are slower)
	time.Sleep(100 * time.Millisecond)

	response := make([]byte, 12)
	if err := dev.Read(response); err != nil {
		return 0, 0, fmt.Errorf("failed to read VCP response: %w", err)
	}

	// Validate response structure
	if response[2] != 0x02 {
		return 0, 0, fmt.Errorf("invalid VCP reply opcode: expected 0x02, got 0x%02x", response[2])
	}

	if response[3] != 0x00 {
		return 0, 0, fmt.Errorf("VCP error result: 0x%02x", response[3])
	}

	// Extract max and current values (big-endian 16-bit values)
	maxValue = response[7]     // max LSB (assuming max < 256)
	currentValue = response[9] // current LSB

	return currentValue, maxValue, nil
}

func writeVCP(fd int, vcpCode uint8, value uint8) error {
	// DDC/CI Set VCP Feature request over I2C.
	// Frames are constructed as:
	//   [source addr 0x51][0x80 | payload len][command][VCP code][MSB][LSB][checksum]
	frame := []byte{
		0x51,    // Host source address
		0x84,    // Length: 4 payload bytes follow
		0x03,    // MCCS command: Set VCP Value
		vcpCode, // VCP code to change
		0x00,    // Value MSB
		value,   // Value LSB
	}

	msg := appendChecksum(frame)

	slog.Debug("VCP write (raw ioctl)", "opcode", fmt.Sprintf("0x%02x", vcpCode), "value", value, "bytes", fmt.Sprintf("%x", msg), "checksum", fmt.Sprintf("0x%02x", msg[len(msg)-1]))

	// Use raw I2C_RDWR ioctl (like ddcutil)
	// Address 0x37 is the DDC/CI monitor address
	err := i2cWrite(uintptr(fd), 0x37, msg)
	if err != nil {
		return fmt.Errorf("failed to write VCP set request: %w", err)
	}

	slog.Debug("VCP write complete")

	// Give monitor time to process
	time.Sleep(50 * time.Millisecond)

	return nil
}

// calculateChecksum computes the DDC/CI checksum by only XORing the payload bytes.
func calculateChecksum(data []byte) uint8 {
	var checksum uint8 = 0x00
	for _, b := range data {
		checksum ^= b
	}
	return checksum
}

func readBrightness(dev *i2c.Device) (int, error) {
	cur, _, err := readVCP(dev, 0x10)
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

func dirIter(p string, maxEntries int) iter.Seq2[os.DirEntry, error] {
	slog.Debug("iterating directory", "path", p)
	return func(yield func(os.DirEntry, error) bool) {
		f, err := os.Open(p)
		if err != nil {
			yield(nil, err)
			return
		}

		defer f.Close()

		for {
			entries, err := f.ReadDir(maxEntries)
			if err != nil {
				if !errors.Is(err, io.EOF) {
					yield(nil, err)
				}
				return
			}

			for _, entry := range entries {
				if !yield(entry, nil) {
					return
				}
			}
		}
	}
}

func supportsDDC(dev *i2c.Device) bool {
	// Query VCP feature 0x10 (Brightness)
	requestPayload := []byte{0x82, 0x01, 0x10}
	checksum := calculateChecksum(requestPayload)
	req := append(requestPayload, checksum)

	err := dev.Write(req)
	if err != nil {
		slog.Debug("could not write to i2c device", "error", err)
		return false
	}

	// Read and discard response to avoid buffering issues
	time.Sleep(50 * time.Millisecond)
	response := make([]byte, 12)
	err = dev.Read(response)
	if err != nil {
		slog.Debug("could not read from i2c device", "error", err)
		return false
	}

	// Check if we got a valid DDC/CI response
	if len(response) < 3 || response[2] != 0x02 {
		return false
	}

	return true
}

func detectDevices(base string) (map[string]*DeviceState, error) {
	out := make(map[string]*DeviceState)

	for entry, err := range dirIter(deviceBase, 10) {
		if err != nil {
			return nil, err
		}

		if !entry.IsDir() {
			stat, err := entry.Info()
			if err != nil {
				slog.Error("could not stat drm entry", "entry", filepath.Join(base, entry.Name()), "error", err)
				continue
			}

			if stat.Mode()&os.ModeSymlink == 0 {
				slog.Debug("skipping non-directory drm entry", "entry", filepath.Join(base, entry.Name()))
				continue
			}
		}

		connectorPath := filepath.Join(base, entry.Name())

		// First try to get DDC device
		d, devPath, err := getDDCDevice(connectorPath)
		if err != nil {
			slog.Error("could not get ddc device", "connector", entry.Name(), "error", err)
			continue
		}

		if d == nil {
			slog.Debug("no ddc device found for connector", "path", connectorPath)
			continue
		}

		// Try to read EDID from sysfs
		// Note: sysfs files may report size 0 but still contain data
		dt, err := os.ReadFile(filepath.Join(connectorPath, "edid"))
		var id *edid.Edid
		var serial string

		if err != nil {
			if !errors.Is(err, os.ErrNotExist) {
				slog.Error("could not read edid", "error", err)
				d.Close()
				continue
			}
			// No EDID file, use connector name
			serial = entry.Name()
		} else if len(dt) == 0 {
			// EDID file empty, use connector name
			slog.Debug("edid data is empty in sysfs, using connector name", "connector", entry.Name())
			serial = entry.Name()
		} else {
			// Parse EDID
			id, err = edid.NewEdid(dt)
			if err != nil {
				slog.Error("could not parse edid", "error", err)
				d.Close()
				continue
			}

			serial = strings.TrimSpace(id.MonitorSerialNumber)
			if serial == "" {
				serial = entry.Name()
			}
		}

		if _, ok := out[serial]; ok {
			// We already have an active DDC device for this serial
			d.Close()
			continue
		}

		st := newDeviceState(d, id, devPath, entry.Name())
		if err := st.Load(); err != nil {
			slog.Error("could not load initial brightness", "serial", serial, "error", err, "devPath", devPath)
			d.Close()
			continue
		}

		slog.Info("detected DDC-capable monitor", "serial", serial, "devPath", devPath, "brightness", st.Get())
		out[serial] = st
	}

	return out, nil
}

func getDDCDevice(devPath string) (*i2c.Device, string, error) {
	// First try i2c-* subdirectories (more reliable for DDC/CI)
	d, p, err := getDDCDeviceLegacy(devPath)
	if err != nil {
		return nil, "", err
	}
	if d != nil {
		return d, p, nil
	}

	// Fall back to ddc symlink
	ddcLink := filepath.Join(devPath, "ddc")
	target, err := os.Readlink(ddcLink)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return nil, "", fmt.Errorf("could not read ddc symlink: %w", err)
		}
		return nil, "", nil
	}

	// Extract i2c device name from symlink target
	i2cName := filepath.Base(target)
	i2cDevPath := filepath.Join("/dev", i2cName)

	d, err = i2c.Open(&i2c.Devfs{Dev: i2cDevPath}, 0x37)
	if err != nil {
		return nil, "", fmt.Errorf("could not open i2c device %s: %w", i2cDevPath, err)
	}

	if !supportsDDC(d) {
		d.Close()
		slog.Debug("i2c device does not support DDC", "device", i2cDevPath)
		return nil, "", nil
	}

	return d, i2cDevPath, nil
}

func getDDCDeviceLegacy(devPath string) (*i2c.Device, string, error) {
	for entry, err := range dirIter(devPath, 20) {
		if err != nil {
			return nil, "", err
		}

		if !strings.HasPrefix(entry.Name(), "i2c-") {
			continue
		}

		i2cDevPath := filepath.Join("/dev", entry.Name())
		d, err := i2c.Open(&i2c.Devfs{Dev: i2cDevPath}, 0x37)
		if err != nil {
			slog.Error("could not open i2c device", "device", entry.Name(), "error", err)
			continue
		}

		if !supportsDDC(d) {
			d.Close()
			slog.Info("i2c device does not support DDC", "device", i2cDevPath)
			continue
		}
		return d, i2cDevPath, nil
	}

	return nil, "", nil
}

type DeviceState struct {
	Dev   *i2c.Device
	i2cFd int // Raw file descriptor for I2C_RDWR ioctl
	EDID  *edid.Edid
	cond  *sync.Cond
	val   int
	Conn  string
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
	if s.Conn != "" {
		return s.Conn
	}
	return ""
}

// SetBrightness writes an absolute brightness value using DDC/CI (VCP code 0x10).
// val is typically 0–100, but you can pass the device's full range if known.
func setBrightness(fd int, val int) error {
	if fd < 0 {
		return fmt.Errorf("invalid file descriptor")
	}

	op := byte(0x10) // VCP code for brightness
	err := writeVCP(fd, op, uint8(val))
	if err != nil {
		return err
	}

	return nil
}

func (s *DeviceState) Wait() {
	s.cond.L.Lock()
	defer s.cond.L.Unlock()

	for {
		s.cond.Wait()

		slog.Debug("attempting to set brightness", "value", s.val)

		err := setBrightness(s.i2cFd, s.val)
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

func (h *handler) Handle(msg *message) {
	state, err := h.dm.Get(msg.monitor)
	if err != nil {
		slog.Error("could not get device state", "monitor", msg.monitor, "error", err)
		return
	}

	if state == nil {
		slog.Error("no device found for monitor", "monitor", msg.monitor)
		return
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
			slog.Error("brightness value out of range (0-100)", "value", msg.step)
			return
		}
		state.Set(msg.step)
	}

	state.SetMonitorAlias(msg.monitor)
	state.Wake()
}

type DeviceManager struct {
	mu          sync.Mutex
	idx         map[string]*DeviceState
	ali         map[string]string
	connAliases map[string][]string
}

func newDeviceManager(devices map[string]*DeviceState, connAliases map[string][]string) *DeviceManager {
	dm := &DeviceManager{
		idx:         devices,
		ali:         make(map[string]string),
		connAliases: connAliases,
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
		d.Dev.Close()
		return d, nil
	}

	if dev != nil {
		if err := dev.Load(); err != nil {
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
	for _, alias := range m.connAliases[id] {
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

func lookupDevice(base string, serial string) (*DeviceState, error) {
	for entry, err := range dirIter(base, 20) {
		if err != nil {
			return nil, err
		}

		if !entry.IsDir() {
			info, err := entry.Info()
			if err != nil {
				slog.Error("could not stat entry", "entry", filepath.Join(base, entry.Name()), "error", err)
				continue
			}

			if info.Mode()&os.ModeSymlink == 0 {
				slog.Debug("skipping non-directory entry", "entry", filepath.Join(base, entry.Name()))
				continue
			}

			stat, err := os.Stat(filepath.Join(base, entry.Name()))
			if err != nil {
				slog.Debug("could not stat entry", "entry", filepath.Join(base, entry.Name()), "error", err)
			}
			if !stat.IsDir() {
				slog.Debug("skipping non-directory entry", "entry", filepath.Join(base, entry.Name()))
				continue
			}
		}

		// Check if this is a connector match by name
		if entry.Name() == serial {
			d, p, err := getDDCDevice(filepath.Join(base, entry.Name()))
			if err != nil {
				slog.Error("could not get ddc device", "connector", entry.Name(), "error", err)
				continue
			}
			if d != nil {
				return newDeviceState(d, nil, p, entry.Name()), nil
			}
		}

		dt, err := os.ReadFile(filepath.Join(base, entry.Name(), "edid"))
		if err != nil {
			if !errors.Is(err, os.ErrNotExist) {
				slog.Error("could not read edid", "error", err)
			}
			continue
		}
		if len(dt) == 0 {
			continue
		}

		id, err := edid.NewEdid(dt)
		if err != nil {
			slog.Error("could not parse edid", "error", err)
			continue
		}

		if strings.TrimSpace(id.MonitorSerialNumber) != serial {
			continue
		}

		d, p, err := getDDCDevice(filepath.Join(base, entry.Name()))
		if err != nil {
			slog.Error("could not get ddc device", "error", err)
			continue
		}

		if d == nil {
			slog.Debug("no ddc device found for monitor", "serial", serial, "devPath", p)
			continue
		}

		return newDeviceState(d, id, p, entry.Name()), nil
	}

	return nil, nil
}

func newDeviceState(d *i2c.Device, id *edid.Edid, devPath string, connector string) *DeviceState {
	// Open raw file descriptor for I2C_RDWR ioctl (for writes)
	fd, err := syscall.Open(devPath, syscall.O_RDWR, 0)
	if err != nil {
		slog.Warn("could not open raw i2c device, writes may not work", "path", devPath, "error", err)
		fd = -1
	} else {
		slog.Debug("opened raw i2c device", "path", devPath, "fd", fd)
	}

	alias := connectorAliases(connector)
	slog.Info("device aliases", "connector", connector, "aliases", alias)

	return &DeviceState{
		Dev:   d,
		i2cFd: fd,
		EDID:  id,
		cond:  sync.NewCond(&sync.Mutex{}),
		Conn:  connector,
		Alias: alias,
	}
}

func connectorAliases(connector string) []string {
	var aliases []string
	connector = strings.TrimSpace(connector)
	if connector == "" {
		return aliases
	}

	aliases = append(aliases, connector)
	if short := trimConnectorPrefix(connector); short != "" && short != connector {
		aliases = append(aliases, short)
	}

	return aliases
}

func trimConnectorPrefix(connector string) string {
	if connector == "" {
		return ""
	}
	parts := strings.SplitN(connector, "-", 2)
	if len(parts) != 2 {
		return connector
	}
	if strings.HasPrefix(parts[0], "card") {
		return parts[1]
	}
	return connector
}

func collectConnectorAliases(base string) map[string][]string {
	out := make(map[string][]string)

	for entry, err := range dirIter(base, 20) {
		if err != nil {
			continue
		}

		if !isDirOrLinkDir(base, entry.Name()) {
			continue
		}

		dt, err := os.ReadFile(filepath.Join(base, entry.Name(), "edid"))
		if err != nil || len(dt) == 0 {
			continue
		}

		id, err := edid.NewEdid(dt)
		if err != nil {
			continue
		}

		serial := strings.TrimSpace(id.MonitorSerialNumber)
		if serial == "" {
			serial = entry.Name()
		}

		out[serial] = append(out[serial], connectorAliases(entry.Name())...)
	}

	return out
}

func isDirOrLinkDir(base, name string) bool {
	entryPath := filepath.Join(base, name)
	info, err := os.Lstat(entryPath)
	if err != nil {
		return false
	}
	if info.IsDir() {
		return true
	}
	if info.Mode()&os.ModeSymlink == 0 {
		return false
	}
	target, err := os.Stat(entryPath)
	if err != nil {
		return false
	}
	return target.IsDir()
}
