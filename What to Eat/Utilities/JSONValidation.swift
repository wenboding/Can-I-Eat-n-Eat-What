import Foundation

enum JSONValidation {
    static func cleanedJSONString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("```") else {
            return trimmed
        }

        var cleaned = trimmed
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst("```json".count))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }

        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidJSON(string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
