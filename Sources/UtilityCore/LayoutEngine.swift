import Foundation
import CoreGraphics


public enum WindowAction: String, CaseIterable, Codable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case maximize, center, snapBack, nextDisplay, previousDisplay, nextDisplayMaximize
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .leftThird: return "Left Third"
        case .centerThird: return "Center Third"
        case .rightThird: return "Right Third"
        case .leftTwoThirds: return "Left Two Thirds"
        case .rightTwoThirds: return "Right Two Thirds"
        case .maximize: return "Maximize"
        case .center: return "Center"
        case .snapBack: return "SnapBack"
        case .nextDisplay: return "Next Display"
        case .previousDisplay: return "Previous Display"
        case .nextDisplayMaximize: return "Next Display & Maximize"
        }
    }
    public var fraction: CGRect? {
        switch self {
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .leftThird: return CGRect(x: 0, y: 0, width: 1.0/3, height: 1)
        case .centerThird: return CGRect(x: 1.0/3, y: 0, width: 1.0/3, height: 1)
        case .rightThird: return CGRect(x: 2.0/3, y: 0, width: 1.0/3, height: 1)
        case .leftTwoThirds: return CGRect(x: 0, y: 0, width: 2.0/3, height: 1)
        case .rightTwoThirds: return CGRect(x: 1.0/3, y: 0, width: 2.0/3, height: 1)
        case .maximize: return CGRect(x: 0, y: 0, width: 1, height: 1)
        default: return nil
        }
    }
}

public struct LayoutSettings: Codable, Equatable {
    public var margin: Double = 0
    public var horizontalGap: Double = 0
    public var verticalGap: Double = 0
    public init(margin: Double = 0, horizontalGap: Double = 0, verticalGap: Double = 0) {
        self.margin = margin; self.horizontalGap = horizontalGap; self.verticalGap = verticalGap
    }
}

/// All coordinates use the Accessibility/Quartz top-left coordinate system, in points.
public enum LayoutEngine {
    public static func frame(fraction: CGRect, screen: CGRect, settings: LayoutSettings) -> CGRect {
        let margin = min(max(0, settings.margin), max(0, min(screen.width, screen.height) / 2 - 1))
        let area = screen.insetBy(dx: margin, dy: margin)
        let gapX = min(max(0, settings.horizontalGap), area.width * fraction.width / 2)
        let gapY = min(max(0, settings.verticalGap), area.height * fraction.height / 2)
        let left = fraction.minX > 0 ? gapX / 2 : 0
        let right = fraction.maxX < 0.999999 ? gapX / 2 : 0
        let top = fraction.minY > 0 ? gapY / 2 : 0
        let bottom = fraction.maxY < 0.999999 ? gapY / 2 : 0
        return CGRect(x: area.minX + area.width * fraction.minX + left,
                      y: area.minY + area.height * fraction.minY + top,
                      width: max(1, area.width * fraction.width - left - right),
                      height: max(1, area.height * fraction.height - top - bottom))
    }
    public static func centered(_ window: CGRect, on screen: CGRect) -> CGRect {
        let size = CGSize(width: min(window.width, screen.width), height: min(window.height, screen.height))
        return CGRect(x: screen.midX - size.width/2, y: screen.midY - size.height/2, width: size.width, height: size.height)
    }
    public static func transfer(_ window: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return centered(window, on: target) }
        let width = min(target.width, window.width / source.width * target.width)
        let height = min(target.height, window.height / source.height * target.height)
        let x = target.minX + (window.minX - source.minX) / source.width * target.width
        let y = target.minY + (window.minY - source.minY) / source.height * target.height
        return CGRect(x: min(max(target.minX, x), target.maxX - width),
                      y: min(max(target.minY, y), target.maxY - height), width: width, height: height)
    }
    public static func quartzFrame(_ frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
