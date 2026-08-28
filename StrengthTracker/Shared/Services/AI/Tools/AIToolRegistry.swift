import Foundation

/// Name → tool lookup for the agent loop.
@MainActor
public final class AIToolRegistry {
    private let toolsByName: [String: any AITool]

    public init(tools: [any AITool]) {
        var byName: [String: any AITool] = [:]
        for tool in tools {
            byName[tool.name] = tool
        }
        self.toolsByName = byName
    }

    public var definitions: [AIToolDefinition] {
        toolsByName.values.map(\.definition).sorted { $0.name < $1.name }
    }

    public var isEmpty: Bool { toolsByName.isEmpty }

    public func tool(named name: String) -> (any AITool)? {
        toolsByName[name]
    }

    // MARK: - Schema helpers shared by tool implementations

    /// `{"type": "string", "enum": [...raw values...]}` derived from a CaseIterable enum.
    public static func enumSchema<T: CaseIterable & RawRepresentable>(
        _ type: T.Type, description: String? = nil
    ) -> JSONValue where T.RawValue == String {
        var schema: [String: JSONValue] = [
            "type": .string("string"),
            "enum": .array(type.allCases.map { .string($0.rawValue) })
        ]
        if let description {
            schema["description"] = .string(description)
        }
        return .object(schema)
    }

    /// `{"type": "object", "properties": ..., "required": ...}`.
    public static func objectSchema(
        properties: [String: JSONValue], required: [String] = []
    ) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.sorted().map { .string($0) })
        ])
    }

    public static func stringSchema(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    public static func numberSchema(_ description: String) -> JSONValue {
        .object(["type": .string("number"), "description": .string(description)])
    }

    public static func integerSchema(_ description: String) -> JSONValue {
        .object(["type": .string("integer"), "description": .string(description)])
    }

    public static func boolSchema(_ description: String) -> JSONValue {
        .object(["type": .string("boolean"), "description": .string(description)])
    }

    public static func arraySchema(of items: JSONValue, description: String? = nil) -> JSONValue {
        var schema: [String: JSONValue] = ["type": .string("array"), "items": items]
        if let description {
            schema["description"] = .string(description)
        }
        return .object(schema)
    }
}
