//
//  WhatsNewSheet.swift
//  FinanceTracker
//

import SwiftUI
import SageKit

struct WhatsNewSheet: View {
    let release: WhatsNewRelease

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 36) {
                    header

                    if let intro = release.intro {
                        Text(intro)
                            .font(.subheadline)
                    }

                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(release.features) { feature in
                            FeatureRow(
                                icon: feature.icon,
                                title: feature.title,
                                description: feature.description,
                                tint: feature.tint
                            )
                        }
                    }
                    
                }
                .padding(.horizontal, 32)
                .padding(.top, 48)
                .padding(.bottom, 24)
            }

            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.sage)
                    .clipShape(.rect(cornerRadius: 15))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .background(Color.sageBackground)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text("What's New")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text("Version \(release.version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            WhatsNewSheet(release: WhatsNewRelease(
                version: "1.1",
                intro: "A few highlights from this update.",
                features: [
                    WhatsNewFeature(icon: "tag.fill", title: "Multiple Tags per Expense",
                                    description: "An expense is no longer limited to a single tag.")
                ]
            ))
        }
}
