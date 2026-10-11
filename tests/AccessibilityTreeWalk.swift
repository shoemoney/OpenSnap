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
        /// Index (in `Tree.nodes`) of the element this one was reached from; nil for a child of the window.
        let reachedFrom: Int?

        var object: AnyObject { element as AnyObject }
        var number: Int? { (value as? NSNumber)?.intValue }
        var text: String? { value as? String }
    }

    struct Tree {
        let window: NSWindow
        fileprivate(set) var nodes: [Node] = []
        /// Elements the walk reached twice: an element listed under two parents, or under itself.
        fileprivate(set) var duplicates: [String] = []

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
    static func walk(_ window: NSWindow, limit: Int = 4000) -> Tree {
        var tree = Tree(window: window)
        var seen = Set<ObjectIdentifier>([ObjectIdentifier(window)])
        func visit(_ raw: [Any]?, from parent: Int?, depth: Int) {
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
                                       enabled: child.isAccessibilityEnabled(), depth: depth, reachedFrom: parent))
                visit(child.accessibilityChildren(), from: index, depth: depth + 1)
            }
        }
        visit(window.accessibilityChildren(), from: nil, depth: 0)
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
