import Foundation
import Testing
@testable import Yoyo

/// A-11: file names are the one thing every captured photo carries forever, and
/// the user chose the format in settings. A regression here is invisible in the
/// app and permanent in the photo library, which is exactly why it deserves
/// tests rather than a manual look.
///
/// `generateFullFileName` takes the date as a parameter, so these run
/// deterministically — no reliance on "now".
struct FileNameGeneratorTests {
    /// The generator is a singleton; its generation methods are pure given a
    /// date, so sharing it is fine and keeps the production wiring honest.
    private let generator = FileNameGenerator.shared

    /// 2024-10-29 14:30:22 in the *current* time zone.
    ///
    /// `FileNameGenerator` fills `{year}`…`{second}` from `Calendar.current`,
    /// so a date parsed in some other zone would render different digits and
    /// the assertions below would be testing the time zone instead of the
    /// template.
    private func fixedDate() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = 2024
        components.month = 10
        components.day = 29
        components.hour = 14
        components.minute = 30
        components.second = 22
        // swiftlint:disable:next force_unwrapping
        return calendar.date(from: components)!
    }

    // MARK: - Template variables

    @Test func timestampTemplateRendersExactDigits() {
        let name = generator.generateFileName(
            template: "{year}{month}{day}_{hour}{minute}{second}",
            prefix: "P",
            fileType: .photo,
            fileFormat: .jpg,
            date: fixedDate()
        )
        #expect(name == "20241029_143022")
    }

    @Test func classicTemplateCombinesTypeAndIndex() {
        let name = generator.generateFileName(
            template: "{type}_{index}",
            prefix: "Snapout",
            fileType: .photo,
            fileFormat: .jpg,
            date: fixedDate()
        )
        #expect(name.hasPrefix("Photo_"))
        #expect(name.contains("_"))
    }

    @Test func fullFileNameAppendsTheFormatExtension() {
        let name = generator.generateFullFileName(
            template: "{year}{month}{day}_{hour}{minute}{second}",
            prefix: "Snapout",
            fileType: .photo,
            fileFormat: .jpg,
            date: fixedDate()
        )
        #expect(name == "20241029_143022.jpg")
    }

    @Test func heicFormatProducesHeicFile() {
        let name = generator.generateFullFileName(
            template: "{year}{month}{day}",
            prefix: "P",
            fileType: .photo,
            fileFormat: .heic,
            date: fixedDate()
        )
        #expect(name == "20241029.heic")
    }

    @Test func originalSuffixIsAddedOnlyWhenRequested() {
        let base = generator.generateFullFileName(
            template: "{year}{month}{day}",
            prefix: "P",
            fileType: .photo,
            fileFormat: .jpg,
            date: fixedDate()
        )
        let original = generator.generateFullFileName(
            template: "{year}{month}{day}",
            prefix: "P",
            fileType: .photo,
            fileFormat: .jpg,
            date: fixedDate(),
            isOriginal: true
        )
        #expect(base == "20241029.jpg")
        #expect(original == "20241029_original.jpg")
    }

    @Test func livePhotoPairSharesTheTimestamp() {
        // If the two halves drift apart, Photos cannot pair them and the user
        // gets a broken Live Photo.
        let names = generator.generateLivePhotoFileNames(
            template: "{year}{month}{day}_{hour}{minute}{second}",
            prefix: "Snapout",
            fileFormat: .jpg,
            date: fixedDate()
        )
        #expect(names.imageFileName.hasPrefix("20241029_143022"))
        #expect(names.videoFileName.hasPrefix("20241029_143022"))
        #expect(names.imageFileName != names.videoFileName)
    }

    @Test func unknownPlaceholdersAreNotSilentlyDropped() {
        // Better to show a literal {foo} the user can see and fix than to
        // produce a name that is missing information.
        let name = generator.generateFileName(
            template: "{prefix}-{notARealVariable}",
            prefix: "Snapout",
            fileType: .photo,
            fileFormat: .jpg,
            date: fixedDate()
        )
        #expect(name == "Snapout-{notARealVariable}")
    }

    @Test func everyBuiltinTemplateRendersWithoutLeftoverPlaceholders() {
        // Renders each shipped template and checks that no known placeholder
        // survives into the file name.
        let placeholders = ["{prefix}", "{index}", "{year}", "{month}", "{day}", "{hour}", "{minute}", "{second}", "{type}"]
        for format in CameraDomainTypes.FileNamingFormat.allCases where !format.template.isEmpty {
            let name = generator.generateFileName(
                template: format.template,
                prefix: "Snapout",
                fileType: .photo,
                fileFormat: .jpg,
                date: fixedDate()
            )
            for placeholder in placeholders {
                #expect(!name.contains(placeholder), "\(format) left \(placeholder) unresolved → \(name)")
            }
        }
    }

    @Test func fileFormatExtensionsMatchTheirCases() {
        // The extension is what the OS and Photos use to open the file.
        #expect(FileFormat.jpg.fileExtension == "jpg")
        #expect(FileFormat.heic.fileExtension == "heic")
        #expect(FileFormat.dng.fileExtension == "dng")
        #expect(FileFormat.mov.fileExtension == "mov")
        #expect(FileFormat.mp4.fileExtension == "mp4")
    }
}