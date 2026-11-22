import SwiftUI
import UIKit

/// One place for every APLite animation. Respects the system Reduce Motion setting and an
/// APLite-specific switch, so the whole desktop can degrade to instant state changes on weak
/// devices without touching every feature's code.
enum APLiteAnimation {
    static let reduceMotionKey = "APLite.reduceMotion"

    static var reduced: Bool {
        // When iOS reports the device is warm, drop straight to instant state changes: glass
        // blurs, springs and repetitions are the first thing to cost GPU time and heat the phone.
        let hot = ThermalMonitor.shared.state.rawValue >= ProcessInfo.ThermalState.fair.rawValue
        return UIAccessibility.isReduceMotionEnabled || UserDefaults.standard.bool(forKey: reduceMotionKey) || hot
    }

    static var spring: Animation {
        reduced ? .linear(duration: 0.001) : .spring(response: 0.34, dampingFraction: 0.82)
    }

    static var snappy: Animation {
        reduced ? .linear(duration: 0.001) : .spring(response: 0.24, dampingFraction: 0.7)
    }

    static var gentle: Animation {
        reduced ? .linear(duration: 0.001) : .easeInOut(duration: 0.45)
    }

    static var dock: Animation {
        reduced ? .linear(duration: 0.001) : .spring(response: 0.3, dampingFraction: 0.78)
    }

    /// Runs a state change with the standard spring unless motion is reduced.
    static func perform(_ work: @escaping () -> Void) {
        if reduced { work() } else { withAnimation(spring, work) }
    }

    static func perform(_ animation: Animation, _ work: @escaping () -> Void) {
        if reduced { work() } else { withAnimation(animation, work) }
    }
}
