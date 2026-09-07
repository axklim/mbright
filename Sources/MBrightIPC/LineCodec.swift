import Foundation

/// One JSON document per line. Newlines never appear inside
/// `JSONEncoder` output (it escapes them), so a bare `\n` is a safe frame
/// delimiter.
public enum LineCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }
}

/// Accumulates socket reads and yields complete lines, without the newline.
public struct LineBuffer: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [Data] {
        pending.append(data)
        var lines: [Data] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            lines.append(pending.subdata(in: pending.startIndex..<newline))
            pending.removeSubrange(pending.startIndex...newline)
        }
        return lines
    }
}
