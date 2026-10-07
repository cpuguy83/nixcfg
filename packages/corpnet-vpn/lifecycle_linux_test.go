package main

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"testing"
)

func TestLifecycle(t *testing.T) {
	t.Run("connect and disconnect preserve normal routes without a readable policy", func(t *testing.T) {
		for _, missing := range []bool{false, true} {
			f := newLifecycleTest(t)

			f.hook("connect")

			saved := f.load()

			requireJSONEqual(t, saved.Baseline, testBaseline())

			info, err := os.Stat(f.controller.path)
			requireNoError(t, err)

			requireEqual(t, info.Mode().Perm(), os.FileMode(0600))

			if missing {
				f.lifecycle.policyPath = filepath.Join(t.TempDir(), "missing")
			} else {
				writeTestFile(t, f.lifecycle.policyPath, "invalid")
			}

			f.hook("disconnect")

			requireJSONEqual(t, f.kernel.rows, testBaseline())

			if _, err := os.Stat(f.controller.path); !os.IsNotExist(err) {
				t.Fatal("cleanup retained state")
			}
		}
	})

	t.Run("carrier loss does not prevent owned route cleanup", func(t *testing.T) {
		for _, flag := range []string{"linkdown", "dead"} {
			f := newLifecycleTest(t)

			f.hook("connect")

			for _, row := range f.kernel.rows {
				row["flags"] = []string{flag}
			}

			normal := cloneRows(t, f.kernel.rows[:2])

			f.hook("disconnect")

			requireJSONEqual(t, f.kernel.rows, normal)
		}
	})

	t.Run("pushed DNS outside XML includes uses the tunnel", func(t *testing.T) {
		f := newLifecycleTest(t)
		f.env["INTERNAL_IP4_DNS"] = "2001:db8::53 198.51.100.53  192.0.2.53 198.51.100.53"

		f.hook("connect")

		for _, address := range []string{"198.51.100.53", "192.0.2.53"} {
			requireEqual(t, lookupRoute(t, f.kernel.rows, address)["dev"], "tun0")
		}

		requireEqual(t, len(f.load().Owned), 4)
		requireEqual(t, f.baseCalls[0]["INTERNAL_IP4_DNS"], f.env["INTERNAL_IP4_DNS"])

		f.hook("disconnect")

		requireJSONEqual(t, f.kernel.rows, testBaseline())
	})

	t.Run("gateway includes replace exact profile exclusions through disconnect", func(t *testing.T) {
		f := newLifecycleTest(t)
		f.env["CISCO_SPLIT_INC"] = "1"
		f.env["CISCO_SPLIT_INC_0_ADDR"] = "198.51.100.0"
		f.env["CISCO_SPLIT_INC_0_MASKLEN"] = "24"

		f.hook("connect")

		requireEqual(t, lookupRoute(t, f.kernel.rows, "198.51.100.1")["dev"], "tun0")
		requireEqual(t, len(f.load().Owned), 2)

		f.hook("disconnect")

		requireJSONEqual(t, f.kernel.rows, testBaseline())
	})

	t.Run("explicit full tunnel fails before calling the base", func(t *testing.T) {
		f := newLifecycleTest(t)
		f.env["CISCO_SPLIT_INC"], f.env["CISCO_SPLIT_INC_0_ADDR"], f.env["CISCO_SPLIT_INC_0_MASKLEN"] = "1", "0.0.0.0", "0"

		_, err := f.call("connect")
		requireError(t, err, "incompatible existing exact route")

		requireEqual(t, len(f.baseCalls), 0)
		requireJSONEqual(t, f.kernel.rows, testBaseline())
	})

	t.Run("baseline is captured before base mutations", func(t *testing.T) {
		f := newLifecycleTest(t)
		added := routeRow{"dst": "198.51.100.128/25", "dev": "eth0", "gateway": "192.0.2.9"}

		f.lifecycle.base = func(env map[string]string, args []string) (int, error) {
			requireEqual(t, args, []string{"argument with spaces"})

			f.kernel.rows = append(f.kernel.rows, added)

			return 0, nil
		}

		f.hook("connect")

		requireJSONEqual(t, f.load().Baseline, testBaseline())
		requireEqual(t, lookupRoute(t, f.kernel.rows, "198.51.100.129")["gateway"], "192.0.2.9")
	})

	t.Run("equivalent foreign routes are borrowed without ownership", func(t *testing.T) {
		f := newLifecycleTest(t)
		borrowed := f.desired[1]
		borrowed.Protocol = 4

		f.kernel.rows = append(f.kernel.rows, routeRows(t, []route{borrowed})...)

		f.hook("connect")

		requireEqual(t, f.load().Owned, []route{f.desired[0]})

		f.hook("disconnect")

		requireJSONEqual(t, f.kernel.rows, append(testBaseline(), routeRows(t, []route{borrowed})...))
	})

	t.Run("foreign conflicts and protocol collisions fail before mutation", func(t *testing.T) {
		for _, collision := range []bool{false, true} {
			f := newLifecycleTest(t)
			foreign := f.desired[0]
			message := "incompatible"

			if collision {
				foreign.Dst = "192.0.2.128/25"
				message = "protocol 242 collision"
			} else {
				foreign.Protocol, foreign.Dev = 4, "foreign0"
			}

			f.kernel.rows = append(f.kernel.rows, routeRows(t, []route{foreign})...)

			_, err := f.call("connect")
			requireError(t, err, message)

			requireEqual(t, len(f.kernel.calls), 0)
			requireEqual(t, len(f.baseCalls), 0)
		}
	})

	t.Run("conflicts created by the base are not overwritten", func(t *testing.T) {
		f := newLifecycleTest(t)
		foreign := f.desired[0]
		foreign.Dev, foreign.Protocol = "foreign0", 4

		f.lifecycle.base = func(env map[string]string, args []string) (int, error) {
			if env["reason"] == "connect" {
				f.kernel.rows = append(f.kernel.rows, routeRows(t, []route{foreign})...)
			}

			return 0, nil
		}

		_, err := f.call("connect")
		requireError(t, err, "incompatible")

		requireEqual(t, len(f.kernel.calls), 0)
		requireJSONEqual(t, f.kernel.rows, append(testBaseline(), routeRows(t, []route{foreign})...))
	})

	t.Run("reconnect reconciles saved and pushed policy", func(t *testing.T) {
		f := newLifecycleTest(t)

		f.hook("connect")

		f.policy([]string{"203.0.113.128/25"}, nil)

		f.env["CISCO_SPLIT_INC"], f.env["CISCO_SPLIT_INC_0_ADDR"], f.env["CISCO_SPLIT_INC_0_MASKLEN"] = "1", "198.51.100.128", "25"

		f.hook("reconnect")

		owned := f.load().Owned

		requireEqual(t, len(owned), 2)
		requireEqual(t, owned[0].Dst, "198.51.100.128/25")
		requireEqual(t, owned[1].Dst, "203.0.113.128/25")

		for _, route := range owned {
			requireEqual(t, route.Dev, "tun0")
		}

		f.hook("disconnect")

		requireJSONEqual(t, f.kernel.rows, testBaseline())
	})

	t.Run("reconnect refreshes gateway source and normal baseline", func(t *testing.T) {
		f := newLifecycleTest(t)

		f.hook("connect")

		normal := testBaseline()
		normal[0]["dev"], normal[0]["gateway"], normal[0]["prefsrc"] = "wlan0", "192.0.2.129", "192.0.2.130"
		normal[1]["dev"], normal[1]["dst"], normal[1]["prefsrc"] = "wlan0", "192.0.2.128/25", "192.0.2.130"
		unrelated := f.desired[0]
		unrelated.Dst, unrelated.Protocol = "192.0.2.254/32", 4

		f.kernel.rows = append(cloneRows(t, normal), routeRows(t, append(f.load().Owned, unrelated))...)
		f.kernel.unavailable["192.0.2.1"] = true

		f.hook("reconnect")

		saved := f.load()

		requireJSONEqual(t, saved.Baseline, normal)

		exclusion := saved.Owned[1]

		requireEqual(t, exclusion.Dev, "wlan0")
		requireEqual(t, exclusion.Gateway, "192.0.2.129")
		requireEqual(t, exclusion.Prefsrc, "192.0.2.130")

		f.hook("disconnect")

		requireJSONEqual(t, f.kernel.rows, append(normal, routeRows(t, []route{unrelated})...))
	})

	t.Run("interrupted transactions clean recorded routes without restoring dead gateways", func(t *testing.T) {
		f := newLifecycleTest(t)

		f.hook("connect")

		saved := f.load()

		updated, err := makePolicy([]string{"203.0.113.128/25"}, []string{"198.51.100.128/25"})
		requireNoError(t, err)

		after, err := desiredRoutes(updated, testBaseline(), "tun0")
		requireNoError(t, err)

		saved.Transaction = &transaction{saved.Owned, after}
		requireNoError(t, f.controller.save(saved))

		normal := testBaseline()
		normal[0]["gateway"], normal[0]["prefsrc"] = "192.0.2.2", "192.0.2.20"
		foreign := after[0]
		foreign.Protocol, foreign.Dev = 4, "foreign0"

		f.kernel.rows = append(cloneRows(t, normal), routeRows(t, []route{saved.Owned[0], after[1], foreign})...)
		f.kernel.unavailable["192.0.2.1"] = true

		f.hook("reconnect")

		if !strings.Contains(f.logs.String(), "recovering interrupted transaction") {
			t.Fatal("recovery was not reported")
		}

		saved = f.load()

		requireEqual(t, saved.Transaction, (*transaction)(nil))
		requireJSONEqual(t, saved.Baseline, append(normal, routeRows(t, []route{foreign})...))
		requireEqual(t, saved.Owned[1].Gateway, "192.0.2.2")

		f.hook("disconnect")

		requireJSONEqual(t, f.kernel.rows, append(normal, routeRows(t, []route{foreign})...))
	})

	t.Run("interrupted cleanup failures retain precise recovery state", func(t *testing.T) {
		f := newLifecycleTest(t)

		saved := f.newState()
		saved.Transaction = &transaction{[]route{}, f.desired}
		requireNoError(t, f.controller.save(saved))

		f.kernel.rows = append(f.kernel.rows, routeRows(t, f.desired)...)
		f.kernel.failures[2] = true

		_, err := f.call("reconnect")
		requireError(t, err, "synthetic mutation failure")

		requireJSONEqual(t, f.load(), saved)
		requireEqual(t, len(f.baseCalls), 0)

		if !strings.Contains(f.logs.String(), "cleanup failed; recovery state retained") {
			t.Fatal("recovery retention was not reported")
		}

		f.hook("reconnect")

		f.hook("disconnect")

		requireJSONEqual(t, f.kernel.rows, testBaseline())
	})

	t.Run("transitions retain old exclusions until new policy is installed", func(t *testing.T) {
		f := newLifecycleTest(t)

		f.hook("connect")

		requireEqual(t, f.kernel.callSummary(), []string{"add 198.51.100.0/24", "add 203.0.113.0/24"})

		f.kernel.calls = nil

		f.policy([]string{"203.0.113.128/25"}, []string{"198.51.100.128/25"})

		f.hook("reconnect")

		requireEqual(t, f.kernel.callSummary(), []string{
			"del 203.0.113.0/24", "add 198.51.100.128/25", "add 203.0.113.128/25", "del 198.51.100.0/24",
		})
	})

	t.Run("foreign replacements survive update and cleanup", func(t *testing.T) {
		for _, sameProtocol := range []bool{false, true} {
			f := newLifecycleTest(t)

			f.hook("connect")

			replacement := f.desired[1]
			replacement.Gateway = "192.0.2.9"

			if !sameProtocol {
				replacement.Protocol = 4
			}

			f.kernel.replace(f.desired[1], replacement)

			if !sameProtocol {
				f.policy([]string{"203.0.113.0/24"}, nil)

				f.hook("reconnect")
			}

			f.hook("disconnect")

			requireJSONEqual(t, f.kernel.rows, append(testBaseline(), routeRows(t, []route{replacement})...))
		}
	})

	t.Run("partial add failure rolls back and preserves the original error", func(t *testing.T) {
		f := newLifecycleTest(t)
		f.kernel.failures[2] = true

		_, err := f.call("connect")
		requireError(t, err, "synthetic mutation failure")

		requireJSONEqual(t, f.kernel.rows, testBaseline())
		requireEqual(t, f.load().Owned, []route{})
		requireEqual(t, f.load().Transaction, (*transaction)(nil))
		requireEqual(t, f.baseReasons(), []string{"connect", "disconnect"})
	})

	t.Run("ownership is durable before every route mutation", func(t *testing.T) {
		f := newLifecycleTest(t)

		f.kernel.beforeChange = func(action string, rows []route) {
			saved := f.load()
			if saved.Transaction == nil {
				t.Fatal("mutation without durable transaction")
			}

			recorded := saved.Transaction.After

			if action == "del" {
				recorded = saved.Transaction.Before
			}

			for _, route := range rows {
				if !containsRoute(recorded, route) {
					t.Fatal("mutation not present in durable transaction")
				}
			}
		}

		f.hook("connect")

		f.policy([]string{"203.0.113.128/25"}, nil)

		f.hook("reconnect")
	})

	t.Run("rollback failure retains write ahead recovery", func(t *testing.T) {
		f := newLifecycleTest(t)
		f.kernel.failures[2], f.kernel.failures[3] = true, true

		_, err := f.call("connect")
		requireError(t, err, "synthetic mutation failure")

		if !strings.Contains(f.logs.String(), "rollback failed") {
			t.Fatal("rollback failure not reported")
		}

		requireEqual(t, f.baseReasons(), []string{"connect", "disconnect"})
		requireEqual(t, f.load().Transaction.After, f.desired)

		f.hook("reconnect")

		requireEqual(t, f.load().Transaction, (*transaction)(nil))

		f.hook("disconnect")

		requireJSONEqual(t, f.kernel.rows, testBaseline())
	})

	t.Run("update failure restores the previous owned routes", func(t *testing.T) {
		f := newLifecycleTest(t)

		f.hook("connect")

		previous := f.load().Owned

		f.policy([]string{"203.0.113.128/25"}, nil)

		f.kernel.failures[f.kernel.operations+3] = true

		_, err := f.call("reconnect")
		requireError(t, err, "synthetic mutation failure")

		requireEqual(t, f.load().Owned, previous)

		current, err := f.controller.current(previous)
		requireNoError(t, err)

		for _, route := range previous {
			if !containsRoute(current, route) {
				t.Fatal("previous route missing after rollback")
			}
		}

		requireEqual(t, len(f.kernel.rows), len(testBaseline())+len(previous))
	})

	t.Run("pending cleanup preserves a foreign replacement", func(t *testing.T) {
		f := newLifecycleTest(t)

		saved := f.newState()
		saved.Transaction = &transaction{[]route{}, f.desired}
		requireNoError(t, f.controller.save(saved))

		foreign := f.desired[1]
		foreign.Protocol = 4

		f.kernel.rows = append(f.kernel.rows, routeRows(t, []route{f.desired[0], foreign})...)

		f.hook("disconnect")

		requireJSONEqual(t, f.kernel.rows, append(testBaseline(), routeRows(t, []route{foreign})...))
	})

	t.Run("stale owners are cleaned before a new session", func(t *testing.T) {
		f := newLifecycleTest(t)

		f.hook("connect")

		f.current.Start = "789"

		f.hook("connect")

		requireEqual(t, f.load().Owner.Start, "789")
		requireEqual(t, len(f.kernel.rows), 4)
	})

	t.Run("another live owner is never cleaned", func(t *testing.T) {
		f := newLifecycleTest(t)

		f.hook("connect")

		previous := cloneRows(t, f.kernel.rows)
		f.env["VPNPID"] = "124"

		f.lifecycle.identity = func(pid int) (*owner, error) {
			result := testOwner
			result.PID = pid

			return &result, nil
		}

		_, err := f.call("connect")
		requireError(t, err, "another live")

		requireJSONEqual(t, f.kernel.rows, previous)
	})

	t.Run("disconnect calls the base despite custom cleanup failures", func(t *testing.T) {
		for _, failure := range []string{"corrupt", "delete", "owner", "lock"} {
			t.Run(failure, func(t *testing.T) {
				f := newLifecycleTest(t)

				f.hook("connect")

				switch failure {
				case "corrupt":
					writeTestFile(t, f.controller.path, `{"version":1}`)

				case "delete":
					f.kernel.failures[f.kernel.operations+1] = true

				case "owner":
					f.current.Start = "789"

				case "lock":
					f.lifecycle.lock = func(string) (io.Closer, error) {
						return nil, syscall.EACCES
					}
				}

				f.baseCalls = nil

				status, err := f.call("disconnect")
				requireNoError(t, err)

				requireEqual(t, status, 1)
				requireEqual(t, f.baseReasons(), []string{"disconnect"})
			})
		}
	})

	t.Run("base exit status wins over cleanup failure", func(t *testing.T) {
		f := newLifecycleTest(t)

		f.lifecycle.base = func(map[string]string, []string) (int, error) {
			return 37, nil
		}

		status, err := f.call("connect")
		requireNoError(t, err)

		requireEqual(t, status, 37)
		requireEqual(t, len(f.kernel.calls), 0)

		writeTestFile(t, f.controller.path, "invalid")

		status, err = f.call("disconnect")
		requireNoError(t, err)

		requireEqual(t, status, 37)
	})

	t.Run("failed initial base attempts always disconnect without masking original errors", func(t *testing.T) {
		for _, original := range []error{nil, errors.New("original base failure"), syscall.EIO} {
			for _, cleanup := range []error{nil, errors.New("cleanup failure"), syscall.EACCES} {
				f := newLifecycleTest(t)
				var reasons []string

				f.lifecycle.base = func(env map[string]string, args []string) (int, error) {
					reasons = append(reasons, env["reason"])

					requireEqual(t, args, []string{"argument with spaces"})

					if env["reason"] == "disconnect" {
						return 19, cleanup
					}

					return 37, original
				}

				status, err := f.call("connect")
				if err != original {
					t.Fatalf("original error lost: %v", err)
				}

				if err == nil {
					requireEqual(t, status, 37)
				}

				requireEqual(t, reasons, []string{"connect", "disconnect"})

				if !strings.Contains(f.logs.String(), "base disconnect hook failed") {
					t.Fatal("cleanup failure not reported separately")
				}
			}
		}
	})

	t.Run("install failures report base cleanup errors separately", func(t *testing.T) {
		f := newLifecycleTest(t)
		f.kernel.failures[2] = true

		f.lifecycle.base = func(env map[string]string, args []string) (int, error) {
			if env["reason"] == "disconnect" {
				return 0, errors.New("cleanup failure")
			}

			return 0, nil
		}

		_, err := f.call("connect")
		requireError(t, err, "synthetic mutation failure")

		if !strings.Contains(f.logs.String(), "base disconnect hook failed: cleanup failure") {
			t.Fatal("cleanup error not reported")
		}

		requireJSONEqual(t, f.kernel.rows, testBaseline())
	})

	t.Run("reconnect failure never disconnects the base", func(t *testing.T) {
		f := newLifecycleTest(t)

		f.hook("connect")

		var reasons []string

		f.lifecycle.base = func(env map[string]string, args []string) (int, error) {
			reasons = append(reasons, env["reason"])

			return 37, nil
		}

		status, err := f.call("reconnect")
		requireNoError(t, err)

		requireEqual(t, status, 37)
		requireEqual(t, reasons, []string{"reconnect"})
	})

	t.Run("disconnect retains the lock through base cleanup", func(t *testing.T) {
		f := newLifecycleTest(t)
		var events []string

		f.lifecycle.lock = func(string) (io.Closer, error) {
			events = append(events, "lock")

			return closeFunc(func() error {
				events = append(events, "unlock")

				return nil
			}), nil
		}

		f.lifecycle.base = func(map[string]string, []string) (int, error) {
			events = append(events, "base")

			return 0, nil
		}

		f.hook("disconnect")

		requireEqual(t, events, []string{"lock", "base", "unlock"})
	})

	t.Run("stale cleanup refuses live owners and removes dead owners", func(t *testing.T) {
		f := newLifecycleTest(t)

		f.hook("connect")

		requireError(t, f.lifecycle.cleanup(), "still alive")

		if _, err := os.Stat(f.controller.path); err != nil {
			t.Fatal("live state lost")
		}

		f.lifecycle.identity = func(int) (*owner, error) {
			return nil, nil
		}
		requireNoError(t, f.lifecycle.cleanup())

		requireJSONEqual(t, f.kernel.rows, testBaseline())
	})

	t.Run("rollback never overwrites a foreign replacement", func(t *testing.T) {
		f := newLifecycleTest(t)

		saved := f.newState()
		saved.Owned = f.desired
		saved.Transaction = &transaction{f.desired, []route{}}
		foreign := f.desired[0]
		foreign.Protocol = 4

		f.kernel.rows = append(f.kernel.rows, routeRows(t, []route{foreign})...)
		requireNoError(t, f.controller.save(saved))

		err := f.controller.rollback(saved)
		requireError(t, err, "foreign replacement")

		requireEqual(t, len(f.kernel.calls), 0)
		requireEqual(t, f.load().Transaction.Before, f.desired)
	})

	t.Run("failed deletion verification retains state", func(t *testing.T) {
		f := newLifecycleTest(t)

		f.hook("connect")

		f.kernel.ignoreDelete = true

		status, err := f.call("disconnect")
		requireNoError(t, err)

		requireEqual(t, status, 1)
		requireEqual(t, f.load().Owned, f.desired)
	})

	t.Run("failed installation verification rolls back", func(t *testing.T) {
		f := newLifecycleTest(t)
		f.kernel.ignoreAdd = true

		_, err := f.call("connect")
		requireError(t, err, "installation verification")

		requireJSONEqual(t, f.kernel.rows, testBaseline())
		requireEqual(t, f.load().Owned, []route{})
	})
}

