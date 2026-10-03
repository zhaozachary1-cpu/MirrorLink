import CoreImage
import Foundation

enum WirelessQRCode {
    static func image(for session: WirelessQRSession) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(session.payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let code = filter.outputImage else { return nil }
        // Integer scaling keeps edges sharp. The view adds the white quiet zone.
        let scaled = code.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
