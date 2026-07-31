package main

import (
	"log"
	"os"
)

func main() {
	dbPath := os.Getenv("DB_PATH")
	if dbPath == "" {
		dbPath = "fingerprints.db"
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "15557"
	}

	db, err := OpenDB(dbPath)
	if err != nil {
		log.Fatalf("DB: %v", err)
	}
	defer db.Close()

	if err := db.Migrate(); err != nil {
		log.Fatalf("Migrate: %v", err)
	}

	srv := NewServer(db)
	log.Printf("fingerprint-api listening on :%s", port)
	if err := srv.ListenAndServe(":" + port); err != nil {
		log.Fatalf("Server: %v", err)
	}
}
