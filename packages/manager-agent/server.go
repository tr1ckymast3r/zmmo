package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
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
	Filename  string      `json:"filename"`
	Size      int64       `json:"size"`
	Props     DeviceProps `json:"props"`
	CreatedAt string      `json:"createdAt"`
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

const version = "1.1.0"

// ── ADB Helpers ──

func adbDevices() []string {
	out, err := exec.Command("adb", "devices").Output()
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
		if strings.Contains(l, "\tdevice") {
			serials = append(serials, strings.Split(l, "\t")[0])
		}
	}
	return serials
}

func adbShell(serial, cmd string) (string, error) {
	out, err := exec.Command("adb", "-s", serial, "shell", cmd).Output()
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
			Features:   []string{"adb", "backup", "restore", "props"},
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
		writeJSON(w, found)
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
			exec.Command("adb", "-s", serial, "shell", "setprop "+prop+" "+pv.Value).Run()
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
		out, err := exec.Command("adb", "-s", serial, "reboot").CombinedOutput()
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

func handleBackups(w http.ResponseWriter, r *http.Request) {
	if r.Method != "GET" {
		writeError(w, 405, "method not allowed")
		return
	}
	backupsMu.RLock()
	list := make([]BackupInfo, 0, len(backups))
	for _, b := range backups {
		list = append(list, *b)
	}
	backupsMu.RUnlock()
	writeJSON(w, list)
}

func handleBackupRestore(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/backups/"), "/")
	if len(parts) < 2 || parts[1] != "restore" {
		writeError(w, 404, "not found")
		return
	}
	var body struct {
		DeviceID string `json:"deviceId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, 400, "invalid JSON")
		return
	}
	backupsMu.RLock()
	backup, ok := backups[parts[0]]
	backupsMu.RUnlock()
	if !ok {
		writeError(w, 404, "backup not found")
		return
	}
	applyProps(body.DeviceID, &backup.Props)
	writeJSON(w, map[string]bool{"ok": true})
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

func startServer() error {
	serverMu.Lock()
	defer serverMu.Unlock()
	if server != nil {
		return fmt.Errorf("already running")
	}
	os.MkdirAll("./backups", 0755)

	mux := http.NewServeMux()
	mux.HandleFunc("/status", handleStatus)
	mux.HandleFunc("/devices", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/devices" {
			handleDevices(w, r)
		} else {
			handleDevice(w, r)
		}
	})
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
	mux.HandleFunc("/adb/", handleADB)
	mux.HandleFunc("/license/activate", handleLicenseActivate)

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
