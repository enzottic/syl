#!/usr/bin/env swift
// Composes raw snapshot captures into App Store pages described by screenshot_template.json.
// Usage: swift frame_screenshots.swift <captures dir> <template json> <output dir> [style json]
//
// The template holds the content (captions, layouts, captures); its "style" names a style file with
// colors, fonts and effects. Passing a style file as the last argument overrides it, to preview variants.
//
// Captures are read from <captures dir>/<language>/<device>-<capture>.png (snapshot's naming) and
// each page is written to <output dir>/<language>/<device>-<page>.png at the capture's pixel size.
// A capture prefixed "iPhone:", "iPad:" or "Duo:" is taken from that device's run, so a page can show another device.
// A page's "overrides" swap its layout and captures for one device, when all of that device's captures exist.

import AppKit
import CoreText
import Foundation

enum Layout: String, Decodable {
    /// Caption above, device running off the bottom edge.
    case captionTop
    /// Device running off the top edge, caption below.
    case captionBottom
    /// Upside-down device off the top facing a second device off the bottom, caption between them.
    case split
}

/// A region of a phone capture, lifted out of the device and floated beside it.
struct Callout: Decodable {
    /// x, y, width, height as fractions of the capture.
    let rect: [CGFloat]
    /// "left" or "right": which way the card is nudged off its spot on the screen.
    let side: String
}

struct PageOverride: Decodable {
    let layout: Layout?
    let captures: [String]
}

struct Page: Decodable {
    let name: String
    var layout: Layout
    /// Words wrapped in *asterisks* are drawn in the style's highlight color.
    let title: String
    let eyebrow: String?
    var captures: [String]
    let callout: Callout?
    /// Keyed by device name as snapshot writes it, e.g. "iPhone Duo".
    let overrides: [String: PageOverride]?
}

struct Template: Decodable {
    let style: String
    let pages: [Page]
}

struct Style: Decodable {
    let titleFont: String
    let titleColor: String
    /// Size relative to the default; display faces often need a nudge to match the rounded default.
    var titleScale: CGFloat? = nil
    var highlightColor: String? = nil
    var eyebrowColor: String? = nil
    let backgroundTop: String
    let backgroundBottom: String
    /// Soft radial lights painted over the background.
    var glowColors: [String]? = nil
    let frameColor: String
    let frameHighlight: String
    var showEyebrows: Bool? = nil
    var showCallouts: Bool? = nil
    /// Degrees; alternates direction page to page. Applies to single-device pages.
    var deviceTilt: CGFloat? = nil
    /// Folder of Apple's official bezel PNGs (Design Resources), relative to the template.
    /// Devices without a bezel there get a drawn frame in `frameColor`.
    var bezels: String? = nil
}

/// "#RRGGBB" or "#RRGGBBAA".
func color(_ hex: String) -> CGColor {
    let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    let value = UInt64(digits, radix: 16) ?? 0
    let hasAlpha = digits.count == 8
    let rgb = hasAlpha ? value >> 8 : value
    return CGColor(
        red: CGFloat((rgb >> 16) & 0xFF) / 255,
        green: CGFloat((rgb >> 8) & 0xFF) / 255,
        blue: CGFloat(rgb & 0xFF) / 255,
        alpha: hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
    )
}

/// Accepts a font file path (relative to the template), "rounded-<weight>" for SF Pro Rounded, or a PostScript name.
func loadFont(_ spec: String, relativeTo base: URL, size: CGFloat) -> CTFont {
    let url = URL(fileURLWithPath: spec, relativeTo: base)
    if FileManager.default.fileExists(atPath: url.path),
       let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first {
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
    if spec.hasPrefix("rounded-") {
        let weights: [String: NSFont.Weight] = ["medium": .medium, "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black]
        let weight = weights[String(spec.dropFirst("rounded-".count))] ?? .bold
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        if let rounded = system.fontDescriptor.withDesign(.rounded), let font = NSFont(descriptor: rounded, size: size) {
            return font as CTFont
        }
        return system as CTFont
    }
    return CTFontCreateWithName(spec as CFString, size, nil)
}

struct TextBlock {
    let framesetter: CTFramesetter
    let width: CGFloat
    let height: CGFloat

    init(_ attributed: NSAttributedString, width: CGFloat) {
        framesetter = CTFramesetterCreateWithAttributedString(attributed)
        self.width = width
        height = ceil(CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil
        ).height)
    }

    /// `top` is measured down from the top of the canvas.
    func draw(in context: CGContext, canvas: CGSize, top: CGFloat) {
        let rect = CGRect(x: (canvas.width - width) / 2, y: canvas.height - top - height, width: width, height: height)
        CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: rect, transform: nil), nil), context)
    }
}