func TestProcessIdentity(t *testing.T) {
	t.Run("VPNPID is supplied and never inferred", func(t *testing.T) {
		for _, value := range []string{"", "0", "-1", "unknown", "1.0"} {
			_, err := hookOwner(map[string]string{"VPNPID": value, "TUNDEV": "tun0"}, func(int) (*owner, error) {
				t.Fatal("invalid VPNPID reached process lookup")

				return nil, nil
			})
			requireError(t, err, "VPNPID")
		}

		_, err := hookOwner(map[string]string{"VPNPID": "123", "TUNDEV": "tun0"},
			func(int) (*owner, error) {
				return nil, nil
			})
		requireError(t, err, "live process")
	})

	t.Run("PID reuse and boot changes do not match ownership", func(t *testing.T) {
		for _, test := range []struct {
			current *owner
			alive   bool
		}{
			{&testOwner, true}, {nil, false},
			{&owner{PID: 123, Start: "789", Boot: testOwner.Boot}, false},
			{&owner{PID: 123, Start: testOwner.Start, Boot: "other-boot"}, false},
		} {
			alive, err := ownerAlive(testOwner, func(int) (*owner, error) {
				return test.current, nil
			})
			requireNoError(t, err)

			requireEqual(t, alive, test.alive)
		}
	})

	t.Run("process status handles parentheses and rejects dead processes", func(t *testing.T) {
		for _, state := range []string{"S", "R", "Z", "X"} {
			content := "123 (process ) name) " + state + strings.Repeat(" 0", 18) + " 456 0"

			start, alive, err := processStart(content)
			requireNoError(t, err)

			requireEqual(t, start, "456")
			requireEqual(t, alive, state != "Z" && state != "X")
		}

		for _, content := range []string{"invalid", "123 (short) S", "123 (bad) " + strings.Repeat("x ", 20)} {
			_, _, err := processStart(content)
			requireError(t, err, "invalid process status")
		}
	})
}

