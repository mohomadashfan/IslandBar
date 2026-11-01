import Foundation

/// Decodes JSON by first deep-merging it over the JSON form of a default value.
///
/// Objects merge key by key; any other value (arrays included) in the stored data replaces the
/// default. Keys absent from the stored data keep their defaults and unknown keys are ignored
/// by the decoder, so synthesized `Codable` conformances become forward and backward tolerant.
///
/// Only use this for types built from structs and raw-value enums. Enums with associated values
/// encode as single-key objects, and merging two different cases would produce an undecodable
/// object with both keys.
public enum JSONMerge {
    public static func decode<Value: Codable>(
        _ type: Value.Type, from data: Data, over defaults: Value
    ) throws -> Value {
        let base = try JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults))
        let stored = try JSONSerialization.jsonObject(with: data)
        let merged = merge(base, stored)
        let mergedData = try JSONSerialization.data(withJSONObject: merged)
        return try JSONDecoder().decode(Value.self, from: mergedData)
    }

    static func merge(_ base: Any, _ overlay: Any) -> Any {
        guard let baseObject = base as? [String: Any], let overlayObject = overlay as? [String: Any] else {
            return overlay
        }
        var result = baseObject
        for (key, value) in overlayObject {
            result[key] = baseObject[key].map { merge($0, value) } ?? value
        }
        return result
    }
}
