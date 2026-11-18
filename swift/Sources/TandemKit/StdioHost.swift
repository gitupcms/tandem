import Foundation

/// Headless transport: stdin lines in, response lines out on stdout, until EOF.
public enum StdioHost {
    public static func run(_ session: Session) {
        let out = FileHandle.standardOutput
        var line: [UInt8] = []

        func answer() {
            // A CR is part of the line ending only when it sits right before the LF.
            if line.last == 0x0D { line.removeLast() }
            out.write(Data((session.respond(line) + "\n").utf8))
            line = []
        }

        while case let chunk = FileHandle.standardInput.availableData, !chunk.isEmpty {
            for byte in chunk {
                if byte == 0x0A {
                    answer()
                } else {
                    // Stop buffering past limit + CR + 1: the line is already too long, even after a CR is dropped.
                    if line.count < Session.maxLine + 2 { line.append(byte) }
                }
            }
        }
        if !line.isEmpty { answer() }
    }
}
