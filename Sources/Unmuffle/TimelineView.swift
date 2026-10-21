import SwiftUI

struct TimelineView: View {
    @EnvironmentObject var m: ProjectModel
    @State private var dragMode: DragMode = .none

    private enum DragMode { case none, seek, start, end }
    private let handleWidth: CGFloat = 40
    private let handleHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                Canvas { ctx, size in draw(ctx, size) }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in handleDrag(v, width: geo.size.width) }
                            .onEnded { _ in dragMode = .none }
                    )
            }
            .frame(height: 130)

            if m.removeSilence {
                GeometryReader { geo in
                    Canvas { ctx, size in drawStrip(ctx, size) }
                        .contentShape(Rectangle())
                        .onTapGesture { loc in
                            m.toggleSilence(at: time(at: loc.x, width: geo.size.width))
                        }
                }
                .frame(height: 20)
            }

        }
    }

    private func handleDrag(_ v: DragGesture.Value, width: CGFloat) {
        if dragMode == .none {
            let sx = v.startLocation.x
            let xs = x(m.trimStart, width), xe = x(m.trimEnd, width)
            let onTab = v.startLocation.y <= handleHeight + 4
            if onTab && abs(sx - xs) <= handleWidth / 2 + 2 { dragMode = .start }
            else if onTab && abs(sx - xe) <= handleWidth / 2 + 2 { dragMode = .end }
            else if abs(sx - xs) <= 6 { dragMode = .start }
            else if abs(sx - xe) <= 6 { dragMode = .end }
            else { dragMode = .seek }
        }
        let t = time(at: v.location.x, width: width)
        switch dragMode {
        case .start: m.trimStart = min(max(0, t), m.trimEnd - 0.1)
        case .end: m.trimEnd = max(min(m.duration, t), m.trimStart + 0.1)
        case .seek: m.seek(to: t)
        case .none: break
        }
    }

    /// Horizontal margin so a trim handle is always fully visible and centered on its line.
    private var inset: CGFloat { handleWidth / 2 }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        let plotW = max(width - 2 * inset, 1)
        return min(max(Double((x - inset) / plotW), 0), 1) * m.duration
    }
    private func x(_ t: Double, _ w: CGFloat) -> CGFloat {
        inset + CGFloat(t / max(m.duration, 0.001)) * (w - 2 * inset)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let top = handleHeight + 2
        let mid = top + (h - top) / 2
        let plot = CGRect(x: inset, y: top, width: w - 2 * inset, height: h - top)
        ctx.fill(Path(roundedRect: plot, cornerRadius: 6), with: .color(Color.gray.opacity(0.22)))
        let peaks = m.peaks
        guard !peaks.isEmpty, m.duration > 0 else { return }

        let xs = x(m.trimStart, w), xe = x(m.trimEnd, w)

        let plotW = max(w - 2 * inset, 1)
        let cols = max(Int(plotW), 1)
        let halfH = (h - top) / 2 - 4
        func columns(_ src: [Float]) -> [CGFloat] {
            var out = [CGFloat](repeating: 0, count: cols)
            guard !src.isEmpty else { return out }
            for c in 0..<cols {
                let i0 = Int(Double(c) / Double(cols) * Double(src.count))
                let i1 = max(i0 + 1, Int(Double(c + 1) / Double(cols) * Double(src.count)))
                var pk: Float = 0
                for i in i0..<min(i1, src.count) { pk = max(pk, src[i]) }
                out[c] = CGFloat(pk)
            }
            return out
        }
        /// Envelope as two lines: one along the peaks above the center, one mirrored below.
        func envelope(_ col: [CGFloat], scale: CGFloat = 1) -> Path {
            var path = Path()
            guard cols > 0 else { return path }
            for c in 0..<cols {
                let amp = min(col[c] * scale, 1) * halfH
                let pt = CGPoint(x: inset + CGFloat(c) + 0.5, y: mid - amp)
                if c == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            for c in 0..<cols {
                let amp = min(col[c] * scale, 1) * halfH
                let pt = CGPoint(x: inset + CGFloat(c) + 0.5, y: mid + amp)
                if c == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            return path
        }
        let original = columns(peaks)
        let neutral = m.settings.filterString() == "anull"
        if neutral {
            ctx.stroke(envelope(original), with: .color(Color.accentColor), lineWidth: 1)
        } else {
            // Original in gray, processed in blue.
            ctx.stroke(envelope(original), with: .color(Color.gray.opacity(0.8)), lineWidth: 1)
            if m.processedPeaks.isEmpty {
                let gainDB = (m.settings.volumeEnabled && !m.settings.loudnorm) ? m.settings.gain : 0
                ctx.stroke(envelope(original, scale: CGFloat(pow(10, gainDB / 20))),
                           with: .color(Color.accentColor), lineWidth: 1)
            } else {
                ctx.stroke(envelope(columns(m.processedPeaks)), with: .color(Color.accentColor), lineWidth: 1)
            }
        }

        if m.removeSilence {
            for s in m.silences where s.remove {
                let r = CGRect(x: x(s.start, w), y: top, width: max(x(s.end, w) - x(s.start, w), 1), height: h - top)
                ctx.fill(Path(r), with: .color(Color.red.opacity(0.35)))
            }
        }

        ctx.fill(Path(CGRect(x: inset, y: top, width: xs - inset, height: h - top)), with: .color(Color.black.opacity(0.5)))
        ctx.fill(Path(CGRect(x: xe, y: top, width: w - inset - xe, height: h - top)), with: .color(Color.black.opacity(0.5)))

        // Trim handles: a scissors tab on top of each yellow line.
        let scissors = ctx.resolve(Text(Image(systemName: "scissors")).font(.system(size: 15, weight: .bold)).foregroundColor(.black))
        for (tx, isStart) in [(xs, true), (xe, false)] {
            var p = Path(); p.move(to: CGPoint(x: tx, y: 0)); p.addLine(to: CGPoint(x: tx, y: h))
            ctx.stroke(p, with: .color(.yellow), lineWidth: 2)
            let tab = CGRect(x: tx - handleWidth / 2, y: 0, width: handleWidth, height: handleHeight)
            ctx.fill(Path(roundedRect: tab, cornerRadius: 6), with: .color(.yellow))
            var icon = ctx
            icon.translateBy(x: tab.midX, y: tab.midY)
            icon.scaleBy(x: isStart ? 1 : -1, y: 1)
            icon.draw(scissors, at: .zero, anchor: .center)
        }

        let px = x(m.currentTime, w)
        var ph = Path(); ph.move(to: CGPoint(x: px, y: top)); ph.addLine(to: CGPoint(x: px, y: h))
        ctx.stroke(ph, with: .color(.white), lineWidth: 1.5)
    }

    private func drawStrip(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        ctx.fill(Path(roundedRect: CGRect(x: inset, y: 0, width: w - 2 * inset, height: h), cornerRadius: 4),
                 with: .color(Color.gray.opacity(0.22)))
        guard m.duration > 0 else { return }
        for s in m.silences {
            let r = CGRect(x: x(s.start, w), y: 2, width: max(x(s.end, w) - x(s.start, w), 2), height: h - 4)
            let color: Color = s.remove ? .red : .gray.opacity(0.5)
            ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(color))
        }
    }
}
