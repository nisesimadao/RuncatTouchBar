/*
 TouchBarPrivateAPI.swift
 RuncatTouchBar

 Uses private AppKit / DFRFoundation entry points to place a persistent item in
 the Touch Bar Control Strip. This is intentionally isolated behind one small
 bridge so the rest of the app stays on normal AppKit APIs.
 */

import AppKit
import Darwin
import ObjectiveC.runtime

@MainActor
final class TouchBarPrivateAPI {
    static let shared = TouchBarPrivateAPI()

    private let frameworkHandle: UnsafeMutableRawPointer?

    private init() {
        let paths = [
            "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation",
            "/System/Library/PrivateFrameworks/TouchBarSupport.framework/TouchBarSupport",
        ]
        frameworkHandle = paths.lazy.compactMap {
            dlopen($0, RTLD_LAZY | RTLD_LOCAL)
        }.first
    }

    var isAvailable: Bool {
        guard frameworkHandle != nil else { return false }
        let addSelector = NSSelectorFromString("addSystemTrayItem:")
        let presentSelector = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        let presentFallbackSelector = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        return dfrSymbol("DFRElementSetControlStripPresenceForIdentifier") != nil
            && class_getClassMethod(NSTouchBarItem.self, addSelector) != nil
            && (class_getClassMethod(NSTouchBar.self, presentSelector) != nil
                || class_getClassMethod(NSTouchBar.self, presentFallbackSelector) != nil)
    }

    func setControlStripPresence(_ identifier: NSTouchBarItem.Identifier, visible: Bool) {
        typealias Function = @convention(c) (UnsafeRawPointer?, Bool) -> Void
        guard let symbol = dfrSymbol("DFRElementSetControlStripPresenceForIdentifier") else { return }
        let function = unsafeBitCast(symbol, to: Function.self)
        let value = identifier.rawValue as NSString
        function(Unmanaged.passUnretained(value).toOpaque(), visible)
    }

    func setSystemModalCloseBoxVisible(_ visible: Bool) {
        typealias Function = @convention(c) (Bool) -> Void
        guard let symbol = dfrSymbol("DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
        let function = unsafeBitCast(symbol, to: Function.self)
        function(visible)
    }

    @discardableResult
    func addSystemTrayItem(_ item: NSTouchBarItem) -> Bool {
        let selector = NSSelectorFromString("addSystemTrayItem:")
        guard let method = class_getClassMethod(NSTouchBarItem.self, selector) else { return false }
        typealias Function = @convention(c) (AnyObject, Selector, NSTouchBarItem) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        function(NSTouchBarItem.self as AnyObject, selector, item)
        return true
    }

    func removeSystemTrayItem(_ item: NSTouchBarItem) {
        let selector = NSSelectorFromString("removeSystemTrayItem:")
        guard let method = class_getClassMethod(NSTouchBarItem.self, selector) else { return }
        typealias Function = @convention(c) (AnyObject, Selector, NSTouchBarItem) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        function(NSTouchBarItem.self as AnyObject, selector, item)
    }

    @discardableResult
    func present(_ touchBar: NSTouchBar, from identifier: NSTouchBarItem.Identifier) -> Bool {
        let identifierObject = identifier.rawValue as NSString

        let placementSelector = NSSelectorFromString(
            "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"
        )
        if let method = class_getClassMethod(NSTouchBar.self, placementSelector) {
            typealias Function = @convention(c) (
                AnyObject,
                Selector,
                NSTouchBar,
                Int64,
                NSString
            ) -> Void
            let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
            function(NSTouchBar.self as AnyObject, placementSelector, touchBar, 1, identifierObject)
            return true
        }

        let selector = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        if let method = class_getClassMethod(NSTouchBar.self, selector) {
            typealias Function = @convention(c) (
                AnyObject,
                Selector,
                NSTouchBar,
                NSString
            ) -> Void
            let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
            function(NSTouchBar.self as AnyObject, selector, touchBar, identifierObject)
            return true
        }

        return false
    }

    func dismiss(_ touchBar: NSTouchBar) {
        let selectors = [
            NSSelectorFromString("dismissSystemModalTouchBar:"),
            NSSelectorFromString("dismissSystemModalFunctionBar:"),
        ]
        for selector in selectors {
            guard let method = class_getClassMethod(NSTouchBar.self, selector) else { continue }
            typealias Function = @convention(c) (AnyObject, Selector, NSTouchBar) -> Void
            let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
            function(NSTouchBar.self as AnyObject, selector, touchBar)
            return
        }
    }

    private func dfrSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let frameworkHandle else { return nil }
        return dlsym(frameworkHandle, name)
    }
}
