package main

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

// ── Types ──

type PropValue struct {
	Value   string `json:"value"`
	Enabled bool   `json:"enabled"`
}

type DeviceProps struct {
	IMEISlot1       PropValue `json:"imei_slot1"`
	IMEISlot2       PropValue `json:"imei_slot2"`
	MEID            PropValue `json:"meid"`
	IMSISlot1       PropValue `json:"imsi_slot1"`
	IMSISlot2       PropValue `json:"imsi_slot2"`
	ICCIDSlot1      PropValue `json:"iccid_slot1"`
	ICCIDSlot2      PropValue `json:"iccid_slot2"`
	PhoneNumber     PropValue `json:"phone_number"`
	SIMOperator     PropValue `json:"sim_operator"`
	SIMOperatorName PropValue `json:"sim_operator_name"`
	SIMCountryISO   PropValue `json:"sim_country_iso"`
	Brand           PropValue `json:"brand"`
	Model           PropValue `json:"model"`
	Manufacturer    PropValue `json:"manufacturer"`
	DeviceName      PropValue `json:"device_name"`
	Hardware        PropValue `json:"hardware"`
	Fingerprint     PropValue `json:"fingerprint"`
	SerialNumber    PropValue `json:"serial_number"`
	AndroidID       PropValue `json:"android_id"`
	OSVersion       PropValue `json:"os_version"`
	SDKVersion      PropValue `json:"sdk_version"`
	BuildID         PropValue `json:"build_id"`
	Bootloader      PropValue `json:"bootloader"`
	RadioVersion    PropValue `json:"radio_version"`
	MACWiFi         PropValue `json:"mac_wifi"`
	MACBluetooth    PropValue `json:"mac_bluetooth"`
	WiFiSSID        PropValue `json:"wifi_ssid"`
	WiFiBSSID       PropValue `json:"wifi_bssid"`
	Latitude        PropValue `json:"latitude"`
	Longitude       PropValue `json:"longitude"`
	Altitude        PropValue `json:"altitude"`
	GSFID           PropValue `json:"gsf_id"`
	AdvertisingID   PropValue `json:"advertising_id"`
}

type DeviceInfo struct {
	ID             string       `json:"id"`
	Serial         string       `json:"serial"`
	Model          string       `json:"model"`
	Brand          string       `json:"brand"`
	AndroidVersion string       `json:"androidVersion"`
	SDKVersion     int          `json:"sdkVersion"`
	Status         string       `json:"status"`
	IP             string       `json:"ip,omitempty"`
	ADBPort        int          `json:"adbPort,omitempty"`
	LastSeen       string       `json:"lastSeen"`
	Props          *DeviceProps `json:"props,omitempty"`
}

type LicenseInfo struct {
	Valid      bool     `json:"valid"`
	ExpiresAt  string   `json:"expiresAt"`
	MaxDevices int      `json:"maxDevices"`
	Features   []string `json:"features"`
}

type AgentStatus struct {
	Version     string      `json:"version"`
	Uptime      int64       `json:"uptime"`
	Port        int         `json:"port"`
	DeviceCount int         `json:"deviceCount"`
	Devices     []string    `json:"devices"`
	License     LicenseInfo `json:"license"`
}

type Task struct {
	ID        string            `json:"id"`
	Type      string            `json:"type"`
	DeviceID  string            `json:"deviceId,omitempty"`
	Params    map[string]string `json:"params"`
	Status    string            `json:"status"`
	Output    string            `json:"output"`
	Error     string            `json:"error,omitempty"`
	CreatedAt string            `json:"createdAt"`
	UpdatedAt string            `json:"updatedAt"`
}

type BackupInfo struct {
	ID        string      `json:"id"`
	DeviceID  string      `json:"deviceId"`
	DeviceSerial string   `json:"deviceSerial,omitempty"`
	Filename  string      `json:"filename"`
	Size      int64       `json:"size"`
	Packages  []string    `json:"packages,omitempty"`
	Props     DeviceProps `json:"props"`
	CreatedAt string      `json:"createdAt"`
	TargetDir string      `json:"targetDir,omitempty"`
}

// ── Global State ──

var (
	startTime  = time.Now()
	devices    = make(map[string]*DeviceInfo)
	deviceMu   sync.RWMutex
	tasks      = make(map[string]*Task)
	tasksMu    sync.RWMutex
	backups    = make(map[string]*BackupInfo)
	backupsMu  sync.RWMutex
	listenPort = 55555

	server       *http.Server
	serverMu     sync.Mutex
	serverCtx    context.Context
	serverCancel context.CancelFunc
	pollerStop   chan struct{}
)

const version = "1.2.0"

// ── ADB Helpers ──

func adbDevices() []string {
	out, err := cmdHide("adb", "devices").Output()
	if err != nil {
		return nil
	}
	lines := strings.Split(string(out), "\n")
	var serials []string
	for _, l := range lines[1:] {
		l = strings.TrimSpace(l)
		if l == "" || strings.HasPrefix(l, "*") {
			continue
		}
		if strings.Contains(l, "	device") {
			serials = append(serials, strings.Split(l, "	")[0])
		}
	}
	return serials
}

func adbShell(serial, cmd string) (string, error) {
	out, err := cmdHide("adb", "-s", serial, "shell", cmd).Output()
	return strings.TrimSpace(string(out)), err
}

func adbGetProp(serial, prop string) string {
	val, _ := adbShell(serial, "getprop "+prop)
	return val
}

func detectAndroidVersion(serial string) string {
	v := adbGetProp(serial, "ro.build.version.release")
	if v == "" {
		v = "unknown"
	}
	return v
}

func detectSDK(serial string) int {
	v := adbGetProp(serial, "ro.build.version.sdk")
	var sdk int
	fmt.Sscanf(v, "%d", &sdk)
	return sdk
}

func detectIP(serial string) string {
	out, _ := adbShell(serial, "ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1")
	if out != "" {
		return out
	}
	out, _ = adbShell(serial, "ip addr show | grep 'inet ' | grep -v 127.0.0.1 | head -1 | awk '{print $2}' | cut -d/ -f1")
	return out
}

