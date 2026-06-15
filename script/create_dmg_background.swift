import AppKit

let outputPath = CommandLine.arguments[1]
let width = 640
let height = 360
let scale = 2

guard let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: width * scale,
  pixelsHigh: height * scale,
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
) else {
  fatalError("Failed to create bitmap")
}

rep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

let bounds = NSRect(x: 0, y: 0, width: width, height: height)
let background = NSGradient(colors: [
  color(248, 251, 252),
  color(237, 246, 244)
])!
background.draw(in: bounds, angle: 92)

color(255, 255, 255, 0.62).setFill()
NSBezierPath(roundedRect: NSRect(x: 22, y: 22, width: 596, height: 316), xRadius: 30, yRadius: 30).fill()

color(41, 178, 146, 0.16).setFill()
NSBezierPath(ovalIn: NSRect(x: -76, y: 226, width: 230, height: 230)).fill()
color(70, 132, 220, 0.13).setFill()
NSBezierPath(ovalIn: NSRect(x: 492, y: -76, width: 230, height: 230)).fill()

let leftPlate = NSRect(x: 80, y: 88, width: 180, height: 180)
let rightPlate = NSRect(x: 380, y: 88, width: 180, height: 180)
for plate in [leftPlate, rightPlate] {
  color(255, 255, 255, 0.78).setFill()
  NSBezierPath(roundedRect: plate, xRadius: 28, yRadius: 28).fill()
  color(84, 103, 115, 0.08).setStroke()
  let outline = NSBezierPath(roundedRect: plate.insetBy(dx: 0.5, dy: 0.5), xRadius: 28, yRadius: 28)
  outline.lineWidth = 1
  outline.stroke()
}

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 286, y: 178))
arrow.line(to: NSPoint(x: 354, y: 178))
arrow.move(to: NSPoint(x: 334, y: 158))
arrow.line(to: NSPoint(x: 354, y: 178))
arrow.line(to: NSPoint(x: 334, y: 198))
color(38, 138, 124, 0.48).setStroke()
arrow.lineWidth = 8
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.stroke()

let chart = NSBezierPath()
chart.move(to: NSPoint(x: 68, y: 58))
chart.curve(to: NSPoint(x: 180, y: 54), controlPoint1: NSPoint(x: 102, y: 82), controlPoint2: NSPoint(x: 132, y: 30))
chart.curve(to: NSPoint(x: 304, y: 62), controlPoint1: NSPoint(x: 216, y: 74), controlPoint2: NSPoint(x: 258, y: 42))
chart.curve(to: NSPoint(x: 572, y: 52), controlPoint1: NSPoint(x: 390, y: 92), controlPoint2: NSPoint(x: 464, y: 24))
color(54, 167, 149, 0.22).setStroke()
chart.lineWidth = 3
chart.lineCapStyle = .round
chart.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
  fatalError("Failed to encode PNG")
}

try data.write(to: URL(fileURLWithPath: outputPath))
