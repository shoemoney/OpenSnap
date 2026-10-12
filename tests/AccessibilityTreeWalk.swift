// G10b: the accessibility tree an external client sees, walked from the WINDOW down and never from the control objects a test already holds.
// AppKit only, no @main, no #if: list this file among a suite's sources and call AXTree.walk(window).
//
// The walk uses the NSAccessibility protocol an assistive client reaches (children, role, label, value, enabled, parent, press; a titled standard
// button's AXTitle is read through the legacy attribute the server asks for, see `name(of:)`), and the
// same expansion the AX server applies: `window.accessibilityChildren()`, then for every element `NSAccessibility.unignoredChildren(from:)` of
// its `accessibilityChildren()`. A control a test can reach through its own property but the walk cannot is invisible to VoiceOver and to
// every external client, which is exactly the defect this guards: a glass plate or panel that is an accessibility element but answers with no
// children. Each reached element must also report as its `accessibilityParent` the element it was reached from, so navigating up and down
// agree, and the chain of parents must lead back to the window.
import AppKit

@MainActor
enum AXTree {
    struct Node {
        let element: any NSAccessibilityProtocol
        let role: NSAccessibility.Role?
        /// The name a client shows: AXDescription (the label), else AXTitle.
        let label: String?
        /// AXTitle as the server reads it, and AXDescription (both through the legacy attributes when the new-style methods are silent).
        let title: String?
        let axDescription: String?
        let value: Any?
        let enabled: Bool
        let depth: Int
        /// What an assistive client also reads (WP1a): the hint, the subrole, the identifier, the frame in screen coordinates, whether it is
        /// selected, the names of its custom actions and how many children the element itself lists.
        let help: String?
        let subrole: NSAccessibility.Subrole?
        let identifier: String
        let frame: CGRect
        let selected: Bool
        let customActions: [String]
        let childCount: Int
        /// Index (in `Tree.nodes`) of the element this one was reached from; nil for a child of the window.
        let reachedFrom: Int?

        var object: AnyObject { element as AnyObject }
        /// The view a click on this element lands on: the element itself, or the control a cell belongs to.
        var hostView: NSView? { (element as? NSView) ?? (element as? NSCell)?.controlView }
        var number: Int? { (value as? NSNumber)?.intValue }
        var text: String? { value as? String }
    }

    struct Tree {
        let window: NSWindow
        fileprivate(set) var nodes: [Node] = []
        /// Elements the walk reached twice: an element listed under two parents, or under itself.
        fileprivate(set) var duplicates: [String] = []
        /// What is wrong with the RAW lists the elements answer with, before any unignored expansion (see `shapeProblems`).
        fileprivate(set) var rawProblems: [String] = []

        /// What an assistive client would find odd about the tree's shape: an element's own `accessibilityChildren()` that hands out something other
        /// than a real element (the AX server publishes a plain view in such a list as a role-less AXUnknown wrapper around the control inside it,
        /// which `unignoredChildren` would quietly flatten away in the walk), or a node with no role. AppKit's native title-bar groups can be unnamed;
        /// app-owned group names are checked by each surface's required-control assertions.
        func shapeProblems() -> [String] {
            var problems = rawProblems
            for node in nodes {
                if node.role == nil || node.role == .unknown { problems.append("a node of unknown role: \"\(node.label ?? "")\" (\(type(of: node.object)))") }
            }
            return problems
        }

        /// `role "label"` for every element from the window down to `index`, joined with ">".
        func path(of index: Int) -> String {
            var parts: [String] = [], current: Int? = index
            while let step = current {
                parts.insert("\(nodes[step].role?.rawValue ?? "?") \"\(nodes[step].label ?? "")\"", at: 0)
                current = nodes[step].reachedFrom
            }
            return parts.joined(separator: ">")
        }

        struct OrderProblem {
            /// Index of the parent whose children disagree; nil for the children of the window (or of the audited view).
            let parent: Int?
            let path: String
            let label: String
            let message: String
        }

        /// Within one AX parent, the order `accessibilityChildren()` lists its children in against the order the eye reads them: rows from the top,
        /// each row left to right. A parent opts out with an identifier that starts with "order-free" (the canvas, a free-form board), and so do
        /// the elements below it. Elements without a frame (zero-sized) are left out, they cannot be read in any order, and so are the window's
        /// own title-bar buttons, which AppKit lists wherever it likes, and a scroll area's scroll bars (AppKit lists them after the content, and a bar spans the
        /// whole edge, so by frame alone it would always be read first).
        func readingOrderProblems() -> [OrderProblem] {
            let furniture: Set<NSAccessibility.Subrole> = [.closeButton, .minimizeButton, .zoomButton, .fullScreenButton, .toolbarButton]
            var groups: [Int?: [Int]] = [:]
            for (index, node) in nodes.enumerated() where node.frame.width > 0 && node.frame.height > 0 && node.role != .scrollBar && !node.identifier.hasPrefix("order-free") && !(node.subrole.map { furniture.contains($0) } ?? false) {
                groups[node.reachedFrom, default: []].append(index)
            }
            func orderFree(_ parent: Int?) -> Bool {
                var current = parent
                while let step = current {
                    if nodes[step].identifier.hasPrefix("order-free") { return true }
                    current = nodes[step].reachedFrom
                }
                return false
            }
            var problems: [OrderProblem] = []
            for (parent, members) in groups.sorted(by: { ($0.key ?? -1) < ($1.key ?? -1) }) where members.count > 1 && !orderFree(parent) {
                let eye = AXTree.eyeOrder(members.map { nodes[$0].frame })
                let expected = eye.map { members[$0] }
                if expected != members {
                    let first = zip(members, expected).first { $0 != $1 }!
                    let owner = parent.map { path(of: $0) } ?? "the window"
                    problems.append(OrderProblem(parent: parent, path: owner, label: parent.flatMap { nodes[$0].label } ?? "",
                        message: "\(owner) lists \(describe(nodes[first.0])) where the eye reads \(describe(nodes[first.1]))"))
                }
            }
            return problems
        }

