import CatWMKit
import SwiftUI

struct LabPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            Text("Features still in testing. They can change, slow CatWM down or go away.")
                .textStyle(.caption).foregroundStyle(Theme.inkMuted)
            OGroup("Experiments") {
                OptionRows(pane: .lab, section: "Experiments", doc: doc, settingsUI: settingsUI)
            }
            AdditionalOptionGroups(pane: .lab, doc: doc, settingsUI: settingsUI)
        }
    }
}
