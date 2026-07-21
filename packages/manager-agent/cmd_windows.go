//go:build windows
// +build windows

package main

import (
	"os/exec"
	"syscall"
)

// cmdHide creates an exec.Cmd with hidden console window (no popup).
func cmdHide(name string, args ...string) *exec.Cmd {
	cmd := exec.Command(name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	return cmd
}
