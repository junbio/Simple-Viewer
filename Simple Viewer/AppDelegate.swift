//
//  AppDelegate.swift
//  Simple Viewer
//
//

import Cocoa

 @main
class AppDelegate: NSObject, NSApplicationDelegate {

    


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        
        UserDefaults.standard.register(defaults: ["columns": 0x7])
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
}

