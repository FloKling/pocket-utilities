import Testing
import CoreGraphics

@testable import UtilityCore

final class LayoutEngineTests {
    let screen = CGRect(x: 100, y: 50, width: 1200, height: 900)
    func rect(_ action: WindowAction, settings: LayoutSettings = LayoutSettings()) -> CGRect {
        LayoutEngine.frame(fraction: action.fraction!, screen: screen, settings: settings)
    }
    @Test func testHalves() {
        expectEqual(rect(.leftHalf), CGRect(x: 100, y: 50, width: 600, height: 900))
        expectEqual(rect(.rightHalf), CGRect(x: 700, y: 50, width: 600, height: 900))
        expectEqual(rect(.topHalf), CGRect(x: 100, y: 50, width: 1200, height: 450))
        expectEqual(rect(.bottomHalf), CGRect(x: 100, y: 500, width: 1200, height: 450))
    }
    @Test func testQuarters() {
        for (action, x, y) in [(WindowAction.topLeft, 100.0, 50.0), (.topRight, 700, 50), (.bottomLeft, 100, 500), (.bottomRight, 700, 500)] {
            expectEqual(rect(action), CGRect(x: x, y: y, width: 600, height: 450))
        }
    }
    @Test func testThirdsAndTwoThirds() {
        expectEqual(rect(.leftThird), CGRect(x: 100, y: 50, width: 400, height: 900))
        expectEqual(rect(.centerThird), CGRect(x: 500, y: 50, width: 400, height: 900))
        expectEqual(rect(.rightThird), CGRect(x: 900, y: 50, width: 400, height: 900))
        expectEqual(rect(.leftTwoThirds), CGRect(x: 100, y: 50, width: 800, height: 900))
        expectEqual(rect(.rightTwoThirds), CGRect(x: 500, y: 50, width: 800, height: 900))
    }
    @Test func testMarginsAndGapsDoNotDoubleAtSeams() {
        let settings = LayoutSettings(margin: 10, horizontalGap: 12, verticalGap: 8)
        let left = rect(.topLeft, settings: settings), right = rect(.topRight, settings: settings), bottom = rect(.bottomLeft, settings: settings)
        expectEqual(left.minX, 110)
        expectEqual(left.minY, 60)
        expectEqual(right.minX - left.maxX, 12)
        expectEqual(bottom.minY - left.maxY, 8)
        expectEqual(right.maxX, screen.maxX - 10)
        expectEqual(rect(.maximize, settings: settings), screen.insetBy(dx: 10, dy: 10))
    }
    @Test func testThirdSeams() {
        let options = LayoutSettings(margin: 5, horizontalGap: 18)
        let a = rect(.leftThird, settings: options), b = rect(.centerThird, settings: options), c = rect(.rightThird, settings: options)
        expectEqual(b.minX - a.maxX, 18, accuracy: 0.00001)
        expectEqual(c.minX - b.maxX, 18, accuracy: 0.00001)
        expectEqual(c.maxX, screen.maxX - 5, accuracy: 0.00001)
    }
    @Test func testVariousDisplaysAndExtremeSettingsStayWithinUsableArea() {
        for size in [CGSize(width: 1440, height: 875), CGSize(width: 3440, height: 1440), CGSize(width: 900, height: 1600), CGSize(width: 200, height: 2000)] {
            let area = CGRect(origin: CGPoint(x: -3440, y: -600), size: size)
            for action in WindowAction.allCases where action.fraction != nil {
                for settings in [LayoutSettings(), LayoutSettings(margin: 20, horizontalGap: 10, verticalGap: 8), LayoutSettings(margin: 9999, horizontalGap: 9999, verticalGap: 9999)] {
                    let result = LayoutEngine.frame(fraction: action.fraction!, screen: area, settings: settings)
                    expectGreater(result.width, 0)
                    expectGreater(result.height, 0)
                    expectGreaterOrEqual(result.minX, area.minX)
                    expectGreaterOrEqual(result.minY, area.minY)
                    expectLessOrEqual(result.maxX, area.maxX + 0.0001)
                    expectLessOrEqual(result.maxY, area.maxY + 0.0001)
                }
            }
        }
    }
    @Test func testDisplayTransferPreservesRelativeFrameAndClampsOffscreenWindows() {
        let target = CGRect(x: -900, y: -400, width: 900, height: 1600)
        expectEqual(LayoutEngine.transfer(CGRect(x: 700, y: 50, width: 600, height: 450), from: screen, to: target), CGRect(x: -450, y: -400, width: 450, height: 800))
        let result = LayoutEngine.transfer(CGRect(x: -1000, y: 5000, width: 3000, height: 3000), from: screen, to: target)
        expectEqual(result, target)
    }
    @Test func testQuartzConversionForDisplaysAboveAndBelowPrimary() {
        expectEqual(LayoutEngine.quartzFrame(CGRect(x: -100, y: 900, width: 500, height: 400), primaryHeight: 900), CGRect(x: -100, y: -400, width: 500, height: 400))
        expectEqual(LayoutEngine.quartzFrame(CGRect(x: 0, y: -400, width: 500, height: 400), primaryHeight: 900).minY, 900)
    }
    @Test func testCenterClampsOversizedWindow() {
        expectEqual(LayoutEngine.centered(CGRect(x: 0, y: 0, width: 2000, height: 1000), on: screen), screen)
        expectEqual(LayoutEngine.centered(CGRect(x: 0, y: 0, width: 200, height: 100), on: screen), CGRect(x: 600, y: 450, width: 200, height: 100))
    }
}
