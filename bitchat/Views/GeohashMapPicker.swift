//
//  GeohashMapPicker.swift
//  bitchat
//
//  Full-screen geohash map picker. Wraps GeohashMapView (MKMapView) with
//  precision controls, a center-pin indicator, and a Select button.
//  Mirrors the UX of the Android GeohashPickerActivity.
//

import SwiftUI
import MapKit

#if os(iOS)

struct GeohashMapPicker: View {
    /// Binding that tells the parent to close this view.
    @Binding var isPresented: Bool
    /// Called with the selected geohash when the user confirms.
    var onSelect: (String) -> Void
    /// Optional initial geohash to center the map on.
    var initialGeohash: String?

    // MARK: - State

    @State private var selectedGeohash: String = ""
    @State private var precision: Int = 5
    @State private var precisionPinned: Bool = false
    @State private var mapView: MKMapView? = nil
    @State private var isWaitingForLocation: Bool = false
    @ObservedObject private var locationState = LocationStateManager.shared
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Derived

    private var levelName: String {
        GeohashChannelLevel.levelForGeohashLength(selectedGeohash.count).displayName
    }

    /// Human-readable approximate cell size for a given geohash precision.
    private func cellSizeDescription(for p: Int) -> String {
        switch p {
        case 1:  return "~5,000 km"
        case 2:  return "~1,250 km"
        case 3:  return "~156 km"
        case 4:  return "~39 km"
        case 5:  return "~5 km"
        case 6:  return "~1.2 km"
        case 7:  return "~152 m"
        case 8:  return "~38 m"
        default: return "~5 m"
        }
    }

    private var initialCoordinate: CLLocationCoordinate2D? {
        if let gh = initialGeohash, !gh.isEmpty {
            let center = Geohash.decodeCenter(gh)
            return CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon)
        }
        // Fall back to user's current location channel
        if case .location(let ch) = LocationChannelManager.shared.selectedChannel {
            let center = Geohash.decodeCenter(ch.geohash)
            return CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon)
        }
        // Fall back to first available nearby channel
        if let first = LocationChannelManager.shared.availableChannels.first {
            let center = Geohash.decodeCenter(first.geohash)
            return CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon)
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Map layer
            GeohashMapView(
                selectedGeohash: $selectedGeohash,
                precision: $precision,
                precisionPinned: $precisionPinned,
                mapView: $mapView,
                initialCoordinate: initialCoordinate
            )
            .ignoresSafeArea()

            // Center crosshair
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(Theme.mapGreen.opacity(0.6))
                .allowsHitTesting(false)

            VStack {
                // Top instruction pill
                instructionPill
                    .padding(.top, 8)

                Spacer()

                // Bottom controls
                VStack(spacing: 12) {
                    HStack {
                        Spacer()
                        myLocationButton
                    }
                    geohashLabel
                    precisionControls
                    selectButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                            .background(Circle().fill(Material.thin))
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }
        }
        .onAppear {
            if let gh = initialGeohash, !gh.isEmpty {
                precision = gh.count
            }
        }
        // Watch for location updates if we're waiting for them
        .onChange(of: locationState.locationUpdateTick) { _, _ in
            if isWaitingForLocation, let loc = locationState.lastLocation {
                let gh = Geohash.encode(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, precision: 8)
                snapTo(geohash: gh)
            }
        }
    }

    // MARK: - Subviews

    private var instructionPill: some View {
        Text(LanguageManager.shared.localizedString("map_picker.instruction"))
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
    }

    private var myLocationButton: some View {
        Button(action: flyToMyLocation) {
            Image(systemName: "location.fill")
                .font(.system(size: 20))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.ultraThinMaterial))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
    }

    private var geohashLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.circle.fill")
                .foregroundColor(Theme.mapGreen)
            Text("#\(selectedGeohash)")
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            Text("• \(levelName)")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private var precisionControls: some View {
        let green = Theme.mapGreen
        let level = GeohashChannelLevel.levelForGeohashLength(precision)
        return HStack(spacing: 16) {
            Button(action: decreasePrecision) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(precision <= 1 ? .gray : green)
            }
            .disabled(precision <= 1)

            VStack(spacing: 3) {
                // Precision number — the geohash string length (1 = widest, 9 = tightest).
                Text(LanguageManager.shared.localizedString("map_picker.precision") + " \(precision)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                // Level name + approx. cell size so the number has meaning.
                Text("\(level.displayName) · \(cellSizeDescription(for: precision))")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 150)

            Button(action: increasePrecision) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(precision >= 9 ? .gray : green)
            }
            .disabled(precision >= 9)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private var selectButton: some View {
        Button(action: confirmSelection) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text(LanguageManager.shared.localizedString("map_picker.select"))
                    .fontWeight(.semibold)
            }
            .font(.system(size: 16, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundColor(.white)
            .background(
                selectedGeohash.isEmpty
                    ? Color.gray
                    : Theme.mapGreen
            )
            .cornerRadius(14)
        }
        .disabled(selectedGeohash.isEmpty)
    }

    // MARK: - Actions

    private func decreasePrecision() {
        guard precision > 1 else { return }
        precision -= 1
        precisionPinned = true
    }

    private func increasePrecision() {
        guard precision < 9 else { return }
        precision += 1
        precisionPinned = true
    }

    private func confirmSelection() {
        guard !selectedGeohash.isEmpty else { return }
        onSelect(selectedGeohash)
        isPresented = false
    }

    private func flyToMyLocation() {
        // Obey user in-app toggle if they previously made a decision
        if !locationState.isLocationUserEnabled && locationState.permissionState != .notDetermined {
            return
        }

        // If we already have a location, jump there immediately to feel responsive
        if locationState.permissionState == .authorized, let loc = locationState.lastLocation {
            let gh = Geohash.encode(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, precision: 8)
            snapTo(geohash: gh)
            // Note: intentionally continuing to let enableLocationChannels() request a fresh one
            // in case the user moved since lastLocation was fetched.
        }
        
        isWaitingForLocation = true
        locationState.enableLocationChannels()
    }

    private func snapTo(geohash: String) {
        isWaitingForLocation = false
        selectedGeohash = geohash
        precision = 8
        // IMPORTANT: Let the map naturally track zoom level changes when the user pinches manually later!
        precisionPinned = false
        
        // Snap map strongly to the new center
        if let map = mapView {
            let center = Geohash.decodeCenter(geohash)
            let coord = CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon)
            let targetSpan = GeohashMapView.spanForPrecision(8)
            let region = MKCoordinateRegion(center: coord, span: targetSpan)
            map.setRegion(region, animated: true)
        }
    }
}

#endif
