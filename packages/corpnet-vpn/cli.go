package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/user"
	"slices"
	"strconv"
	"strings"
	"syscall"
)

func environment() map[string]string {
	result := make(map[string]string)

	for _, entry := range os.Environ() {
		key, value, _ := strings.Cut(entry, "=")
		result[key] = value
	}

	return result
}

func envList(env map[string]string) []string {
	result := make([]string, 0, len(env))

	for key, value := range env {
		result = append(result, key+"="+value)
	}

	return result
}

func safeError(err error) string {
	var errno syscall.Errno

	if errors.As(err, &errno) {
		return fmt.Sprintf("OS error %d: %s", errno, errno.Error())
	}

	var path *os.PathError
	var link *os.LinkError
	var command *exec.Error

	if errors.As(err, &path) || errors.As(err, &link) || errors.As(err, &command) {
		return "system operation failed; no response content logged"
	}

	return err.Error()
}

func report(output io.Writer, err error) {
	fmt.Fprintf(output, "corpnet-vpn: %s\n", safeError(err))
}

type importArgs struct {
	xml    string
	output string
	check  bool
}

func parseImport(args []string) (importArgs, error) {
	result := importArgs{output: policyPath}
	options := true
	foundXML := false

	for i := 0; i < len(args); i++ {
		arg := args[i]

		switch {
		case options && arg == "--":
			options = false

		case options && arg == "--check":
			result.check = true

		case options && arg == "--output":
			i++

			if i >= len(args) || strings.HasPrefix(args[i], "--") {
				return result, fmt.Errorf("--output requires a path")
			}

			result.output = args[i]

		case options && strings.HasPrefix(arg, "--output="):
			result.output = strings.TrimPrefix(arg, "--output=")

		case options && strings.HasPrefix(arg, "-") && arg != "-":
			return result, fmt.Errorf("unsupported import option")

		default:
			if foundXML {
				return result, fmt.Errorf("import requires exactly one XML path")
			}

			result.xml, foundXML = arg, true
		}
	}

	if !foundXML {
		return result, fmt.Errorf("import requires exactly one XML path")
	}

	return result, nil
}

func importPolicy(args importArgs, euid int, output io.Writer) error {
	file, err := os.Open(args.xml)
	if err != nil {
		return err
	}

	defer file.Close()

	data, err := xmlPolicy(file)
	if err != nil {
		return err
	}

	action := "validated"

	if !args.check {
		if euid != 0 {
			return fmt.Errorf("import requires root; use --check for unprivileged validation")
		}

		if err := atomicJSON(args.output, data, 0644, true); err != nil {
			return err
		}

		action = "imported"
	}

	fmt.Fprintf(output, "corpnet-vpn: %s %d includes, %d excludes\n",
		action, len(data.Includes), len(data.Excludes))

	return nil
}

const usage = `usage: corpnet-vpn <subcommand>
  import XML [--check] [--output PATH]
  hook -- [args]
  cleanup
  eligible
  fetch
  install`

type cli struct {
	env        map[string]string
	euid       int
	lifecycle  *lifecycle
	updater    *updater
	lookupUser func(string) (*user.User, error)
	output     io.Writer
	errors     io.Writer
}

func (c *cli) run(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(c.errors, usage)

		return 2
	}

	if args[0] == "--help" || args[0] == "-h" {
		fmt.Fprintln(c.output, usage)

		return 0
	}

	operation := args[0]
	if !slices.Contains([]string{"import", "hook", "cleanup", "eligible", "fetch", "install"}, operation) {
		report(c.errors, fmt.Errorf("unknown subcommand"))

		return 2
	}

	if len(args) == 2 && (args[1] == "--help" || args[1] == "-h") {
		fmt.Fprintln(c.output, usage)

		return 0
	}

	if operation != "import" && operation != "hook" && len(args) != 1 {
		fmt.Fprintln(c.errors, usage)

		return 2
	}

	failureStatus := 1
	if operation == "eligible" {
		failureStatus = 255
	}

	var uid int
	var upn string
	var err error

	if operation == "eligible" || operation == "fetch" || operation == "install" {
		uid, upn, err = c.profileUser()
		if err != nil {
			report(c.errors, err)

			return failureStatus
		}
	}

	switch operation {
	case "import":
		var options importArgs

		options, err = parseImport(args[1:])
		if err != nil {
			report(c.errors, err)

			return 2
		}

		err = importPolicy(options, c.euid, c.output)

	case "hook", "cleanup":
		if c.euid != 0 {
			err = fmt.Errorf("route lifecycle commands require root")

			break
		}

		if operation == "cleanup" {
			err = c.lifecycle.cleanup()
		} else {
			forwarded := args[1:]
			if len(forwarded) != 0 && forwarded[0] == "--" {
				forwarded = forwarded[1:]
			}

			var status int

			status, err = c.lifecycle.hook(c.env, forwarded)
			if err == nil {
				return status
			}
		}

	case "eligible":
		var due bool

		due, err = c.updater.eligible(uid)
		if err == nil && !due {
			return 1
		}

	case "fetch":
		err = c.updater.fetch(uid, upn)

	case "install":
		err = c.updater.install(uid)
	}

	if err != nil {
		report(c.errors, err)

		return failureStatus
	}

	return 0
}

func (c *cli) profileUser() (int, string, error) {
	username, upn := c.env["CORPNET_PROFILE_USER"], c.env["CORPNET_PROFILE_UPN"]
	if username == "" || upn == "" {
		return 0, "", fmt.Errorf("configured username and UPN are required")
	}

	account, err := c.lookupUser(username)
	if err != nil {
		return 0, "", fmt.Errorf("system, account, or network operation failed; no response content logged")
	}

	uid, err := strconv.Atoi(account.Uid)
	if err != nil || uid < 0 {
		return 0, "", fmt.Errorf("configured user has an invalid UID")
	}

	return uid, upn, nil
}
