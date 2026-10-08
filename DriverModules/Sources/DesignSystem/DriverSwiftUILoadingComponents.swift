import SwiftUI

public struct DriverSkeletonBlock: View {
    private let height: CGFloat
    private let cornerRadius: CGFloat

    public init(height: CGFloat, cornerRadius: CGFloat = DriverTheme.cardCornerRadius) {
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

public struct DriverReconnectingPill: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Reconnecting...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(DriverTheme.cardColor))
        .clipShape(RoundedRectangle(cornerRadius: DriverTheme.cardCornerRadius, style: .continuous))
        .accessibilityLabel("Reconnecting")
    }
}

public struct DriverPrimaryLoadingLabel: View {
    private let title: String
    private let isLoading: Bool

    public init(title: String, isLoading: Bool) {
        self.title = title
        self.isLoading = isLoading
    }

    public var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .opacity(isLoading ? 0 : 1)
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text(title)
                        .font(.headline)
                        .hidden()
                }
            }
        }
    }
}
