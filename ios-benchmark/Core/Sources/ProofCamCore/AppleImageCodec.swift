#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum AppleImageCodec {
public static func decode(_ data: Data) throws -> RGBImage {
    guard data.count <= 25*1024*1024,
          let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
          let type = CGImageSourceGetType(source) as String?, ["public.jpeg", "public.png"].contains(type),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, width <= 16384, height <= 16384, width*height <= 20_000_000,
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width,height)] as CFDictionary)
    else { throw ResearchError.invalidDimensions }
    var bytes = [UInt8](repeating: 0, count: image.width*image.height*4)
    let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))); return true
    }
    guard rendered else { throw ResearchError.invalidDimensions }
    let pixels: [UInt32] = stride(from: 0, to: bytes.count, by: 4).map { offset in
        let alpha = UInt32(bytes[offset + 3]) << 24
        let red = UInt32(bytes[offset]) << 16
        let green = UInt32(bytes[offset + 1]) << 8
        let blue = UInt32(bytes[offset + 2])
        return alpha | red | green | blue
    }
    return try RGBImage(width: image.width, height: image.height, pixels: pixels)
}
public static func jpeg(_ image: RGBImage) throws -> Data {
    var bytes = [UInt8](); bytes.reserveCapacity(image.pixels.count*4)
    for p in image.pixels { bytes += [UInt8((p>>16)&255), UInt8((p>>8)&255), UInt8(p&255),255] }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let cg = CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: image.width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { throw ResearchError.invalidDimensions }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw ResearchError.invalidDimensions }
    CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw ResearchError.invalidDimensions }
    return output as Data
}
}
#endif
