//go:build !windows && !darwin
// +build !windows,!darwin

package main

import (
	"log"
)

func main() {
	log.SetFlags(0)
	if err := startServer(); err != nil {
		log.Fatal(err)
	}
	log.Printf("Manager-Agent v%s running on port %d (headless)", version, listenPort)

	// Block forever
	select {}
}
