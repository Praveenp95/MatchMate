//
//  DatabaseService.swift
//  MatchMate
//
//  Created by Praveen P on 09/06/26.
//

import Foundation
import SQLite3

// MARK: - Database Errors

enum DatabaseError: LocalizedError {
    case openFailed
    case prepareFailed(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .openFailed:               return "Failed to open SQLite database."
        case .prepareFailed(let msg):   return "SQL error: \(msg)"
        case .unknown:                  return "Unknown database error."
        }
    }
}

// MARK: - DatabaseService (actor for thread-safe, off-main-thread SQLite access)

actor DatabaseService {

    static let shared = DatabaseService()
    private var db: OpaquePointer?

    /// init is intentionally empty.
    /// Opening the DB here would run on the CALLER'S thread (not the actor's
    /// executor), which causes SQLITE_BUSY on every subsequent write.
    /// openIfNeeded() is called at the top of every public method instead,
    /// guaranteeing the handle is created on the actor's serial executor.
    private init() { }

    // MARK: - Lazy setup (always runs on the actor's executor)

    private func openIfNeeded() {
        guard db == nil else { return }

        guard let url = try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("MatchMate.sqlite") else {
            print("[DB] Could not resolve documents directory")
            return
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            print("[DB] sqlite3_open_v2 failed")
            return
        }
        db = handle

        // WAL mode: readers never block writers and vice-versa.
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)

        let ddl = """
            CREATE TABLE IF NOT EXISTS user_profiles (
                id           INTEGER PRIMARY KEY,
                name         TEXT    NOT NULL DEFAULT '',
                email        TEXT             DEFAULT '',
                phone        TEXT             DEFAULT '',
                website      TEXT             DEFAULT '',
                city         TEXT             DEFAULT '',
                company      TEXT             DEFAULT '',
                match_status INTEGER NOT NULL DEFAULT 0
            );
            """
        if sqlite3_exec(db, ddl, nil, nil, nil) != SQLITE_OK {
            print("[DB] createTable failed: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    // MARK: - CRUD

    /// Upserts profile rows – updates all data columns on conflict but never
    /// touches match_status for existing rows.
    func saveUsers(_ users: [UserProfile]) {
        openIfNeeded()
        guard db != nil else { return }

        let sql = """
            INSERT INTO user_profiles
                (id, name, email, phone, website, city, company, match_status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name    = excluded.name,
                email   = excluded.email,
                phone   = excluded.phone,
                website = excluded.website,
                city    = excluded.city,
                company = excluded.company;
            """

        // Wrap all inserts in a single transaction to avoid per-row lock cycling.
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        defer { sqlite3_exec(db, "COMMIT;", nil, nil, nil) }

        for user in users {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("[DB] saveUsers prepare failed: \(String(cString: sqlite3_errmsg(db)))")
                continue
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(user.id))
            bind(text: user.name,          to: stmt, at: 2)
            bind(text: user.email,         to: stmt, at: 3)
            bind(text: user.phone,         to: stmt, at: 4)
            bind(text: user.website,       to: stmt, at: 5)
            bind(text: user.address.city,  to: stmt, at: 6)
            bind(text: user.company.name,  to: stmt, at: 7)
            sqlite3_bind_int(stmt, 8, Int32(user.matchStatus.rawValue))

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[DB] saveUsers step failed: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    /// Loads all stored profiles.
    func loadUsers() -> [UserProfile] {
        openIfNeeded()
        guard db != nil else { return [] }

        let sql = """
            SELECT id, name, email, phone, website, city, company, match_status
            FROM user_profiles ORDER BY id ASC;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [UserProfile] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id       = Int(sqlite3_column_int(stmt, 0))
            let name     = string(from: stmt, column: 1)
            let email    = string(from: stmt, column: 2)
            let phone    = string(from: stmt, column: 3)
            let website  = string(from: stmt, column: 4)
            let city     = string(from: stmt, column: 5)
            let company  = string(from: stmt, column: 6)
            let status   = MatchStatus(rawValue: Int(sqlite3_column_int(stmt, 7))) ?? .none

            results.append(UserProfile(
                id: id, name: name, email: email,
                phone: phone, website: website,
                city: city, companyName: company,
                matchStatus: status
            ))
        }
        return results
    }

    /// Updates only the match_status for a given user ID.
    /// Falls back to inserting a placeholder row if the user is not yet saved.
    func updateMatchStatus(userId: Int, status: MatchStatus) {
        openIfNeeded()
        guard db != nil else { return }

        let sql = "UPDATE user_profiles SET match_status = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[DB] updateMatchStatus prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(status.rawValue))
        sqlite3_bind_int(stmt, 2, Int32(userId))

        if sqlite3_step(stmt) != SQLITE_DONE {
            print("[DB] updateMatchStatus step failed: \(String(cString: sqlite3_errmsg(db)))")
        } else if sqlite3_changes(db) == 0 {
            insertStatusOnly(userId: userId, status: status)
        }
    }

    // MARK: - Private helpers

    /// Inserts a minimal row when the profile row doesn't exist yet.
    private func insertStatusOnly(userId: Int, status: MatchStatus) {
        let sql = """
            INSERT OR IGNORE INTO user_profiles
                (id, name, email, phone, website, city, company, match_status)
            VALUES (?, '', '', '', '', '', '', ?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(userId))
        sqlite3_bind_int(stmt, 2, Int32(status.rawValue))
        sqlite3_step(stmt)
    }

    private func bind(text: String, to stmt: OpaquePointer?, at index: Int32) {
        sqlite3_bind_text(stmt, index, (text as NSString).utf8String, -1, nil)
    }

    private func string(from stmt: OpaquePointer?, column: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, column) else { return "" }
        return String(cString: cStr)
    }
}
