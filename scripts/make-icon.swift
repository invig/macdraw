// Builds App/Assets.xcassets/AppIcon.appiconset from App/Icon/icon-source.webp.
// Finds the rounded-square artwork in the source (ignoring the white/shadow backdrop),
// masks it, and places it on Apple's 1024px macOS icon grid (824px body, 100px margin).
// Usage: swift scripts/make-icon.swift [source] [appiconset-dir]
import AppKit
import ImageIO

let args = CommandLine.arguments
let src = URL(fileURLWithPath: args.count > 1 ? args[1] : "App/Icon/icon-source.webp")
let outDir = URL(fileURLWithPath: args.count > 2 ? args[2] : "App/Assets.xcassets/AppIcon.appiconset")

guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("can't read \(src.path)") }
let w = image.width, h = image.height

// Read pixels as RGBA8.
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let rgb = CGColorSpaceCreateDeviceRGB()
let readCtx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
readCtx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

// "Body" pixel = the blue background (strongly blue, not white/grey shadow).
func isBody(_ x: Int, _ y: Int) -> Bool {
    let i = (y * w + x) * 4
    let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
    return b > 90 && b - r > 50 && b - g > 50
}

// Bounding box of the body, scanning rows/cols through the middle (row 0 = top in this buffer).
func firstBody(_ range: StrideTo<Int>, _ probe: (Int) -> Bool) -> Int { range.first(where: probe)! }
let midX = w / 2, midY = h / 2
let left = firstBody(stride(from: 0, to: w, by: 1)) { isBody($0, midY) }
let right = firstBody(stride(from: w - 1, to: 0, by: -1)) { isBody($0, midY) }
let top = firstBody(stride(from: 0, to: h, by: 1)) { isBody(midX, $0) }
let bottom = firstBody(stride(from: h - 1, to: 0, by: -1)) { isBody(midX, $0) }
let side = Double(min(right - left, bottom - top))

// Corner radius: walk the diagonal from the top-left corner until we hit the body.
// For a circular corner of radius r the diagonal hits at t = r(1 - 1/√2) per axis.
let t = (0..<Int(side / 2)).first { isBody(left + $0, top + $0) }!
let radiusFraction = (Double(t) / (1 - 1 / 2.0.squareRoot())) / side
print("body: x \(left)…\(right), y \(top)…\(bottom); corner radius ≈ \(Int(radiusFraction * 100))% of side")

// Crop slightly inside the body edge so no white fringe survives.
let inset = 3
let crop = CGRect(x: left + inset, y: top + inset, width: right - left - 2 * inset, height: bottom - top - 2 * inset)
let body = image.cropping(to: crop)!

// Render the 1024 master.
let canvas = 1024.0, bodySize = 824.0
let rect = CGRect(x: (canvas - bodySize) / 2, y: (canvas - bodySize) / 2, width: bodySize, height: bodySize)
let radius = bodySize * max(0.2237, radiusFraction + 0.01)  // Apple's ratio, or the art's if rounder
let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
                    space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()  // soft drop shadow, like the system template
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path); ctx.clip()
ctx.interpolationQuality = .high
ctx.draw(body, in: rect)
ctx.restoreGState()
let master = ctx.makeImage()!

// Write every size the macOS app icon set needs.
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
func write(_ size: Int, _ name: String) {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                      space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
    let dest = CGImageDestinationCreateWithURL(outDir.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, c.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}
var entries: [String] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        write(pt * scale, name)
        entries.append(#"{"idiom":"mac","size":"\#(pt)x\#(pt)","scale":"\#(scale)x","filename":"\#(name)"}"#)
    }
}
let json = "{\"images\":[\n" + entries.joined(separator: ",\n") + "\n],\"info\":{\"author\":\"xcode\",\"version\":1}}\n"
try! json.write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try! #"{"info":{"author":"xcode","version":1}}"#.write(to: outDir.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(entries.count) icons to \(outDir.path)")
