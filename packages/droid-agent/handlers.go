// handlers.go — Wire up command handlers for the agent

package main

import "encoding/json"

func buildHandlers() map[string]CommandHandler {
	return map[string]CommandHandler{
		"setProp": func(msg *AgentMessage) (interface{}, error) {
			var cs ChangeSet
			if err := parseData(msg, &cs); err != nil {
				return nil, err
			}
			results := make(map[string]string)
			for _, p := range cs.Props {
				if err := applyPropChange(p.Key, p.Value, p.Enabled); err != nil {
					results[p.Key] = err.Error()
				} else if p.Enabled {
					results[p.Key] = "changed"
				} else {
					results[p.Key] = "skipped"
				}
			}
			return results, nil
		},

		"resetProps": func(msg *AgentMessage) (interface{}, error) {
			return resetAllProps()
		},

		"screenshot": func(msg *AgentMessage) (interface{}, error) {
			return handleScreenshot()
		},

		"tap": func(msg *AgentMessage) (interface{}, error) {
			return handleTouch(msg.Data)
		},

		"swipe": func(msg *AgentMessage) (interface{}, error) {
			return handleTouch(msg.Data)
		},

		"install": func(msg *AgentMessage) (interface{}, error) {
			return handleInstall(msg.Data)
		},

		"uninstall": func(msg *AgentMessage) (interface{}, error) {
			return handleUninstall(msg.Data)
		},

		"wipeApp": func(msg *AgentMessage) (interface{}, error) {
			return handleWipeApp(msg.Data)
		},

		"backupAcc": func(msg *AgentMessage) (interface{}, error) {
			return handleAccOp(msg.Data)
		},

		"restoreAcc": func(msg *AgentMessage) (interface{}, error) {
			return handleAccOp(msg.Data)
		},

		"reboot": func(msg *AgentMessage) (interface{}, error) {
			return handleReboot()
		},

		"runCmd": func(msg *AgentMessage) (interface{}, error) {
			return handleRunCmd(msg.Data)
		},
	}
}

func parseData(msg *AgentMessage, v interface{}) error {
	if msg.Data == nil {
		return nil
	}
	return json.Unmarshal(msg.Data, v)
}
