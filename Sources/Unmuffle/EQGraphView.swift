import SwiftUI

/// Eight draggable gain points on a log-frequency graph, plus two edge handles for the
/// low cut (rumble) and high cut (hiss). Cropped regions are shaded and the curve shows
/// the real 2nd-order roll-off.
struct EQGraphView: View {
    @Binding var gains: [Double]
    @Binding var highpass: Double   // Hz, 0 = off
    @Binding var lowpass: Double    // Hz, 0 = off

    @State private var drag: Drag?
    private enum Drag { case point(Int), low, high }

    let range: Double = 12
    private let bands = AudioSettings.eqBands
    private let fMin = log10(20.0), fMax = log10(20000.0)
    private let inset: CGFloat = 14
    private let labelHeight: CGFloat = 18
    private let handleW: CGFloat = 16, handleH: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in draw(ctx, size) }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in onDrag(v, size: geo.size) }
                        .onEnded { _ in drag = nil }
                )
                .onTapGesture(count: 2) { loc in
                    if let i = nearestPoint(loc.x, width: geo.size.width) { gains[i] = 0 }
                }
        }
        .frame(height: 210)
    }

    // MARK: Mapping

    private func xFor(_ hz: Double, _ w: CGFloat) -> CGFloat {
        inset + CGFloat((log10(max(hz, 20)) - fMin) / (fMax - fMin)) * (w - 2 * inset)
    }
    private func hzFor(_ x: CGFloat, _ w: CGFloat) -> Double {
        let t = min(max(Double((x - inset) / (w - 2 * inset)), 0), 1)
        return pow(10, fMin + t * (fMax - fMin))
    }
    private func plotHeight(_ h: CGFloat) -> CGFloat { h - labelHeight - handleH }
    private func yFor(_ g: Double, _ h: CGFloat) -> CGFloat {
        let ph = plotHeight(h)
        return handleH + ph / 2 - CGFloat(g / range) * (ph / 2 - inset)
    }
    private func gainFor(_ y: CGFloat, _ h: CGFloat) -> Double {
        let ph = plotHeight(h)
        let g = Double((handleH + ph / 2 - y) / (ph / 2 - inset)) * range
        return (min(range, max(-range, g)) * 2).rounded() / 2
    }
    private func nearestPoint(_ x: CGFloat, width: CGFloat) -> Int? {
        let d = bands.indices.map { (abs(xFor(bands[$0], width) - x), $0) }.min { $0.0 < $1.0 }
        guard let d, d.0 < 28 else { return nil }
        return d.1
    }
    private var lowX: (CGFloat) -> CGFloat { { w in self.highpass > 0 ? self.xFor(self.highpass, w) : self.inset } }
    private var highX: (CGFloat) -> CGFloat { { w in self.lowpass > 0 ? self.xFor(self.lowpass, w) : w - self.inset } }

    // MARK: Interaction

    private func onDrag(_ v: DragGesture.Value, size: CGSize) {
        let w = size.width, h = size.height
        if drag == nil {
            let sx = v.startLocation.x, sy = v.startLocation.y
            let onHandleRow = sy <= handleH + 6
            if onHandleRow && abs(sx - lowX(w)) <= handleW { drag = .low }
            else if onHandleRow && abs(sx - highX(w)) <= handleW { drag = .high }
            else if let i = nearestPoint(sx, width: w) { drag = .point(i) }
            else { return }
        }
        switch drag {
        case .point(let i):
            gains[i] = gainFor(v.location.y, h)
        case .low:
            let hz = hzFor(v.location.x, w)
            highpass = v.location.x <= inset + 4 ? 0 : hz
            if lowpass > 0 && highpass >= lowpass * 0.8 { highpass = lowpass * 0.8 }
        case .high:
            let hz = hzFor(v.location.x, w)
            lowpass = v.location.x >= w - inset - 4 ? 0 : hz
            if highpass > 0 && lowpass <= highpass * 1.25 { lowpass = highpass * 1.25 }
        case .none: break
        }
    }

    // MARK: Response

    /// Smooth (monotone cubic) interpolation of the band gains in log-frequency.
    private func bandGain(atLogF lf: Double) -> Double {
        let xs = bands.map { log10($0) }
        if lf <= xs[0] { return gains[0] }
        if lf >= xs[xs.count - 1] { return gains[gains.count - 1] }
        let n = xs.count
        var m = [Double](repeating: 0, count: n)
        var d = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) { d[i] = (gains[i + 1] - gains[i]) / (xs[i + 1] - xs[i]) }
        m[0] = d[0]; m[n - 1] = d[n - 2]
        for i in 1..<(n - 1) { m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2 }
        var i = 0
        while i < n - 2 && lf > xs[i + 1] { i += 1 }
        let hseg = xs[i + 1] - xs[i]
        let t = (lf - xs[i]) / hseg
        let h00 = 2 * t * t * t - 3 * t * t + 1, h10 = t * t * t - 2 * t * t + t
        let h01 = -2 * t * t * t + 3 * t * t, h11 = t * t * t - t * t
        return h00 * gains[i] + h10 * hseg * m[i] + h01 * gains[i + 1] + h11 * hseg * m[i + 1]
    }

    /// Total response including the 2nd-order low and high cuts, in dB.
    private func response(atLogF lf: Double) -> Double {
        var g = bandGain(atLogF: lf)
        let f = pow(10, lf)
        if highpass > 0 { g -= 10 * log10(1 + pow(highpass / f, 4)) }
        if lowpass > 0 { g -= 10 * log10(1 + pow(f / lowpass, 4)) }
        return max(g, -range * 1.6)
    }

    // MARK: Drawing

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let ph = plotHeight(h)
        // The gray plot spans exactly the frequency axis, so the cut tabs touch its edges when off.
        let plot = CGRect(x: inset, y: handleH, width: w - 2 * inset, height: ph)
        ctx.fill(Path(roundedRect: plot, cornerRadius: 6), with: .color(Color.gray.opacity(0.22)))

        for g in [-6.0, 0, 6] {
            var p = Path()
            let y = yFor(g, h)
            p.move(to: CGPoint(x: plot.minX, y: y)); p.addLine(to: CGPoint(x: plot.maxX, y: y))
            ctx.stroke(p, with: .color(.secondary.opacity(g == 0 ? 0.6 : 0.2)), lineWidth: g == 0 ? 1 : 0.5)
            ctx.draw(Text("\(g > 0 ? "+" : "")\(Int(g))").font(.system(size: 9)).foregroundColor(.secondary),
                     at: CGPoint(x: plot.maxX - 10, y: y - 7), anchor: .center)
        }

        // Response curve sampled across the axis, clipped to the plot.
        var curve = Path()
        let samples = max(Int(w), 2)
        for sIdx in 0...samples {
            let x = inset + CGFloat(sIdx) / CGFloat(samples) * (w - 2 * inset)
            let lf = fMin + Double((x - inset) / (w - 2 * inset)) * (fMax - fMin)
            let y = min(yFor(response(atLogF: lf), h), plot.maxY - 1)
            if sIdx == 0 { curve.move(to: CGPoint(x: x, y: y)) } else { curve.addLine(to: CGPoint(x: x, y: y)) }
        }
        var fill = curve
        fill.addLine(to: CGPoint(x: w - inset, y: yFor(0, h)))
        fill.addLine(to: CGPoint(x: inset, y: yFor(0, h)))
        fill.closeSubpath()
        ctx.fill(fill, with: .color(Color.accentColor.opacity(0.18)))
        ctx.stroke(curve, with: .color(Color.accentColor), lineWidth: 2)

        // Cropped regions and their handles.
        let lx = lowX(w), hx = highX(w)
        if highpass > 0 {
            ctx.fill(Path(CGRect(x: plot.minX, y: plot.minY, width: lx - plot.minX, height: ph)),
                     with: .color(Color.black.opacity(0.35)))
        }
        if lowpass > 0 {
            ctx.fill(Path(CGRect(x: hx, y: plot.minY, width: plot.maxX - hx, height: ph)),
                     with: .color(Color.black.opacity(0.35)))
        }
        for (x, hz, isLow) in [(lx, highpass, true), (hx, lowpass, false)] {
            var line = Path(); line.move(to: CGPoint(x: x, y: plot.minY)); line.addLine(to: CGPoint(x: x, y: plot.maxY))
            ctx.stroke(line, with: .color(.orange.opacity(hz > 0 ? 0.9 : 0.4)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            let tab = CGRect(x: x - handleW / 2, y: 0, width: handleW, height: handleH)
            ctx.fill(Path(roundedRect: tab, cornerRadius: 3), with: .color(hz > 0 ? .orange : .gray))
            let glyph = ctx.resolve(Text(Image(systemName: isLow ? "arrow.right.to.line" : "arrow.left.to.line"))
                .font(.system(size: 9, weight: .bold)).foregroundColor(.black))
            ctx.draw(glyph, at: CGPoint(x: tab.midX, y: tab.midY), anchor: .center)
            if hz > 0 {
                let label = hz >= 1000 ? String(format: "%.1fk", hz / 1000) : "\(Int(hz.rounded()))"
                ctx.draw(Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(.orange),
                         at: CGPoint(x: x + (isLow ? 4 : -4), y: plot.maxY - 8), anchor: isLow ? .leading : .trailing)
            }
        }

        // Band points and labels.
        for i in bands.indices {
            let c = CGPoint(x: xFor(bands[i], w), y: yFor(gains[i], h))
            let active: Bool = { if case .point(let d) = drag { return d == i }; return false }()
            let r: CGFloat = active ? 8 : 6
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(Color.accentColor))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(.white), lineWidth: 1.5)
            let label = bands[i] >= 1000 ? String(format: "%gk", bands[i] / 1000) : "\(Int(bands[i]))"
            ctx.draw(Text(label).font(.system(size: 10)).foregroundColor(.secondary),
                     at: CGPoint(x: c.x, y: plot.maxY + labelHeight / 2), anchor: .center)
            if abs(gains[i]) >= 0.25 || active {
                let txt = String(format: "%+.1f", gains[i])
                ctx.draw(Text(txt).font(.system(size: 10, weight: .medium)).foregroundColor(.primary),
                         at: CGPoint(x: c.x, y: c.y + (gains[i] >= 0 ? -16 : 16)), anchor: .center)
            }
        }
    }
}
