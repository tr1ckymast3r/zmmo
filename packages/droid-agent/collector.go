// collector.go — Device property collection (all changeable props)
// Reads via getprop + settings + service calls + direct file I/O

package main

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// DeviceMeta mirrors manager-agent's DeviceMeta struct
type DeviceMeta struct {
	Serial       string `json:"serial"`
	RealSerial   string `json:"realSerial"`
	AgentVer     string `json:"agentVer"`
	CollectedAt  string `json:"collectedAt"`

	// SIM / Telephony
	IMEI1        string `json:"imei1"`
	IMEI2        string `json:"imei2"`
	MEID         string `json:"meid"`
	IMSI1        string `json:"imsi1"`
	IMSI2        string `json:"imsi2"`
	ICCID1       string `json:"iccid1"`
	ICCID2       string `json:"iccid2"`
	PhoneNumber  string `json:"phoneNumber"`
	SIMOperator  string `json:"simOperator"`
	SIMCarrier   string `json:"simCarrier"`
	SIMCountry   string `json:"simCountry"`

	// Identity
	Brand        string `json:"brand"`
	Model        string `json:"model"`
	Manufacturer string `json:"manufacturer"`
	DeviceName   string `json:"deviceName"`
	ProductName  string `json:"productName"`
	Device       string `json:"device"`
	Board        string `json:"board"`
	Hardware     string `json:"hardware"`
	Platform     string `json:"platform"`

	// Build
	Fingerprint   string `json:"fingerprint"`
	BuildID       string `json:"buildId"`
	BuildType     string `json:"buildType"`
	BuildTags     string `json:"buildTags"`
	OSVersion     string `json:"osVersion"`
	SDKVersion    string `json:"sdkVersion"`
	Incremental   string `json:"incremental"`
	SecurityPatch string `json:"securityPatch"`
	Bootloader    string `json:"bootloader"`
	RadioBaseband string `json:"radioBaseband"`

	// Display
	DisplayDensity string `json:"displayDensity"`
	DisplayWidth   string `json:"displayWidth"`
	DisplayHeight  string `json:"displayHeight"`

	// Network IDs
	MACWiFi      string `json:"macWifi"`
	MACBluetooth string `json:"macBluetooth"`
	WiFiSSID     string `json:"wifiSsid"`
	WiFiBSSID    string `json:"wifiBssid"`
	IPAddress    string `json:"ipAddress"`

	// Persistent IDs
	AndroidID     string `json:"androidId"`
	GSFID         string `json:"gsfId"`
	AdvertisingID string `json:"advertisingId"`

	// Misc
	Timezone     string `json:"timezone"`
	Language     string `json:"language"`
	CPUABI       string `json:"cpuAbi"`
	TotalRAM     string `json:"totalRam"`
	InternalSize string `json:"internalSize"`

	RawProps map[string]string `json:"rawProps"`
}

// ── Shell helpers ──

