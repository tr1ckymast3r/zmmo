// syscall.c — system() wrapper for iOS cross-compile
// iOS SDK marks system() unavailable, so we declare it ourselves
// system() exists at runtime (it's in libSystem), just not in SDK headers

// Must NOT include <stdlib.h> — it has the unavailable annotation
// Declare system() manually
extern int system(const char *command);

int zmmo_system(const char *cmd) {
    if (!cmd) return -1;
    return system(cmd);
}
