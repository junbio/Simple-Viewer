//
//  ViewController.swift
//  Simple Viewer
//
//

import Cocoa
import QuickLookUI



enum ViewCellID {
    static let NameCellID = "NameCellID"
    static let ModifedCellID = "ModifiedCellID"
    static let SizeCellID = "SizeCellID"
    static let CreatedCellID = "CreatedCellID"
    static let PermissionsCellID = "PermissionsCellID"
}

func permissionsString(_ permissions : Int) -> String {
    var str = ""
    var permissions = permissions
    for _ in 0..<3 {
        
        str = (permissions & 0x1 != 0 ? "x" : "-") + str
        str = (permissions & 0x2 != 0 ? "w" : "-") + str
        str = (permissions & 0x4 != 0 ? "r" : "-") + str
        permissions >>= 3
    }
    return str
}

extension NSPasteboard.PasteboardType {
    
    static let rowDragType = NSPasteboard.PasteboardType("com.simpleviewer.dragdrop")
}

enum FolderStatus {
    case notLoaded
    case isLoading
    case isLoaded
}

func itemComparator<T:Comparable>(lhs: T, rhs: T, ascending: Bool) -> Bool
{
    if ascending {
        return rhs > lhs
    } else {
        return lhs > rhs
    }
}

class DownloadItem
{
    enum OperationType {
        case download
        case upload
    }
    
    var type : OperationType = .download
    var stop : Bool = false
    var name : String
    var icon : NSImage
    var size : Int
    var identifier : Int = -1
    var downloaded : Int

    
    init(name: String, icon: NSImage, size: Int, downloaded: Int, type: OperationType)
    {
        self.name = name
        self.icon = icon
        self.size = size
        self.downloaded = downloaded
        self.type = type
    }
}

class DownloadQueue {
    var queue : [DownloadItem] = []
}

class FilePromiseProvider : NSFilePromiseProvider
{
    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType]
    {
        var types = super.writableTypes(for: pasteboard)
        types.append(.fileURL)
        types.append(.rowDragType)
        return types
    }
    
    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .fileURL {
            if let url = (userInfo as? [String : Any])?["url"] as? NSURL {
                return url.pasteboardPropertyList(forType: type)
            }
        } else if type == .rowDragType {
            if let row = (userInfo as? [String : Any])?["row"] as? Int {
                return row
            }
        }
        
        return super.pasteboardPropertyList(forType: type)
    }
}

@objc class Node : NSObject {
    var name : String
    var url: URL
    var created : Date
    var modified : Date
    var icon : NSImage
    var size : Int64
    var isFolder : Bool
    var contents : [Node]?
    var isLoaded : FolderStatus = .notLoaded
    var path : String
    var permissions : Int
    
    @objc init(path: String, name: String, created: Date, modified: Date, icon: NSImage, size: Int64, permissions: Int, isFolder: Bool) {
        self.name = name
        self.path = path
        self.url = URL(string: path)!
        self.created = created
        self.modified = modified
        self.icon = icon
        self.size = size
        self.isFolder = isFolder
        if isFolder {
            self.contents = []
        }
        self.permissions = permissions
    }
}

enum SortDescriptor {
    static let CreatedID = "CreatedID"
    static let SizeID = "SizeID"
    static let ModifedID = "ModifiedID"
    static let NameID = "NameID"
}

func sorted(_ contents : inout [Node], ascending: Bool, key: String)
{
    contents.sort(by: {
        if key == SortDescriptor.SizeID {
            return itemComparator(lhs: $0.size, rhs: $1.size, ascending: ascending)
        } else if key == SortDescriptor.CreatedID {
            return itemComparator(lhs: $0.created, rhs: $1.created, ascending: ascending)
        } else if key == SortDescriptor.ModifedID {
            return itemComparator(lhs: $0.modified, rhs: $1.modified, ascending: ascending)
        }  else {
            return itemComparator(lhs: $0.name, rhs: $1.name, ascending: ascending)
        }
    })
    for item in contents {
        if item.isFolder {
            sorted(&item.contents!, ascending: ascending, key: key)
        }
    }
}

class BrowserViewController: NSViewController {
    
    var sortDescriptor : String = SortDescriptor.NameID
    var client : SSHClient?
    
    var previewURL : URL?
    var navigation : [URL] = []
    var navIndex : Int = 0
    var backMenu : NSMenu = NSMenu()
    var canQuit : Bool = false
    var forwardMenu : NSMenu = NSMenu()
    
    var isFiltered : Bool = false
    var filter : String?
    var results : [Node] = []
    
    weak var previewItem : DownloadItem?
    var previousSearches : [String] = []
    
    
    var columnMask : Int!

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let sortDescriptor = outlineView.sortDescriptors.first, contents?.count ?? 0 > 0 else {
          return
        }
        
        let ascending = sortDescriptor.ascending
        
