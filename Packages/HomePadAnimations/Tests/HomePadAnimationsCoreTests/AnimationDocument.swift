import Foundation
import Testing
@testable import HomePadAnimationsCore

/// The parts of a bundled animation file that the tests reason about, read with Foundation only.
struct AnimationDocument {
    struct AnimatedProperty {
        let path: String
        let times: [Double]
        let first: [Double]
        let last: [Double]
    }

    struct Style {
        /// Layer, group, and item names joined with dots, the way Lottie keypaths are written.
        let keypath: String
        let name: String
        let type: String
        let color: [Double]
    }

    let root: [String: Any]
    let layers: [[String: Any]]
    private(set) var animatedProperties: [AnimatedProperty] = []
    private(set) var styles: [Style] = []
    private(set) var shapeTypes: Set<String> = []
    private(set) var keys: Set<String> = []
    /// Lottie stores an After Effects expression as a string under "x" on a property.
    private(set) var hasExpressions = false
    /// Number of path-drawing items in each group, by group keypath.
    private(set) var pathCounts: [String: Int] = [:]
    /// Group keypaths that hold both a trim and a fill.
    private(set) var trimmedFills: [String] = []

    init(_ animation: HomePadAnimation) throws {
        let object = try JSONSerialization.jsonObject(with: animation.data())
        root = try #require(object as? [String: Any])
        layers = try #require(root["layers"] as? [[String: Any]])
        for layer in layers {
            let name = layer["nm"] as? String ?? ""
            collectKeys(layer)
            if let transform = layer["ks"] as? [String: Any] {
                collectProperties(transform, path: name + ".Transform")
            }
            for shape in layer["shapes"] as? [[String: Any]] ?? [] {
                walk(shape, path: name)
            }
        }
    }

    func number(_ key: String) -> Double? {
        root[key] as? Double
    }

    private mutating func walk(_ item: [String: Any], path: String) {
        let type = item["ty"] as? String ?? ""
        let name = item["nm"] as? String ?? ""
        let keypath = path + "." + name
        shapeTypes.insert(type)
        if type == "gr" {
            let children = item["it"] as? [[String: Any]] ?? []
            let types = children.compactMap { $0["ty"] as? String }
            pathCounts[keypath] = types.count { ["el", "rc", "sh"].contains($0) }
            if types.contains("tm"), types.contains("fl") {
                trimmedFills.append(keypath)
            }
            for child in children {
                walk(child, path: keypath)
            }
            return
        }
        if type == "st" || type == "fl", let color = (item["c"] as? [String: Any])?["k"] as? [Double] {
            styles.append(Style(keypath: keypath, name: name, type: type, color: color))
        }
        collectProperties(item, path: keypath)
    }

    private mutating func collectProperties(_ item: [String: Any], path: String) {
        for (key, value) in item.sorted(by: { $0.key < $1.key }) {
            guard
                let property = value as? [String: Any],
                property["a"] as? Int == 1,
                let frames = property["k"] as? [[String: Any]]
            else { continue }
            let values = frames.compactMap { $0["s"] as? [Double] }
            animatedProperties.append(AnimatedProperty(
                path: path + "." + key,
                times: frames.compactMap { $0["t"] as? Double },
                first: values.first ?? [],
                last: values.last ?? []
            ))
        }
    }

    private mutating func collectKeys(_ value: Any) {
        if let dictionary = value as? [String: Any] {
            keys.formUnion(dictionary.keys)
            if dictionary["x"] is String { hasExpressions = true }
            dictionary.values.forEach { collectKeys($0) }
        } else if let array = value as? [Any] {
            array.forEach { collectKeys($0) }
        }
    }
}
