import CoreGraphics
import IslandCore

/// The agent logos exactly as the design draws them. The droplet is 11 pt
/// wide, so the difference between a stand-in shape and the real logo is
/// plainly visible at that size.
@MainActor
enum DesignMark {
    struct PaintedPart {
        let path: CGPath
        let fill: CGColor?
    }

    private static var cache: [AgentKindOption: [PaintedPart]] = [:]

    static func parts(for kind: AgentKindOption) -> [PaintedPart] {
        if let cached = cache[kind] { return cached }
        guard let source = DesignMarkData.all[kind.rawValue] else { return [] }
        let parts = source.map { part in
            let path = CGMutablePath()
            path.addPath(SVGPathParser.parse(part.path), transform: part.transform)
            return PaintedPart(path: path, fill: part.fill.flatMap(color(hex:)))
        }
        cache[kind] = parts
        return parts
    }

    private static func color(hex: String) -> CGColor? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("#") else { return nil }
        text.removeFirst()
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return CGColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Minimal SVG path parser for the design's 24x24 icon sprite. It covers the
/// commands those symbols use: M/L/H/V/C/A/Z and their relative forms.
private enum SVGPathParser {
    static func parse(_ source: String) -> CGPath {
        var scanner = Scanner(source)
        let path = CGMutablePath()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var active: Character?

        while true {
            scanner.skipSeparators()
            guard !scanner.isAtEnd else { break }
            if let ch = scanner.peek(), ch.isLetter {
                active = ch
                scanner.advance()
                scanner.skipSeparators()
            } else if active == nil {
                break
            }
            guard let command = active else { break }
            let relative = command.isLowercase

            switch command.lowercased() {
            case "m":
                var first = true
                while scanner.hasNumber() {
                    let value = scanner.vector()
                    let destination = relative
                        ? CGPoint(x: current.x + value.x, y: current.y + value.y)
                        : value
                    if first {
                        path.move(to: destination)
                        subpathStart = destination
                        first = false
                    } else {
                        path.addLine(to: destination)
                    }
                    current = destination
                }

            case "l":
                while scanner.hasNumber() {
                    let value = scanner.vector()
                    let destination = relative
                        ? CGPoint(x: current.x + value.x, y: current.y + value.y)
                        : value
                    path.addLine(to: destination)
                    current = destination
                }

            case "h":
                while scanner.hasNumber() {
                    let value = scanner.number()
                    let destination = CGPoint(
                        x: relative ? current.x + value : value,
                        y: current.y
                    )
                    path.addLine(to: destination)
                    current = destination
                }

            case "v":
                while scanner.hasNumber() {
                    let value = scanner.number()
                    let destination = CGPoint(
                        x: current.x,
                        y: relative ? current.y + value : value
                    )
                    path.addLine(to: destination)
                    current = destination
                }

            case "c":
                while scanner.hasNumber() {
                    let c1 = scanner.vector()
                    let c2 = scanner.vector()
                    let end = scanner.vector()
                    let control1 = relative
                        ? CGPoint(x: current.x + c1.x, y: current.y + c1.y)
                        : c1
                    let control2 = relative
                        ? CGPoint(x: current.x + c2.x, y: current.y + c2.y)
                        : c2
                    let destination = relative
                        ? CGPoint(x: current.x + end.x, y: current.y + end.y)
                        : end
                    path.addCurve(to: destination, control1: control1, control2: control2)
                    current = destination
                }

            case "a":
                while scanner.hasNumber() {
                    let rx = scanner.number()
                    let ry = scanner.number()
                    let rotation = scanner.number()
                    let largeArc = scanner.flag()
                    let sweep = scanner.flag()
                    let end = scanner.vector()
                    let destination = relative
                        ? CGPoint(x: current.x + end.x, y: current.y + end.y)
                        : end
                    appendArc(
                        to: path,
                        from: current,
                        rx: rx,
                        ry: ry,
                        rotationDegrees: rotation,
                        largeArc: largeArc,
                        sweep: sweep,
                        to: destination
                    )
                    current = destination
                }

            case "z":
                path.closeSubpath()
                current = subpathStart

            default:
                // No other commands appear in the sprite; consume nothing.
                active = nil
            }
        }

        return path
    }

    private static func appendArc(
        to path: CGMutablePath,
        from start: CGPoint,
        rx rawRx: CGFloat,
        ry rawRy: CGFloat,
        rotationDegrees: CGFloat,
        largeArc: Bool,
        sweep: Bool,
        to end: CGPoint
    ) {
        var rx = abs(rawRx)
        var ry = abs(rawRy)
        guard rx > 1e-9, ry > 1e-9, start != end else {
            path.addLine(to: end)
            return
        }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let halfX = (start.x - end.x) / 2
        let halfY = (start.y - end.y) / 2
        let x1p = cosPhi * halfX + sinPhi * halfY
        let y1p = -sinPhi * halfX + cosPhi * halfY

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }

