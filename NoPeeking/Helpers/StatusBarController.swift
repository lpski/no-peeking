//
//  StatusBarController.swift
//  Luke Porupski
//
//  Created by Luke Porupski on 12/11/19.
//  Copyright © 2019 Luke Porupski. All rights reserved.
//

import AppKit
import Vision
import AVKit

class StatusBarController: CaptureMonitorDelegate, MenuDelegate {
    private var statusBar: NSStatusBar
    private var statusItem: NSStatusItem
    private var menuView: MenuView?
    private var captureMonitor: CaptureMonitor?
    
    private var flashingEnabled = false
    private var trackingEnabled = true
    private var isPreviewing = false
    
    init()
    {
        statusBar = NSStatusBar.init()
        statusItem = statusBar.statusItem(withLength: 28.0)
        
        menuView = MenuView(title: "Testing", delegate: self)
        statusItem.menu = menuView
        
        if let statusBarButton = statusItem.button {
            statusBarButton.image = NSImage(named: "white_circle")
            statusBarButton.image?.size = NSSize(width: 16.0, height: 16.0)
            statusBarButton.isBordered = true
            statusBarButton.image?.isTemplate = false
            statusBarButton.contentTintColor = NSColor(red: 0.3, green: 0.3, blue: 0.7, alpha: 1)
        }
        
        
        // Setup Capture Config
        self.captureMonitor = CaptureMonitor(delegate: self)
    }
    
    func setAlertState(color: String, active: Bool = true) {
        if !active {
            DispatchQueue.main.async {
                if let statusBarButton = self.statusItem.button {
                    statusBarButton.image = NSImage(named: "white_circle")
                    statusBarButton.image?.size = CGSize(width: 16, height: 16)
                    statusBarButton.image?.isTemplate = false
                }
            }
        } else {
            DispatchQueue.main.async {
                if let statusBarButton = self.statusItem.button {
                    statusBarButton.image = NSImage(named: color == "black" ? "black_alert" : "red_alert")
                    statusBarButton.image?.size = CGSize(width: 16, height: 16)
                    statusBarButton.image?.isTemplate = false
                }
            }
        }
    }
    
    func flashAlert() {
        var isRed = false
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            DispatchQueue.main.async {
                self.setAlertState(color: isRed ? "black" : "red")
                isRed = !isRed

                if !self.isPreviewing && (self.captureMonitor!.lastPeepingCount == 0 || !self.flashingEnabled || !self.trackingEnabled) {
                    self.setAlertState(color: "red", active: self.captureMonitor!.lastPeepingCount > 0)
                    timer.invalidate()
                }
            }
        }
    }
    
    // Capture Delegate Methods
    func faceDetectionUpdate(faces: [VNFaceObservation]) {
        if faces.count == 0 {
            menuView?.canPreview = true
            setAlertState(color: "red", active: false)
        } else {
            DispatchQueue.main.async {
                self.menuView?.canPreview = false
                if self.flashingEnabled { self.flashAlert() }
                else { self.setAlertState(color: "red") }
            }
        }
    }
    func captureError(error: Error) {}
    func cameraAccessRejected() {
        menuView?.cameraDisabled = true
    }
    
    
    // Menu Item Delegate Methods
    func toggledFlashState() {
        flashingEnabled = !flashingEnabled
        menuView?.flashingEnabled = flashingEnabled
        
        if (self.captureMonitor!.lastPeepingCount > 0) {
            flashAlert()
        }
    }
    func toggledTrackingState() {
        DispatchQueue.main.async {
            self.trackingEnabled = !self.trackingEnabled
            self.trackingEnabled ? self.captureMonitor?.start() : self.captureMonitor?.pause()
            self.menuView?.trackingActive = self.trackingEnabled
            
            if !self.trackingEnabled {
                self.setAlertState(color: "white", active: false)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: {
                    if self.flashingEnabled {
                        self.flashAlert()
                    } else {
                        self.setAlertState(color: "red", active: self.captureMonitor!.lastPeepingCount > 0)
                    }
                })
            }
        }
    }
    func preview() {
        isPreviewing = true
        flashingEnabled ? flashAlert() : setAlertState(color: "red")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.isPreviewing = false
            
            if (!self.flashingEnabled || self.captureMonitor!.lastPeepingCount == 0) {
                self.setAlertState(color: "red", active: self.captureMonitor!.lastPeepingCount > 0)
            }
        }
    }
    func terminate() {
        NSApplication.shared.terminate(self)
    }
}
