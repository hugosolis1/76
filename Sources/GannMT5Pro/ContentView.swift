import SwiftUI

// MARK: - Root App
@main
struct GannMT5ProApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Content View
struct ContentView: View {
    @StateObject private var vm    = ChartViewModel()
    @StateObject private var mt5   = MT5Service.shared
    @State private var showWavyPanel = false
    @State private var showSq9Panel  = false
    @State private var showRetroPanel = false
    @State private var showInspector = false
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack {
            Color(hex: "#0d1117").ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider().background(Color(hex: "#30363d"))

                // Main area
                HStack(spacing: 0) {
                    // Chart
                    VStack(spacing: 0) {
                        CandleChartView(vm: vm)
                        chartControls
                    }

                    // Side panel (iPhone: sheet, iPad: inline)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        Divider().background(Color(hex: "#30363d"))
                        sidePanel
                            .frame(width: 320)
                    }
                }

                statusBar
            }
        }
        .sheet(isPresented: $showWavyPanel)  { WavyPanelView(vm: vm) }
        .sheet(isPresented: $showSq9Panel)   { Sq9PanelView(vm: vm) }
        .sheet(isPresented: $showRetroPanel) { RetroPanelView(vm: vm) }
        .sheet(isPresented: $vm.showInspector) {
            if let ins = vm.inspection {
                InspectorView(inspection: ins)
            }
        }
        .onAppear {
            // Auto-conectar a Deriv al iniciar
            MT5Service.shared.autoConnect()
            vm.loadDemo()
            // Cuando Deriv se conecte, recargar datos reales
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if MT5Service.shared.isConnected { vm.loadDeriv() }
            }
        }
    }

    // MARK: - Top Bar
    var topBar: some View {
        HStack(spacing: 8) {
            Text("GannMT5 Pro")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#f0883e"))

            Divider().frame(height: 16).background(Color(hex: "#30363d"))

            // Symbol picker
            Menu {
                ForEach(mt5.symbols, id: \.self) { sym in
                    Button(action: { vm.symbol = sym; vm.loadDeriv() }) {
                        Label(
                            mt5.symbolNames[sym] ?? sym,
                            systemImage: sym.hasPrefix("R_") || sym.hasPrefix("1HZ") ? "waveform" :
                                         sym.hasPrefix("BOOM") || sym.hasPrefix("CRASH") ? "bolt" :
                                         sym.contains("USD") || sym.contains("EUR") || sym.contains("GBP") ? "dollarsign.circle" :
                                         "chart.xyaxis.line"
                        )
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(vm.symbol)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down").font(.caption2)
                        .foregroundColor(Color(hex: "#8b949e"))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(hex: "#21262d")).cornerRadius(6)
            }

            // TF picker
            Menu {
                ForEach(Timeframe.allCases) { tf in
                    Button(tf.rawValue) { vm.timeframe = tf; vm.loadDeriv() }
                }
            } label: {
                Text(vm.timeframe.rawValue)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(hex: "#f0883e"))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(hex: "#21262d")).cornerRadius(6)
            }

            Spacer()

            // Overlay toggles
            overlayToggles

            Divider().frame(height: 16).background(Color(hex: "#30363d"))

            // Estado de conexión Deriv (sin botón de login)
            HStack(spacing: 4) {
                if mt5.isConnecting {
                    ProgressView().scaleEffect(0.5).tint(.orange)
                } else {
                    Circle()
                        .fill(mt5.isConnected ? Color(hex: "#3fb950") : Color(hex: "#f85149"))
                        .frame(width: 7, height: 7)
                }
                Text(mt5.isConnecting ? "Deriv…" : mt5.isConnected ? "Deriv" : "Offline")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(hex: "#21262d")).cornerRadius(6)
            .onTapGesture {
                if !mt5.isConnected && !mt5.isConnecting {
                    MT5Service.shared.autoConnect()
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(hex: "#161b22"))
    }

    var overlayToggles: some View {
        HStack(spacing: 6) {
            ToggleChip("Sq9",  on: $vm.showSq9,   color: "#ff4444")
            ToggleChip("Retro",on: $vm.showRetro,  color: "#44ff44")
            ToggleChip("Luna", on: $vm.showMoon,   color: "#aaaacc")
            ToggleChip("Wavy", on: $vm.showWavy,   color: "#ff8844")
            ToggleChip("Vol",  on: $vm.showVolume, color: "#8b949e")
        }
    }

    // MARK: - Chart Controls
    var chartControls: some View {
        HStack(spacing: 8) {
            // Navigation
            Group {
                IconBtn("chevron.left.2")  { vm.scrollLeft() }
                IconBtn("minus.magnifyingglass") { vm.zoomOut() }
                IconBtn("plus.magnifyingglass")  { vm.zoomIn() }
                IconBtn("chevron.right.2") { vm.scrollRight() }
            }

            Divider().frame(height: 16).background(Color(hex: "#30363d"))

            // Tools
            ToolBtn("Wavy", icon: "waveform.path", color: "#ff4444") {
                vm.startWavyBuild()
            }
            ToolBtn("Sq9", icon: "square.grid.3x3", color: "#ffaa44") {
                if let last = vm.candles.last {
                    vm.computeSq9(from: last.close)
                }
                showSq9Panel = true
            }
            ToolBtn("Retrógradas", icon: "arrow.triangle.2.circlepath", color: "#44ff44") {
                showRetroPanel = true
            }
            ToolBtn("Luna", icon: "moonphase.waxing.crescent", color: "#aaaacc") {
                vm.computeMoonCrossings(months: 3)
            }

            Spacer()

            // Wavy list compact
            if !vm.wavyLines.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(vm.wavyLines) { w in
                            WavyChip(config: w, vm: vm)
                        }
                    }
                }
                .frame(maxWidth: 220)

                IconBtn("list.bullet") { showWavyPanel = true }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(hex: "#161b22"))
    }

    // MARK: - Side Panel (iPad)
    var sidePanel: some View {
        TabView(selection: $selectedTab) {
            WavyPanelView(vm: vm).tabItem {
                Label("Wavy", systemImage: "waveform.path")
            }.tag(0)

            Sq9PanelView(vm: vm).tabItem {
                Label("Sq9", systemImage: "square.grid.3x3")
            }.tag(1)

            RetroPanelView(vm: vm).tabItem {
                Label("Retrógradas", systemImage: "arrow.triangle.2.circlepath")
            }.tag(2)

            MoonCalendarView(vm: vm).tabItem {
                Label("Luna", systemImage: "moon.stars")
            }.tag(3)
        }
        .background(Color(hex: "#161b22"))
    }

    // MARK: - Status Bar
    var statusBar: some View {
        HStack {
            Text(vm.statusMsg)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(hex: "#8b949e"))
            Spacer()
            if vm.isLoading {
                ProgressView().scaleEffect(0.6).tint(Color(hex: "#f0883e"))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 3)
        .background(Color(hex: "#0d1117"))
    }
}

