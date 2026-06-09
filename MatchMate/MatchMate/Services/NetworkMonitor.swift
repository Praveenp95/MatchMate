//
//  NetworkMonitor.swift
//  MatchMate
//
//  Created by Praveen P on 09/06/26.
//

import Foundation
import Network
import Combine

@MainActor
final class NetworkMonitor: ObservableObject {

    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var connectionType: ConnectionType = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.matchmate.networkmonitor", qos: .background)

    enum ConnectionType: String {
        case wifi     = "Wi-Fi"
        case cellular = "Cellular"
        case ethernet = "Ethernet"
        case unknown  = "Unknown"
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let type: ConnectionType
            if path.usesInterfaceType(.wifi) {
                type = .wifi
            } else if path.usesInterfaceType(.cellular) {
                type = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                type = .ethernet
            } else {
                type = .unknown
            }

            Task { @MainActor [weak self] in
                self?.isConnected   = connected
                self?.connectionType = type
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
