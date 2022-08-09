//
//  SidebarViewController.swift
//  Simple Viewer
//
//

import AppKit

extension NSPasteboard.PasteboardType {
    
    static let bookmarkDragType = NSPasteboard.PasteboardType("com.simpleviewer.bookmarkDrag")
}


class SidebarViewController : NSViewController {
    @IBOutlet var sourceList : NSOutlineView?
    var bookmarks : [URL] = []
    var isUserTriggered : Bool = true
    
    @objc func handleConnection(_ sender: Any?){
        BookmarksManager.shared.load()
        
        self.sourceList?.reloadData()
    }

    func save(){
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let menu = NSMenu()
        menu.delegate = self
        
        self.sourceList?.registerForDraggedTypes([NSPasteboard.PasteboardType(rawValue: (kUTTypeItem as String)), .rowDragType, .bookmarkDragType])
        self.sourceList?.intercellSpacing = NSMakeSize(0, 8)
        self.sourceList?.menu = menu
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleConnection), name: .connected, object: nil)
    }
    
    func selectUrl(_ url: URL){
        self.isUserTriggered = false
        if let index = BookmarksManager.shared.bookmarks.firstIndex(where: { $0 == url }) {
            self.sourceList?.selectRowIndexes(IndexSet(integer: index+1), byExtendingSelection: false)
        } else {
            self.sourceList?.deselectAll(nil)
        }
    }
}
extension SidebarViewController : NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(String(outlineView.row(forItem: item)), forType: .bookmarkDragType)
        return pasteboardItem
    }
    
    func outlineView(_ outlineView: NSOutlineView,
                      viewFor tableColumn: NSTableColumn?,
                         item: Any) -> NSView?
    {
        if let header = item as? String {
            let cell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "header"), owner: nil) as? NSTableCellView
            cell?.textField?.stringValue = header
            return cell
            
        }
        
        if let cell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "cell"), owner: nil) as? NSTableCellView {
            if #available(macOS 11.0, *) {
                let image = NSImage(systemSymbolName: "folder", accessibilityDescription: "nil")
            
            cell.imageView?.image = image
            }
            let url = item as? URL
            cell.textField?.stringValue = url!.lastPathComponent
            cell.identifier = NSUserInterfaceItemIdentifier(rawValue: "cell")
            return cell
        }
        return nil
    }
    
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        
        if item != nil || index == 0 || info.numberOfValidItemsForDrop != 1 {
            return []
        }
        if index == -1{
            outlineView.setDropItem(nil, dropChildIndex: BookmarksManager.shared.bookmarks.count + 1)
            
        }
        if info.draggingPasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.bookmarkDragType.rawValue]){
            return [.move]
        }
        
        let bvc = browserViewController()
        if let draggingItem = info.draggingPasteboard.pasteboardItems?.first, let row = draggingItem.propertyList(forType: .rowDragType) as? Int, let node = bvc?.outlineView?.item(atRow: row) as? Node {
            if !node.isFolder {
                return []
            } else {
                return [.generic]
            }
        }
        return []
    }
    
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        
        if isUserTriggered, let row = self.sourceList?.selectedRow {
            browserViewController()?.goTo(BookmarksManager.shared.bookmarks[row-1])
        }
        // reset...
        isUserTriggered = true
    }

    
    func browserViewController() -> BrowserViewController? {
        // ugly hack:
        return self.view.window?.windowController?.contentViewController?.children[1] as? BrowserViewController
    }
    
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        if let _ = info.draggingSource as? NSOutlineView {
            let bvc = browserViewController()
           
        info.enumerateDraggingItems(options: .concurrent, for: outlineView, classes: [NSPasteboardItem.self], searchOptions: [:]) { (draggingItem, idx, stop) in
            if let draggingItem = draggingItem.item as? NSPasteboardItem {
                if let data = draggingItem.string(forType: .bookmarkDragType), let row = Int(data) {
                    var dest = index
                    if row < index {
                        dest -= 1
                    }
                    let src = BookmarksManager.shared.bookmarks.remove(at: row-1)
                    
                    BookmarksManager.shared.bookmarks.insert(src, at: dest-1)
                    self.sourceList?.reloadData()
                }
            else if let row = draggingItem.propertyList(forType: .rowDragType) as? Int, let node = bvc?.outlineView?.item(atRow: row) as? Node {
                print("\(node.url)")
                let duplicate = BookmarksManager
                    .shared.bookmarks.firstIndex(where: { $0 == node.url })
            
                BookmarksManager.shared.bookmarks.insert(node.url, at:index-1)
                
                if var duplicate = duplicate {
                    if duplicate > index {
                        duplicate += 1
                    }
                    BookmarksManager.shared.bookmarks.remove(at: duplicate)
                }
                self.sourceList?.reloadData()
            }
                BookmarksManager.shared.save()
            }
            }
        }
        
        return true
    }
    
    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        
        self.sourceList?.draggingDestinationFeedbackStyle = .gap
    }
    
    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        self.sourceList?.draggingDestinationFeedbackStyle = .sourceList
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return !(item is String)
        
    }
    
}

extension SidebarViewController : NSOutlineViewDataSource
{
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        return BookmarksManager.shared.bookmarks.count + 1
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return false
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        return index == 0 ? "Favorites" : BookmarksManager.shared.bookmarks[index-1]
    }
    
    
   
}
extension SidebarViewController : NSMenuDelegate
   {
       func menuNeedsUpdate(_ menu: NSMenu) {
           menu.removeAllItems()
           let menuItem = NSMenuItem(title: "Remove from Sidebar", action: #selector(delete(_:)), keyEquivalent: "")
           
           menu.addItem(menuItem)
           
       }
    
    @objc func delete(_ sender: Any?){
        BookmarksManager.shared.bookmarks.remove(at: self.sourceList!.clickedRow-1)
        BookmarksManager.shared.save()
        self.sourceList?.reloadData()
    }
       
   }
