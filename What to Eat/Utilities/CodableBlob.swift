import Foundation

enum CodableBlob {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? encoder.encode(value)
    }

    static func decode<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}
