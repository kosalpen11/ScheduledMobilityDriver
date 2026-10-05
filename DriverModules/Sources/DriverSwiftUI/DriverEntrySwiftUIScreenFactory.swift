//
//  DriverEntrySwiftUIScreenFactory.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import DesignSystem
import DriverDomain
import DriverPresentation
import FeatureContracts
import SwiftUI
import UIKit

public final class DriverEntrySwiftUIScreenFactory: DriverEntryScreenFactory {
    public init() {}

    public func makeDriverEntryStatus(
        resolution: DriverEntryResolution,
        onOutput: @escaping (DriverEntryOutput) -> Void
    ) -> UIViewController {
        UIHostingController(rootView: DriverEntryStatusView(resolution: resolution, onOutput: onOutput))
    }
}

private struct DriverEntryStatusView: View {
    let resolution: DriverEntryResolution
    let onOutput: (DriverEntryOutput) -> Void

    var body: some View {
        ZStack {
            Color(DriverTheme.panelColor)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    header
                    statusCard
                    primaryButton
                    signOutButton
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 28)
            }
        }
        .navigationTitle("Driver status")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.eyebrow)
                .font(.caption.weight(.bold))
                .foregroundColor(Color(DriverTheme.brandColor))
                .textCase(.uppercase)
            Text(model.title)
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.detail)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: model.symbol)
                    .font(.title2.weight(.bold))
                    .foregroundColor(Color(DriverTheme.brandColor))
                    .frame(width: 42, height: 42)
                    .background(Color(DriverTheme.brandColor).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: DriverTheme.cardCornerRadius, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.cardTitle)
                        .font(.headline)
                    Text(model.cardSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.requirements.isEmpty == false {
                Divider()
                    .background(Color(DriverTheme.separatorColor))
                ForEach(model.requirements, id: \.self) { requirement in
                    Label(requirement, systemImage: "checklist")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DriverTheme.innerMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(DriverTheme.cardColor))
        .clipShape(RoundedRectangle(cornerRadius: DriverTheme.cardCornerRadius, style: .continuous))
    }

    private var primaryButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOutput(model.primaryOutput)
        } label: {
            Text(model.primaryTitle)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: DriverTheme.controlHeight)
        }
        .buttonStyle(EntryPrimaryButtonStyle())
    }

    private var signOutButton: some View {
        Button {
            onOutput(.signOut)
        } label: {
            Text("Use another account")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: DriverTheme.controlHeight)
        }
        .foregroundColor(Color(DriverTheme.destructiveColor))
        .accessibilityHint("Signs out and returns to phone login.")
    }

    private var model: EntryStatusModel {
        EntryStatusModel(resolution: resolution)
    }
}

private struct EntryStatusModel {
    let eyebrow: String
    let title: String
    let detail: String
    let symbol: String
    let cardTitle: String
    let cardSubtitle: String
    let requirements: [String]
    let primaryTitle: String
    let primaryOutput: DriverEntryOutput

