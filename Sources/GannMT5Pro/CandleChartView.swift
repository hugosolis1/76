import SwiftUI

// MARK: - Main Chart View

struct CandleChartView: View {
    @ObservedObject var vm: ChartViewModel
    @State private var crosshair: CGPoint? = nil
    @State private var crosshairDate: Date? = nil
    @State private var crosshairPrice: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: "#0d1117")

                // ── Chart canvas
                Canvas { ctx, size in
                    guard !vm.candles.isEmpty else { return }
                    drawBackground(ctx, size)
                    drawPriceGrid(ctx, size)
                    drawTimeGrid(ctx, size)
                    if vm.showSq9    { drawSq9Levels(ctx, size) }
                    if vm.showRetro  { drawRetroStations(ctx, size) }
                    if vm.showMoon   { drawMoonCrossings(ctx, size) }
                    if vm.showWavy   { drawWavyLines(ctx, size) }
                    drawCandles(ctx, size)
                    drawVolume(ctx, size)
                    if let _ = crosshair { drawCrosshair(ctx, size) }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            crosshair = v.location
                            let (d, p) = coordsAt(v.location, size: geo.size)
                            crosshairDate  = d
                            crosshairPrice = p
                        }
                        .onEnded { v in
                            let (d, p) = coordsAt(v.location, size: geo.size)
                            vm.tapChart(date: d, price: p)
                            DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                                crosshair = nil
                            }
                        }
                )

                // ── Crosshair labels
                if let _ = crosshair, let d = crosshairDate {
                    VStack {
                        Spacer()
                        HStack {
                            Text(vm.formatDate(d))
                                .font(.caption2.monospaced())
                                .foregroundColor(Color(hex: "#f0883e"))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(hex: "#1a1f2c"))
                                .cornerRadius(4)
                            Spacer()
                            Text(vm.formatPrice(crosshairPrice))
                                .font(.caption2.monospaced())
                                .foregroundColor(Color(hex: "#f0883e"))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(hex: "#1a1f2c"))
                                .cornerRadius(4)
                        }
                        .padding(.horizontal, 8).padding(.bottom, 4)
                    }
                }

                // ── Wavy builder indicator
                if vm.wavyBuildMode {
                    VStack {
                        HStack {
                            Image(systemName: "pencil.line")
                                .foregroundColor(Color(hex: "#ff4444"))
                            Text("Modo Wavy Builder — Toca P1")
                                .font(.caption.monospaced())
                                .foregroundColor(Color(hex: "#ff4444"))
                            Spacer()
                            Button("✕") { vm.cancelWavyBuild() }
                                .foregroundColor(.white)
                        }
                        .padding(8)
                        .background(Color(hex: "#1a1f2c").opacity(0.9))
                        .cornerRadius(8)
                        .padding(8)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Coordinate helpers
    func xFor(_ idx: Int, size: CGSize) -> CGFloat {
        let range  = vm.visibleRange
        let count  = range.upperBound - range.lowerBound + 1
        let margin = 50.0 as CGFloat
        let w      = size.width - margin
        return margin + CGFloat(idx - range.lowerBound) / CGFloat(count) * w
    }

    func yFor(_ price: Double, size: CGSize) -> CGFloat {
        let pMin = vm.priceRange.lowerBound
        let pMax = vm.priceRange.upperBound
        let h    = size.height - 30.0
        return CGFloat(1.0 - (price - pMin) / (pMax - pMin)) * h
    }

    func coordsAt(_ pt: CGPoint, size: CGSize) -> (Date, Double) {
        let range  = vm.visibleRange
        let count  = range.upperBound - range.lowerBound + 1
        let margin = 50.0 as CGFloat
        let w      = size.width - margin
        let idx    = range.lowerBound + Int((pt.x - margin) / w * CGFloat(count))
        let safeIdx = max(range.lowerBound, min(range.upperBound, idx))
        let date   = vm.candles[safeIdx].time

        let pMin   = vm.priceRange.lowerBound
        let pMax   = vm.priceRange.upperBound
        let h      = Double(size.height - 30)
        let price  = pMax - (Double(pt.y) / h) * (pMax - pMin)

        return (date, price)
    }

    // MARK: - Draw background
    func drawBackground(_ ctx: GraphicsContext, _ size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(Color(hex: "#0d1117")))
    }

    // MARK: - Price grid
    func drawPriceGrid(_ ctx: GraphicsContext, _ size: CGSize) {
        let pMin  = vm.priceRange.lowerBound
        let pMax  = vm.priceRange.upperBound
        let steps = 8
        let step  = (pMax - pMin) / Double(steps)
        var style = StrokeStyle(lineWidth: 0.3)

        for i in 0...steps {
            let p = pMin + Double(i) * step
            let y = yFor(p, size: size)
            var path = Path(); path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(path, with: .color(Color(hex: "#21262d")), style: style)

            let label = vm.formatPrice(p)
            ctx.draw(Text(label).font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(hex: "#8b949e")),
                      at: CGPoint(x: 24, y: y))
        }
    }

    // MARK: - Time grid
    func drawTimeGrid(_ ctx: GraphicsContext, _ size: CGSize) {
        let range = vm.visibleRange
        let count = range.upperBound - range.lowerBound + 1
        let step  = max(1, count / 8)
        for i in stride(from: range.lowerBound, through: range.upperBound, by: step) {
            let x = xFor(i, size: size)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height - 20))
            ctx.stroke(path, with: .color(Color(hex: "#21262d")),
                        style: StrokeStyle(lineWidth: 0.3))
            let label = vm.formatDate(vm.candles[i].time)
            ctx.draw(Text(label).font(.system(size: 8, design: .monospaced))
                        .foregroundColor(Color(hex: "#8b949e")),
                      at: CGPoint(x: x, y: size.height - 10))
        }
    }

    // MARK: - Candles
    func drawCandles(_ ctx: GraphicsContext, _ size: CGSize) {
        let range  = vm.visibleRange
        let count  = range.upperBound - range.lowerBound + 1
        let cWidth = max(1.0, (size.width - 50) / CGFloat(count) * 0.7) as CGFloat

        for i in range {
            let c  = vm.candles[i]
            let x  = xFor(i, size: size)
            let yH = yFor(c.high,  size: size)
            let yL = yFor(c.low,   size: size)
            let yO = yFor(c.open,  size: size)
            let yC = yFor(c.close, size: size)
            let color = c.isBullish ? Color(hex: "#3fb950") : Color(hex: "#f85149")

            // Wick
            var wick = Path()
            wick.move(to: CGPoint(x: x, y: yH))
            wick.addLine(to: CGPoint(x: x, y: yL))
            ctx.stroke(wick, with: .color(color), style: StrokeStyle(lineWidth: 0.8))

            // Body
            let bodyTop    = min(yO, yC)
            let bodyBottom = max(yO, yC)
            let bodyH      = max(1.0, bodyBottom - bodyTop)
            let body = Path(CGRect(x: x - cWidth/2, y: bodyTop,
                                    width: cWidth, height: bodyH))
            ctx.fill(body, with: .color(color))
        }
    }

    // MARK: - Volume bars
    func drawVolume(_ ctx: GraphicsContext, _ size: CGSize) {
        guard vm.showVolume else { return }
        let range  = vm.visibleRange
        let count  = range.upperBound - range.lowerBound + 1
        let maxVol = vm.candles[range].map(\.volume).max() ?? 1
        let cWidth = max(1.0, (size.width - 50) / CGFloat(count) * 0.7) as CGFloat
        let maxH   = size.height * 0.12

        for i in range {
            let c   = vm.candles[i]
            let x   = xFor(i, size: size)
            let h   = CGFloat(c.volume / maxVol) * maxH
            let rect = CGRect(x: x - cWidth/2, y: size.height - 20 - h,
                               width: cWidth, height: h)
            let color = c.isBullish ? Color(hex: "#3fb950").opacity(0.3)
                                     : Color(hex: "#f85149").opacity(0.3)
            ctx.fill(Path(rect), with: .color(color))
        }
    }

    // MARK: - Sq9 levels
    func drawSq9Levels(_ ctx: GraphicsContext, _ size: CGSize) {
        for level in vm.sq9Levels {
            let p = level.price
            guard p >= vm.priceRange.lowerBound,
                  p <= vm.priceRange.upperBound else { continue }
            let y = yFor(p, size: size)
            var path = Path()
            path.move(to: CGPoint(x: 50, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            let lw = CGFloat(level.lineWidth)
            let dash: [CGFloat] = level.potency == .high ? [] : [4, 3]
            ctx.stroke(path, with: .color(Color(hex: level.color).opacity(0.6)),
                        style: StrokeStyle(lineWidth: lw, dash: dash))
            ctx.draw(Text(vm.formatPrice(p)).font(.system(size: 8, design: .monospaced))
                        .foregroundColor(Color(hex: level.color)),
                      at: CGPoint(x: size.width - 40, y: y - 5))
        }
    }

    // MARK: - Retro stations
    func drawRetroStations(_ ctx: GraphicsContext, _ size: CGSize) {
        for s in vm.stations {
            guard let idx = vm.candles.firstIndex(where: {
                Calendar.current.isDate($0.time, inSameDayAs: s.date)
            }) else { continue }
            guard idx >= vm.visibleRange.lowerBound,
                  idx <= vm.visibleRange.upperBound else { continue }
            let x = xFor(idx, size: size)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height - 20))
            ctx.stroke(path, with: .color(Color(hex: s.color).opacity(0.7)),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            ctx.draw(Text(s.label).font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: s.color)),
                      at: CGPoint(x: x, y: 10))
        }
    }

    // MARK: - Moon crossings
    func drawMoonCrossings(_ ctx: GraphicsContext, _ size: CGSize) {
        for cross in vm.moonCrossings {
            guard let idx = vm.candles.firstIndex(where: {
                Calendar.current.isDate($0.time, inSameDayAs: cross.date)
            }) else { continue }
            guard idx >= vm.visibleRange.lowerBound,
                  idx <= vm.visibleRange.upperBound else { continue }
            let x = xFor(idx, size: size)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height - 20))
            ctx.stroke(path, with: .color(Color(hex: cross.color).opacity(0.5)),
                        style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
            ctx.draw(Text("☽").font(.system(size: 8))
                        .foregroundColor(Color(hex: "#aaaacc")),
                      at: CGPoint(x: x, y: 22))
        }
    }

    // MARK: - Wavy Lines
    func drawWavyLines(_ ctx: GraphicsContext, _ size: CGSize) {
        for config in vm.wavyLines where config.visible {
            if config.showHarmonics {
                let harmonicSets = vm.allWavyHarmonics(config)
                for set in harmonicSets {
                    drawWavyPath(set.points, color: set.color,
                                  lw: set.multiplier == 1.0 ? 2.0 : 0.8,
                                  dashed: set.multiplier != 1.0,
                                  ctx: ctx, size: size)
                }
            } else {
                let pts = vm.wavyPointsFor(config)
                drawWavyPath(pts, color: config.color, lw: config.lineWidth,
                              dashed: false, ctx: ctx, size: size)
            }

            // Anchor marker
            if let idx = vm.candles.firstIndex(where: {
                Calendar.current.isDate($0.time, inSameDayAs: config.anchorDate)
            }), idx >= vm.visibleRange.lowerBound, idx <= vm.visibleRange.upperBound {
                let x = xFor(idx, size: size)
                let y = yFor(config.anchorPrice, size: size)
                let r: CGFloat = 5
                ctx.fill(Path(ellipseIn: CGRect(x: x-r, y: y-r, width: 2*r, height: 2*r)),
                          with: .color(Color(hex: config.color)))
                ctx.draw(Text(config.name).font(.system(size: 8, design: .monospaced))
                            .foregroundColor(Color(hex: config.color)),
                          at: CGPoint(x: x+8, y: y))
            }
        }
    }

    func drawWavyPath(_ pts: [WavyPoint], color: String, lw: CGFloat,
                       dashed: Bool, ctx: GraphicsContext, size: CGSize) {
        var path = Path()
        var first = true
        for pt in pts {
            guard let idx = vm.candles.firstIndex(where: {
                Calendar.current.isDate($0.time, inSameDayAs: pt.date)
            }) else { continue }
            guard idx >= vm.visibleRange.lowerBound,
                  idx <= vm.visibleRange.upperBound else { continue }
            let x = xFor(idx, size: size)
            let y = yFor(pt.price, size: size)
            if first { path.move(to: CGPoint(x: x, y: y)); first = false }
            else      { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        let dash: [CGFloat] = dashed ? [6, 4] : []
        ctx.stroke(path, with: .color(Color(hex: color)),
                    style: StrokeStyle(lineWidth: lw, dash: dash))
    }

    // MARK: - Crosshair
    func drawCrosshair(_ ctx: GraphicsContext, _ size: CGSize) {
        guard let pt = crosshair else { return }
        let color = Color(hex: "#f0883e").opacity(0.6)
        var h = Path(); h.move(to: CGPoint(x: 0, y: pt.y))
        h.addLine(to: CGPoint(x: size.width, y: pt.y))
        var v = Path(); v.move(to: CGPoint(x: pt.x, y: 0))
        v.addLine(to: CGPoint(x: pt.x, y: size.height))
        ctx.stroke(h, with: .color(color), style: StrokeStyle(lineWidth: 0.5, dash: [4,3]))
        ctx.stroke(v, with: .color(color), style: StrokeStyle(lineWidth: 0.5, dash: [4,3]))
    }
}

// MARK: - Color extension
extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3: (a,r,g,b) = (255,(int>>8)*17,(int>>4&0xF)*17,(int&0xF)*17)
        case 6: (a,r,g,b) = (255,int>>16,int>>8&0xFF,int&0xFF)
        case 8: (a,r,g,b) = (int>>24,int>>16&0xFF,int>>8&0xFF,int&0xFF)
        default:(a,r,g,b) = (255,0,0,0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255,
                   blue: Double(b)/255, opacity: Double(a)/255)
    }
}
