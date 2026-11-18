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
    @Environment(\.hubMotion) private var motion
    @State private var address = ""
    @Environment(\.faceDensity) private var density
    @State private var stage = Stage.cover

    var body: some View {
        let library = environment.recipes
        Group {
            switch library.state {
            case .empty:
                entry(error: nil)
            case .failed(let error):
                entry(error: error)
            case .loading:
                waiting("Reading the recipe", identifier: "recipes.loading")
            case .preparing:
                waiting("Getting this recipe ready", identifier: "recipes.preparing")
            case .loaded(let recipe):
                // The tidied recipe takes the place of the page's own with a slow cross-fade.
                Group {
                    switch stage {
                    case .cover: cover(recipe)
                    case .ingredients: ingredients(recipe)
                    case .cooking: cooking(recipe)
                    }
                }
                .id(recipe.isTidied)
                .transition(.opacity)
            }
        }
        .animation(motion.gentle, value: library.isShowingTidied)
        .task(id: navigator.pendingRecipeURL) {
            if let url = navigator.takePendingRecipeURL() {
                stage = .cover
                await library.load(url: url)
            }
        }
    }

    private func waiting(_ text: LocalizedStringKey, identifier: String) -> some View {
        AppScreen(title: "Recipes", onClose: { environment.recipes.close() }) {
            VStack(spacing: metrics.pt(3)) {
                ProgressView()
                    .controlSize(.extraLarge)
                    .tint(.white)
                Text(text)
                    .font(.system(size: metrics.text(3.6), weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
        }
    }

    /// Says the recipe was rewritten on the device, and switches to the page's own words and
    /// back. Small and quiet: it is information, not a feature.
    @ViewBuilder
    private var tidiedNote: some View {
        let library = environment.recipes
        if library.canSwitchToOriginal {
            let tidied = library.isShowingTidied
            HStack(spacing: metrics.token(8)) {
                Label(tidied ? "Tidied on this iPad" : "Original from the page", systemImage: tidied ? "sparkles" : "doc.plaintext")
                    .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle), weight: .medium))
                    .foregroundStyle(Color.hubSecondaryText)
                    .accessibilityIdentifier("recipes.tidiedNote")
                Button {
                    library.setShowsOriginal(tidied)
                } label: {
                    Text(tidied ? "Show Original" : "Show Tidied")
                        .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, metrics.token(12))
                        .frame(minHeight: max(metrics.token(DesignTokens.minimumTouch), HubMetrics.minimumTouchSide))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .hubGlass(in: Capsule(), interactive: true)
                .accessibilityIdentifier("recipes.toggleOriginal")
            }
            .lineLimit(1)
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
                        environment.recipes.goToStep(0)
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
                .frame(width: metrics.width, height: metrics.height)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
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
                tidiedNote
                GlassCapsuleButton(title: "Start Cooking", symbol: "frying.pan.fill") {
                    environment.recipes.goToStep(0)
                    stage = .cooking
                }
            }
            .padding(metrics.pt(5))
        }
    }

    // MARK: Cooking

    /// One step at a time, for messy hands: a large badge with the step number, the step's
    /// short title, the instruction in large type with its amounts picked out, the ingredients
    /// the step uses, and the running timer floating in the corner. Across the room only the
    /// badge, the title, and a larger instruction show; the chips come in on approach and the
    /// buttons within reach.
    private func cooking(_ recipe: Recipe) -> some View {
        let library = environment.recipes
        let steps = recipe.steps
        let index = min(max(library.stepIndex, 0), steps.count - 1)
        let step = steps[index]
        let section = recipe.sections.first { $0.steps.contains(step) }?.name
        let badge = max(metrics.token(64), HubMetrics.minimumTouchSide)
        let textSize = metrics.textToken(density.showsLabels ? 24 : 32)
        return ZStack {
            Color.black
            VStack(alignment: .leading, spacing: metrics.token(14)) {
                HStack(spacing: metrics.token(14)) {
                    GlassCircleButton(symbol: "xmark", label: "Stop Cooking", identifier: "recipes.stopCooking") { stage = .cover }
                        .opacity(density.showsControls ? 1 : 0)
                        .allowsHitTesting(density.showsControls)
                    Text(verbatim: "\(index + 1)")
                        .font(.system(size: badge * 0.54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(white: 0.08))
                        .contentTransition(.numericText())
                        .frame(width: badge, height: badge)
                        .background(Circle().fill(Color(RainbowTint.orange)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Step \(index + 1) of \(steps.count)")
                            .font(.system(size: metrics.textToken(DesignTokens.tileTitle), weight: .bold))
                            .foregroundStyle(Color(RainbowTint.orange))
                        Text(section ?? recipe.name)
                            .font(.system(size: metrics.textToken(DesignTokens.tileSubtitle)))
                            .foregroundStyle(Color.hubSecondaryText)
                            .opacity(density.showsLabels ? 1 : 0)
                    }
                    .lineLimit(1)
                    .accessibilityIdentifier("recipes.stepBadge")
                    Spacer()
                    timerPill
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: metrics.token(12)) {
                        if let title = step.title {
                            Text(title)
                                .font(.system(size: textSize * 1.25, weight: .bold))
                                .foregroundStyle(.white)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("recipes.stepTitle")
                        }
                        Text(highlighted(step.text, size: textSize))
                            .font(.system(size: textSize, weight: .medium))
                            .foregroundStyle(.white)
                            .lineSpacing(textSize * 0.22)
                        if !step.ingredients.isEmpty, density.showsLabels {
                            ingredientChips(step.ingredients)
                                .padding(.top, metrics.token(6))
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .id(index)
                .transition(.opacity)
                if density.showsControls {
                    tidiedNote
                    HStack(spacing: metrics.pt(2.4)) {
                        GlassCircleButton(symbol: "chevron.left", label: "Previous Step", size: 11.5, identifier: "recipes.previous") { library.goToStep(index - 1) }
                            .disabled(index == 0)
                            .opacity(index == 0 ? 0.4 : 1)
                        if let duration = step.timer {
                            GlassCapsuleButton(title: "Start \(DurationText.countdown(duration)) Timer", symbol: "timer", tint: Color(RainbowTint.orange).opacity(0.4)) {
                                environment.timers.add(name: recipe.name, duration: duration)
                            }
                        } else {
                            Spacer()
                        }
                        GlassCircleButton(symbol: "chevron.right", label: "Next Step", size: 11.5, identifier: "recipes.next") { library.goToStep(index + 1) }
                            .disabled(index == steps.count - 1)
                            .opacity(index == steps.count - 1 ? 0.4 : 1)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, metrics.token(28))
            .padding(.top, max(metrics.token(24), metrics.topObstruction))
            .padding(.bottom, metrics.bottomBar + metrics.token(12))
            .animation(motion.snappy, value: index)
            .animation(motion.gentle, value: density)
        }
    }

    /// The ingredients one step uses, as glass chips that wrap, with the amounts picked out.
    private func ingredientChips(_ lines: [String]) -> some View {
        let size = metrics.textToken(DesignTokens.tileTitle)
        return GlassEffectContainer(spacing: metrics.token(8)) {
            ChipFlow(spacing: metrics.token(8)) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(highlighted(line, size: size))
                        .font(.system(size: size, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.horizontal, metrics.token(14))
                        .padding(.vertical, metrics.token(9))
                        .hubGlass(in: RoundedRectangle(cornerRadius: metrics.token(18), style: .continuous))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ingredients for this step")
        .accessibilityIdentifier("recipes.stepIngredients")
    }

    /// The step's text with its amounts in the accent color.
    private func highlighted(_ text: String, size: CGFloat) -> AttributedString {
        var result = AttributedString(text)
        for range in RecipeQuantities.ranges(in: text) {
            guard let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].foregroundColor = Color(RainbowTint.orange)
            result[lower..<upper].font = .system(size: size, weight: .bold)
        }
        return result
    }

    /// The first running timer, in the corner where a glance from the stove finds it.
    private var timerPill: some View {
        TimelineView(.periodic(from: .startOfCurrentSecond, by: 1)) { _ in
            if let entry = environment.timers.strip.entries.first {
                HStack(spacing: metrics.token(8)) {
                    Image(systemName: "timer")
                        .foregroundStyle(Color(RainbowTint.orange))
                    Text(entry.countdown)
                        .monospacedDigit()
                        .foregroundStyle(entry.isFinished ? Color(RainbowTint.red) : .white)
                        .contentTransition(.numericText(countsDown: true))
                }
                .font(.system(size: metrics.textToken(22), weight: .semibold))
                .padding(.horizontal, metrics.token(16))
                .frame(height: metrics.chromeHeight)
                .hubGlass(in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Timer")
                .accessibilityIdentifier("recipes.timerPill")
            }
        }
    }
}

/// Lays chips out in rows, starting a new row when the next chip does not fit.
private struct ChipFlow: Layout {
    let spacing: CGFloat

    private func rows(for subviews: Subviews, width: CGFloat) -> [(indices: [Int], height: CGFloat)] {
        var rows: [(indices: [Int], height: CGFloat)] = []
        var used: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            if let last = rows.indices.last, used + spacing + size.width <= width {
                rows[last].indices.append(index)
                rows[last].height = max(rows[last].height, size.height)
                used += spacing + size.width
            } else {
                rows.append(([index], size.height))
                used = size.width
            }
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(for: subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
}
