//
//  Notification+Operations.swift
//  Simple Viewer
//
//

import Foundation

extension Notification.Name {
    static let finishedOperation = Notification.Name(rawValue:" finishedOperationName")
    static let progressUpdated  =  Notification.Name(rawValue:"progressUpdatedName")
    static let cancelDownload  =  Notification.Name(rawValue:"cancelDownloadName")
    static let connected =
    NSNotification.Name(rawValue: "connectedName")
}
