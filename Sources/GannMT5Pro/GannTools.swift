import Foundation

// MARK: - Gann Tools Engine

public final class GannTools {

    public static let shared = GannTools()
    private let ephem = EphemerisEngine.shared

    // MARK: - Square of Nine
    public func priceToSq9Degrees(_ price: Double) -> (degrees: Double, sqrtVal: Double) {
        guard price > 0 else { return (0, 0) }
        let s = sqrt(price)
        let deg = (s - floor(s)) * 360.0
        return (deg, s)
    }

    public func sq9Levels(from price: Double, stepsEach: Int = 8) -> [Sq9Level] {
        guard price > 0 else { return [] }
        let s = sqrt(price)
        var levels: [Sq9Level] = []
        for i in -stepsEach...stepsEach {
            if i == 0 { continue }
            let step   = Double(i) * 0.25
            let newP   = pow(s + step, 2)
            let deg    = Double(i) * 90.0
            let angDeg = ((deg.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
            levels.append(Sq9Level(price: newP, angle: angDeg,
                                    step: i, direction: i > 0 ? .up : .down))
        }
        return levels.sorted { $0.price < $1.price }
    }

    public func sq9LevelsPotency(_ levels: [Sq9Level]) -> [Sq9Level] {
        levels.map { level in
            var l = level
            let angle = Int(level.angle)
            l.potency = [0, 90, 180, 270].contains(angle % 360) ? .high :
                        [45, 135, 225, 315].contains(angle % 360) ? .medium : .low
            return l
        }
    }

    // MARK: - FC Calculator
    public func calculateFC(dt1: Date, price1: Double,
                             dt2: Date, price2: Double,
                             planet: String, helio: Bool = false) -> FCResult {
        let l1 = ephem.longitude(planet, date: dt1, helio: helio)
        let l2 = ephem.longitude(planet, date: dt2, helio: helio)
        var dl = (l2 - l1 + 540).truncatingRemainder(dividingBy: 360) - 180
        let dp = abs(price2 - price1)
        let fc = abs(dl) > 0.001 ? dp / abs(dl) : 0.0
        let dir: WavyDirection = price2 < price1 ? .resta : .suma
        return FCResult(planet: planet, fc: fc, deltaPrice: dp,
                        deltaLon: abs(dl), direction: dir,
                        harmonics: harmonics(fc))
    }

    public func harmonics(_ fc: Double) -> [FCHarmonic] {
        let mults = [0.125, 0.25, 0.333, 0.5, 1.0,
                     1.414, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 9.0]
        return mults.map { m in
            FCHarmonic(multiplier: m, value: fc * m,
                       label: m == 1.0 ? "×1 ★" : "×\(formatMult(m))")
        }
    }

    private func formatMult(_ m: Double) -> String {
        if m == 0.333 { return "1/3" }
        if m == 0.125 { return "1/8" }
        if m == 0.25  { return "1/4" }
        if m == 0.5   { return "1/2" }
        if m == 1.414 { return "√2" }
        if m == floor(m) { return String(Int(m)) }
        return String(format: "%.3f", m)
    }

    // MARK: - Wavy Line
    public func wavyPoints(config: WavyConfig, dates: [Date]) -> [WavyPoint] {
        let lonAnc = ephem.longitude(config.planet, date: config.anchorDate,
                                      helio: config.helio)
        return dates.map { dt in
            let lon = ephem.longitude(config.planet, date: dt, helio: config.helio)
            var dl  = (lon - lonAnc + 540).truncatingRemainder(dividingBy: 360) - 180
            let dir = config.direction == .suma ? 1.0 : -1.0
            let price = config.anchorPrice + dir * dl * config.fc
            return WavyPoint(date: dt, price: price,
                              lon: lon, deltaLon: dl)
        }
    }

    public func wavyPointsAllHarmonics(config: WavyConfig, dates: [Date]) -> [WavyHarmonicSet] {
        let mults = [0.25, 0.5, 1.0, 2.0]
        return mults.map { mult in
            var c = config
            c.fc = config.fc * mult
            let pts = wavyPoints(config: c, dates: dates)
            return WavyHarmonicSet(multiplier: mult, fc: c.fc, points: pts,
                                   color: harmonicColor(mult))
        }
    }

    private func harmonicColor(_ mult: Double) -> String {
        switch mult {
        case 0.25: return "#445588"
        case 0.5:  return "#4488cc"
        case 1.0:  return "#ff4444"
        case 2.0:  return "#ff8844"
        default:   return "#888888"
        }
    }

    // MARK: - Square the Price (Time projection)
    public func squareThePrice(_ price: Double) -> SquareResult {
        let (deg, sqrtV) = priceToSq9Degrees(price)
        return SquareResult(
            price: price, degrees: deg, sqrtValue: sqrtV,
            daysFromDegrees: deg,
            sunDaysToSquare: deg / 0.9856,
            marsDaysToSquare: deg / 0.5240
        )
    }

    public func squareTheRange(high: Double, low: Double) -> SquareResult {
        let range = abs(high - low)
        return squareThePrice(range)
    }

    // MARK: - Aspect inspector
    public func inspectPoint(date: Date, price: Double) -> PointInspection {
        let lons  = ephem.snapshot(date)
        let (priceDeg, sqrtV) = priceToSq9Degrees(price)
        var aspects: [PlanetAspect] = []
        for (p, lon) in lons {
            let (dist, type) = ephem.aspectToNearest(lon, priceDeg)
            aspects.append(PlanetAspect(planet: p, longitude: lon,
                                         dist: dist, type: type,
                                         isHit: dist <= 10.0))
        }
        let moonLat = ephem.moonLatitude(date)
        return PointInspection(date: date, price: price,
                                priceDegrees: priceDeg,
                                sqrtPrice: sqrtV,
                                aspects: aspects.sorted { $0.dist < $1.dist },
                                moonLatitude: moonLat)
    }

    // MARK: - Family tree (longitude → price)
    public func familyTree(longitude: Double, scale: Double,
                            levels: Int = 10) -> [FamilyLevel] {
        var result: [FamilyLevel] = []
        for n in 0...levels {
            let price = (longitude + Double(n) * 360) * scale
            result.append(FamilyLevel(n: n, price: price,
                                       longitude: longitude + Double(n)*360))
        }
        // Sub-family trine (÷3) and square (÷4)
        for div in [3.0, 4.0] {
            for n in 0...levels {
                let frac = longitude / div + Double(n) * (360/div)
                let price = frac * scale
                result.append(FamilyLevel(n: n, price: price,
                                           longitude: frac, family: div == 3 ? "trine" : "square"))
            }
        }
        return result.sorted { $0.price < $1.price }
    }

    // MARK: - Gann numbers
    public static let magicNumbers: [Double] = [
        1,3,7,9,11,12,13,22,23,30,33,46,49,
        81,90,100,121,144,169,225,256,289,360,
        441,529,625,666,729,841,900,1000
    ]

    public func nearestMagicNumber(_ price: Double) -> (number: Double, distance: Double) {
        let scaled = GannTools.magicNumbers.map { n -> (Double, Double) in
            var scale = 1.0
            while n * scale < price * 0.5 { scale *= 10 }
            return (n * scale, abs(n * scale - price))
        }
        return scaled.min(by: { $0.1 < $1.1 }) ?? (price, 0)
    }
}

// MARK: - Models

public struct Sq9Level: Identifiable {
    public let id = UUID()
    public let price: Double
    public let angle: Double
    public let step: Int
    public let direction: Direction
    public var potency: Potency = .low

    public enum Direction { case up, down }
    public enum Potency   { case high, medium, low }

    public var color: String {
        switch potency {
        case .high:   return "#ff4444"
        case .medium: return "#ffaa44"
        case .low:    return "#445566"
        }
    }
    public var lineWidth: Double {
        switch potency { case .high: return 1.5; case .medium: return 1.0; case .low: return 0.5 }
    }
}

public struct FCResult {
    public let planet: String
    public let fc: Double
    public let deltaPrice: Double
    public let deltaLon: Double
    public let direction: WavyDirection
    public let harmonics: [FCHarmonic]

    public var summary: String {
        String(format: "FC = %.2f $/°  |  Δ$%.0f / %.2f°", fc, deltaPrice, deltaLon)
    }
}

public struct FCHarmonic: Identifiable {
    public let id = UUID()
    public let multiplier: Double
    public let value: Double
    public let label: String
}

public enum WavyDirection: String, CaseIterable {
    case suma = "Suma"
    case resta = "Resta"
}

public struct WavyConfig: Identifiable {
    public let id = UUID()
    public var name: String
    public var planet: String
    public var fc: Double
    public var direction: WavyDirection
    public var anchorDate: Date
    public var anchorPrice: Double
    public var helio: Bool = false
    public var visible: Bool = true
    public var color: String = "#ff4444"
    public var showHarmonics: Bool = true
    public var lineWidth: Double = 1.5
}

public struct WavyPoint: Identifiable {
    public let id = UUID()
    public let date: Date
    public let price: Double
    public let lon: Double
    public let deltaLon: Double
}

public struct WavyHarmonicSet: Identifiable {
    public let id = UUID()
    public let multiplier: Double
    public let fc: Double
    public let points: [WavyPoint]
    public let color: String
}

public struct SquareResult {
    public let price: Double
    public let degrees: Double
    public let sqrtValue: Double
    public let daysFromDegrees: Double
    public let sunDaysToSquare: Double
    public let marsDaysToSquare: Double

    public var summary: String {
        String(format: "√%.0f = %.4f → %.2f° → %.0f días Sol / %.0f días Marte",
               price, sqrtValue, degrees, sunDaysToSquare, marsDaysToSquare)
    }
}

public struct PlanetAspect: Identifiable {
    public let id = UUID()
    public let planet: String
    public let longitude: Double
    public let dist: Double
    public let type: String
    public let isHit: Bool
}

public struct PointInspection {
    public let date: Date
    public let price: Double
    public let priceDegrees: Double
    public let sqrtPrice: Double
    public let aspects: [PlanetAspect]
    public let moonLatitude: Double

    public var topHits: [PlanetAspect] { aspects.filter { $0.isHit } }
}

public struct FamilyLevel: Identifiable {
    public let id = UUID()
    public let n: Int
    public let price: Double
    public let longitude: Double
    public var family: String = "base"
}
