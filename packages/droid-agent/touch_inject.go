// touch_inject.go — Low-level touch injection via /dev/input/eventX
// Fallback chain: sendevent (direct) → sendevent (binary) → input cmd
// Much harder to detect than "input tap/swipe"

package main

import (
	"encoding/binary"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"
)

// ── Linux input subsystem constants ──

const (
	EV_SYN = 0x00
	EV_KEY = 0x01
	EV_ABS = 0x03

	SYN_REPORT = 0

	BTN_TOUCH = 0x14a // 330

	ABS_MT_TRACKING_ID = 0x39 // 57
	ABS_MT_POSITION_X  = 0x35 // 53
	ABS_MT_POSITION_Y  = 0x36 // 54
	ABS_MT_PRESSURE    = 0x30 // 48
	ABS_MT_SLOT        = 0x2f // 47
)

// InputEvent is the raw Linux input_event struct (24 bytes on 64-bit)
type InputEvent struct {
	Sec   int64
	USec  int64
	Type  uint16
	Code  uint16
	Value int32
}

// ── Touch device cache ──

var (
	touchDev     string
	touchDevMu   sync.Mutex
	touchDevInited bool
)

// findTouchDevice scans /dev/input/event* for the touchscreen device.
// Uses a quick heuristic: the device must support ABS_MT_POSITION_X.
func findTouchDevice() string {
	touchDevMu.Lock()
	if touchDevInited {
		defer touchDevMu.Unlock()
		return touchDev
	}
	touchDevMu.Unlock()

	// Scan /dev/input/event[0-9]*
	entries, err := os.ReadDir("/dev/input")
	if err != nil {
		touchDevMu.Lock()
		touchDevInited = true
		touchDevMu.Unlock()
		return ""
	}

	for _, e := range entries {
		if !strings.HasPrefix(e.Name(), "event") {
			continue
		}
		devPath := "/dev/input/" + e.Name()

		// Use getevent to check if this device reports ABS_MT_POSITION_X
		out, err := runShell(fmt.Sprintf("getevent -p %s 2>/dev/null", devPath))
		if err != nil {
			continue
		}
		if strings.Contains(out, "ABS_MT_POSITION_X") {
			// Also must have KEY (01) handler, which touchscreens have
			devPath = resolveDevPath(devPath)

			touchDevMu.Lock()
			touchDev = devPath
			touchDevInited = true
			touchDevMu.Unlock()
			return devPath
		}
	}

	touchDevMu.Lock()
	touchDevInited = true
	touchDevMu.Unlock()
	return ""
}

// resolveDevPath ensures we use the real path (follows symlinks)
func resolveDevPath(p string) string {
	if real, err := os.Readlink(p); err == nil {
		return "/dev/input/" + strings.TrimPrefix(real, "../input/")
	}
	return p
}

// ── sendevent via direct /dev/input write ──

// injectEvent writes a single input_event to the touch device.
func injectEvent(dev string, evType, code uint16, value int32) error {
	f, err := os.OpenFile(dev, os.O_WRONLY, 0)
	if err != nil {
		return fmt.Errorf("open %s: %w", dev, err)
	}
	defer f.Close()

	now := time.Now()
	ev := InputEvent{
		Sec:  now.Unix(),
		USec: int64(now.Nanosecond() / 1000), // microseconds
		Type: evType,
		Code: code,
		Value: value,
	}

	return binary.Write(f, binary.LittleEndian, ev)
}

// injectSync writes a SYN_REPORT.
func injectSync(dev string) error {
	return injectEvent(dev, EV_SYN, SYN_REPORT, 0)
}

// tapDown writes the touch-down sequence.
func tapDown(dev string, x, y int32) error {
	if err := injectEvent(dev, EV_ABS, ABS_MT_TRACKING_ID, 0); err != nil {
		return err
	}
	if err := injectEvent(dev, EV_ABS, ABS_MT_POSITION_X, x); err != nil {
		return err
	}
	if err := injectEvent(dev, EV_ABS, ABS_MT_POSITION_Y, y); err != nil {
		return err
	}
	if err := injectEvent(dev, EV_ABS, ABS_MT_PRESSURE, 30); err != nil {
		return err
	}
	if err := injectEvent(dev, EV_KEY, BTN_TOUCH, 1); err != nil {
		return err
	}
	return injectSync(dev)
}

