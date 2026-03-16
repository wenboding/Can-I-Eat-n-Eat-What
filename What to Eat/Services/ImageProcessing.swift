import Foundation
import UIKit

enum ImageProcessingError: LocalizedError {
    case loadFailed
    case invalidImage
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed:
            return AppLanguage.current == .simplifiedChinese ? "无法加载所选图片。" : "Unable to load selected image."
        case .invalidImage:
            return AppLanguage.current == .simplifiedChinese ? "所选文件不是有效图片。" : "The selected file is not a valid image."
        case .encodeFailed:
            return AppLanguage.current == .simplifiedChinese ? "无法处理图片用于上传。" : "Unable to process image for upload."
        }
    }
}

struct ProcessedImage {
    let image: UIImage
    let jpegData: Data
    let dataURL: String
}

enum ImageProcessing {
    static let maxDataURIItemBytes = 10 * 1024 * 1024
    private static let dataURLPrefix = "data:image/jpeg;base64,"

    enum UploadProfile {
        case mealPhoto
        case healthReport

        var maxDimension: CGFloat {
            switch self {
            case .mealPhoto:
                return 3840
            case .healthReport:
                return 3840
            }
        }

        var minimumDimension: CGFloat {
            switch self {
            case .mealPhoto:
                return 1280
            case .healthReport:
                return 2048
            }
        }

        var compressionQualities: [CGFloat] {
            [0.8, 0.7, 0.6, 0.5, 0.4, 0.3]
        }
    }

    static func processImageData(_ rawData: Data, profile: UploadProfile) throws -> ProcessedImage {
        guard let image = UIImage(data: rawData) else {
            throw ImageProcessingError.invalidImage
        }

        let candidateDimensions = uploadDimensions(
            maxDimension: profile.maxDimension,
            minimumDimension: profile.minimumDimension
        )

        for maxDimension in candidateDimensions {
            let resized = resizedImage(image, maxDimension: maxDimension)
            for compressionQuality in profile.compressionQualities {
                guard let candidateJPEGData = resized.jpegData(compressionQuality: compressionQuality) else {
                    continue
                }

                guard isWithinDataURIItemLimit(jpegData: candidateJPEGData) else {
                    continue
                }

                return ProcessedImage(
                    image: resized,
                    jpegData: candidateJPEGData,
                    dataURL: dataURL(forJPEGData: candidateJPEGData)
                )
            }
        }

        throw ImageProcessingError.encodeFailed
    }

    static func resizedImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)

        guard longestSide > maxDimension else {
            return image
        }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    static func jpegData(from image: UIImage, maxDimension: CGFloat, compressionQuality: CGFloat) -> Data? {
        let resized = resizedImage(image, maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: compressionQuality)
    }

    static func dataURL(forJPEGData data: Data) -> String {
        "\(dataURLPrefix)\(data.base64EncodedString())"
    }

    static func isWithinDataURIItemLimit(jpegData: Data) -> Bool {
        let base64Length = ((jpegData.count + 2) / 3) * 4
        let totalLength = dataURLPrefix.utf8.count + base64Length
        return totalLength <= maxDataURIItemBytes
    }

    private static func uploadDimensions(maxDimension: CGFloat, minimumDimension: CGFloat) -> [CGFloat] {
        guard maxDimension > minimumDimension else { return [maxDimension] }

        var dimensions: [CGFloat] = []
        var current = maxDimension

        while current > minimumDimension {
            dimensions.append(current)
            current *= 0.85
        }

        dimensions.append(minimumDimension)
        return dimensions
    }
}