var testOwner = owner{PID: 123, Start: "456", Boot: "synthetic-boot", Tun: "tun0"}

type lifecycleTest struct {
	t          *testing.T
	lifecycle  *lifecycle
	controller *controller
	kernel     *fakeKernel
	env        map[string]string
	current    owner
	desired    []route
	baseCalls  []map[string]string
	logs       bytes.Buffer
}

func newLifecycleTest(t *testing.T) *lifecycleTest {
	t.Helper()

	directory := t.TempDir()
	f := &lifecycleTest{
		t: t, current: testOwner,
		env: map[string]string{
			"VPNPID": "123", "TUNDEV": "tun0", "CORPNET_BASE_VPNC_SCRIPT": "/synthetic/vpnc-script",
		},
	}
	f.kernel = &fakeKernel{t: t, rows: cloneRows(t, testBaseline()), failures: map[int]bool{}, unavailable: map[string]bool{}}
	f.controller = &controller{path: filepath.Join(directory, "routes.json"), kernel: f.kernel, errors: &f.logs}
	f.lifecycle = &lifecycle{
		controller: f.controller, policyPath: filepath.Join(directory, "policy.json"), output: &f.logs,
		lock: func(string) (io.Closer, error) {
			return closeFunc(func() error {
				return nil
			}), nil
		},
		identity: func(int) (*owner, error) {
			result := f.current

			return &result, nil
		},
		base: func(env map[string]string, args []string) (int, error) {
			f.baseCalls = append(f.baseCalls, maps.Clone(env))

			requireEqual(t, args, []string{"argument with spaces"})

			return 0, nil
		},
	}

	f.desired = mustDesired(t, testPolicy(t), testBaseline())
	requireNoError(t, atomicJSON(f.lifecycle.policyPath, testPolicy(t), 0644, false))

	return f
}