// ── Device Refresh ──

func refreshDevices() {
	deviceMu.Lock()
	defer deviceMu.Unlock()
	seen := make(map[string]bool)
	for _, serial := range adbDevices() {
		seen[serial] = true
		if _, exists := devices[serial]; !exists {
			devices[serial] = &DeviceInfo{
				ID:             uuid.New().String(),
				Serial:         serial,
				Model:          adbGetProp(serial, "ro.product.model"),
				Brand:          adbGetProp(serial, "ro.product.brand"),
				AndroidVersion: detectAndroidVersion(serial),
				SDKVersion:     detectSDK(serial),
				Status:         "online",
				IP:             detectIP(serial),
				LastSeen:       time.Now().Format(time.RFC3339),
			}
		} else {
			d := devices[serial]
			d.Status = "online"
			d.IP = detectIP(serial)
			d.LastSeen = time.Now().Format(time.RFC3339)
		}
	}
	for _, d := range devices {
		if !seen[d.Serial] {
			d.Status = "offline"
		}
	}
}

func readDeviceProps(serial string) DeviceProps {
	return DeviceProps{
		Brand:        PropValue{Value: adbGetProp(serial, "ro.product.brand"), Enabled: false},
		Model:        PropValue{Value: adbGetProp(serial, "ro.product.model"), Enabled: false},
		Manufacturer: PropValue{Value: adbGetProp(serial, "ro.product.manufacturer"), Enabled: false},
		Fingerprint:  PropValue{Value: adbGetProp(serial, "ro.build.fingerprint"), Enabled: false},
		SerialNumber: PropValue{Value: adbGetProp(serial, "ro.serialno"), Enabled: false},
		OSVersion:    PropValue{Value: adbGetProp(serial, "ro.build.version.release"), Enabled: false},
		SDKVersion:   PropValue{Value: adbGetProp(serial, "ro.build.version.sdk"), Enabled: false},
		BuildID:      PropValue{Value: adbGetProp(serial, "ro.build.id"), Enabled: false},
		Bootloader:   PropValue{Value: adbGetProp(serial, "ro.bootloader"), Enabled: false},
		Hardware:     PropValue{Value: adbGetProp(serial, "ro.hardware"), Enabled: false},
	}
}

// ── Device Meta (full ADB snapshot → ~/.zmmo/devices/<serial>/meta.json) ──

// DeviceMeta holds a complete snapshot of every changeable property on the device.
type DeviceMeta struct {
	Serial     string `json:"serial"`     // ADB serial (transport id)
	RealSerial string `json:"realSerial"` // ro.serialno or bootloader serial

	// ── SIM / Telephony ──
	IMEI1        string `json:"imei1"`
	IMEI2        string `json:"imei2"`
	MEID         string `json:"meid"`
	IMSI1        string `json:"imsi1"`
	IMSI2        string `json:"imsi2"`
	ICCID1       string `json:"iccid1"`
	ICCID2       string `json:"iccid2"`
	PhoneNumber  string `json:"phoneNumber"`
	SIMOperator  string `json:"simOperator"`  // MCC+MNC
	SIMCarrier   string `json:"simCarrier"`   // friendly name
	SIMCountry   string `json:"simCountry"`   // ISO

	// ── Device Identity ──
	Brand        string `json:"brand"`
	Model        string `json:"model"`
	Manufacturer string `json:"manufacturer"`
	DeviceName   string `json:"deviceName"`
	ProductName  string `json:"productName"`  // ro.product.name
	Device       string `json:"device"`       // ro.product.device (codename)
	Board        string `json:"board"`        // ro.product.board
	Hardware     string `json:"hardware"`
	Platform     string `json:"platform"`     // ro.board.platform

	// ── Build Info ──
	Fingerprint     string `json:"fingerprint"`
	BuildID         string `json:"buildId"`
	BuildType       string `json:"buildType"`       // user/userdebug/eng
	BuildTags       string `json:"buildTags"`
	OSVersion       string `json:"osVersion"`
	SDKVersion      string `json:"sdkVersion"`
	Incremental     string `json:"incremental"`     // ro.build.version.incremental
	SecurityPatch   string `json:"securityPatch"`   // ro.build.version.security_patch
	Bootloader      string `json:"bootloader"`
	RadioBaseband   string `json:"radioBaseband"`   // gsm.version.baseband

	// ── Display ──
	DisplayDensity string `json:"displayDensity"` // ro.sf.lcd_density
	DisplayWidth   string `json:"displayWidth"`
	DisplayHeight  string `json:"displayHeight"`

	// ── Network IDs ──
	MACWiFi      string `json:"macWifi"`
	MACBluetooth string `json:"macBluetooth"`
	WiFiSSID     string `json:"wifiSsid"`
	WiFiBSSID    string `json:"wifiBssid"`
	IPAddress    string `json:"ipAddress"`

	// ── Persistent IDs (survive factory reset on some devices) ──
	AndroidID     string `json:"androidId"`
	GSFID         string `json:"gsfId"`
	AdvertisingID string `json:"advertisingId"`

	// ── Misc ──
	Timezone     string `json:"timezone"`
	Language     string `json:"language"`
	CPUABI       string `json:"cpuAbi"`
	TotalRAM     string `json:"totalRam"`
	InternalSize string `json:"internalSize"`

	// ── Raw props dump (for panel to parse) ──
	RawProps map[string]string `json:"rawProps"`

	CollectedAt string `json:"collectedAt"`
	AgentVer    string `json:"agentVer"`
}

// metaDir returns ~/.zmmo/devices/<realSerial>/
func metaDir(realSerial string) string {
	home, _ := os.UserHomeDir()
	if home == "" {
		home = "."
	}
	return filepath.Join(home, ".zmmo", "devices", realSerial)
}

// metaExists checks if meta.json already exists for the given real serial.
func metaExists(realSerial string) bool {
	_, err := os.Stat(filepath.Join(metaDir(realSerial), "meta.json"))
	return err == nil
}

