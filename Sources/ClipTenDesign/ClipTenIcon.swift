import AppKit

public enum ClipTenIcon {
    public static func statusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            drawGlyph(
                in: CGRect(x: 2.25, y: 1.5, width: 13.5, height: 15),
                color: .black,
                lineWidth: 1.45
            )
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "ClipTen"
        return image
    }

    public static func appIconImage(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let tileRect = CGRect(
                x: size * 0.075,
                y: size * 0.085,
                width: size * 0.85,
                height: size * 0.85
            )
            let tile = NSBezierPath(
                roundedRect: tileRect,
                xRadius: size * 0.205,
                yRadius: size * 0.205
            )

            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
            shadow.shadowBlurRadius = size * 0.045
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.022)

            NSGraphicsContext.saveGraphicsState()
            shadow.set()

            NSColor(calibratedRed: 0.22, green: 0.29, blue: 0.94, alpha: 1).setFill()
            tile.fill()
            NSGraphicsContext.restoreGraphicsState()

            drawGlyph(
                in: CGRect(
                    x: size * 0.285,
                    y: size * 0.235,
                    width: size * 0.43,
                    height: size * 0.55
                ),
                color: .white,
                lineWidth: size * 0.044
            )
            return true
        }
    }

    private static func drawGlyph(in rect: CGRect, color: NSColor, lineWidth: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let boardRect = CGRect(
            x: rect.minX + rect.width * 0.08,
            y: rect.minY + rect.height * 0.055,
            width: rect.width * 0.84,
            height: rect.height * 0.86
        )
        let boardPath = CGPath(
            roundedRect: boardRect,
            cornerWidth: rect.width * 0.105,
            cornerHeight: rect.width * 0.105,
            transform: nil
        )
        context.addPath(boardPath)
        context.strokePath()

        let claspRect = CGRect(
            x: rect.minX + rect.width * 0.305,
            y: rect.minY + rect.height * 0.82,
            width: rect.width * 0.39,
            height: rect.height * 0.145
        )
        let claspPath = CGPath(
            roundedRect: claspRect,
            cornerWidth: rect.height * 0.0725,
            cornerHeight: rect.height * 0.0725,
            transform: nil
        )
        context.addPath(claspPath)
        context.fillPath()

        let lineStartX = rect.minX + rect.width * 0.27
        let lineYs = [0.61, 0.45, 0.29]
        let lineEnds = [0.73, 0.65, 0.57]
        for (y, end) in zip(lineYs, lineEnds) {
            context.move(to: CGPoint(x: lineStartX, y: rect.minY + rect.height * y))
            context.addLine(to: CGPoint(x: rect.minX + rect.width * end, y: rect.minY + rect.height * y))
            context.strokePath()
        }

        context.restoreGState()
    }
}
