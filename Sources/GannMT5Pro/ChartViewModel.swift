import Foundation
import Combine
import SwiftUI

@MainActor
public final class ChartViewModel: ObservableObject {

    // ── Data
    @Published public var candles: [Candle]    = []
    @Published public var symbol: String       = "R_75"
    @Published public var timeframe: Timeframe = .d1

    // ── Overlays
    @Published public var wavyLines: [WavyConfig]       = []
    @Published public var stations: [Station]            = []
    @Published public var moonCrossings: [MoonCrossing] = []
    @Published public var sq9Levels: [Sq9Level]          = []
    @Published public var verticalLines: [VerticalLine]  = []

    // ── Visibility toggles
    @Published public var showSq9      = true
    @Published public var showRetro    = true
    @Published public var showMoon     = true
    @Published public var showWavy     = true
    @Published public var showVolume   = true

    // ── Chart range
    @Published public var visibleRange: ClosedRange<Int> = 0...200
    @Published public var priceRange:   ClosedRange<Double> = 0...1

    // ── Inspector
    @Published public var inspection: PointInspection? = nil
    @Published public var showInspector = false

    // ── Wavy builder
    @Published public var wavyBuildMode = false
    @Published public var wavyBuildP1: (date: Date, price: Double)? = nil
    @Published public var wavyBuildP2: (date: Date, price: Double)? = nil
    @Published public var wavyBuildPlanet: String = "Marte"
    @Published public var wavyBuildDirection: WavyDirection = .resta
    @Published public var wavyBuildFC: Double = 0
    @Published public var wavyBuildName: String = "Wavy 1"
    @Published public var wavyBuildHelio: Bool = false

    // ── Loading
    @Published public var isLoading = false
    @Published public var statusMsg = "Listo"

