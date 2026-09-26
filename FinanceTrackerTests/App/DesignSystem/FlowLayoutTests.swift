import SwiftUI
import UIKit
import XCTest

@MainActor
final class FlowLayoutTests: XCTestCase {
    func testOversizedChipsWrapAndReserveTheirFullHeight() async throws {
        for dynamicType in [DynamicTypeSize.large, .accessibility3] {
            for alignment in [HorizontalAlignment.leading, .center] {
                let frames = Frames()
                let names = ["Short", "A very long tag name that must wrap across several lines", "Next"]
                let content = FlowLayout(spacing: 8, alignment: alignment) {
                    ForEach(names.indices, id: \.self) { index in
                        Button {} label: {
                            Text(names[index])
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(.green.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("flow")) } action: {
                            frames.items[index] = $0
                        }
                    }
                }
                .coordinateSpace(name: "flow")
                .environment(\.dynamicTypeSize, dynamicType)

                let host = UIHostingController(rootView: content)
                let size = host.sizeThatFits(in: CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude))
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                host.view.frame = window.bounds
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                // Geometry callbacks arrive on the next SwiftUI update.
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    frames.items.count == names.count
                }, object: nil)
                await fulfillment(of: [ready], timeout: 5)

                let first = try XCTUnwrap(frames.items[0])
                let long = try XCTUnwrap(frames.items[1])
                let next = try XCTUnwrap(frames.items[2])
                for frame in frames.items.values {
                    XCTAssertGreaterThanOrEqual(frame.minX, -0.5)
                    XCTAssertLessThanOrEqual(frame.maxX, 240.5)
                }
                XCTAssertGreaterThan(long.height, first.height)
                XCTAssertEqual(long.minY, first.maxY + 8, accuracy: 0.5)
                XCTAssertEqual(next.minY, long.maxY + 8, accuracy: 0.5)
                XCTAssertEqual(size.height, next.maxY, accuracy: 0.5)
                let expectedX = alignment == .leading ? 0 : (240 - next.width) / 2
                XCTAssertEqual(next.minX, expectedX, accuracy: 0.5)
            }
        }
    }

    func testOrdinaryChipsFitExactlyAndRowsUseTheTallestChild() {
        let host = UIHostingController(rootView: FlowLayout(spacing: 8) {
            Color.clear.frame(width: 80, height: 20)
            Color.clear.frame(width: 112, height: 35)
            Color.clear.frame(width: 60, height: 15)
        })
        let size = host.sizeThatFits(in: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertEqual(size.width, 200)
        XCTAssertEqual(size.height, 35 + 8 + 15)
    }

    func testUnspecifiedWidthUsesTheNaturalRowWidth() {
        let host = UIHostingController(rootView: FlowLayout(spacing: 8) {
            Color.clear.frame(width: 80, height: 20)
            Color.clear.frame(width: 112, height: 35)
        }.fixedSize())
        let size = host.sizeThatFits(in: CGSize(width: 300, height: 300))
        XCTAssertEqual(size, CGSize(width: 200, height: 35))
    }

    func testEmptyLayoutHasNoRowSpacing() {
        let host = UIHostingController(rootView: FlowLayout { EmptyView() })
        let size = host.sizeThatFits(in: CGSize(width: 240, height: 300))
        XCTAssertEqual(size, CGSize(width: 240, height: 0))
    }

    private final class Frames {
        var items: [Int: CGRect] = [:]
    }
}
