//
//  GeohashMapView.swift
//  bitchat
//
//  MKMapView wrapped in UIViewRepresentable for geohash cell visualization.
//  Draws the center cell (selected) and its 8 neighbors as polygon overlays.
//

import SwiftUI
import MapKit

#if os(iOS)

// MARK: - Coordinator

/// Bridges MKMapViewDelegate callbacks into SwiftUI bindings.
final class GeohashMapCoordinator: NSObject, MKMapViewDelegate {
    var parent: GeohashMapView
    var lastPrecision: Int?
    /// Debounce timer so we don't re-compute overlays on every pixel pan.
    private var debounce: Timer?

    init(_ parent: GeohashMapView) {
        self.parent = parent
    }

    // MARK: MKMapViewDelegate

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.parent.recalculate(mapView: mapView)
            self.lastPrecision = self.parent.precision
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polygon = overlay as? GeohashPolygon {
            let renderer = MKPolygonRenderer(polygon: polygon)
            let green = UIColor(red: 0, green: 0.78, blue: 0.32, alpha: 1.0)  // #00C851
            if polygon.isSelected {
                // Center cell: thick visible border + subtle fill so it pops on any basemap.
                renderer.strokeColor = green
                renderer.lineWidth = 5
                renderer.fillColor = green.withAlphaComponent(0.18)
            } else {
                // Neighbor cells: green-tinted border so the whole grid reads as one system.
                renderer.strokeColor = green.withAlphaComponent(0.45)
                renderer.lineWidth = 1.5
                renderer.fillColor = .clear
            }
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let label = annotation as? GeohashLabel else { return nil }
        let id = "GeohashLabel"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
            ?? MKAnnotationView(annotation: label, reuseIdentifier: id)
        view.annotation = label
        view.canShowCallout = false

        let lbl = UILabel()
        lbl.text = label.geohash
        lbl.font = UIFont.monospacedSystemFont(ofSize: label.isSelected ? 13 : 11, weight: .bold)
        lbl.textColor = label.isSelected
            ? UIColor(red: 0, green: 0.78, blue: 0.32, alpha: 1)
            : UIColor.secondaryLabel
        lbl.sizeToFit()

        // Remove previous subviews
        view.subviews.forEach { $0.removeFromSuperview() }
        lbl.center = .zero
        lbl.frame.origin = CGPoint(x: -lbl.frame.width / 2, y: -lbl.frame.height / 2)
        view.addSubview(lbl)
        view.frame = lbl.frame
        return view
    }
}

// MARK: - Custom Overlay & Annotation types

/// MKPolygon subclass carrying a selection flag for styling.
final class GeohashPolygon: MKPolygon {
    var isSelected = false
}

/// Lightweight annotation to show a geohash label at a cell center.
final class GeohashLabel: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let geohash: String
    let isSelected: Bool
    var title: String? { nil }

    init(coordinate: CLLocationCoordinate2D, geohash: String, isSelected: Bool) {
        self.coordinate = coordinate
        self.geohash = geohash
        self.isSelected = isSelected
    }
}

// MARK: - UIViewRepresentable

struct GeohashMapView: UIViewRepresentable {
    /// The geohash string selected by the map center.
    @Binding var selectedGeohash: String
    /// Current precision (geohash length). Can be overridden externally.
    @Binding var precision: Int
    /// When true, the user has manually pinned the precision (±).
    @Binding var precisionPinned: Bool
    /// Exposes the underlying map view.
    @Binding var mapView: MKMapView?
    /// Optional initial coordinate to center the map on.
    var initialCoordinate: CLLocationCoordinate2D?