// MARK: - Wavy Panel
struct WavyPanelView: View {
    @ObservedObject var vm: ChartViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var fcStr = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#0d1117").ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {

                        // Builder
                        if vm.wavyBuildMode {
                            builderCard
                        } else {
                            Button(action: { vm.startWavyBuild(); dismiss() }) {
                                Label("Nueva Wavy", systemImage: "plus.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "#f0883e"))
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                    .background(Color(hex: "#21262d")).cornerRadius(8)
                            }
                        }

                        // Active wavys
                        if !vm.wavyLines.isEmpty {
                            Text("LÍNEAS ACTIVAS")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(hex: "#8b949e"))
                                .padding(.top, 4)

                            ForEach(vm.wavyLines) { w in
                                WavyCard(config: w, vm: vm)
                            }
                        }
                    }
                    .padding(14)
                }
            }
            .navigationTitle("Wavy Lines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cerrar") { dismiss() }
                    .foregroundColor(Color(hex: "#f0883e"))
            }}
        }
    }

    var builderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Wavy Builder", systemImage: "pencil.line")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#ff4444"))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("P1").font(.caption).foregroundColor(Color(hex: "#8b949e"))
                    if let p1 = vm.wavyBuildP1 {
                        Text(vm.formatDate(p1.date))
                            .font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                        Text(vm.formatPrice(p1.price))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: "#3fb950"))
                    } else {
                        Text("Toca el gráfico")
                            .font(.system(size: 10)).foregroundColor(Color(hex: "#8b949e"))
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("P2").font(.caption).foregroundColor(Color(hex: "#8b949e"))
                    if let p2 = vm.wavyBuildP2 {
                        Text(vm.formatDate(p2.date))
                            .font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                        Text(vm.formatPrice(p2.price))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: "#f85149"))
                    } else {
                        Text("Pendiente")
                            .font(.system(size: 10)).foregroundColor(Color(hex: "#8b949e"))
                    }
                }
            }

            // Planet
            PlanetPicker(label: "Planeta", selection: $vm.wavyBuildPlanet)

            // Direction
            Picker("Dirección", selection: $vm.wavyBuildDirection) {
                ForEach(WavyDirection.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }.pickerStyle(.segmented)

            // FC
            HStack {
                Text("FC").font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: "#8b949e"))
                TextField("ej. 990", text: Binding(
                    get: { vm.wavyBuildFC > 0 ? String(format: "%.2f", vm.wavyBuildFC) : "" },
                    set: { if let v = Double($0) { vm.wavyBuildFC = v } }
                ))
                .keyboardType(.decimalPad)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .padding(6).background(Color(hex: "#21262d")).cornerRadius(6)
            }

            // Name
            HStack {
                Text("Nombre").font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: "#8b949e"))
                TextField("Wavy 1", text: $vm.wavyBuildName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(6).background(Color(hex: "#21262d")).cornerRadius(6)
            }

            Toggle("Heliocéntrico", isOn: $vm.wavyBuildHelio)
                .font(.system(size: 11)).foregroundColor(Color(hex: "#8b949e"))

            HStack {
                Button("Cancelar") { vm.cancelWavyBuild() }
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#f85149"))
                    .frame(maxWidth: .infinity).padding(8)
                    .background(Color(hex: "#21262d")).cornerRadius(8)

                Button("Confirmar") { vm.confirmWavy() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding(8)
                    .background(vm.wavyBuildFC > 0 ? Color(hex: "#f0883e") : Color(hex: "#30363d"))
                    .cornerRadius(8)
                    .disabled(vm.wavyBuildFC <= 0)
            }
        }
        .padding(12)
        .background(Color(hex: "#161b22")).cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#ff4444").opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Sq9 Panel
