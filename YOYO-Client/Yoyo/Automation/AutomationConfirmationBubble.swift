import AVFoundation
import SwiftUI

/// Pending rule information
struct PendingConfirmation: Identifiable {
    let id = UUID()
    let rules: [AutomationRule]
    let settings: CameraSettings
    let toasts: [(type: ToastType, message: String, duration: Double, customIcon: String?)]
    let analysis: SceneAnalysis
    let timestamp: Date
    /// Filter list pending import (downloaded from URL)
    let pendingFilterImports: [(url: String, displayName: String?)]

    var ruleNames: String {
        rules.map(\.name).joined(separator: "、")
    }

    /// UX-08: a one-line human-readable description of what the rule is
    /// about to change (filter / exposure / etc.) so the user can decide
    /// whether to accept without opening the management page.
    var changeSummary: String? {
        var parts: [String] = []

        if let filterName = settings.filter?.name, !filterName.isEmpty {
            parts.append(String.automationSummaryFilter.localized(filterName))
        }
        if let bias = settings.exposureBias {
            let ev = String(format: "%+.1f", bias)
            parts.append(String.automationSummaryExposure.localized(ev))
        }
        if let zoom = settings.zoom {
            parts.append(String.automationSummaryZoom.localized(String(format: "%.1fx", zoom)))
        }
        if let flash = settings.flashMode {
            parts.append(flashLabel(flash))
        }
        if let iso = settings.iso {
            parts.append(String.automationSummaryIso.localized(iso))
        }

        // If the plan came with explicit toast messages, surface the first
        // one too — that is usually the most user-friendly description of
        // what the rule wants to do.
        if let firstToast = toasts.first {
            parts.append(firstToast.message)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func flashLabel(_ mode: AVCaptureDevice.FlashMode) -> String {
        switch mode {
        case .on: return String.automationSummaryFlashOn.localized
        case .off: return String.automationSummaryFlashOff.localized
        case .auto: return String.automationSummaryFlashAuto.localized
        @unknown default: return ""
        }
    }
}

/// Automation rule confirmation bubble
struct AutomationConfirmationBubble: View {
    let pending: PendingConfirmation
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    private let bubbleColor = Color(white: 0.15).opacity(0.4)
    private let accentColor = Color.accentColor
    private let cornerRadius: CGFloat = 12
    private let triangleWidth: CGFloat = 12
    private let triangleHeight: CGFloat = 6
    private let trianglePadding: CGFloat = 16

    var body: some View {
        HStack(spacing: 8) {
            // task info
            VStack(alignment: .leading, spacing: 2) {
                Text(String.automationConfirmPendingTitle.localized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                Text(pending.ruleNames)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // UX-08: a one-line summary of what is about to change so the
                // user can decide whether to accept without having to open
                // the management page.
                if let summary = pending.changeSummary {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            // action buttons
            HStack(spacing: 6) {
                // cancel button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }

                // confirm button
                Button(action: onConfirm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 26, height: 26)
                        .background(accentColor)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .padding(.top, triangleHeight)
        .background {
            BubbleShape(
                cornerRadius: cornerRadius,
                triangleWidth: triangleWidth,
                triangleHeight: triangleHeight,
                trianglePadding: trianglePadding
            )
            .fill(bubbleColor)
            .overlay {
                BubbleShape(
                    cornerRadius: cornerRadius,
                    triangleWidth: triangleWidth,
                    triangleHeight: triangleHeight,
                    trianglePadding: trianglePadding
                )
                .fill(.ultraThinMaterial)
            }
            .overlay {
                BubbleShape(
                    cornerRadius: cornerRadius,
                    triangleWidth: triangleWidth,
                    triangleHeight: triangleHeight,
                    trianglePadding: trianglePadding
                )
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            }
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

/// Rounded rectangle shape with a triangle
struct BubbleShape: Shape {
    let cornerRadius: CGFloat
    let triangleWidth: CGFloat
    let triangleHeight: CGFloat
    let trianglePadding: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let bubbleRect = CGRect(
            x: rect.minX,
            y: rect.minY + triangleHeight,
            width: rect.width,
            height: rect.height - triangleHeight
        )

        // start point: top-left cornerbefore the rounded corner starts, near the triangle
        path.move(to: CGPoint(x: bubbleRect.minX + trianglePadding, y: bubbleRect.minY))

        // triangle
        path.addLine(to: CGPoint(x: bubbleRect.minX + trianglePadding + triangleWidth / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: bubbleRect.minX + trianglePadding + triangleWidth, y: bubbleRect.minY))

        // top-right corner
        path.addLine(to: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.minY))
        path.addArc(
            center: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: -90),
            endAngle: Angle(degrees: 0),
            clockwise: false
        )

        // bottom-right corner
        path.addLine(to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY - cornerRadius))
        path.addArc(
            center: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 0),
            endAngle: Angle(degrees: 90),
            clockwise: false
        )

        // bottom-left corner
        path.addLine(to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.maxY))
        path.addArc(
            center: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 90),
            endAngle: Angle(degrees: 180),
            clockwise: false
        )

        // top-left corner
        path.addLine(to: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY + cornerRadius))
        path.addArc(
            center: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 180),
            endAngle: Angle(degrees: 270),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            // simulate AutomationStatusView position
            HStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 32)
                Spacer()
            }
            .padding(.horizontal, 16)

            // confirmation bubble - use the simplified preview
            HStack {
                AutomationConfirmationBubblePreview()
                    .padding(.leading, 16)
                Spacer()
            }

            Spacer()
        }
        .padding(.top, 60)
    }
}

/// Simplified bubble for preview
private struct AutomationConfirmationBubblePreview: View {
    private let bubbleColor = Color(white: 0.15).opacity(0.4)
    private let accentColor = Color(red: 0.0, green: 0.8, blue: 0.6)
    private let cornerRadius: CGFloat = 12
    private let triangleWidth: CGFloat = 12
    private let triangleHeight: CGFloat = 6
    private let trianglePadding: CGFloat = 16

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String.automationConfirmPendingTitle.localized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Text("人像优化")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Button(action: {}) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }

                Button(action: {}) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 26, height: 26)
                        .background(accentColor)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .padding(.top, triangleHeight)
        .background {
            BubbleShape(
                cornerRadius: cornerRadius,
                triangleWidth: triangleWidth,
                triangleHeight: triangleHeight,
                trianglePadding: trianglePadding
            )
            .fill(bubbleColor)
            .overlay {
                BubbleShape(
                    cornerRadius: cornerRadius,
                    triangleWidth: triangleWidth,
                    triangleHeight: triangleHeight,
                    trianglePadding: trianglePadding
                )
                .fill(.ultraThinMaterial)
            }
            .overlay {
                BubbleShape(
                    cornerRadius: cornerRadius,
                    triangleWidth: triangleWidth,
                    triangleHeight: triangleHeight,
                    trianglePadding: trianglePadding
                )
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            }
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}
