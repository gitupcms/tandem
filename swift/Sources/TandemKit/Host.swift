import Foundation

/// Picks the transport from the arguments after the fixture name: none for stdio, `--socket <port>` for the debug socket.
public enum Host {
    public static func run(_ options: ArraySlice<String>, _ makeSession: () -> Session) -> Never {
        func fail(_ message: String) -> Never {
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(64)
        }
        let opts = Array(options)
        if opts.isEmpty {
            StdioHost.run(makeSession())
            exit(0)
        }
        guard opts.count == 2, opts[0] == "--socket" else { fail("usage: <fixture> [--socket <port>]") }
        #if DEBUG
        guard let port = UInt16(opts[1]) else { fail("bad port: \(opts[1])") }
        SocketHost.run(port: port, makeSession)
        #else
        fail("--socket is not available in a release build")
        #endif
    }
}
