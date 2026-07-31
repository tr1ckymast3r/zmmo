package main

import (
	"encoding/json"
	"os"
)

// LoadDeviceSeeds reads seed/devices.json
func LoadDeviceSeeds() ([]Device, error) {
	data, err := os.ReadFile("seed/devices.json")
	if err != nil {
		return nil, err
	}
	var devices []Device
	if err := json.Unmarshal(data, &devices); err != nil {
		return nil, err
	}
	return devices, nil
}

// LoadCarrierSeeds reads seed/carriers.json
func LoadCarrierSeeds() ([]Carrier, error) {
	data, err := os.ReadFile("seed/carriers.json")
	if err != nil {
		return nil, err
	}
	var carriers []Carrier
	if err := json.Unmarshal(data, &carriers); err != nil {
		return nil, err
	}
	return carriers, nil
}
