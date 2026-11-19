import Foundation

/// Headless transport: stdin lines in, response lines out on stdout, until EOF.
public enum StdioHost {
    public static func run(_ session: Session) {
        let out = FileHandle.standardOutput
        var reader = LineReader()
        let answer = { (line: [UInt8]) in out.write(Data((session.respond(line) + "\n").utf8)) }

        while case let chunk = FileHandle.standardInput.availableData, !chunk.isEmpty {
            reader.feed(chunk, answer)
        }
        reader.finish(answer)
    }
}