// collectDeviceMeta gathers all changeable device properties via ADB.
// Returns the populated DeviceMeta and saves to ~/.zmmo/devices/<realSerial>/meta.json.
func collectDeviceMeta(serial string) (*DeviceMeta, error) {
	m := &DeviceMeta{
		Serial:      serial,
		AgentVer:    version,
		CollectedAt: time.Now().Format(time.RFC3339),
		RawProps:    make(map[string]string),
	}

	// ── Dump ALL build props in one call ──
	// getprop returns all properties; we parse just the ones we care about.
	allProps, _ := adbShell(serial, "getprop")
	for _, line := range strings.Split(allProps, "\n") {
		line = strings.TrimSpace(line)
		// Format: [key]: [value]
		if idx := strings.Index(line, "]:"); idx > 0 && strings.HasPrefix(line, "[") {
			key := strings.TrimSpace(line[1:idx])
			val := strings.TrimSpace(line[idx+2:])
			if len(val) > 2 && val[0] == '[' && val[len(val)-1] == ']' {
				val = val[1 : len(val)-1]
			}
			m.RawProps[key] = val
		}
	}

	// ── Helper: get raw prop from map, otherwise fall back to adb getprop ──
	getp := func(prop string) string {
		if v, ok := m.RawProps[prop]; ok && v != "" {
			return v
		}
		return adbGetProp(serial, prop)
	}

	// ── Device Identity ──
	m.Brand = getp("ro.product.brand")
	m.Model = getp("ro.product.model")
	m.Manufacturer = getp("ro.product.manufacturer")
	m.ProductName = getp("ro.product.name")
	m.Device = getp("ro.product.device")
	m.Board = getp("ro.product.board")
	m.Hardware = getp("ro.hardware")
	m.Platform = getp("ro.board.platform")
	m.DeviceName = getp("ro.product.model") // fallback
	if dn := getp("bluetooth.device_name"); dn != "" {
		m.DeviceName = dn
	}

	// ── Real serial (ro.serialno or bootloader serial) ──
	m.RealSerial = getp("ro.serialno")
	if m.RealSerial == "" {
		m.RealSerial = getp("ro.boot.serialno")
	}
	if m.RealSerial == "" {
		m.RealSerial = serial // fallback to ADB transport id
	}
	m.Bootloader = getp("ro.bootloader")

	// ── Build Info ──
	m.Fingerprint = getp("ro.build.fingerprint")
	m.BuildID = getp("ro.build.id")
	m.BuildType = getp("ro.build.type")
	m.BuildTags = getp("ro.build.tags")
	m.OSVersion = getp("ro.build.version.release")
	m.SDKVersion = getp("ro.build.version.sdk")
	m.Incremental = getp("ro.build.version.incremental")
	m.SecurityPatch = getp("ro.build.version.security_patch")
	m.RadioBaseband = getp("gsm.version.baseband")
	if m.RadioBaseband == "" {
		m.RadioBaseband = getp("ro.boot.baseband")
	}

	// ── Display ──
	m.DisplayDensity = getp("ro.sf.lcd_density")
	w, _ := adbShell(serial, "wm size 2>/dev/null")
	if w != "" {
		w = strings.TrimPrefix(strings.TrimSpace(w), "Physical size: ")
		w = strings.TrimPrefix(w, "Override size: ")
		if parts := strings.Split(w, "x"); len(parts) == 2 {
			m.DisplayWidth, m.DisplayHeight = parts[0], parts[1]
		}
	}

	// ── CPU / Memory ──
	m.CPUABI = getp("ro.product.cpu.abi")
	if m.CPUABI == "" {
		m.CPUABI = getp("ro.product.cpu.abilist")
	}
	ram, _ := adbShell(serial, "cat /proc/meminfo 2>/dev/null | grep MemTotal | awk '{print $2}'")
	if ram != "" {
		k, _ := strconv.Atoi(ram)
		if k > 0 {
			m.TotalRAM = fmt.Sprintf("%d MB", k/1024)
		}
	}
	disk, _ := adbShell(serial, "df /data 2>/dev/null | tail -1 | awk '{print $2}'")
	if disk != "" {
		sz, _ := strconv.Atoi(disk)
		if sz > 0 {
			m.InternalSize = fmt.Sprintf("%d GB", sz/(1024*1024))
		}
	}

	// ── Timezone / Language ──
	m.Timezone, _ = adbShell(serial, "settings get global time_zone 2>/dev/null")
	m.Language, _ = adbShell(serial, "settings get system system_locales 2>/dev/null")
	if m.Language == "" {
		m.Language = getp("persist.sys.locale")
	}

	// ── IP ──
	m.IPAddress = detectIP(serial)

	// ── MAC addresses ──
	wifiMAC, _ := adbShell(serial, "cat /sys/class/net/wlan0/address 2>/dev/null")
	if wifiMAC == "" {
		wifiMAC, _ = adbShell(serial, "ip link show wlan0 2>/dev/null | grep ether | awk '{print $2}'")
	}
	m.MACWiFi = strings.TrimSpace(wifiMAC)

	btMAC, _ := adbShell(serial, "settings get secure bluetooth_address 2>/dev/null")
	if btMAC == "" {
		btMAC, _ = adbShell(serial, "cat /data/misc/bluedroid/bt_config.conf 2>/dev/null | grep -i 'bdAddress' | head -1 | awk '{print $2}'")
	}
	if btMAC == "" {
		btMAC, _ = adbShell(serial, "cat /data/misc/bluetooth/bt_config.conf 2>/dev/null | grep -i 'bdAddress' | head -1 | awk '{print $2}'")
	}
	m.MACBluetooth = strings.TrimSpace(btMAC)

	// ── WiFi connection ──
	m.WiFiSSID, _ = adbShell(serial, "dumpsys wifi 2>/dev/null | grep -m1 'mWifiInfo' | sed 's/.*SSID: //' | sed 's/,.*//'")
	if m.WiFiSSID != "" && m.WiFiSSID[0] == '"' {
		m.WiFiSSID = m.WiFiSSID[1 : len(m.WiFiSSID)-1]
	}
	if m.WiFiSSID == "" {
		m.WiFiSSID, _ = adbShell(serial, "dumpsys connectivity 2>/dev/null | grep 'Wi-Fi network' | head -1 | awk '{print $NF}'")
	}
	m.WiFiBSSID, _ = adbShell(serial, "dumpsys wifi 2>/dev/null | grep -m1 'mWifiInfo' | sed 's/.*BSSID: //' | sed 's/,.*//'")

	// ── SIM / Telephony (may fail on WiFi-only tablets) ──

	// IMEI 1 & 2 (works on most devices)
	imei1, _ := adbShell(serial, "service call iphonesubinfo 1 2>/dev/null | awk '{print $NF}' | sed 's/\\r//g' | sed \"s/'//g\"")
	m.IMEI1 = parsePhoneServiceOutput(imei1)
	if m.IMEI1 == "" {
		m.IMEI1 = getp("gsm.imei")
	}
	if m.IMEI1 == "" {
		m.IMEI1 = getp("persist.radio.imei")
	}

	imei2, _ := adbShell(serial, "service call iphonesubinfo 3 2>/dev/null | awk '{print $NF}' | sed 's/\\r//g' | sed \"s/'//g\"")
	m.IMEI2 = parsePhoneServiceOutput(imei2)
	if m.IMEI2 == "" {
		m.IMEI2 = getp("gsm.imei2")
	}
	if m.IMEI2 == "" {
		m.IMEI2 = getp("persist.radio.imei2")
	}

	// MEID
	meid, _ := adbShell(serial, "service call iphonesubinfo 9 2>/dev/null | awk '{print $NF}' | sed 's/\\r//g' | sed \"s/'//g\"")
	m.MEID = parsePhoneServiceOutput(meid)

	// IMSI 1 & 2
	m.IMSI1, _ = adbShell(serial, "dumpsys telephony.registry 2>/dev/null | grep -m1 'mSubId=0' -A2 | grep mImsi | awk -F= '{print $NF}'")
	if m.IMSI1 == "" {
		m.IMSI1 = getp("gsm.sim.operator.numeric")
		// Append wildcard IMSI suffix — only operator part is available from getprop
	}
	imsi2, _ := adbShell(serial, "dumpsys telephony.registry 2>/dev/null | grep -m1 'mSubId=1' -A2 | grep mImsi | awk -F= '{print $NF}'")
	m.IMSI2 = strings.TrimSpace(imsi2)
	if m.IMSI2 == "" {
		m.IMSI2 = getp("gsm.sim.operator.numeric.2")
	}

	// ICCID
	m.ICCID1, _ = adbShell(serial, "dumpsys telephony.registry 2>/dev/null | grep -m1 'mSubId=0' -A15 | grep mIccId | awk -F= '{print $NF}'")
	if m.ICCID1 == "" {
		m.ICCID1 = getp("persist.radio.iccid")
	}
	iccid2, _ := adbShell(serial, "dumpsys telephony.registry 2>/dev/null | grep -m1 'mSubId=1' -A15 | grep mIccId | awk -F= '{print $NF}'")
	m.ICCID2 = strings.TrimSpace(iccid2)

	// Phone number
	m.PhoneNumber, _ = adbShell(serial, "dumpsys telephony.registry 2>/dev/null | grep -m1 'mSubId=0' -A30 | grep mMsisdn | awk -F= '{print $NF}'")
	if m.PhoneNumber == "" {
		m.PhoneNumber = getp("gsm.sim.phoneNumber")
	}

	// SIM Operator
	m.SIMOperator = getp("gsm.sim.operator.numeric")
	m.SIMCarrier = getp("gsm.sim.operator.alpha")
	m.SIMCountry = getp("gsm.sim.operator.iso-country")

	// ── Persistent IDs ──
	m.AndroidID, _ = adbShell(serial, "settings get secure android_id 2>/dev/null")

	// GSF ID
	gsf, _ := adbShell(serial, "sqlite3 /data/data/com.google.android.gsf/databases/gservices.db \"select value from main where name='android_id';\" 2>/dev/null")
	if gsf == "" {
		gsf, _ = adbShell(serial, "content query --uri content://com.google.android.gsf.gservices/prefix --projection value --where \"name='android_id'\" 2>/dev/null | sed 's/.*value=//' | sed 's/,.*//'")
	}
	m.GSFID = strings.TrimSpace(gsf)

	// Advertising ID
	adID, _ := adbShell(serial, "cat /data/data/com.google.android.gms/shared_prefs/adid_settings.xml 2>/dev/null | grep adid_key | sed 's/.*<string name=\"adid_key\">//' | sed 's/<.*//'")
	if adID == "" {
		adID, _ = adbShell(serial, "cat /data/data/com.google.android.gms/shared_prefs/AdvertisingId.xml 2>/dev/null | grep string | sed 's/.*>//' | sed 's/<.*//'")
	}
	m.AdvertisingID = strings.TrimSpace(adID)

	// ── Save to ~/.zmmo/devices/<realSerial>/meta.json ──
	dir := metaDir(m.RealSerial)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return m, fmt.Errorf("mkdir %s: %w", dir, err)
	}
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return m, fmt.Errorf("marshal: %w", err)
	}
	metaPath := filepath.Join(dir, "meta.json")
	if err := os.WriteFile(metaPath, data, 0644); err != nil {
		return m, fmt.Errorf("write meta.json: %w", err)
	}
	log.Printf("[meta] Saved %s (%d bytes)", metaPath, len(data))
	return m, nil
}

