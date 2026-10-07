package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"syscall"
)

const runtimeDirectory = "/run/msft-vpn"

type owner struct {
	PID   int    `json:"pid"`
	Start string `json:"start"`
	Boot  string `json:"boot"`
	Tun   string `json:"tun"`
}

type transaction struct {
	Before []route `json:"before"`
	After  []route `json:"after"`
}

type state struct {
	Version     int          `json:"version"`
	Owner       owner        `json:"owner"`
	Baseline    []routeRow   `json:"baseline"`
	Owned       []route      `json:"owned"`
	Transaction *transaction `json:"transaction"`
}

func atomicJSON(path string, data any, mode os.FileMode, rootOwned bool) error {
	file, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".")
	if err != nil {
		return err
	}

	temporary := file.Name()
	defer os.Remove(temporary)
	defer file.Close()

	if err := file.Chmod(mode); err != nil {
		return err
	}

	if rootOwned {
		if err := file.Chown(0, 0); err != nil {
			return err
		}
	}

	if err := json.NewEncoder(file).Encode(data); err != nil {
		return err
	}

	if err := file.Sync(); err != nil {
		return err
	}

	if err := file.Close(); err != nil {
		return err
	}

	if err := os.Rename(temporary, path); err != nil {
		return err
	}

	directory, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}

	defer directory.Close()

	return directory.Sync()
}

func decodeOwned(value any) ([]route, error) {
	list, ok := value.([]any)
	if !ok {
		return nil, fmt.Errorf("recovery state: invalid ownership list")
	}

	routes := make([]route, 0, len(list))

	for _, value := range list {
		row, ok := value.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("recovery state: invalid owned route")
		}

		spec, err := routeSpec(row, "recovery route")
		if err != nil {
			return nil, err
		}

		encoded, err := json.Marshal(spec)
		if err != nil {
			return nil, err
		}

		canonical, err := decodeJSON(encoded, "recovery route")
		if err != nil {
			return nil, err
		}

		if spec.Protocol != protocol || !reflect.DeepEqual(row, canonical) {
			return nil, fmt.Errorf("recovery state: invalid owned route")
		}

		routes = append(routes, spec)
	}

	return routes, nil
}

func decodeState(content []byte) (*state, error) {
	value, err := decodeJSON(content, "recovery state")
	if err != nil {
		return nil, err
	}

	object, ok := value.(map[string]any)
	if !ok || !exactKeys(object, "version", "owner", "baseline", "owned", "transaction") ||
		object["version"] != json.Number("1") {
		return nil, fmt.Errorf("recovery state: invalid schema or version")
	}

	identity, ok := object["owner"].(map[string]any)
	if !ok || !exactKeys(identity, "pid", "start", "boot", "tun") {
		return nil, fmt.Errorf("recovery state: invalid process identity")
	}

	pidNumber, pidOK := identity["pid"].(json.Number)
	pid, pidErr := strconv.Atoi(string(pidNumber))

	start, startOK := identity["start"].(string)
	boot, bootOK := identity["boot"].(string)
	tun, tunOK := identity["tun"].(string)
	if !pidOK || pidErr != nil || !decimal(string(pidNumber)) || pid < 1 ||
		!startOK || !decimal(start) || !bootOK || !tunOK {
		return nil, fmt.Errorf("recovery state: invalid process identity")
	}

	if err := device(tun); err != nil {
		return nil, err
	}

	result := &state{Version: 1, Owner: owner{pid, start, boot, tun}}
	baseline, ok := object["baseline"].([]any)
	if !ok {
		return nil, fmt.Errorf("recovery state: invalid baseline")
	}

	result.Baseline = make([]routeRow, 0, len(baseline))

	for _, value := range baseline {
		row, ok := value.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("recovery state: invalid baseline")
		}

		if _, err := routePrefix(row, "recovery baseline"); err != nil {
			return nil, err
		}

		result.Baseline = append(result.Baseline, row)
	}

	result.Owned, err = decodeOwned(object["owned"])
	if err != nil {
		return nil, err
	}

	if object["transaction"] != nil {
		pending, ok := object["transaction"].(map[string]any)
		if !ok || !exactKeys(pending, "before", "after") {
			return nil, fmt.Errorf("recovery state: invalid transaction")
		}

		before, err := decodeOwned(pending["before"])
		if err != nil {
			return nil, err
		}

		after, err := decodeOwned(pending["after"])
		if err != nil {
			return nil, err
		}

		result.Transaction = &transaction{before, after}
	}

	return result, nil
}

func sessionLock(directory string) (*os.File, error) {
	if err := os.Mkdir(directory, 0700); err != nil && !os.IsExist(err) {
		return nil, err
	}

	info, err := os.Stat(directory)
	if err != nil {
		return nil, err
	}

	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || !info.IsDir() || stat.Uid != 0 || info.Mode().Perm()&0077 != 0 {
		return nil, fmt.Errorf("runtime directory must be root-owned and mode 0700")
	}

	lock, err := os.OpenFile(filepath.Join(directory, "lock"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return nil, err
	}

	if err := lock.Chmod(0600); err != nil {
		lock.Close()

		return nil, err
	}

	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		lock.Close()

		return nil, err
	}

	return lock, nil
}

func readCandidate(path string, uid int, limit int64) (policy, error) {
	fd, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if err != nil {
		return policy{}, err
	}

	file := os.NewFile(uintptr(fd), path)
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		return policy{}, err
	}

	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || !info.Mode().IsRegular() || uint64(stat.Uid) != uint64(uid) {
		return policy{}, fmt.Errorf("candidate is not a regular file owned by the configured user")
	}

	content, err := io.ReadAll(io.LimitReader(file, limit+1))
	if err != nil {
		return policy{}, err
	}

	if int64(len(content)) > limit {
		return policy{}, fmt.Errorf("candidate exceeds 8 MiB")
	}

	return jsonPolicy(content)
}
