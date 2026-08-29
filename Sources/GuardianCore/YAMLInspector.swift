import Foundation
import Yams

public struct InspectedYAML: Equatable, Sendable {
    public let flattenedValues: [String: String]
    public let flattenedKinds: [String: YAMLValueKind]

    public init(flattenedValues: [String: String], flattenedKinds: [String: YAMLValueKind]) {
        self.flattenedValues = flattenedValues
        self.flattenedKinds = flattenedKinds
    }
}

public enum YAMLValueKind: String, Codable, Equatable, Sendable {
    case string
    case integer
    case number
    case boolean
    case null
    case sequence
    case mapping

    public var displayName: String { rawValue }
}

public enum YAMLInspectionError: LocalizedError {
    case invalidUTF8
    case emptyDocument
    case rootIsNotMapping
    case unsupportedKey(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "The file is not valid UTF-8 text."
        case .emptyDocument:
            return "The YAML document is empty."
        case .rootIsNotMapping:
            return "Hermes configuration must be a YAML mapping at the top level."
        case let .unsupportedKey(key):
            return "The YAML contains a non-text key: \(key)."
        }
    }
}

public enum YAMLInspector {
    public static func inspect(data: Data) throws -> InspectedYAML {
        guard let text = String(data: data, encoding: .utf8) else {
            throw YAMLInspectionError.invalidUTF8
        }
        let loaded = try Yams.load(yaml: text)
        guard let loaded else { throw YAMLInspectionError.emptyDocument }
        guard loaded is [String: Any] || loaded is [AnyHashable: Any] else {
            throw YAMLInspectionError.rootIsNotMapping
        }

        var flattened: [String: String] = [:]
        var kinds: [String: YAMLValueKind] = [:]
        try flatten(value: loaded, path: "", values: &flattened, kinds: &kinds)
        return InspectedYAML(flattenedValues: flattened, flattenedKinds: kinds)
    }

    private static func flatten(
        value: Any,
        path: String,
        values result: inout [String: String],
        kinds: inout [String: YAMLValueKind]
    ) throws {
        if let dictionary = value as? [String: Any] {
            if dictionary.isEmpty, !path.isEmpty {
                result[path] = "{}"
                kinds[path] = .mapping
            }
            for key in dictionary.keys.sorted() {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                if let child = dictionary[key] {
                    try flatten(value: child, path: childPath, values: &result, kinds: &kinds)
                }
            }
            return
        }

        if let dictionary = value as? [AnyHashable: Any] {
            if dictionary.isEmpty, !path.isEmpty {
                result[path] = "{}"
                kinds[path] = .mapping
            }
            let pairs = try dictionary.map { key, value -> (String, Any) in
                guard let key = key as? String else {
                    throw YAMLInspectionError.unsupportedKey(String(describing: key))
                }
                return (key, value)
            }.sorted { $0.0 < $1.0 }
            for (key, child) in pairs {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                try flatten(value: child, path: childPath, values: &result, kinds: &kinds)
            }
            return
        }

        if let array = value as? [Any] {
            if array.isEmpty, !path.isEmpty {
                result[path] = "[]"
                kinds[path] = .sequence
            }
            for (index, child) in array.enumerated() {
                try flatten(value: child, path: "\(path)[\(index)]", values: &result, kinds: &kinds)
            }
            return
        }

        if value is NSNull {
            result[path] = "null"
            kinds[path] = .null
        } else if let string = value as? String {
            result[path] = string
            kinds[path] = .string
        } else if let boolean = value as? Bool {
            result[path] = String(describing: boolean)
            kinds[path] = .boolean
        } else if value is Int || value is Int8 || value is Int16 || value is Int32 || value is Int64
                    || value is UInt || value is UInt8 || value is UInt16 || value is UInt32 || value is UInt64 {
            result[path] = String(describing: value)
            kinds[path] = .integer
        } else if value is Float || value is Double || value is Decimal {
            result[path] = String(describing: value)
            kinds[path] = .number
        } else {
            result[path] = String(describing: value)
            kinds[path] = .string
        }
    }
}
