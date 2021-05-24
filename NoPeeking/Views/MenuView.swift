//
//  MenuView.swift
//  NoPeeking
//
//  Created by Luke Porupski on 12/19/20.
//  Copyright © 2020 Golden Chopper. All rights reserved.
//

import AppKit

@objc protocol MenuDelegate {
    @objc func toggledTrackingState()
    @objc func toggledFlashState()
    @objc func preview()
    @objc func terminate()
}

class MenuView: NSMenu {
    var cameraEnabledItems: [NSMenuItem] = []
    var cameraDisabledItems: [NSMenuItem] = []
    var sharedItems: [NSMenuItem] = []

    var menuDelegate: MenuDelegate?
    var cameraDisabled = false {
        didSet {
            if cameraDisabled != oldValue {
                print("set camera disabled to ", cameraDisabled)
                if cameraDisabled {
                    self.items = cameraDisabledItems + sharedItems
                } else {
                    self.items = cameraEnabledItems + sharedItems
                }
            }
        }
    }
    var canPreview = true {
        didSet {
            if let item = self.items.first(where: { item in item.identifier?.rawValue == "preview" }) {
                item.isEnabled = canPreview
            }
        }
    }
    
    var flashingEnabled = false {
        didSet {
            if let item = self.items.first(where: { item in item.identifier?.rawValue == "flash" }) {
                item.state = flashingEnabled ? .on : .off
                item.title = flashingEnabled ? "Disable Alert Flashing" : "Enable Alert Flashing"
            }
        }
    }
    var trackingActive = true {
        didSet {
            if let item = self.items.first(where: { item in item.identifier?.rawValue == "track" }) {
                item.state = trackingActive ? .on : .off
                item.title = trackingActive ? "Pause Monitoring" : "Enable Monitoring"
            }
        }
    }
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initMenuItems()
    }
    
    init(title: String, delegate: MenuDelegate) {
        self.menuDelegate = delegate
        super.init(title: title)
        self.autoenablesItems = false
        initMenuItems()
    }
    
    fileprivate func initMenuItems() {
        // Configure flashing state
        let flashToggle = NSMenuItem(title: "Enable Alert Flashing", action: #selector(menuDelegate?.toggledFlashState), keyEquivalent: "")
        flashToggle.state = .off
        flashToggle.onStateImage = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Disable alert flashing")
        flashToggle.offStateImage = NSImage(systemSymbolName: "bolt", accessibilityDescription: "Enable alert flashing")
        flashToggle.identifier = NSUserInterfaceItemIdentifier("flash")
        self.addItem(flashToggle)
        
        // Configure tracking toggle
        let pauseToggle = NSMenuItem(title: "Pause Monitoring", action: #selector(menuDelegate?.toggledTrackingState), keyEquivalent: "")
        pauseToggle.state = .on
        pauseToggle.offStateImage = NSImage(systemSymbolName: "play", accessibilityDescription: "Start Monitoring")
        pauseToggle.onStateImage = NSImage(systemSymbolName: "pause", accessibilityDescription: "Pause Monitoring")
        pauseToggle.identifier = NSUserInterfaceItemIdentifier("track")
        self.addItem(pauseToggle)

        
        // Configure preview toggle
        let previewItem = NSMenuItem(title: "Preview Alert", action: #selector(menuDelegate?.preview), keyEquivalent: "")
        previewItem.identifier = NSUserInterfaceItemIdentifier("preview")
        previewItem.state = .off
        previewItem.offStateImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Preview alert")
        previewItem.onStateImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Preview alert")
        self.addItem(previewItem)
        
        cameraEnabledItems = [flashToggle, pauseToggle, previewItem]
        
        // Setup disabled text
        let cameraRequiredItem = NSMenuItem(title: "Camera Access Required", action: nil, keyEquivalent: "")
        let itemTitle = NSAttributedString(
            string: "Camera Access Required\n",
            attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 14, weight: .semibold)]
        )
        
        let itemMessage = NSAttributedString(
            string: "Enable via system preferences:\nSecurity & Privacy -> Camera",
            attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 12, weight: .regular)]
        )
        
        let mergedStrings = NSMutableAttributedString(string: "")
        mergedStrings.append(itemTitle)
        mergedStrings.append(itemMessage)
        cameraRequiredItem.attributedTitle = mergedStrings
        
//        cameraRequiredItem.attributedTitle = NSAttributedString(string: "Camera Access Required\nEnable by going to:\n\nSystem Preferences ->\nSecurity & Privacy ->\nCamera", attributes: nil)
        cameraRequiredItem.isEnabled = false
        cameraDisabledItems = [cameraRequiredItem]
        
        self.addItem(NSMenuItem.separator())
        
        // Configure close toggle
        let closeItem = NSMenuItem(title: "Quit", action: #selector(menuDelegate?.terminate), keyEquivalent: "q")
        self.addItem(closeItem)
        
        sharedItems = [NSMenuItem.separator(), closeItem]
        
        for item in self.items {
            item.target = menuDelegate
        }
    }
}
