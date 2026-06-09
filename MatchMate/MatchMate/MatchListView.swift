//
//  MatchListView.swift
//  MatchMate
//
//  Created by Praveen P on 09/06/26.
//

import SwiftUI

struct MatchListView: View {

    @StateObject  private var viewModel = MatchListViewModel()
    @EnvironmentObject private var network: NetworkMonitor

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                mainContent
            }
            .navigationTitle("Profile Matches")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert("Connection Error", isPresented: $viewModel.showErrorAlert) {
            Button("Retry") { Task { await viewModel.fetchFromAPI() } }
            Button("Dismiss", role: .cancel) { viewModel.showErrorAlert = false }
        } message: {
            Text(viewModel.errorMessage ?? "Could not load profiles.")
        }
    }

    // MARK: - Main content switcher

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading && viewModel.profiles.isEmpty {
            loadingView
        } else if viewModel.profiles.isEmpty {
            emptyStateView
        } else {
            profileList
        }
    }

    // MARK: - Profile list

    private var profileList: some View {
        List {
            if !network.isConnected {
                offlineBanner
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ForEach(viewModel.profiles) { profile in
                MatchCardView(
                    profile: profile,
                    onAccept:  { viewModel.updateMatchStatus(userId: profile.id, status: .accepted) },
                    onDecline: { viewModel.updateMatchStatus(userId: profile.id, status: .declined) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                // Left swipe → Accept
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        withAnimation { viewModel.updateMatchStatus(userId: profile.id, status: .accepted) }
                    } label: {
                        Label("Accept", systemImage: "checkmark.circle.fill")
                    }
                    .tint(.matchTeal)
                }
                // Right swipe → Decline
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        withAnimation { viewModel.updateMatchStatus(userId: profile.id, status: .declined) }
                    } label: {
                        Label("Decline", systemImage: "xmark.circle.fill")
                    }
                    .tint(Color(red: 0.55, green: 0.55, blue: 0.60))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.fetchFromAPI() }
    }

    // MARK: - Sub-views

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("You're offline — showing cached data")
                .font(.footnote.weight(.medium))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.orange)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(.matchTeal)
            Text("Finding your matches…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: network.isConnected ? "person.2.slash" : "wifi.slash")
                .font(.system(size: 64))
                .foregroundColor(.matchTeal.opacity(0.6))

            Text(network.isConnected ? "No profiles found" : "You're offline")
                .font(.title3.bold())

            Text(network.isConnected
                 ? "Pull down to refresh"
                 : "Connect to the internet to load profiles")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if network.isConnected {
                Button {
                    Task { await viewModel.fetchFromAPI() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.matchTeal))
                }
            }
        }
    }
}

#Preview {
    MatchListView()
        .environmentObject(NetworkMonitor.shared)
}
