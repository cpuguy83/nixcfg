package main

import (
	"bytes"
	"errors"
	"io"
	"maps"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"
	"testing"
)

func TestRouteSubcommands(t *testing.T) {
	t.Run("import options work before and after the XML path", func(t *testing.T) {
		for _, args := range [][]string{
			{"profile.xml", "--check", "--output", "policy.json"},
			{"--check", "--output", "policy.json", "profile.xml"},
			{"profile.xml", "--output=policy.json", "--check"},
			{"--output=policy.json", "--check", "--", "profile.xml"},
		} {
			actual, err := parseImport(args)
			requireNoError(t, err)

			requireEqual(t, actual, importArgs{xml: "profile.xml", output: "policy.json", check: true})
		}

		actual, err := parseImport([]string{"--", "--check"})
		requireNoError(t, err)

		requireEqual(t, actual, importArgs{xml: "--check", output: policyPath})
	})

	t.Run("invalid import arguments fail without exposing values", func(t *testing.T) {
		for _, args := range [][]string{
			{}, {"one", "two"}, {"one", "--unknown-private"}, {"one", "--output"},
			{"one", "--output", "--check"}, {"one", "--", "--check"},
		} {
			if _, err := parseImport(args); err == nil {
				t.Fatalf("accepted invalid synthetic args %#v", args)
			}
		}
	})

	t.Run("check is unprivileged and never writes", func(t *testing.T) {
		dir := t.TempDir()

		path, output := filepath.Join(dir, "profile.xml"), filepath.Join(dir, "policy.json")

		writeTestFile(t, path, testXML)

		var logs bytes.Buffer

		command := cli{euid: 1000, output: &logs, errors: &logs}

		status := command.run([]string{"import", path, "--check", "--output=" + output})

		requireEqual(t, status, 0)

		if _, err := os.Stat(output); !os.IsNotExist(err) {
			t.Fatal("check wrote a policy")
		}

		if !strings.Contains(logs.String(), "validated 1 includes, 1 excludes") {
			t.Fatal("missing count output")
		}
	})

	t.Run("import requires root and reports only safe failures", func(t *testing.T) {
		dir := t.TempDir()

		path, output := filepath.Join(dir, "profile.xml"), filepath.Join(dir, "policy.json")

		writeTestFile(t, path, testXML)

		writeTestFile(t, output, "previous policy")

		var logs bytes.Buffer

		command := cli{euid: 1000, output: &logs, errors: &logs}

		status := command.run([]string{"import", path, "--output", output})

		requireEqual(t, status, 1)
		requireEqual(t, readTestFile(t, output), "previous policy")

		if !strings.Contains(logs.String(), "requires root") {
			t.Fatal("missing privilege error")
		}
	})

	t.Run("lifecycle commands require root before reading state", func(t *testing.T) {
		for _, subcommand := range []string{"cleanup", "hook"} {
			var logs bytes.Buffer

			command := cli{euid: 1000, output: &logs, errors: &logs}

			status := command.run([]string{subcommand})

			requireEqual(t, status, 1)

			if !strings.Contains(logs.String(), "require root") {
				t.Fatal("missing root requirement")
			}
		}
	})

	t.Run("hook removes only the leading separator and preserves arguments", func(t *testing.T) {
		for _, separator := range []bool{false, true} {
			f := newLifecycleTest(t)
			var called []string

			f.lifecycle.base = func(env map[string]string, args []string) (int, error) {
				requireEqual(t, env["reason"], "pre-init")

				called = args

				return 9, nil
			}

			f.env["reason"] = "pre-init"
			args := []string{"hook"}

			if separator {
				args = append(args, "--")
			}

			args = append(args, "one", "two words", "--", "--private")

			command := cli{
				env:       f.env,
				lifecycle: f.lifecycle,
				output:    io.Discard,
				errors:    io.Discard,
			}

			status := command.run(args)

			requireEqual(t, status, 9)
			requireEqual(t, called, []string{"one", "two words", "--", "--private"})
		}
	})

	t.Run("usage errors do not expose unknown arguments", func(t *testing.T) {
		for _, args := range [][]string{nil, {"private"}, {"cleanup", "private"}, {"import", "file", "--private"}} {
			var logs bytes.Buffer

			command := cli{output: &logs, errors: &logs}

			status := command.run(args)

			requireEqual(t, status, 2)

			if strings.Contains(logs.String(), "private") {
				t.Fatal("argument leaked")
			}
		}
	})
}

