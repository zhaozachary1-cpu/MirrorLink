import AppKit
import Darwin
import Foundation

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
let canvasSize: CGFloat = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize),
    pixelsHigh: Int(canvasSize),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bitmapFormat: [],
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("无法创建图标绘图上下文。\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
defer { NSGraphicsContext.restoreGraphicsState() }

let context = graphicsContext.cgContext
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.interpolationQuality = .high

let colorSpace = CGColorSpaceCreateDeviceRGB()

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha).cgColor
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )
}

func fillRoundedRect(_ rect: CGRect, radius: CGFloat, fill: CGColor) {
    context.saveGState()
    context.setFillColor(fill)
    context.addPath(roundedPath(rect, radius: radius))
    context.fillPath()
    context.restoreGState()
}

func gradientRoundedRect(
    _ rect: CGRect,
    radius: CGFloat,
    colors: [CGColor],
    start: CGPoint,
    end: CGPoint,
    locations: [CGFloat] = [0, 1]
) {
    context.saveGState()
    context.addPath(roundedPath(rect, radius: radius))
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: colors as CFArray,
        locations: locations
    ) {
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
    }
    context.restoreGState()
}

func drawShadowedRoundedRect(
    _ rect: CGRect,
    radius: CGFloat,
    fill: CGColor,
    shadowColor: CGColor,
    shadowOffset: CGSize,
    shadowBlur: CGFloat
) {
    context.saveGState()
    context.setShadow(offset: shadowOffset, blur: shadowBlur, color: shadowColor)
    context.setFillColor(fill)
    context.addPath(roundedPath(rect, radius: radius))
    context.fillPath()
    context.restoreGState()
}

func strokePath(_ path: CGPath, color: CGColor, width: CGFloat) {
    context.saveGState()
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(path)
    context.strokePath()
    context.restoreGState()
}

func drawScreenContent(in rect: CGRect, accent: CGColor) {
    let contentRect = CGRect(
        x: rect.minX + rect.width * 0.17,
        y: rect.minY + rect.height * 0.19,
        width: rect.width * 0.66,
        height: rect.height * 0.58
    )

    fillRoundedRect(
        CGRect(
            x: contentRect.minX,
            y: contentRect.maxY - contentRect.height * 0.20,
            width: contentRect.width * 0.72,
            height: contentRect.height * 0.12
        ),
        radius: contentRect.height * 0.06,
        fill: color(1, 1, 1, 0.96)
    )
    fillRoundedRect(
        CGRect(
            x: contentRect.minX,
            y: contentRect.maxY - contentRect.height * 0.46,
            width: contentRect.width * 0.94,
            height: contentRect.height * 0.10
        ),
        radius: contentRect.height * 0.05,
        fill: color(1, 1, 1, 0.78)
    )
    fillRoundedRect(
        CGRect(
            x: contentRect.minX,
            y: contentRect.maxY - contentRect.height * 0.70,
            width: contentRect.width * 0.58,
            height: contentRect.height * 0.10
        ),
        radius: contentRect.height * 0.05,
        fill: accent
    )
}

// A deep blue-to-indigo canvas gives the icon a strong silhouette in both light and dark mode.
let canvasRect = CGRect(x: 42, y: 42, width: 940, height: 940)
gradientRoundedRect(
    canvasRect,
    radius: 210,
    colors: [
        color(0.08, 0.15, 0.45),
        color(0.04, 0.52, 0.82),
        color(0.12, 0.74, 0.73)
    ],
    start: CGPoint(x: 130, y: 920),
    end: CGPoint(x: 900, y: 80),
    locations: [0, 0.58, 1]
)

// Soft highlight keeps the icon from looking flat without adding small details.
context.saveGState()
context.addPath(roundedPath(canvasRect, radius: 210))
context.clip()
let highlight = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(1, 1, 1, 0.18), color(1, 1, 1, 0)] as CFArray,
    locations: [0, 1]
)
if let highlight {
    context.drawLinearGradient(
        highlight,
        start: CGPoint(x: 160, y: 930),
        end: CGPoint(x: 610, y: 440),
        options: []
    )
}
context.restoreGState()

