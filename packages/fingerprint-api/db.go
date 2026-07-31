package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"

	_ "github.com/mattn/go-sqlite3"
)

type DB struct {
	conn *sql.DB
}

func OpenDB(path string) (*DB, error) {
	conn, err := sql.Open("sqlite3", path+"?_journal_mode=WAL&_foreign_keys=on")
	if err != nil {
		return nil, fmt.Errorf("open: %w", err)
	}
	if err := conn.Ping(); err != nil {
		return nil, fmt.Errorf("ping: %w", err)
	}
	return &DB{conn: conn}, nil
}

func (db *DB) Close() error { return db.conn.Close() }

func (db *DB) Migrate() error {
	schema := `
	CREATE TABLE IF NOT EXISTS devices (
		id         INTEGER PRIMARY KEY AUTOINCREMENT,
		model      TEXT NOT NULL UNIQUE,
		marketing_name TEXT DEFAULT '',
		os         TEXT DEFAULT '',
		os_version TEXT DEFAULT '',
		cpu        TEXT DEFAULT '',
		cpu_cores  INTEGER DEFAULT 0,
		cpu_arch   TEXT DEFAULT '',
		cpu_features TEXT DEFAULT '[]',
		ram        INTEGER DEFAULT 0,
		storage    INTEGER DEFAULT 0,
		resolution TEXT DEFAULT '',
		width      INTEGER DEFAULT 0,
		height     INTEGER DEFAULT 0,
		dpi        INTEGER DEFAULT 0,
		scale      REAL DEFAULT 1.0,
		gpu        TEXT DEFAULT '',
		screen_size REAL DEFAULT 0,
		screen_type TEXT DEFAULT '',
		battery    INTEGER DEFAULT 0,
		sensors    TEXT DEFAULT '[]',
		build_id   TEXT DEFAULT '',
		fingerprint TEXT DEFAULT '',
		manufacturer TEXT DEFAULT '',
		brand      TEXT DEFAULT '',
		device     TEXT DEFAULT '',
		hardware   TEXT DEFAULT '',
		release_date TEXT DEFAULT '',
		source     TEXT DEFAULT 'real_device',
		created_at TEXT DEFAULT (datetime('now'))
	);

	CREATE TABLE IF NOT EXISTS carriers (
		id          INTEGER PRIMARY KEY AUTOINCREMENT,
		carrier_name TEXT NOT NULL,
		country     TEXT DEFAULT '',
		country_iso TEXT DEFAULT '',
		mcc         TEXT DEFAULT '',
		mnc         TEXT DEFAULT '',
		network_type TEXT DEFAULT 'GSM',
		brand       TEXT DEFAULT '',
		apn         TEXT DEFAULT '',
		created_at  TEXT DEFAULT (datetime('now')),
		UNIQUE(mcc, mnc)
	);

	CREATE INDEX IF NOT EXISTS idx_devices_model ON devices(model);
	CREATE INDEX IF NOT EXISTS idx_devices_os ON devices(os);
	CREATE INDEX IF NOT EXISTS idx_carriers_mcc ON carriers(mcc);
	CREATE INDEX IF NOT EXISTS idx_carriers_country ON carriers(country_iso);
	`
	_, err := db.conn.Exec(schema)
	return err
}

// ── Devices ──

