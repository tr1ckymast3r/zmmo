// changer.go — Property modification (setprop / settings / resetprop)
// Uses Magisk resetprop for read-only props, standard setprop for userdebug

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"
)

// PropChange describes a single property change
type PropChange struct {
	Key     string `json:"key"`
	Value   string `json:"value"`
	Enabled bool   `json:"enabled"`
}

// ChangeSet contains the full property override payload
type ChangeSet struct {
	Props []PropChange `json:"props"`
}

// ── Property modification ──

func applyPropChange(key, value string, enabled bool) error {
	if !enabled || value == "" {
		return nil
	}

	// Route based on key type
	switch {
	case isSettingsKey(key):
		// Use settings put <namespace> <key> <value>
		return applySettings(key, value)

	case isReadOnlyProp(key):
		// Use Magisk resetprop (needs root)
		return applyResetprop(key, value)

	default:
		// Standard setprop
		return applySetprop(key, value)
	}
}

func isSettingsKey(key string) bool {
	settingsKeys := []string{
		"sim_operator", "sim_operator_name", "sim_country_iso",
		"android_id", "wifi_ssid", "wifi_bssid",
		"phone_number", "bluetooth_address",
		"advertising_id", "gsf_id",
	}
	for _, sk := range settingsKeys {
		if key == sk || strings.HasSuffix(key, "."+sk) {
			return true
		}
	}
	return false
}

func isReadOnlyProp(key string) bool {
	roProps := []string{
		"ro.product.brand", "ro.product.model", "ro.product.manufacturer",
		"ro.product.name", "ro.product.device", "ro.product.board",
		"ro.hardware", "ro.board.platform",
		"ro.build.fingerprint", "ro.build.id", "ro.build.type",
		"ro.build.version.release", "ro.build.version.sdk",
		"ro.bootloader", "ro.serialno",
	}
	for _, rp := range roProps {
		if key == rp {
			return true
		}
	}
	return strings.HasPrefix(key, "ro.") || strings.HasPrefix(key, "gsm.")
}

func applySettings(key string, value string) error {
	var namespace string
	switch {
	case strings.Contains(key, "android_id"):
		namespace = "secure"
	case strings.Contains(key, "wifi"):
		namespace = "global"
	case strings.Contains(key, "advertising"):
		namespace = "google"
	default:
		namespace = "global"
	}

	// settings put <namespace> <key> <value>
	cmd := fmt.Sprintf("settings put %s %s %s", namespace, key, value)
	out, err := runShell(cmd)
	if err != nil {
		log.Printf("[changer] settings put %s/%s = %s: %v (%s)", namespace, key, value, err, out)
		return err
	}
	log.Printf("[changer] settings: %s/%s = %s", namespace, key, value)
	return nil
}

func applyResetprop(key string, value string) error {
	// Try Magisk resetprop first, fall back to setprop
	cmd := fmt.Sprintf("resetprop %s %s 2>/dev/null || setprop %s %s 2>/dev/null", key, value, key, value)
	out, err := runSu(cmd)
	if err != nil {
		log.Printf("[changer] resetprop %s = %s: %v (%s)", key, value, err, out)
		return err
	}
	log.Printf("[changer] resetprop: %s = %s", key, value)
	return nil
}

func applySetprop(key string, value string) error {
	cmd := fmt.Sprintf("setprop %s %s", key, value)
	out, err := runShell(cmd)
	if err != nil {
		log.Printf("[changer] setprop %s = %s: %v (%s)", key, value, err, out)
		return err
	}
	log.Printf("[changer] setprop: %s = %s", key, value)
	return nil
}

// ── Full change / reset ──

func applyChangeSet(raw json.RawMessage) (map[string]string, error) {
	var cs ChangeSet
	if err := json.Unmarshal(raw, &cs); err != nil {
		return nil, fmt.Errorf("invalid change set: %w", err)
	}

	results := make(map[string]string)
	for _, p := range cs.Props {
		if err := applyPropChange(p.Key, p.Value, p.Enabled); err != nil {
			results[p.Key] = fmt.Sprintf("error: %v", err)
		} else if p.Enabled {
			results[p.Key] = "changed"
		} else {
			results[p.Key] = "skipped (disabled)"
		}
	}
	return results, nil
}

func resetAllProps() (map[string]string, error) {
	results := make(map[string]string)

	// Reset all standard reset-able props
	resetCmds := []string{
		"settings delete global sim_operator",
		"settings delete global sim_operator_name",
		"settings delete global sim_country_iso",
		"settings delete global phone_number",
		"settings delete global wifi_ssid",
		"settings delete global wifi_bssid",
		"settings delete secure android_id",
		"settings delete google advertising_id",
	}

	for _, cmd := range resetCmds {
		out, err := runShell(cmd)
		if err != nil {
			results[cmd] = fmt.Sprintf("error: %v (%s)", err, out)
		} else {
			results[cmd] = "reset"
		}
	}

	// Kill apps that cache props
	runShell("am force-stop com.google.android.gms 2>/dev/null")
	runShell("am force-stop com.android.vending 2>/dev/null")

	return results, nil
}
