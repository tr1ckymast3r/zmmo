package main

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
)

type Server struct {
	db  *DB
	mux *http.ServeMux
}

func NewServer(db *DB) *Server {
	s := &Server{db: db, mux: http.NewServeMux()}
	s.registerRoutes()
	return s
}

func (s *Server) ListenAndServe(addr string) error {
	return http.ListenAndServe(addr, corsMiddleware(s.mux))
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type,Authorization")
		w.Header().Set("Content-Type", "application/json")
		if r.Method == "OPTIONS" {
			w.WriteHeader(204)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) registerRoutes() {
	// Devices
	s.mux.HandleFunc("/api/v1/devices", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case "GET":
			s.handleListDevices(w, r)
		case "POST":
			s.handleCreateDevice(w, r)
		default:
			http.Error(w, `{"error":"method not allowed"}`, 405)
		}
	})
	s.mux.HandleFunc("/api/v1/devices/", func(w http.ResponseWriter, r *http.Request) {
		s.handleDeviceByPath(w, r)
	})

	// Carriers
	s.mux.HandleFunc("/api/v1/carriers", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case "GET":
			s.handleListCarriers(w, r)
		case "POST":
			s.handleCreateCarrier(w, r)
		default:
			http.Error(w, `{"error":"method not allowed"}`, 405)
		}
	})
	s.mux.HandleFunc("/api/v1/carriers/", func(w http.ResponseWriter, r *http.Request) {
		s.handleCarrierByPath(w, r)
	})

	// Stats
	s.mux.HandleFunc("/api/v1/stats", s.handleStats)

	// Seed (one-time bootstrap)
	s.mux.HandleFunc("/api/v1/seed", s.handleSeed)

	// Health
	s.mux.HandleFunc("/api/v1/health", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	})
}

// ── Device handlers ──

func (s *Server) handleListDevices(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	offset, _ := strconv.Atoi(q.Get("offset"))
	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 || limit > 200 {
		limit = 50
	}

	devices, total, err := s.db.ListDevices(q.Get("q"), q.Get("os"), offset, limit)
	if err != nil {
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		w.WriteHeader(500)
		return
	}
	if devices == nil {
		devices = []Device{}
	}
	json.NewEncoder(w).Encode(ListResponse[Device]{Total: total, Items: devices})
}

func (s *Server) handleCreateDevice(w http.ResponseWriter, r *http.Request) {
	var d Device
	if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		w.WriteHeader(400)
		return
	}
	id, err := s.db.InsertDevice(&d)
	if err != nil {
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		w.WriteHeader(500)
		return
	}
	d.ID = id
	w.WriteHeader(201)
	json.NewEncoder(w).Encode(d)
}

func (s *Server) handleDeviceByPath(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/v1/devices/")

	if path == "model" {
		// GET /api/v1/devices/model/:model
		s.handleGetDeviceByModel(w, r)
		return
	}

	id, err := strconv.ParseInt(path, 10, 64)
	if err != nil {
		http.Error(w, `{"error":"invalid id"}`, 400)
		return
	}
	switch r.Method {
	case "GET":
		d, err := s.db.GetDevice(id)
		if err != nil {
			json.NewEncoder(w).Encode(map[string]string{"error": "not found"})
			w.WriteHeader(404)
			return
		}
		json.NewEncoder(w).Encode(d)
	default:
		http.Error(w, `{"error":"method not allowed"}`, 405)
	}
}

func (s *Server) handleGetDeviceByModel(w http.ResponseWriter, r *http.Request) {
	model := strings.TrimPrefix(r.URL.Path, "/api/v1/devices/model/")
	if model == "" {
		http.Error(w, `{"error":"model required"}`, 400)
		return
	}
	d, err := s.db.GetDeviceByModel(model)
	if err != nil {
		json.NewEncoder(w).Encode(map[string]string{"error": "not found"})
		w.WriteHeader(404)
		return
	}
	json.NewEncoder(w).Encode(d)
}

// ── Carrier handlers ──

func (s *Server) handleListCarriers(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	offset, _ := strconv.Atoi(q.Get("offset"))
	limit, _ := strconv.Atoi(q.Get("limit"))
	if limit <= 0 || limit > 1000 {
		limit = 200
	}

	carriers, total, err := s.db.ListCarriers(q.Get("q"), q.Get("country"), offset, limit)
	if err != nil {
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		w.WriteHeader(500)
		return
	}
	if carriers == nil {
		carriers = []Carrier{}
	}
	json.NewEncoder(w).Encode(ListResponse[Carrier]{Total: total, Items: carriers})
}

func (s *Server) handleCreateCarrier(w http.ResponseWriter, r *http.Request) {
	var c Carrier
	if err := json.NewDecoder(r.Body).Decode(&c); err != nil {
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		w.WriteHeader(400)
		return
	}
	id, err := s.db.InsertCarrier(&c)
	if err != nil {
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		w.WriteHeader(500)
		return
	}
	c.ID = id
	w.WriteHeader(201)
	json.NewEncoder(w).Encode(c)
}

func (s *Server) handleCarrierByPath(w http.ResponseWriter, r *http.Request) {
	idStr := strings.TrimPrefix(r.URL.Path, "/api/v1/carriers/")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		http.Error(w, `{"error":"invalid id"}`, 400)
		return
	}
	switch r.Method {
	case "GET":
		c, err := s.db.GetCarrier(id)
		if err != nil {
			json.NewEncoder(w).Encode(map[string]string{"error": "not found"})
			w.WriteHeader(404)
			return
		}
		json.NewEncoder(w).Encode(c)
	default:
		http.Error(w, `{"error":"method not allowed"}`, 405)
	}
}

// ── Stats ──

func (s *Server) handleStats(w http.ResponseWriter, r *http.Request) {
	st, err := s.db.Stats()
	if err != nil {
		json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
		w.WriteHeader(500)
		return
	}
	json.NewEncoder(w).Encode(st)
}

// ── Seed ──

func (s *Server) handleSeed(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, `{"error":"POST required"}`, 405)
		return
	}

	devices, err := LoadDeviceSeeds()
	if err != nil {
		json.NewEncoder(w).Encode(map[string]string{"error": "load devices: " + err.Error()})
		w.WriteHeader(500)
		return
	}

	carriers, err := LoadCarrierSeeds()
	if err != nil {
		json.NewEncoder(w).Encode(map[string]string{"error": "load carriers: " + err.Error()})
		w.WriteHeader(500)
		return
	}

	dCount, _ := s.db.SeedDevices(devices)
	cCount, _ := s.db.SeedCarriers(carriers)

	json.NewEncoder(w).Encode(map[string]int{
		"devices_seeded":  dCount,
		"carriers_seeded": cCount,
	})
}
