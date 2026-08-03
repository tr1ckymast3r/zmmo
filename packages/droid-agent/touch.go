// touch.go — Touch injection + screenshot
// Uses input tap/swipe + screencap (built into Android)

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"time"
)

// ── Touch / Gesture ──

type TouchParams struct {
	X        int    `json:"x"`
	Y        int    `json:"y"`
	X2       int    `json:"x2"`
	Y2       int    `json:"y2"`
	Duration int    `json:"duration"` // ms for swipe
	Text     string `json:"text"`
	Action   string `json:"action"` // "tap", "swipe", "home", "power", "volUp", "volDown"
}

func handleTouch(raw json.RawMessage) (map[string]string, error) {
	var p TouchParams
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, fmt.Errorf("invalid touch params: %w", err)
	}

	result := make(map[string]string)

	switch p.Action {
	case "tap":
		cmd := fmt.Sprintf("input tap %d %d", p.X, p.Y)
		out, err := runShell(cmd)
		if err != nil {
			return nil, fmt.Errorf("tap: %w (%s)", err, out)
		}
		result["tap"] = fmt.Sprintf("%d,%d", p.X, p.Y)

	case "swipe":
		dur := p.Duration
		if dur == 0 {
			dur = 300
		}
		cmd := fmt.Sprintf("input swipe %d %d %d %d %d", p.X, p.Y, p.X2, p.Y2, dur)
		out, err := runShell(cmd)
		if err != nil {
			return nil, fmt.Errorf("swipe: %w (%s)", err, out)
		}
		result["swipe"] = fmt.Sprintf("%d,%d → %d,%d (%dms)", p.X, p.Y, p.X2, p.Y2, dur)

	case "home":
		out, err := runShell("input keyevent KEYCODE_HOME")
		if err != nil {
			return nil, fmt.Errorf("home: %w (%s)", err, out)
		}
		result["home"] = "pressed"

	case "power":
		out, err := runShell("input keyevent KEYCODE_POWER")
		if err != nil {
			return nil, fmt.Errorf("power: %w (%s)", err, out)
		}
		result["power"] = "pressed"

	case "back":
		out, err := runShell("input keyevent KEYCODE_BACK")
		if err != nil {
			return nil, fmt.Errorf("back: %w (%s)", err, out)
		}
		result["back"] = "pressed"

	case "volUp":
		out, err := runShell("input keyevent KEYCODE_VOLUME_UP")
		if err != nil {
			return nil, fmt.Errorf("volUp: %w (%s)", err, out)
		}
		result["volUp"] = "pressed"

	case "volDown":
		out, err := runShell("input keyevent KEYCODE_VOLUME_DOWN")
		if err != nil {
			return nil, fmt.Errorf("volDown: %w (%s)", err, out)
		}
		result["volDown"] = "pressed"

	case "text":
		if p.Text == "" {
			return nil, fmt.Errorf("text field required")
		}
		// Escape special chars for input text
		text := escapeInputText(p.Text)
		out, err := runShell(fmt.Sprintf("input text '%s'", text))
		if err != nil {
			return nil, fmt.Errorf("text: %w (%s)", err, out)
		}
		result["text"] = p.Text

	default:
		return nil, fmt.Errorf("unknown action: %s", p.Action)
	}

	return result, nil
}

func escapeInputText(s string) string {
	// Replace single quote with nothing (input text can't handle it)
	result := ""
	for _, c := range s {
		if c == '\'' {
			continue
		}
		if c == ' ' {
			result += "%s"
		} else {
			result += string(c)
		}
	}
	return result
}

// ── Screenshot ──

func handleScreenshot() (map[string]string, error) {
	timestamp := time.Now().Unix()
	path := fmt.Sprintf("/data/local/tmp/zmmo_screenshot_%d.png", timestamp)

	cmd := fmt.Sprintf("screencap -p %s", path)
	out, err := runShell(cmd)
	if err != nil {
		return nil, fmt.Errorf("screencap: %w (%s)", err, out)
	}

	// Get file size
	size, _ := runShell(fmt.Sprintf("stat -c%%s %s 2>/dev/null", path))

	result := map[string]string{
		"path":      path,
		"timestamp": fmt.Sprintf("%d", timestamp),
		"size":      size,
	}

	// Base64 encode for transport (small screens receive inline)
	// For large files, the path is returned and panel fetches via /adb/download
	out, err = runShell(fmt.Sprintf("base64 %s | tr -d '\\n'", path))
	if err == nil && len(out) < 500000 { // ~375KB PNG threshold
		result["dataB64"] = out
	} else {
		log.Printf("[touch] screenshot too large for inline (%d bytes)", len(out))
	}

	return result, nil
}
