//
//  DriverTheme.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/4/26.
//

import UIKit

public enum DriverTheme {
    public static let cornerRadius: CGFloat = 8
    public static let cardCornerRadius: CGFloat = 8
    public static let controlHeight: CGFloat = 52
    public static let minimumTouchTarget: CGFloat = 44
    public static let panelSpacing: CGFloat = 16
    public static let outerMargin: CGFloat = 16
    public static let innerMargin: CGFloat = 16

    public static var brandColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.36, green: 0.78, blue: 0.67, alpha: 1)
                : UIColor(red: 0.00, green: 0.44, blue: 0.35, alpha: 1)
        }
    }

    public static var accentColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.98, green: 0.82, blue: 0.30, alpha: 1)
                : UIColor(red: 0.72, green: 0.43, blue: 0.00, alpha: 1)
        }
    }

    public static var destructiveColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1.00, green: 0.45, blue: 0.42, alpha: 1)
                : UIColor(red: 0.73, green: 0.12, blue: 0.10, alpha: 1)
        }
    }

    public static var panelColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 0.96)
                : UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.96)
        }
    }

    public static var cardColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.13, green: 0.14, blue: 0.15, alpha: 1)
                : UIColor(red: 0.95, green: 0.97, blue: 0.96, alpha: 1)
        }
    }

    public static var separatorColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.10)
                : UIColor(white: 0, alpha: 0.08)
        }
    }

    public static var mapTintColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.22, green: 0.28, blue: 0.31, alpha: 1)
                : UIColor(red: 0.87, green: 0.91, blue: 0.90, alpha: 1)
        }
    }

    public static func statusColor(isAvailable: Bool) -> UIColor {
        isAvailable ? brandColor : destructiveColor
    }
}
