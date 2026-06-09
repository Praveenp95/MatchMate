//
//  MatchCardView.swift
//  MatchMate
//
//  Created by Praveen P on 09/06/26.
//

import SwiftUI

struct MatchCardView: View {

    let profile:   UserProfile
    let onAccept:  () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            profileImage
            cardBody
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Profile image band

    private var profileImage: some View {
        ZStack(alignment: .bottom) {
            CachedAsyncImage(urlString: profile.imageURL)
                .frame(height: 220)
                .clipped()

            LinearGradient(
                colors: [.clear, Color.white.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .frame(height: 220)
        .clipped()
    }

    // MARK: - Card body (name + info + action)

    private var cardBody: some View {
        VStack(spacing: 10) {
            // Name
            Text(profile.name)
                .font(.title2.bold())
                .foregroundColor(.matchTeal)
                .multilineTextAlignment(.center)

            // Details
            VStack(spacing: 4) {
                Label(profile.address.city, systemImage: "mappin.circle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Label(profile.company.name, systemImage: "briefcase")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label(profile.email, systemImage: "envelope")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Divider().padding(.vertical, 4)
            actionArea
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: - Action area (buttons or status banner)

    @ViewBuilder
    private var actionArea: some View {
        switch profile.matchStatus {
        case .none:
            HStack(spacing: 44) {
                actionButton(
                    icon: "xmark",
                    color: .matchTeal,
                    action: onDecline
                )
                actionButton(
                    icon: "checkmark",
                    color: .matchTeal,
                    action: onAccept
                )
            }

        case .accepted:
            statusBanner(text: "Member Accepted ✓", color: .matchTeal)

        case .declined:
            statusBanner(text: "Member Declined ✗", color: Color(red: 0.55, green: 0.55, blue: 0.60))
        }
    }

    // MARK: - Sub-components

    private func actionButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(color, lineWidth: 2.5)
                    .frame(width: 58, height: 58)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(color)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func statusBanner(text: String, color: Color) -> some View {
        Text(text)
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MatchCardView(
            profile: UserProfile(
                id: 1, name: "Leanne Graham",
                email: "leanne@example.com",
                phone: "+1 234 567 890",
                website: "example.com",
                city: "Gwenborough",
                companyName: "Romaguera-Crona",
                matchStatus: .none
            ),
            onAccept:  {},
            onDecline: {}
        )
        MatchCardView(
            profile: UserProfile(
                id: 2, name: "Ervin Howell",
                email: "ervin@example.com",
                phone: "+1 987 654 321",
                website: "example.com",
                city: "Wisokyburgh",
                companyName: "Deckow-Crist",
                matchStatus: .accepted
            ),
            onAccept:  {},
            onDecline: {}
        )
        MatchCardView(
            profile: UserProfile(
                id: 3, name: "Clementine Bauch",
                email: "clementine@example.com",
                phone: "+1 555 555 555",
                website: "example.com",
                city: "McKenziehaven",
                companyName: "Romaguera-Jacobson",
                matchStatus: .declined
            ),
            onAccept:  {},
            onDecline: {}
        )
    }
    .background(Color(UIColor.systemGroupedBackground))
}
