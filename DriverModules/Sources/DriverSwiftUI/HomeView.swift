//
//  HomeView.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import DesignSystem
import DriverDomain
import DriverPresentation
import FeatureContracts
import FloatingPanel
import MapKit
import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var model: HomeViewModel
    let onOutput: (HomeOutput) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DriverMapView(trips: model.state.contentSnapshot?.trips ?? [])
            .ignoresSafeArea(.all)
            .floatingPanel { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        sectionHeading("Next scheduled trip")
                        nextTripCard
                        sectionHeading("Today's assignments")
                        content
                    }
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, DriverTheme.innerMargin)
                    .padding(.vertical, 16)
                }
                .floatingPanelScrollTracking(proxy: proxy)
                .background(Color(DriverTheme.panelColor))
            }
            .floatingPanelLayout(HomeFloatingPanelLayout())
            .floatingPanelSurfaceAppearance(.transparent(cornerRadius: DriverTheme.cornerRadius + 4))
            .floatingPanelGrabberHandlePadding(8)
            .accessibilityElement(children: .contain)
        .navigationTitle("Driver")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.state.isBusy)
                .accessibilityLabel("Refresh")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    onOutput(.showProfile)
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Profile")
            }
        }
        .onAppear {
            model.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.state.isBusy)
    }

    @ViewBuilder
    private var header: some View {
        let snapshot = model.state.contentSnapshot
        let isAvailable = snapshot?.availability == .available
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Driver availability")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(snapshot.map { HomePresentationFormatting.title(for: $0.availability) } ?? "Loading")
                    .font(.title3.weight(.bold))
                    .foregroundColor(snapshot == nil ? .primary : Color(DriverTheme.statusColor(isAvailable: isAvailable)))
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                model.toggleAvailability()
            } label: {
                Label(isAvailable ? "Go unavailable" : "Go available", systemImage: "power")
                    .font(.headline)
                    .frame(minWidth: 150, minHeight: DriverTheme.controlHeight)
            }
            .buttonStyle(AvailabilityButtonStyle(isAvailable: isAvailable))
            .disabled(model.state.isBusy || snapshot == nil)
            .opacity(model.state.isBusy || snapshot == nil ? 0.55 : 1)
            .accessibilityHint("Changes whether you can receive scheduled mobility work.")
        }
    }

    @ViewBuilder
    private var nextTripCard: some View {
        Group {
            if let trip = model.state.contentSnapshot?.nextTrip {
                Button {
                    onOutput(.showTrip(trip.id))
                } label: {
                    nextTripContent(trip)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the next scheduled trip.")
            } else {
                nextTripContent(nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(DriverTheme.cardColor))
        .clipShape(RoundedRectangle(cornerRadius: DriverTheme.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func nextTripContent(_ trip: ScheduledTrip?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let trip {
                Text(HomePresentationFormatting.timeFormatter.string(from: trip.scheduledPickupAt))
                    .font(.title2.weight(.bold))
                Text("\(trip.pickupName) to \(trip.dropoffName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("\(HomePresentationFormatting.title(for: trip.assignment)) assignment · View trip")
                    .font(.caption.weight(.bold))
                    .foregroundColor(trip.assignment == .primary ? Color(DriverTheme.brandColor) : Color(DriverTheme.accentColor))
            } else {
                Text("No scheduled pickup")
                    .font(.title3.weight(.bold))
                Text("No scheduled pickup is assigned today.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Stand by")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.bold))
            .foregroundColor(.primary)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = model.state.contentSnapshot {
            if snapshot.trips.isEmpty {
                Text("No scheduled trips are assigned today.")
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(snapshot.trips) { trip in
                        Button {
                            onOutput(.showTrip(trip.id))
                        } label: {
                            TripRow(trip: trip)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens trip details.")

                        if trip.id != snapshot.trips.last?.id {
                            Divider().background(Color(DriverTheme.separatorColor))
                        }
                    }
                }
            }
        } else if case .failure(let message) = model.state {
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    model.refresh()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: DriverTheme.controlHeight)
                }
                .buttonStyle(AvailabilityButtonStyle(isAvailable: false))
                .disabled(model.state.isBusy)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 96)
        }
    }

    private var message: String {
        switch model.state {
        case .initial, .loading:
            return "Checking assignments..."
        case .empty:
            return "No scheduled trips are assigned today."
        case .content(let snapshot), .refreshing(let snapshot), .updatingAvailability(let snapshot):
            guard let nextTrip = snapshot.nextTrip else { return "No scheduled trips are assigned today." }
            let time = HomePresentationFormatting.timeFormatter.string(from: nextTrip.scheduledPickupAt)
            return "Next pickup at \(time) from \(nextTrip.pickupName)."
        case .refreshFailed(_, let message), .failure(let message):
            return message
        }
    }
}

private final class HomeFloatingPanelLayout: FloatingPanelBottomLayout {
    override var initialState: FloatingPanelState { .half }

    override var anchors: [FloatingPanelState: FloatingPanelLayoutAnchoring] {
        [
            .full: FloatingPanelLayoutAnchor(absoluteInset: 18, edge: .top, referenceGuide: .safeArea),
            .half: FloatingPanelLayoutAnchor(fractionalInset: 0.52, edge: .bottom, referenceGuide: .safeArea),
            .tip: FloatingPanelLayoutAnchor(absoluteInset: 92, edge: .bottom, referenceGuide: .safeArea)
        ]
    }

    override func backdropAlpha(for state: FloatingPanelState) -> CGFloat {
        0
    }
}

private struct TripRow: View {
    let trip: ScheduledTrip
    private let resolver = TripActionResolver()

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: DriverTheme.cardCornerRadius, style: .continuous)
                    .fill(trip.assignment == .primary ? Color(DriverTheme.brandColor) : Color(DriverTheme.accentColor))
                Image(systemName: trip.assignment == .primary ? "checkmark" : "exclamationmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(HomePresentationFormatting.timeFormatter.string(from: trip.scheduledPickupAt)) · \(trip.pickupName)")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)
                Text("\(HomePresentationFormatting.title(for: trip.assignment)) to \(trip.dropoffName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(HomePresentationFormatting.title(for: resolver.nextAction(for: trip)))
                    .font(.caption.weight(.bold))
                    .foregroundColor(Color(DriverTheme.brandColor))
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 12)
        .frame(minHeight: DriverTheme.minimumTouchTarget)
        .accessibilityElement(children: .combine)
    }
}

