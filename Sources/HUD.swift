import AppKit

let cream = NSColor(calibratedRed: 0.95, green: 0.935, blue: 0.905, alpha: 1)
let ember = NSColor(calibratedRed: 1, green: 0.77, blue: 0.49, alpha: 1)

final class HUDView: NSView {
    var activity = Activity(phase: .idle, detail: "Ready when you are") { didSet {
        needsDisplay = true
        setAccessibilityLabel("Codex Notch: \(activity.phase.title). \(activity.detail)")
    } }
    var demo = false
    var expanded = true
    var reduceMotion = false
    var glow: Double = 0.75
    var topInset: CGFloat = 32
    var minimumWidth: CGFloat = 210
    var preview = false
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    private var timer: Timer?
    private var currentWidth: CGFloat = 260
    private var currentHeight: CGFloat = 91
    private var began = Date()
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Codex Notch: ready")
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.needsDisplay = true
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    deinit { timer?.invalidate() }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(tracking!); super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return abs(local.x - bounds.midX) < currentWidth / 2 && local.y < currentHeight ? self : nil
    }
    func text(_ text: String, rect: NSRect, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular, alignment: NSTextAlignment = .center) {
        let style = NSMutableParagraphStyle(); style.alignment = alignment; style.lineBreakMode = .byTruncatingMiddle
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
    }
    override func draw(_ dirtyRect: NSRect) {
        if preview { cream.setFill(); bounds.fill() }
        let detailWidth = (activity.detail as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        let targetWidth: CGFloat = max(minimumWidth, expanded ? min(310, max(240, detailWidth + 40)) : 210)
        let targetHeight: CGFloat = topInset + (expanded ? 59 : 29)
        let easing: CGFloat = reduceMotion ? 1 : 0.18
        currentWidth += (targetWidth - currentWidth) * easing
        currentHeight += (targetHeight - currentHeight) * easing
        let x = bounds.midX - currentWidth / 2
        let w = currentWidth, h = currentHeight, shoulder: CGFloat = 14, radius: CGFloat = 20
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x - shoulder, y: 0))
        path.line(to: NSPoint(x: x + w + shoulder, y: 0))
        path.curve(to: NSPoint(x: x + w, y: shoulder), controlPoint1: NSPoint(x: x + w + 2, y: 0), controlPoint2: NSPoint(x: x + w, y: 4))
        path.line(to: NSPoint(x: x + w, y: h - radius))
        path.curve(to: NSPoint(x: x + w - radius, y: h), controlPoint1: NSPoint(x: x + w, y: h - 5), controlPoint2: NSPoint(x: x + w - 8, y: h))
        path.line(to: NSPoint(x: x + radius, y: h))
        path.curve(to: NSPoint(x: x, y: h - radius), controlPoint1: NSPoint(x: x + 8, y: h), controlPoint2: NSPoint(x: x, y: h - 5))
        path.line(to: NSPoint(x: x, y: shoulder))
        path.curve(to: NSPoint(x: x - shoulder, y: 0), controlPoint1: NSPoint(x: x, y: 4), controlPoint2: NSPoint(x: x - 2, y: 0))
        path.close()
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.14); shadow.shadowBlurRadius = 14; shadow.shadowOffset = NSSize(width: 0, height: -5); shadow.set()
        NSColor.black.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        // The physical camera notch occupies topInset. All content stays below it.
        let t = reduceMotion ? 1.0 : Date().timeIntervalSince(began)
        let expandAmount = max(0, min(1, (currentHeight - topInset - 29) / 30))
        if expandAmount > 0.1 {
            text(activity.detail, rect: NSRect(x: x + 20, y: topInset + 3, width: w - 40, height: 18), size: 13, color: NSColor.white.withAlphaComponent(0.52 * expandAmount))
        }
        let baseline = topInset + 4 + 22 * expandAmount
        let title = activity.phase.title
        let titleWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium)]).width
        let rowWidth = titleWidth + 28
        let left = bounds.midX - rowWidth / 2
        drawPixels(at: NSPoint(x: left, y: baseline + 2), time: t)
        text(title, rect: NSRect(x: left + 28, y: baseline, width: titleWidth + 2, height: 22), size: 16, color: cream, weight: .medium, alignment: .left)
    }
    func drawPixels(at point: NSPoint, time: Double) {
        let phase = activity.phase
        let color = phase == .complete ? NSColor(calibratedRed: 0.71, green: 0.95, blue: 0.74, alpha: 1) : ember
        let speed: Double = phase == .building ? 2.8 : 1.6
        for row in 0..<4 {
            for col in 0..<4 {
                let distance = hypot(Double(col) - 1.5, Double(row) - 1.5)
                let wave: Double
                switch phase {
                case .reading: wave = sin(time * 4.2 - Double(row) * 1.1)
                case .building: wave = sin(time * speed + Double(row + col) * 1.3)
                case .answering: wave = sin(time * 3.4 - Double(col) * 1.0)
                case .complete: wave = 0.75
                case .idle, .waiting: wave = sin(time * 1.5) * 0.2 - distance * 0.12
                default: wave = sin(time * 2.4 - distance * 2.1)
                }
                let alpha = 0.26 + (wave + 1) * 0.34
                let rect = NSRect(x: point.x + CGFloat(col) * 4.1, y: point.y + CGFloat(row) * 4.1, width: 3.9, height: 3.9)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow(); shadow.shadowColor = color.withAlphaComponent(glow * alpha); shadow.shadowBlurRadius = 5 + 8 * glow; shadow.shadowOffset = .zero; shadow.set()
                color.withAlphaComponent(alpha).setFill(); rect.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
