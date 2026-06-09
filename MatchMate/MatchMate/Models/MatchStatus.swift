//
//  MatchStatus.swift
//  MatchMate
//
//  Created by Praveen P on 09/06/26.
//

import Foundation

enum MatchStatus: Int, Codable, Sendable {
    case none     = 0
    case accepted = 1
    case declined = 2
}
