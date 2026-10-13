import SwiftUI
import UIKit

/// 开发者选项：内置滤镜注册完整性自检。
///
/// 只在「开发者模式」开启时从设置页进入。用于在新增 / 修改内置滤镜后
/// 一次性确认资源（背景图、LUT、文案、胶片预设）是否齐备，
/// 避免出现「滤镜能选中但没效果 / 描述空白」这类只在运行期才暴露的问题。
struct FilterDiagnosticsSettingsView: View {

    private enum Design {
        static let backgroundColor = Color(white: 0.04)
        static let cardColor = Color(red: 40 / 255, green: 40 / 255, blue: 40 / 255, opacity: 0.4)
        static let errorColor = Color(red: 1, green: 0.45, blue: 0.4)
        static let warningColor = Color(red: 1, green: 0.8, blue: 0.35)
        static let okColor = Color(red: 0.4, green: 0.85, blue: 0.6)
        static let cardPadding: CGFloat = 20
    }

    @State private var report: FilterRegistryDiagnostics.Report?
    @State private var copied = false

    var body: some View {
        ZStack {
            Design.backgroundColor.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summaryCard

                    if let report {
                        if report.issues.isEmpty {
                            healthyCard
                        } else {
                            issueList(report)
                        }
                    }

                    actionBar
                    hintCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle("滤镜完整性自检")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if report == nil { runCheck() }
        }
    }

    // MARK: - 概览

    private var summaryCard: some View {
        GlassCard(cardColor: Design.cardColor, paddingValue: Design.cardPadding) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)

                    Text("内置滤镜注册表")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)

                    Spacer()

                    if let report {
                        Text(report.isHealthy ? "通过" : "有 \(report.issues.count) 项待处理")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(report.isHealthy ? Design.okColor : Design.warningColor)
                    }
                }

                HStack(spacing: 20) {
                    metric(label: "滤镜数量", value: "\(report?.filterCount ?? 0)", color: .white)
                    metric(label: "错误", value: "\(report?.errorCount ?? 0)", color: Design.errorColor)
                    metric(label: "警告", value: "\(report?.warningCount ?? 0)", color: Design.warningColor)
                }

                Text("检查项：注册表与目录一致 · 名称唯一 · 卡片背景图 · LUT 数据集 · 中英文描述 · 胶片预设有效性 · 胶片模拟成员一致性 · 历史数据残留")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }
        }
    }

    private func metric(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.gray)
        }
    }

    // MARK: - 结果

    private var healthyCard: some View {
        GlassCard(cardColor: Design.cardColor, paddingValue: Design.cardPadding) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Design.okColor)
                Text("全部检查通过。当前所有内置滤镜的背景图、LUT、描述文案与胶片预设都已就位。")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func issueList(_ report: FilterRegistryDiagnostics.Report) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("检查结果")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.gray)
                .padding(.leading, 4)

            ForEach(report.sortedIssues) { issue in
                GlassCard(cardColor: Design.cardColor, paddingValue: Design.cardPadding) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(issue.severity.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(issue.severity == .error ? Design.errorColor : Design.warningColor)
                                .cornerRadius(6)

                            Text(issue.check)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                        }

                        Text(issue.filters)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .textSelection(.enabled)

                        Text(issue.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - 操作

    private var actionBar: some View {
        VStack(spacing: 12) {
            Button {
                runCheck()
            } label: {
                Text("重新运行自检")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(14)
            }

            if let report {
                Button {
                    UIPasteboard.general.string = report.plainText
                    copied = true
                } label: {
                    Text(copied ? "已复制到剪贴板" : "复制文字报告")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(14)
                }
            }
        }
    }

    private var hintCard: some View {
        GlassCard(cardColor: Design.cardColor, paddingValue: Design.cardPadding) {
            VStack(alignment: .leading, spacing: 8) {
                Text("怎么用")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)

                Text("新增或修改内置滤镜后跑一次，确认没有漏资源。新增滤镜需要动的文件与命名约定见工程内 docs/FilterExtensionGuide.md；滤镜定义集中在 Filter/BuiltinFilterCatalog.swift。")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 行为

    private func runCheck() {
        copied = false
        report = FilterRegistryDiagnostics.run()
    }
}