func centeredParagraph(lineHeight: CGFloat) -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineHeightMultiple = lineHeight
    return paragraph
}

/// Splits on *asterisks*, coloring the wrapped words.
func highlightedTitle(_ text: String, font: CTFont, color: CGColor, highlight: CGColor) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for (index, part) in text.components(separatedBy: "*").enumerated() where !part.isEmpty {
        result.append(NSAttributedString(string: part, attributes: [
            .font: font,
            .foregroundColor: NSColor(cgColor: index.isMultiple(of: 2) ? color : highlight)!,
            .paragraphStyle: centeredParagraph(lineHeight: 0.95),
        ]))
    }
    return result
}

/// Optional eyebrow label stacked over the title, drawn and measured as one block.
struct Caption {
    let eyebrow: TextBlock?
    let title: TextBlock
    let spacing: CGFloat

    var height: CGFloat { (eyebrow.map { $0.height + spacing } ?? 0) + title.height }

    func draw(in context: CGContext, canvas: CGSize, top: CGFloat) {
        var cursor = top
        if let eyebrow {
            eyebrow.draw(in: context, canvas: canvas, top: cursor)
            cursor += eyebrow.height + spacing
        }
        title.draw(in: context, canvas: canvas, top: cursor)
    }
}

/// Hardware proportions, relative to the screen's short side, for the device held in portrait.
struct DeviceStyle {
    enum Sensor {
        case dynamicIsland, sideCamera, none
        /// Hole-punch camera, positioned from the screen's top-right corner.
        case punchHole(fromRight: CGFloat, fromTop: CGFloat, diameter: CGFloat)
    }

    let bezel: CGFloat
    let screenCorner: CGFloat
    /// Corner radius on the left (hinge) side, when it differs from `screenCorner`.
    var hingeScreenCorner: CGFloat? = nil
    /// Width of a hinge spine standing proud of the body's left edge.
    var spineWidth: CGFloat = 0
    let sensor: Sensor
    let leftButtons: [(top: CGFloat, length: CGFloat)]
    let rightButtons: [(top: CGFloat, length: CGFloat)]
    let topButtons: [(left: CGFloat, length: CGFloat)]
    /// File name stem in the style's bezel folder; "-landscape" is appended for landscape captures.
    var bezelName = ""

    static let iPhone = DeviceStyle(
        bezel: 0.04, screenCorner: 0.14, sensor: .dynamicIsland,
        leftButtons: [(0.36, 0.11), (0.56, 0.2), (0.82, 0.2)],
        rightButtons: [(0.64, 0.3), (1.32, 0.17)],
        topButtons: [],
        bezelName: "iphone"
    )

    static let iPad = DeviceStyle(
        bezel: 0.045, screenCorner: 0.03, sensor: .sideCamera,
        leftButtons: [],
        rightButtons: [(0.12, 0.07), (0.21, 0.07)],
        topButtons: [(0.8, 0.07)],
        bezelName: "ipad"
    )

    /// The closed iPhone Duo, traced from the Simulator's bezel: hinge spine on the left, camera top right.
    static let foldableClosed = DeviceStyle(
        bezel: 0.032, screenCorner: 0.15, hingeScreenCorner: 0.035, spineWidth: 0.034,
        sensor: .punchHole(fromRight: 0.112, fromTop: 0.1, diameter: 0.078),
        leftButtons: [],
        rightButtons: [(0.4, 0.22)],
        topButtons: [(0.446, 0.14), (0.617, 0.144)],
        bezelName: "duo-closed"
    )

