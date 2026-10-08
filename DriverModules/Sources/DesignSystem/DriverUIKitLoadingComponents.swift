import UIKit

public final class DriverSkeletonBlockView: UIView {
    public init(height: CGFloat, cornerRadius: CGFloat = DriverTheme.cardCornerRadius) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.tertiarySystemFill
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        isAccessibilityElement = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public final class DriverReconnectingIndicatorView: UIView {
    private let activity = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        backgroundColor = DriverTheme.cardColor
        layer.cornerRadius = DriverTheme.cardCornerRadius
        layer.cornerCurve = .continuous

        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.color = DriverTheme.brandColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Reconnecting..."
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [activity, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])

        isAccessibilityElement = true
        accessibilityLabel = "Reconnecting"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setVisible(_ visible: Bool) {
        guard visible == isHidden else { return }
        isHidden = !visible
        if visible {
            activity.startAnimating()
        } else {
            activity.stopAnimating()
        }
    }
}

public extension UIButton {
    func setDriverLoading(_ loading: Bool, title: String) {
        guard var configuration else { return }
        configuration.title = title
        configuration.showsActivityIndicator = loading
        configuration.activityIndicatorColorTransformer = UIConfigurationColorTransformer { _ in
            configuration.baseForegroundColor ?? .white
        }
        self.configuration = configuration
        isEnabled = !loading
    }
}

public final class DriverSessionRestoreMarkView: UIView {
    private let container = UIView()
    private let monogram = UILabel()
    private let badge = UILabel()
    private let roadLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()
    private var path: UIBezierPath?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = DriverTheme.cardColor
        container.layer.cornerRadius = 16
        container.layer.cornerCurve = .continuous
        addSubview(container)

        monogram.translatesAutoresizingMaskIntoConstraints = false
        monogram.text = "M"
        monogram.font = .systemFont(ofSize: 34, weight: .heavy)
        monogram.textColor = DriverTheme.brandColor
        monogram.textAlignment = .center
        container.addSubview(monogram)

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.text = "DEV"
        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = DriverTheme.accentColor
        badge.layer.cornerRadius = 7
        badge.layer.cornerCurve = .continuous
        badge.layer.masksToBounds = true
        badge.textAlignment = .center
        container.addSubview(badge)

        roadLayer.fillColor = UIColor.clear.cgColor
        roadLayer.strokeColor = DriverTheme.separatorColor.cgColor
        roadLayer.lineWidth = 3
        roadLayer.lineCap = .round
        container.layer.addSublayer(roadLayer)

        dotLayer.fillColor = UIColor.systemTeal.cgColor
        container.layer.addSublayer(dotLayer)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 92),
            heightAnchor.constraint(equalToConstant: 92),
            monogram.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            monogram.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            badge.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            badge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
            badge.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 14
        let baselineY = container.bounds.maxY - 20
        let start = CGPoint(x: inset, y: baselineY)
        let end = CGPoint(x: container.bounds.maxX - inset, y: baselineY)
        let control = CGPoint(x: container.bounds.midX, y: baselineY - 14)

        let curve = UIBezierPath()
        curve.move(to: start)
        curve.addQuadCurve(to: end, controlPoint: control)
        path = curve
        roadLayer.path = curve.cgPath

        dotLayer.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 8, height: 8)).cgPath
        if UIAccessibility.isReduceMotionEnabled {
            dotLayer.position = start
        }
    }

    public func startAnimating() {
        guard UIAccessibility.isReduceMotionEnabled == false else { return }
        guard let path else { return }
        if dotLayer.animation(forKey: "driver.restore.dot") != nil { return }
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.path = path.cgPath
        animation.duration = 1.2
        animation.calculationMode = .paced
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        dotLayer.add(animation, forKey: "driver.restore.dot")
    }

    public func stopAnimating() {
        dotLayer.removeAnimation(forKey: "driver.restore.dot")
    }
}
