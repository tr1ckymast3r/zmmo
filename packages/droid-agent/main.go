// droid-agent — Native Android device agent
//
// Runs on rooted Android devices. Connects to ZMMO manager-agent
// via WebSocket. Receives commands: getProps, setProp, resetProps,
// screenshot, tap, swipe, install/uninstall, reboot, runCmd.
//
// Build: GOOS=android GOARCH=arm64 go build -ldflags="-s -w" -o droid-agent .
//   or: make android-arm64  /  make android-arm
//
// Deploy: adb push droid-agent /data/local/tmp/
//         adb shell chmod 755 /data/local/tmp/droid-agent
//         adb shell /data/local/tmp/droid-agent -server 192.168.1.100:55555
//
// For persistent daemon: package as Magisk module or init.d script.

package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"
)

var (
	serverAddr = flag.String("server", "127.0.0.1:55555", "manager-agent address")
	deviceID   = flag.String("id", "", "device identifier (default: ro.serialno)")
	secret     = flag.String("secret", "", "auth secret (optional)")
	debug      = flag.Bool("debug", false, "enable debug logging")
)

func main() {
	flag.Parse()

	if !*debug {
		log.SetFlags(0)
	}

	log.Printf("[droid-agent] starting (rev %s)", Revision)

	// Collect device identity
	ident := collectIdentity()
	if *deviceID != "" {
		ident.Serial = *deviceID
	}
	log.Printf("[droid-agent] device: %s (%s %s / Android %s)",
		ident.Serial, ident.Brand, ident.Model, ident.OSVersion)

	// Create agent client
	agent := &AgentClient{
		ServerAddr: *serverAddr,
		Device:     ident,
		Secret:     *secret,
		Handlers:   buildHandlers(),
	}

	// Connect with auto-reconnect
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		for {
			if err := agent.Connect(); err != nil {
				log.Printf("[droid-agent] connection error: %v — retrying in 5s", err)
				time.Sleep(5 * time.Second)
				continue
			}
			// Connected — block until disconnect
			agent.Wait()
			log.Printf("[droid-agent] disconnected — reconnecting in 3s")
			time.Sleep(3 * time.Second)
		}
	}()

	<-sigCh
	log.Printf("[droid-agent] shutting down")
	agent.Close()
}