// The Mac screen sits behind the phone to make the mirroring relationship obvious.
let displayFrame = CGRect(x: 300, y: 266, width: 590, height: 410)
drawShadowedRoundedRect(
    displayFrame,
    radius: 66,
    fill: color(0.91, 0.97, 1, 0.98),
    shadowColor: color(0.02, 0.04, 0.16, 0.34),
    shadowOffset: CGSize(width: 0, height: -22),
    shadowBlur: 34
)
let displayScreen = CGRect(x: 330, y: 298, width: 530, height: 342)
gradientRoundedRect(
    displayScreen,
    radius: 42,
    colors: [color(0.05, 0.18, 0.55), color(0.04, 0.70, 0.78)],
    start: CGPoint(x: displayScreen.minX, y: displayScreen.maxY),
    end: CGPoint(x: displayScreen.maxX, y: displayScreen.minY)
)
drawScreenContent(in: displayScreen, accent: color(1, 0.80, 0.31, 0.98))

// Small stand: simple enough to survive 16px rendering.
fillRoundedRect(
    CGRect(x: 532, y: 205, width: 126, height: 92),
    radius: 26,
    fill: color(0.83, 0.91, 0.98, 0.96)
)
fillRoundedRect(
    CGRect(x: 430, y: 156, width: 330, height: 62),
    radius: 31,
    fill: color(0.89, 0.96, 1, 0.98)
)

// Broadcast waves are the key product cue: the phone is sending its screen to the Mac.
let waveColorA = color(1.0, 0.83, 0.34, 1)
let waveColorB = color(1.0, 0.47, 0.52, 1)
let waves: [(start: CGPoint, control: CGPoint, end: CGPoint, width: CGFloat)] = [
    (
        CGPoint(x: 468, y: 586),
        CGPoint(x: 532, y: 705),
        CGPoint(x: 622, y: 728),
        26
    ),
    (
        CGPoint(x: 474, y: 540),
        CGPoint(x: 585, y: 758),
        CGPoint(x: 724, y: 762),
        22
    ),
    (
        CGPoint(x: 480, y: 492),
        CGPoint(x: 642, y: 810),
        CGPoint(x: 816, y: 793),
        18
    )
]
for (index, wave) in waves.enumerated() {
    let path = CGMutablePath()
    path.move(to: wave.start)
    path.addQuadCurve(to: wave.end, control: wave.control)
    strokePath(path, color: index == 0 ? waveColorA : waveColorB, width: wave.width)
}

// Phone in front: white bezel, vivid screen, and a mirrored content pattern.
let phoneFrame = CGRect(x: 112, y: 146, width: 346, height: 692)
drawShadowedRoundedRect(
    phoneFrame,
    radius: 72,
    fill: color(0.96, 0.99, 1, 1),
    shadowColor: color(0.02, 0.05, 0.18, 0.45),
    shadowOffset: CGSize(width: 0, height: -26),
    shadowBlur: 40
)
let phoneScreen = CGRect(x: 140, y: 208, width: 290, height: 548)
gradientRoundedRect(
    phoneScreen,
    radius: 52,
    colors: [color(0.10, 0.25, 0.76), color(0.08, 0.78, 0.77)],
    start: CGPoint(x: phoneScreen.minX, y: phoneScreen.maxY),
    end: CGPoint(x: phoneScreen.maxX, y: phoneScreen.minY)
)
drawScreenContent(in: phoneScreen, accent: color(1, 0.49, 0.56, 0.98))

// Speaker and camera dot establish the phone shape without relying on a detailed bezel.
fillRoundedRect(
    CGRect(x: 246, y: 778, width: 78, height: 13),
    radius: 6.5,
    fill: color(0.10, 0.18, 0.36, 0.50)
)
fillRoundedRect(
    CGRect(x: 335, y: 776, width: 16, height: 16),
    radius: 8,
    fill: color(0.10, 0.18, 0.36, 0.50)
)

// A small highlight on the phone edge adds depth while preserving the bold silhouette.
context.saveGState()
context.setStrokeColor(color(1, 1, 1, 0.72))
context.setLineWidth(7)
context.setLineCap(.round)
let edgePath = CGMutablePath()
edgePath.move(to: CGPoint(x: 153, y: 304))
edgePath.addCurve(
    to: CGPoint(x: 153, y: 662),
    control1: CGPoint(x: 135, y: 398),
    control2: CGPoint(x: 135, y: 568)
)
context.addPath(edgePath)
context.strokePath()
context.restoreGState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("无法导出 PNG 图标。\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments.outputPath)
do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    fputs("写入图标失败：\(error)\n", stderr)
    exit(1)
}
