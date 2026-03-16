import Foundation
import UIKit

enum FileStorageError: LocalizedError {
    case documentsUnavailable
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .documentsUnavailable:
            return AppLanguage.current == .simplifiedChinese ? "无法访问本地存储。" : "Unable to access local storage."
        case .writeFailed:
            return AppLanguage.current == .simplifiedChinese ? "无法将图片保存到本地存储。" : "Unable to save image to local storage."
        }
    }
}

enum FileStorage {
    private static let imageDirectoryName = "MealCoachImages"

    private static var imageDirectoryURL: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent(imageDirectoryName, isDirectory: true)
    }

    static func saveJPEGData(_ data: Data, prefix: String) throws -> String {
        guard let directory = imageDirectoryURL else {
            throw FileStorageError.documentsUnavailable
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = "\(prefix)-\(UUID().uuidString).jpg"
        let destination = directory.appendingPathComponent(filename)

        do {
            try data.write(to: destination, options: [.atomic])
            return filename
        } catch {
            throw FileStorageError.writeFailed
        }
    }

    static func fileURL(for filename: String) -> URL? {
        imageDirectoryURL?.appendingPathComponent(filename)
    }

    static func loadImage(filename: String) -> UIImage? {
        guard
            let url = fileURL(for: filename),
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return UIImage(data: data)
    }

    static func deleteImage(filename: String) {
        guard let url = fileURL(for: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAllImages() {
        guard let directory = imageDirectoryURL else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
