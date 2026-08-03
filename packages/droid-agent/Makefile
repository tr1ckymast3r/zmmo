# droid-agent Makefile
REV    ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "dev")
LDFLAGS = -ldflags="-s -w -X main.Revision=$(REV)"

.PHONY: all android-arm64 android-arm linux windows clean

all: android-arm64

android-arm64:
	GOOS=android GOARCH=arm64 CGO_ENABLED=0 go build $(LDFLAGS) -o droid-agent-arm64 .

android-arm:
	GOOS=android GOARCH=arm GOARM=7 CGO_ENABLED=1 go build $(LDFLAGS) -o droid-agent-arm .

linux:
	GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o droid-agent-linux .

windows:
	GOOS=windows GOARCH=amd64 go build $(LDFLAGS) -o droid-agent.exe .

clean:
	rm -f droid-agent droid-agent-arm64 droid-agent-arm droid-agent-linux droid-agent.exe