// parsePhoneServiceOutput converts hex-string service call output to human-readable ASCII.
// E.g. "303335393430343038303630383439" → "035940408060849"
func parsePhoneServiceOutput(raw string) string {
	// Strip newlines and spaces
	s := strings.ReplaceAll(raw, "\n", "")
	s = strings.ReplaceAll(s, " ", "")
	s = strings.Trim(s, ".")

	// Try hex decode (service call returns hex pairs that spell ASCII in decimal)
	if re := regexp.MustCompile(`^[0-9]{15,}$`); re.MatchString(s) {
		// This could be a raw numeric IMEI already
		return s
	}

	// Try dot-separated hex (e.g. "30 33 35 39 34 30 34 30 ...")
	parts := strings.Split(raw, ".")
	if len(parts) > 3 {
		var asciiStr strings.Builder
		for _, p := range parts {
			p = strings.TrimSpace(p)
			n, err := strconv.ParseInt(p, 16, 32)
			if err == nil && n >= 0x20 && n <= 0x7E {
				asciiStr.WriteByte(byte(n))
			}
		}
		if asciiStr.Len() > 0 {
			return asciiStr.String()
		}
	}

	// Try comma-separated format
	if len(parts) <= 3 && strings.Contains(raw, ",") {
		var asciiStr strings.Builder
		for _, p := range strings.Split(raw, ",") {
			p = strings.TrimSpace(p)
			n, err := strconv.ParseInt(p, 10, 32)
			if err == nil && n >= 0x20 && n <= 0x7E {
				asciiStr.WriteByte(byte(n))
			}
		}
		if asciiStr.Len() > 0 {
			return asciiStr.String()
		}
	}

	return strings.TrimSpace(raw)
}