struct Sq9PanelView: View {
    @ObservedObject var vm: ChartViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var priceStr = ""
    private let gann = GannTools.shared

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#0d1117").ignoresSafeArea()
                VStack(spacing: 14) {
                    // Input
                    HStack {
                        Text("Precio base")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: "#8b949e"))
                        TextField("ej. 36920", text: $priceStr)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(8).background(Color(hex: "#21262d")).cornerRadius(6)
                        Button("Calcular") {
                            if let p = Double(priceStr) { vm.computeSq9(from: p) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(hex: "#f0883e")).cornerRadius(6)
                        .foregroundColor(.black).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)

                    // Levels list
                    List(vm.sq9Levels) { lv in
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: lv.color))
                                .frame(width: 4, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vm.formatPrice(lv.price))
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.white)
                                Text("\(lv.angle, specifier: "%.0f")°  ·  \(lv.direction == .up ? "↑" : "↓")  ·  \(lv.potency == .high ? "FUERTE" : lv.potency == .medium ? "Med" : "débil")")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(Color(hex: lv.color))
                            }
                            Spacer()
                            Button("En gráfico") { vm.showSq9 = true; dismiss() }
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#8b949e"))
                        }
                        .listRowBackground(Color(hex: "#161b22"))
                    }
                    .listStyle(.plain)
                    .background(Color(hex: "#0d1117"))
                }
                .padding(.top, 14)
            }
            .navigationTitle("Square of Nine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cerrar") { dismiss() }.foregroundColor(Color(hex: "#f0883e"))
            }}
        }
    }
}

