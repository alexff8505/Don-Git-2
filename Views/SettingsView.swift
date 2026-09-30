import SwiftUI

struct SettingsView: View {
    @Binding var appearance: AppAppearance

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text("System follows your Mac’s appearance. Your choice is remembered.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
