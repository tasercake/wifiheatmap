# WiFi Heatmap macOS App — Design Spec

## Decisions

| Question | Decision |
|---|---|
| Platform | macOS only (CoreWLAN; iOS locks down WiFi scanning) |
| Distribution | Developer ID direct download (no App Store sandbox/entitlement friction) |
| Positioning | Manual tap-to-mark MVP (ARKit stretch goal) |
| Persistence | `.wifiheatmap` directory bundle (JSON + PNG, no SQLite) |
| Multi-floor | Yes — each survey holds N floors, each with its own floor plan |
| Rendering | IDW interpolation → `Canvas` overlay per band |

---

## Architecture

Three layers with one job each:

```
CoreWLAN  →  ScanActor  →  WifiSurveyDocument  →  SwiftUI views
(hardware)   (concurrency  (state + disk)          (render + input)
              boundary)
```

The app shell is a `DocumentGroup` SwiftUI scene. Surveys are first-class documents — Open, Save, Recent Files, and dirty-state tracking all come from the OS. No custom file management code.

---

## Data Model

### Bundle layout

```
MySurvey.wifiheatmap/
  manifest.json          ← { name: String, createdAt: Date, floorIDs: [UUID] }
  floors/
    <uuid>.json          ← { id, name, floorPlanFilename, calibration, samples[] }
    <uuid>.png           ← floor plan image (copied in on import, never modified)
```

`WifiSurveyDocument` reads the bundle in two passes: manifest first (to get the ordered floor ID list), then each `floors/<id>.json` in that order. Writes are mirrored: manifest + one file per floor.

### Swift types

```swift
struct WifiSurvey: Codable {
    var name: String
    var floors: [Floor]
}

struct Floor: Codable, Identifiable {
    var id: UUID
    var name: String
    var floorPlanFilename: String
    var calibration: Calibration?
    var samples: [WifiSample]
}

struct Calibration: Codable {
    var pointA: CGPoint
    var pointB: CGPoint
    var realWorldDistanceMeters: Double
}

struct WifiSample: Codable {
    var id: UUID
    var position: CGPoint        // floor plan image coordinates
    var timestamp: Date
    var ssid: String
    var bssid: String
    var rssi: Int                // dBm
    var noise: Int               // dBm
    var band: WiFiBand
}

enum WiFiBand: String, Codable { case ghz2_4, ghz5, ghz6 }
```

`Calibration` stores two tapped pixel positions and their real-world distance. The pixels-per-meter scale factor is derived at render time and used only by IDW — raw samples always store pixel coordinates.

`WifiSurveyDocument` conforms to `ReferenceFileDocument`. It reads/writes the bundle directory: the manifest as `manifest.json`, each `Floor` as `floors/<id>.json`, and floor plan images as `floors/<id>.png`.

---

## CoreWLAN Scan Layer

`ScanActor` is the sole owner of `CWWiFiClient`. Nothing else touches CoreWLAN.

```swift
actor ScanActor {
    private let client = CWWiFiClient.shared()
    private(set) var isScanning = false

    func startScanning() -> AsyncStream<[WifiSample]>
    func stopScanning()
}
```

Loop inside `startScanning()`:
1. Call `interface.scanForNetworks(withSSID: nil)` — blocks ~2–4 s (the rate limiter; no added sleep needed).
2. Map each `CWNetwork` → `WifiSample`. Filter out nil-BSSID entries.
3. Yield the batch into the `AsyncStream`.
4. Repeat.

**Location authorization:** `CLLocationManager` auth is required for non-nil BSSID. A thin `LocationAuthManager` requests it once at launch. If denied, scanning still works but BSSID will be empty and per-AP filtering won't work. A banner in the UI warns the user.

**Sample capture:** The active view holds the latest batch from the stream. On "Log Reading" tap, it takes the strongest reading matching the selected SSID/band, attaches the tapped `CGPoint`, and appends a `WifiSample` to the active `Floor`.

---

## UI Structure

```
ContentView
├── Sidebar — floor list (add / remove / rename)
└── DetailView (active floor)
    ├── Toolbar — band toggle (2.4 / 5 / 6 GHz), SSID picker, scan status indicator
    ├── FloorPlanView (ZStack)
    │   ├── Image — floor plan
    │   ├── HeatmapCanvas — Canvas overlay (IDW grid, ~60% opacity)
    │   └── SampleMarkers — dots at logged positions
    └── BottomBar — calibration status, "Log Reading" button, last RSSI readout
```

### Calibration

Before any readings can be logged, the user taps two points on the floor plan and enters the real-world distance between them. The app draws crosshairs at both points. No calibration → heatmap hidden with a prompt.

### IDW Computation

Runs in a detached `Task` whenever samples or the active band change. Steps:
1. Filter `floor.samples` by selected `WiFiBand`.
2. Compute a 200×200 grid. For each cell: weighted average of all sample RSSI values, weight = 1/distance² (distance in real-world meters via calibration scale factor). Cells where the nearest sample is farther than a tunable `idwMaxRadiusMeters` constant (default: 5 m) are left transparent.
3. Map each interpolated dBm value to a color: blue (−90 dBm) → green → yellow → red (−50 dBm).
4. Produce a `CGImage` and pass it to `HeatmapCanvas`.

`HeatmapCanvas` only draws — no logic in the draw closure.

### Band Toggle

Filters samples by `WiFiBand` before IDW. Switching bands triggers a new background `Task`. Fast for typical sample counts (tens to low hundreds).

### SSID Picker

Dropdown in the toolbar, populated from unique SSIDs in the current scan batch. Defaults to the currently connected network. Controls both which samples are displayed and which scan results "Log Reading" pulls from.

---

## Stretch Goal: ARKit Auto-Positioning

Replace manual tap-to-mark with ARKit world tracking. The Mac holds the floor plan; the user walks with an iPhone/iPad running a companion app that reports ARKit position over local network (Bonjour). The Mac app maps ARKit coordinates to floor plan coordinates using the same two-point calibration. Not in scope for MVP.
