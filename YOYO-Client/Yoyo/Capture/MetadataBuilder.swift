import AVFoundation
import Foundation
import UIKit

/// data
final class MetadataBuilder {
    static let shared = MetadataBuilder(orientationManager: .shared)

    private weak var orientationManager: OrientationManager?

    private init(
        orientationManager: OrientationManager?
    ) {
        self.orientationManager = orientationManager
    }

    /// data
    func buildBaseMetadata() -> [String: Any] {
        var metadata: [String: Any] = [
            "deviceModel": UIDevice.current.model,
            "systemVersion": UIDevice.current.systemVersion,
            "timestamp": Date().timeIntervalSince1970,
        ]

        // adddeviceorientation
        if let orientation = orientationManager?.currentDeviceOrientation {
            metadata["deviceOrientation"] = orientation.rawValue
        }

        // addfilter
        let filter = FilterManager.shared.selectedFilter
        metadata["filterName"] = filter.name

        return metadata
    }

    /// photodata
    func buildPhotoMetadata(originalMetadata: [String: Any]? = nil) -> [String: Any] {
        var metadata = buildBaseMetadata()

        // andoriginaldata
        if let originalMetadata {
            metadata.merge(originalMetadata) { _, new in new }
        }

        return metadata
    }

    /// Live Photodata
    func buildLivePhotoMetadata(uniqueID: Int, originalMetadata: [String: Any]? = nil) -> [String: Any] {
        var metadata = buildBaseMetadata()
        metadata["uniqueID"] = uniqueID

        // andoriginaldata
        if let originalMetadata {
            metadata.merge(originalMetadata) { _, new in new }
        }

        return metadata
    }

    /// videodata
    func buildVideoMetadata(camera: AVCaptureDevice?) -> [String: Any] {
        var metadata = buildBaseMetadata()

        if let camera {
            // add TIFF
            var tiffDict: [String: Any] = [:]
            tiffDict["Make"] = "Apple"
            let deviceSpec = CameraSpecs.getCurrentDeviceSpec()
            tiffDict["Model"] = deviceSpec.deviceName
            metadata["{TIFF}"] = tiffDict

            // add Exif
            var exifDict: [String: Any] = [:]

            // aperture
            exifDict["FNumber"] = camera.lensAperture

            // shutter speed
            let exposureTime = CMTimeGetSeconds(camera.exposureDuration)
            exifDict["ExposureTime"] = exposureTime

            // ISO
            exifDict["ISOSpeedRatings"] = [Int(camera.iso)]

            // focal length
            let deviceManager = CameraDeviceManager.shared
            let focalLength = deviceManager.currentFocalLength
            exifDict["FocalLenIn35mmFilm"] = Int(focalLength)
            // originalfocal length
            exifDict["FocalLength"] = focalLength

            // exposure
            exifDict["ExposureBiasValue"] = Double(camera.exposureTargetBias)

            // Lens information
            exifDict["LensModel"] = "\(deviceSpec.deviceName) \(camera.position == .front ? "front" : "back") camera"

            // white balance
            exifDict["WhiteBalance"] = camera.whiteBalanceMode == .locked ? 1 : 0

            // flash (videomodeuse Torch)
            exifDict["Flash"] = camera.torchMode == .on ? 1 : 0

            // Color space
            if #available(iOS 10.0, *) {
                if camera.activeColorSpace == .P3_D65 {
                    exifDict["ColorSpace"] = 65535 // Map to Display P3 (Uncalibrated)
                } else {
                    exifDict["ColorSpace"] = 1 // Map to sRGB / Rec. 709
                }
            } else {
                exifDict["ColorSpace"] = 1
            }

            metadata["{Exif}"] = exifDict
        }

        return metadata
    }

    /// AVAssetWriter usedata
    func buildAVMetadataItems(camera: AVCaptureDevice?) -> [AVMetadataItem] {
        var items: [AVMutableMetadataItem] = []
        let deviceSpec = CameraSpecs.getCurrentDeviceSpec()

        // 1. Make ()
        let makeItem = AVMutableMetadataItem()
        makeItem.keySpace = .common
        makeItem.key = AVMetadataKey.commonKeyMake.rawValue as any NSCopying & NSObjectProtocol
        makeItem.value = "Apple" as any NSCopying & NSObjectProtocol
        items.append(makeItem)

        // 2. Model ()
        let modelItem = AVMutableMetadataItem()
        modelItem.keySpace = .common
        modelItem.key = AVMetadataKey.commonKeyModel.rawValue as any NSCopying & NSObjectProtocol
        modelItem.value = deviceSpec.deviceName as any NSCopying & NSObjectProtocol
        items.append(modelItem)

        // 3. Software ()
        let softwareItem = AVMutableMetadataItem()
        softwareItem.keySpace = .common
        softwareItem.key = AVMetadataKey.commonKeySoftware.rawValue as any NSCopying & NSObjectProtocol
        softwareItem.value = "\(String.brandName.localized) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")" as any NSCopying & NSObjectProtocol
        items.append(softwareItem)

        // 4. Creation Date (create)
        let creationDateItem = AVMutableMetadataItem()
        creationDateItem.keySpace = .common
        creationDateItem.key = AVMetadataKey.commonKeyCreationDate.rawValue as any NSCopying & NSObjectProtocol
        // ISO 8601 format
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        creationDateItem.value = formatter.string(from: Date()) as any NSCopying & NSObjectProtocol
        items.append(creationDateItem)

        // 5. iOS 26 QuickTime camera-metrics metadata removed:
        //    those AVMetadataKey members require the iOS 26 SDK and are
        //    unavailable when building with Xcode 16 (iOS 18.2 SDK).
        //    Video EXIF-equivalent info is still covered by buildVideoMetadata().

        return items
    }
}
