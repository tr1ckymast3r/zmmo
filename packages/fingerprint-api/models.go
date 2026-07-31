package main

// Device — full fingerprint snapshot from real device
type Device struct {
	ID             int64    `json:"id"`
	Model          string   `json:"model"`           // e.g. "iPhone14,3", "SM-G998B"
	MarketingName  string   `json:"marketingName"`   // e.g. "iPhone 13 Pro Max"
	OS             string   `json:"os"`              // "iOS", "Android"
	OSVersion      string   `json:"osVersion"`       // e.g. "16.5", "13"
	CPU            string   `json:"cpu"`             // e.g. "Apple A15 Bionic"
	CPUCores       int      `json:"cpuCores"`
	CPUArch        string   `json:"cpuArchitecture"` // "arm64e", "aarch64"
	CPUFeatures    string   `json:"cpuFeatures"`     // JSON array string
	RAM            int64    `json:"ram"`             // MB
	Storage        int64    `json:"storage"`         // GB
	Resolution     string   `json:"resolution"`      // "1284x2778"
	Width          int      `json:"width"`
	Height         int      `json:"height"`
	DPI            int      `json:"dpi"`
	Scale          float64  `json:"scale"`
	GPU            string   `json:"gpu"`
	ScreenSize     float64  `json:"screenSize"` // inches
	ScreenType     string   `json:"screenType"` // "OLED", "IPS LCD"
	Battery        int      `json:"battery"`    // mAh
	Sensors        string   `json:"sensors"`    // JSON array
	BuildID        string   `json:"buildId"`    // e.g. "20F75", "TP1A.220624.014"
	Fingerprint    string   `json:"fingerprint"` // Android build fingerprint
	Manufacturer   string   `json:"manufacturer"`
	Brand          string   `json:"brand"`
	Device         string   `json:"device"`     // Android device codename
	Hardware       string   `json:"hardware"`   // Android hardware
	ReleaseDate    string   `json:"releaseDate"`
	Source         string   `json:"source"`     // "real_device", "official", "crowdsourced"
}

// Carrier — mobile network carrier profile
type Carrier struct {
	ID           int64  `json:"id"`
	CarrierName  string `json:"carrierName"`
	Country      string `json:"country"`
	CountryISO   string `json:"countryISO"`
	MCC          string `json:"mcc"`
	MNC          string `json:"mnc"`
	NetworkType  string `json:"networkType"` // "GSM", "CDMA", "LTE", "5G"
	Brand        string `json:"brand"`       // Full brand name
	APN          string `json:"apn"`         // Default APN
}

// ListResponse — paginated list
type ListResponse[T any] struct {
	Total int `json:"total"`
	Items []T `json:"items"`
}

// StatsResponse
type StatsResponse struct {
	Devices         int            `json:"devices"`
	Carriers        int            `json:"carriers"`
	DevicesByOS     map[string]int `json:"devicesByOS"`
	CarriersByCountry map[string]int `json:"carriersByCountry"`
}