    /// The open iPhone Duo's inner screen, kept plain.
    static let foldableOpen = DeviceStyle(
        bezel: 0.03, screenCorner: 0.09, sensor: .none,
        leftButtons: [],
        rightButtons: [],
        topButtons: [],
        bezelName: "duo-open"
    )

    /// iPhone Duo captures are recognized by its two screen sizes (fastlane's APP_IPHONE_DUO).
    static func `for`(_ capture: CGImage) -> DeviceStyle {
        let size = [min(capture.width, capture.height), max(capture.width, capture.height)]
        if size == [1398, 2034] { return .foldableClosed }
        if size == [2007, 2853] { return .foldableOpen }
        return isPhoneShaped(capture) ? .iPhone : .iPad
    }
}

enum VerticalAnchor {
    /// Distance from the canvas's top edge to the device's top edge.
    case top(CGFloat)
    /// Distance from the canvas's top edge to the device's bottom edge.
    case bottom(CGFloat)
    /// Distance from the canvas's top edge to the device's center.
    case center(CGFloat)
}

func isPhoneShaped(_ image: CGImage) -> Bool {
    CGFloat(min(image.width, image.height)) / CGFloat(max(image.width, image.height)) < 0.6
}

/// An official bezel image and the transparent screen opening inside it.
struct Bezel {
    let image: CGImage
    /// The opening in image pixels, measured from the top-left corner.
    let opening: CGRect
    /// Image-sized grayscale mask that is white across the opening, camera cutouts excluded.
    let mask: CGImage

    private static var cache: [String: Bezel?] = [:]

    static func load(_ url: URL) -> Bezel? {
        if let cached = cache[url.path] { return cached }
        let bezel = Bezel(url: url)
        cache[url.path] = bezel
        return bezel
    }

    /// Flood-fills the see-through pixels outward from the image's center, stopping at the frame.
    private init?(url: URL) {
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var opening = [UInt8](repeating: 0, count: width * height)
        var stack = [(height / 2) * width + width / 2]
        var minX = width, minY = height, maxX = 0, maxY = 0
        while let index = stack.popLast() {
            guard opening[index] == 0, pixels[index * 4 + 3] < 200 else { continue }
            opening[index] = 255
            let x = index % width, y = index / width
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            if x > 0 { stack.append(index - 1) }
            if x < width - 1 { stack.append(index + 1) }
            if y > 0 { stack.append(index - width) }
            if y < height - 1 { stack.append(index + width) }
        }
        guard minX > 0, minY > 0, maxX < width - 1, maxY < height - 1 else {
            print("\(url.lastPathComponent): no enclosed screen opening, using a drawn frame")
            return nil
        }

        self.image = image
        self.opening = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        self.mask = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: CGDataProvider(data: Data(opening) as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )!
    }
}

struct DeviceRenderer {
    let body: CGColor
    let highlight: CGColor
    let bezelDir: URL?

