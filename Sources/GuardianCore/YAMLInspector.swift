import Foundation
import Yams

public struct InspectedYAML: Equatable, Sendable {
    public let flattenedValues: [String: String]

    public init(flattenedValues: [String: String]) {
        self.flattenedValues = flattenedValues
    }
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
        try flatten(value: loaded, path: "", into: &flattened)
        return InspectedYAML(flattenedValues: flattened)
    }

    private static func flatten(value: Any, path: String, into result: inout [String: String]) throws {
        if let dictionary = value as? [String: Any] {
            if dictionary.isEmpty, !path.isEmpty { result[path] = "{}" }
            for key in dictionary.keys.sorted() {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                if let child = dictionary[key] {
                    try flatten(value: child, path: childPath, into: &result)
                }
            }
            return
        }

        if let dictionary = value as? [AnyHashable: Any] {
            if dictionary.isEmpty, !path.isEmpty { result[path] = "{}" }
            let pairs = try dictionary.map { key, value -> (String, Any) in
                guard let key = key as? String else {
                    throw YAMLInspectionError.unsupportedKey(String(describing: key))
                }
                return (key, value)
            }.sorted { $0.0 < $1.0 }
            for (key, child) in pairs {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                try flatten(value: child, path: childPath, into: &result)
            }
            return
        }

        if let array = value as? [Any] {
            if array.isEmpty, !path.isEmpty { result[path] = "[]" }
            for (index, child) in array.enumerated() {
                try flatten(value: child, path: "\(path)[\(index)]", into: &result)
            }
            return
        }

        if value is NSNull {
            result[path] = "null"
        } else if let string = value as? String {
            result[path] = string
        } else {
            result[path] = String(describing: value)
        }
    }
}
