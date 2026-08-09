// spoof.go — Persistent spoof profile management
// Profile saved to /data/local/tmp/zmmo/spoof.json on device
// Loaded at startup, auto-applied on boot
// Supports: build props, settings, MAC WiFi, GSF ID

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"sync"
	"time"
)

// ── SpoofProfile — the persistent spoof configuration ──

type SpoofProfile struct {
	Name      string            `json:"name"`      // "Samsung S22 Ultra", "Xiaomi 13 Pro", etc.
	Device    string            `json:"device"`    // model name for display
	Props     map[string]string `json:"props"`     // build.prop overrides (ro.product.*, ro.build.*)
	Settings  map[string]string `json:"settings"`  // settings put overrides (android_id, sim_operator, etc.)
	MacWifi   string            `json:"mac_wifi"`  // MAC address for wlan0
	GSFID     string            `json:"gsf_id"`    // Google Services Framework ID
	IMEI      string            `json:"imei"`      // IMEI override
	SIMSerial string            `json:"sim_serial"` // SIM serial
	AppliedAt string            `json:"applied_at"` // last apply timestamp
}

const spoofConfigPath = "/data/local/tmp/zmmo/spoof.json"

var (
	currentSpoof  *SpoofProfile
	spoofMu       sync.RWMutex
)

// ── Profile I/O ──

// loadSpoofProfile reads the saved profile from device storage.
func loadSpoofProfile() (*SpoofProfile, error) {
	data, err := os.ReadFile(spoofConfigPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil // no profile yet — not an error
		}
		return nil, fmt.Errorf("read spoof.json: %w", err)
	}

	var sp SpoofProfile
	if err := json.Unmarshal(data, &sp); err != nil {
		return nil, fmt.Errorf("parse spoof.json: %w", err)
	}

	spoofMu.Lock()
	currentSpoof = &sp
	spoofMu.Unlock()

	log.Printf("[spoof] loaded profile %q from %s", sp.Name, spoofConfigPath)
	return &sp, nil
}

// saveSpoofProfile writes the profile to device storage.
func saveSpoofProfile(sp *SpoofProfile) error {
	sp.AppliedAt = time.Now().Format(time.RFC3339)

	// Ensure directory exists
	os.MkdirAll("/data/local/tmp/zmmo", 0755)

	data, err := json.MarshalIndent(sp, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal: %w", err)
	}

	if err := os.WriteFile(spoofConfigPath, data, 0644); err != nil {
		return fmt.Errorf("write %s: %w", spoofConfigPath, err)
	}

	spoofMu.Lock()
	currentSpoof = sp
	spoofMu.Unlock()

	log.Printf("[spoof] saved profile %q (%d props, %d settings)", sp.Name, len(sp.Props), len(sp.Settings))
	return nil
}

// getCurrentSpoof returns the in-memory profile (or nil).
func getCurrentSpoof() *SpoofProfile {
	spoofMu.RLock()
	defer spoofMu.RUnlock()
	return currentSpoof
}

// ── Apply spoof ──

// applySpoofProfile applies all spoof values to the device.
// Returns a result map of what was applied.
func applySpoofProfile(sp *SpoofProfile) (map[string]string, error) {
	if sp == nil {
		return nil, fmt.Errorf("no spoof profile to apply")
	}

	results := make(map[string]string)
	applied := 0

	// 1. Build props via resetprop
	for key, value := range sp.Props {
		if value == "" {
			continue
		}
		if err := applyResetprop(key, value); err != nil {
			results[key] = fmt.Sprintf("error: %v", err)
		} else {
			results[key] = "ok"
			applied++
		}
	}

	// 2. Settings via settings put
	for key, value := range sp.Settings {
		if value == "" {
			continue
		}
		if err := applySettings(key, value); err != nil {
			results["settings:"+key] = fmt.Sprintf("error: %v", err)
		} else {
			results["settings:"+key] = "ok"
			applied++
		}
	}

	// 3. MAC WiFi
	if sp.MacWifi != "" {
		if err := applyMacWifi(sp.MacWifi); err != nil {
			results["mac_wifi"] = fmt.Sprintf("error: %v", err)
		} else {
			results["mac_wifi"] = "ok"
			applied++
		}
	}

	// 4. GSF ID (same as android_id on Android 12+)
	if sp.GSFID != "" {
		if err := applySettings("android_id", sp.GSFID); err != nil {
			results["gsf_id"] = fmt.Sprintf("error: %v", err)
		} else {
			results["gsf_id"] = "ok"
			applied++
		}
	}

	// 5. IMEI
	if sp.IMEI != "" {
		cmd := fmt.Sprintf("resetprop persist.radio.imei %s", sp.IMEI)
		if _, err := runSu(cmd); err != nil {
			results["imei"] = fmt.Sprintf("error: %v", err)
		} else {
			results["imei"] = "ok"
			applied++
		}
	}

	// Kill apps that cache identity props
	runSu("am force-stop com.google.android.gms 2>/dev/null")
	runSu("am force-stop com.android.vending 2>/dev/null")

	results["applied"] = fmt.Sprintf("%d/%d", applied, len(sp.Props)+len(sp.Settings)+extraSpoofCount(sp))
	log.Printf("[spoof] applied profile %q: %d changes", sp.Name, applied)
	return results, nil
}

