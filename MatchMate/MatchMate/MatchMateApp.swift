//
//  MatchMateApp.swift
//  MatchMate
//
//  Created by Praveen P on 09/06/26.
//

import SwiftUI

@main
struct MatchMateApp: App {

    @StateObject private var networkMonitor = NetworkMonitor.shared

    var body: some Scene {
        WindowGroup {
            MatchListView()
                .environmentObject(networkMonitor)
        }
    }
}
