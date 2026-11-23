import CoreImage
import Foundation

enum DownloadQR {
    static let placeholder = "https://hgsldswk-alt.github.io/unitprice-support/"

    static func target(appStoreID: String?) -> String {
        guard let id = appStoreID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
              id.utf8.allSatisfy({ (48...57).contains($0) }) else { return placeholder }
        return "https://apps.apple.com/app/id\(id)"
    }

    static func image(for link: String, scale: Int = 8) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator"), (1...32).contains(scale) else { return nil }
        filter.setValue(Data(link.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let result = filter.outputImage else { return nil }
        let scaled = result.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        return CIContext(options: [.useSoftwareRenderer: true]).createCGImage(scaled, from: scaled.extent)
    }
}