// zmmoHome returns cross-platform path to ~/.zmmo
func zmmoHome() string {
	home, _ := os.UserHomeDir()
	if home == "" {
		home = "."
	}
	return filepath.Join(home, ".zmmo")
}

// ── CORS & JSON ──

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(data)
}

func writeError(w http.ResponseWriter, code int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"error": msg})
}

// ── Handlers ──

func handleStatus(w http.ResponseWriter, r *http.Request) {
	deviceMu.RLock()
	devicesList := make([]string, 0, len(devices))
	for _, d := range devices {
		devicesList = append(devicesList, d.Serial)
	}
	deviceMu.RUnlock()
	writeJSON(w, AgentStatus{
		Version:     version,
		Uptime:      int64(time.Since(startTime).Seconds()),
		Port:        listenPort,
		DeviceCount: len(devicesList),
		Devices:     devicesList,
		License: LicenseInfo{
			Valid:      true,
			ExpiresAt:  time.Now().AddDate(1, 0, 0).Format(time.RFC3339),
			MaxDevices: 100,
			Features:   []string{"adb", "backup", "restore", "props", "meta"},
		},
	})
}

func handleDevices(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		writeError(w, 405, "method not allowed")
		return
	}
	refreshDevices()
	deviceMu.RLock()
	list := make([]DeviceInfo, 0, len(devices))
	for _, d := range devices {
		list = append(list, *d)
	}
	deviceMu.RUnlock()
	writeJSON(w, list)
}

func handleDevice(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/devices/"), "/")
	if len(parts) < 1 {
		writeError(w, 400, "missing device id")
		return
	}
	deviceMu.RLock()
	var found *DeviceInfo
	for _, d := range devices {
		if d.ID == parts[0] {
			found = d
			break
		}
	}
	deviceMu.RUnlock()
	if found == nil {
		writeError(w, 404, "device not found")
		return
	}
	subPath := ""
	if len(parts) > 1 {
		subPath = parts[1]
	}
	switch {
	case r.Method == "GET" && subPath == "":
		if found.Props == nil {
			props := readDeviceProps(found.Serial)
			found.Props = &props
		}
		// Auto-collect meta if not already saved
		realSerial := found.Serial
		if sn := adbGetProp(found.Serial, "ro.serialno"); sn != "" {
			realSerial = sn
		}
		if !metaExists(realSerial) {
			go func(ser, rs string) {
				if meta, err := collectDeviceMeta(ser); err != nil {
					log.Printf("[meta] auto-collect %s: %v", ser, err)
				} else {
					log.Printf("[meta] auto-collected for %s → %s", ser, meta.RealSerial)
				}
			}(found.Serial, realSerial)
		}
		writeJSON(w, found)
	case r.Method == "GET" && subPath == "meta":
		// Read existing meta.json without re-collecting
		realSerial := found.Serial
		if sn := adbGetProp(found.Serial, "ro.serialno"); sn != "" {
			realSerial = sn
		}
		metaPath := filepath.Join(metaDir(realSerial), "meta.json")
		data, err := os.ReadFile(metaPath)
		if err != nil {
			writeJSON(w, map[string]interface{}{
				"ok":      false,
				"found":   false,
				"path":    metaPath,
				"message": "No meta.json yet — use refresh-meta to collect",
			})
			return
		}
		var meta DeviceMeta
		if err := json.Unmarshal(data, &meta); err != nil {
			writeError(w, 500, fmt.Sprintf("corrupt meta.json: %v", err))
			return
		}
		writeJSON(w, map[string]interface{}{
			"ok":    true,
			"found": true,
			"path":  metaPath,
			"meta":  meta,
		})
	case r.Method == "POST" && subPath == "refresh-meta":
		meta, err := collectDeviceMeta(found.Serial)
		if err != nil {
			writeError(w, 500, fmt.Sprintf("failed to collect meta: %v", err))
			return
		}
		writeJSON(w, map[string]interface{}{
			"ok":   true,
			"path": filepath.Join(metaDir(meta.RealSerial), "meta.json"),
			"meta": meta,
		})
	case r.Method == "PUT" && subPath == "props":
		var body struct {
			Props DeviceProps `json:"props"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeError(w, 400, "invalid JSON")
			return
		}
		found.Props = &body.Props
		writeJSON(w, map[string]bool{"ok": true})
	case r.Method == "POST" && subPath == "apply":
		if found.Props == nil {
			writeError(w, 400, "no props to apply")
			return
		}
		applyProps(found.Serial, found.Props)
		writeJSON(w, map[string]bool{"ok": true})
	default:
		writeError(w, 405, "method not allowed")
	}
}

func applyProps(serial string, props *DeviceProps) {
	for prop, pv := range map[string]PropValue{
		"ro.product.brand":        props.Brand,
		"ro.product.model":        props.Model,
		"ro.product.manufacturer": props.Manufacturer,
		"ro.build.fingerprint":    props.Fingerprint,
	} {
		if pv.Enabled && pv.Value != "" {
			cmdHide("adb", "-s", serial, "shell", "setprop "+prop+" "+pv.Value).Run()
		}
	}
}

func handleTasks(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case "GET":
		tasksMu.RLock()
		list := make([]Task, 0, len(tasks))
		for _, t := range tasks {
			list = append(list, *t)
		}
		tasksMu.RUnlock()
		writeJSON(w, list)
	case "POST":
		var body struct {
			Type     string            `json:"type"`
			DeviceID string            `json:"deviceId"`
			Params   map[string]string `json:"params"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeError(w, 400, "invalid JSON")
			return
		}
		task := &Task{
			ID:        uuid.New().String(),
			Type:      body.Type,
			DeviceID:  body.DeviceID,
			Params:    body.Params,
			Status:    "pending",
			CreatedAt: time.Now().Format(time.RFC3339),
			UpdatedAt: time.Now().Format(time.RFC3339),
		}
		go executeTask(task)
		tasksMu.Lock()
		tasks[task.ID] = task
		tasksMu.Unlock()
		writeJSON(w, task)
	default:
		writeError(w, 405, "method not allowed")
	}
}

