//
//  AppearanceSettingsSection.swift
//  FinanceTracker
//
//  Created by Enzo on 10/15/25.
//
import SwiftUI
import SageKit

private struct ColorPalette: Identifiable {
    let id = UUID()
    let name: String
    let needs: Color
    let wants: Color
    let savings: Color

    static let presets: [ColorPalette] = [
        ColorPalette(
            name: "Default",
            needs:   Color("NeedColor"),
            wants:   Color("WantColor"),
            savings: Color("SavingColor")
        ),
        // Triadic — three hues 120° apart on the color wheel, high contrast
        ColorPalette(
            name: "Primary",
            needs:   Color(red: 0.08, green: 0.40, blue: 0.75),  // #1565C0 blue (220°)
            wants:   Color(red: 0.90, green: 0.22, blue: 0.21),  // #E53935 red (0°)
            savings: Color(red: 0.98, green: 0.66, blue: 0.15)   // #F9A825 amber (40°→120°)
        ),
        ColorPalette(
            name: "Jewel",
            needs:   Color(red: 0.42, green: 0.11, blue: 0.60),  // #6A1B9A purple (280°)
            wants:   Color(red: 0.90, green: 0.32, blue: 0.00),  // #E65100 deep orange (20°)
            savings: Color(red: 0.00, green: 0.41, blue: 0.36)   // #00695C dark teal (172°)
        ),
        ColorPalette(
            name: "Electric",
            needs:   Color(red: 0.01, green: 0.53, blue: 0.82),  // #0288D1 cerulean (202°)
            wants:   Color(red: 0.85, green: 0.11, blue: 0.38),  // #D81B60 magenta (322°)
            savings: Color(red: 0.98, green: 0.66, blue: 0.15)   // #F9A825 amber (82°)
        ),
        ColorPalette(
            name: "Vivid",
            needs:   Color(red: 0.36, green: 0.37, blue: 0.89),  // #5C5FE4 indigo
            wants:   Color(red: 0.96, green: 0.64, blue: 0.38),  // #F4A261 amber
            savings: Color(red: 0.18, green: 0.77, blue: 0.71)   // #2EC4B6 cyan
        ),
        ColorPalette(
            name: "Sunset",
            needs:   Color(red: 1.00, green: 0.42, blue: 0.21),  // #FF6B35 coral
            wants:   Color(red: 0.48, green: 0.18, blue: 0.55),  // #7B2D8B violet
            savings: Color(red: 0.00, green: 0.71, blue: 0.85)   // #00B4D8 sky
        ),
        ColorPalette(
            name: "Earthy",
            needs:   Color(red: 0.75, green: 0.36, blue: 0.18),  // #C05C2E terracotta
            wants:   Color(red: 0.83, green: 0.63, blue: 0.09),  // #D4A017 gold
            savings: Color(red: 0.29, green: 0.48, blue: 0.62)   // #4A7B9D slate
        ),
        ColorPalette(
            name: "Pastel",
            needs:   Color(red: 0.48, green: 0.56, blue: 0.83),  // #7B8FD4 periwinkle
            wants:   Color(red: 0.95, green: 0.65, blue: 0.35),  // #F2A65A peach
            savings: Color(red: 0.49, green: 0.75, blue: 0.56)   // #7DBF8E sage green
        ),
    ]
}

struct AppearanceSettingsSection: View {
    @Environment(AppConfiguration.self) private var config

    func appearanceFill(_ appearance: AppConfiguration.Appearance) -> UIColor {
        switch appearance {
        case .light:
            return UIColor(.sageBackground).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        case .dark:
            return UIColor(.sageBackground).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        case .system: return .darkGray
        }
    }

    var body: some View {
        @Bindable var config = config
        List {
            Section {
                ForEach(AppConfiguration.Appearance.allCases, id: \.self) { appearance in
                    Button {
                        config.selectedAppearance = appearance
                    } label: {
                        HStack {
                            ZStack(alignment: .center) {
                                Rectangle()
                                    .fill(Color(uiColor: appearanceFill(appearance)))
                                    .frame(width: 50, height: 50)
                                    .cornerRadius(10)

                                Text("Aa")
                                    .font(.title3)
                                    .foregroundStyle(appearance == .light ? .black : .white)
                            }

                            VStack(alignment: .leading) {
                                Text(appearance.rawValue).tag(appearance)
                                    .font(.title2)
                                Text(
                                    appearance == .system ? "Use the default system appearance"
                                    : "Always use a \(appearance.rawValue.lowercased()) appearance"
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if config.selectedAppearance == appearance {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel(appearance.rawValue)
                    .accessibilityValue(config.selectedAppearance == appearance ? "Selected" : "Not selected")
                    .accessibilityAddTraits(config.selectedAppearance == appearance ? .isSelected : [])
                }
            } header: {
                Text("App Theme")
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(ColorPalette.presets) { palette in
                            Button {
                                withAnimation(.spring(duration: 0.25)) {
                                    config.needsColor   = palette.needs
                                    config.wantsColor   = palette.wants
                                    config.savingsColor = palette.savings
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    HStack(spacing: 4) {
                                        ForEach([palette.needs, palette.wants, palette.savings], id: \.self) { color in
                                            Circle().fill(color).frame(width: 20, height: 20)
                                        }
                                    }
                                    Text(palette.name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(.cardBackground), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(palette.name) color palette")
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                ForEach(ExpenseCategory.allCases, id: \.self) { category in
                    HStack {
                        Circle()
                            .fill(category.color(in: config.categoryColors))
                            .frame(width: 14, height: 14)
                        Text(category.rawValue)
                        Spacer()
                        switch category {
                        case .needs:
                            ColorPicker("Needs color", selection: $config.needsColor, supportsOpacity: false)
                                .labelsHidden()
                        case .wants:
                            ColorPicker("Wants color", selection: $config.wantsColor, supportsOpacity: false)
                                .labelsHidden()
                        case .savings:
                            ColorPicker("Savings color", selection: $config.savingsColor, supportsOpacity: false)
                                .labelsHidden()
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            } header: {
                Text("Category Colors")
            }
        }
        .settingsBackground()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    @Previewable @State var appConfig = AppConfiguration.preview
    AppearanceSettingsSection()
        .environment(appConfig)
        .preferredColorScheme(appConfig.selectedAppearance.colorScheme)
}