    func makeCoordinator() -> GeohashMapCoordinator {
        GeohashMapCoordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.mapType = .standard
        mapView.pointOfInterestFilter = .excludingAll
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false

        if let coord = initialCoordinate {
            let span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            mapView.setRegion(MKCoordinateRegion(center: coord, span: span), animated: false)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Keep the coordinator's parent reference fresh
        context.coordinator.parent = self
        
        // Pass the map reference up if requested
        DispatchQueue.main.async {
            self.mapView = mapView
        }

        // If the precision was externally changed (e.g., via +/- buttons) and is different from the last tracked value,
        // we should adjust the map zoom to match the new precision.
        if precisionPinned, let last = context.coordinator.lastPrecision, last != precision {
            let targetSpan = Self.spanForPrecision(precision)
            let region = MKCoordinateRegion(center: mapView.centerCoordinate, span: targetSpan)
            mapView.setRegion(region, animated: true)
            context.coordinator.lastPrecision = precision
        }
    }

    // MARK: - Grid calculation

    /// Called by the coordinator on region change to recompute the geohash grid.
    func recalculate(mapView: MKMapView) {
        let center = mapView.centerCoordinate

        // Auto-pick precision unless user pinned it
        let p: Int
        if precisionPinned {
            p = precision
        } else {
            p = Self.autoPrecision(for: mapView)
        }

        let geohash = Geohash.encode(latitude: center.latitude, longitude: center.longitude, precision: p)

        // Remove existing overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations.filter { $0 is GeohashLabel })

        // Build center + neighbor cells
        var allHashes: [(String, Bool)] = []
        for neighbor in Geohash.neighbors(of: geohash) {
            allHashes.append((neighbor, false))
        }
        allHashes.append((geohash, true))

        for (hash, isCenter) in allHashes {
            let bounds = Geohash.decodeBounds(hash)
            let coords = [
                CLLocationCoordinate2D(latitude: bounds.latMin, longitude: bounds.lonMin),
                CLLocationCoordinate2D(latitude: bounds.latMax, longitude: bounds.lonMin),
                CLLocationCoordinate2D(latitude: bounds.latMax, longitude: bounds.lonMax),
                CLLocationCoordinate2D(latitude: bounds.latMin, longitude: bounds.lonMax),
                CLLocationCoordinate2D(latitude: bounds.latMin, longitude: bounds.lonMin) // Close the polygon loop explicitly
            ]
            let polygon = GeohashPolygon(coordinates: coords, count: coords.count)
            polygon.isSelected = isCenter
            // Draw center cell on top so the thick green border covers the thin neighbour borders
            mapView.addOverlay(polygon, level: isCenter ? .aboveLabels : .aboveRoads)

            let cellCenter = Geohash.decodeCenter(hash)
            let label = GeohashLabel(
                coordinate: CLLocationCoordinate2D(latitude: cellCenter.lat, longitude: cellCenter.lon),
                geohash: hash,
                isSelected: isCenter
            )
            mapView.addAnnotation(label)
        }

        // Push state back to SwiftUI
        DispatchQueue.main.async {
            self.selectedGeohash = geohash
            if !self.precisionPinned {
                self.precision = p
            }
        }
    }

    // MARK: - Auto-precision

    /// Picks the geohash precision whose cells are roughly 80–240 px on the current viewport.
    static func autoPrecision(for mapView: MKMapView) -> Int {
        let center = mapView.centerCoordinate
        var chosen = 1

        for p in 1...9 {
            let gh = Geohash.encode(latitude: center.latitude, longitude: center.longitude, precision: p)
            let bounds = Geohash.decodeBounds(gh)

            let sw = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.latMin, longitude: bounds.lonMin))
            let ne = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.latMax, longitude: bounds.lonMax))

            let swPt = mapView.convert(sw.coordinate, toPointTo: mapView)
            let nePt = mapView.convert(ne.coordinate, toPointTo: mapView)

            let cellPx = min(abs(nePt.x - swPt.x), abs(swPt.y - nePt.y))

            if cellPx >= 80 && cellPx <= 240 {
                chosen = p
                break
            }
            if cellPx >= 80 {
                chosen = p
            }
            if cellPx < 80 {
                break
            }
        }
        return max(1, min(9, chosen))
    }

    /// Suggested zoom span for a given precision, used when jumping to a precision.
    static func spanForPrecision(_ p: Int) -> MKCoordinateSpan {
        switch p {
        case 1:  return MKCoordinateSpan(latitudeDelta: 45, longitudeDelta: 45)
        case 2:  return MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)
        case 3:  return MKCoordinateSpan(latitudeDelta: 3, longitudeDelta: 3)
        case 4:  return MKCoordinateSpan(latitudeDelta: 0.7, longitudeDelta: 0.7)
        case 5:  return MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        case 6:  return MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        case 7:  return MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        case 8:  return MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
        default: return MKCoordinateSpan(latitudeDelta: 0.0005, longitudeDelta: 0.0005)
        }
    }
}

#endif
