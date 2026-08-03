// client.go — WebSocket client for manager-agent communication

package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/url"
	"sync"

	"github.com/gorilla/websocket"
)

// ── Protocol Types ──

type AgentMessage struct {
	Type   string          `json:"type"`
	ID     string          `json:"id,omitempty"`
	Device *DeviceIdentity `json:"device,omitempty"`
	Data   json.RawMessage `json:"data,omitempty"`
	Error  string          `json:"error,omitempty"`
}

type DeviceIdentity struct {
	Serial       string `json:"serial"`
	Model        string `json:"model"`
	Brand        string `json:"brand"`
	Manufacturer string `json:"manufacturer"`
	OSVersion    string `json:"osVersion"`
	SDKVersion   string `json:"sdkVersion"`
	BuildID      string `json:"buildId"`
	Fingerprint  string `json:"fingerprint"`
	Hardware     string `json:"hardware"`
	CPUABI       string `json:"cpuAbi"`
	IPAddress    string `json:"ipAddress"`
	AgentVersion string `json:"agentVersion"`
}

type CommandHandler func(msg *AgentMessage) (interface{}, error)

// ── Agent Client ──

type AgentClient struct {
	ServerAddr string
	Device     *DeviceIdentity
	Secret     string
	Handlers   map[string]CommandHandler

	conn *websocket.Conn
	mu   sync.Mutex
	done chan struct{}
}

func (c *AgentClient) Connect() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.done = make(chan struct{})

	u := url.URL{
		Scheme: "ws",
		Host:   c.ServerAddr,
		Path:   "/agent/ws",
	}
	if c.Secret != "" {
		u.RawQuery = "secret=" + url.QueryEscape(c.Secret)
	}

	log.Printf("[droid-agent] connecting to %s", u.String())

	conn, _, err := websocket.DefaultDialer.Dial(u.String(), nil)
	if err != nil {
		return fmt.Errorf("dial: %w", err)
	}
	c.conn = conn

	// Send registration
	regMsg := AgentMessage{
		Type:   "register",
		Device: c.Device,
	}
	if err := c.writeJSON(regMsg); err != nil {
		conn.Close()
		return fmt.Errorf("register: %w", err)
	}
	log.Printf("[droid-agent] registered as %s", c.Device.Serial)

	// Read loop
	go c.readLoop()

	return nil
}

func (c *AgentClient) readLoop() {
	defer func() {
		c.mu.Lock()
		if c.conn != nil {
			c.conn.Close()
		}
		c.mu.Unlock()
		close(c.done)
	}()

	for {
		_, raw, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway) {
				return
			}
			log.Printf("[droid-agent] read error: %v", err)
			return
		}

		var msg AgentMessage
		if err := json.Unmarshal(raw, &msg); err != nil {
			log.Printf("[droid-agent] bad message: %v", err)
			continue
		}

		c.handleMessage(&msg)
	}
}

func (c *AgentClient) handleMessage(msg *AgentMessage) {
	switch msg.Type {
	case "ping":
		c.writeJSON(AgentMessage{Type: "pong", ID: msg.ID})
		return
	case "getProps":
		c.handleGetProps(msg)
		return
	case "setProp", "resetProps", "screenshot", "tap", "swipe",
		"install", "uninstall", "runCmd", "reboot", "wipeApp", "backupAcc":
		// Route to registered handler
		handler, ok := c.Handlers[msg.Type]
		if !ok {
			c.reply(msg, nil, fmt.Errorf("unknown command: %s", msg.Type))
			return
		}
		result, err := handler(msg)
		c.reply(msg, result, err)
	default:
		c.reply(msg, nil, fmt.Errorf("unknown type: %s", msg.Type))
	}
}

func (c *AgentClient) handleGetProps(msg *AgentMessage) {
	props, err := CollectDeviceMeta(c.Device.Serial)
	c.reply(msg, props, err)
}

func (c *AgentClient) reply(msg *AgentMessage, result interface{}, err error) {
	reply := AgentMessage{
		Type: msg.Type + "_result",
		ID:   msg.ID,
	}

	if err != nil {
		reply.Error = err.Error()
	} else if result != nil {
		data, _ := json.Marshal(result)
		reply.Data = data
	}

	c.writeJSON(reply)
}

func (c *AgentClient) writeJSON(v interface{}) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.conn == nil {
		return fmt.Errorf("not connected")
	}
	return c.conn.WriteJSON(v)
}

func (c *AgentClient) Wait() {
	<-c.done
}

func (c *AgentClient) Close() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.conn != nil {
		c.conn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
		c.conn.Close()
		c.conn = nil
	}
	if c.done != nil {
		select {
		case <-c.done:
		default:
			close(c.done)
		}
	}
}

// ── Identity ──

func collectIdentity() *DeviceIdentity {
	getp := shellGetprop

	return &DeviceIdentity{
		Serial:       or(getp("ro.serialno"), getp("ro.boot.serialno"), "unknown"),
		Model:        getp("ro.product.model"),
		Brand:        getp("ro.product.brand"),
		Manufacturer: getp("ro.product.manufacturer"),
		OSVersion:    getp("ro.build.version.release"),
		SDKVersion:   getp("ro.build.version.sdk"),
		BuildID:      getp("ro.build.id"),
		Fingerprint:  getp("ro.build.fingerprint"),
		Hardware:     getp("ro.hardware"),
		CPUABI:       or(getp("ro.product.cpu.abi"), getp("ro.product.cpu.abilist")),
		IPAddress:    getIPAddress(),
		AgentVersion: Revision,
	}
}

func or(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}
