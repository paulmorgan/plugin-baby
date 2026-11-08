import Foundation
import CoreGraphics
import ImageIO

// Renders Plugin Baby's original app icon: an electric plug + lightning bolt on
// a dark gradient. Run: swift Tools/MakeIcon.swift <output.png>

let size = 1024
let S = CGFloat(size)
guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("context")
}

let cyan = CGColor(red: 0.0, green: 0.80, blue: 1.0, alpha: 1)
let magenta = CGColor(red: 1.0, green: 0.18, blue: 0.62, alpha: 1)

// Background: rounded square with a diagonal navy→black gradient.
let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
                cornerWidth: S * 0.22, cornerHeight: S * 0.22, transform: nil)
ctx.addPath(bg); ctx.clip()
let grad = CGGradient(colorsSpace: cs,
                      colors: [CGColor(red: 0.05, green: 0.07, blue: 0.16, alpha: 1),
                               CGColor(red: 0.01, green: 0.01, blue: 0.04, alpha: 1)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * S, y: y * S) }

// Lightning bolt (magenta, glowing) as the energy backdrop.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 70, color: magenta)
ctx.setFillColor(magenta)
let bolt = CGMutablePath()
bolt.addLines(between: [p(0.58, 0.88), p(0.33, 0.50), p(0.47, 0.50),
                        p(0.38, 0.14), p(0.66, 0.56), p(0.52, 0.56)])
bolt.closeSubpath()
ctx.addPath(bolt); ctx.fillPath()
ctx.restoreGState()

// Cable + plug (cyan, glowing).
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 55, color: cyan)
ctx.setStrokeColor(cyan); ctx.setFillColor(cyan)
ctx.setLineCap(.round); ctx.setLineJoin(.round)

ctx.setLineWidth(S * 0.055)
let cable = CGMutablePath()
cable.move(to: p(0.22, 0.28))
cable.addCurve(to: p(0.60, 0.41), control1: p(0.34, 0.08), control2: p(0.56, 0.17))
ctx.addPath(cable); ctx.strokePath()

let plug = CGPath(roundedRect: CGRect(x: 0.57 * S, y: 0.36 * S, width: 0.16 * S, height: 0.10 * S),
                  cornerWidth: S * 0.02, cornerHeight: S * 0.02, transform: nil)
ctx.addPath(plug); ctx.fillPath()

ctx.setLineWidth(S * 0.028)
ctx.move(to: p(0.73, 0.39)); ctx.addLine(to: p(0.80, 0.39))
ctx.move(to: p(0.73, 0.43)); ctx.addLine(to: p(0.80, 0.43))
ctx.strokePath()
ctx.restoreGState()

guard let image = ctx.makeImage() else { fatalError("image") }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
guard let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("dest")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
