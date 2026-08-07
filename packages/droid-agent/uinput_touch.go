// uinput_touch.go — Virtual input device touch injection via /dev/uinput
// Creates a temporary virtual touchscreen, injects events, then destroys it.
// Priority #2 in the fallback chain (after sendevent, before input cmd).

package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"log"
	"os"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

// ── uinput ioctl constants (from linux/uinput.h) ──

const (
	uinputPath = "/dev/uinput"

	// ioctl commands
	_UI_SET_EV_BIT  = 0x40045564 // _IOW('U', 100, int)
	_UI_SET_KEY_BIT = 0x40045565 // _IOW('U', 101, int)
	_UI_SET_ABS_BIT = 0x40045567 // _IOW('U', 103, int)
	_UI_DEV_CREATE  = 0x5501     // _IO('U', 1)
	_UI_DEV_DESTROY = 0x5502     // _IO('U', 2)
)

// uinputUserDev mirrors struct uinput_user_dev for UI_DEV_SETUP
type uinputUserDev struct {
	Name     [80]byte
	ID       inputID
	FFEffectsMax uint32
	AbsMax   [64]int32
	AbsMin   [64]int32
	AbsFuzz  [64]int32
	AbsFlat  [64]int32
}

type inputID struct {
	Bustype uint16
	Vendor  uint16
	Product uint16
	Version uint16
}

// ── Virtual touch device ──

// createVirtualTouchDevice sets up a uinput virtual touchscreen.
// Returns the fd (open /dev/uinput) and the device path created.
func createVirtualTouchDevice(name string) (fd int, devPath string, err error) {
	f, err := os.OpenFile(uinputPath, os.O_WRONLY|syscall.O_NONBLOCK, 0)
	if err != nil {
		return 0, "", fmt.Errorf("open %s: %w (kernel support?)", uinputPath, err)
	}

	fd = int(f.Fd()) // keep fd for ioctl; f will close on GC
	// Prevent Go from closing fd when f is GC'd — we manage it manually
	syscall.SetNonblock(fd, false)

	// Enable event types: EV_SYN, EV_KEY, EV_ABS
	for _, ev := range []uintptr{uintptr(EV_SYN), uintptr(EV_KEY), uintptr(EV_ABS)} {
		if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), _UI_SET_EV_BIT, ev); errno != 0 {
			f.Close()
			return 0, "", fmt.Errorf("ioctl UI_SET_EV_BIT(%d): %v", ev, errno)
		}
	}

	// Enable key: BTN_TOUCH
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), _UI_SET_KEY_BIT, uintptr(BTN_TOUCH)); errno != 0 {
		f.Close()
		return 0, "", fmt.Errorf("ioctl UI_SET_KEY_BIT(BTN_TOUCH): %v", errno)
	}

	// Enable multitouch absolute axes
	for _, axis := range []uintptr{
		uintptr(ABS_MT_SLOT),
		uintptr(ABS_MT_TRACKING_ID),
		uintptr(ABS_MT_POSITION_X),
		uintptr(ABS_MT_POSITION_Y),
		uintptr(ABS_MT_PRESSURE),
		uintptr(ABS_MT_TOUCH_MAJOR),
	} {
		if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), _UI_SET_ABS_BIT, axis); errno != 0 {
			f.Close()
			return 0, "", fmt.Errorf("ioctl UI_SET_ABS_BIT(%d): %v", axis, errno)
		}
	}

	// Configure device with absolute axis limits
	setup := uinputUserDev{}
	copy(setup.Name[:], name)
	setup.ID.Bustype = 0x03 // BUS_USB (looks like a real USB HID device)

	// Get screen size for axis limits (fallback 1080x2400)
	w, h := getScreenSize()
	setup.AbsMax[ABS_MT_POSITION_X] = int32(w)
	setup.AbsMax[ABS_MT_POSITION_Y] = int32(h)
	setup.AbsMax[ABS_MT_PRESSURE] = 255
	setup.AbsMax[ABS_MT_TOUCH_MAJOR] = 15

	var buf bytes.Buffer
	binary.Write(&buf, binary.LittleEndian, setup)

	// UI_DEV_SETUP
	// ioctl is: _IOW('U', 3, struct uinput_user_dev) = 0x405c5503
	const _UI_DEV_SETUP uintptr = 0x405c5503
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), _UI_DEV_SETUP, uintptr(unsafe.Pointer(&buf.Bytes()[0]))); errno != 0 {
		f.Close()
		return 0, "", fmt.Errorf("ioctl UI_DEV_SETUP: %v", errno)
	}

	// UI_DEV_CREATE
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), _UI_DEV_CREATE, 0); errno != 0 {
		f.Close()
		return 0, "", fmt.Errorf("ioctl UI_DEV_CREATE: %v", errno)
	}

	// After creation, Android creates /dev/input/eventN — find it
	devPath = findNewInputDevice(name)
	log.Printf("[uinput] virtual device %q created at %s (fd=%d)", name, devPath, fd)

	return fd, devPath, nil
}

// destroyVirtualTouchDevice destroys the uinput device.
func destroyVirtualTouchDevice(fd int) {
	if fd > 0 {
		syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), _UI_DEV_DESTROY, 0)
		syscall.Close(fd)
	}
}

// ── Helper: find newly created input device ──

