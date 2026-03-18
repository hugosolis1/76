# GannMT5 Pro — iOS Trading Terminal con Herramientas Gann/Jenkins

Terminal de trading para iOS basado en MetaTrader 5, con efemérides reales de precisión al minuto y todas las herramientas Gann/Jenkins.

---

## Estructura del proyecto

```
GannMT5Pro/
├── Package.swift
├── README.md
├── Resources/
│   └── Info.plist
└── Sources/
    └── GannMT5Pro/
        ├── EphemerisEngine.swift    ← Efemérides Jean Meeus, precisión al minuto
        ├── GannTools.swift          ← Square of Nine, FC, Wavy, Family Tree
        ├── MT5Service.swift         ← Conexión MT5 WebAPI + modo Demo
        ├── ChartViewModel.swift     ← Estado del gráfico y herramientas
        ├── CandleChartView.swift    ← Gráfico de velas + overlays
        └── ContentView.swift        ← UI completa (iPhone + iPad)
```

---

## Funcionalidades

### Gráfico
- Velas japonesas con volumen
- Zoom + scroll táctil
- Crosshair con fecha/precio
- Tema oscuro MT5-style

### Herramientas Gann (todas activables/desactivables)
| Herramienta | Descripción |
|---|---|
| **Wavy Lines** | Líneas planetarias con FC configurable. Builder tap-tap en el gráfico. 4 armónicos automáticos (×0.25, ×0.5, ×1, ×2) |
| **Square of Nine** | Niveles de soporte/resistencia desde cualquier precio. Colores por potencia (rojo = 0/90/180/270°) |
| **Retrogradaciones** | Hitos R→D→Retorno_R de cualquier planeta, cualquier año |
| **Latitud Luna** | Cruces de 0°, +5°, -5° con calendario mensual |
| **Inspector** | Toca cualquier punto del gráfico → muestra aspectos de los 10 planetas con el precio |

### Efemérides
- Algoritmos Jean Meeus "Astronomical Algorithms" 2nd Ed.
- Precisión: ~0.01° para planetas interiores, ~0.05° para exteriores
- Velocidad planetaria (detecta retrogradaciones automáticamente)
- Latitud de la Luna (±5.15°)
- Caché inteligente por resolución temporal (Luna: 10 min, Marte: 2h, etc.)
- **Sin dependencias externas** — todo calculado en Swift puro

### Conexión MT5
- MT5 WebAPI REST (requiere broker con WebAPI habilitada)
- Modo Demo integrado (datos sintéticos para practicar)
- Soporte iPhone + iPad (panel lateral en iPad)

---

## Compilación con MagicCode

### Pasos:

1. **Sube este repositorio a GitHub**
   ```bash
   git init
   git add .
   git commit -m "GannMT5 Pro v1.0"
   git remote add origin https://github.com/TU_USUARIO/GannMT5Pro.git
   git push -u origin main
   ```

2. **Abre MagicCode en tu iPhone/iPad**

3. **Clona el repositorio**
   - En MagicCode → "Clone Repository" → pega la URL de GitHub

4. **Configura el proyecto**
   - Bundle ID: `com.TU_NOMBRE.GannMT5Pro`
   - Deployment Target: iOS 16.0+
   - Device: iPhone + iPad

5. **Compila y ejecuta**
   - Build → Run on Device (o TestFlight para distribución)

### Notas de compilación:
- Mínimo iOS 16.0 (usa `Canvas`, `Charts` de SwiftUI)
- No requiere pods ni SPM externo — Swift puro
- Orientación: Portrait + Landscape soportados

---

## Uso básico

### Wavy Line (paso a paso):
1. Toca **"Wavy"** en la barra de herramientas
2. Toca **P1** en el gráfico (máximo o mínimo confirmado)
3. Toca **P2** (segundo punto con hit planetario)
4. El FC se calcula automáticamente
5. Ajusta planeta/dirección si es necesario
6. Toca **"Confirmar"** → aparece en el gráfico

### Square of Nine:
1. Toca **"Sq9"** → ingresa el precio base
2. Los niveles aparecen en el gráfico automáticamente
3. Rojo = nivel fuerte (0°/90°/180°/270°), naranja = medio, azul oscuro = débil

### Retrogradaciones:
1. Toca **"Retrógradas"** → elige planeta y año
2. Los hitos R (rojo), D (verde) y Ret_R (naranja) aparecen como líneas verticales

### Inspector (identificar planeta regente):
1. **Toca cualquier punto** del gráfico sin modo Wavy activo
2. Se muestra: precio en grados Sq9, aspectos de los 10 planetas
3. Los hits (orbe ≤10°) se marcan en verde

---

## Configuración MT5 WebAPI

En el terminal MetaTrader 5 del broker:
1. Herramientas → Opciones → Expert Advisors
2. Activar: "Permitir solicitudes Web para las siguientes URLs"
3. Añadir la URL de tu servidor

O contacta a tu broker para obtener las credenciales de su API REST.

---

## Planetas y sus FCs para R_75 (datos calculados)

| Planeta | FC base | Período activo |
|---|---|---|
| **Marte** | 990 $/° | Todo el año (planeta maestro) |
| **Venus** | 576 $/° | Co-regente, activo en máximos |
| **Sol** | ~750 $/° | Solo dic-ene (zona Capricornio) |

---

*Basado en la metodología Jenkins/Gann — Volúmenes 1, 2 y 3*