func (f *lifecycleTest) newState() *state {
	return &state{Version: 1, Owner: testOwner, Baseline: cloneRows(f.t, testBaseline()), Owned: []route{}}
}

func (f *lifecycleTest) call(reason string) (int, error) {
	f.env["reason"] = reason

	return f.lifecycle.hook(f.env, []string{"argument with spaces"})
}

func (f *lifecycleTest) hook(reason string) {
	f.t.Helper()

	status, err := f.call(reason)
	requireNoError(f.t, err)

	requireEqual(f.t, status, 0)
}

func (f *lifecycleTest) policy(includes, excludes []string) {
	f.t.Helper()

	data, err := makePolicy(includes, excludes)
	requireNoError(f.t, err)
	requireNoError(f.t, atomicJSON(f.lifecycle.policyPath, data, 0644, false))
}

func (f *lifecycleTest) load() *state {
	f.t.Helper()

	state, err := f.controller.load()
	requireNoError(f.t, err)

	if state == nil {
		f.t.Fatal("state is missing")
	}

	return state
}

func (f *lifecycleTest) baseReasons() []string {
	reasons := make([]string, 0, len(f.baseCalls))

	for _, call := range f.baseCalls {
		reasons = append(reasons, call["reason"])
	}

	return reasons
}

type closeFunc func() error

