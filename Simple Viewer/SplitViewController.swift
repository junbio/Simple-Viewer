//
//  SplitViewController.swift
//  Simple Viewer
//


import AppKit

class SplitViewController : NSSplitViewController
{
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        for childViewController in children {
            if childViewController.responds(to: action) {
                return childViewController
            } else {
                guard let supplementalTarget = childViewController.supplementalTarget(forAction: action, sender: sender) else {
                    continue
                }

                return supplementalTarget
            }
        }

        return super.supplementalTarget(forAction: action, sender: sender)
    }
    
}