    /// Draws `capture` in a device frame centered horizontally.
    /// `screenWidth` is the on-canvas width of the screen; landscape captures get a sideways device.
    /// Returns the untilted screen's frame, measured down from the canvas's top edge.
    @discardableResult
    func draw(_ capture: CGImage, screenWidth: CGFloat, upsideDown: Bool = false, tilt: CGFloat = 0, anchor: VerticalAnchor, in context: CGContext, canvas: CGSize) -> CGRect {
        let style = DeviceStyle.for(capture)
        let isLandscape = capture.width > capture.height
        if let bezelDir, let bezel = Bezel.load(bezelDir.appendingPathComponent(style.bezelName + (isLandscape ? "-landscape" : "") + ".png")) {
            return draw(capture, in: bezel, screenWidth: screenWidth, upsideDown: upsideDown, tilt: tilt, anchor: anchor, context: context, canvas: canvas)
        }
        let short = CGFloat(min(capture.width, capture.height)), long = CGFloat(max(capture.width, capture.height))
        let scale = screenWidth / (isLandscape ? long : short)
        let screen = CGSize(width: short * scale, height: long * scale)
        let bezel = screen.width * style.bezel
        let body = CGSize(width: screen.width + bezel * 2, height: screen.height + bezel * 2)
        let onCanvasHeight = isLandscape ? body.width : body.height

        let centerFromTop: CGFloat
        switch anchor {
        case .top(let top): centerFromTop = top + onCanvasHeight / 2
        case .bottom(let bottom): centerFromTop = bottom - onCanvasHeight / 2
        case .center(let center): centerFromTop = center
        }

        // Shadows are cast in canvas space, so they stay below the device whatever its rotation.
        context.saveGState()
        context.translateBy(x: canvas.width / 2, y: canvas.height - centerFromTop)
        // Turning counterclockwise puts the iPad's long-edge camera on top, as in landscape use.
        let deviceRotation: CGFloat = isLandscape ? .pi / 2 : (upsideDown ? .pi : 0)
        context.rotate(by: deviceRotation + tilt * .pi / 180)
        drawPortrait(capture, style: style, screen: screen, bezel: bezel, contentRotation: isLandscape ? -.pi / 2 : 0, in: context, canvas: canvas)
        context.restoreGState()

        let onCanvasScreen = isLandscape ? CGSize(width: screen.height, height: screen.width) : screen
        return CGRect(
            x: (canvas.width - onCanvasScreen.width) / 2, y: centerFromTop - onCanvasScreen.height / 2,
            width: onCanvasScreen.width, height: onCanvasScreen.height
        )
    }

