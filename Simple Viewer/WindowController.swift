//
//  WindowController.swift
//  Simple Viewer
//
//

import Cocoa
import QuickLookUI

class WindowController : NSWindowController
{
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let controller = self.contentViewController?.children[1] as? BrowserViewController, let downloadController = segue.destinationController as? DownloadsViewController {
            downloadController.downloadQueue = controller.downloadQueue
        }
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        super.endPreviewPanelControl(panel)
    }
} 
