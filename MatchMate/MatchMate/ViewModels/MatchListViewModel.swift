//
//  MatchListViewModel.swift
//  MatchMate
//
//  Created by Praveen P on 09/06/26.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class MatchListViewModel: ObservableObject {
    
    // MARK: - Published state
    
    @Published var profiles: [UserProfile] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showErrorAlert: Bool = false
    
    // MARK: - Dependencies
    
    private let apiService = APIService.shared
    private let dbService = DatabaseService.shared
    let networkMonitor = NetworkMonitor.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var hasFetched = false
    
    // MARK: - Init
    
    init() {
        setupNetworkObserver()
        Task { await loadInitialData() }
    }
    
    // MARK: - Network observer
    
    private func setupNetworkObserver() {
        networkMonitor.$isConnected
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isConnected in
                guard let self, isConnected else { return }
                Task { await self.fetchFromAPI() }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data loading
    
    func loadInitialData() async {
        let cached = await dbService.loadUsers()
        if !cached.isEmpty {
            profiles = cached
        }
        if networkMonitor.isConnected {
            await fetchFromAPI()
        }
    }
    
    func fetchFromAPI() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            let apiUsers = try await apiService.fetchUsers()
            let stored   = await dbService.loadUsers()
            let statusMap = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.matchStatus) })
            
            let merged = apiUsers.map { user -> UserProfile in
                var u = user
                let liveStatus = profiles.first(where: { $0.id == user.id })?.matchStatus
                u.matchStatus = liveStatus ?? statusMap[user.id] ?? .none
                return u
            }
            
            profiles = merged
            hasFetched = true
            await dbService.saveUsers(merged)
            
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = profiles.isEmpty
        }
        
        isLoading = false
    }
    
    // MARK: - Accept / Decline
    
    func updateMatchStatus(userId: Int, status: MatchStatus) {
        if let idx = profiles.firstIndex(where: { $0.id == userId }) {
            profiles[idx].matchStatus = status
        }
        Task {
            await dbService.updateMatchStatus(userId: userId, status: status)
        }
    }
}