    /// Lays the capture into the bezel's opening and the bezel over it, so the camera cutouts and frame edges sit on top.
    private func draw(_ capture: CGImage, in bezel: Bezel, screenWidth: CGFloat, upsideDown: Bool, tilt: CGFloat, anchor: VerticalAnchor, context: CGContext, canvas: CGSize) -> CGRect {
        let scale = screenWidth / bezel.opening.width
        let body = CGRect(x: 0, y: 0, width: CGFloat(bezel.image.width) * scale, height: CGFloat(bezel.image.height) * scale)
        let bodyRect = body.offsetBy(dx: -body.width / 2, dy: -body.height / 2)
        let screen = CGRect(
            x: bodyRect.minX + bezel.opening.minX * scale, y: bodyRect.maxY - bezel.opening.maxY * scale,
            width: bezel.opening.width * scale, height: bezel.opening.height * scale
        )

        let centerFromTop: CGFloat
        switch anchor {
        case .top(let top): centerFromTop = top + body.height / 2
        case .bottom(let bottom): centerFromTop = bottom - body.height / 2
        case .center(let center): centerFromTop = center
        }

        context.saveGState()
        context.translateBy(x: canvas.width / 2, y: canvas.height - centerFromTop)
        context.rotate(by: (upsideDown ? .pi : 0) + tilt * .pi / 180)
        context.interpolationQuality = .high

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -canvas.width * 0.01), blur: canvas.width * 0.045, color: CGColor(gray: 0, alpha: 0.28))
        context.draw(bezel.image, in: bodyRect)
        context.restoreGState()

        context.saveGState()
        context.clip(to: bodyRect, mask: bezel.mask)
        context.draw(capture, in: screen)
        context.restoreGState()
        context.draw(bezel.image, in: bodyRect)
        context.restoreGState()

        // Upside down, the opening's offset from the body's center flips too.
        let flip: CGFloat = upsideDown ? -1 : 1
        return CGRect(
            x: canvas.width / 2 + screen.minX * flip - (upsideDown ? screen.width : 0),
            y: centerFromTop - (upsideDown ? -screen.minY : screen.maxY),
            width: screen.width, height: screen.height
        )
    }

    /// Draws a portrait device centered on the current origin.
    private func drawPortrait(_ capture: CGImage, style: DeviceStyle, screen: CGSize, bezel: CGFloat, contentRotation: CGFloat, in context: CGContext, canvas: CGSize) {
        let w = screen.width
        let screenRect = CGRect(x: -screen.width / 2, y: -screen.height / 2, width: screen.width, height: screen.height)
        let screenCorner = w * style.screenCorner
        let hingeCorner = w * (style.hingeScreenCorner ?? style.screenCorner)
        let bodyRect = screenRect.insetBy(dx: -bezel, dy: -bezel)
        let bandWidth = bezel * 0.3
        let buttonDepth = bezel * 0.22

        /// A rounded rect whose left corners can be tighter than its right ones; `outset` is how far outside the screen edge it sits.
        func devicePath(_ rect: CGRect, outset: CGFloat) -> CGPath {
            let left = max(hingeCorner + outset, 0), right = max(screenCorner + outset, 0)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX + left, y: rect.maxY))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: right)
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: right)
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: left)
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: left)
            path.closeSubpath()
            return path
        }
        func fill(_ path: CGPath, color: CGColor) {
            context.addPath(path)
            context.setFillColor(color)
            context.fillPath()
        }
        func fillRounded(_ rect: CGRect, radius: CGFloat, color: CGColor) {
            fill(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil), color: color)
        }

        // Buttons sit behind the body so only their outer edge shows.
        // Positions are measured from the screen's top-left corner in units of screen width.
        for (top, length) in style.leftButtons {
            fillRounded(CGRect(x: bodyRect.minX - buttonDepth, y: screenRect.maxY - (top + length) * w, width: buttonDepth * 2, height: length * w), radius: buttonDepth, color: body)
        }
        for (top, length) in style.rightButtons {
            fillRounded(CGRect(x: bodyRect.maxX - buttonDepth, y: screenRect.maxY - (top + length) * w, width: buttonDepth * 2, height: length * w), radius: buttonDepth, color: body)
        }
        for (left, length) in style.topButtons {
            fillRounded(CGRect(x: screenRect.minX + left * w, y: bodyRect.maxY - buttonDepth, width: length * w, height: buttonDepth * 2), radius: buttonDepth, color: body)
        }

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -canvas.width * 0.01), blur: canvas.width * 0.045, color: CGColor(gray: 0, alpha: 0.28))
        if style.spineWidth > 0 {
            let spine = w * style.spineWidth
            let spineRect = CGRect(x: bodyRect.minX - spine * 0.7, y: bodyRect.minY + bezel * 0.4, width: spine, height: bodyRect.height - bezel * 0.8)
            fillRounded(spineRect, radius: spine * 0.35, color: body)
        }
        fill(devicePath(bodyRect, outset: bezel), color: body)
        context.restoreGState()

        let rimInset = bandWidth * 0.3
        context.addPath(devicePath(bodyRect.insetBy(dx: rimInset, dy: rimInset), outset: bezel - rimInset))
        context.setStrokeColor(highlight)
        context.setLineWidth(bandWidth * 0.35)
        context.strokePath()

        let glassRect = bodyRect.insetBy(dx: bandWidth, dy: bandWidth)
        fill(devicePath(glassRect, outset: bezel - bandWidth), color: CGColor(gray: 0.04, alpha: 1))

        context.saveGState()
        context.addPath(devicePath(screenRect, outset: 0))
        context.clip()
        context.rotate(by: contentRotation)
        let content = contentRotation == 0 ? screen : CGSize(width: screen.height, height: screen.width)
        context.interpolationQuality = .high
        context.draw(capture, in: CGRect(x: -content.width / 2, y: -content.height / 2, width: content.width, height: content.height))
        context.restoreGState()

        switch style.sensor {
        case .dynamicIsland:
            let island = CGSize(width: w * 0.285, height: w * 0.084)
            let rect = CGRect(x: -island.width / 2, y: screenRect.maxY - w * 0.027 - island.height, width: island.width, height: island.height)
            fillRounded(rect, radius: island.height / 2, color: CGColor(gray: 0, alpha: 1))
        case .sideCamera:
            // Front camera, centered on the long edge (the right side in portrait).
            let dot = bezel * 0.22
            context.setFillColor(CGColor(gray: 0.15, alpha: 1))
            context.fillEllipse(in: CGRect(x: (glassRect.maxX + screenRect.maxX - dot) / 2, y: -dot / 2, width: dot, height: dot))
        case .punchHole(let fromRight, let fromTop, let diameter):
            let d = w * diameter
            fillRounded(CGRect(x: screenRect.maxX - fromRight * w - d / 2, y: screenRect.maxY - fromTop * w - d / 2, width: d, height: d), radius: d / 2, color: CGColor(gray: 0, alpha: 1))
        case .none:
            break
        }
    }
}