        let rx2 = rx * rx
        let ry2 = ry * ry
        let numerator = max(0, rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p)
        let denominator = rx2 * y1p * y1p + ry2 * x1p * x1p
        var coefficient = denominator > 1e-12 ? sqrt(numerator / denominator) : 0
        if largeArc == sweep { coefficient = -coefficient }

        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func signedAngle(ux: CGFloat, uy: CGFloat, vx: CGFloat, vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let lengths = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            guard lengths > 1e-12 else { return 0 }
            var angle = acos(min(max(dot / lengths, -1), 1))
            if ux * vy - uy * vx < 0 { angle = -angle }
            return angle
        }

        let startVectorX = (x1p - cxp) / rx
        let startVectorY = (y1p - cyp) / ry
        let endVectorX = (-x1p - cxp) / rx
        let endVectorY = (-y1p - cyp) / ry
        let theta1 = signedAngle(ux: 1, uy: 0, vx: startVectorX, vy: startVectorY)
        var delta = signedAngle(
            ux: startVectorX,
            uy: startVectorY,
            vx: endVectorX,
            vy: endVectorY
        )
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let segmentCount = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let segmentAngle = delta / CGFloat(segmentCount)
        let handle = 4.0 / 3.0 * tan(segmentAngle / 4)

        var theta = theta1
        var point = start
        for _ in 0..<segmentCount {
            let nextTheta = theta + segmentAngle
            let cos1 = cos(theta)
            let sin1 = sin(theta)
            let cos2 = cos(nextTheta)
            let sin2 = sin(nextTheta)

            func ellipsePoint(cosine: CGFloat, sine: CGFloat) -> CGPoint {
                CGPoint(
                    x: cx + cosPhi * rx * cosine - sinPhi * ry * sine,
                    y: cy + sinPhi * rx * cosine + cosPhi * ry * sine
                )
            }

            func ellipseDerivative(cosine: CGFloat, sine: CGFloat) -> CGPoint {
                CGPoint(
                    x: -rx * sine * cosPhi - ry * cosine * sinPhi,
                    y: -rx * sine * sinPhi + ry * cosine * cosPhi
                )
            }

            let destination = ellipsePoint(cosine: cos2, sine: sin2)
            let d1 = ellipseDerivative(cosine: cos1, sine: sin1)
            let d2 = ellipseDerivative(cosine: cos2, sine: sin2)
            let control1 = CGPoint(x: point.x + handle * d1.x, y: point.y + handle * d1.y)
            let control2 = CGPoint(x: destination.x - handle * d2.x, y: destination.y - handle * d2.y)
            path.addCurve(to: destination, control1: control1, control2: control2)
            theta = nextTheta
            point = destination
        }
    }

    private struct Scanner {
        private let characters: [Character]
        private var index = 0

        init(_ source: String) {
            characters = Array(source)
        }

        var isAtEnd: Bool { index >= characters.count }

        func peek() -> Character? {
            index < characters.count ? characters[index] : nil
        }

        mutating func advance() {
            index += 1
        }

        mutating func skipSeparators() {
            while let ch = peek(), ch == " " || ch == "," || ch == "\n" || ch == "\t" || ch == "\r" {
                index += 1
            }
        }

        mutating func hasNumber() -> Bool {
            skipSeparators()
            guard let ch = peek() else { return false }
            return ch.isNumber || ch == "-" || ch == "+" || ch == "."
        }

        mutating func number() -> CGFloat {
            skipSeparators()
            var text = ""
            if let ch = peek(), ch == "-" || ch == "+" {
                text.append(ch)
                index += 1
            }
            while let ch = peek(), ch.isNumber {
                text.append(ch)
                index += 1
            }
            if peek() == "." {
                text.append(".")
                index += 1
                while let ch = peek(), ch.isNumber {
                    text.append(ch)
                    index += 1
                }
            }
            if let ch = peek(), ch == "e" || ch == "E" {
                text.append(ch)
                index += 1
                if let sign = peek(), sign == "-" || sign == "+" {
                    text.append(sign)
                    index += 1
                }
                while let ch = peek(), ch.isNumber {
                    text.append(ch)
                    index += 1
                }
            }
            return CGFloat(Double(text) ?? 0)
        }

        mutating func vector() -> CGPoint {
            CGPoint(x: number(), y: number())
        }

        mutating func flag() -> Bool {
            skipSeparators()
            guard let ch = peek() else { return false }
            index += 1
            return ch == "1"
        }
    }
}
