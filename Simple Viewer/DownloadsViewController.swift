//
//  DownloadsViewController.swift
//  Simple Viewer
//
//

import Cocoa


protocol DownloadDelegate : class {
    
    func didCancelDownload(for cell: DownloadTableCellView)
}

class DownloadTableCellView : NSTableCellView
{
    @IBOutlet var iconView : NSImageView?
    @IBOutlet var progressIndicator : NSProgressIndicator?
    @IBOutlet var secondaryLabel : NSTextField?
    @IBOutlet var cancelButton : NSButton?
    
    weak var delegate : DownloadDelegate?
    
    @IBAction func cancelDownload(_ sender: Any?)
    {
        delegate?.didCancelDownload(for: self)
    }
}

class DownloadsViewController: NSViewController {

    @IBOutlet var tableView : NSTableView?
    weak var downloadQueue : DownloadQueue?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        self.tableView?.delegate = self
        self.tableView?.dataSource = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: .progressUpdated, object: nil)
        
        
        NotificationCenter.default.addObserver(self, selector: #selector(operationFinished(_:)), name: .finishedOperation, object: nil)
    }
    
    @objc func operationFinished(_ notification: Notification){
        DispatchQueue.main.async {
            self.tableView?.reloadData()
        }
    }
    
    @objc func update(_ notification: Notification)
    {
        
        DispatchQueue.main.async {
            if let info = notification.userInfo as? [String:Any?], let item = info["item"] as? DownloadItem {
                if let row = self.downloadQueue?.queue.firstIndex(where: {return $0.identifier == item.identifier }), let view = self.tableView?.view(atColumn: 0, row: 0, makeIfNecessary: true) as? DownloadTableCellView {
                    
                    let byteFormatter = ByteCountFormatter()
                        view.progressIndicator?.doubleValue = Double(item.downloaded)/Double(item.size)*100.0
                    view.secondaryLabel?.stringValue = "\(byteFormatter.string(fromByteCount: Int64(item.downloaded))) of \((byteFormatter.string(fromByteCount: Int64(item.size))))"
                    }
                }
            }
    }
    
}

extension DownloadsViewController : NSTableViewDataSource
{
    func numberOfRows(in tableView: NSTableView) -> Int {
        return downloadQueue?.queue.count ?? 0
    }
}

extension DownloadsViewController : DownloadDelegate
{
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat
    {
        return 60.0
    }
    func didCancelDownload(for cell: DownloadTableCellView) {
        if let row = tableView?.row(for: cell) {
            let item = downloadQueue?.queue[row]
            NotificationCenter.default.post(name: .cancelDownload, object: item)
            downloadQueue?.queue.remove(at: row)
            DispatchQueue.main.async {
                self.tableView?.reloadData()
            }
        }
        
    }
}

extension DownloadsViewController : NSTableViewDelegate
{
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "download"), owner: nil) as? DownloadTableCellView, let item = downloadQueue?.queue[row] {
            let type = item.type == .download ? "Downloading" : "Uploading"
            view.textField?.stringValue = "\(type) \"\(item.name)\""
            let byteFormatter = ByteCountFormatter()
            view.delegate = self
            if item.size > 0 {
                view.progressIndicator?.doubleValue = Double(item.downloaded)/Double(item.size)*100.0
            }
//            view.progressIndicator?.isIndeterminate = true
            view.iconView?.image = item.icon
            view.secondaryLabel?.stringValue = "\(byteFormatter.string(fromByteCount: Int64(item.downloaded))) of \((byteFormatter.string(fromByteCount: Int64(item.size))))"
            return view
        }
        return nil
    }
}