func TestProfileSubcommands(t *testing.T) {
	t.Run("configured username and UPN are required for every operation", func(t *testing.T) {
		for _, operation := range []string{"eligible", "fetch", "install"} {
			for _, env := range []map[string]string{
				{}, {"CORPNET_PROFILE_USER": "synthetic"}, {"CORPNET_PROFILE_UPN": "user@example.com"},
			} {
				want := 1

				if operation == "eligible" {
					want = 255
				}

				command := cli{env: env, output: io.Discard, errors: io.Discard}

				status := command.run([]string{operation})

				requireEqual(t, status, want)
			}
		}
	})

	t.Run("NSS lookup failures never print account values", func(t *testing.T) {
		var logs bytes.Buffer

		lookup := func(string) (*user.User, error) {
			return nil, errors.New("private account user@example.com")
		}

		command := cli{
			env:        configuredEnv(),
			lookupUser: lookup,
			output:     &logs,
			errors:     &logs,
		}

		status := command.run([]string{"eligible"})

		requireEqual(t, status, 255)

		if strings.Contains(logs.String(), "user@example.com") || strings.Contains(logs.String(), "private account") {
			t.Fatal("account leaked")
		}
	})

	t.Run("help and invalid operations do not trigger account lookup", func(t *testing.T) {
		for _, test := range []struct {
			args []string
			want int
		}{
			{nil, 2}, {[]string{"unknown-private"}, 2}, {[]string{"--help"}, 0},
		} {
			var logs bytes.Buffer

			command := cli{output: &logs, errors: &logs}

			status := command.run(test.args)

			requireEqual(t, status, test.want)

			if strings.Contains(logs.String(), "unknown-private") {
				t.Fatal("unknown argument logged")
			}
		}
	})
}

func TestProcessBoundary(t *testing.T) {
	t.Run("base environment and argument vector change only IPv4 split counts", func(t *testing.T) {
		dir := t.TempDir()

		script := filepath.Join(dir, "base")
		// A local shell fixture checks the process boundary without any VPN tools.
		writeTestScript(t, script, `
test "$1" = "one" && test "$2" = "two words" || exit 11
test "$CISCO_SPLIT_INC" = 0 && test "$CISCO_SPLIT_EXC" = 0 || exit 12
test "$CISCO_IPV6_SPLIT_INC" = 7 || exit 13
test "$INTERNAL_IP4_DNS" = "192.0.2.53" || exit 14
test "$reason" = "pre-init" || exit 15
exit 9
`)

		env := map[string]string{
			"CORPNET_BASE_VPNC_SCRIPT": script, "CISCO_SPLIT_INC": "2", "CISCO_SPLIT_EXC": "3",
			"CISCO_IPV6_SPLIT_INC": "7", "INTERNAL_IP4_DNS": "192.0.2.53", "reason": "pre-init",
		}

		before := maps.Clone(env)

		status, err := baseHook(env, []string{"one", "two words"})
		requireNoError(t, err)

		requireEqual(t, status, 9)
		requireEqual(t, env, before)
	})

	t.Run("command failures expose only status and deduplicated AAD codes", func(t *testing.T) {
		dir := t.TempDir()

		script := filepath.Join(dir, "command")

		writeTestScript(t, script, `
printf '%s\n' 'synthetic-token-that-must-not-be-logged'
printf '%s\n' 'AADSTS50076 private 203.0.113.0/24 AADSTS50076 AADSTS50079' >&2
exit 2
`)

		output, err := runCommand([]string{script}, "broker", nil, "")

		requireEqual(t, output, "")
		requireError(t, err, "exit 2; AADSTS50076, AADSTS50079")

		for _, value := range []string{testToken, "203.0.113", "private", script} {
			if strings.Contains(err.Error(), value) {
				t.Fatal("command failure leaked captured content or arguments")
			}
		}
	})

	t.Run("missing executables do not expose private command arguments", func(t *testing.T) {
		_, err := runCommand([]string{"/nonexistent/private", testToken}, "broker", nil, "")
		requireError(t, err, "system operation failed")

		if strings.Contains(err.Error(), testToken) || strings.Contains(err.Error(), "private") {
			t.Fatal("command arguments leaked")
		}
	})

	t.Run("kernel failures never report private stderr or broker codes", func(t *testing.T) {
		script := filepath.Join(t.TempDir(), "ip")

		writeTestScript(t, script, `
printf '%s\n' 'private 203.0.113.0/24 AADSTS50076' >&2
exit 2
`)

		_, err := runKernelCommand([]string{script}, "route add batch 1 (1 entries)", nil, "")
		requireError(t, err, "batch 1 (1 entries) failed (exit 2)")

		if strings.Contains(err.Error(), "203.0.113") || strings.Contains(err.Error(), "AADSTS") {
			t.Fatal("kernel stderr leaked")
		}
	})
}

func writeTestScript(t *testing.T, path, content string) {
	t.Helper()

	shell, err := exec.LookPath("sh")
	requireNoError(t, err)

	writeTestFile(t, path, "#!"+shell+"\n"+content)

	requireNoError(t, os.Chmod(path, 0700))
}