        if let key = sortDescriptor.key {
            let items = saveSelecton()
            
            sorted(&contents!, ascending: ascending, key: key)
            if  self.isFiltered {
                self.results = self.contents!.filter { return $0.name.contains(self.filter!)}
            }
            outlineView.reloadData()
            
            // todo:
            
            restoreSelection(with: items)
            if let selected = self.outlineView?.selectedRowIndexes.first {
                self.outlineView?.scrollRowToVisible(selected as Int)
            }
        }
        
    }
    
    func menuItem(for url: URL) -> NSMenuItem {
        
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(goto(_:)), keyEquivalent: "")
            if let rep = NSWorkspace.shared.icon(forFileType: kUTTypeFolder as String).bestRepresentation(for: NSMakeRect(0, 0, 16, 16), context: nil, hints: nil) {
            let image=NSImage()
            image.addRepresentation(rep)
                item.image = image
                }
        return item
    }
    
    func buildNavigationMenu()
    {
        self.backMenu.removeAllItems()
        let index=self.navigation.count - navIndex
        for i in 0..<index-1 {
            let url = navigation[i]
            let item = menuItem(for: url)
            self.backMenu.insertItem(item, at:0)
        }
        self.forwardMenu.removeAllItems()
        for i in index..<self.navigation.endIndex {
            
            let url = navigation[i]
            let item = menuItem(for: url)
            self.forwardMenu.addItem(item)
        }
    }
    
    func restoreSelection(with items: [Node]){
        let rows = items.compactMap( { return self.outlineView?.row(forItem: $0) } )
        
        let rowIndices = IndexSet(rows)
        self.outlineView?.selectRowIndexes(rowIndices, byExtendingSelection: false)
    }
    
    func outlineViewItemDidCollapse(_ notification: Notification) {
        DispatchQueue.main.async {
            self.updateStatusLabel()
        }
    }
    
    func outlineViewItemDidExpand(_ notification: Notification) {
        
        DispatchQueue.global().async {
            
            if let node = notification.userInfo?["NSObject"] as? Node {
                if node.isLoaded == .notLoaded {
                    
                    node.isLoaded = .isLoading
                    DispatchQueue.main.async {
                        self.loadingIndicator!.isHidden = false
                    }
                    if var nodes = self.client?.readDir(node.url.path) {
                        DispatchQueue.main.async {
                            if let sortDescriptor = self.outlineView?.sortDescriptors.first {
                                
                                let ascending = sortDescriptor.ascending
                                
                                if let key = sortDescriptor.key {
                                    sorted(&nodes, ascending: ascending, key: key)
                                }
                            }
                            node.isLoaded = .isLoaded
                            
                            node.contents?.append(contentsOf: nodes)
                            self.outlineView?.insertItems(at: IndexSet(integersIn: 0..<nodes.count), inParent: node, withAnimation: .slideDown)
                            self.loadingIndicator!.isHidden = true
                            self.updateStatusLabel()
                        }
                    }
            
            } else {
                DispatchQueue.main.async {
                    self.updateStatusLabel()
                }
            }
        }
        }
    }
    
    
    
    @IBAction func copy(_ sender:Any?)
    {
        var items : [NSPasteboardWriting] = []
        if let selected = self.outlineView?.selectedRowIndexes {
            for index in selected {
                if let item = self.outlineView?.item(atRow: index), let pasteboardItem = self.outlineView(self.outlineView!, pasteboardWriterForItem: item){
                    items.append(pasteboardItem)
                
                }
            }
        }
        NSPasteboard.general.clearContents()
        let retValue = NSPasteboard.general.writeObjects(items)
            print("\(retValue)")
    }
    
    @objc func paste(_ sender:Any?)
    {
        let data =  NSPasteboard.general.data(forType: .fileURL)
        
        let url = URL(string:String(data: data!, encoding: .utf8)!)!
        let dest=self.url!.appendingPathComponent(url.lastPathComponent)
        copyData(url, destination: dest)
    }
    
    func addNavigationItem()
    {
        let item = NSMenuItem(title: self.url!.lastPathComponent, action: #selector(goto(_:)), keyEquivalent: "")
        if let rep = NSWorkspace.shared.icon(forFileType: kUTTypeFolder as String).bestRepresentation(for: NSMakeRect(0, 0, 16, 16), context: nil, hints: nil) {
        let image=NSImage()
        image.addRepresentation(rep)
            item.image = image
            }
        self.backMenu.insertItem(item, at:0)
    }
    
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers?.first == " " {
            if QLPreviewPanel.shared().isVisible {
                QLPreviewPanel.shared().close()
            } else {
                preview(nil)
            }
        }
 //       super.keyDown(with: event)
    }
    
    func setupToolbarItems()
    {
    }
    
    
    func enableToolbarItems()
    {
        if let items = self.view.window?.toolbar?.items {
            for item in items {
                if item.itemIdentifier.rawValue != "download" {
                    item.isEnabled = true
                }
                if item.itemIdentifier.rawValue == "navigation" {
                    let nav = item.view as! NSSegmentedControl
                    
                    nav.setEnabled(navigation.count - navIndex - 1 > 0, forSegment: 0)
                    nav.setEnabled(navIndex > 0, forSegment: 1)
                    nav.setMenu(self.backMenu, forSegment: 0)
                    nav.setMenu(self.forwardMenu, forSegment: 1)
                    }
                
            if  item.itemIdentifier.rawValue ==  "search" {
                if #available(macOS 11.0, *) {
                    (item as! NSSearchToolbarItem).searchField.delegate = self
                }
            }
            }
        }
        
    }
    
    
    func saveSelecton() -> [Node]
    {
        let rows = self.outlineView?.selectedRowIndexes ?? IndexSet()
        let items = rows.compactMap( { return self.outlineView?.item(atRow: $0) as? Node})
        return items
    }
    
    @objc func handleDoubleClick(_ sender: Any?){
        if let row = self.outlineView?.clickedRow, let item = self.outlineView?.item(atRow: row), let isFolder = (item as? Node)?.isFolder, isFolder {
            if let url = (item as? Node)?.url {
                self.url = url
                navigation.removeLast(navIndex)
                navigation.append(url)
                navIndex = 0
                buildNavigationMenu()
                
                self.updateSidebar()
            }
            reload(nil)
            enableToolbarItems()
        }
    }
    
    func goTo(_ url : URL){
        
            self.url = url
            navigation.removeLast(navIndex)
            navigation.append(self.url!)
            navIndex=0
            reload(nil)
            
            buildNavigationMenu()
            enableToolbarItems()
            updateSidebar()
    }
    
    @IBAction func goUp(_ sender:Any?){
        goTo(self.url!.deletingLastPathComponent())
    }
    /*
    func enumerateFiles(at directory: URL) -> [Node]
    {
        var contents : [Node] = []
        let attributes : [URLResourceKey] = [.creationDateKey, .effectiveIconKey, .contentModificationDateKey, .fileSizeKey, .isDirectoryKey, .localizedNameKey]
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: attributes, options: [.skipsHiddenFiles], errorHandler: nil) {
            
            var stack : [Node] = []
            
            while let url = enumerator.nextObject() as? URL {
                do {
                    let properties = try  (url as NSURL).resourceValues(forKeys: attributes)
                    
                    let node = Node(fileURL: url, name: properties[.localizedNameKey] as? String ?? "", created: properties[.creationDateKey] as? Date ?? Date.distantPast, modified: properties[.contentModificationDateKey] as? Date ?? Date.distantPast, icon: properties[.effectiveIconKey] as? NSImage ?? NSImage(), size: (properties[.fileSizeKey] as? NSNumber)?.int64Value ?? 0, isFolder: (properties[.isDirectoryKey] as? NSNumber)?.boolValue ?? false)
                    let level = enumerator.level - 1
                    while stack.count > 0 && level < stack.count {
                        _ = stack.popLast()
                    }
                
                    if let dir = stack.last {
                        dir.contents?.append(node)
                    } else {
                        contents.append(node)
                    }
                    
                    // push directory onto stack
                    if node.isFolder {
                        stack.append(node)
                    }
                } catch {
                    print("\(error)")
                }
            }
        }
        return contents
    }*/
    
    @IBAction func handleNavigation(_ sender: Any?){
        let selected = (sender as? NSSegmentedControl)!.selectedSegment
        if selected == 0 {
            if navIndex < navigation.count {
                navIndex += 1
                
            }
            self.url = navigation[navigation.endIndex - navIndex - 1]
        } else {
            
                if navIndex > 0 {
                    navIndex -= 1
                    
                }
                self.url = navigation[navigation.endIndex - navIndex - 1]
        }
        
        reload(nil)
        buildNavigationMenu()
        enableToolbarItems()
    }
    

    @IBOutlet var outlineView : NSOutlineView?
    @IBOutlet var label : NSTextField?
    @IBOutlet var loadingIndicator : NSProgressIndicator?

    var contents : [Node]?
    var url : URL?   {
        didSet  {
            DispatchQueue.main.async {
                if let title = self.url?.lastPathComponent {
                    self.view.window?.title  = title
                }
            }
        }
    }
    var downloadQueue : DownloadQueue = DownloadQueue()
    
    func loadContents()
    {
        
        self.loadingIndicator?.isHidden = false
        self.label?.stringValue = ""
        DispatchQueue.global().async {
            let nodes = self.client?.readDir(self.url!.path)
        
            self.contents = nodes
            DispatchQueue.main.async {
                self.loadingIndicator?.isHidden = true
                self.outlineView?.reloadData()
            
                self.updateStatusLabel()
            }
        }
    }
    
    func filenameForOutput(_ dest : URL, filename : String) -> String? {
        var n = 1
        let name = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: filename).pathExtension
        var actualName = filename
        repeat {
            
            let destURL = dest.appendingPathComponent(actualName)
            if !FileManager.default.fileExists(atPath: destURL.path) {
                return actualName
            }
            actualName = "\(name) \(n).\(ext)"
            n += 1
                
        } while n < 1000
    
        return nil
    }
    
    func connect(to server: String, user: String, passphrase: String, method: Bool)
    {
        let client =  method ? SSHClient(server: server, user: user, passphrase: passphrase)  :  SSHClient(server: server, user: user, password: passphrase)
        self.client = client
        if !client.connect() {
            let alert = NSAlert()
            alert.messageText = "Invalid credentials or network error."
            
            alert.addButton(withTitle: NSLocalizedString("OK_TEXT", comment: ""))
            alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
        } else {
        
        
        self.url = URL(string: ".")
        self.navIndex = 0
        self.navigation.removeAll()
        self.navigation.append(self.url!)
        
        NotificationCenter.default.post(name: .connected, object: nil)
        
        loadContents()
            
        }
        
    }
    
    @objc func goto(_ sender: Any?){
        if let menuItem = sender as? NSMenuItem {
        var index = self.backMenu.index(of: menuItem)
            if index != -1 {
            navIndex += index + 1
            
            self.url = navigation[navigation.endIndex - navIndex - 1]
        }
        else {
            index = self.forwardMenu.index(of: menuItem)
            navIndex -= index + 1
            
            self.url = navigation[navigation.endIndex - navIndex - 1]
        }
            
            buildNavigationMenu()
            reload(nil)
            enableToolbarItems()
        }
    }
    
    func buildCustomizeMenu(_ items : [String]) {
        let menu = NSMenu()
        
        for i in 0..<items.count {
            let obj = items[i]
            let item = NSMenuItem(title: obj, action: #selector(customizeColumns(_:)), keyEquivalent: "")
            if self.columnMask & (1 << i) != 0 {
                item.state = .on
            } else {
                item.state = .off
            }
            menu.addItem(item)
        }
        self.outlineView?.headerView?.menu = menu
    }
    
    @IBAction func showConnectSheet(_ sender: Any?)
    {
        self.performSegue(withIdentifier: "connectSheet", sender: nil)
    }
    
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        
        if let controller = segue.destinationController as? ConnectViewController {
            controller.completionBlock = { [weak self] (method, server, user, passphrase) in
                
                DispatchQueue.main.async {
                    
                    self?.connect(to: server, user: user, passphrase: passphrase, method: method)
                }
            }
        } else if let controller = segue.destinationController as? GoToFileViewController {
            
                controller.previousSearches = self.previousSearches
            controller.completionBlock = { [weak self] (path) in
                
                DispatchQueue.main.async {
                    if let index = self?.previousSearches.firstIndex(of: path){
                        self?.previousSearches.remove(at: index)
                    }
                    self?.previousSearches.append(path)
                    self?.goTo(URL(string:path)!)
                }

            }
        }
    }
    
    @IBAction func showGoToWindow(_ sender:Any?){
        self.performSegue(withIdentifier: "gotoWindow", sender: nil)
    }
    
    @IBAction func deleteItem(_ sender: Any?){
        // todo...
        let alert = NSAlert()
        
        let rows = outlineView?.selectedRowIndexes ?? IndexSet()
        let items = rows.compactMap { return (outlineView?.item(atRow: $0) as? Node) }
        
        let str = items.count > 1 ? "\(items.count) items" : "\"\(items.first!.name)\""
        alert.messageText = String(format: NSLocalizedString("CONFIRM_DELETE_MESSAGE", comment: ""), str) 
        alert.addButton(withTitle: NSLocalizedString("CANCEL_TEXT", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("DELETE_TEXT", comment: ""))
        
        alert.beginSheetModal(for: self.view.window!) { (response) in
            if response == .alertSecondButtonReturn {
                self.outlineView?.beginUpdates()
                items.forEach {
                    if $0.isFolder {
                        self.client?.removeFolder($0.url.path)
                    } else {
                        self.client?.unlink($0.url.path)
                    }
                    
                    let parent = self.outlineView?.parent(forItem:$0) as? Node
                    if let index = self.outlineView?.childIndex(forItem: $0), index != 1 {
                        self.outlineView?.removeItems(at: IndexSet(integer: index), inParent: parent, withAnimation: .slideUp)
                        if parent == nil {
                            self.contents?.remove(at: index)
                        } else {
                            parent?.contents?.remove(at: index)
                        
                        }
                        
                    }
                }
                self.outlineView?.endUpdates()
            }
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        enableToolbarItems()
        
    }
    
    @objc func customizeColumns(_ sender: Any?)
    {
        if let menuItem = sender as? NSMenuItem, let index = self.outlineView?.headerView?.menu?.index(of:menuItem){
            let items = [ViewCellID.SizeCellID,ViewCellID.PermissionsCellID,ViewCellID.ModifedCellID]
            let item = items[index]
            let mask=(1<<index)
            if let index=self.outlineView?.column(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: item)){
                let isHidden = self.columnMask & mask !=  0
            self.outlineView?.tableColumns[index].isHidden = isHidden
                menuItem.state = isHidden ? .off : .on
                self.columnMask ^= mask
                UserDefaults.standard.set(self.columnMask, forKey: "columns")
            }
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        
        self.view.window?.delegate = self
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.columnMask =
        UserDefaults.standard.integer(forKey: "columns")
        self.outlineView?.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        // Do any additional setup after loading the view.
        
        self.view.window?.toolbar?.validateVisibleItems()
        
        setupToolbarItems()
        
        self.loadingIndicator?.isHidden = true
        self.loadingIndicator?.startAnimation(nil)
        
        buildCustomizeMenu(["Size","Permissions","Modified"])
        let items = [ViewCellID.SizeCellID,ViewCellID.PermissionsCellID,ViewCellID.ModifedCellID]
        for i in 0 ..<  items.count {
            let item = items[i]
            let mask = (1 << i)
                if let index=self.outlineView?.column(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: item)){
                    let isHidden = self.columnMask & mask !=  0
                self.outlineView?.tableColumns[index].isHidden = !isHidden
            }
        }
        
        self.outlineView?.doubleAction = #selector(handleDoubleClick(_:))
        self.outlineView?.tableColumns[0].sortDescriptorPrototype = NSSortDescriptor(key: SortDescriptor.NameID, ascending: true)
        self.outlineView?.tableColumns[1].sortDescriptorPrototype = NSSortDescriptor(key: SortDescriptor.ModifedID, ascending: true)
        self.outlineView?.tableColumns[3].sortDescriptorPrototype = NSSortDescriptor(key: SortDescriptor.SizeID, ascending: true)
        self.outlineView?.registerForDraggedTypes([NSPasteboard.PasteboardType(rawValue: (kUTTypeItem as String)), .rowDragType])
        self.outlineView?.allowsMultipleSelection = true
        
    
        
        let menu = NSMenu()
        menu.delegate = self
        outlineView?.menu = menu
        outlineView?.setDraggingSourceOperationMask(.copy, forLocal: false)
        outlineView?.registerForDraggedTypes([.fileURL])
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleCancelDownload(_:)), name: .cancelDownload, object: nil)
    }
    
    @objc func download(_ sender : Any?){
        if let row = outlineView?.clickedRow, let node = outlineView?.item(atRow: row) as? Node, let downloadsURL = try? FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true), let filename=filenameForOutput(downloadsURL, filename: node.url.lastPathComponent){
            let url = downloadsURL.appendingPathComponent(filename)
            let item = DownloadItem(name: node.name, icon: node.icon, size: Int(node.size), downloaded: 0, type: .download)
            downloadQueue.queue.append(item)
            item.identifier = client!.download(node.url.path, progress: { (progress) in
                let info = ["item":item]
                item.downloaded = progress
                NotificationCenter.default.post(name: .progressUpdated, object: item, userInfo: info)
            }, completion: {(data, error) in
                guard error == nil else {
                    return
                }
                do {
                    try data?.write(to: url as URL)
                    self.downloadQueue.queue.removeAll {
                        return item.name == $0.name
                    }
                    
                    let info = ["operation":item]
                    NotificationCenter.default.post(name: .finishedOperation, object: item, userInfo:info)
                } catch {
                    print("\(error)")
                }
            })
        }
    }

    
    func getNode(for url:URL) -> Node?
    {
        // hack...
        let rootUrl = self.url!
        let pathComponents = url.pathComponents
        let start = rootUrl.pathComponents.count
        
        var dir = contents
        for i in start..<pathComponents.count {
            var found = false
            for node in dir! {
                if node.name == pathComponents[i] {
                    if i == pathComponents.count-1 {
                        return node
                    } else {
                        dir = node.contents
                        found = true
                        continue
                    }
                }
            }
            if !found {
                break
            }
        }
        return nil
        
    }
    
    func copyData(_  url: URL, destination dest: URL, completion: (()->Void)? = nil) {
        do {
            let data = try Data(contentsOf: url)
            let icon = NSWorkspace.shared.icon(forFileType: url.pathExtension)
            let item = DownloadItem(name: url.lastPathComponent, icon: icon, size: data.count, downloaded: 0, type: .upload)
            item.identifier = client!.uploadFile(data, path: dest.path, progress: { (progress) in
                item.downloaded = progress
                NotificationCenter.default.post(name: .progressUpdated, object: item)
            }, completion: {
                
                self.downloadQueue.queue.removeAll(where: {
                    return $0.identifier == item.identifier
                })
                let info = ["operation":item]
                NotificationCenter.default.post(name: .finishedOperation, object: item, userInfo:info)
               completion?()
                
            })
            
            downloadQueue.queue.append(item)
        } catch {
            
        }
    }
    
    func download(_ node : Node, destination dest: URL, completion: (()->Void)? = nil){
        let item = DownloadItem(name: node.name, icon: node.icon, size: Int(node.size), downloaded: 0, type: .download)
        downloadQueue.queue.append(item)
        item.identifier = client!.download(url!.path, progress: { (progress) in
            let info = ["item":item]
            item.downloaded = progress
            NotificationCenter.default.post(name: .progressUpdated, object: item, userInfo: info)
        }, completion: {(data, error) in
            guard error == nil else {
                return
            }
            do {
                try data?.write(to: dest as URL)
                self.downloadQueue.queue.removeAll {
                    return item.name == $0.name
                }
                
                let info = ["operation":item]
                NotificationCenter.default.post(name: .finishedOperation, object: item, userInfo:info)
                
                completion?()
            } catch {
                print("\(error)")
            }
        })
    }
    
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return true
    }
    
    @IBAction func preview(_ sender: Any?)
    {
        
        if let node = self.outlineView?.item(atRow: self.outlineView!.selectedRow) as? Node, !node.isFolder {
            let url = node.url
            self.previewURL = nil
            QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
            QLPreviewPanel.shared().dataSource = self
            QLPreviewPanel.shared().delegate = self
            
            let tmp = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let cacheDir = tmp?.appendingPathComponent(Bundle.main.bundleIdentifier!)
            if !FileManager.default.fileExists(atPath: cacheDir!.path){
                try? FileManager.default.createDirectory(at: cacheDir!, withIntermediateDirectories: true, attributes: nil)
            }
            
            let dest=cacheDir!.appendingPathComponent(url.lastPathComponent)
            let item = DownloadItem(name: node.name, icon: node.icon, size: Int(node.size), downloaded: 0, type: .download)
            downloadQueue.queue.append(item)
            item.identifier = client!.download(node.url.path, progress: { (progress) in
                let info = ["item":item]
                item.downloaded = progress
                NotificationCenter.default.post(name: .progressUpdated, object: item, userInfo: info)
            }, completion: {(data, error) in
                guard error == nil else {
                    return
                }
                do {
                    try data?.write(to: dest as URL)
                    self.downloadQueue.queue.removeAll {
                        return item.name == $0.name
                    }
                    
                    let info = ["operation":item]
                    NotificationCenter.default.post(name: .finishedOperation, object: item, userInfo:info)
                    
                        DispatchQueue.main.async {
                            self.previewURL = dest
                            QLPreviewPanel.shared().reloadData()
                        
                    }
                } catch {
                    print("\(error)")
                }
            })
            previewItem = item
            
        }
    }
    
    override var acceptsFirstResponder: Bool {
        return true
        
    }
    
    func updateSidebar() {
        if let sidebar = self.view.window?.windowController?.contentViewController?.children[0] as? SidebarViewController
        {
        sidebar.selectUrl(self.url!)
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        
        let source = URL(string: info.draggingPasteboard.string(forType: .fileURL) ?? "")
        var dest = (item as? Node)?.url ?? url
        
        dest?.appendPathComponent(source?.lastPathComponent ?? "")
        if let _ = info.draggingSource as? NSOutlineView {
            let isCopy = info.draggingSourceOperationMask == .copy
            
            
            var movedNodes : [Node] = []
            info.enumerateDraggingItems(options: .concurrent, for: outlineView, classes: [NSPasteboardItem.self], searchOptions: [:]) { (draggingItem, idx, stop) in
                if let draggingItem = draggingItem.item as? NSPasteboardItem, let row = draggingItem.propertyList(forType: .rowDragType) as? Int, let node = outlineView.item(atRow: row) as? Node {
                    let parent = outlineView.parent(forItem: node) as? Node
                    if parent != item as? Node {
                        movedNodes.append(node)
                    }
                }
            }
            
            outlineView.beginUpdates()
            
            let destUrl = (item as? Node)?.url ?? url!
            
            let destNode = item as? Node
            movedNodes.forEach( {
                let parent = outlineView.parent(forItem: $0) as? Node
                let index = outlineView.childIndex(forItem: $0)
                let node = $0
                
                if !isCopy {
                    if let parent = parent {
                        parent.contents?.removeAll(where: { return $0.name == node.name })
                    } else {
                        contents?.removeAll(where: { return $0.name == node.name })
                    }
                    outlineView.removeItems(at: IndexSet.init(integer: index), inParent: parent, withAnimation: .slideUp)
                }
               
                var newUrl = destUrl

                let contents = destNode?.contents ?? self.contents
                let filename = getFilename(node.url.lastPathComponent, in: contents!)
        
                newUrl.appendPathComponent(filename!)
            
                if isCopy {
                    client?.copy(node.url.path, destination: newUrl.path)
                } else {
                    client?.moveFile(node.url.path, toPath: newUrl.path)
                }
                node.url = newUrl
            })
            
            let start : Int
            if let destNode = item as? Node {
                start = destNode.contents?.count ?? 0
                if destNode.isLoaded == .isLoaded {
                    destNode.contents?.append(contentsOf: movedNodes)}
                
            } else {
                start = contents?.count ?? 0
                contents?.append(contentsOf: movedNodes)
            }
            let end = start + movedNodes.count
            if destNode?.isLoaded == .isLoaded {
            outlineView.insertItems(at: IndexSet.init(integersIn: start..<end), inParent: item, withAnimation: .slideDown)
            }
            
            outlineView.endUpdates()
            return true
        } else {
            if let dest = dest {
                    // todo: move file
                do {
                    let url = NSURL(from: info.draggingPasteboard) as URL?
                    let data = try Data(contentsOf: url!)
                    let icon = NSWorkspace.shared.icon(forFileType: url!.pathExtension)
                    let item = DownloadItem(name: url!.lastPathComponent, icon: icon, size: data.count, downloaded: 0, type: .upload)
                    item.identifier = client!.uploadFile(data, path: dest.path, progress: { (progress) in
                        item.downloaded = progress
                        NotificationCenter.default.post(name: .finishedOperation, object: item)
                    }, completion:{
                        
                        self.downloadQueue.queue.removeAll(where: {
                            return $0.identifier == item.identifier
                        })
                        let info = ["operation":item]
                        NotificationCenter.default.post(name: .finishedOperation, object: item, userInfo:info)
                    })
                    downloadQueue.queue.append(item)
                } catch {
                    
                }
            }
            return true
        }
}
    func getFilename(_ filename: String, in folder: [Node]) -> String? {
        
        var actualName = filename
        var n = 1
        let name = URL(string: filename)!.deletingPathExtension().lastPathComponent
        let ext = URL(string: filename)!.pathExtension
        repeat {
            if !folder.contains(where: { $0.name == actualName }) {
                return actualName
            }
            actualName = "\(name) \(n).\(ext)"
            n += 1
                
        } while n < 1000
        return nil
    }
    
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        let file = item as! Node
        let fileExtension = file.url.pathExtension as CFString
        let identifier = file.isFolder ?  kUTTypeFolder as String :  fileExtension as String == "" ? "public.data" : UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension, nil)!.takeRetainedValue() as String
        let provider = FilePromiseProvider(fileType: identifier, delegate: self)
        provider.userInfo = ["url" : file.url as NSURL, "row" : outlineView.row(forItem: item)]
        return provider
    }
    
    @objc func handleCancelDownload(_ notification: NSNotification) {
        if let item = notification.object as? DownloadItem {
            client?.stopTask(withIdentifer: item.identifier)
        }
    }
    
    @objc func copyURL(_ sender : Any?){
        var items : [NSPasteboardWriting] = []
        let urls = self.outlineView!.selectedRowIndexes.compactMap {
            (index) -> String? in
            let node = self.outlineView?.item(atRow: index) as? Node
            return node?.url.path
        }
        items.append(urls.joined(separator: " ") as NSPasteboardWriting)
        NSPasteboard.general.clearContents()
        let _ = NSPasteboard.general.writeObjects(items)
        
    }
    
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        
        guard client != nil else {
            return []
        }
            var parentItem : Node? = nil
        
        var isSelf = false
        info.enumerateDraggingItems(options: .concurrent, for: outlineView, classes: [NSPasteboardItem.self], searchOptions: [:]) { (draggingItem, row, stop) in
            if let draggingItem = draggingItem.item as? NSPasteboardItem, let row = draggingItem.propertyList(forType: .rowDragType) as? Int, let node = outlineView.item(atRow: row) as? Node {
                if (item as? Node) == node {
                    isSelf = true
                }
            }
            
        }
        if isSelf {
            return []
        }
            if let node = item as? Node {
                
                if !node.isFolder {
                    parentItem = outlineView.parent(forItem: item) as? Node
                } else {
                    parentItem = item as? Node
                }
            }
            
            outlineView.setDropItem(parentItem, dropChildIndex: -1)
        
        
        if let _ = info.draggingSource as? NSOutlineView {
            return info.draggingSourceOperationMask == .copy ? [.copy] : [.move]
        } else {
            return [.copy]
        }
        
        
    }
    
    

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
            
        }
    }
    
    
}

