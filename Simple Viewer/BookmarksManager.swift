//
//  BookmarksManager.swift
//  Simple Viewer
//
//

import Foundation

class BookmarksManager : NSObject {
    static var shared : BookmarksManager = {
        return BookmarksManager()
    }()
    var bookmarks : [URL] = []


    func urlForFile() -> URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let dir = url!.appendingPathComponent(Bundle.main.bundleIdentifier!)
        if !FileManager.default.fileExists(atPath: dir.path) {
            let _
             = try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [:])
        }
        let fileUrl = dir.appendingPathComponent("bookmarks.plist")
        return fileUrl
    }
    
    func save(){
        let fileUrl = urlForFile()
        
        let data = ["bookmarks" : bookmarks.compactMap( {return $0.path })]
        try? (data as NSDictionary).write(to: fileUrl)
    }
    
    func load(){
        let fileUrl = urlForFile()
        if let bookmarks = NSDictionary(contentsOf: fileUrl) as? [String : Any]{
            if let bookmarkArray = bookmarks["bookmarks"] as? [String] {
                self.bookmarks = bookmarkArray.compactMap { return URL(string: $0) }
            }
        }
        
    }
}