func findNewInputDevice(name string) string {
	// After uinput creation, udev creates /dev/input/eventN
	// Find the device with matching name via /sys
	entries, err := os.ReadDir("/dev/input")
	if err != nil {
		return ""
	}
	for _, e := range entries {
		if !strings.HasPrefix(e.Name(), "event") {
			continue
		}
		devPath := "/dev/input/" + e.Name()
		// Read the device name from /sys/class/input/eventN/device/name
		namePath := fmt.Sprintf("/sys/class/input/%s/device/name", e.Name())
		if data, err := os.ReadFile(namePath); err == nil {
			if strings.TrimSpace(string(data)) == name {
				return devPath
			}
		}
	}
	return ""
}

// ── Screen size ──

func getScreenSize() (width, height int) {
	// Try dumpsys window
	out, _ := runShell("dumpsys window displays 2>/dev/null | grep init=")
	if out != "" {
		// Parse "init=1080x2400" or similar
		start := strings.Index(out, "init=")
		if start >= 0 {
			out = out[start+5:]
			end := strings.IndexByte(out, ' ')
			if end < 0 {
				end = len(out)
			}
			out = out[:end]
			fmt.Sscanf(out, "%dx%d", &width, &height)
			if width > 0 && height > 0 {
				return
			}
		}
	}
	// Fallback: wm size
	out, _ = runShell("wm size 2>/dev/null")
	if strings.Contains(out, "Override size:") {
		fmt.Sscanf(out, "Override size: %dx%d", &width, &height)
	} else {
		fmt.Sscanf(out, "Physical size: %dx%d", &width, &height)
	}
	if width <= 0 || height <= 0 {
		width, height = 1080, 2400
	}
	return
}

// ── Public API ──

// injectTapUinput performs a tap using a virtual uinput device.
func injectTapUinput(x, y int32) error {
	fd, dev, err := createVirtualTouchDevice("ZMMO Virtual Touch")
	if err != nil {
		return err
	}
	defer destroyVirtualTouchDevice(fd)

	// Write events to fd directly (not through dev path, more reliable)
	writeUinputEvent := func(evType, code uint16, value int32) error {
		ev := InputEvent{
			Sec:  time.Now().Unix(),
			USec: int64(time.Now().Nanosecond() / 1000),
			Type: evType,
			Code: code,
			Value: value,
		}
		return binary.Write(os.NewFile(uintptr(fd), "uinput"), binary.LittleEndian, ev)
	}

	// Touch down
	writeUinputEvent(EV_ABS, ABS_MT_SLOT, 0)
	writeUinputEvent(EV_ABS, ABS_MT_TRACKING_ID, 0)
	writeUinputEvent(EV_ABS, ABS_MT_POSITION_X, x)
	writeUinputEvent(EV_ABS, ABS_MT_POSITION_Y, y)
	writeUinputEvent(EV_ABS, ABS_MT_PRESSURE, 30)
	writeUinputEvent(EV_KEY, BTN_TOUCH, 1)
	writeUinputEvent(EV_SYN, SYN_REPORT, 0)

	// Touch up
	writeUinputEvent(EV_ABS, ABS_MT_TRACKING_ID, -1)
	writeUinputEvent(EV_KEY, BTN_TOUCH, 0)
	writeUinputEvent(EV_SYN, SYN_REPORT, 0)

	_ = dev
	return nil
}

// injectSwipeUinput performs a swipe using a virtual uinput device.
func injectSwipeUinput(x1, y1, x2, y2 int32, duration int) error {
	fd, dev, err := createVirtualTouchDevice("ZMMO Virtual Touch")
	if err != nil {
		return err
	}
	defer destroyVirtualTouchDevice(fd)

	writeUinputEvent := func(evType, code uint16, value int32) error {
		ev := InputEvent{
			Sec:  time.Now().Unix(),
			USec: int64(time.Now().Nanosecond() / 1000),
			Type: evType,
			Code: code,
			Value: value,
		}
		return binary.Write(os.NewFile(uintptr(fd), "uinput"), binary.LittleEndian, ev)
	}

	steps := duration / 16
	if steps < 2 { steps = 2 }
	if steps > 50 { steps = 50 }
	stepDelay := time.Duration(duration) * time.Millisecond / time.Duration(steps)

	dx := float64(x2 - x1)
	dy := float64(y2 - y1)

	// Touch down
	writeUinputEvent(EV_ABS, ABS_MT_SLOT, 0)
	writeUinputEvent(EV_ABS, ABS_MT_TRACKING_ID, 0)
	writeUinputEvent(EV_ABS, ABS_MT_POSITION_X, x1)
	writeUinputEvent(EV_ABS, ABS_MT_POSITION_Y, y1)
	writeUinputEvent(EV_ABS, ABS_MT_PRESSURE, 30)
	writeUinputEvent(EV_KEY, BTN_TOUCH, 1)
	writeUinputEvent(EV_SYN, SYN_REPORT, 0)

	// Interpolated move
	for i := 1; i <= steps; i++ {
		t := float64(i) / float64(steps)
		cx := x1 + int32(dx*t)
		cy := y1 + int32(dy*t)
		writeUinputEvent(EV_ABS, ABS_MT_POSITION_X, cx)
		writeUinputEvent(EV_ABS, ABS_MT_POSITION_Y, cy)
		writeUinputEvent(EV_SYN, SYN_REPORT, 0)
		if i < steps {
			time.Sleep(stepDelay)
		}
	}

	// Touch up
	writeUinputEvent(EV_ABS, ABS_MT_TRACKING_ID, -1)
	writeUinputEvent(EV_KEY, BTN_TOUCH, 0)
	writeUinputEvent(EV_SYN, SYN_REPORT, 0)

	_ = dev
	return nil
}