func handleTask(w http.ResponseWriter, r *http.Request) {
	taskID := strings.TrimPrefix(r.URL.Path, "/tasks/")
	tasksMu.RLock()
	task, ok := tasks[taskID]
	tasksMu.RUnlock()
	if !ok {
		writeError(w, 404, "task not found")
		return
	}
	writeJSON(w, task)
}

func executeTask(task *Task) {
	task.Status = "running"
	task.UpdatedAt = time.Now().Format(time.RFC3339)
	serial := task.DeviceID
	if task.Params != nil {
		if s, ok := task.Params["deviceId"]; ok && s != "" {
			serial = s
		}
	}
	switch task.Type {
	case "adb", "shell":
		cmd := ""
		if task.Params != nil {
			cmd = task.Params["command"]
		}
		out, err := adbShell(serial, cmd)
		task.Output = out
		if err != nil {
			task.Status = "failed"
			task.Error = err.Error()
		} else {
			task.Status = "completed"
		}
	case "reboot":
		out, err := cmdHide("adb", "-s", serial, "reboot").CombinedOutput()
		task.Output = strings.TrimSpace(string(out))
		if err != nil {
			task.Status = "failed"
			task.Error = err.Error()
		} else {
			task.Status = "completed"
		}
	case "backup":
		props := readDeviceProps(serial)
		data, _ := json.MarshalIndent(props, "", "  ")
		filename := fmt.Sprintf("backup_%s_%s.json", serial, time.Now().Format("20060102_150405"))
		path := fmt.Sprintf("./backups/%s", filename)
		os.MkdirAll("./backups", 0755)
		if err := os.WriteFile(path, data, 0644); err != nil {
			task.Status = "failed"
			task.Error = err.Error()
		} else {
			info, _ := os.Stat(path)
			backupsMu.Lock()
			backups[task.ID] = &BackupInfo{
				ID: task.ID, DeviceID: serial, Filename: filename,
				Size: info.Size(), Props: props, CreatedAt: time.Now().Format(time.RFC3339),
			}
			backupsMu.Unlock()
			task.Output = fmt.Sprintf("Backup saved: %s (%d bytes)", filename, info.Size())
			task.Status = "completed"
		}
	case "restore":
		backupsMu.RLock()
		var latest *BackupInfo
		for _, b := range backups {
			if b.DeviceID == serial {
				latest = b
			}
		}
		backupsMu.RUnlock()
		if latest == nil {
			task.Status = "failed"
			task.Error = "no backup found"
		} else {
			applyProps(serial, &latest.Props)
			task.Output = fmt.Sprintf("Restored from %s", latest.Filename)
			task.Status = "completed"
		}
	default:
		task.Status = "failed"
		task.Error = fmt.Sprintf("unknown task: %s", task.Type)
	}
	task.UpdatedAt = time.Now().Format(time.RFC3339)
}

// ── Package Listing ──

func handlePackages(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/packages/"), "/")
	if len(parts) < 1 || parts[0] == "" {
		writeError(w, 400, "device id required: /packages/:deviceId")
		return
	}
	deviceID := parts[0]

	// Resolve UUID or serial → ADB serial
	deviceMu.RLock()
	serial := ""
	for _, dev := range devices {
		if dev.ID == deviceID || dev.Serial == deviceID {
			serial = dev.Serial
			break
		}
	}
	deviceMu.RUnlock()
	if serial == "" {
		writeError(w, 404, "device not found")
		return
	}

	out, err := adbShell(serial, "pm list packages -f")
	if err != nil {
		writeError(w, 500, "failed to list packages: "+err.Error())
		return
	}
	type PkgInfo struct {
		Package string `json:"package"`
		Name    string `json:"name"`
	}
	pkgs := make([]PkgInfo, 0)
	lines := strings.Split(strings.TrimSpace(out), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "package:") {
			continue
		}
		// "package:/data/app/com.example==/base.apk=com.example"
		line = strings.TrimPrefix(line, "package:")
		parts := strings.Split(line, "=")
		if len(parts) >= 1 {
			pkg := parts[len(parts)-1] // last segment is the package name
			if pkg != "" {
				pkgs = append(pkgs, PkgInfo{Package: pkg, Name: pkg})
			}
		}
	}
	writeJSON(w, pkgs)
}

// ── Backups (full userdata backup/restore) ──