    private let gann  = GannTools.shared
    private let ephem = EphemerisEngine.shared
    private let mt5   = MT5Service.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Load data
    // Carga inicial: intenta Deriv, hace demo si falla
    public func loadDemo() {
        isLoading = true
        statusMsg = "Conectando a Deriv…"
        if mt5.isConnected {
            loadDeriv()
        } else {
            // Deriv aún no conectado: demo temporal, se recargará al conectar
            mt5.connectDemo(symbol: symbol)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                self.candles = self.mt5.candles
                self.updateVisibleRange()
                self.isLoading = false
                self.statusMsg = "Demo \(self.symbol) (sin conexión)"
            }
        }
    }

    public func loadMT5() {
        loadDeriv()
    }

    // Carga datos reales de Deriv
    public func loadDeriv() {
        isLoading = true
        statusMsg = "Cargando \(symbol) \(timeframe.rawValue)…"
        mt5.fetchCandles(symbol: symbol, timeframe: timeframe.rawValue, count: 500) { [weak self] c in
            guard let self else { return }
            if !c.isEmpty {
                self.candles = c
                self.updateVisibleRange()
                self.statusMsg = "Deriv · \(self.symbol) \(self.timeframe.rawValue) — \(c.count) velas"
            } else {
                self.statusMsg = "Sin datos para \(self.symbol) \(self.timeframe.rawValue)"
            }
            self.isLoading = false
        }
    }

    // MARK: - Visible range
    public func updateVisibleRange() {
        let n = candles.count
        guard n > 0 else { return }
        let end = n - 1
        let start = max(0, end - 199)
        visibleRange = start...end
        updatePriceRange()
    }

    public func updatePriceRange() {
        let slice = candles[visibleRange]
        guard !slice.isEmpty else { return }
        let lo = slice.map(\.low).min()!
        let hi = slice.map(\.high).max()!
        let margin = (hi - lo) * 0.05
        priceRange = (lo - margin)...(hi + margin)
    }

    // MARK: - Square of Nine
    public func computeSq9(from price: Double) {
        let raw  = gann.sq9Levels(from: price, stepsEach: 12)
        sq9Levels = gann.sq9LevelsPotency(raw)
        statusMsg = String(format: "Sq9 desde %.0f → %d niveles", price, sq9Levels.count)
    }

    // MARK: - Retrograde stations
    public func computeRetrogrades(planet: String, year: Int) {
        isLoading = true
        statusMsg = "Calculando retrógradas \(planet) \(year)…"
        Task.detached { [weak self] in
            guard let self else { return }
            let result = self.ephem.retrogradeStations(planet: planet, year: year) { p in
                Task { @MainActor in self.statusMsg = String(format: "Retrógradas %.0f%%", p*100) }
            }
            await MainActor.run {
                self.stations = result
                self.isLoading = false
                self.statusMsg = "\(result.count) hitos \(planet) \(year)"
            }
        }
    }

    // MARK: - Moon crossings
    public func computeMoonCrossings(months: Int = 3) {
        let start = Date()
        let end   = start.addingTimeInterval(Double(months) * 30 * 86400)
        isLoading = true
        Task.detached { [weak self] in
            guard let self else { return }
            let result = self.ephem.moonLatCrossings(from: start, to: end)
            await MainActor.run {
                self.moonCrossings = result
                self.isLoading = false
                self.statusMsg = "\(result.count) cruces Luna próximos \(months) meses"
            }
        }
    }

    // MARK: - Inspector (tap on chart)
    public func inspect(date: Date, price: Double) {
        Task.detached { [weak self] in
            guard let self else { return }
            let result = self.gann.inspectPoint(date: date, price: price)
            await MainActor.run {
                self.inspection = result
                self.showInspector = true
            }
        }
    }

    // MARK: - Wavy builder
    public func startWavyBuild() {
        wavyBuildMode = true
        wavyBuildP1   = nil
        wavyBuildP2   = nil
        wavyBuildFC   = 0
        statusMsg = "Modo Wavy: toca P1 en el gráfico"
    }

    public func cancelWavyBuild() {
        wavyBuildMode = false
        wavyBuildP1   = nil
        wavyBuildP2   = nil
    }

    public func tapChart(date: Date, price: Double) {
        if wavyBuildMode {
            if wavyBuildP1 == nil {
                wavyBuildP1 = (date, price)
                statusMsg = "P1 = \(formatDate(date)) / \(formatPrice(price)) — toca P2"
            } else if wavyBuildP2 == nil {
                wavyBuildP2 = (date, price)
                computeWavyFC()
                statusMsg = String(format: "FC calculado: %.2f $/°  → confirma o ajusta", wavyBuildFC)
            }
        } else {
            inspect(date: date, price: price)
        }
    }

    private func computeWavyFC() {
        guard let p1 = wavyBuildP1, let p2 = wavyBuildP2 else { return }
        let result = gann.calculateFC(dt1: p1.date, price1: p1.price,
                                       dt2: p2.date, price2: p2.price,
                                       planet: wavyBuildPlanet,
                                       helio: wavyBuildHelio)
        wavyBuildFC = result.fc
        wavyBuildDirection = result.direction
    }

    public func confirmWavy() {
        guard let p1 = wavyBuildP1 else { return }
        var config = WavyConfig(
            name: wavyBuildName,
            planet: wavyBuildPlanet,
            fc: wavyBuildFC,
            direction: wavyBuildDirection,
            anchorDate: p1.date,
            anchorPrice: p1.price,
            helio: wavyBuildHelio
        )
        config.color = nextWavyColor()
        wavyLines.append(config)
        cancelWavyBuild()
        statusMsg = "Wavy '\(config.name)' añadida — \(wavyLines.count) líneas activas"
    }

    public func deleteWavy(id: UUID) {
        wavyLines.removeAll { $0.id == id }
    }

    public func toggleWavy(id: UUID) {
        if let idx = wavyLines.firstIndex(where: { $0.id == id }) {
            wavyLines[idx].visible.toggle()
        }
    }

    private var wavyColorIndex = 0
    private let wavyColors = ["#ff4444","#ff8844","#ffaa44","#ffdd44",
                               "#44ff88","#44ddff","#aa44ff","#ff44aa"]
    private func nextWavyColor() -> String {
        let c = wavyColors[wavyColorIndex % wavyColors.count]
        wavyColorIndex += 1
        return c
    }

    // MARK: - Wavy points for drawing
    public func wavyPointsFor(_ config: WavyConfig) -> [WavyPoint] {
        guard !candles.isEmpty else { return [] }
        let dates = candles.map(\.time)
        if config.showHarmonics {
            // Solo regresa el FC base para la línea principal
        }
        return gann.wavyPoints(config: config, dates: dates)
    }

    public func allWavyHarmonics(_ config: WavyConfig) -> [WavyHarmonicSet] {
        guard !candles.isEmpty else { return [] }
        let dates = candles.map(\.time)
        return gann.wavyPointsAllHarmonics(config: config, dates: dates)
    }

    // MARK: - Formatters
    public func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd-MMM-yy"
        return f.string(from: d)
    }

    public func formatPrice(_ p: Double) -> String {
        p >= 1000 ? String(format: "%.0f", p) : String(format: "%.4f", p)
    }

    // MARK: - Scroll / zoom
    public func scrollRight() {
        let n = candles.count
        let len = visibleRange.upperBound - visibleRange.lowerBound
        let newEnd = min(n-1, visibleRange.upperBound + len/4)
        visibleRange = max(0, newEnd-len)...newEnd
        updatePriceRange()
    }

    public func scrollLeft() {
        let len = visibleRange.upperBound - visibleRange.lowerBound
        let newStart = max(0, visibleRange.lowerBound - len/4)
        visibleRange = newStart...min(candles.count-1, newStart+len)
        updatePriceRange()
    }

    public func zoomIn() {
        let mid = (visibleRange.lowerBound + visibleRange.upperBound) / 2
        let half = max(20, (visibleRange.upperBound - visibleRange.lowerBound) / 2) / 2
        visibleRange = max(0, mid-half)...min(candles.count-1, mid+half)
        updatePriceRange()
    }

    public func zoomOut() {
        let mid  = (visibleRange.lowerBound + visibleRange.upperBound) / 2
        let half = min((visibleRange.upperBound - visibleRange.lowerBound) / 2 * 2, candles.count/2)
        visibleRange = max(0, mid-half)...min(candles.count-1, mid+half)
        updatePriceRange()
    }
}

// MARK: - Vertical line model
public struct VerticalLine: Identifiable {
    public let id = UUID()
    public let date: Date
    public let color: String
    public let label: String
    public let dashed: Bool
}
