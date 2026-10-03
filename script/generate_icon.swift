import CoreGraphics
import Darwin
import Foundation
import ImageIO

struct IconArguments {
    let outputPath: String
}

func parseArguments() -> IconArguments {
    var outputPath: String?
    var arguments = CommandLine.arguments.dropFirst().makeIterator()

    while let argument = arguments.next() {
        switch argument {
        case "--output":
            outputPath = arguments.next()
        case "-h", "--help":
            print("用法：swift script/generate_icon.swift --output <png-path>")
            exit(0)
        default:
            fputs("未知参数：\(argument)\n", stderr)
            exit(2)
        }
    }

    guard let outputPath, !outputPath.isEmpty else {
        fputs("缺少 --output <png-path>。\n", stderr)
        exit(2)
    }

    return IconArguments(outputPath: outputPath)
}

let arguments = parseArguments()
let canvasSize = 1024
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: canvasSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    fputs("无法创建图标绘图上下文。\n", stderr)
    exit(1)
}

context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, 1])!
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func stroke(_ path: CGPath, color: CGColor, width: CGFloat) {
    context.saveGState()
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(path)
    context.strokePath()
    context.restoreGState()
}

// One brand color, one white glyph. Transparent margins keep the icon aligned
// with neighboring macOS icons without baking in shadows or an exterior backdrop.
let blue = color(37 / 255, 99 / 255, 235 / 255)
let white = color(1, 1, 1)
context.setFillColor(blue)
context.addPath(roundedPath(CGRect(x: 88, y: 88, width: 848, height: 848), radius: 190))
context.fillPath()

// A landscape display and an overlapping portrait phone are the entire mark.
// The shared weight is intentionally bold enough to survive the 16px variant.
let lineWidth: CGFloat = 52
// Leave a deliberate opening behind the phone rather than subtracting a mask:
// both visible ends stay round instead of tapering into sharp slivers.
let display = CGMutablePath()
display.move(to: CGPoint(x: 478, y: 446))
display.addLine(to: CGPoint(x: 280, y: 446))
display.addQuadCurve(to: CGPoint(x: 236, y: 490), control: CGPoint(x: 236, y: 446))
display.addLine(to: CGPoint(x: 236, y: 714))
display.addQuadCurve(to: CGPoint(x: 280, y: 758), control: CGPoint(x: 236, y: 758))
display.addLine(to: CGPoint(x: 744, y: 758))
display.addQuadCurve(to: CGPoint(x: 788, y: 714), control: CGPoint(x: 788, y: 758))
display.addLine(to: CGPoint(x: 788, y: 704))
stroke(display, color: white, width: lineWidth)

let phone = roundedPath(CGRect(x: 554, y: 266, width: 216, height: 374), radius: 40)
stroke(phone, color: white, width: lineWidth)

guard let image = context.makeImage() else {
    fputs("无法生成图标图像。\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments.outputPath)
do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let pngData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(pngData, "public.png" as CFString, 1, nil) else {
        fputs("无法创建 PNG 图标。\n", stderr)
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fputs("无法导出 PNG 图标。\n", stderr)
        exit(1)
    }
    try (pngData as Data).write(to: outputURL, options: .atomic)
} catch {
    fputs("写入图标失败：\(error)\n", stderr)
    exit(1)
}