func (f closeFunc) Close() error {
	return f()
}

type kernelCall struct {
	action string
	rows   []route
}

type fakeKernel struct {
	t            *testing.T
	rows         []routeRow
	calls        []kernelCall
	operations   int
	failures     map[int]bool
	unavailable  map[string]bool
	beforeChange func(string, []route)
	ignoreDelete bool
	ignoreAdd    bool
}

func (k *fakeKernel) routes() ([]routeRow, error) {
	return cloneRows(k.t, k.rows), nil
}

func (k *fakeKernel) change(action string, rows []route) error {
	if len(rows) == 0 {
		return nil
	}

	if k.beforeChange != nil {
		k.beforeChange(action, rows)
	}

	k.calls = append(k.calls, kernelCall{action, slices.Clone(rows)})

	for _, descriptor := range rows {
		k.operations++

		if k.failures[k.operations] {
			return fmt.Errorf("synthetic mutation failure")
		}

		switch action {
		case "add":
			if k.ignoreAdd {
				continue
			}

			if k.unavailable[descriptor.Gateway] {
				return fmt.Errorf("synthetic unavailable gateway")
			}

			for _, row := range k.rows {
				prefix, err := routePrefix(row, "synthetic")
				requireNoError(k.t, err)

				metric, err := number(field(row, "metric", 0), "synthetic")
				requireNoError(k.t, err)

				if prefix.String() == descriptor.Dst && metric == descriptor.Metric {
					return fmt.Errorf("synthetic duplicate route")
				}
			}

			k.rows = append(k.rows, routeRows(k.t, []route{descriptor})...)

		case "del":
			if k.ignoreDelete {
				continue
			}

			found := false

			for i, row := range k.rows {
				spec, err := routeSpec(row, "synthetic")
				requireNoError(k.t, err)

				if sameRoute(spec, descriptor) {
					k.rows = append(k.rows[:i], k.rows[i+1:]...)
					found = true
					break
				}
			}

			if !found {
				return fmt.Errorf("synthetic missing route")
			}

		default:
			k.t.Fatal("unsupported mutation")
		}
	}

	return nil
}

