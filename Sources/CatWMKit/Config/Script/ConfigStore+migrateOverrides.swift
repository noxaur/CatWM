import Foundation

extension ConfigStore {
    @discardableResult
    package func migrateOverrides() -> Bool {
        guard !embedded, isScript, !defaults.bool(forKey: DefaultsKey.migratedOverridesToConfig) else { return false }
        guard FileManager.default.fileExists(atPath: overridesURL.path) else {
            defaults.set(true, forKey: DefaultsKey.migratedOverridesToConfig)
            return false
        }
        guard let data = try? Data(contentsOf: overridesURL), let object = JSON.parse(data)?.object else {
            return fail(migration: "the file isn't a JSON object")
        }
        let overrides = Self.droppingFunctions(ConfigScript.renamingOverrides(object))
        var expected = current
        if let problem = ConfigScript.read(.object(overrides), into: &expected, file: nil).first {
            return fail(migration: problem.message)
        }
        let kept = current.bindings.filter { $0.function != nil }
        expected.bindings = Self.functionsLast(expected.bindings.filter { $0.function == nil } + kept)
        let edits = ConfigScript.paths(overrides).compactMap { path in
            Self.value(at: path, in: overrides).map { Edit(path: path, value: $0) }
        }
        do {
            try write(edits, expected: expected)
            try FileManager.default.removeItem(at: overridesURL)
        } catch {
            return fail(migration: error.localizedDescription)
        }
        defaults.set(true, forKey: DefaultsKey.migratedOverridesToConfig)
        Log.info("config: moved \(edits.count) values from \(Self.overridesName) into \(Self.scriptName)")
        return true
    }

    private func fail(migration reason: String) -> Bool {
        let problem = ConfigDiagnostic(file: overridesURL.path, phase: .migrate,
                                       message: "CatWM couldn't move these values into \(Self.scriptName), so it left "
                                           + "the file alone and no longer applies it: \(reason)")
        Log.info("config: \(problem.text)")
        failures.append(problem)
        current.diagnostics.append(problem)
        current.errors = current.diagnostics.map(\.text)
        return false
    }

    private static func droppingFunctions(_ overrides: [String: JSON]) -> [String: JSON] {
        func isData(_ bind: JSON) -> Bool { bind["run"]?.object == nil }
        var result = overrides
        if let binds = overrides["binds"]?.array { result["binds"] = .array(binds.filter(isData)) }
        if let submaps = overrides["submaps"]?.object {
            result["submaps"] = .object(submaps.mapValues { .array($0.array?.filter(isData) ?? []) })
        }
        return result
    }

    private static func value(at path: String, in object: [String: JSON]) -> JSON? {
        path.split(separator: ".").reduce(JSON.object(object) as JSON?) { $0?[String($1)] }
    }
}
