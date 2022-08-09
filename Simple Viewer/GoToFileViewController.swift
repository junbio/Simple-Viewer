//
//  GoToFileViewController.swift
//  Simple Viewer
//
//

import AppKit

class GoToFileViewController : NSViewController
{
    
    @IBOutlet var searchField : NSComboBox?
    @IBOutlet var okButton : NSButton?
    @IBOutlet var cancelButton : NSButton?
    
    var previousSearches : [String]?
    var completionBlock : ((String) -> Void)?
    
    @IBAction func cancel(_ sender : Any?){
        self.dismiss(nil)
    }
    
    @IBAction func goToFile(_ sender : Any?){
        if let completionBlock = completionBlock {
            completionBlock(searchField!.stringValue)
        }
        self.dismiss(nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.okButton?.isEnabled = false
        self.searchField?.delegate = self
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        self.searchField?.removeAllItems()
        if let searches = self.previousSearches {
        for search in searches {
            self.searchField?.addItem(withObjectValue: search)
        }
        }
        
    }
    
    

}

extension GoToFileViewController : NSComboBoxDelegate
{
    func controlTextDidChange(_ obj: Notification) {
        self.okButton?.isEnabled = self.searchField!.stringValue.count > 0
    }
    
    func comboBoxSelectionDidChange(_ notification: Notification) {
        self.okButton?.isEnabled = true
    }
}