func runShell(cmd string) (string, error) {
	out, err := exec.Command("sh", "-c", cmd).Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func runSu(cmd string) (string, error) {
	return runShell("su -c '" + strings.ReplaceAll(cmd, "'", "'\\''") + "'")
}

func shellGetprop(prop string) string {
	val, _ := runShell("getprop " + prop)
	return val
}

func shellSettings(namespace, key string) string {
	val, _ := runShell("settings get " + namespace + " " + key)
	if val == "null" {
		return ""
	}
	return val
}

func getIPAddress() string {
	// Try wlan0 first, then any interface
	for _, iface := range []string{"wlan0", "eth0", "rmnet_data0"} {
		out, _ := runShell("ip addr show " + iface + " 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1")
		if out != "" {
			return out
		}
	}
	// Fallback
	out, _ := runShell("ip addr show | grep 'inet ' | grep -v 127.0.0.1 | head -1 | awk '{print $2}' | cut -d/ -f1")
	return out
}

// ── Full Meta Collection ──

func CollectDeviceMeta(serial string) (*DeviceMeta, error) {
	m := &DeviceMeta{
		Serial:      serial,
		AgentVer:    Revision,
		CollectedAt: time.Now().Format(time.RFC3339),
		RawProps:    make(map[string]string),
	}

	getp := shellGetprop

	// Dump all props
	allProps, _ := runShell("getprop")
	for _, line := range strings.Split(allProps, "\n") {
		line = strings.TrimSpace(line)
		if idx := strings.Index(line, "]:"); idx > 0 && strings.HasPrefix(line, "[") {
			key := strings.TrimSpace(line[1:idx])
			val := strings.TrimSpace(line[idx+2:])
			if len(val) > 2 && val[0] == '[' && val[len(val)-1] == ']' {
				val = val[1 : len(val)-1]
			}
			m.RawProps[key] = val
		}
	}

	// Identity
	m.Brand = getp("ro.product.brand")
	m.Model = getp("ro.product.model")
	m.Manufacturer = getp("ro.product.manufacturer")
	m.ProductName = getp("ro.product.name")
	m.Device = getp("ro.product.device")
	m.Board = getp("ro.product.board")
	m.Hardware = getp("ro.hardware")
	m.Platform = getp("ro.board.platform")
	m.DeviceName = getp("bluetooth.device_name")
	if m.DeviceName == "" { m.DeviceName = getp("ro.product.model") }

	// Serial
	m.RealSerial = getp("ro.serialno")
	if m.RealSerial == "" { m.RealSerial = getp("ro.boot.serialno") }
	if m.RealSerial == "" { m.RealSerial = serial }

	// Build
	m.Fingerprint = getp("ro.build.fingerprint")
	m.BuildID = getp("ro.build.id")
	m.BuildType = getp("ro.build.type")
	m.BuildTags = getp("ro.build.tags")
	m.OSVersion = getp("ro.build.version.release")
	m.SDKVersion = getp("ro.build.version.sdk")
	m.Incremental = getp("ro.build.version.incremental")
	m.SecurityPatch = getp("ro.build.version.security_patch")
	m.Bootloader = getp("ro.bootloader")
	m.RadioBaseband = getp("gsm.version.baseband")

	// Display
	m.DisplayDensity = getp("ro.sf.lcd_density")
	w, _ := runShell("wm size 2>/dev/null | awk '{print $NF}' | cut -dx -f1")
	h, _ := runShell("wm size 2>/dev/null | awk '{print $NF}' | cut -dx -f2")
	m.DisplayWidth = w
	m.DisplayHeight = h

	// SIM / Telephony (needs root or service call)
	m.IMEI1 = getTelephony("imei1")
	m.IMEI2 = getTelephony("imei2")
	m.MEID = getTelephony("meid")
	m.IMSI1 = getTelephony("imsi1")
	m.IMSI2 = getTelephony("imsi2")
	m.ICCID1 = getTelephony("iccid1")
	m.ICCID2 = getTelephony("iccid2")
	m.PhoneNumber = getTelephony("phoneNumber")

	// Carrier from settings
	m.SIMOperator = shellSettings("global", "sim_operator")
	m.SIMCarrier = shellSettings("global", "sim_operator_name")
	m.SIMCountry = shellSettings("global", "sim_country_iso")

	// Network IDs
	m.MACWiFi = getNetworkID("wlan0")
	m.MACBluetooth = getNetworkID("bt_mac")
	m.WiFiSSID = shellSettings("global", "wifi_ssid")
	m.WiFiBSSID = shellSettings("global", "wifi_bssid")
	m.IPAddress = getIPAddress()

	// Persistent IDs
	m.AndroidID = shellSettings("secure", "android_id")
	m.AdvertisingID = getAdvertisingID()

	// Misc
	m.Timezone = getp("persist.sys.timezone")
	m.Language = getp("persist.sys.locale")
	m.CPUABI = or(getp("ro.product.cpu.abi"), getp("ro.product.cpu.abilist"))

	// RAM
	ram, _ := runShell("cat /proc/meminfo | grep MemTotal | awk '{print $2}'")
	if kb, err := strconv.Atoi(ram); err == nil && kb > 0 {
		m.TotalRAM = fmt.Sprintf("%.1f GB", float64(kb)/(1024*1024))
	}

	// Internal storage
	stor, _ := runShell("df -k /data | tail -1 | awk '{print $2}'")
	if kb, err := strconv.Atoi(stor); err == nil && kb > 0 {
		m.InternalSize = fmt.Sprintf("%.1f GB", float64(kb)/(1024*1024))
	}

	return m, nil
}

func getTelephony(what string) string {
	switch what {
	case "imei1":
		out, _ := runSu("service call iphonesubinfo 1 | grep -oE \"'[0-9]+'\" | head -1 | tr -d \"'\"")
		return out
	case "imei2":
		out, _ := runSu("service call iphonesubinfo 3 | grep -oE \"'[0-9]+'\" | head -1 | tr -d \"'\"")
		return out
	case "meid":
		out, _ := runSu("service call iphonesubinfo 4 | grep -oE \"'[0-9A-Fa-f]+'\" | head -1 | tr -d \"'\"")
		return out
	case "imsi1":
		return shellSettings("global", "imsi1")
	case "imsi2":
		return shellSettings("global", "imsi2")
	case "iccid1":
		return shellSettings("global", "iccid1")
	case "iccid2":
		return shellSettings("global", "iccid2")
	case "phoneNumber":
		return shellSettings("global", "phone_number")
	}
	return ""
}

func getNetworkID(iface string) string {
	if iface == "wlan0" {
		out, _ := runShell("cat /sys/class/net/wlan0/address 2>/dev/null")
		return out
	}
	if iface == "bt_mac" {
		out, _ := runShell("settings get secure bluetooth_address 2>/dev/null")
		return out
	}
	return ""
}

func getAdvertisingID() string {
	// Check for Google Play Services advertising ID
	paths := []string{
		"/data/data/com.google.android.gms/shared_prefs/adid_settings.xml",
		"/data/data/com.android.vending/shared_prefs/adid_settings.xml",
	}
	for _, p := range paths {
		data, err := os.ReadFile(p)
		if err == nil {
			content := string(data)
			if idx := strings.Index(content, "adid_key"); idx > 0 {
				// Extract from XML (simple)
				rest := content[idx:]
				if end := strings.Index(rest, "<"); strings.Count(rest[:end], ">") >= 2 {
					continue
				}
			}
		}
	}
	return shellSettings("google", "advertising_id")
}