/// Canvas-relative sizes, tuned separately for the phone (portrait) and tablet (landscape) pages.
struct PageMetrics {
    let titleSize: CGFloat
    let titleWidth: CGFloat
    let titleTop: CGFloat
    /// The lowest a caption-top device may start, so short captions don't pull it up.
    let minDeviceTop: CGFloat
    let gap: CGFloat
    let captionBottom: CGFloat
    let splitCaptionCenter: CGFloat
    let ownScreenWidth: CGFloat
    let phoneScreenWidth: CGFloat

    static func `for`(_ canvas: CGSize) -> PageMetrics {
        if canvas.width < canvas.height {
            return PageMetrics(
                titleSize: canvas.width * 0.08, titleWidth: canvas.width * 0.84, titleTop: canvas.height * 0.075,
                minDeviceTop: canvas.height * 0.215, gap: canvas.height * 0.035, captionBottom: canvas.height * 0.93,
                splitCaptionCenter: canvas.height * 0.535, ownScreenWidth: canvas.width * 0.8, phoneScreenWidth: canvas.width * 0.8
            )
        }
        return PageMetrics(
            titleSize: canvas.width * 0.042, titleWidth: canvas.width * 0.9, titleTop: canvas.height * 0.07,
            minDeviceTop: canvas.height * 0.2, gap: canvas.height * 0.045, captionBottom: canvas.height * 0.93,
            splitCaptionCenter: canvas.height * 0.45, ownScreenWidth: canvas.width * 0.78, phoneScreenWidth: canvas.width * 0.24
        )
    }

    func screenWidth(for capture: CGImage, canvas: CGImage) -> CGFloat {
        isPhoneShaped(capture) && !isPhoneShaped(canvas) ? phoneScreenWidth : ownScreenWidth
    }
}

