#!/usr/bin/env bash
# Checks that release distributions carry no socket host and debug ones do (spec "Transport").
# Run after: gradlew installDist installDebugDist (for kotlin/ and, if present, samples/inventory/kotlin/).
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

has_socket() { # lib dir -> 0 if tandem-socket jar or SocketHost class is present
  ls "$1"/tandem-socket*.jar >/dev/null 2>&1 && return 0
  for j in "$1"/*.jar; do unzip -Z1 "$j" 2>/dev/null | grep -q 'tandem/socket/SocketHost' && return 0; done
  return 1
}

check() { # release lib, debug lib
  if [ ! -d "$1" ] || [ ! -d "$2" ]; then echo "missing: $1 or $2"; fail=1; return; fi
  if has_socket "$1"; then echo "FAIL release has socket host: $1"; fail=1; else echo "ok   release clean: $1"; fi
  if has_socket "$2"; then echo "ok   debug has socket host: $2"; else echo "FAIL debug lacks socket host: $2"; fail=1; fi
}

check "$root/kotlin/probe-host/build/install/probe-host/lib" "$root/kotlin/probe-host/build/install/probe-host-debug/lib"
inv="$root/samples/inventory/kotlin/cli/build/install"
[ -d "$inv/cli" ] && check "$inv/cli/lib" "$inv/cli-debug/lib"
exit $fail
