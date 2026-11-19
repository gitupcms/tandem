#!/bin/sh
# Checks that the debug socket host is in debug builds and absent from release builds. Exit 0 ok, 1 not.
# Run after `swift build` and `swift build -c release` in swift/ and samples/inventory/swift/.
cd "$(dirname "$0")/.." || exit 1
status=0
for bin in swift/.build/debug/TandemProbe samples/inventory/swift/.build/debug/InventoryCLI; do
  if [ ! -f "$bin" ]; then echo "missing $bin"; status=1
  elif ! nm "$bin" | grep -q SocketHost; then echo "debug $bin: SocketHost missing"; status=1; fi
done
for bin in swift/.build/release/TandemProbe samples/inventory/swift/.build/release/InventoryCLI; do
  if [ ! -f "$bin" ]; then echo "missing $bin"; status=1
  elif nm "$bin" | grep -q SocketHost || strings "$bin" | grep -q 'listening 127.0.0.1'; then echo "release $bin: SocketHost present"; status=1; fi
done
[ $status -eq 0 ] && echo "ok: socket host only in debug builds"
exit $status
