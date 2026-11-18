# Network guard

`tandem_guard.c` is a preload shim that refuses non-loopback network calls from a host process and logs them. Contract: AF_INET/AF_INET6 `connect`, `sendto` and `sendmsg` to anything outside 127.0.0.0/8 and ::1 fail with `ECONNREFUSED`; AF_UNIX and loopback pass.

```sh
bun run build:guard   # guard/build/libtandemguard.so (Linux) or .dylib (macOS)
TANDEM_GUARD_LOG=/tmp/guard.log LD_PRELOAD=$PWD/guard/build/libtandemguard.so <host>              # Linux
TANDEM_GUARD_LOG=/tmp/guard.log DYLD_INSERT_LIBRARIES=$PWD/guard/build/libtandemguard.dylib <host> # macOS
```

Log lines (to `TANDEM_GUARD_LOG`, or stderr when unset): `loaded <pid>` when the library loads in a process (child processes that inherit the variable add their own), and `denied <ipv4|ipv6> <address> <port>` per refused call. No `loaded` line means the guard is not active.

This is not a security boundary. It catches accidental network use by ordinary dynamically linked code. Statically linked binaries, code that issues syscalls directly, and processes that clear `LD_PRELOAD`/`DYLD_INSERT_LIBRARIES` (or SIP-protected binaries on macOS, which drop it) bypass it.

Test: `bun test guard` (compiles `canary.c`; the Swift and Kotlin probe host checks run only when those hosts are built).