extension BrowserViewController : NSOutlineViewDelegate
{
    
    func outlineView(_ outlineView: NSOutlineView,
                      viewFor tableColumn: NSTableColumn?,
                         item: Any) -> NSView?
    {
        var image: NSImage?
        var text: String = ""
        var cellIdentifier: String = ""

        let node = item as! Node
        if tableColumn?.identifier.rawValue == ViewCellID.NameCellID {
            cellIdentifier = ViewCellID.NameCellID
            text = node.name
            image = node.icon
        } else if tableColumn?.identifier.rawValue == ViewCellID.ModifedCellID{
            cellIdentifier = ViewCellID.ModifedCellID
            text = DateFormatter.localizedString(from: node.modified, dateStyle: .medium, timeStyle: .short)
        } else if tableColumn?.identifier.rawValue == ViewCellID.SizeCellID {
            cellIdentifier = ViewCellID.SizeCellID
            if node.isFolder {
                text = "-"
            } else {
                text = ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file)
            }
        }  else if tableColumn?.identifier.rawValue == ViewCellID.PermissionsCellID {
            cellIdentifier = ViewCellID.PermissionsCellID
            text = "\(permissionsString(node.permissions)) (\(String( node.permissions & 0x1ff, radix: 8)))"
        }
        if let cell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: cellIdentifier), owner: nil) as? NSTableCellView {
            cell.imageView?.image = image
            cell.textField?.stringValue = text
            cell.identifier = NSUserInterfaceItemIdentifier(rawValue: cellIdentifier)
            return cell
        }
        return nil
    }
    
    @IBAction func duplicate(_ sender:Any?){
        let node = self.outlineView?.item(atRow: self.outlineView!.selectedRow) as? Node
        let contents = node?.contents ?? self.contents!
        let filename = node?.url.lastPathComponent
        let dest = getFilename(filename!, in: contents)
        
        var destURL = node!.url.deletingLastPathComponent()
            
        destURL.appendPathComponent(dest!)
        client?.copy(node!.url.path, destination: destURL.path)
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification)
    {
        updateStatusLabel()
    }
    
    func updateStatusLabel(){
        
        self.label?.stringValue = self.outlineView!.selectedRowIndexes.count > 0 ?  "\(self.outlineView!.selectedRowIndexes.count) of \(self.contents!.count) selected" : "\(self.outlineView!.numberOfRows) items"
    }
    
    @IBAction func reload(_ sender : Any?){
        self.contents = []
        self.isFiltered = false
        
        self.outlineView?.reloadData()
        loadContents()
    }
    
}

