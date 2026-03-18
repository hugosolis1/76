import Foundation
import Combine

// MARK: - Deriv WebSocket Service
// Se conecta automáticamente a la API pública de Deriv
// Endpoint: wss://ws.derivws.com/websockets/v3?app_id=1089
// No requiere credenciales para datos de mercado

public final class MT5Service: ObservableObject {

    public static let shared = MT5Service()

    @Published public var isConnected   = false
    @Published public var isConnecting  = false
    @Published public var lastError: String? = nil
    @Published public var symbols: [String]  = []
    @Published public var symbolNames: [String: String] = [:]
    @Published public var candles: [Candle]  = []
    @Published public var currentPrice: Double = 0

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession    = URLSession.shared
    private var pendingHandlers: [Int: (Data) -> Void] = [:]
    private var tickHandler: ((Double) -> Void)?
    private var pingTimer: Timer?
    private var reqCounter = 0

    private let derivEndpoint = "wss://ws.derivws.com/websockets/v3?app_id=1089"

    // MARK: - Auto-connect al broker Deriv
    public func autoConnect() {
        guard !isConnected, !isConnecting else { return }
        isConnecting = true
        lastError    = nil

        guard let url = URL(string: derivEndpoint) else {
            lastError = "URL inválida"; isConnecting = false; return
        }

        let request = URLRequest(url: url)
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        startReceiving()

        // Verificar con ping
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.sendPing()
        }
    }

    public func disconnect() {
        pingTimer?.invalidate(); pingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.isConnected  = false
            self.isConnecting = false
            self.candles      = []
        }
    }

    // MARK: - Ping / keep-alive
    private func sendPing() {
        wsRequest(["ping": 1]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isConnecting = false
                self?.isConnected  = true
            }
            self?.schedulePing()
            self?.fetchSymbols()
        }
    }

    private func schedulePing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.wsRequest(["ping": 1]) { _ in }
        }
    }

    // MARK: - Símbolos activos de Deriv
    public func fetchSymbols() {
        let payload: [String: Any] = [
            "active_symbols": "brief",
            "product_type": "basic"
        ]
        wsRequest(payload) { [weak self] data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["active_symbols"] as? [[String: Any]] else { return }

            var syms: [String] = []
            var names: [String: String] = [:]

            // Orden de prioridad: sintéticos Deriv primero
            let priority = [
                "R_75","R_100","R_50","R_25","R_10",
                "1HZ10V","1HZ25V","1HZ50V","1HZ75V","1HZ100V",
                "BOOM500","CRASH500","BOOM1000","CRASH1000",
                "EURUSD","GBPUSD","USDJPY","USDCHF","AUDUSD",
                "XAUUSD","XAGUSD","BTCUSD","ETHUSD","LTCUSD"
            ]

            for sym in priority {
                if let item = list.first(where: { ($0["symbol"] as? String) == sym }),
                   let symbol = item["symbol"] as? String {
                    syms.append(symbol)
                    names[symbol] = item["display_name"] as? String ?? symbol
                }
            }
            for item in list {
                if let symbol = item["symbol"] as? String, !syms.contains(symbol) {
                    syms.append(symbol)
                    names[symbol] = item["display_name"] as? String ?? symbol
                }
            }

            DispatchQueue.main.async {
                self?.symbols     = syms
                self?.symbolNames = names
            }
        }
    }

    // MARK: - Historial de velas
    public func fetchCandles(symbol: String, timeframe: String, count: Int = 500,
                              completion: @escaping ([Candle]) -> Void) {
        guard isConnected else {
            let demo = makeDemoCandles(symbol: symbol, count: count)
            completion(demo); return
        }

        let gran = granularity(timeframe)
        let payload: [String: Any] = [
            "ticks_history": symbol,
            "count": count,
            "end": "latest",
            "style": "candles",
            "granularity": gran
        ]

        wsRequest(payload) { [weak self] data in
            guard let self = self,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion([]) }; return
            }

            var result: [Candle] = []

            if let rawCandles = json["candles"] as? [[String: Any]] {
                result = rawCandles.compactMap { c -> Candle? in
                    guard let epoch = (c["epoch"] as? NSNumber)?.doubleValue else { return nil }
                    return Candle(
                        time:   Date(timeIntervalSince1970: epoch),
                        open:   self.toDouble(c["open"])  ?? 0,
                        high:   self.toDouble(c["high"])  ?? 0,
                        low:    self.toDouble(c["low"])   ?? 0,
                        close:  self.toDouble(c["close"]) ?? 0,
                        volume: 0
                    )
                }
            }

            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Tick en tiempo real
    public func subscribeTick(symbol: String, handler: @escaping (Double) -> Void) {
        tickHandler = handler
        wsRequest(["ticks": symbol, "subscribe": 1]) { _ in }
    }

    // MARK: - Demo mode (fallback sin internet)
    public func connectDemo(symbol: String = "R_75") {
        DispatchQueue.main.async {
            self.isConnected  = true
            self.isConnecting = false
            self.symbols = ["R_75","R_100","R_50","R_25","R_10",
                            "EURUSD","GBPUSD","USDJPY","XAUUSD","BTCUSD"]
            self.symbolNames = [
                "R_75":"Volatility 75 Index","R_100":"Volatility 100 Index",
                "R_50":"Volatility 50 Index","R_25":"Volatility 25 Index",
                "R_10":"Volatility 10 Index","EURUSD":"EUR/USD",
                "GBPUSD":"GBP/USD","USDJPY":"USD/JPY",
                "XAUUSD":"Gold/USD","BTCUSD":"Bitcoin/USD"
            ]
            self.generateDemoCandles(symbol: symbol)
        }
    }

    // MARK: - WebSocket I/O
    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.startReceiving()
            case .failure(let err):
                DispatchQueue.main.async {
                    self?.isConnected  = false
                    self?.isConnecting = false
                    self?.lastError    = err.localizedDescription
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        var raw: Data?
        switch message {
        case .string(let s): raw = s.data(using: .utf8)
        case .data(let d):   raw = d
        @unknown default:    return
        }
        guard let data = raw,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Tick en vivo
        if let tick = json["tick"] as? [String: Any],
           let quote = (tick["quote"] as? NSNumber)?.doubleValue {
            DispatchQueue.main.async {
                self.currentPrice = quote
                self.tickHandler?(quote)
            }
        }

        // Respuesta a req_id
        let reqId = (json["req_id"] as? NSNumber)?.intValue ?? -1
        if let handler = pendingHandlers[reqId] {
            pendingHandlers.removeValue(forKey: reqId)
            handler(data)
        }
    }

    private func wsRequest(_ payload: [String: Any], completion: @escaping (Data) -> Void) {
        reqCounter += 1
        let id = reqCounter
        var mutable = payload
        mutable["req_id"] = id

        guard let data = try? JSONSerialization.data(withJSONObject: mutable),
              let str  = String(data: data, encoding: .utf8) else { return }

        pendingHandlers[id] = completion

        webSocketTask?.send(.string(str)) { [weak self] error in
            if error != nil {
                self?.pendingHandlers.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Helpers
    private func toDouble(_ v: Any?) -> Double? {
        if let d = v as? Double      { return d }
        if let s = v as? String      { return Double(s) }
        if let n = v as? NSNumber    { return n.doubleValue }
        return nil
    }

    private func granularity(_ tf: String) -> Int {
        switch tf {
        case "M1":  return 60
        case "M5":  return 300
        case "M15": return 900
        case "M30": return 1800
        case "H1":  return 3600
        case "H4":  return 14400
        case "D1":  return 86400
        case "W1":  return 604800
        case "MN":  return 2592000
        default:    return 86400
        }
    }

    @discardableResult
    private func makeDemoCandles(symbol: String, count: Int = 500) -> [Candle] {
        let result = generateDemoCandles(symbol: symbol, count: count)
        return result
    }

    @discardableResult
    private func generateDemoCandles(symbol: String, count: Int = 500) -> [Candle] {
        var result: [Candle] = []
        let cal  = Calendar(identifier: .gregorian)
        var dt   = cal.date(byAdding: .day, value: -count, to: Date()) ?? Date()
        var price: Double = symbol.contains("R_75")  ? 46988.0 :
                            symbol.contains("R_100") ? 10000.0 :
                            symbol.contains("BTC")   ? 60000.0 : 1.1

        for _ in 0..<count {
            let range = price * Double.random(in: 0.005...0.025)
            let up    = Bool.random()
            let high  = price + range * Double.random(in: 0.5...1.0)
            let low   = price - range * Double.random(in: 0.5...1.0)
            let close = up ? price + range * Double.random(in: 0...0.8)
                           : price - range * Double.random(in: 0...0.8)
            result.append(Candle(time: dt, open: price, high: high,
                                  low: low, close: close,
                                  volume: Double.random(in: 100...2000)))
            price = close
            dt    = cal.date(byAdding: .day, value: 1, to: dt) ?? dt
        }
        DispatchQueue.main.async { self.candles = result }
        return result
    }
}

// MARK: - Models

public struct Candle: Identifiable {
    public let id    = UUID()
    public let time:   Date
    public let open:   Double
    public let high:   Double
    public let low:    Double
    public let close:  Double
    public let volume: Double
    public var isBullish: Bool { close >= open }
}

// MARK: - Timeframe

public enum Timeframe: String, CaseIterable, Identifiable {
    public var id: String { rawValue }
    case m1  = "M1"
    case m5  = "M5"
    case m15 = "M15"
    case m30 = "M30"
    case h1  = "H1"
    case h4  = "H4"
    case d1  = "D1"
    case w1  = "W1"
    case mn  = "MN"

    public var seconds: Int {
        switch self {
        case .m1:  return 60
        case .m5:  return 300
        case .m15: return 900
        case .m30: return 1800
        case .h1:  return 3600
        case .h4:  return 14400
        case .d1:  return 86400
        case .w1:  return 604800
        case .mn:  return 2592000
        }
    }
    public var label: String { rawValue }
}