        func nodes(role: NSAccessibility.Role) -> [Node] { nodes.filter { $0.role == role } }
        func find(_ role: NSAccessibility.Role, _ label: String) -> Node? { nodes.first { $0.role == role && $0.label == label } }
        func find(label: String) -> Node? { nodes.first { $0.label == label } }

        func index(of node: Node) -> Int? { nodes.firstIndex { $0.object === node.object } }

        /// The nodes reached through `node`, at any depth, in the order the walk met them.
        func descendants(of node: Node) -> [Node] {
            guard let root = index(of: node) else { return [] }
            return nodes.filter { candidate in
                var current = candidate.reachedFrom
                while let step = current {
                    if step == root { return true }
                    current = nodes[step].reachedFrom
                }
                return false
            }
        }

        func children(of node: Node) -> [Node] {
            guard let root = index(of: node) else { return [] }
            return nodes.filter { $0.reachedFrom == root }
        }

        /// What is wrong with the parent chains, one message each: an element whose `accessibilityParent` is not the element it was reached from,
        /// or whose chain of parents does not end at the window.
        func parentProblems(where include: (Node) -> Bool = { _ in true }) -> [String] {
            var problems = duplicates
            for node in nodes where include(node) {
                let expected: AnyObject = node.reachedFrom.map { nodes[$0].object } ?? window
                let reported = node.element.accessibilityParent() as AnyObject?
                if reported !== expected {
                    problems.append("\(describe(node)): parent is \(describe(reported)), but it was reached from \(describe(expected))")
                }
                var current: AnyObject? = reported, steps = 0, reachedWindow = false
                while let parent = current, steps < 64 {
                    if parent === window { reachedWindow = true; break }
                    current = (parent as? any NSAccessibilityProtocol)?.accessibilityParent() as AnyObject?
                    steps += 1
                }
                if !reachedWindow { problems.append("\(describe(node)): the chain of parents does not lead back to the window") }
            }
            return problems
        }

        private func describe(_ node: Node) -> String { "\(node.role?.rawValue ?? "?") \"\(node.label ?? "")\" (\(type(of: node.object)))" }
        private func describe(_ object: AnyObject?) -> String {
            guard let object else { return "nil" }
            if object === window { return "the window" }
            if let element = object as? any NSAccessibilityProtocol { return "\(element.accessibilityRole()?.rawValue ?? "?") \"\(element.accessibilityLabel() ?? "")\" (\(type(of: object)))" }
            return "\(type(of: object))"
        }

        /// A readable dump, for a failure message.
        var outline: String {
            nodes.map { String(repeating: "  ", count: $0.depth) + "\($0.role?.rawValue ?? "?") \"\($0.label ?? "")\"" }.joined(separator: "\n")
        }
    }

    /// The tree below `window`, as the accessibility server publishes it.
    static func walk(_ window: NSWindow, limit: Int = 4000) -> Tree { walk(roots: window.accessibilityChildren(), in: window, limit: limit) }

    /// The tree below one view (an ignored plain view is replaced by what it contains, as the server does). A view that is not in a window is
    /// walked against a throwaway one: its roles, names and values are real, its frames are not.
    static func walk(_ view: NSView, limit: Int = 4000) -> Tree {
        let window = view.window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return walk(roots: [view], in: window, limit: limit)
    }

    /// Rows from the top, each row left to right: the indices of `frames` in the order the eye reads them. Frames are in screen coordinates
    /// (y up). Two frames share a row when the lower one's top edge is above the middle of the row's first frame.
    nonisolated static func eyeOrder(_ frames: [CGRect]) -> [Int] {
        let byTop = frames.indices.sorted { frames[$0].maxY != frames[$1].maxY ? frames[$0].maxY > frames[$1].maxY : frames[$0].minX < frames[$1].minX }
        var rows: [[Int]] = []
        for index in byTop {
            if let anchor = rows.last?.first, frames[index].maxY > frames[anchor].midY { rows[rows.count - 1].append(index) } else { rows.append([index]) }
        }
        return rows.flatMap { $0.sorted { frames[$0].minX < frames[$1].minX } }
    }

