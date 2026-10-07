package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestQueryMemoryRoundTrip(t *testing.T) {
	root := testRuntime(t, true)
	got, err := readQuery()
	if err != nil || got != "" {
		t.Fatalf("missing value: %q, %v", got, err)
	}

	for _, value := range []string{"Firefox", "  app \t ", "=2 m to cm", "1+2", "\u2603", "", " ", strings.Repeat("x", 4096), strings.Repeat("\U0001f600", 2048)} {
		if err := saveQuery(value); err != nil {
			t.Fatal(err)
		}

		if got, err := readQuery(); err != nil || got != value {
			t.Fatalf("round trip: got %q, %v", got, err)
		}

		info, err := os.Stat(filepath.Join(root, "qs-launcher", queryFile))
		if err != nil || info.Mode().Perm() != 0600 {
			t.Fatalf("private file: %v", err)
		}

		files, err := os.ReadDir(filepath.Join(root, "qs-launcher"))
		if err != nil || len(files) != 1 {
			t.Fatalf("pending file retained: %v", err)
		}
	}
}

func TestQueryMemoryRejectsCorruption(t *testing.T) {
	root := testRuntime(t, true)
	path := filepath.Join(root, "qs-launcher", queryFile)

	for _, value := range []string{"\xff", "\x00", strings.Repeat("x", 4097), strings.Repeat("\U0001f600", 2049), strings.Repeat("x", lineLimit+1)} {
		if err := saveQuery(value); err == nil {
			t.Fatal("invalid query saved")
		}

		if err := os.WriteFile(path, []byte(value), 0600); err != nil {
			t.Fatal(err)
		}

		if _, err := readQuery(); err == nil || err.Error() != "cannot read private launcher query memory" {
			t.Fatalf("corruption diagnostic: %v", err)
		}
	}
}

func TestQueryMemoryRequiresPrivateStorage(t *testing.T) {
	t.Run("directory must already exist", func(t *testing.T) {
		root := testRuntime(t, false)

		if _, err := readQuery(); err == nil {
			t.Fatal("missing directory accepted")
		}
		if err := saveQuery("synthetic"); err == nil {
			t.Fatal("created missing directory")
		}
		if _, err := os.Stat(filepath.Join(root, "qs-launcher")); !os.IsNotExist(err) {
			t.Fatal("query directory unexpectedly created")
		}
	})

	t.Run("directory permissions", func(t *testing.T) {
		root := testRuntime(t, true)
		if err := os.Chmod(filepath.Join(root, "qs-launcher"), 0755); err != nil {
			t.Fatal(err)
		}

		if _, err := readQuery(); err == nil {
			t.Fatal("public directory accepted")
		}
	})

	t.Run("file permissions", func(t *testing.T) {
		root := testRuntime(t, true)
		if err := saveQuery("synthetic"); err != nil {
			t.Fatal(err)
		}

		for _, mode := range []os.FileMode{0644, 0400, 0000} {
			if err := os.Chmod(filepath.Join(root, "qs-launcher", queryFile), mode); err != nil {
				t.Fatal(err)
			}

			if _, err := readQuery(); err == nil {
				t.Fatal("unsafe file accepted")
			}
		}
	})

	t.Run("symlinks are rejected", func(t *testing.T) {
		root := testRuntime(t, true)
		target := filepath.Join(root, "synthetic-target")
		if err := os.WriteFile(target, []byte("previous"), 0600); err != nil {
			t.Fatal(err)
		}

		for _, name := range []string{queryFile, queryFile + ".pending"} {
			if err := os.Symlink(target, filepath.Join(root, "qs-launcher", name)); err != nil {
				t.Fatal(err)
			}
		}

		if _, err := readQuery(); err == nil {
			t.Fatal("followed memory symlink")
		}
		if err := saveQuery("replacement"); err == nil {
			t.Fatal("followed pending symlink")
		}

		got, err := os.ReadFile(target)
		if err != nil || string(got) != "previous" {
			t.Fatal("symlink target changed")
		}
	})

	t.Run("pending files are reused", func(t *testing.T) {
		root := testRuntime(t, true)
		if err := os.WriteFile(filepath.Join(root, "qs-launcher", queryFile+".pending"), []byte("old long pending query"), 0600); err != nil {
			t.Fatal(err)
		}

		if err := saveQuery(""); err != nil {
			t.Fatal(err)
		}

		if got, err := readQuery(); err != nil || got != "" {
			t.Fatalf("empty save: %q, %v", got, err)
		}
	})
}
