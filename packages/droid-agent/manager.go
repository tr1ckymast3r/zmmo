// manager.go — APK management + app operations

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"
)

// ── APK Install / Uninstall ──

type PackageParams struct {
	APKPath  string `json:"apkPath"`
	BundleID string `json:"bundleId"`
}

func handleInstall(raw json.RawMessage) (map[string]string, error) {
	var p PackageParams
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, fmt.Errorf("invalid params: %w", err)
	}
	if p.APKPath == "" {
		return nil, fmt.Errorf("apkPath required")
	}

	// pm install -r -d (allow downgrade)
	cmd := fmt.Sprintf("pm install -r -d '%s'", p.APKPath)
	out, err := runSu(cmd)
	if err != nil {
		return nil, fmt.Errorf("install: %w (%s)", err, out)
	}

	return map[string]string{
		"status": "installed",
		"output": out,
	}, nil
}

func handleUninstall(raw json.RawMessage) (map[string]string, error) {
	var p PackageParams
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, fmt.Errorf("invalid params: %w", err)
	}
	if p.BundleID == "" {
		return nil, fmt.Errorf("bundleId required")
	}

	cmd := fmt.Sprintf("pm uninstall %s", p.BundleID)
	out, err := runSu(cmd)
	if err != nil {
		return nil, fmt.Errorf("uninstall: %w (%s)", err, out)
	}

	return map[string]string{
		"status":   "uninstalled",
		"bundleId": p.BundleID,
		"output":   out,
	}, nil
}

// ── App Data Wipe ──

func handleWipeApp(raw json.RawMessage) (map[string]string, error) {
	var p PackageParams
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, fmt.Errorf("invalid params: %w", err)
	}
	if p.BundleID == "" {
		return nil, fmt.Errorf("bundleId required")
	}

	// Kill app
	runShell(fmt.Sprintf("am force-stop %s", p.BundleID))

	// Clear app data
	cmd := fmt.Sprintf("pm clear %s", p.BundleID)
	out, err := runSu(cmd)
	if err != nil {
		return nil, fmt.Errorf("wipe: %w (%s)", err, out)
	}

	return map[string]string{
		"status":   "wiped",
		"bundleId": p.BundleID,
		"output":   out,
	}, nil
}

// ── App Account Backup / Restore ──

type AccParams struct {
	BundleID string `json:"bundleId"`
	AccName  string `json:"accName"`
	Action   string `json:"action"` // "backup" or "restore"
}

func handleAccOp(raw json.RawMessage) (map[string]string, error) {
	var p AccParams
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, fmt.Errorf("invalid params: %w", err)
	}

	backupDir := fmt.Sprintf("/data/local/tmp/zmmo_farms/%s", p.BundleID)
	accDir := fmt.Sprintf("%s/%s", backupDir, p.AccName)

	// Find app data dir
	appDir := findAppDataDir(p.BundleID)
	if appDir == "" {
		return nil, fmt.Errorf("app data dir not found for %s", p.BundleID)
	}

	switch p.Action {
	case "backup":
		// Kill app first
		runShell(fmt.Sprintf("am force-stop %s", p.BundleID))
		time.Sleep(500)

		// Copy app data to backup
		os.MkdirAll(accDir, 0755)
		subdirs := []string{"shared_prefs", "databases", "files"}
		for _, sub := range subdirs {
			src := fmt.Sprintf("%s/%s", appDir, sub)
			dst := fmt.Sprintf("%s/%s", accDir, sub)
			if _, err := os.Stat(src); err == nil {
				runSu(fmt.Sprintf("cp -r %s %s", src, dst))
			}
		}
		return map[string]string{"status": "backed_up", "bundleId": p.BundleID, "accName": p.AccName}, nil

	case "restore":
		// Kill app
		runShell(fmt.Sprintf("am force-stop %s", p.BundleID))
		time.Sleep(500)

		// Copy backup to app data
		subdirs := []string{"shared_prefs", "databases", "files"}
		for _, sub := range subdirs {
			src := fmt.Sprintf("%s/%s", accDir, sub)
			dst := fmt.Sprintf("%s/%s", appDir, sub)
			if _, err := os.Stat(src); err == nil {
				runSu(fmt.Sprintf("rm -rf %s", dst))
				runSu(fmt.Sprintf("cp -r %s %s", src, dst))
			}
		}
		// Fix permissions
		runSu(fmt.Sprintf("chown -R $(stat -c%%u:%g %s) %s", appDir, appDir))
		return map[string]string{"status": "restored", "bundleId": p.BundleID, "accName": p.AccName}, nil

	default:
		return nil, fmt.Errorf("unknown action: %s", p.Action)
	}
}

func findAppDataDir(bundleID string) string {
	// Try common paths
	paths := []string{
		fmt.Sprintf("/data/data/%s", bundleID),
		fmt.Sprintf("/data/user/0/%s", bundleID),
	}
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	// Try pm path
	out, _ := runShell(fmt.Sprintf("pm path %s 2>/dev/null", bundleID))
	if out != "" && strings.Contains(out, ":") {
		return fmt.Sprintf("/data/data/%s", bundleID)
	}
	return ""
}

// ── Reboot ──

func handleReboot() (map[string]string, error) {
	out, err := runSu("reboot")
	if err != nil {
		// Try non-root reboot
		out, err = runShell("reboot")
		if err != nil {
			return nil, fmt.Errorf("reboot: %w (%s)", err, out)
		}
	}
	return map[string]string{"status": "rebooting"}, nil
}

// ── Run arbitrary command ──

func handleRunCmd(raw json.RawMessage) (map[string]string, error) {
	var p struct {
		Cmd    string `json:"cmd"`
		UseSu  bool   `json:"useSu"`
		TimeoutSec int `json:"timeoutSec"`
	}
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, fmt.Errorf("invalid params: %w", err)
	}
	if p.Cmd == "" {
		return nil, fmt.Errorf("cmd required")
	}

	var out string
	var err error
	if p.UseSu {
		out, err = runSu(p.Cmd)
	} else {
		out, err = runShell(p.Cmd)
	}
	if err != nil {
		return map[string]string{"output": out, "error": err.Error()}, nil
	}
	return map[string]string{"output": out}, nil
}