/// Large soft lights; each page shifts the pattern so the set flows when viewed side by side.
func drawGlow(_ colors: [String], pageIndex: Int, in context: CGContext, canvas: CGSize) {
    let spots: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = [(0.15, 0.2, 0.7), (0.95, 0.55, 0.8), (0.3, 0.95, 0.6)]
    for (index, spot) in spots.enumerated() {
        let glow = color(colors[index % colors.count])
        let x = (spot.x + CGFloat(pageIndex) * 0.37).truncatingRemainder(dividingBy: 1.2) - 0.1
        let center = CGPoint(x: canvas.width * x, y: canvas.height * (1 - spot.y))
        let radius = max(canvas.width, canvas.height) * spot.radius * 0.5
        let gradient = CGGradient(colorsSpace: nil, colors: [glow, glow.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
}

/// Floats a crop of the capture over its own spot on the screen, enlarged so it fully covers the original.
/// `screen` is the device screen's frame, measured down from the canvas's top edge.
func drawCallout(_ callout: Callout, from capture: CGImage, screen: CGRect, in context: CGContext, canvas: CGSize) {
    let r = callout.rect
    let crop = CGRect(x: r[0] * CGFloat(capture.width), y: r[1] * CGFloat(capture.height), width: r[2] * CGFloat(capture.width), height: r[3] * CGFloat(capture.height))
    guard let image = capture.cropping(to: crop) else { return }
    let width = screen.width * r[2] * 1.12
    let height = width * crop.height / crop.width
    let nudge = canvas.width * 0.035 * (callout.side == "left" ? -1 : 1)
    let centerX = screen.minX + (r[0] + r[2] / 2) * screen.width + nudge
    let centerFromTop = screen.minY + (r[1] + r[3] / 2) * screen.height
    let rect = CGRect(x: centerX - width / 2, y: canvas.height - centerFromTop - height / 2, width: width, height: height)
    let path = CGPath(roundedRect: rect, cornerWidth: width * 0.06, cornerHeight: width * 0.06, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -canvas.width * 0.015), blur: canvas.width * 0.06, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(path)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.interpolationQuality = .high
    context.draw(image, in: rect)
    context.restoreGState()
}

func loadCapture(_ url: URL) throws -> CGImage {
    guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "frame", code: 1, userInfo: [NSLocalizedDescriptionKey: "Can't read \(url.path)"])
    }
    return image
}

func render(_ page: Page, index: Int, captures: [CGImage], canvasCapture: CGImage, style: Style, templateDir: URL, to output: URL) throws {
    let canvas = CGSize(width: canvasCapture.width, height: canvasCapture.height)
    let metrics = PageMetrics.for(canvas)
    let renderer = DeviceRenderer(
        body: color(style.frameColor), highlight: color(style.frameHighlight),
        bezelDir: style.bezels.map { URL(fileURLWithPath: $0, relativeTo: templateDir) }
    )

    let context = CGContext(
        data: nil, width: canvasCapture.width, height: canvasCapture.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    let gradient = CGGradient(colorsSpace: nil, colors: [color(style.backgroundTop), color(style.backgroundBottom)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas.height), end: .zero, options: [])
    if let glowColors = style.glowColors, !glowColors.isEmpty {
        drawGlow(glowColors, pageIndex: index, in: context, canvas: canvas)
    }

    let titleColor = color(style.titleColor)
    let titleSize = metrics.titleSize * (style.titleScale ?? 1)
    let title = TextBlock(highlightedTitle(
        page.title,
        font: loadFont(style.titleFont, relativeTo: templateDir, size: titleSize),
        color: titleColor,
        highlight: style.highlightColor.map(color) ?? titleColor
    ), width: metrics.titleWidth)
    let eyebrow = (style.showEyebrows ?? false) ? page.eyebrow.map { text in
        TextBlock(NSAttributedString(string: text.uppercased(), attributes: [
            .font: loadFont("rounded-bold", relativeTo: templateDir, size: metrics.titleSize * 0.36),
            .foregroundColor: NSColor(cgColor: style.eyebrowColor.map(color) ?? titleColor)!,
            .kern: metrics.titleSize * 0.06,
            .paragraphStyle: centeredParagraph(lineHeight: 1),
        ]), width: metrics.titleWidth)
    } : nil
    let caption = Caption(eyebrow: eyebrow, title: title, spacing: metrics.titleSize * 0.3)

    // Callout crops are measured on phone captures, so they only apply to phone pages.
    let callout = (style.showCallouts ?? false) && isPhoneShaped(canvasCapture) ? page.callout : nil
    // A tilted device would leave its copy of the callout card peeking out from under the floating one.
    let tilt = callout == nil ? (style.deviceTilt ?? 0) * (index.isMultiple(of: 2) ? -1 : 1) : 0
    func device(_ capture: CGImage, upsideDown: Bool = false, tilt: CGFloat = 0, _ anchor: VerticalAnchor) -> CGRect {
        renderer.draw(capture, screenWidth: metrics.screenWidth(for: capture, canvas: canvasCapture), upsideDown: upsideDown, tilt: tilt, anchor: anchor, in: context, canvas: canvas)
    }

    let screen: CGRect
    switch page.layout {
    case .captionTop:
        caption.draw(in: context, canvas: canvas, top: metrics.titleTop)
        let deviceTop = max(metrics.titleTop + caption.height + metrics.gap, metrics.minDeviceTop)
        // A horizontal device on a portrait page is short, so it sits centered in the space below the caption.
        let isWideOnTall = captures[0].width > captures[0].height && canvas.height > canvas.width
        screen = device(captures[0], tilt: tilt, isWideOnTall ? .center((deviceTop + canvas.height * 0.95) / 2) : .top(deviceTop))
    case .captionBottom:
        let captionTop = metrics.captionBottom - caption.height
        caption.draw(in: context, canvas: canvas, top: captionTop)
        screen = device(captures[0], tilt: tilt, .bottom(captionTop - metrics.gap))
    case .split:
        let captionTop = metrics.splitCaptionCenter - caption.height / 2
        caption.draw(in: context, canvas: canvas, top: captionTop)
        screen = device(captures[0], upsideDown: true, .bottom(captionTop - metrics.gap))
        _ = device(captures.count > 1 ? captures[1] : captures[0], .top(captionTop + caption.height + metrics.gap))
    }

    if let callout, page.layout != .split {
        drawCallout(callout, from: captures[0], screen: screen, in: context, canvas: canvas)
    }

    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!.write(to: output)
    print("Wrote \(output.lastPathComponent)")
}

let arguments = CommandLine.arguments
guard arguments.count == 4 || arguments.count == 5 else {
    print("Usage: swift frame_screenshots.swift <captures dir> <template json> <output dir> [style json]")
    exit(1)
}
let capturesDir = URL(fileURLWithPath: arguments[1], isDirectory: true)
let templateURL = URL(fileURLWithPath: arguments[2])
let outputDir = URL(fileURLWithPath: arguments[3], isDirectory: true)
let template = try JSONDecoder().decode(Template.self, from: Data(contentsOf: templateURL))
let templateDir = templateURL.deletingLastPathComponent()
let styleURL = arguments.count == 5 ? URL(fileURLWithPath: arguments[4]) : URL(fileURLWithPath: template.style, relativeTo: templateDir)
let style = try JSONDecoder().decode(Style.self, from: Data(contentsOf: styleURL))
let fileManager = FileManager.default

/// Resolves a capture reference to its file, following an optional "iPhone:", "iPad:" or "Duo:" device prefix.
func captureURL(_ reference: String, device: String, devices: [String], canvases: [String: CGImage], in languageDir: URL) -> URL {
    let parts = reference.split(separator: ":", maxSplits: 1).map(String.init)
    var owner = device
    if parts.count == 2 {
        let match: (String) -> Bool
        switch parts[0] {
        case "iPhone": match = { isPhoneShaped(canvases[$0]!) }
        case "iPad": match = { $0.hasPrefix("iPad") }
        case "Duo": match = { $0.contains("Duo") }
        default: match = { _ in false }
        }
        owner = devices.first(where: match) ?? device
    }
    return languageDir.appendingPathComponent("\(owner)-\(parts.last!).png")
}

try? fileManager.removeItem(at: outputDir)
var written = 0
for language in try fileManager.contentsOfDirectory(atPath: capturesDir.path).sorted() {
    let languageDir = capturesDir.appendingPathComponent(language, isDirectory: true)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: languageDir.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }

    let files = try fileManager.contentsOfDirectory(atPath: languageDir.path).filter { $0.hasSuffix(".png") }
    // snapshot names files "<device>-<capture>.png"; the first page's first capture identifies each device.
    let anchorCapture = template.pages[0].captures[0].split(separator: ":").last!
    let anchor = "-\(anchorCapture).png"
    let devices = files.filter { $0.hasSuffix(anchor) }.map { String($0.dropLast(anchor.count)) }.sorted()
    let canvases = try Dictionary(uniqueKeysWithValues: devices.map { ($0, try loadCapture(languageDir.appendingPathComponent($0 + anchor))) })

    for device in devices {
        for (index, basePage) in template.pages.enumerated() {
            func urls(for captures: [String]) -> [URL] {
                captures.map { captureURL($0, device: device, devices: devices, canvases: canvases, in: languageDir) }
            }
            var page = basePage
            if let override = page.overrides?[device] {
                if urls(for: override.captures).allSatisfy({ fileManager.fileExists(atPath: $0.path) }) {
                    page.captures = override.captures
                    page.layout = override.layout ?? page.layout
                } else {
                    print("\(device) \(page.name): override captures missing, using the default page")
                }
            }
            let urls = urls(for: page.captures)
            guard urls.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
                print("Skipping \(device) \(page.name): missing \(page.captures.joined(separator: ", "))")
                continue
            }
            let output = outputDir.appendingPathComponent(language).appendingPathComponent("\(device)-\(page.name).png")
            try render(page, index: index, captures: try urls.map(loadCapture), canvasCapture: canvases[device]!, style: style, templateDir: templateDir, to: output)
            written += 1
        }
    }
}
print("Wrote \(written) page(s)")