func (k *fakeKernel) replace(before, after route) {
	k.t.Helper()

	for i, row := range k.rows {
		spec, err := routeSpec(row, "synthetic")
		requireNoError(k.t, err)

		if sameRoute(spec, before) {
			k.rows = append(k.rows[:i], k.rows[i+1:]...)

			k.rows = append(k.rows, routeRows(k.t, []route{after})...)

			return
		}
	}

	k.t.Fatal("missing route for replacement")
}

func (k *fakeKernel) callSummary() []string {
	result := make([]string, 0)

	for _, call := range k.calls {
		for _, route := range call.rows {
			result = append(result, call.action+" "+route.Dst)
		}
	}

	return result
}

func cloneRows(t *testing.T, rows []routeRow) []routeRow {
	t.Helper()

	value, err := decodeJSON(encodeTestJSON(t, rows), "synthetic")
	requireNoError(t, err)

	list := value.([]any)

	result := make([]routeRow, 0, len(list))

	for _, value := range list {
		result = append(result, value.(map[string]any))
	}

	return result
}

func requireJSONEqual(t *testing.T, actual, expected any) {
	t.Helper()

	a, err := decodeJSON(encodeTestJSON(t, actual), "synthetic")
	requireNoError(t, err)

	b, err := decodeJSON(encodeTestJSON(t, expected), "synthetic")
	requireNoError(t, err)

	requireEqual(t, a, b)
}

func mustDesired(t *testing.T, data policy, baseline []routeRow) []route {
	t.Helper()

	routes, err := desiredRoutes(data, baseline, "tun0")
	requireNoError(t, err)

	return routes
}
