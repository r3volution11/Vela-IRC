// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaMedia
import VelaTheme

/// Per-site preview rules: a row per domain with an Everything / Text only /
/// Nothing picker and a remove button, then a row for adding a site.
///
/// It keeps no copy of the rules. It shows `rules` and sends every change
/// through `setRule`, so it can't drift from rules written elsewhere (the
/// blocked-preview chip, the link's site menu).
struct SiteRulesEditor: View {
    @Environment(\.theme) private var theme
    /// Normalized domain → access.
    let rules: [String: SiteAccess]
    var emptyMessage = "No site rules."
    /// Sets the rule for a domain, or removes it when given nil.
    let setRule: (SiteAccess?, String) -> Void

    @State private var newDomain = ""
    /// Most rules people add by hand are blocks, so the picker starts there.
    @State private var newAccess: SiteAccess = .block
    @State private var showsInvalidHint = false

    struct Rule: Hashable {
        let domain: String
        let access: SiteAccess
    }

    var body: some View {
        let sorted = Self.sorted(rules)
        let candidate = Self.ruleDomain(newDomain)
        VStack(alignment: .leading, spacing: 0) {
            if sorted.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(theme[ThemeKey.settingsSecondaryForeground])
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sorted, id: \.domain) { rule in
                        row(rule)
                    }
                }
                .padding(.vertical, 4)
            }
            SettingsHairline()
            addRow(candidate: candidate)
        }
    }

    // MARK: Rows

    private func row(_ rule: Rule) -> some View {
        HStack(spacing: 8) {
            Image(systemName: Self.symbol(for: rule.access))
                .font(.system(size: 12))
                .foregroundStyle(theme[Self.colorKey(for: rule.access)])
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(rule.domain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme[ThemeKey.settingsForeground])
                .lineLimit(1)
                .truncationMode(.middle)
                .help(rule.domain)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            accessPicker(
                "Previews from \(rule.domain)",
                selection: Binding(
                    get: { rule.access },
                    set: { access in setRule(access, rule.domain) }
                )
            )
            RemoveRuleButton(domain: rule.domain) {
                withAnimation(.snappy(duration: 0.2)) { setRule(nil, rule.domain) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rule.domain)
    }

    private func addRow(candidate: String?) -> some View {
        let isUpdate = candidate.map { rules[$0] != nil } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ThemedTextField(
                    "example.com",
                    text: $newDomain,
                    monospaced: true,
                    accessibilityName: "Site to add a rule for",
                    onSubmit: add
                )
                accessPicker("Previews from the new site", selection: $newAccess)
                Button(isUpdate ? "Update" : "Add", action: add)
                    .buttonStyle(ThemedButtonStyle())
                    .themedDisabled(candidate == nil)
                    .help(isUpdate ? "Change the rule for \(candidate ?? "this site")" : "Add a rule for this site")
                    .accessibilityLabel(isUpdate ? "Update rule" : "Add rule")
            }
            if showsInvalidHint {
                Text("Enter a site's domain, such as example.com.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme[ThemeKey.statusError])
                    .padding(.horizontal, 2)
            }
        }
        .padding(10)
        .onChange(of: newDomain) { showsInvalidHint = false }
    }

    /// A compact Everything / Text only / Nothing menu. A fixed width keeps
    /// the menus lined up from row to row.
    private func accessPicker(_ label: String, selection: Binding<SiteAccess>) -> some View {
        Picker(label, selection: selection) {
            ForEach(SiteAccess.allCases, id: \.self) { access in
                Text(Self.title(for: access)).tag(access)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: 104)
        .help("Everything: previews, images and players. Text only: titles and descriptions. Nothing: Vela never contacts the site.")
        .accessibilityLabel(label)
    }

    // MARK: Actions

    private func add() {
        guard let domain = Self.ruleDomain(newDomain) else {
            // Only explain on Return: mid-typing ("exa") is always invalid.
            showsInvalidHint = !newDomain.allSatisfy(\.isWhitespace)
            return
        }
        // Writing a domain that already has a rule replaces it.
        withAnimation(.snappy(duration: 0.2)) { setRule(newAccess, domain) }
        newDomain = ""
    }

    // MARK: Logic

    /// The menu wording for each access level.
    nonisolated static func title(for access: SiteAccess) -> String {
        switch access {
        case .allow: "Everything"
        case .textOnly: "Text only"
        case .block: "Nothing"
        }
    }

    nonisolated static func symbol(for access: SiteAccess) -> String {
        switch access {
        case .allow: "checkmark.circle.fill"
        case .textOnly: "text.alignleft"
        case .block: "nosign"
        }
    }

    nonisolated static func colorKey(for access: SiteAccess) -> String {
        switch access {
        case .allow: ThemeKey.statusSuccess
        case .textOnly: ThemeKey.settingsSecondaryForeground
        case .block: ThemeKey.statusError
        }
    }

    /// Cleans up a typed or pasted site, or returns nil when it isn't one:
    /// `https://www.Example.com:8080/page` → `example.com`.
    ///
    /// Normalizes like the rules themselves (`SiteRules.normalizedDomain`), then
    /// requires a dot so a bare word or a TLD (`com`) can't cover half the web.
    /// A leading `www.` is dropped because rules cover subdomains, and a rule
    /// for `www.example.com` would miss `example.com` itself. IP addresses are
    /// kept as typed.
    nonisolated static func ruleDomain(_ text: String) -> String? {
        guard var domain = SiteRules.normalizedDomain(text) else { return nil }
        if domain.contains(":") {
            // IPv6 literal.
            return domain.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." } ? domain : nil
        }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.allSatisfy({ label in
                  !label.isEmpty && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
              })
        else { return nil }
        if labels.count > 2, labels[0] == "www" { domain.removeFirst(4) }
        return domain
    }

    /// Rules sorted by site, each parent before its subdomains
    /// (`example.com`, `i.example.com`, `news.example`), so a more specific
    /// rule sits right under the one it overrides.
    nonisolated static func sorted(_ rules: [String: SiteAccess]) -> [Rule] {
        rules
            .map { Rule(domain: $0.key, access: $0.value) }
            .sorted { sortKey($0.domain) < sortKey($1.domain) }
    }

    /// (site, labels from the top down): `a.b.example.com` → (`example.com`, `com.example.b.a`).
    nonisolated static func sortKey(_ domain: String) -> (String, String) {
        let isIP = domain.contains(":") || domain.allSatisfy { $0.isNumber || $0 == "." }
        let labels = domain.split(separator: ".")
        let site = isIP ? domain : labels.suffix(2).joined(separator: ".")
        return (site, labels.reversed().joined(separator: "."))
    }
}

/// The minus button at the end of a rule row; it turns the error color on
/// hover to read as destructive.
private struct RemoveRuleButton: View {
    @Environment(\.theme) private var theme
    let domain: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(theme[isHovered ? ThemeKey.statusError : ThemeKey.settingsSecondaryForeground])
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Remove the rule for \(domain)")
        .accessibilityLabel("Remove the rule for \(domain)")
    }
}
