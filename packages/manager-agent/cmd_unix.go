//go:build !windows
// +build !windows

package main

import "os/exec"

// cmdHide is a no-op on non-Windows platforms.
func cmdHide(name string, args ...string) *exec.Cmd {
	return exec.Command(name, args...)
}
