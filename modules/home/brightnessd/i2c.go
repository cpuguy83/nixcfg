package main

import (
	"fmt"
	"log/slog"
	"syscall"
	"time"
	"unsafe"
)

const (
	I2C_SLAVE = 0x0703
	I2C_RDWR  = 0x0707

	vcpBrightness = 0x10
)

type i2cMessage struct {
	addr  uint16
	flags uint16
	len   uint16
	buf   uintptr
}

type i2c_rdwr_ioctl_data struct {
	msgs  uintptr
	nmsgs uint32
}

type DDCDevice struct {
	fd   int
	path string
}

func newDDCDevice(fd int, path string) *DDCDevice {
	return &DDCDevice{fd: fd, path: path}
}

func (d *DDCDevice) Close() {
	if d == nil {
		return
	}
	closeI2CFd(d.fd)
	d.fd = -1
}

func (d *DDCDevice) ReadVCP(vcpCode uint8) (currentValue, maxValue uint8, err error) {
	if d == nil || d.fd < 0 {
		return 0, 0, fmt.Errorf("invalid DDC device")
	}

	frame := []byte{
		0x51,
		0x82,
		0x01,
		vcpCode,
	}
	requestMsg := appendChecksum(frame)

	if err := i2cWrite(uintptr(d.fd), 0x37, requestMsg); err != nil {
		return 0, 0, fmt.Errorf("failed to write VCP read request: %w", err)
	}

	time.Sleep(50 * time.Millisecond)

	response := make([]byte, 12)
	if err := i2cRead(uintptr(d.fd), 0x37, response); err != nil {
		return 0, 0, fmt.Errorf("failed to read VCP response: %w", err)
	}

	if response[2] != 0x02 {
		return 0, 0, fmt.Errorf("invalid VCP reply opcode: expected 0x02, got 0x%02x", response[2])
	}

	if response[3] != 0x00 {
		return 0, 0, fmt.Errorf("VCP error result: 0x%02x", response[3])
	}

	maxValue = response[7]
	currentValue = response[9]

	return currentValue, maxValue, nil
}

func appendChecksum(msg []byte) []byte {
	const ddcDestAddr = 0x6e
	chk := byte(ddcDestAddr)
	for _, b := range msg {
		chk ^= b
	}
	return append(msg, chk)
}

func (d *DDCDevice) WriteVCP(vcpCode uint8, value uint8) error {
	if d == nil || d.fd < 0 {
		return fmt.Errorf("invalid DDC device")
	}

	frame := []byte{
		0x51,
		0x84,
		0x03,
		vcpCode,
		0x00,
		value,
	}

	msg := appendChecksum(frame)

	slog.Debug("VCP write (raw ioctl)", "opcode", fmt.Sprintf("0x%02x", vcpCode), "value", value, "bytes", fmt.Sprintf("%x", msg), "checksum", fmt.Sprintf("0x%02x", msg[len(msg)-1]))

	if err := i2cWrite(uintptr(d.fd), 0x37, msg); err != nil {
		return fmt.Errorf("failed to write VCP set request: %w", err)
	}

	time.Sleep(50 * time.Millisecond)
	return nil
}

func openI2CFd(devPath string) (int, error) {
	fd, err := syscall.Open(devPath, syscall.O_RDWR, 0)
	if err != nil {
		return -1, err
	}

	if err := setI2CSlave(fd, 0x37); err != nil {
		syscall.Close(fd)
		return -1, err
	}

	return fd, nil
}

func setI2CSlave(fd int, addr int) error {
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), uintptr(I2C_SLAVE), uintptr(addr))
	if errno != 0 {
		return fmt.Errorf("failed to set I2C slave: %v", errno)
	}
	return nil
}

func closeI2CFd(fd int) {
	if fd >= 0 {
		if err := syscall.Close(fd); err != nil {
			slog.Warn("could not close i2c fd", "error", err)
		}
	}
}

func i2cWrite(fd uintptr, addr uint16, data []byte) error {
	if len(data) == 0 {
		return fmt.Errorf("empty data")
	}

	msg := i2cMessage{
		addr:  addr,
		flags: 0,
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

func i2cRead(fd uintptr, addr uint16, data []byte) error {
	msg := i2cMessage{
		addr:  addr,
		flags: 1,
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
