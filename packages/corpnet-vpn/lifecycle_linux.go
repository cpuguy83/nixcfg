package main

import (
	"fmt"
	"io"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

type controller struct {
	path   string
	kernel routeKernel
	errors io.Writer
}

func (c *controller) save(state *state) error {
	return atomicJSON(c.path, state, 0600, false)
}

func (c *controller) load() (*state, error) {
	content, err := os.ReadFile(c.path)
	if os.IsNotExist(err) {
		return nil, nil
	}

	if err != nil {
		return nil, err
	}

	return decodeState(content)
}

func (c *controller) current(routes []route) ([]route, error) {
	rows, err := c.kernel.routes()
	if err != nil {
		return nil, err
	}

	return exactRoutes(routes, rows)
}

func (c *controller) deleteOwned(routes []route) error {
	current, err := c.current(routes)
	if err != nil {
		return err
	}

	present := make([]route, 0)

	for _, route := range routes {
		if containsRoute(current, route) {
			present = append(present, route)
		}
	}

	if err := c.kernel.change("del", present); err != nil {
		return err
	}

	remaining, err := c.current(present)
	if err != nil {
		return err
	}

	for _, route := range present {
		if containsRoute(remaining, route) {
			return fmt.Errorf("owned-route deletion verification failed")
		}
	}

	return nil
}

func recordedRoutes(state *state) []route {
	routes := append([]route{}, state.Owned...)

	if state.Transaction != nil {
		for _, collection := range [][]route{state.Transaction.Before, state.Transaction.After} {
			for _, route := range collection {
				if !containsRoute(routes, route) {
					routes = append(routes, route)
				}
			}
		}
	}

	return routes
}

func (c *controller) cleanup(state *state) error {
	if err := c.changeRoutes(recordedRoutes(state), nil, state.Owner.Tun); err != nil {
		return err
	}

	return os.Remove(c.path)
}

func (c *controller) recover(state *state) error {
	report(c.errors, fmt.Errorf("recovering interrupted transaction: cleaning recorded routes"))

	if err := c.changeRoutes(recordedRoutes(state), nil, state.Owner.Tun); err != nil {
		report(c.errors, fmt.Errorf("interrupted transaction cleanup failed; recovery state retained"))

		return err
	}

	state.Owned = []route{}
	state.Transaction = nil

	if err := c.save(state); err != nil {
		report(c.errors, fmt.Errorf("interrupted transaction cleanup failed; recovery state retained"))

		return err
	}

	return nil
}

func (c *controller) changeRoutes(removals, additions []route, tun string) error {
	includes := make([]route, 0)

	replacedExcludes := make([]route, 0)

	obsoleteExcludes := make([]route, 0)

	newIncludes := make([]route, 0)

	newExcludes := make([]route, 0)

	replacing := make(map[string]bool)

	for _, route := range additions {
		replacing[route.Dst] = true

		if route.Dev == tun {
			newIncludes = append(newIncludes, route)
		} else {
			newExcludes = append(newExcludes, route)
		}
	}

	for _, route := range removals {
		if route.Dev == tun {
			includes = append(includes, route)
		} else if replacing[route.Dst] {
			replacedExcludes = append(replacedExcludes, route)
		} else {
			obsoleteExcludes = append(obsoleteExcludes, route)
		}
	}

	if err := c.deleteOwned(includes); err != nil {
		return err
	}

	if err := c.deleteOwned(replacedExcludes); err != nil {
		return err
	}

	if err := c.kernel.change("add", newExcludes); err != nil {
		return err
	}

	if err := c.kernel.change("add", newIncludes); err != nil {
		return err
	}

	return c.deleteOwned(obsoleteExcludes)
}

func (c *controller) rollback(state *state) error {
	before, after := state.Transaction.Before, state.Transaction.After

	removals := make([]route, 0)

	for _, route := range after {
		if !containsRoute(before, route) {
			removals = append(removals, route)
		}
	}

	current, err := c.current(before)
	if err != nil {
		return err
	}

	missing := make([]route, 0)

	for _, route := range before {
		if containsRoute(current, route) {
			continue
		}

		for _, row := range current {
			if row.Dst == route.Dst && !containsRoute(removals, row) {
				return fmt.Errorf("rollback blocked by a foreign replacement; recovery state retained")
			}
		}

		missing = append(missing, route)
	}

	if err := c.changeRoutes(removals, missing, state.Owner.Tun); err != nil {
		return err
	}

	current, err = c.current(before)
	if err != nil {
		return err
	}

	for _, route := range before {
		if !containsRoute(current, route) {
			return fmt.Errorf("rollback verification failed; recovery state retained")
		}
	}

	state.Owned = before
	state.Transaction = nil

	return c.save(state)
}

func (c *controller) additions(desired []route, state *state) ([]route, []route, error) {
	rows, err := c.kernel.routes()
	if err != nil {
		return nil, nil, err
	}

	for i, row := range rows {
		if !privateProtocol(row) {
			continue
		}

		spec, err := routeSpec(row, fmt.Sprintf("protocol collision check, route %d", i+1))
		if err != nil {
			return nil, nil, err
		}

		if !containsRoute(state.Owned, spec) {
			return nil, nil, fmt.Errorf("private protocol 242 collision at route %d", i+1)
		}
	}

	current, err := exactRoutes(desired, rows)
	if err != nil {
		return nil, nil, err
	}

	additions, retained := make([]route, 0), make([]route, 0)

	for i, route := range desired {
		foreign := false

		for _, row := range current {
			if row.Dst != route.Dst || containsRoute(state.Owned, row) {
				continue
			}

			foreign = true

			if !equivalent(row, route) {
				return nil, nil, fmt.Errorf("desired entry %d: incompatible existing exact route", i+1)
			}
		}

		if foreign {
			continue
		}

		if containsRoute(current, route) {
			retained = append(retained, route)
		} else {
			additions = append(additions, route)
		}
	}

	return additions, retained, nil
}

func (c *controller) reconcile(state *state, desired []route) (result error) {
	additions, retained, err := c.additions(desired, state)
	if err != nil {
		return err
	}

	before := state.Owned

	after := append(append([]route{}, retained...), additions...)
	state.Transaction = &transaction{before, after}

	if err := c.save(state); err != nil {
		return err
	}

	defer func() {
		if result != nil {
			state.Transaction = &transaction{before, after}

			if err := c.rollback(state); err != nil {
				report(c.errors, fmt.Errorf("rollback failed: %s", safeError(err)))
			}
		}
	}()

	removals := make([]route, 0)

	for _, route := range before {
		if !containsRoute(retained, route) {
			removals = append(removals, route)
		}
	}

	if err := c.changeRoutes(removals, additions, state.Owner.Tun); err != nil {
		return err
	}

	current, err := c.current(desired)
	if err != nil {
		return err
	}

	for _, route := range after {
		if !containsRoute(current, route) {
			return fmt.Errorf("route installation verification failed")
		}
	}

	for _, route := range desired {
		found := false

		for _, row := range current {
			if equivalent(route, row) {
				found = true
				break
			}
		}

		if !found {
			return fmt.Errorf("route installation verification failed")
		}
	}

	state.Owned = after
	state.Transaction = nil

	return c.save(state)
}

func processIdentity(pid int) (*owner, error) {
	content, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
	if os.IsNotExist(err) {
		return nil, nil
	}

	if err != nil {
		return nil, err
	}

	start, alive, err := processStart(string(content))
	if err != nil || !alive {
		return nil, err
	}

	boot, err := os.ReadFile("/proc/sys/kernel/random/boot_id")
	if err != nil {
		return nil, err
	}

	return &owner{PID: pid, Start: start, Boot: strings.TrimSpace(string(boot))}, nil
}

func processStart(stat string) (string, bool, error) {
	end := strings.LastIndex(stat, ")")
	if end < 0 {
		return "", false, fmt.Errorf("process identity: invalid process status")
	}

	fields := strings.Fields(stat[end+1:])
	if len(fields) < 20 || !decimal(fields[19]) {
		return "", false, fmt.Errorf("process identity: invalid process status")
	}

	return fields[19], fields[0] != "Z" && fields[0] != "X", nil
}

func hookOwner(env map[string]string, identity func(int) (*owner, error)) (owner, error) {
	pid, err := strconv.Atoi(env["VPNPID"])
	if !decimal(env["VPNPID"]) || err != nil || pid < 1 {
		return owner{}, fmt.Errorf("a valid supplied VPNPID is required; parent PID inference is unsafe")
	}

	current, err := identity(pid)
	if err != nil {
		return owner{}, err
	}

	if current == nil {
		return owner{}, fmt.Errorf("VPNPID does not identify a live process")
	}

	if err := device(env["TUNDEV"]); err != nil {
		return owner{}, err
	}

	result := *current
	result.Tun = env["TUNDEV"]

	return result, nil
}

func ownerAlive(record owner, identity func(int) (*owner, error)) (bool, error) {
	current, err := identity(record.PID)
	if err != nil || current == nil {
		return false, err
	}

	return record.PID == current.PID && record.Start == current.Start && record.Boot == current.Boot, nil
}

func baseHook(env map[string]string, args []string) (int, error) {
	base := env["CORPNET_BASE_VPNC_SCRIPT"]
	if base == "" {
		return 0, fmt.Errorf("CORPNET_BASE_VPNC_SCRIPT is required")
	}

	clean := maps.Clone(env)
	clean["CISCO_SPLIT_INC"], clean["CISCO_SPLIT_EXC"] = "0", "0"

	cmd := exec.Command(base, args...)

	cmd.Env = envList(clean)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr

	if err := cmd.Run(); err != nil {
		if exit, ok := err.(*exec.ExitError); ok {
			if status, ok := exit.Sys().(syscall.WaitStatus); ok && status.Signaled() {
				return -int(status.Signal()), nil
			}

			return exit.ExitCode(), nil
		}

		return 0, err
	}

	return 0, nil
}

// These are the three process boundaries needed to exercise the lifecycle
// without acquiring a root lock, consulting live VPN processes, or running vpnc.
type lifecycle struct {
	controller *controller
	policyPath string
	lock       func(string) (io.Closer, error)
	identity   func(int) (*owner, error)
	base       func(map[string]string, []string) (int, error)
	output     io.Writer
}

func newLifecycle(output, errors io.Writer) *lifecycle {
	return &lifecycle{
		controller: &controller{
			path:   filepath.Join(runtimeDirectory, "routes.json"),
			kernel: kernel{runKernelCommand},
			errors: errors,
		},
		policyPath: policyPath,
		lock: func(directory string) (io.Closer, error) {
			return sessionLock(directory)
		},
		identity: processIdentity,
		base:     baseHook,
		output:   output,
	}
}

func (l *lifecycle) disconnect(env map[string]string, args []string) (int, error) {
	lock, cleanupErr := l.lock(filepath.Dir(l.controller.path))
	if cleanupErr == nil {
		defer lock.Close()

		var state *state

		state, cleanupErr = l.controller.load()
		if cleanupErr == nil && state != nil {
			var owner owner

			owner, cleanupErr = hookOwner(env, l.identity)
			if cleanupErr == nil && owner != state.Owner {
				cleanupErr = fmt.Errorf("disconnect does not match the recorded VPN owner")
			}

			if cleanupErr == nil {
				cleanupErr = l.controller.cleanup(state)
			}
		}
	}

	if cleanupErr != nil {
		report(l.controller.errors, cleanupErr)
	}

	status, err := l.base(env, args)
	if err != nil {
		return 0, err
	}

	if status != 0 {
		report(l.controller.errors, fmt.Errorf("base disconnect hook failed (exit %d)", status))

		return status, nil
	}

	if cleanupErr != nil {
		return 1, nil
	}

	return 0, nil
}

func (l *lifecycle) hook(env map[string]string, args []string) (int, error) {
	reason := env["reason"]
	if reason == "disconnect" {
		return l.disconnect(env, args)
	}

	if reason != "connect" && reason != "reconnect" {
		return l.base(env, args)
	}

	lock, err := l.lock(filepath.Dir(l.controller.path))
	if err != nil {
		return 0, err
	}

	defer lock.Close()

	owner, err := hookOwner(env, l.identity)
	if err != nil {
		return 0, err
	}

	data, err := loadPolicy(l.policyPath)
	if err != nil {
		return 0, err
	}

	data, err = serverPolicy(data, env)
	if err != nil {
		return 0, err
	}

	saved, err := l.controller.load()
	if err != nil {
		return 0, err
	}

	if saved != nil && saved.Owner != owner {
		alive, err := ownerAlive(saved.Owner, l.identity)
		if err != nil {
			return 0, err
		}

		if alive {
			return 0, fmt.Errorf("another live corpnet session owns the route state")
		}

		if err := l.controller.cleanup(saved); err != nil {
			return 0, err
		}

		saved = nil
	}

	if saved != nil && saved.Transaction != nil {
		if err := l.controller.recover(saved); err != nil {
			return 0, err
		}
	}

	if saved == nil {
		saved = &state{Version: 1, Owner: owner, Baseline: []routeRow{}, Owned: []route{}}
	}

	rows, err := l.controller.kernel.routes()
	if err != nil {
		return 0, err
	}

	saved.Baseline = normalBaseline(rows, owner.Tun)

	desired, err := desiredRoutes(data, saved.Baseline, owner.Tun)
	if err != nil {
		return 0, err
	}

	if _, _, err := l.controller.additions(desired, saved); err != nil {
		return 0, err
	}

	if err := l.controller.save(saved); err != nil {
		return 0, err
	}

	applied := false
	defer func() {
		if reason != "connect" || applied {
			return
		}

		cleanup := maps.Clone(env)
		cleanup["reason"] = "disconnect"

		status, err := l.base(cleanup, args)
		if err != nil {
			report(l.controller.errors, fmt.Errorf("base disconnect hook failed: %s", safeError(err)))
		} else if status != 0 {
			report(l.controller.errors, fmt.Errorf("base disconnect hook failed (exit %d)", status))
		}
	}()

	status, err := l.base(env, args)
	if err != nil {
		return 0, err
	}

	if status != 0 {
		report(l.controller.errors, fmt.Errorf("base %s hook failed (exit %d)", reason, status))

		return status, nil
	}

	if err := l.controller.reconcile(saved, desired); err != nil {
		return 0, err
	}

	applied = true

	fmt.Fprintf(l.output, "corpnet-vpn: applied %d includes, %d excludes; %d owned routes\n",
		len(data.Includes), len(data.Excludes), len(saved.Owned))

	return 0, nil
}

func (l *lifecycle) cleanup() error {
	lock, err := l.lock(filepath.Dir(l.controller.path))
	if err != nil {
		return err
	}

	defer lock.Close()

	state, err := l.controller.load()
	if err != nil || state == nil {
		return err
	}

	alive, err := ownerAlive(state.Owner, l.identity)
	if err != nil {
		return err
	}

	if alive {
		return fmt.Errorf("cleanup refused: recorded VPN owner is still alive")
	}

	return l.controller.cleanup(state)
}