func handleBackups(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case "GET":
		backupsMu.RLock()
		list := make([]BackupInfo, 0, len(backups))
		for _, b := range backups {
			list = append(list, *b)
		}
		backupsMu.RUnlock()
		writeJSON(w, list)

	case "POST":
		var body struct {
			DeviceID string   `json:"deviceId"`
			Packages []string `json:"packages,omitempty"`
			TargetDir string  `json:"targetDir,omitempty"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeError(w, 400, "invalid JSON")
			return
		}
		if body.DeviceID == "" {
			writeError(w, 400, "deviceId required")
			return
		}
		if len(body.Packages) == 0 {
			writeError(w, 400, "at least one package required")
			return
		}

		id := uuid.New().String()
		timestamp := time.Now().Format("20060102_150405")
		filename := fmt.Sprintf("zmmo-backup-%s.tar.gz", timestamp)
		
		targetDir := body.TargetDir
		if targetDir == "" {
			targetDir = "./backups"
		}
		os.MkdirAll(targetDir, 0755)
		localPath := filepath.Join(targetDir, filename)

		serial := getDeviceSerial(body.DeviceID)

		// Build tar command on device (toybox tar: no -z, gzip later)
		// Use /sdcard which always has write permission
		tarBase := fmt.Sprintf("zmmo-tar-%s", timestamp)
		deviceTar := "/sdcard/" + tarBase + ".tar"
		tarCmd := fmt.Sprintf("cd /data/data && tar cf %s %s 2>&1", deviceTar,
			strings.Join(body.Packages, " "))

		log.Printf("[backup:%s] creating tar on device %s: %s", id, serial, tarCmd)
		out, err := adbShell(body.DeviceID, tarCmd)
		if err != nil {
			log.Printf("[backup:%s] tar stderr: %s", id, out)
			adbShell(body.DeviceID, "rm -f "+deviceTar)
			writeError(w, 500, "tar on device failed: "+err.Error())
			return
		}

		// Pull tar from device
		tarLocal := filepath.Join(targetDir, tarBase+".tar")
		log.Printf("[backup:%s] pulling %s → %s", id, deviceTar, tarLocal)
		if err := adbPull(body.DeviceID, deviceTar, tarLocal); err != nil {
			adbShell(body.DeviceID, "rm -f "+deviceTar)
			writeError(w, 500, "pull failed: "+err.Error())
			return
		}
		adbShell(body.DeviceID, "rm -f "+deviceTar)

		// Gzip on server
		tarData, _ := os.ReadFile(tarLocal)
		var gzBuf bytes.Buffer
		gw := gzip.NewWriter(&gzBuf)
		gw.Write(tarData)
		gw.Close()
		os.Remove(tarLocal)
		os.WriteFile(localPath, gzBuf.Bytes(), 0644)

		// Get file size
		fi, err := os.Stat(localPath)
		size := int64(0)
		if err == nil {
			size = fi.Size()
		}

		backup := &BackupInfo{
			ID:           id,
			DeviceID:     body.DeviceID,
			DeviceSerial: serial,
			Filename:     filename,
			Size:         size,
			Packages:     body.Packages,
			Props:        DeviceProps{},
			CreatedAt:    time.Now().Format(time.RFC3339),
			TargetDir:    targetDir,
		}

		// Load current device props into backup
		deviceMu.RLock()
		if dev, ok := devices[body.DeviceID]; ok && dev.Props != nil {
			backup.Props = *dev.Props
		}
		deviceMu.RUnlock()

		backupsMu.Lock()
		backups[id] = backup
		backupsMu.Unlock()

		log.Printf("[backup:%s] done — %d bytes, %d packages", id, size, len(body.Packages))
		writeJSON(w, map[string]interface{}{"ok": true, "backup": backup})

	default:
		writeError(w, 405, "method not allowed")
	}
}

func handleBackupRestore(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		writeError(w, 405, "method not allowed")
		return
	}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/backups/"), "/")
	if len(parts) < 2 || parts[1] != "restore" {
		writeError(w, 404, "not found — use /backups/:id/restore")
		return
	}
	backupID := parts[0]

	var body struct {
		DeviceID string `json:"deviceId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, 400, "invalid JSON")
		return
	}
	if body.DeviceID == "" {
		writeError(w, 400, "deviceId required")
		return
	}

	backupsMu.RLock()
	backup, ok := backups[backupID]
	backupsMu.RUnlock()
	if !ok {
		writeError(w, 404, "backup not found")
		return
	}

	localPath := filepath.Join(backup.TargetDir, backup.Filename)
	if backup.TargetDir == "" {
		localPath = filepath.Join("./backups", backup.Filename)
	}

	// Check file exists
	if _, err := os.Stat(localPath); os.IsNotExist(err) {
		writeError(w, 404, "backup file not found on disk: "+localPath)
		return
	}

	// Stop apps before restore
	for _, pkg := range backup.Packages {
		adbShell(body.DeviceID, "am force-stop "+pkg)
	}

	// Push tar to device
	remotePath := "/data/local/tmp/" + backup.Filename
	log.Printf("[restore:%s] pushing %s → %s", backupID, localPath, remotePath)
	err := adbPush(body.DeviceID, localPath, remotePath)
	if err != nil {
		writeError(w, 500, "push failed: "+err.Error())
		return
	}

	// Extract on device
	extractCmd := fmt.Sprintf("tar xzf %s -C /data/data/ 2>/dev/null", remotePath)
	log.Printf("[restore:%s] extracting: %s", backupID, extractCmd)
	_, err = adbShell(body.DeviceID, extractCmd)
	if err != nil {
		writeError(w, 500, "extract failed: "+err.Error())
		adbShell(body.DeviceID, "rm -f "+remotePath)
		return
	}

	// Fix permissions (set owner back to each package's UID)
	for _, pkg := range backup.Packages {
		adbShell(body.DeviceID, fmt.Sprintf("chown -R $(stat -c %%u /data/data/%s 2>/dev/null || echo 1000):$(stat -c %%g /data/data/%s 2>/dev/null || echo 1000) /data/data/%s 2>/dev/null", pkg, pkg, pkg))
	}

	// Clean up
	adbShell(body.DeviceID, "rm -f "+remotePath)

	log.Printf("[restore:%s] done — %d packages restored to %s", backupID, len(backup.Packages), body.DeviceID)
	writeJSON(w, map[string]interface{}{"ok": true, "restored": len(backup.Packages)})
}

// ── ADB helpers for push/pull ──

func adbPull(deviceID, remotePath, localPath string) error {
	return cmdHide("adb", "-s", deviceID, "pull", remotePath, localPath).Run()
}

func adbPush(deviceID, localPath, remotePath string) error {
	return cmdHide("adb", "-s", deviceID, "push", localPath, remotePath).Run()
}

