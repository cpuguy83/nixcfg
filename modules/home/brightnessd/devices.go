package main

import (
	"errors"
	"fmt"
	"io"
	"iter"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"github.com/anoopengineer/edidparser/edid"
)

func getDDCDeviceI2C(devPath string) (*DDCDevice, string, error) {
	for entry, err := range dirIter(devPath, 20) {
		if err != nil {
			return nil, "", err
		}

		if !strings.HasPrefix(entry.Name(), "i2c-") {
			continue
		}

		i2cDevPath := filepath.Join("/dev", entry.Name())
		fd, err := openI2CFd(i2cDevPath)
		if err != nil {
			slog.Error("could not open i2c device", "device", entry.Name(), "error", err)
			continue
		}

		dev := newDDCDevice(fd, i2cDevPath)
		if !deviceSupportsDDC(dev) {
			dev.Close()
			slog.Info("i2c device does not support DDC", "device", i2cDevPath)
			continue
		}
		return dev, i2cDevPath, nil
	}

	return nil, "", nil
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

		devicePath := filepath.Join(base, entry.Name())

		// First try to get DDC device
		dev, devPath, err := getDDCDevice(devicePath)
		if err != nil {
			slog.Error("could not get ddc device", "device", entry.Name(), "error", err)
			continue
		}

		if dev == nil {
			slog.Debug("no ddc device found for device", "path", devicePath)
			continue
		}

		// Try to read EDID from sysfs
		// Note: sysfs files may report size 0 but still contain data
		dt, err := os.ReadFile(filepath.Join(devicePath, "edid"))
		var id *edid.Edid
		var serial string

		if err != nil {
			if !errors.Is(err, os.ErrNotExist) {
				slog.Error("could not read edid", "error", err)
				dev.Close()
				continue
			}
			// No EDID file, use device name
			serial = entry.Name()
		} else if len(dt) == 0 {
			// EDID file empty, use device name
			slog.Debug("edid data is empty in sysfs, using device name", "device", entry.Name())
			serial = entry.Name()
		} else {
			// Parse EDID
			id, err = edid.NewEdid(dt)
			if err != nil {
				slog.Error("could not parse edid", "error", err)
				dev.Close()
				continue
			}

			serial = strings.TrimSpace(id.MonitorSerialNumber)
			if serial == "" {
				serial = entry.Name()
			}
		}

		if _, ok := out[serial]; ok {
			// We already have an active DDC device for this serial
			dev.Close()
			continue
		}

		st := newDeviceState(dev, id, devPath, entry.Name())
		if err := st.Load(); err != nil {
			slog.Error("could not load initial brightness", "serial", serial, "error", err, "devPath", devPath)
			dev.Close()
			continue
		}

		slog.Info("detected DDC-capable monitor", "serial", serial, "devPath", devPath, "brightness", st.Get())
		out[serial] = st
	}

	return out, nil
}

func getDDCDevice(devPath string) (*DDCDevice, string, error) {
	// First try i2c-* subdirectories (more reliable for DDC/CI)
	dev, p, err := getDDCDeviceI2C(devPath)
	if err != nil {
		return nil, "", err
	}
	if dev != nil {
		return dev, p, nil
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

	fd, err := openI2CFd(i2cDevPath)
	if err != nil {
		return nil, "", fmt.Errorf("could not open i2c device %s: %w", i2cDevPath, err)
	}

	dev = newDDCDevice(fd, i2cDevPath)
	if !deviceSupportsDDC(dev) {
		dev.Close()
		slog.Debug("i2c device does not support DDC", "device", i2cDevPath)
		return nil, "", nil
	}

	return dev, i2cDevPath, nil
}

func deviceSupportsDDC(dev *DDCDevice) bool {
	if dev == nil {
		return false
	}
	if _, _, err := dev.ReadVCP(vcpBrightness); err != nil {
		slog.Debug("ddc probe failed", "error", err)
		return false
	}
	return true
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

		// Check if this is a device match by name
		if entry.Name() == serial {
			dev, p, err := getDDCDevice(filepath.Join(base, entry.Name()))
			if err != nil {
				slog.Error("could not get ddc device", "device", entry.Name(), "error", err)
				continue
			}
			if dev != nil {
				return newDeviceState(dev, nil, p, entry.Name()), nil
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

		dev, p, err := getDDCDevice(filepath.Join(base, entry.Name()))
		if err != nil {
			slog.Error("could not get ddc device", "error", err)
			continue
		}

		if dev == nil {
			slog.Debug("no ddc device found for monitor", "serial", serial, "devPath", p)
			continue
		}

		return newDeviceState(dev, id, p, entry.Name()), nil
	}

	return nil, nil
}

func collectDeviceAliases(base string) map[string][]string {
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

		out[serial] = append(out[serial], deviceAliases(entry.Name())...)
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
