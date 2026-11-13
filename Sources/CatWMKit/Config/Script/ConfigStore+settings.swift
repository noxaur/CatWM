import AppKit

extension ConfigStore {
    package var isScript: Bool { isLoaded && source == .script }

    package func set(option: ConfigOption, _ value: String) throws {
        guard source == .script else { return try Config.write(option: option.key, value, to: confURL) }
        var edited = current
        if let problem = option.read(&edited, value, option.key) { throw ConfigError(message: problem) }
        if embedded {
            var overrides = heldOverrides
            ConfigScript.set(ConfigScript.json(option, in: edited), at: option.script, in: &overrides)
            return heldOverrides = overrides
        }
        try write(edits(from: current, to: edited), expected: edited)
    }

    package func set(_ path: String, to value: JSON) throws {
        var overrides = heldOverrides
        ConfigScript.set(value, at: path, in: &overrides)
        var probe = base
        if let problem = ConfigScript.read(.object(overrides), into: &probe, file: nil, embedded: embedded).first {
            throw ConfigError(message: problem.message)
        }
        heldOverrides = overrides
    }

    package var overrides: [String: JSON] { heldOverrides }

    package func resetOverride(_ path: String) {
        ConfigScript.remove(path, from: &heldOverrides)
    }

    package struct SettingsCopy {
        package let text: String
        package let shown: Config
        package let source: Config
    }

    package var settingsCopy: SettingsCopy {
        let text = settingsText
        return SettingsCopy(text: text, shown: ConfigText(text).config, source: current)
    }

    package func save(settings edited: Config, from copy: SettingsCopy) throws {
        let shown = copy.shown
        var merged = current
        for option in Options.all where option.text(edited) != option.text(shown) { option.copy(&merged, edited) }
        if edited.layouts != shown.layouts { merged.layouts = edited.layouts }
        if edited.floating != shown.floating { merged.floating = edited.floating }
        if edited.mainMod != shown.mainMod { merged.mainMod = edited.mainMod }
        if edited.changes(from: shown).contains("bindings") {
            let aligned = shown.bindings.count == copy.source.bindings.count
            merged.bindings = edited.bindings.map { binding in
                guard aligned, let index = shown.bindings.firstIndex(of: binding) else { return binding }
                return copy.source.bindings[index]
            }
            merged.bindings = Self.functionsLast(merged.bindings)
        }
        try write(edits(from: current, to: merged), expected: merged)
    }

    static func functionsLast(_ bindings: [KeyBinding]) -> [KeyBinding] {
        bindings.filter { $0.function == nil } + bindings.filter { $0.function != nil }
    }

    struct Edit {
        let path: String
        let value: JSON
    }

    func edits(from old: Config, to new: Config) -> [Edit] {
        var edits = Options.all.filter { $0.text(new) != $0.text(old) }.map {
            Edit(path: $0.script, value: ConfigScript.json($0, in: new))
        }
        let changes = new.changes(from: old)
        if changes.contains("layouts") {
            edits.append(Edit(path: "layouts", value: .array(new.layouts.map { .string($0.rawValue) })))
        }
        if changes.contains("floating") {
            edits.append(Edit(path: "floating.apps", value: .array(new.floating.map(JSON.string))))
        }
        if changes.contains("mod") { edits.append(Edit(path: "mod", value: ConfigScript.json(mod: new.mainMod))) }
        if changes.contains("bindings") {
            let binds = ConfigScript.json(binds: new.bindings.filter { $0.function == nil })
            edits.append(Edit(path: "binds", value: binds.binds))
            edits.append(Edit(path: "submaps", value: binds.submaps))
        }
        return edits
    }

    func write(_ edits: [Edit], expected: Config) throws {
        guard !edits.isEmpty else { return }
        var reason = ""
        for inPlace in [true, false] {
            var files: [String: String] = [:]
            for edit in edits.sorted(by: { line(of: $0) > line(of: $1) }) {
                place(edit, inPlace: inPlace, into: &files)
            }
            if let problem = trial(files, matching: expected) {
                if reason.isEmpty { reason = problem }
                continue
            }
            for (path, text) in files {
                try text.write(to: URL(fileURLWithPath: path).resolvingSymlinksInPath(), atomically: true,
                               encoding: .utf8)
            }
            return
        }
        throw ConfigError(message: "CatWM couldn't save this change to \(Self.scriptName), so it left the file "
            + "alone: \(reason)")
    }

    private func line(of edit: Edit) -> Int { sources[edit.path]?.line ?? 0 }

    private func place(_ edit: Edit, inPlace: Bool, into files: inout [String: String]) {
        if inPlace, let source = sources[edit.path] {
            if let text = files[source.file] ?? (try? String(contentsOfFile: source.file, encoding: .utf8)),
               let edited = ConfigEdit.replacing(edit.path, with: edit.value, in: text, near: source.line) {
                files[source.file] = edited
                return
            }
        }
        let path = scriptURL.path
        let text = files[path] ?? (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        files[path] = ConfigEdit.settings(edit.path, edit.value, in: text)
    }

    package var settingsText: String {
        let main = NSEvent.ModifierFlags(rawValue: UInt(current.mainMod.rawValue))
        let mainText = ConfigScript.mods.filter { main.contains($0.flag) }.map(\.conf).joined(separator: " ")
        let rows = current.bindRows.map { row -> BindRow in
            guard !main.isEmpty, let flags = ConfigText.flags(row.mods), flags.isSuperset(of: main) else { return row }
            var copy = row
            let rest = ConfigScript.mods.filter { flags.subtracting(main).contains($0.flag) }.map(\.conf)
            copy.mods = ([Self.settingsMod] + rest).joined(separator: " ")
            return copy
        }
        let mod = VarRow(name: Self.settingsMod, value: mainText.isEmpty ? "ALT" : mainText)
        return ConfigText.keyboard(vars: [mod], binds: rows)
            + Options.lines(current).joined(separator: "\n") + "\n"
    }

    private static let settingsMod = "$__catwm_main_mod"
}
