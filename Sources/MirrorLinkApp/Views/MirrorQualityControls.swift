import SwiftUI

/// Edits the preference for the next session, never the snapshot of a running one.
struct MirrorQualityControls: View {
    @ObservedObject private var language = LanguageStore.shared
    @Binding var profile: MirrorQualityProfile

    var body: some View {
        let _ = language.selection
        VStack(alignment: .leading, spacing: 8) {
            Picker(L10n.tr("画质"), selection: $profile) {
                ForEach(MirrorQualityProfile.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 300, alignment: .leading)
            .accessibilityHint(L10n.tr("选择下次开始或重新投屏时使用的画质"))

            Text(L10n.tr("下次投屏时生效。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