// MARK: - Retro Panel
struct RetroPanelView: View {
    @ObservedObject var vm: ChartViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var planet = "Marte"
    @State private var year   = Calendar.current.component(.year, from: Date())

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#0d1117").ignoresSafeArea()
                VStack(spacing: 14) {
                    HStack {
                        PlanetPicker(label: "Planeta", selection: $planet)
                        Stepper("\(year)", value: $year, in: 2000...2050)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white)
                        Button("Calcular") { vm.computeRetrogrades(planet: planet, year: year) }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(hex: "#44ff44")).cornerRadius(6)
                            .foregroundColor(.black).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)

                    List(vm.stations) { s in
                        HStack {
                            Text(s.label)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: s.color))
                                .frame(width: 44)
                            VStack(alignment: .leading) {
                                Text(vm.formatDate(s.date))
                                    .font(.system(size: 12, design: .monospaced)).foregroundColor(.white)
                                Text(String(format: "%.2f°", s.longitude))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Color(hex: "#8b949e"))
                            }
                            Spacer()
                            Image(systemName: stationIcon(s.type))
                                .foregroundColor(Color(hex: s.color))
                        }
                        .listRowBackground(Color(hex: "#161b22"))
                    }
                    .listStyle(.plain).background(Color(hex: "#0d1117"))
                }
                .padding(.top, 14)
            }
            .navigationTitle("Retrógradas R→D→Ret_R")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cerrar") { dismiss() }.foregroundColor(Color(hex: "#f0883e"))
            }}
        }
    }

    func stationIcon(_ t: Station.StationType) -> String {
        switch t {
        case .R: return "arrow.uturn.backward"
        case .D: return "arrow.right"
        case .retR: return "flag.fill"
        }
    }
}

// MARK: - Moon Calendar
struct MoonCalendarView: View {
    @ObservedObject var vm: ChartViewModel
    var body: some View {
        ZStack {
            Color(hex: "#0d1117").ignoresSafeArea()
            VStack {
                Button("Calcular próximos 3 meses") {
                    vm.computeMoonCrossings(months: 3)
                }
                .padding(10)
                .background(Color(hex: "#aaaacc")).cornerRadius(8)
                .foregroundColor(.black).font(.system(size: 12, weight: .medium))

                List(vm.moonCrossings) { c in
                    HStack {
                        Text("☽").font(.title3)
                        VStack(alignment: .leading) {
                            Text(vm.formatDate(c.date))
                                .font(.system(size: 12, design: .monospaced)).foregroundColor(.white)
                            Text(c.label)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color(hex: c.color))
                        }
                        Spacer()
                        Circle()
                            .fill(Color(hex: c.level == 0 ? "#aaaacc" : "#666688"))
                            .frame(width: 8, height: 8)
                    }
                    .listRowBackground(Color(hex: "#161b22"))
                }
                .listStyle(.plain).background(Color(hex: "#0d1117"))
            }
        }
    }
}

// MARK: - Inspector Sheet
struct InspectorView: View {
    let inspection: PointInspection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#0d1117").ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Header
                        infoRow("Precio",  String(format: "%.2f", inspection.price))
                        infoRow("Sq9°",    String(format: "%.2f°", inspection.priceDegrees))
                        infoRow("√Precio", String(format: "%.4f", inspection.sqrtPrice))
                        infoRow("Lat Luna",String(format: "%.3f°", inspection.moonLatitude))

