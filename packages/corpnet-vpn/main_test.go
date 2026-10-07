package main

import (
	"bytes"
	"os"
	"os/user"
	"strconv"
	"strings"
	"testing"
)

func TestCommandHelp(t *testing.T) {
	t.Run("one command advertises all six subcommands", func(t *testing.T) {
		var output bytes.Buffer

		command := cli{output: &output, errors: &output}

		status := command.run([]string{"--help"})

		requireEqual(t, status, 0)

		for _, subcommand := range []string{"import", "hook", "cleanup", "eligible", "fetch", "install"} {
			if !strings.Contains(output.String(), subcommand) {
				t.Fatalf("help is missing %s", subcommand)
			}
		}

		if !strings.Contains(output.String(), "corpnet-vpn") {
			t.Fatal("help must name the single executable")
		}
	})

	t.Run("subcommand help does not acquire privileges or consult accounts", func(t *testing.T) {
		for _, subcommand := range []string{"import", "hook", "cleanup", "eligible", "fetch", "install"} {
			var output bytes.Buffer

			command := cli{output: &output, errors: &output}

			status := command.run([]string{subcommand, "--help"})

			requireEqual(t, status, 0)
		}
	})

	t.Run("unknown commands and extra operation arguments are usage errors", func(t *testing.T) {
		for _, args := range [][]string{
			nil,
			{"unknown", "--help"},
			{"cleanup", "extra"},
			{"eligible", "extra"},
			{"fetch", "extra"},
			{"install", "extra"},
		} {
			var output bytes.Buffer

			command := cli{output: &output, errors: &output}

			status := command.run(args)

			requireEqual(t, status, 2)
		}
	})
}

func TestCommandDispatch(t *testing.T) {
	t.Run("hook and cleanup share the same recovery state", func(t *testing.T) {
		f := newLifecycleTest(t)
		f.env["reason"] = "connect"

		command := cli{
			env:       f.env,
			lifecycle: f.lifecycle,
			output:    &f.logs,
			errors:    &f.logs,
		}

		status := command.run([]string{"hook", "--", "argument with spaces"})

		requireEqual(t, status, 0)
		requireEqual(t, f.load().Owned, f.desired)

		f.current.Start = "789"

		status = command.run([]string{"cleanup"})

		requireEqual(t, status, 0)
		requireJSONEqual(t, f.kernel.rows, testBaseline())
	})

	t.Run("fetch writes a candidate through the single dispatcher", func(t *testing.T) {
		var output bytes.Buffer

		u := syntheticUpdater(t, 1000)
		u.output = &output

		installSyntheticBroker(t, u)
		installSyntheticDownload(t, u)

		command := cli{
			env:        configuredEnv(),
			euid:       1000,
			updater:    u,
			lookupUser: syntheticUser,
			output:     &output,
			errors:     &output,
		}

		status := command.run([]string{"fetch"})

		requireEqual(t, status, 0)

		data, err := loadPolicy(u.candidate)
		requireNoError(t, err)

		requireEqual(t, data, testPolicy(t))

		if !strings.Contains(output.String(), "corpnet-vpn: fetched") {
			t.Fatal("fetch output must identify the single executable")
		}
	})

	t.Run("install validation failures preserve the policy and fail normally", func(t *testing.T) {
		var output bytes.Buffer

		u := syntheticUpdater(t, os.Getuid())
		u.euid = 0
		u.output = &output

		writeTestFile(t, u.policy, "previous policy")
		writeTestFile(t, u.candidate, `{"version":1}`)

		command := cli{
			env:     configuredEnv(),
			updater: u,
			lookupUser: func(string) (*user.User, error) {
				return &user.User{Uid: strconv.Itoa(os.Getuid())}, nil
			},
			output: &output,
			errors: &output,
		}

		status := command.run([]string{"install"})

		requireEqual(t, status, 1)
		requireEqual(t, readTestFile(t, u.policy), "previous policy")

		if !strings.Contains(output.String(), "corpnet-vpn: policy: invalid schema") {
			t.Fatal("install must surface candidate validation through the shared dispatcher")
		}
	})
}
