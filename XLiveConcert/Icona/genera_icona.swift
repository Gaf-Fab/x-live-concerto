// Genera l'icona 1024x1024 (senza trasparenza) dell'app X-LIVE Concerto: pannello antracite, display nero con onda ambra,
// marker rosso e punto REC. Uso: swift genera_icona.swift <file.png>
import AppKit
import CoreGraphics

let size = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
let amber = col(0xf2a900), red = col(0xc8102e)
let S = CGFloat(size)

// sfondo antracite con leggera sfumatura
let g = CGGradient(colorsSpace: cs, colors: [col(0x3a3d41), col(0x1b1d1f)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

// display nero
let lcd = CGRect(x: 112, y: 262, width: 800, height: 500)
let lcdPath = CGPath(roundedRect: lcd, cornerWidth: 56, cornerHeight: 56, transform: nil)
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: col(0x000000, 0.55))
ctx.addPath(lcdPath); ctx.setFillColor(col(0x050505)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0)
ctx.addPath(lcdPath); ctx.setStrokeColor(col(0x6b6e72, 0.9)); ctx.setLineWidth(6); ctx.strokePath()

// onda ambra (barre simmetriche)
let heights: [CGFloat] = [34, 70, 120, 90, 150, 200, 130, 220, 160, 110, 180, 90, 130, 60, 36]
let barW: CGFloat = 30, gap: CGFloat = 20
let total = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
var x = lcd.midX - total / 2
let midY = lcd.midY - 20
for (i, h) in heights.enumerated() {
    let r = CGRect(x: x, y: midY - h / 2 - h * 0.15, width: barW, height: h * 1.3)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 12, cornerHeight: 12, transform: nil))
    ctx.setFillColor(amber); ctx.setAlpha(i >= 6 && i <= 8 ? 1 : 0.92); ctx.fillPath(); ctx.setAlpha(1)
    x += barW + gap
}

// marker rosso con bandierina
let mx = lcd.minX + 285
ctx.setStrokeColor(red); ctx.setLineWidth(12); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: mx, y: lcd.minY + 50)); ctx.addLine(to: CGPoint(x: mx, y: lcd.maxY - 70)); ctx.strokePath()
ctx.setFillColor(red)
ctx.move(to: CGPoint(x: mx, y: lcd.maxY - 70)); ctx.addLine(to: CGPoint(x: mx + 76, y: lcd.maxY - 100))
ctx.addLine(to: CGPoint(x: mx, y: lcd.maxY - 130)); ctx.closePath(); ctx.fillPath()

// punto REC in alto sopra il display
let rec = CGRect(x: lcd.minX + 8, y: lcd.maxY + 56, width: 92, height: 92)
ctx.setShadow(offset: .zero, blur: 40, color: col(0xc8102e, 0.8))
ctx.setFillColor(red); ctx.fillEllipse(in: rec)
ctx.setShadow(offset: .zero, blur: 0)
ctx.setFillColor(col(0xffffff, 0.22)); ctx.fillEllipse(in: CGRect(x: rec.minX + 18, y: rec.minY + 46, width: 30, height: 26))

// "tacche" del pannello sotto il display
ctx.setFillColor(col(0x8a8d91, 0.8))
for i in 0..<6 {
    ctx.fill(CGRect(x: lcd.minX + 30 + CGFloat(i) * 70, y: lcd.minY - 92, width: 44, height: 12))
}
ctx.setFillColor(amber)
ctx.fill(CGRect(x: lcd.maxX - 30 - 44 * 3 - 20, y: lcd.minY - 92, width: 44, height: 12))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("scritto", out)
