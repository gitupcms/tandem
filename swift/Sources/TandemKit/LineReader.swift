/// Framing shared by every transport: LF ends a line, a CR right before the LF is dropped,
/// and bytes after the last LF count as one more line at end of input.
public struct LineReader {
    var line: [UInt8] = []

    public init() {}

    public mutating func feed<S: Sequence>(_ bytes: S, _ emit: ([UInt8]) -> Void) where S.Element == UInt8 {
        for byte in bytes {
            if byte == 0x0A {
                flush(emit)
            } else {
                // Stop buffering past limit + CR + 1: the line is already too long, even after a CR is dropped.
                if line.count < Session.maxLine + 2 { line.append(byte) }
            }
        }
    }

    /// End of input: answer what is left after the last LF.
    public mutating func finish(_ emit: ([UInt8]) -> Void) {
        if !line.isEmpty { flush(emit) }
    }

    private mutating func flush(_ emit: ([UInt8]) -> Void) {
        // A CR is part of the line ending only when it sits right before the LF.
        if line.last == 0x0D { line.removeLast() }
        emit(line)
        line = []
    }
}
