import Foundation
import QuartzCore

package enum DesktopTransitionError: LocalizedError {
    case check(String)
    case occupied
    package var errorDescription: String? {
        switch self {
        case .check(let message): message
        case .occupied: "Move all windows out of the Desktop before removing it"
        }
    }
}
