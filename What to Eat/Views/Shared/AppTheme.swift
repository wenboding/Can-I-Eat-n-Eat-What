import SwiftUI

enum MealCoachTheme {
    static let backgroundTop = Color(red: 0.95, green: 0.98, blue: 1.00)
    static let backgroundBottom = Color(red: 1.00, green: 0.95, blue: 0.88)

    static let navy = Color(red: 0.09, green: 0.27, blue: 0.59)
    static let teal = Color(red: 0.09, green: 0.61, blue: 0.56)
    static let coral = Color(red: 0.93, green: 0.46, blue: 0.29)
    static let amber = Color(red: 0.95, green: 0.68, blue: 0.22)
    static let ink = Color(red: 0.11, green: 0.14, blue: 0.20)
    static let secondaryInk = Color(red: 0.11, green: 0.14, blue: 0.20)

    static let listRowBackground = Color.white.opacity(0.78)
}

struct MealCoachBackground: View {
    var body: some View {
        LinearGradient(
            colors: [MealCoachTheme.backgroundTop, MealCoachTheme.backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(MealCoachTheme.teal.opacity(0.20))
                .frame(width: 220, height: 220)
                .offset(x: -70, y: -50)
                .blur(radius: 20)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(MealCoachTheme.coral.opacity(0.20))
                .frame(width: 280, height: 280)
                .offset(x: 80, y: 70)
                .blur(radius: 30)
        }
        .ignoresSafeArea()
    }
}

struct MealCoachCardModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .foregroundStyle(MealCoachTheme.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.84))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(tint.opacity(0.12))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.7), lineWidth: 1)
                    }
            )
            .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
    }
}

extension View {
    func mealCoachCard(tint: Color) -> some View {
        modifier(MealCoachCardModifier(tint: tint))
    }
}

struct MealCoachPrimaryButtonStyle: ButtonStyle {
    let startColor: Color
    let endColor: Color
    let foregroundColor: Color

    init(
        startColor: Color = MealCoachTheme.navy,
        endColor: Color = MealCoachTheme.coral,
        foregroundColor: Color = MealCoachTheme.ink
    ) {
        self.startColor = startColor
        self.endColor = endColor
        self.foregroundColor = foregroundColor
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .foregroundStyle(foregroundColor)
            .background(
                LinearGradient(
                    colors: [startColor, endColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(configuration.isPressed ? 0.82 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.06 : 0.14), radius: 8, x: 0, y: 4)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct MealCoachSecondaryButtonStyle: ButtonStyle {
    let tint: Color

    init(tint: Color = MealCoachTheme.navy) {
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .foregroundStyle(MealCoachTheme.ink)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.60 : 0.78))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