func getDeviceSerial(deviceID string) string {
	deviceMu.RLock()
	defer deviceMu.RUnlock()
	if dev, ok := devices[deviceID]; ok {
		return dev.Serial
	}
	return deviceID
}

func handleADB(w http.ResponseWriter, r *http.Request) {
	deviceID := strings.TrimPrefix(r.URL.Path, "/adb/")
	var body struct {
		Command string `json:"command"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, 400, "invalid JSON")
		return
	}
	out, err := adbShell(deviceID, body.Command)
	if err != nil {
		writeJSON(w, map[string]string{"output": out + "\nError: " + err.Error()})
		return
	}
	writeJSON(w, map[string]string{"output": out})
}

func handleLicenseActivate(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Key string `json:"key"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, 400, "invalid JSON")
		return
	}
	if len(body.Key) < 8 {
		writeJSON(w, map[string]interface{}{"ok": false, "message": "Invalid license key"})
		return
	}
	writeJSON(w, map[string]interface{}{"ok": true, "message": "License activated successfully"})
}

// ── Server Control ──

// ── Agent WebSocket Registry ──

type AgentConn struct {
	DeviceID string
	Conn     *websocket.Conn
	ConnectedAt time.Time
	LastSeen    time.Time
	Mu          sync.Mutex
}

var (
	agentConns   = make(map[string]*AgentConn)
	agentConnsMu sync.RWMutex
)

func handleAgentWS(w http.ResponseWriter, r *http.Request) {
	upgrader := websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool { return true },
	}
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[agent-ws] upgrade: %v", err)
		return
	}
	defer conn.Close()

	// Read registration message
	var regMsg struct {
		Type   string                 `json:"type"`
		Device map[string]interface{} `json:"device"`
	}
	if err := conn.ReadJSON(&regMsg); err != nil || regMsg.Type != "register" {
		log.Printf("[agent-ws] bad register: %v", err)
		return
	}

	deviceID := "unknown"
	if regMsg.Device != nil {
		if id, ok := regMsg.Device["serial"].(string); ok && id != "" {
			deviceID = id
		}
	}
	log.Printf("[agent-ws] agent %s connected", deviceID)

	ac := &AgentConn{
		DeviceID:    deviceID,
		Conn:        conn,
		ConnectedAt: time.Now(),
		LastSeen:    time.Now(),
	}
	agentConnsMu.Lock()
	agentConns[deviceID] = ac
	agentConnsMu.Unlock()

	defer func() {
		agentConnsMu.Lock()
		delete(agentConns, deviceID)
		agentConnsMu.Unlock()
		log.Printf("[agent-ws] agent %s disconnected", deviceID)
	}()

	// Read loop — handle messages from agent
	for {
		var msg struct {
			Type   string          `json:"type"`
			ID     string          `json:"id"`
			Data   json.RawMessage `json:"data"`
			Error  string          `json:"error"`
		}
		if err := conn.ReadJSON(&msg); err != nil {
			if !websocket.IsCloseError(err, websocket.CloseNormalClosure) {
				log.Printf("[agent-ws] %s read: %v", deviceID, err)
			}
			return
		}
		ac.LastSeen = time.Now()

		switch msg.Type {
		case "pong":
			// keepalive acknowledged
		case "getProps_result", "setProp_result", "resetProps_result",
			"screenshot_result", "tap_result", "swipe_result",
			"install_result", "uninstall_result", "runCmd_result", "reboot_result":
			// Forward to task completion handler (TODO)
			log.Printf("[agent-ws] %s: %s completed", deviceID, msg.Type)
		default:
			log.Printf("[agent-ws] %s: unknown msg type %s", deviceID, msg.Type)
		}
	}
}

// ── Server Control ──

func startServer() error {
	serverMu.Lock()
	defer serverMu.Unlock()
	if server != nil {
		return fmt.Errorf("already running")
	}
	os.MkdirAll("./backups", 0755)

	mux := http.NewServeMux()
	mux.HandleFunc("/status", handleStatus)
	mux.HandleFunc("/devices", handleDevices)
	mux.HandleFunc("/devices/", handleDevice)
	mux.HandleFunc("/tasks", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/tasks" {
			handleTasks(w, r)
		} else {
			handleTask(w, r)
		}
	})
	mux.HandleFunc("/backups", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/backups" {
			handleBackups(w, r)
		} else {
			handleBackupRestore(w, r)
		}
	})
	mux.HandleFunc("/packages/", handlePackages)
	mux.HandleFunc("/adb/", handleADB)
	mux.HandleFunc("/license/activate", handleLicenseActivate)
	mux.HandleFunc("/agent/ws", handleAgentWS)

	for _, port := range []int{55555, 55556} {
		addr := fmt.Sprintf(":%d", port)
		ln, err := net.Listen("tcp", addr)
		if err == nil {
			ln.Close()
			listenPort = port
			break
		}
	}

	serverCtx, serverCancel = context.WithCancel(context.Background())
	server = &http.Server{Addr: fmt.Sprintf(":%d", listenPort), Handler: corsMiddleware(mux)}

	pollerStop = make(chan struct{})
	refreshDevices()
	go func() {
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				refreshDevices()
			case <-pollerStop:
				return
			}
		}
	}()

	go func() {
		log.Printf("Manager-Agent v%s on port %d", version, listenPort)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("Server: %v", err)
		}
	}()
	return nil
}

func stopServer() error {
	serverMu.Lock()
	defer serverMu.Unlock()
	if server == nil {
		return nil
	}
	if pollerStop != nil {
		close(pollerStop)
		pollerStop = nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	server.Shutdown(ctx)
	server = nil
	if serverCancel != nil {
		serverCancel()
	}
	return nil
}

func restartServer() {
	stopServer()
	time.Sleep(1 * time.Second)
	if err := startServer(); err != nil {
		log.Printf("Restart failed: %v", err)
	}
}

func serverStatus() string {
	serverMu.Lock()
	defer serverMu.Unlock()
	if server != nil {
		deviceMu.RLock()
		count := len(devices)
		deviceMu.RUnlock()
		return fmt.Sprintf("Running — port %d, %d devices", listenPort, count)
	}
	return "Stopped"
}