    private static func walk(roots: [Any]?, in window: NSWindow, limit: Int) -> Tree {
        var tree = Tree(window: window)
        var seen = Set<ObjectIdentifier>([ObjectIdentifier(window)])
        func visit(_ raw: [Any]?, from parent: Int?, depth: Int) {
            let owner = parent.map { "\(tree.nodes[$0].role?.rawValue ?? "?") \"\(tree.nodes[$0].label ?? "")\"" } ?? "the window"
            for item in raw ?? [] { if let problem = rawProblem(item) { tree.rawProblems.append("\(owner) lists \(problem)") } }
            for case let child as any NSAccessibilityProtocol in NSAccessibility.unignoredChildren(from: raw ?? []) {
                guard tree.nodes.count < limit else { return }
                let object = child as AnyObject
                guard seen.insert(ObjectIdentifier(object)).inserted else {
                    tree.duplicates.append("\(child.accessibilityRole()?.rawValue ?? "?") \"\(child.accessibilityLabel() ?? "")\" is listed more than once")
                    continue
                }
                let index = tree.nodes.count
                tree.nodes.append(Node(element: child, role: child.accessibilityRole(), label: Self.name(of: child), title: Self.title(of: child), axDescription: Self.description(of: child),
                                       value: child.accessibilityValue(),
                                       enabled: child.isAccessibilityEnabled(), depth: depth,
                                       help: child.accessibilityHelp().flatMap { $0.isEmpty ? nil : $0 }, subrole: child.accessibilitySubrole(),
                                       identifier: child.accessibilityIdentifier() ?? "", frame: child.accessibilityFrame(), selected: child.isAccessibilitySelected(),
                                       customActions: (child.accessibilityCustomActions() ?? []).map(\.name), childCount: child.accessibilityChildren()?.count ?? 0,
                                       reachedFrom: parent))
                visit(child.accessibilityChildren(), from: index, depth: depth + 1)
            }
        }
        visit(roots, from: nil, depth: 0)
        return tree
    }

    private static func legacy(_ element: any NSAccessibilityProtocol, _ attribute: NSAccessibility.Attribute) -> String? {
        let text = (element as? NSObject)?.accessibilityAttributeValue(attribute) as? String
        return text?.isEmpty == false ? text : nil
    }

    /// AXTitle the way AXUIElement reads it. A standard titled button's cell answers only through the legacy attribute (which the server asks
    /// for); a custom element answers `accessibilityTitle()`.
    private static func title(of element: any NSAccessibilityProtocol) -> String? {
        if let title = element.accessibilityTitle(), !title.isEmpty { return title }
        return legacy(element, .title)
    }

    /// AXDescription: the label a custom element sets. A standard button is published as its cell, and the server's AXDescription for the cell is
    /// the label its control carries (verified with an external AXUIElement client: a titled command shows its longer label, an icon-only one its
    /// name), which the new-style methods on the cell do not echo; the walker reads it from the control, then from the legacy attribute.
    private static func description(of element: any NSAccessibilityProtocol) -> String? {
        if let label = element.accessibilityLabel(), !label.isEmpty { return label }
        if let label = (element as? NSCell)?.controlView?.accessibilityLabel(), !label.isEmpty { return label }
        return legacy(element, .description)
    }

    /// Why an item in an element's raw children list is not a real element, or nil. A view in the list must itself be an accessibility element
    /// (a standard control is not: its cell is, and AppKit's own lists hand out the cell); anything else must have a role.
    private static func rawProblem(_ item: Any) -> String? {
        // AppKit also publishes legacy cell proxies which do not adopt the newer protocol. Judge their server-facing role attribute,
        // rather than rejecting an otherwise valid accessibility object for its implementation type.
        let element = item as? any NSAccessibilityProtocol
        let legacy = item as? NSObject
        let role = element?.accessibilityRole()?.rawValue ?? legacy?.accessibilityAttributeValue(.role) as? String
        let name = element?.accessibilityLabel() ?? legacy?.accessibilityAttributeValue(.description) as? String ?? ""
        if role == nil || role == NSAccessibility.Role.unknown.rawValue { return "\(type(of: item)) \"\(name)\" with no role" }
        if let view = item as? NSView, !view.isAccessibilityElement() { return "the plain view \(type(of: item)) \"\(name)\", which is not an accessibility element" }
        return nil
    }

    /// What a client calls the element: its description, else its title.
    private static func name(of element: any NSAccessibilityProtocol) -> String? {
        description(of: element) ?? title(of: element) ?? element.accessibilityLabel()
    }

    /// Performs AXPress on a reached element, as an assistive client would.
    /// A standard button is published as its cell, which performs AXPress through the legacy action (its new-style method acts but answers
    /// false); any other element answers `accessibilityPerformPress()`.
    static func press(_ node: Node) -> Bool {
        if let cell = node.element as? NSCell {
            guard cell.accessibilityActionNames().contains(.press) else { return false }
            cell.accessibilityPerformAction(.press)
            return true
        }
        return node.element.accessibilityPerformPress()
    }
}