    init(resolution: DriverEntryResolution) {
        switch resolution.route {
        case .home:
            self.init(
                eyebrow: "Ready",
                title: "You are ready to drive",
                detail: "Your driver profile is approved and operational requirements are complete.",
                symbol: "checkmark.seal.fill",
                cardTitle: "Operationally eligible",
                cardSubtitle: "Scheduled trips will open from Home.",
                requirements: [],
                primaryTitle: "Retry",
                primaryOutput: .retry
            )
        case .onboarding:
            self.init(
                eyebrow: "Onboarding",
                title: "Complete your driver checklist",
                detail: "Upload the required documents before submitting your application for review.",
                symbol: "doc.badge.plus",
                cardTitle: "Documents required",
                cardSubtitle: "National ID, driving license, and profile photo are required by the backend.",
                requirements: readinessRequirements(from: resolution),
                primaryTitle: "Open checklist",
                primaryOutput: .showOnboarding
            )
        case .applicationReview:
            self.init(
                eyebrow: "Review",
                title: "Application in review",
                detail: "Your documents were submitted. The app will unlock operational workflows after backend approval.",
                symbol: "clock.badge.checkmark",
                cardTitle: "Documents submitted",
                cardSubtitle: "Training or approval may be assigned after review.",
                requirements: readinessRequirements(from: resolution),
                primaryTitle: "Refresh status",
                primaryOutput: .retry
            )
        case .training:
            self.init(
                eyebrow: "Training",
                title: "Training is required",
                detail: "Your profile is approved for the training step. Complete assigned training before going online.",
                symbol: "graduationcap.fill",
                cardTitle: "Training pending",
                cardSubtitle: "Operational actions stay locked until the backend marks training complete.",
                requirements: readinessRequirements(from: resolution),
                primaryTitle: "Refresh status",
                primaryOutput: .retry
            )
        case .rejected:
            self.init(
                eyebrow: "Not approved",
                title: "Application rejected",
                detail: "This driver profile cannot continue unless support or the backend exposes a new action.",
                symbol: "xmark.octagon.fill",
                cardTitle: "Restricted",
                cardSubtitle: "No driver self-service registration or appeal endpoint was verified.",
                requirements: readinessRequirements(from: resolution),
                primaryTitle: "Refresh status",
                primaryOutput: .retry
            )
        case .suspended:
            self.init(
                eyebrow: "Restricted",
                title: "Driver account suspended",
                detail: "Operational workflows are disabled. Contact support if this status looks wrong.",
                symbol: "lock.fill",
                cardTitle: "Access limited",
                cardSubtitle: "Scheduled trip and availability actions are unavailable for suspended drivers.",
                requirements: readinessRequirements(from: resolution),
                primaryTitle: "Refresh status",
                primaryOutput: .retry
            )
        case .readiness:
            self.init(
                eyebrow: "Readiness",
                title: "Requirements still pending",
                detail: "Your profile is approved, but operational readiness is not complete yet.",
                symbol: "exclamationmark.triangle.fill",
                cardTitle: "Outstanding requirements",
                cardSubtitle: "Complete backend-confirmed requirements before entering Home.",
                requirements: readinessRequirements(from: resolution),
                primaryTitle: "View requirements",
                primaryOutput: .showOnboarding
            )
        case .nonDriver:
            self.init(
                eyebrow: "Access",
                title: "This is not a driver account",
                detail: "The signed-in account does not have the backend DRIVER role. Driver registration is admin-managed in the verified API.",
                symbol: "person.crop.circle.badge.exclamationmark",
                cardTitle: "Driver role required",
                cardSubtitle: "Use a driver account or ask an administrator to provision access.",
                requirements: [],
                primaryTitle: "Try again",
                primaryOutput: .retry
            )
        case .missingDriverProfile:
            self.init(
                eyebrow: "Profile",
                title: "Driver profile not found",
                detail: "The account has driver access, but `/drivers/me` did not return a profile. The backend only exposes admin-side driver creation.",
                symbol: "person.text.rectangle.fill",
                cardTitle: "Profile missing",
                cardSubtitle: "Ask an administrator to create or repair the driver profile.",
                requirements: [],
                primaryTitle: "Retry status",
                primaryOutput: .retry
            )
        }
    }

    private init(
        eyebrow: String,
        title: String,
        detail: String,
        symbol: String,
        cardTitle: String,
        cardSubtitle: String,
        requirements: [String],
        primaryTitle: String,
        primaryOutput: DriverEntryOutput
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.cardTitle = cardTitle
        self.cardSubtitle = cardSubtitle
        self.requirements = requirements
        self.primaryTitle = primaryTitle
        self.primaryOutput = primaryOutput
    }
}

private func readinessRequirements(from resolution: DriverEntryResolution) -> [String] {
    guard let profile = resolution.profile else { return [] }
    var values = profile.readiness.missing.map { "Missing \($0.displayTitle)" }
    values += profile.readiness.pendingReview.map { "\($0.displayTitle) pending review" }
    values += profile.readiness.expired.map { "\($0.displayTitle) expired" }
    if profile.readiness.hasActiveVehicle == false {
        values.append("Active vehicle assignment required")
    }
    return values
}

private struct EntryPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: DriverTheme.cardCornerRadius, style: .continuous)
                    .fill(Color(DriverTheme.brandColor))
            )
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}
