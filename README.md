# WiFi Heatmap

A macOS app for mapping WiFi signal coverage. Import a floor plan, walk around your space with your Mac, tap to log readings, and watch a signal strength heatmap build up in real time.

![App icon](WifiHeatmap/Assets.xcassets/AppIcon.appiconset/icon_128x128.png)

## What it does

WiFi Heatmap turns your MacBook into a survey instrument. You load a floor plan, set a scale reference, then walk to different spots in your space and tap the corresponding location on the map. The app records the WiFi signal at each point and interpolates a smooth heatmap across the floor plan showing where signal is strong, weak, or absent.

Useful for:
- Finding dead zones before placing a mesh node or extender
- Verifying coverage after adding or repositioning an access point
- Documenting signal quality across a floor for reporting or troubleshooting
- Comparing per-band coverage (2.4 / 5 / 6 GHz) on the same floor plan

## Requirements

- macOS 14 (Sonoma) or later
- [Xcode 16](https://developer.apple.com/xcode/) or later
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Location Services permission — Apple requires this to read access point BSSIDs from CoreWLAN

## Building

```bash
git clone git@github.com:jhludwig/wifiheatmap.git
cd wifiheatmap
xcodegen generate
open WifiHeatmap.xcodeproj
```

Press **⌘R** to build and run, or build from the command line:

```bash
xcodebuild -scheme WifiHeatmap -configuration Debug build
```

On first launch, macOS will ask for Location Services permission. Grant it — without it the app cannot read BSSID information from nearby networks.

## Usage

### 1. Create a document

**File > New** creates a new WiFi survey document (`.wifiheatmap`). These are directory bundles that store the floor plan image and all logged readings together.

### 2. Add a floor

Click the **+** tab in the tab bar at the top of the window to add a floor. You can add as many floors as your building has. Click a tab to switch between floors; right-click a tab to rename or delete it.

### 3. Import a floor plan

Open the inspector panel (the **⊞** button, top-right of the window) and click **Import Floor Plan…** at the bottom. Supported formats: PNG, JPEG, PDF. A clean architectural drawing or even a hand-sketched layout works fine — anything with recognizable room boundaries.

### 4. Calibrate the scale

Before logging readings, the app needs to know the real-world scale of your floor plan. In the inspector, turn on **Calibration Mode**. Two crosshairs appear on the floor plan — drag them to two points whose real-world distance you know (e.g. the ends of a hallway you have measured). Enter the distance when prompted. Turn Calibration Mode off when done.

Calibration is required for the fade radius to reflect meters accurately. Without it the heatmap will still render, but the signal falloff distances will be wrong.

### 5. Log readings

Make sure your Mac is connected to (or can see) the WiFi network you want to map. The inspector's **Status** indicator shows when the scanner is running.

Walk to a location in your space, then click the corresponding spot on the floor plan. The app records the strongest detected signal on the selected band at that moment and places a marker on the map. Repeat across the space — more readings produce a more accurate heatmap. Aim for one reading every 3–5 meters.

**Tips:**
- Use the **Band** picker to select the band your network operates on (most modern networks use 5 GHz).
- Use **Network** to lock scanning to a specific SSID if multiple networks are visible.
- The status bar at the bottom shows the last recorded signal strength so you know a reading was captured.

### 6. View the heatmap

Toggle **Show Heatmap** in the inspector. The heatmap renders immediately from your logged readings using inverse-distance weighting interpolation.

#### Metrics

| Metric | What it shows |
|--------|--------------|
| **RSSI** | Raw received signal strength in dBm. Higher (less negative) is stronger. Range: −90 to −50 dBm. |
| **SNR** | Signal-to-noise ratio in dB. Measures connection quality independent of raw power. Range: 0 to 40 dB. |
| **Channel** | The WiFi channel dominating each area, color-coded by channel number. Useful for identifying interference between overlapping networks. |

#### Color schemes

| Scheme | Description |
|--------|-------------|
| Blue → Red | Classic heatmap: cold colors for weak signal, hot colors for strong. |
| Red → Green | Traffic-light convention: red = poor, green = good. |
| Colorblind Safe | Blue and orange palette, readable for deuteranopia and protanopia. |

The **Fade Radius** slider controls how far each reading's influence spreads in meters. Increase it to smooth over sparse readings; decrease it to show sharp transitions between measurement points.

A **legend** appears at the bottom of the inspector when the heatmap is active.

### 7. Filter by access point

If multiple access points share the same SSID (common in mesh networks), use the **Access Point** picker to isolate one AP by BSSID and see its individual coverage area.

### 8. Delete readings

To remove a misplaced reading, enable **Delete Mode** in the inspector, then click the marker on the map. You can also right-click any marker at any time for a context menu with a delete option. Delete and add operations support full **undo/redo** (⌘Z / ⇧⌘Z).

### 9. Export

Click **Export as PNG…** in the inspector to save the floor plan with the heatmap composited on top. If the heatmap is hidden at export time, only the floor plan is saved.

## Project structure

```
WifiHeatmap/
├── Models/          # Data types: WifiSurvey, Floor, WifiSample, ScannedNetwork
├── Heatmap/         # IDW interpolation, rendering, color schemes, metrics
├── Scanning/        # CoreWLAN wrapper (ScanActor)
├── Views/           # SwiftUI views
│   ├── ContentView.swift       # Document root, floor tab bar
│   ├── FloorTabBar.swift       # Tab bar + inspector toggle
│   ├── FloorDetailView.swift   # Map area + inspector layout
│   ├── FloorPlanView.swift     # Floor plan + heatmap canvas + markers
│   ├── InspectorView.swift     # All controls (band, metric, calibration, etc.)
│   └── HeatmapLegendView.swift # Color scale legend overlay
└── Assets.xcassets/
```

The document format is a directory bundle (`.wifiheatmap`). Floor plan images are stored as PNGs inside the bundle alongside a JSON file containing all survey data.