func extraSpoofCount(sp *SpoofProfile) int {
	n := 0
	if sp.MacWifi != "" { n++ }
	if sp.GSFID != "" { n++ }
	if sp.IMEI != "" { n++ }
	if sp.SIMSerial != "" { n++ }
	return n
}

// applyMacWifi changes the wlan0 MAC address.
func applyMacWifi(mac string) error {
	script := fmt.Sprintf(
		"ip link set wlan0 down && ip link set wlan0 address %s && ip link set wlan0 up",
		mac,
	)
	out, err := runSu(script)
	if err != nil {
		return fmt.Errorf("mac change: %w (%s)", err, out)
	}
	log.Printf("[spoof] MAC wifi → %s", mac)
	return nil
}

// ── WS Handlers ──

// handleLoadSpoof reads the current profile from disk and returns it.
func handleLoadSpoof() (interface{}, error) {
	sp, err := loadSpoofProfile()
	if err != nil {
		return nil, err
	}
	if sp == nil {
		return map[string]interface{}{
			"loaded": false,
			"message": "No spoof profile found on device",
		}, nil
	}
	return map[string]interface{}{
		"loaded":  true,
		"profile": sp,
		"path":    spoofConfigPath,
	}, nil
}

// handleSaveSpoof saves a new spoof profile from the manager.
func handleSaveSpoof(raw json.RawMessage) (interface{}, error) {
	var sp SpoofProfile
	if err := json.Unmarshal(raw, &sp); err != nil {
		return nil, fmt.Errorf("invalid spoof profile: %w", err)
	}

	if err := saveSpoofProfile(&sp); err != nil {
		return nil, err
	}

	return map[string]interface{}{
		"saved": true,
		"path":  spoofConfigPath,
		"name":  sp.Name,
	}, nil
}

// handleApplySpoof applies the currently saved profile.
func handleApplySpoof() (interface{}, error) {
	sp, err := loadSpoofProfile()
	if err != nil {
		return nil, fmt.Errorf("load: %w", err)
	}
	if sp == nil {
		return nil, fmt.Errorf("no spoof profile saved — save one first")
	}

	results, err := applySpoofProfile(sp)
	if err != nil {
		return nil, err
	}

	// Update applied_at timestamp
	saveSpoofProfile(sp)

	return map[string]interface{}{
		"applied": true,
		"results": results,
	}, nil
}

// handleDeleteSpoof removes the spoof profile.
func handleDeleteSpoof() (interface{}, error) {
	spoofMu.Lock()
	currentSpoof = nil
	spoofMu.Unlock()

	if err := os.Remove(spoofConfigPath); err != nil && !os.IsNotExist(err) {
		return nil, fmt.Errorf("remove: %w", err)
	}

	return map[string]interface{}{
		"deleted": true,
	}, nil
}

// ── Auto-apply on startup ──

// autoApplySpoofOnBoot checks for a saved profile and applies it.
// Called during agent init.
func autoApplySpoofOnBoot() {
	sp, err := loadSpoofProfile()
	if err != nil {
		log.Printf("[spoof] boot: failed to load profile: %v", err)
		return
	}
	if sp == nil {
		log.Printf("[spoof] boot: no profile found, skipping")
		return
	}

	log.Printf("[spoof] boot: auto-applying profile %q...", sp.Name)
	results, err := applySpoofProfile(sp)
	if err != nil {
		log.Printf("[spoof] boot: apply failed: %v", err)
		return
	}
	log.Printf("[spoof] boot: applied successfully — %v", results["applied"])
}
