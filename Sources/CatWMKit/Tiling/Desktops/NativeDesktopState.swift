import CoreGraphics
import Foundation

package struct NativeDesktopState {
    package var nativeCatalog = NativeWorkspaceCatalog()
    package var lastNativeCatalogSaved: [String: UInt64] = [:]
    package var lastNativeCatalogHomes: [String: String] = [:]
    package var lastNativeCatalogUUIDs: [String: String] = [:]
    package var nativeMigration: [CGWindowID: String] = [:]
    package var desktopRemovalFailures: [UInt64: Date] = [:]
    package var nativeSortNames: Set<String> = []
    package var nativeDroppedWorkspaces: Set<String> = []
    package var homeSpace: [String: UInt64] = [:]
    package var spaceArrival: (token: Int, action: @MainActor () -> Void)?
}
