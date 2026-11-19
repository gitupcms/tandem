#if DEBUG
#if canImport(Glibc)
import Glibc
private let streamType = Int32(SOCK_STREAM.rawValue)
#elseif canImport(Darwin)
import Darwin
private let streamType = SOCK_STREAM
#endif

/// In-app transport for debug builds: the same lines over a loopback TCP socket.
/// One connection at a time, each with a fresh Session on the same app; exits 0 when stdin ends.
enum SocketHost {
    static func run(port: UInt16, _ makeSession: () -> Session) -> Never {
        signal(SIGPIPE, SIG_IGN) // a client that hangs up must not kill the host
        let server = listenLoopback(port)
        logErr("listening 127.0.0.1:\(boundPort(server))")

        var conn: Int32 = -1
        var session: Session? = nil
        var reader = LineReader()
        var buf = [UInt8](repeating: 0, count: 64 * 1024)

        func endConnection() {
            close(conn)
            conn = -1
            session = nil
        }

        while true {
            // While a connection is served, the listening socket is not polled: later clients wait in the backlog.
            var fds = [pollfd(fd: 0, events: Int16(POLLIN), revents: 0),
                       pollfd(fd: conn >= 0 ? conn : server, events: Int16(POLLIN), revents: 0)]
            if poll(&fds, 2, -1) < 0 {
                if errno == EINTR { continue }
                die("poll")
            }
            if fds[0].revents != 0 {
                let n = read(0, &buf, buf.count)
                if n <= 0 && !(n < 0 && errno == EINTR) { exit(0) } // stdin input itself is ignored
            }
            guard fds[1].revents != 0 else { continue }
            if conn < 0 {
                let c = accept(server, nil, nil)
                if c < 0 { continue }
                conn = c
                session = makeSession()
                reader = LineReader()
                continue
            }
            let n = read(conn, &buf, buf.count)
            if n < 0 {
                if errno == EINTR { continue }
                endConnection()
                continue
            }
            var alive = true
            let answer = { (line: [UInt8]) in
                if alive { alive = writeAll(conn, Array((session!.respond(line) + "\n").utf8)) }
            }
            if n == 0 {
                // EOF or half-close: answer the bytes after the last LF, then close and keep listening.
                reader.finish(answer)
                endConnection()
            } else {
                reader.feed(buf[0..<n], answer)
                if !alive { endConnection() }
            }
        }
    }

    private static func listenLoopback(_ port: UInt16) -> Int32 {
        let fd = socket(AF_INET, streamType, 0)
        if fd < 0 { die("socket") }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: UInt32(0x7F00_0001).bigEndian)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if bound < 0 { die("bind 127.0.0.1:\(port)") }
        if listen(fd, 16) < 0 { die("listen") }
        return fd
    }

    private static func boundPort(_ fd: Int32) -> UInt16 {
        var addr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        if ok < 0 { die("getsockname") }
        return UInt16(bigEndian: addr.sin_port)
    }

    private static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var off = 0
        while off < bytes.count {
            let n = bytes[off...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                return false
            }
            off += n
        }
        return true
    }

    private static func logErr(_ s: String) {
        let bytes = Array((s + "\n").utf8)
        _ = writeAll(2, bytes)
    }

    private static func die(_ what: String) -> Never {
        logErr("\(what): \(String(cString: strerror(errno)))")
        exit(1)
    }
}
#endif