extension BrowserViewController : NSOutlineViewDataSource
{
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        return (item as? Node)?.contents!.count ?? (isFiltered ? results.count : (contents?.count ?? 0) )
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return (item as! Node).isFolder
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any
    {
        return (item as? Node)?.contents![index] ?? (self.isFiltered ? results[index] : contents![index])
    }
}

extension BrowserViewController : NSMenuDelegate
{
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        var rows = self.outlineView?.selectedRowIndexes ?? IndexSet()
        if let clicked = self.outlineView?.clickedRow, clicked != -1 {
            rows.insert(clicked)
        }
        menu.addItem(NSMenuItem(title: "Copy URL", action: #selector(copyURL(_:)), keyEquivalent: ""))
        if rows.count > 0 {
            
                let hasFolder = rows.contains(where: {
                    let node = self.outlineView?.item(atRow: $0) as? Node
                    return node?.isFolder ?? false
                })
            
                if !hasFolder {
                    let copyMenuItem = NSMenuItem(title: "Copy", action: #selector(download(_:)), keyEquivalent: "")
                    
                    menu.addItem(copyMenuItem)
                    let duplicateMenuItem = NSMenuItem(title: "Duplicate", action: #selector(duplicate(_:)), keyEquivalent: "")
                    
                    menu.addItem(duplicateMenuItem)
                    menu.addItem(NSMenuItem.separator())
                    
                }
                menu.addItem(NSMenuItem(title: "Delete", action: #selector(deleteItem(_:)), keyEquivalent: ""))
                
                
                if !hasFolder {
                    let previewMenuItem = NSMenuItem(title: "Preview", action:#selector(preview), keyEquivalent: "")
                    menu.addItem(NSMenuItem.separator())
                    menu.addItem(previewMenuItem)
                menu.addItem(NSMenuItem(title: "Download", action: #selector(download(_:)), keyEquivalent: ""))
            
            }
        }
    }
}

extension BrowserViewController : NSFilePromiseProviderDelegate
{
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        if let userInfo = filePromiseProvider.userInfo as? [String : Any] {
            let url = userInfo["url"] as! NSURL
            return url.lastPathComponent ?? ""
        }
        
        return ""
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
            
            if let userInfo = filePromiseProvider.userInfo as? [String : Any] {
                let remoteUrl = userInfo["url"] as! NSURL
                let row = userInfo["row"] as! Int
                let file = outlineView?.item(atRow: row) as! Node
                let item = DownloadItem(name: file.name, icon: file.icon, size: Int(file.size), downloaded: 0, type: .download)
                downloadQueue.queue.append(item)
                item.identifier = client!.download(remoteUrl.path!, progress: { (progress) in
                    let info = ["item":item]
                    item.downloaded = progress
                    NotificationCenter.default.post(name: .progressUpdated, object: item, userInfo: info)
                }, completion: {(data, error) in
                    guard error == nil else {
                        completionHandler(error)
                        return
                    }
                    do {
                        try data?.write(to: url as URL)
                        self.downloadQueue.queue.removeAll {
                            return item.name == $0.name
                        }
                        
                        let info = ["operation":item]
                        NotificationCenter.default.post(name:.finishedOperation, object: item, userInfo:info)
                        completionHandler(nil)
                    } catch {
                        
                        completionHandler(error)
                    }
                })
            }
    }
    
    
}

extension BrowserViewController : NSUserInterfaceValidations
{
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool
    {
        if client == nil && item.tag == 1 {
            return false
        }
        
        if item.action == #selector(copy(_:)) {
            return outlineView?.selectedRowIndexes.count ?? 0 > 0
        } else if item.action == #selector(goUp(_:)) {
            return self.url?.path != "/"
        } else if item.action == #selector(paste(_:)) {
            return NSPasteboard.general.canReadItem(withDataConformingToTypes: [kUTTypeFileURL as String])
        }
        return true
    }
    
}

extension BrowserViewController :  NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        let searchField = obj.userInfo?["NSFieldEditor"] as! NSTextView
        self.filter = searchField.string
        self.results = self.contents!.filter { return $0.name.contains(self.filter!) }
            
        self.outlineView?.reloadData()
        print("\(results.count)")
    }
    
    func searchFieldDidStartSearching(_ sender: NSSearchField) {
        self.isFiltered = true
        self.outlineView?.reloadData()
    }
    
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        self.isFiltered = false
        self.outlineView?.reloadData()
    }
    

}

extension BrowserViewController : QLPreviewPanelDelegate, QLPreviewPanelDataSource
{
    
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        if let previewItem = previewItem {
            // cancel
            NotificationCenter.default.post(name: .cancelDownload, object: previewItem)
            downloadQueue.queue.removeAll { $0.identifier == previewItem.identifier }
        }
    }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return previewURL! as QLPreviewItem
    }
    
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return previewURL != nil ? 1 : 0
    }
    
}



extension BrowserViewController : NSWindowDelegate {
func windowShouldClose(_ window: NSWindow) -> Bool {
    if downloadQueue.queue.count > 0 && !canQuit {
    DispatchQueue.main.async {
        let alert = NSAlert()
        alert.messageText = "You have an active transfer. Do you still want to close this window?"
        alert.addButton(withTitle: "Cancel")
        
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: self.view.window!) { response in
            if response == .alertSecondButtonReturn {
                self.canQuit = true
                window.close()
            }
        }
    }
    return false
} else {
    return true}
}
    
}
