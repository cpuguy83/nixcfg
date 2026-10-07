package main

import (
	"os"
	"os/user"
)

func main() {
	command := cli{
		env:        environment(),
		euid:       os.Geteuid(),
		lifecycle:  newLifecycle(os.Stdout, os.Stderr),
		updater:    newUpdater(os.Stdout),
		lookupUser: user.Lookup,
		output:     os.Stdout,
		errors:     os.Stderr,
	}

	os.Exit(command.run(os.Args[1:]))
}
