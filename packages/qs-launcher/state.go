package main

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unicode/utf8"
)

const queryFile = "qs-launcher-query"

func validateQuery(text string) error {
	units := 0
	for _, r := range text {
		units++
		if r > 0xffff {
			units++
		}
	}

	if !utf8.ValidString(text) || len(text) > lineLimit || units > 4096 || strings.ContainsRune(text, 0) {
		return errors.New("launcher query exceeds its limit or contains invalid text")
	}

	return nil
}

func queryDirectory() (int, error) {
	root := os.Getenv("XDG_RUNTIME_DIR")
	if !filepath.IsAbs(root) {
		return -1, errors.New("query memory requires an absolute XDG_RUNTIME_DIR")
	}

	fd, err := syscall.Open(filepath.Join(root, "qs-launcher"), syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_NOFOLLOW|syscall.O_CLOEXEC, 0)
	if err != nil {
		return -1, err
	}

	var info syscall.Stat_t
	err = syscall.Fstat(fd, &info)
	if err != nil || info.Uid != uint32(os.Getuid()) || info.Mode&07777 != 0700 {
		syscall.Close(fd)
		return -1, errors.New("query memory requires an owner-only session directory")
	}

	return fd, nil
}

func checkQueryFile(fd int) error {
	var info syscall.Stat_t
	if err := syscall.Fstat(fd, &info); err != nil {
		return err
	}

	if info.Mode&syscall.S_IFMT != syscall.S_IFREG || info.Uid != uint32(os.Getuid()) ||
		info.Mode&07777 != 0600 || info.Nlink != 1 {
		return errors.New("query memory requires a private regular file")
	}

	return nil
}

func readQuery() (text string, err error) {
	defer func() {
		if err != nil {
			text, err = "", errors.New("cannot read private launcher query memory")
		}
	}()

	directory, err := queryDirectory()
	if err != nil {
		return "", err
	}
	defer syscall.Close(directory)

	fd, err := syscall.Openat(directory, queryFile, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK|syscall.O_CLOEXEC, 0)
	if errors.Is(err, syscall.ENOENT) {
		return "", nil
	}
	if err != nil {
		return "", err
	}

	file := os.NewFile(uintptr(fd), queryFile)
	defer file.Close()
	if err := checkQueryFile(fd); err != nil {
		return "", err
	}

	data, err := io.ReadAll(io.LimitReader(file, lineLimit+1))
	if err != nil {
		return "", err
	}

	text = string(data)
	return text, validateQuery(text)
}

func saveQuery(text string) (err error) {
	if err = validateQuery(text); err != nil {
		return err
	}

	defer func() {
		if err != nil {
			err = errors.New("cannot save private launcher query memory")
		}
	}()

	directory, err := queryDirectory()
	if err != nil {
		return err
	}
	defer syscall.Close(directory)

	pending := queryFile + ".pending"
	flags := syscall.O_WRONLY | syscall.O_NOFOLLOW | syscall.O_NONBLOCK | syscall.O_CLOEXEC
	fd, err := syscall.Openat(directory, pending, flags|syscall.O_CREAT|syscall.O_EXCL, 0600)
	created := err == nil
	if errors.Is(err, syscall.EEXIST) {
		fd, err = syscall.Openat(directory, pending, flags, 0)
	}
	if err != nil {
		return err
	}

	file := os.NewFile(uintptr(fd), pending)
	defer file.Close()
	if created {
		if err := file.Chmod(0600); err != nil {
			return err
		}
	}
	if err := checkQueryFile(fd); err != nil {
		return err
	}

	if err := file.Truncate(0); err != nil {
		return err
	}
	if _, err := io.WriteString(file, text); err != nil {
		return err
	}
	if err := file.Sync(); err != nil {
		return err
	}

	return syscall.Renameat(directory, pending, directory, queryFile)
}
