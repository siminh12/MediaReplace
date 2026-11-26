// MediaReplaceApp.swift
// MediaReplace — clean-room rewrite. App entry point.

import SwiftUI

@main
struct MediaReplaceApp: App {
    @StateObject private var viewModel = MediaReplaceViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}