private struct AvailabilityButtonStyle: ButtonStyle {
    let isAvailable: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: DriverTheme.cardCornerRadius, style: .continuous)
                    .fill(Color(isAvailable ? DriverTheme.destructiveColor : DriverTheme.brandColor))
            )
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

private struct DriverMapView: UIViewRepresentable {
    let trips: [ScheduledTrip]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = true
        mapView.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 11.5564, longitude: 104.9282),
                latitudinalMeters: 9_000,
                longitudinalMeters: 9_000
            ),
            animated: false
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let existingIDs = Set(mapView.annotations.compactMap { ($0 as? TripAnnotation)?.tripID })
        let newIDs = Set(trips.map(\.id))
        guard existingIDs != newIDs else { return }

        mapView.removeAnnotations(mapView.annotations)
        mapView.addAnnotations(trips.map(TripAnnotation.init))
    }
}

private final class TripAnnotation: NSObject, MKAnnotation {
    let tripID: UUID
    let title: String?
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D

    init(trip: ScheduledTrip) {
        self.tripID = trip.id
        self.title = trip.pickupName
        self.subtitle = HomePresentationFormatting.title(for: trip.assignment)
        self.coordinate = CLLocationCoordinate2D(
            latitude: trip.pickupCoordinate.latitude,
            longitude: trip.pickupCoordinate.longitude
        )
    }
}
