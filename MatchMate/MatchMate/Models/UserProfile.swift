//
//  UserProfile.swift
//  MatchMate
//
//  Created by Praveen P on 09/06/26.
//

import Foundation

// MARK: - Supporting API models

struct UserAddress: Codable, Sendable {
    let city: String
}

struct UserCompany: Codable, Sendable {
    let name: String
}

// MARK: - Main model

struct UserProfile: Identifiable, Sendable {
    let id: Int
    let name: String
    let email: String
    let phone: String
    let website: String
    let address: UserAddress
    let company: UserCompany
    var matchStatus: MatchStatus

    var imageURL: String {
        "https://i.pravatar.cc/300?img=\(id)"
    }
}

// MARK: - Decodable (API → Model; matchStatus not in JSON, defaults to .none)

extension UserProfile: Decodable {
    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, website, address, company
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self,         forKey: .id)
        name = try c.decode(String.self,      forKey: .name)
        email = try c.decode(String.self,      forKey: .email)
        phone = try c.decode(String.self,      forKey: .phone)
        website = try c.decode(String.self,      forKey: .website)
        address = try c.decode(UserAddress.self, forKey: .address)
        company = try c.decode(UserCompany.self, forKey: .company)
        matchStatus = .none
    }
}

// MARK: - Convenience init for SQLite reconstruction

extension UserProfile {
    init(id: Int, name: String, email: String, phone: String, website: String, city: String, companyName: String, matchStatus: MatchStatus) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.website = website
        self.address = UserAddress(city: city)
        self.company = UserCompany(name: companyName)
        self.matchStatus = matchStatus
    }
}
