import HomePadCore
import HomePadUICore
import SwiftUI

/// Turns a recipe web page into a cover, an ingredient checklist, and one step at a time with
/// timers. The page is read as data; nothing from it is run.
struct RecipesApp: View {
    private enum Stage {
        case cover, ingredients, cooking
    }

    let onClose: () -> Void
    @Environment(\.hubMetrics) private var metrics
    @Environment(\.hubUnits) private var units
    @Environment(\.calendar) private var calendar
    @Environment(HubEnvironment.self) private var environment
    @Environment(HubNavigator.self) private var navigator
    @State private var address = ""
    @State private var stage = Stage.cover
    @State private var stepIndex = 0

    var body: some View {
        let library = environment.recipes
        Group {
            switch library.state {
            case .empty:
                entry(error: nil)
            case .failed(let error):
                entry(error: error)
            case .loading:
                AppScreen(title: "Recipes", onClose: onClose) {
                    VStack(spacing: metrics.pt(3)) {
                        ProgressView()
                            .controlSize(.extraLarge)
                            .tint(.white)
                        Text("Reading the recipe")
                            .font(.system(size: metrics.text(3.6), weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            case .loaded(let recipe):
                switch stage {
                case .cover: cover(recipe)
                case .ingredients: ingredients(recipe)
                case .cooking: cooking(recipe)
                }
            }
        }
        .task(id: navigator.pendingRecipeURL) {
            if let url = navigator.takePendingRecipeURL() {
                stage = .cover
                stepIndex = 0
                await library.load(url: url)
            }
        }
    }

    // MARK: Entry

    /// With no recipe open, the screen is laid out like a recipe's cover: a full-bleed picture,
    /// a large title at the bottom, and the controls underneath.
    private func entry(error: RecipeLoadError?) -> some View {
        ZStack {
            LinearGradient(colors: [Color(RainbowTint.orange), Color(RainbowTint.red)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(.white.opacity(0.14))
                .frame(width: metrics.pt(62))
                .offset(x: metrics.pt(14), y: metrics.pt(-14))
            Circle()
                .stroke(.white.opacity(0.2), lineWidth: metrics.pt(1.2))
                .frame(width: metrics.pt(46))
                .offset(x: metrics.pt(14), y: metrics.pt(-14))
            Image(systemName: "fork.knife")
                .font(.system(size: metrics.pt(22), weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .offset(x: metrics.pt(14), y: metrics.pt(-14))
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: metrics.pt(1)) {
                GlassCircleButton(symbol: "xmark", label: "Close", identifier: "hub.close", action: onClose)
                Spacer()
                Text("Recipes")
                    .font(.system(size: metrics.text(6), weight: .bold))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text(error.map(message(for:)) ?? "Paste a link to a recipe, or beam one from your iPhone.")
                    .font(.system(size: metrics.text(3.4), weight: error == nil ? .regular : .semibold))
                    .foregroundStyle(.white.opacity(error == nil ? 0.8 : 1))
                    .lineLimit(2)
                HStack(spacing: metrics.pt(2.4)) {
                    TextField("Recipe link", text: $address, prompt: Text("Recipe link").foregroundStyle(.white.opacity(0.6)))
                        .font(.system(size: metrics.text(3.4), weight: .semibold))
                        .textFieldStyle(.plain)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .foregroundStyle(.white)
                        .padding(.horizontal, metrics.pt(4))
                        .frame(height: metrics.pt(11.5))
                        .hubGlass(in: Capsule())
                        .onSubmit(load)
                        .accessibilityIdentifier("recipes.link")
                    GlassCircleButton(symbol: "arrow.right", label: "Open Recipe", size: 11.5, identifier: "recipes.open", action: load)
                }
                .padding(.top, metrics.pt(3))
            }
            .padding(metrics.pt(5))
        }
        .accessibilityElement(children: .contain)
    }

    private func load() {
        let text = address
        stage = .cover
        stepIndex = 0
        Task { await environment.recipes.load(address: text) }
    }

    private func message(for error: RecipeLoadError) -> LocalizedStringKey {
        switch error {
        case .invalidAddress: "That does not look like a web address."
        case .network: "The page could not be loaded."
        case .parse(.pageTooLarge): "That page is too large to read."
        case .parse(.noStructuredData), .parse(.noRecipe): "No recipe was found on that page."
        case .parse(.incompleteRecipe): "The recipe on that page has no steps."
        }
    }

    // MARK: Cover

    private func subtitle(_ recipe: Recipe) -> String {
        var parts: [String] = []
        if let author = recipe.author { parts.append(author) }
        if let duration = recipe.displayDuration {
            let time = DurationText.compact(duration)
            parts.append(time.hours > 0 ? String(localized: "\(time.hours) hr \(time.minutes) min") : String(localized: "\(time.minutes) min."))
        }
        if let yield = recipe.yield { parts.append(yield) }
        return parts.joined(separator: " \u{2022} ")
    }

    private func cover(_ recipe: Recipe) -> some View {
        ZStack {
            photo(recipe)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: metrics.pt(1)) {
                HStack(alignment: .top) {
                    GlassCircleButton(symbol: "xmark", label: "Close Recipe", identifier: "recipes.closeRecipe") { environment.recipes.close() }
                    Spacer()
                    TimelineView(.periodic(from: .startOfCurrentSecond, by: 10)) { timeline in
                        Text(FaceText.clock(timeline.date, calendar: calendar, density: .glanceable, units: units).digits)
                            .font(.system(size: metrics.text(3.6), weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: metrics.pt(0.6))
                            .padding(.top, metrics.pt(2.4))
                    }
                }
                Spacer()
                Text(recipe.name)
                    .font(.system(size: metrics.text(6), weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle(recipe))
                    .font(.system(size: metrics.text(3.4)))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                HStack(spacing: metrics.pt(2.4)) {
                    GlassCapsuleButton(title: "Ingredients", symbol: "checklist", identifier: "recipes.ingredients") { stage = .ingredients }
                    GlassCapsuleButton(title: "Start Cooking", symbol: "frying.pan.fill", identifier: "recipes.cook") {
                        stepIndex = 0
                        stage = .cooking
                    }
                }
                .padding(.top, metrics.pt(3))
            }
            .padding(metrics.pt(5))
        }
    }

    private func photo(_ recipe: Recipe) -> some View {
        ZStack {
            LinearGradient(colors: [Color(RainbowTint.orange), Color(RainbowTint.red)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "fork.knife")
                .font(.system(size: metrics.pt(30)))
                .foregroundStyle(.white.opacity(0.25))
            if let url = recipe.imageURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .frame(width: metrics.side, height: metrics.side)
            }
        }
        .frame(width: metrics.side, height: metrics.side)
        .clipped()
        .accessibilityHidden(true)
    }

    // MARK: Ingredients

    private func ingredients(_ recipe: Recipe) -> some View {
        let library = environment.recipes
        return ZStack(alignment: .topLeading) {
            Color.black
            VStack(alignment: .leading, spacing: metrics.pt(2.5)) {
                HStack(spacing: metrics.pt(3)) {
                    GlassCircleButton(symbol: "chevron.left", label: "Back", identifier: "recipes.back") { stage = .cover }
                    Text("Ingredients")
                        .font(.system(size: metrics.text(4.6), weight: .bold))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: metrics.pt(1.4)) {
                        ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ingredient in
                            let checked = library.checkedIngredients.contains(index)
                            Button {
                                library.toggleIngredient(index)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: metrics.pt(2.4)) {
                                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(checked ? Color(RainbowTint.green) : Color.hubSecondaryText)
                                    Text(ingredient)
                                        .foregroundStyle(checked ? Color.hubSecondaryText : .white)
                                        .strikethrough(checked)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .font(.system(size: metrics.text(3.7), weight: .medium))
                                .padding(.vertical, metrics.pt(1.4))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(checked ? .isSelected : [])
                        }
                        if recipe.ingredients.isEmpty {
                            Text("This recipe does not list its ingredients.")
                                .font(.system(size: metrics.text(3.4)))
                                .foregroundStyle(Color.hubSecondaryText)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                GlassCapsuleButton(title: "Start Cooking", symbol: "frying.pan.fill") {
                    stepIndex = 0
                    stage = .cooking
                }
            }
            .padding(metrics.pt(5))
        }
    }

    // MARK: Cooking

    private func cooking(_ recipe: Recipe) -> some View {
        let steps = recipe.steps
        let index = min(max(stepIndex, 0), steps.count - 1)
        let step = steps[index]
        let section = recipe.sections.first { $0.steps.contains(step) }?.name
        return ZStack {
            Color.black
            VStack(alignment: .leading, spacing: metrics.pt(2.4)) {
                HStack(spacing: metrics.pt(3)) {
                    GlassCircleButton(symbol: "xmark", label: "Stop Cooking", identifier: "recipes.stopCooking") { stage = .cover }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Step \(index + 1) of \(steps.count)")
                            .font(.system(size: metrics.text(3.4), weight: .bold))
                            .foregroundStyle(Color(RainbowTint.orange))
                        Text(section ?? recipe.name)
                            .font(.system(size: metrics.text(3)))
                            .foregroundStyle(Color.hubSecondaryText)
                    }
                    .lineLimit(1)
                    Spacer()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: metrics.pt(2)) {
                        if let title = step.title {
                            Text(title)
                                .font(.system(size: metrics.text(4.4), weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text(step.text)
                            .font(.system(size: metrics.text(6.2), weight: .medium))
                            .foregroundStyle(.white)
                            .lineSpacing(metrics.pt(1))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                TimerStripView(strip: environment.timers.strip) {}
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                HStack(spacing: metrics.pt(2.4)) {
                    GlassCircleButton(symbol: "chevron.left", label: "Previous Step", size: 11.5) { stepIndex = max(0, index - 1) }
                        .disabled(index == 0)
                        .opacity(index == 0 ? 0.4 : 1)
                    if let duration = step.timer {
                        GlassCapsuleButton(title: "Start \(DurationText.countdown(duration)) Timer", symbol: "timer", tint: Color(RainbowTint.orange).opacity(0.4)) {
                            environment.timers.add(name: recipe.name, duration: duration)
                        }
                    } else {
                        Spacer()
                    }
                    GlassCircleButton(symbol: "chevron.right", label: "Next Step", size: 11.5, identifier: "recipes.next") { stepIndex = min(steps.count - 1, index + 1) }
                        .disabled(index == steps.count - 1)
                        .opacity(index == steps.count - 1 ? 0.4 : 1)
                }
            }
            .padding(metrics.pt(5))
        }
    }
}
