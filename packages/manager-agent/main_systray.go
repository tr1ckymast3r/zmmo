//go:build windows || darwin

package main

import (
	"log"

	"github.com/getlantern/systray"
)

// 16x16 PNG icon (blue/purple gradient)
var iconData = []byte{
	0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
	0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x10,
	0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0xF3, 0xFF, 0x61, 0x00, 0x00, 0x00,
	0x01, 0x73, 0x52, 0x47, 0x42, 0x00, 0xAE, 0xCE, 0x1C, 0xE9, 0x00, 0x00,
	0x00, 0x7B, 0x49, 0x44, 0x41, 0x54, 0x38, 0xCB, 0x63, 0x60, 0x18, 0x05,
	0xA3, 0x60, 0x14, 0x0C, 0x25, 0x00, 0x00, 0xEA, 0xB5, 0x10, 0x30, 0xDE,
	0x08, 0x57, 0x43, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
	0x42, 0x60, 0x82,
}

func onReady() {
	systray.SetIcon(iconData)
	systray.SetTitle("ZMMO Agent")
	systray.SetTooltip("ZMMO Device Changer Agent")

	mStatus := systray.AddMenuItem("Starting...", "Server status")
	mStatus.Disable()
	systray.AddSeparator()

	mStart := systray.AddMenuItem("Start", "Start agent server")
	mStop := systray.AddMenuItem("Stop", "Stop agent server")
	mRestart := systray.AddMenuItem("Restart", "Restart agent server")
	systray.AddSeparator()
	mQuit := systray.AddMenuItem("Quit", "Exit ZMMO Agent")

	startServer()
	updateTrayStatus(mStatus, mStart, mStop, mRestart)

	for {
		select {
		case <-mStart.ClickedCh:
			if err := startServer(); err != nil {
				mStatus.SetTitle("Error: " + err.Error())
			}
			updateTrayStatus(mStatus, mStart, mStop, mRestart)
		case <-mStop.ClickedCh:
			stopServer()
			updateTrayStatus(mStatus, mStart, mStop, mRestart)
		case <-mRestart.ClickedCh:
			restartServer()
			updateTrayStatus(mStatus, mStart, mStop, mRestart)
		case <-mQuit.ClickedCh:
			stopServer()
			systray.Quit()
			return
		}
	}
}

func onExit() {
	stopServer()
}

func updateTrayStatus(mStatus, mStart, mStop, mRestart *systray.MenuItem) {
	status := serverStatus()
	mStatus.SetTitle(status)
	serverMu.Lock()
	running := server != nil
	serverMu.Unlock()
	if running {
		mStart.Disable()
		mStop.Enable()
		mRestart.Enable()
		systray.SetTooltip("ZMMO Agent — "+status)
	} else {
		mStart.Enable()
		mStop.Disable()
		mRestart.Disable()
		systray.SetTooltip("ZMMO Agent — Stopped")
	}
}

func main() {
	log.SetFlags(0)
	systray.Run(onReady, onExit)
}
