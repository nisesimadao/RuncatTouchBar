/*
 RuncatTouchBarAppDelegate.swift
 RuncatTouchBar

 Keeps RunCat Neo's original application lifecycle intact, then adds the
 Control Strip integration on top.
 */

import AppKit
import Model
import UserInterface

final class RuncatTouchBarAppDelegate: NSObject, NSApplicationDelegate {
    private let baseAppDelegate = AppDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        baseAppDelegate.applicationDidFinishLaunching(notification)
        TouchBarController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        TouchBarController.shared.stop()
        baseAppDelegate.applicationWillTerminate(notification)
    }
}
