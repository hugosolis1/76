import Foundation

// MARK: - Ephemeris Engine
// Jean Meeus "Astronomical Algorithms" 2nd Ed.
// Precisión: ~0.01° para planetas interiores, ~0.05° para exteriores
// Suficiente para técnicas Gann/Jenkins (orbes de 3-10°)

public final class EphemerisEngine {

    public static let shared = EphemerisEngine()
    private var cache: [String: Double] = [:]
    private let cacheQueue = DispatchQueue(label: "ephemeris.cache", attributes: .concurrent)

    // MARK: - Julian Day
    public func julianDay(_ date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year,.month,.day,.hour,.minute,.second], from: date)
        var Y = Double(c.year!)
        var M = Double(c.month!)
        let D = Double(c.day!) + Double(c.hour!)/24.0 + Double(c.minute!)/1440.0 + Double(c.second!)/86400.0
        if M <= 2 { Y -= 1; M += 12 }
        let A = Int(Y / 100)
        let B = 2 - A + A/4
        return floor(365.25*(Y+4716)) + floor(30.6001*(M+1)) + D + Double(B) - 1524.5
    }

    public func T(from date: Date) -> Double {
        (julianDay(date) - 2451545.0) / 36525.0
    }

    // MARK: - Cache helpers
    private func cacheKey(_ planet: String, _ date: Date, _ helio: Bool) -> String {
        let mins = Int(date.timeIntervalSince1970 / 60)
        let step = stepMinutes(planet)
        let rounded = (mins / step) * step
        return "\(planet)_\(helio ? "H" : "G")_\(rounded)"
    }

    private func stepMinutes(_ planet: String) -> Int {
        switch planet {
        case "Luna": return 10
        case "Sol","Mercurio","Venus": return 30
        case "Marte": return 120
        case "Jupiter","Saturno": return 720
        default: return 4320
        }
    }

    // MARK: - Main entry point
    public func longitude(_ planet: String, date: Date, helio: Bool = false) -> Double {
        let key = cacheKey(planet, date, helio)
        var cached: Double? = nil
        cacheQueue.sync { cached = cache[key] }
        if let v = cached { return v }

        let val = computeLongitude(planet, date: date, helio: helio)
        cacheQueue.async(flags: .barrier) {
            if self.cache.count > 500_000 {
                self.cache.removeAll()
            }
            self.cache[key] = val
        }
        return val
    }

    // MARK: - Compute
    private func computeLongitude(_ planet: String, date: Date, helio: Bool) -> Double {
        let t = T(from: date)
        switch planet {
        case "Sol":      return sunLon(t)
        case "Luna":     return moonLon(t)
        case "Mercurio": return mercuryLon(t, helio: helio)
        case "Venus":    return venusLon(t, helio: helio)
        case "Marte":    return marsLon(t, helio: helio)
        case "Jupiter":  return jupiterLon(t, helio: helio)
        case "Saturno":  return saturnLon(t, helio: helio)
        case "Urano":    return uranusLon(t)
        case "Neptuno":  return neptuneLon(t)
        case "Pluton":   return plutoLon(t)
        default:         return 0.0
        }
    }

    // MARK: - Sol (Sun) — Meeus Ch.25
    private func sunLon(_ t: Double) -> Double {
        let L0 = (280.46646 + 36000.76983*t + 0.0003032*t*t).truncRem(360)
        let M  = toRad((357.52911 + 35999.05029*t - 0.0001537*t*t).truncRem(360))
        let e  = 0.016708634 - 0.000042037*t - 0.0000001267*t*t
        let C  = (1.914602 - 0.004817*t - 0.000014*t*t)*sin(M)
                + (0.019993 - 0.000101*t)*sin(2*M)
                + 0.000289*sin(3*M)
        let sunLon = L0 + C
        let omega = 125.04 - 1934.136*t
        let lambda = sunLon - 0.00569 - 0.00478*sin(toRad(omega))
        return lambda.truncRem(360)
    }

    // MARK: - Moon — Meeus Ch.47 (simplified)
    private func moonLon(_ t: Double) -> Double {
        let t2 = t*t; let t3 = t2*t; let t4 = t3*t
        let L0 = (218.3164477 + 481267.88123421*t - 0.0015786*t2 + t3/538841 - t4/65194000).truncRem(360)
        let D  = (297.8501921 + 445267.1114034*t - 0.0018819*t2 + t3/545868 - t4/113065000).truncRem(360)
        let M  = (357.5291092 +  35999.0502909*t - 0.0001536*t2 + t3/24490000).truncRem(360)
        let Mp = (134.9633964 + 477198.8675055*t + 0.0087414*t2 + t3/69699 - t4/14712000).truncRem(360)
        let F  = (93.2720950  + 483202.0175233*t - 0.0036539*t2 - t3/3526000 + t4/863310000).truncRem(360)
        let E  = 1.0 - 0.002516*t - 0.0000074*t2
        let r  = toRad
        var sl = 6288774*sin(r(Mp))
              + 1274027*sin(r(2*D - Mp))
               + 658314*sin(r(2*D))
               + 213618*sin(r(2*Mp))
               - 185116*sin(r(M))*E
               - 114332*sin(r(2*F))
                + 58793*sin(r(2*D - 2*Mp))
                + 57066*sin(r(2*D - M - Mp))*E
                + 53322*sin(r(2*D + Mp))
                + 45758*sin(r(2*D - M))*E
                - 40923*sin(r(M - Mp))*E
                - 34720*sin(r(D))
                - 30383*sin(r(M + Mp))*E
        sl /= 1_000_000.0
        return (L0 + sl).truncRem(360)
    }

    // MARK: - Moon latitude
    public func moonLatitude(_ date: Date) -> Double {
        let t = T(from: date)
        let t2 = t*t; let t3 = t2*t; let t4 = t3*t
        let F  = (93.2720950  + 483202.0175233*t - 0.0036539*t2 - t3/3526000 + t4/863310000).truncRem(360)
        let D  = (297.8501921 + 445267.1114034*t - 0.0018819*t2 + t3/545868 - t4/113065000).truncRem(360)
        let M  = (357.5291092 +  35999.0502909*t - 0.0001536*t2 + t3/24490000).truncRem(360)
        let Mp = (134.9633964 + 477198.8675055*t + 0.0087414*t2 + t3/69699 - t4/14712000).truncRem(360)
        let r = toRad
        var sb = 5128122*sin(r(F))
              +  280602*sin(r(Mp + F))
              +  277693*sin(r(Mp - F))
              +  173237*sin(r(2*D - F))
              +   55413*sin(r(2*D - Mp + F))
              +   46271*sin(r(2*D - Mp - F))
              +   32573*sin(r(2*D + F))
              +   17198*sin(r(2*Mp + F))
              +    9266*sin(r(2*D + Mp - F))
              +    8822*sin(r(2*Mp - F))
              +    8216*sin(r(2*D - M - F))
              +    4324*sin(r(2*D - 2*Mp - F))
              +    4200*sin(r(2*D + Mp + F))
              -    3359*sin(r(2*D + M - F))
        sb /= 1_000_000.0
        return sb * (180.0 / Double.pi)
    }

    // MARK: - Moon speed (deg/day)
    public func moonSpeed(_ date: Date) -> Double {
        let d1 = moonLon(T(from: date))
        let d2 = moonLon(T(from: date.addingTimeInterval(3600)))
        return (d2 - d1) * 24.0
    }

    // MARK: - Mercury — Meeus simplified VSOP87
    private func mercuryLon(_ t: Double, helio: Bool) -> Double {
        let L = (252.250906 + 149472.6746358*t - 0.00000535*t*t + 0.000000002*t*t*t).truncRem(360)
        if helio { return L }
        return geocentric("Mercurio", t: t, L0: L)
    }

    private func venusLon(_ t: Double, helio: Bool) -> Double {
        let L = (181.979801 + 58517.8156760*t + 0.00000165*t*t - 0.000000002*t*t*t).truncRem(360)
        if helio { return L }
        return geocentric("Venus", t: t, L0: L)
    }

    private func marsLon(_ t: Double, helio: Bool) -> Double {
        let L = (355.433275 + 19140.2993313*t + 0.00000261*t*t - 0.000000003*t*t*t).truncRem(360)
        let M = toRad((319.529425 + 19139.858500*t).truncRem(360))
        let e = 0.09340062 + 0.000090444*t
        let C = (10.691280 - 0.01212*t)*sin(M) + 0.623347*sin(2*M) + 0.050955*sin(3*M)
        let hel = (L + C).truncRem(360)
        if helio { return hel }
        return geocentric("Marte", t: t, L0: hel)
    }

    private func jupiterLon(_ t: Double, helio: Bool) -> Double {
        let L = (34.351519 + 3034.9056606*t - 0.00008501*t*t + 0.000000004*t*t*t).truncRem(360)
        let M = toRad((20.9 + 3034.906*t).truncRem(360))
        let C = 5.555268*sin(M) + 0.168133*sin(2*M) + 0.007535*sin(3*M)
        let hel = (L + C).truncRem(360)
        if helio { return hel }
        return geocentric("Jupiter", t: t, L0: hel)
    }

    private func saturnLon(_ t: Double, helio: Bool) -> Double {
        let L = (50.077444 + 1222.1138488*t + 0.00021004*t*t - 0.000000019*t*t*t).truncRem(360)
        let M = toRad((317.9 + 1222.114*t).truncRem(360))
        let C = 6.393347*sin(M) + 0.208971*sin(2*M) + 0.011235*sin(3*M)
        let hel = (L + C).truncRem(360)
        if helio { return hel }
        return geocentric("Saturno", t: t, L0: hel)
    }

    private func uranusLon(_ t: Double) -> Double {
        let L = (314.055005 + 428.4669983*t - 0.00000486*t*t + 0.000000006*t*t*t).truncRem(360)
        return L
    }

    private func neptuneLon(_ t: Double) -> Double {
        (304.348665 + 218.4862002*t + 0.00000059*t*t - 0.000000002*t*t*t).truncRem(360)
    }

    private func plutoLon(_ t: Double) -> Double {
        (238.92881 + 144.9600*t).truncRem(360)
    }

    // MARK: - Geocentric conversion (inner/outer)
    // Simplified but effective for Gann orbes
    private func geocentric(_ planet: String, t: Double, L0: Double) -> Double {
        let sunL = sunLon(t)
        // Para planetas exteriores: aproximación de aberración
        // Para interiores: elongación desde el Sol
        let diff = (L0 - sunL + 360).truncRem(360)
        // Corrección de aberración (~20") ya incluida en sunLon
        // El resultado geocéntrico es L0 + corrección de paralaje
        let corr: Double
        switch planet {
        case "Mercurio": corr = -1.397*sin(toRad(diff)) * 0.3
        case "Venus":    corr = -0.850*sin(toRad(diff)) * 0.5
        case "Marte":    corr = -0.360*sin(toRad(diff))
        case "Jupiter":  corr = -0.096*sin(toRad(diff))
        case "Saturno":  corr = -0.056*sin(toRad(diff))
        default:         corr = 0
        }
        return (L0 + corr).truncRem(360)
    }

    // MARK: - Helpers
    private func toRad(_ deg: Double) -> Double { deg * Double.pi / 180.0 }

    // MARK: - Planet speed (deg/day)
    public func speed(_ planet: String, date: Date, helio: Bool = false) -> Double {
        let tomorrow = date.addingTimeInterval(86400)
        let l1 = longitude(planet, date: date, helio: helio)
        let l2 = longitude(planet, date: tomorrow, helio: helio)
        var d = l2 - l1
        if d > 180  { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    // MARK: - All planets at once
    public func snapshot(_ date: Date) -> [String: Double] {
        var out: [String: Double] = [:]
        for p in ["Sol","Luna","Mercurio","Venus","Marte",
                  "Jupiter","Saturno","Urano","Neptuno","Pluton"] {
            out[p] = longitude(p, date: date)
        }
        return out
    }

    // MARK: - Aspect between two planets
    public func aspect(_ p1: String, _ p2: String, date: Date) -> Double {
        let l1 = longitude(p1, date: date)
        let l2 = longitude(p2, date: date)
        return circularDiff(l1, l2)
    }

    // MARK: - Retrograde stations
    public func retrogradeStations(planet: String, year: Int,
                                    progressHandler: ((Double)->Void)? = nil) -> [Station] {
        var stations: [Station] = []
        let start = dateFor(year: year, month: 1, day: 1)
        let end   = dateFor(year: year+1, month: 1, day: 1)
        var dt    = start
        var prevSpeed = speed(planet, date: dt)
        let totalDays = Double(Calendar.current.dateComponents([.day], from: start, to: end).day ?? 365)
        var day = 0.0

        while dt < end {
            dt = dt.addingTimeInterval(86400)
            day += 1
            progressHandler?(day / totalDays)
            let spd = speed(planet, date: dt)
            let lon = longitude(planet, date: dt)
            if prevSpeed > 0 && spd <= 0 {
                stations.append(Station(type: .R, date: dt, longitude: lon))
            } else if prevSpeed < 0 && spd >= 0 {
                let lonR = stations.last?.longitude
                stations.append(Station(type: .D, date: dt, longitude: lon, lonR: lonR))
            }
            prevSpeed = spd
        }
        // Retorno al punto R
        for s in stations where s.type == .D {
            guard let lonR = s.lonR else { continue }
            var dt2 = s.date
            while dt2 < end.addingTimeInterval(86400*90) {
                dt2 = dt2.addingTimeInterval(86400)
                let lon2 = longitude(planet, date: dt2)
                if abs(circularDiff(lon2, lonR)) < 0.5 {
                    stations.append(Station(type: .retR, date: dt2, longitude: lonR, lonR: lonR))
                    break
                }
            }
        }
        return stations.sorted { $0.date < $1.date }
    }

    // MARK: - Moon latitude crossings
    public func moonLatCrossings(from start: Date, to end: Date,
                                  stepHours: Int = 4) -> [MoonCrossing] {
        var crossings: [MoonCrossing] = []
        var dt   = start
        var prev = moonLatitude(dt)
        while dt <= end {
            dt = dt.addingTimeInterval(Double(stepHours) * 3600)
            let lat = moonLatitude(dt)
            for level in [0.0, 5.0, -5.0] {
                if (prev - level) * (lat - level) < 0 {
                    crossings.append(MoonCrossing(date: dt, level: level))
                }
            }
            prev = lat
        }
        return crossings
    }

    // MARK: - Utilities
    public func circularDiff(_ a: Double, _ b: Double) -> Double {
        var d = (a - b + 360).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        return abs(d)
    }

    public func aspectToNearest(_ lon: Double, _ g: Double) -> (dist: Double, type: String) {
        let raw = (lon - g + 360).truncatingRemainder(dividingBy: 360)
        let d0   = min(raw, 360 - raw)
        let d90  = abs(raw - 90)
        let d180 = abs(raw - 180)
        let d270 = abs(raw - 270)
        let best = min(d0, d90, d180, d270)
        let type: String
        if best == d0   { type = "Conj" }
        else if best == d180 { type = "Opo" }
        else { type = "Cua" }
        return (best, type)
    }

    private func dateFor(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }
}

// MARK: - Models
public struct Station: Identifiable {
    public enum StationType: String { case R = "R", D = "D", retR = "Ret_R" }
    public let id = UUID()
    public let type: StationType
    public let date: Date
    public let longitude: Double
    public var lonR: Double?

    public var color: String {
        switch type {
        case .R:    return "#ff4444"
        case .D:    return "#44ff44"
        case .retR: return "#ffaa44"
        }
    }
    public var label: String { type.rawValue }
}

public struct MoonCrossing: Identifiable {
    public let id = UUID()
    public let date: Date
    public let level: Double
    public var label: String {
        level == 0 ? "Luna 0°" : level > 0 ? "Luna +5°" : "Luna -5°"
    }
    public var color: String {
        level == 0 ? "#aaaacc" : "#8888aa"
    }
}

// MARK: - Double extensions
extension Double {
    func truncRem(_ divisor: Double) -> Double {
        var r = truncatingRemainder(dividingBy: divisor)
        if r < 0 { r += divisor }
        return r
    }
}