// tapUp writes the touch-up sequence.
func tapUp(dev string) error {
	if err := injectEvent(dev, EV_ABS, ABS_MT_TRACKING_ID, -1); err != nil {
		return err
	}
	if err := injectEvent(dev, EV_KEY, BTN_TOUCH, 0); err != nil {
		return err
	}
	return injectSync(dev)
}

// ── Public inject API ──

// injectTapSendevent taps at (x,y) using direct /dev/input event injection.
func injectTapSendevent(dev string, x, y int32) error {
	if dev == "" {
		return fmt.Errorf("no touch device found")
	}
	if err := tapDown(dev, x, y); err != nil {
		return err
	}
	if err := tapUp(dev); err != nil {
		return err
	}
	return nil
}

// injectSwipeSendevent performs a swipe from (x1,y1) to (x2,y2) with duration ms.
// Interpolates intermediate touch positions for smooth motion.
func injectSwipeSendevent(dev string, x1, y1, x2, y2 int32, duration int) error {
	if dev == "" {
		return fmt.Errorf("no touch device found")
	}

	steps := duration / 16 // ~60fps interpolated
	if steps < 2 {
		steps = 2
	}
	if steps > 50 {
		steps = 50
	}

	stepDelay := time.Duration(duration) * time.Millisecond / time.Duration(steps)

	dx := float64(x2 - x1)
	dy := float64(y2 - y1)

	// Touch down
	if err := injectEvent(dev, EV_ABS, ABS_MT_TRACKING_ID, 0); err != nil {
		return err
	}
	if err := injectEvent(dev, EV_ABS, ABS_MT_POSITION_X, x1); err != nil {
		return err
	}
	if err := injectEvent(dev, EV_ABS, ABS_MT_POSITION_Y, y1); err != nil {
		return err
	}
	if err := injectEvent(dev, EV_ABS, ABS_MT_PRESSURE, 30); err != nil {
		return err
	}
	if err := injectEvent(dev, EV_KEY, BTN_TOUCH, 1); err != nil {
		return err
	}
	if err := injectSync(dev); err != nil {
		return err
	}

	// Move through interpolated positions
	for i := 1; i <= steps; i++ {
		t := float64(i) / float64(steps)
		cx := x1 + int32(dx*t)
		cy := y1 + int32(dy*t)

		if err := injectEvent(dev, EV_ABS, ABS_MT_POSITION_X, cx); err != nil {
			return err
		}
		if err := injectEvent(dev, EV_ABS, ABS_MT_POSITION_Y, cy); err != nil {
			return err
		}
		if err := injectSync(dev); err != nil {
			return err
		}
		if i < steps {
			time.Sleep(stepDelay)
		}
	}

	// Touch up
	if err := injectEvent(dev, EV_ABS, ABS_MT_TRACKING_ID, -1); err != nil {
		return err
	}
	if err := injectEvent(dev, EV_KEY, BTN_TOUCH, 0); err != nil {
		return err
	}
	if err := injectSync(dev); err != nil {
		return err
	}

	return nil
}

// ── Fallback chain ──

// injectTouchIntelligently chooses the best injection method.
// Priority: sendevent direct > sendevent binary > input cmd
func injectTouchIntelligently(action string, params map[string]int32) (method string, err error) {
	dev := findTouchDevice()

	// Method 1: sendevent direct (most stealth)
	if dev != "" {
		switch action {
		case "tap":
			x, y := params["x"], params["y"]
			if err := injectTapSendevent(dev, x, y); err == nil {
				return "sendevent", nil
			}
		case "swipe":
			x1, y1 := params["x1"], params["y1"]
			x2, y2 := params["x2"], params["y2"]
			dur := int(params["duration"])
			if dur == 0 { dur = 300 }
			if err := injectSwipeSendevent(dev, x1, y1, x2, y2, dur); err == nil {
				return "sendevent", nil
			}
		}
	}

	// Method 2: fallback — caller uses input tap/swipe
	return "input", fmt.Errorf("sendevent unavailable, fall back to input cmd")
}

// cachedTouchDev is a thread-safe lookup
func cachedTouchDev() string {
	touchDevMu.Lock()
	defer touchDevMu.Unlock()
	if !touchDevInited {
		return ""
	}
	return touchDev
}
