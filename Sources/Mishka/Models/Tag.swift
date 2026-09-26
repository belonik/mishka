import Foundation

/// One node of the nested tag tree shown in the sidebar (`#work/projects` → work ▸ projects).
struct TagNode: Identifiable, Hashable {
    let id: String          // full path without the leading '#'
    let name: String        // last path component
    var children: [TagNode]
    var count: Int          // notes carrying this tag or any descendant of it

    var displayName: String { "#" + name }

    /// Depth-first flattening, used for keyboard navigation and search.
    var flattened: [TagNode] {
        [self] + children.flatMap { $0.flattened }
    }

    /// Builds the tree from `[noteTags]`, where each element is the tag list of one note.
    /// A note is counted once per distinct path, and parent tags inherit the count of
    /// their descendants so that folding `#work` still shows how much lives inside.
    static func build(from noteTags: [[String]]) -> [TagNode] {
        // parent path ("" for roots) -> set of full child paths
        var childPaths: [String: Set<String>] = [:]
        var directCount: [String: Int] = [:]

        for tags in noteTags {
            var seen = Set<String>()
            for tag in tags {
                let components = tag.split(separator: "/").map(String.init)
                guard !components.isEmpty else { continue }
                for index in components.indices {
                    let path = components[0...index].joined(separator: "/")
                    let parent = index == 0 ? "" : components[0..<index].joined(separator: "/")
                    childPaths[parent, default: []].insert(path)
                    if index == components.count - 1, seen.insert(path).inserted {
                        directCount[path, default: 0] += 1
                    }
                }
            }
        }

        func makeNode(_ path: String) -> TagNode {
            let children = (childPaths[path] ?? []).sorted().map(makeNode)
            let total = (directCount[path] ?? 0) + children.reduce(0) { $0 + $1.count }
            let name = path.split(separator: "/").last.map(String.init) ?? path
            return TagNode(id: path, name: name, children: children, count: total)
        }

        return (childPaths[""] ?? []).sorted().map(makeNode)
    }
}