                        Divider().background(Color(hex: "#30363d"))
                        Text("ASPECTOS PLANETARIOS (todos)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(hex: "#8b949e"))

                        ForEach(inspection.aspects) { asp in
                            HStack {
                                Circle()
                                    .fill(asp.isHit ? Color(hex: "#3fb950") : Color(hex: "#30363d"))
                                    .frame(width: 7, height: 7)
                                Text(asp.planet)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(asp.isHit ? .white : Color(hex: "#8b949e"))
                                    .frame(width: 80, alignment: .leading)
                                Text(String(format: "%.2f°", asp.longitude))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Color(hex: "#8b949e"))
                                    .frame(width: 65)
                                Text(asp.type)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color(hex: "#ffaa44"))
                                    .frame(width: 36)
                                Text(String(format: "Δ%.2f°", asp.dist))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(asp.isHit ? Color(hex: "#3fb950") : Color(hex: "#8b949e"))
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cerrar") { dismiss() }.foregroundColor(Color(hex: "#f0883e"))
            }}
        }
    }

    func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(hex: "#8b949e")).frame(width: 80, alignment: .leading)
            Text(value).font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Reusable Components

struct ToggleChip: View {
    let label: String
    @Binding var on: Bool
    let color: String
    init(_ label: String, on: Binding<Bool>, color: String) {
        self.label = label; self._on = on; self.color = color
    }
    var body: some View {
        Button(action: { on.toggle() }) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(on ? .black : Color(hex: "#8b949e"))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(on ? Color(hex: color) : Color(hex: "#21262d"))
                .cornerRadius(4)
        }
    }
}

struct IconBtn: View {
    let icon: String
    let action: () -> Void
    init(_ icon: String, _ action: @escaping () -> Void) {
        self.icon = icon; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#8b949e"))
                .frame(width: 28, height: 28)
                .background(Color(hex: "#21262d")).cornerRadius(6)
        }
    }
}

struct ToolBtn: View {
    let label: String; let icon: String; let color: String; let action: () -> Void
    init(_ label: String, icon: String, color: String, action: @escaping () -> Void) {
        self.label = label; self.icon = icon; self.color = color; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundColor(Color(hex: color))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color(hex: "#21262d")).cornerRadius(6)
        }
    }
}

struct PlanetPicker: View {
    let label: String
    @Binding var selection: String
    let planets = ["Sol","Luna","Mercurio","Venus","Marte",
                   "Jupiter","Saturno","Urano","Neptuno","Pluton"]
    var body: some View {
        HStack {
            Text(label).font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(hex: "#8b949e"))
            Picker("", selection: $selection) {
                ForEach(planets, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(Color(hex: "#f0883e"))
        }
    }
}

struct WavyCard: View {
    let config: WavyConfig
    @ObservedObject var vm: ChartViewModel
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: config.color))
                .frame(width: 4, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(config.name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundColor(.white)
                Text("\(config.planet) · FC \(String(format: "%.0f", config.fc)) · \(config.direction.rawValue)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "#8b949e"))
                Text(vm.formatDate(config.anchorDate) + " / " + vm.formatPrice(config.anchorPrice))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(hex: "#8b949e"))
            }
            Spacer()
            VStack(spacing: 8) {
                Button(action: { vm.toggleWavy(id: config.id) }) {
                    Image(systemName: config.visible ? "eye.fill" : "eye.slash")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: config.visible ? "#3fb950" : "#8b949e"))
                }
                Button(action: { vm.deleteWavy(id: config.id) }) {
                    Image(systemName: "trash").font(.system(size: 12))
                        .foregroundColor(Color(hex: "#f85149"))
                }
            }
        }
        .padding(10).background(Color(hex: "#161b22")).cornerRadius(8)
    }
}

struct WavyChip: View {
    let config: WavyConfig
    @ObservedObject var vm: ChartViewModel
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color(hex: config.color)).frame(width: 7, height: 7)
            Text(config.name).font(.system(size: 10, design: .monospaced)).foregroundColor(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color(hex: "#21262d")).cornerRadius(4)
        .onTapGesture { vm.toggleWavy(id: config.id) }
    }
}
