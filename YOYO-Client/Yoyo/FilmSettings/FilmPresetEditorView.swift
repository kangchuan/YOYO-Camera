import simd
import SwiftUI

struct FilmPresetEditorView: View {
    let presetIndex: Int
    var onDismiss: () -> Void
    @ObservedObject private var debugManager = FilmPresetDebugManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var draft: FilmPreset?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.trailing, 4)

                Text(draft?.name ?? String.filmPresetEditorTitle.localized)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: reset) {
                    Text(String.filmReset.localized)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(4)
                }

                Button(action: copyConfig) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .padding(8)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 4)

            ScrollView(.horizontal, showsIndicators: true) {
                if let draft {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(spacing: 16) {
                            Text(String.filmSectionExposure.localized).font(.caption).bold().foregroundColor(.gray)

                            ParamSlider(title: String.filmParamExposureTitle.localized, subtitle: String.filmParamExposureSubtitle.localized, description: desc(String.filmParamExposureDesc, String.filmParamExposureDescZh), value: Binding(
                                get: { draft.negativeExposure },
                                set: { val in update { $0 = $0.copy(negativeExposure: val) } }
                            ), range: -1.0 ... 1.0)

                            ParamSlider(title: String.filmParamGammaTitle.localized, subtitle: String.filmParamGammaSubtitle.localized, description: desc(String.filmParamGammaDesc, String.filmParamGammaDescZh), value: Binding(
                                get: { draft.developmentGamma },
                                set: { val in update { $0 = $0.copy(developmentGamma: val) } }
                            ), range: 0.0 ... 2.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text(String.filmSectionContrast.localized).font(.caption).bold().foregroundColor(.gray)

                            ParamSlider(title: String.filmParamContrastTitle.localized, subtitle: String.filmParamContrastSubtitle.localized, description: desc(String.filmParamContrastDesc, String.filmParamContrastDescZh), value: Binding(
                                get: { draft.printContrast },
                                set: { val in update { $0 = $0.copy(printContrast: val) } }
                            ), range: 0.0 ... 1.5)

                            ParamSlider(title: String.filmParamWarmthTitle.localized, subtitle: String.filmParamWarmthSubtitle.localized, description: desc(String.filmParamWarmthDesc, String.filmParamWarmthDescZh), value: Binding(
                                get: { draft.printWarmth },
                                set: { val in update { $0 = $0.copy(printWarmth: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text(String.filmSectionColorDensity.localized).font(.caption).bold().foregroundColor(.gray)

                            ParamSlider(title: String.filmParamDyeDensityTitle.localized, subtitle: String.filmParamDyeDensitySubtitle.localized, description: desc(String.filmParamDyeDensityDesc, String.filmParamDyeDensityDescZh), value: Binding(
                                get: { draft.dyeDensity },
                                set: { val in update { $0 = $0.copy(dyeDensity: val) } }
                            ), range: 0.0 ... 2.0)

                            ParamSlider(title: String.filmParamCrosstalkTitle.localized, subtitle: String.filmParamCrosstalkSubtitle.localized, description: desc(String.filmParamCrosstalkDesc, String.filmParamCrosstalkDescZh), value: Binding(
                                get: { draft.colorCrosstalk },
                                set: { val in update { $0 = $0.copy(colorCrosstalk: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text(String.filmSectionHighlightShadow.localized).font(.caption).bold().foregroundColor(.gray)

                            ParamSlider(title: String.filmParamRolloffTitle.localized, subtitle: String.filmParamRolloffSubtitle.localized, description: desc(String.filmParamRolloffDesc, String.filmParamRolloffDescZh), value: Binding(
                                get: { draft.highlightRolloff },
                                set: { val in update { $0 = $0.copy(highlightRolloff: val) } }
                            ), range: 0.0 ... 1.0)

                            ParamSlider(title: String.filmParamShadowLiftTitle.localized, subtitle: String.filmParamShadowLiftSubtitle.localized, description: desc(String.filmParamShadowLiftDesc, String.filmParamShadowLiftDescZh), value: Binding(
                                get: { draft.shadowLift },
                                set: { val in update { $0 = $0.copy(shadowLift: val) } }
                            ), range: 0.0 ... 1.0)

                            ParamSlider(title: String.filmParamAdjacencyTitle.localized, subtitle: String.filmParamAdjacencySubtitle.localized, description: desc(String.filmParamAdjacencyDesc, String.filmParamAdjacencyDescZh), value: Binding(
                                get: { draft.adjacencyStrength },
                                set: { val in update { $0 = $0.copy(adjacencyStrength: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text(String.filmSectionLayerSpeeds.localized).font(.caption).bold().foregroundColor(.gray)
                            SIMD3Sliders(title: String.filmParamSpeedsRgbTitle.localized, subtitle: String.filmParamSpeedsRgbSubtitle.localized, description: desc(String.filmParamSpeedsRgbDesc, String.filmParamSpeedsRgbDescZh), value: Binding(
                                get: { draft.layerSpeeds },
                                set: { val in update { $0 = $0.copy(layerSpeeds: val) } }
                            ), range: 0.5 ... 1.5)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text(String.filmSectionCrossovers.localized).font(.caption).bold().foregroundColor(.gray)
                            SIMD3Sliders(title: String.filmParamXOverTitle.localized, subtitle: String.filmParamXOverSubtitle.localized, description: desc(String.filmParamXOverDesc, String.filmParamXOverDescZh), value: Binding(
                                get: { draft.layerCrossovers },
                                set: { val in update { $0 = $0.copy(layerCrossovers: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text(String.filmSectionHalationPower.localized).font(.caption).bold().foregroundColor(.gray)

                            ParamSlider(title: String.filmParamHalationStrengthTitle.localized, subtitle: String.filmParamHalationStrengthSubtitle.localized, description: desc(String.filmParamHalationStrengthDesc, String.filmParamHalationStrengthDescZh), value: Binding(
                                get: { draft.halationStrength },
                                set: { val in update { $0 = $0.copy(halationStrength: val) } }
                            ), range: 0.0 ... 5.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text(String.filmSectionHalationCore.localized).font(.caption).bold().foregroundColor(.gray)

                            SIMD3Sliders(title: String.filmParamTintCoreTitle.localized, subtitle: String.filmParamTintCoreSubtitle.localized, description: desc(String.filmParamTintCoreDesc, String.filmParamTintCoreDescZh), value: Binding(
                                get: { draft.halationTintCore },
                                set: { val in update { $0 = $0.copy(halationTintCore: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text(String.filmSectionHalationMid.localized).font(.caption).bold().foregroundColor(.gray)

                            SIMD3Sliders(title: String.filmParamTintMidTitle.localized, subtitle: String.filmParamTintMidSubtitle.localized, description: desc(String.filmParamTintMidDesc, String.filmParamTintMidDescZh), value: Binding(
                                get: { draft.halationTintMid },
                                set: { val in update { $0 = $0.copy(halationTintMid: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text(String.filmSectionHalationEdge.localized).font(.caption).bold().foregroundColor(.gray)

                            SIMD3Sliders(title: String.filmParamTintEdgeTitle.localized, subtitle: String.filmParamTintEdgeSubtitle.localized, description: desc(String.filmParamTintEdgeDesc, String.filmParamTintEdgeDescZh), value: Binding(
                                get: { draft.halationTintEdge },
                                set: { val in update { $0 = $0.copy(halationTintEdge: val) } }
                            ), range: 0.0 ... 1.0)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text(String.filmSectionMixerRed.localized).font(.caption).bold().foregroundColor(.gray)

                            SIMD3Sliders(title: String.filmParamMixerRedTitle.localized, subtitle: String.filmParamMixerRedSubtitle.localized, description: desc(String.filmParamMixerRedDesc, String.filmParamMixerRedDescZh), value: Binding(
                                get: { draft.channelMixerRed },
                                set: { val in update { $0 = $0.copy(channelMixerRed: val) } }
                            ), range: -0.5 ... 1.5)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text(String.filmSectionMixerGreen.localized).font(.caption).bold().foregroundColor(.gray)

                            SIMD3Sliders(title: String.filmParamMixerGreenTitle.localized, subtitle: String.filmParamMixerGreenSubtitle.localized, description: desc(String.filmParamMixerGreenDesc, String.filmParamMixerGreenDescZh), value: Binding(
                                get: { draft.channelMixerGreen },
                                set: { val in update { $0 = $0.copy(channelMixerGreen: val) } }
                            ), range: -0.5 ... 1.5)
                        }
                        .frame(width: 140)

                        VStack(spacing: 16) {
                            Text(String.filmSectionMixerBlue.localized).font(.caption).bold().foregroundColor(.gray)

                            SIMD3Sliders(title: String.filmParamMixerBlueTitle.localized, subtitle: String.filmParamMixerBlueSubtitle.localized, description: desc(String.filmParamMixerBlueDesc, String.filmParamMixerBlueDescZh), value: Binding(
                                get: { draft.channelMixerBlue },
                                set: { val in update { $0 = $0.copy(channelMixerBlue: val) } }
                            ), range: -0.5 ... 1.5)
                        }
                        .frame(width: 140)
                    }
                    .padding([.horizontal, .bottom])
                }
            }
        }
        .background(Material.ultraThinMaterial)
        .onAppear {
            loadPreset()
        }
        .onChange(of: presetIndex) { _, newValue in
            loadPreset(newValue)
        }
    }

    /// 按当前语言择一显示说明文案：中文环境只出中文说明，英文环境只出英文说明。
    private func desc(_ english: String, _ chinese: String) -> String {
        languageManager.currentLanguage.isChinese ? chinese.localized : english.localized
    }

    private func loadPreset(_ index: Int? = nil) {
        let idx = index ?? presetIndex
        if FilmPreset.all.indices.contains(idx) {
            let original = FilmPreset.all[idx]
            draft = debugManager.getPreset(original: original, index: idx)
        }
    }

    private func update(_ modifier: (inout FilmPreset) -> Void) {
        guard var current = draft else { return }
        modifier(&current)
        draft = current
        debugManager.updatePreset(index: presetIndex, preset: current)
    }

    private func reset() {
        debugManager.resetPreset(index: presetIndex)
        loadPreset()
    }

    private func copyConfig() {
        guard let draft else { return }
        debugManager.copyConfigToClipboard(preset: draft)
    }
}

struct ParamSlider: View {
    let title: String
    let subtitle: String
    let description: String
    @Binding var value: Float
    let range: ClosedRange<Float>

    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: { showDetail = true }) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                        Image(systemName: "info.circle")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .buttonStyle(.plain)
                .alert(isPresented: $showDetail) {
                    Alert(
                        // 按语言择一后，英文环境的 subtitle 就是同一个英文术语，直接拼会变成
                        // "Exposure / Exposure"。相同就只显示一个。
                        title: Text(subtitle.isEmpty || subtitle == title ? title : "\(title) / \(subtitle)"),
                        message: Text(description),
                        dismissButton: .default(Text(String.commonOk.localized))
                    )
                }

                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(.yellow)
            }
            Slider(value: $value, in: range)
                .tint(.yellow)
        }
    }
}

struct SIMD3Sliders: View {
    let title: String
    let subtitle: String
    let description: String
    @Binding var value: SIMD3<Float>
    let range: ClosedRange<Float>

    @ObservedObject private var languageManager = LanguageManager.shared

    @State private var showDetail = false

    /// 按当前语言择一显示说明文案：中文环境只出中文说明，英文环境只出英文说明。
    private func desc(_ english: String, _ chinese: String) -> String {
        languageManager.currentLanguage.isChinese ? chinese.localized : english.localized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { showDetail = true }) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
                    Image(systemName: "info.circle").font(.system(size: 8)).foregroundColor(.gray.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            .alert(isPresented: $showDetail) {
                Alert(
                    // 按语言择一后，英文环境的 subtitle 就是同一个英文术语，直接拼会变成
                        // "Exposure / Exposure"。相同就只显示一个。
                        title: Text(subtitle.isEmpty || subtitle == title ? title : "\(title) / \(subtitle)"),
                    message: Text(description),
                    dismissButton: .default(Text(String.commonOk.localized))
                )
            }

            ParamSlider(title: String.filmParamChannelRLowTitle.localized, subtitle: String.filmParamChannelRLowSubtitle.localized, description: desc(String.filmParamChannelRLowDesc, String.filmParamChannelRLowDescZh), value: Binding(
                get: { value.x },
                set: {
                    var newValue = value
                    newValue.x = $0
                    value = newValue
                }
            ), range: range)

            ParamSlider(title: String.filmParamChannelGMidTitle.localized, subtitle: String.filmParamChannelGMidSubtitle.localized, description: desc(String.filmParamChannelGMidDesc, String.filmParamChannelGMidDescZh), value: Binding(
                get: { value.y },
                set: {
                    var newValue = value
                    newValue.y = $0
                    value = newValue
                }
            ), range: range)

            ParamSlider(title: String.filmParamChannelBHighTitle.localized, subtitle: String.filmParamChannelBHighSubtitle.localized, description: desc(String.filmParamChannelBHighDesc, String.filmParamChannelBHighDescZh), value: Binding(
                get: { value.z },
                set: {
                    var newValue = value
                    newValue.z = $0
                    value = newValue
                }
            ), range: range)
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}