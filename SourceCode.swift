import SwiftUI
import UIKit

// MARK: - FLOATING TAB BAR

struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack(spacing: 4) {
            FloatingTabItem(
                icon: "hammer.fill",
                title: "Compiler",
                isSelected: selectedTab == 0
            ) {
                triggerHaptic()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    selectedTab = 0
                }
            }
            
            FloatingTabItem(
                icon: "brain.head.profile",
                title: "AI Assistant",
                isSelected: selectedTab == 1
            ) {
                triggerHaptic()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    selectedTab = 1
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 20, y: -10)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
    }
    
    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred()
    }
}

// MARK: - FLOATING TAB ITEM

struct FloatingTabItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                
                if isSelected {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundColor(isSelected ? .white : .gray)
            .padding(.horizontal, isSelected ? 20 : 16)
            .padding(.vertical, 12)
            .background(
                Group {
                    if isSelected {
                        // Glassmorphic selection style
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    }
                }
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}