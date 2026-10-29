import Foundation

/// Any JSON value. Requests and results cross the engine boundary as JSON (API.md, "Envelope").
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        get {
            if case .object(let o) = self { return o[key] }
            return nil
        }
        set {
            guard case .object(var o) = self else { return }
            o[key] = newValue
            self = .object(o)
        }
    }

    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var double: Double? { if case .number(let n) = self { return n }; return nil }
    public var int: Int? { double.map { Int($0) } }
    public var int64: Int64? { double.map { Int64($0) } }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }

    // MARK: Text form

    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONValue(any: any)
    }

    public init(any: Any) throws {
        switch any {
        case is NSNull: self = .null
        case let n as NSNumber:
            // JSONSerialization gives booleans as NSNumber too; tell them apart by type.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(try a.map { try JSONValue(any: $0) })
        case let o as [String: Any]: self = .object(try o.mapValues { try JSONValue(any: $0) })
        default: throw RavenError.badResponse("not a JSON value: \(type(of: any))")
        }
    }

    var foundation: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n):
            if n.rounded() == n, abs(n) < 9.0e15 { return Int64(n) }
            return n
        case .string(let s): return s
        case .array(let a): return a.map { $0.foundation }
        case .object(let o): return o.mapValues { $0.foundation }
        }
    }

    /// Compact JSON with sorted keys.
    public func text() -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: foundation, options: [.sortedKeys, .fragmentsAllowed]),
              let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }

    // MARK: Codable bridges (snake_case on the wire, camelCase in Swift)

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: foundation, options: [.fragmentsAllowed])
        do {
            return try JSONValue.decoder.decode(T.self, from: data)
        } catch {
            throw RavenError.badResponse("decode \(T.self): \(error)")
        }
    }

    public static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try encoder.encode(value)
        return try parse(data)
    }

    /// Every string leaf cleaned with `Sanitizer.text` (newlines kept). Keys are left alone.
    public func sanitized() -> JSONValue {
        switch self {
        case .string(let s): return .string(Sanitizer.text(s))
        case .array(let a): return .array(a.map { $0.sanitized() })
        case .object(let o): return .object(o.mapValues { $0.sanitized() })
        default: return self
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue {
    public static func int(_ v: Int64) -> JSONValue { .number(Double(v)) }
    public static func int(_ v: Int) -> JSONValue { .number(Double(v)) }
    public static func opt(_ s: String?) -> JSONValue { s.map { .string($0) } ?? .null }
}
