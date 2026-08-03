// zmmo-gzip — tiny static gzip pipe for Android
// Reads stdin, writes gzip to stdout. < 2MB binary.
package main

import (
	"compress/gzip"
	"io"
	"os"
)

func main() {
	w := gzip.NewWriter(os.Stdout)
	io.Copy(w, os.Stdin)
	w.Close()
}