func (db *DB) InsertDevice(d *Device) (int64, error) {
	r, err := db.conn.Exec(`INSERT OR REPLACE INTO devices
		(model, marketing_name, os, os_version, cpu, cpu_cores, cpu_arch, cpu_features,
		 ram, storage, resolution, width, height, dpi, scale, gpu, screen_size, screen_type,
		 battery, sensors, build_id, fingerprint, manufacturer, brand, device, hardware,
		 release_date, source)
		VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
		d.Model, d.MarketingName, d.OS, d.OSVersion, d.CPU, d.CPUCores, d.CPUArch, d.CPUFeatures,
		d.RAM, d.Storage, d.Resolution, d.Width, d.Height, d.DPI, d.Scale, d.GPU, d.ScreenSize, d.ScreenType,
		d.Battery, d.Sensors, d.BuildID, d.Fingerprint, d.Manufacturer, d.Brand, d.Device, d.Hardware,
		d.ReleaseDate, d.Source)
	if err != nil {
		return 0, err
	}
	return r.LastInsertId()
}

func (db *DB) ListDevices(q, osFilter string, offset, limit int) ([]Device, int, error) {
	where := []string{"1=1"}
	args := []any{}

	if q != "" {
		where = append(where, "(model LIKE ? OR marketing_name LIKE ? OR cpu LIKE ? OR manufacturer LIKE ?)")
		pattern := "%" + q + "%"
		args = append(args, pattern, pattern, pattern, pattern)
	}
	if osFilter != "" {
		where = append(where, "os = ?")
		args = append(args, osFilter)
	}

	clause := strings.Join(where, " AND ")

	var total int
	if err := db.conn.QueryRow("SELECT COUNT(*) FROM devices WHERE "+clause, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := db.conn.Query(
		`SELECT id,model,marketing_name,os,os_version,cpu,cpu_cores,cpu_arch,cpu_features,
		        ram,storage,resolution,width,height,dpi,scale,gpu,screen_size,screen_type,
		        battery,sensors,build_id,fingerprint,manufacturer,brand,device,hardware,
		        release_date,source
		 FROM devices WHERE `+clause+` ORDER BY id DESC LIMIT ? OFFSET ?`,
		append(args, limit, offset)...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var devices []Device
	for rows.Next() {
		var d Device
		if err := rows.Scan(&d.ID, &d.Model, &d.MarketingName, &d.OS, &d.OSVersion,
			&d.CPU, &d.CPUCores, &d.CPUArch, &d.CPUFeatures,
			&d.RAM, &d.Storage, &d.Resolution, &d.Width, &d.Height,
			&d.DPI, &d.Scale, &d.GPU, &d.ScreenSize, &d.ScreenType,
			&d.Battery, &d.Sensors, &d.BuildID, &d.Fingerprint,
			&d.Manufacturer, &d.Brand, &d.Device, &d.Hardware,
			&d.ReleaseDate, &d.Source); err != nil {
			return nil, 0, err
		}
		devices = append(devices, d)
	}
	return devices, total, nil
}

func (db *DB) GetDevice(id int64) (*Device, error) {
	var d Device
	err := db.conn.QueryRow(
		`SELECT id,model,marketing_name,os,os_version,cpu,cpu_cores,cpu_arch,cpu_features,
		        ram,storage,resolution,width,height,dpi,scale,gpu,screen_size,screen_type,
		        battery,sensors,build_id,fingerprint,manufacturer,brand,device,hardware,
		        release_date,source
		 FROM devices WHERE id = ?`, id).Scan(
		&d.ID, &d.Model, &d.MarketingName, &d.OS, &d.OSVersion,
		&d.CPU, &d.CPUCores, &d.CPUArch, &d.CPUFeatures,
		&d.RAM, &d.Storage, &d.Resolution, &d.Width, &d.Height,
		&d.DPI, &d.Scale, &d.GPU, &d.ScreenSize, &d.ScreenType,
		&d.Battery, &d.Sensors, &d.BuildID, &d.Fingerprint,
		&d.Manufacturer, &d.Brand, &d.Device, &d.Hardware,
		&d.ReleaseDate, &d.Source)
	if err != nil {
		return nil, err
	}
	return &d, nil
}

func (db *DB) GetDeviceByModel(model string) (*Device, error) {
	var d Device
	err := db.conn.QueryRow(
		`SELECT id,model,marketing_name,os,os_version,cpu,cpu_cores,cpu_arch,cpu_features,
		        ram,storage,resolution,width,height,dpi,scale,gpu,screen_size,screen_type,
		        battery,sensors,build_id,fingerprint,manufacturer,brand,device,hardware,
		        release_date,source
		 FROM devices WHERE model = ?`, model).Scan(
		&d.ID, &d.Model, &d.MarketingName, &d.OS, &d.OSVersion,
		&d.CPU, &d.CPUCores, &d.CPUArch, &d.CPUFeatures,
		&d.RAM, &d.Storage, &d.Resolution, &d.Width, &d.Height,
		&d.DPI, &d.Scale, &d.GPU, &d.ScreenSize, &d.ScreenType,
		&d.Battery, &d.Sensors, &d.BuildID, &d.Fingerprint,
		&d.Manufacturer, &d.Brand, &d.Device, &d.Hardware,
		&d.ReleaseDate, &d.Source)
	if err != nil {
		return nil, err
	}
	return &d, nil
}

// ── Carriers ──

func (db *DB) InsertCarrier(c *Carrier) (int64, error) {
	r, err := db.conn.Exec(`INSERT OR REPLACE INTO carriers
		(carrier_name, country, country_iso, mcc, mnc, network_type, brand, apn)
		VALUES (?,?,?,?,?,?,?,?)`,
		c.CarrierName, c.Country, c.CountryISO, c.MCC, c.MNC, c.NetworkType, c.Brand, c.APN)
	if err != nil {
		return 0, err
	}
	return r.LastInsertId()
}

func (db *DB) ListCarriers(q, countryISO string, offset, limit int) ([]Carrier, int, error) {
	where := []string{"1=1"}
	args := []any{}

	if q != "" {
		where = append(where, "(carrier_name LIKE ? OR country LIKE ? OR mcc LIKE ? OR mnc LIKE ?)")
		pattern := "%" + q + "%"
		args = append(args, pattern, pattern, pattern, pattern)
	}
	if countryISO != "" {
		where = append(where, "country_iso = ?")
		args = append(args, countryISO)
	}

	clause := strings.Join(where, " AND ")

	var total int
	if err := db.conn.QueryRow("SELECT COUNT(*) FROM carriers WHERE "+clause, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := db.conn.Query(
		`SELECT id,carrier_name,country,country_iso,mcc,mnc,network_type,brand,apn
		 FROM carriers WHERE `+clause+` ORDER BY country_iso, carrier_name LIMIT ? OFFSET ?`,
		append(args, limit, offset)...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var carriers []Carrier
	for rows.Next() {
		var c Carrier
		if err := rows.Scan(&c.ID, &c.CarrierName, &c.Country, &c.CountryISO,
			&c.MCC, &c.MNC, &c.NetworkType, &c.Brand, &c.APN); err != nil {
			return nil, 0, err
		}
		carriers = append(carriers, c)
	}
	return carriers, total, nil
}

func (db *DB) GetCarrier(id int64) (*Carrier, error) {
	var c Carrier
	err := db.conn.QueryRow(
		`SELECT id,carrier_name,country,country_iso,mcc,mnc,network_type,brand,apn
		 FROM carriers WHERE id = ?`, id).Scan(
		&c.ID, &c.CarrierName, &c.Country, &c.CountryISO,
		&c.MCC, &c.MNC, &c.NetworkType, &c.Brand, &c.APN)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

// ── Stats ──

func (db *DB) Stats() (*StatsResponse, error) {
	s := &StatsResponse{
		DevicesByOS:       make(map[string]int),
		CarriersByCountry: make(map[string]int),
	}
	db.conn.QueryRow("SELECT COUNT(*) FROM devices").Scan(&s.Devices)
	db.conn.QueryRow("SELECT COUNT(*) FROM carriers").Scan(&s.Carriers)

	rows, _ := db.conn.Query("SELECT os, COUNT(*) FROM devices GROUP BY os")
	if rows != nil {
		defer rows.Close()
		for rows.Next() {
			var os string; var c int
			rows.Scan(&os, &c)
			s.DevicesByOS[os] = c
		}
	}

	rows2, _ := db.conn.Query("SELECT country_iso, COUNT(*) FROM carriers GROUP BY country_iso ORDER BY COUNT(*) DESC LIMIT 20")
	if rows2 != nil {
		defer rows2.Close()
		for rows2.Next() {
			var iso string; var c int
			rows2.Scan(&iso, &c)
			s.CarriersByCountry[iso] = c
		}
	}
	return s, nil
}

// ── Batch Seed ──

func (db *DB) SeedDevices(devices []Device) (int, error) {
	count := 0
	for _, d := range devices {
		_, err := db.InsertDevice(&d)
		if err != nil {
			return count, fmt.Errorf("%s: %w", d.Model, err)
		}
		count++
	}
	return count, nil
}

func (db *DB) SeedCarriers(carriers []Carrier) (int, error) {
	count := 0
	for _, c := range carriers {
		_, err := db.InsertCarrier(&c)
		if err != nil {
			return count, fmt.Errorf("%s/%s/%s: %w", c.CountryISO, c.MCC, c.MNC, err)
		}
		count++
	}
	return count, nil
}

// Unused imports guard
var _ = json.Marshal
