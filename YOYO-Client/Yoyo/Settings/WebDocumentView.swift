import SwiftUI

struct WebDocumentView: View {
    let path: String
    let title: String

    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var isLoading = true

    var body: some View {
        let urlString = ServiceEndpoints.shared.staticURLString(
            path,
            query: ["lang": languageManager.currentLanguage.webLanguageCode]
        )

        ZStack {
            WebView(urlString: urlString, isLoading: $isLoading)
                .background(Color(white: 0.04).ignoresSafeArea())

            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen(name: title)
    }
}
