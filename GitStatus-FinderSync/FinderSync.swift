//
//  FinderSync.swift
//  GitStatus-FinderSync
//
//  Created by Guillaume Legrain on 10/5/16.
//  Copyright © 2016 Guillaume Legrain. All rights reserved.
//

import Cocoa
import FinderSync
import ObjectiveGit

class FinderSync: FIFinderSync {

    /// list of directory paths to be monitored by the extension.
    var myFolders = ["/"] // "/" will just monitor the whole system
    /// Current repository
    var observedRepo: GTRepository? {
        didSet {
            listStatus()
        }
    }
    /// Dictionary containing the status for all the files in the observedRepo
    var filesStatus: Dictionary<String, GTDeltaType>? = nil

    struct BadgeIdentifiers {
        static let caution = "Caution"
        static let green = "Green"
        static let orange = "Orange"
        static let red = "Red"
        static let plus = "Plus"
        static let transparent = "Transparent"
        static let cleanRepo = "Clean Repo"
        static let modifiedRepo = "Modified Repo"

        static func badgeIdentifier(status: GTDeltaType) -> String {
            switch status {
            case .unmodified: return BadgeIdentifiers.green
            case .added: return BadgeIdentifiers.plus
            case .deleted: return BadgeIdentifiers.red
            case .modified, .renamed, .copied: return  BadgeIdentifiers.orange
            case .ignored: return BadgeIdentifiers.transparent
            case .untracked: return BadgeIdentifiers.red
            case .typeChange: return  BadgeIdentifiers.orange
            case .unreadable: return BadgeIdentifiers.red
            case .conflicted: return BadgeIdentifiers.red
            }

        }
    }

    override init() {
        super.init()

        NSLog("FinderSync() launched from %@", Bundle.main.bundlePath as NSString)

        // Set up the directory we are syncing.
        let directoryURLs = Set(self.myFolders.map { URL(fileURLWithPath: $0) })
        FIFinderSyncController.default().directoryURLs = directoryURLs

        // Set up images for our badge identifiers. For demonstration purposes, this uses off-the-shelf images.
        // Off-the-shelf images names can be found here http://hetima.github.io/fucking_nsimage_syntax/
        let fsController = FIFinderSyncController.default()
        fsController.setBadgeImage(NSImage(named: NSImageNameCaution)!, label: "Caution", forBadgeIdentifier: BadgeIdentifiers.caution)
        fsController.setBadgeImage(NSImage(named: NSImageNameStatusAvailable)!, label: "Green", forBadgeIdentifier: BadgeIdentifiers.green)
        fsController.setBadgeImage(NSImage(named: NSImageNameStatusPartiallyAvailable)!, label: "Orange", forBadgeIdentifier: BadgeIdentifiers.orange)
        fsController.setBadgeImage(NSImage(named: NSImageNameStatusUnavailable)!, label: "Red", forBadgeIdentifier: BadgeIdentifiers.red)
        fsController.setBadgeImage(NSImage(named: NSImageNameAddTemplate)!, label: "Plus", forBadgeIdentifier: BadgeIdentifiers.plus)
        fsController.setBadgeImage(NSImage(named: NSImageNameStatusNone)!, label: "Transparent", forBadgeIdentifier: BadgeIdentifiers.transparent)

        fsController.setBadgeImage(NSImage(named: "git-branch")!, label: "Clean Repo", forBadgeIdentifier: BadgeIdentifiers.cleanRepo)
        fsController.setBadgeImage(NSImage(named: "git-branch-orange")!, label: "Modified Repo", forBadgeIdentifier: BadgeIdentifiers.modifiedRepo)
    }

    /// Get status for files in the currently observed directory
    private func listStatus() {
        guard let repo = observedRepo else {
            // The currently observed directory is not a git repository
            filesStatus = nil
            return
        }

        filesStatus = [:]

        // Set options to enumerate all files
        let options: [String: Any] = [
            GTRepositoryStatusOptionsShowKey: NSNumber(value: GTRepositoryStatusOptionsShowIndexAndWorkingDirectory.rawValue),
            GTRepositoryStatusOptionsFlagsKey: NSNumber(value: (
                GTRepositoryStatusFlagsIncludeUnmodified.rawValue |
                GTRepositoryStatusFlagsIncludeUntracked.rawValue |
                GTRepositoryStatusFlagsIncludeIgnored.rawValue |
                GTRepositoryStatusFlagsRecurseUntrackedDirectories.rawValue |
                GTRepositoryStatusFlagsRecurseIgnoredDirectories.rawValue |
                GTRepositoryStatusFlagsRenamesHeadToIndex.rawValue
            ))
        ]

        // Get status for files in observedRepo
        // NOTE: Slow for large repos.
        try? repo.enumerateFileStatus(options: options, usingBlock: { (headToIndex: GTStatusDelta?, indexToWorkingDirectory: GTStatusDelta?, stop) in
            // print("headToIndex FILE: \(headToIndex?.newFile?.path) is \(headToIndex?.status.rawValue)")
            // print("indexToWDir FILE: \(indexToWorkingDirectory?.newFile?.path) is \(indexToWorkingDirectory?.status.rawValue)")
            // Add each file to the filesStatus dictionary
            // Set the status to the most critical between headToIndex and indexToWorkingDirectory). To be discussed.
            var status: GTDeltaType?
            var fileName: String?
            if let statusDelta = headToIndex {
                fileName = statusDelta.newFile?.path
                status = statusDelta.status
            }
            if let statusDelta = indexToWorkingDirectory {
                if fileName == nil {
                    fileName = statusDelta.newFile!.path
                }
                if (status?.rawValue ?? 0) <= statusDelta.status.rawValue {
                    status = statusDelta.status
                }
            }
            self.filesStatus![fileName!] = status
        })

    }

    // MARK: - Primary Finder Sync protocol methods

    override func beginObservingDirectory(at url: URL) {
        // The user is now seeing the container's contents.
        // If they see it in more than one view at a time, we're only told once.
        NSLog("beginObservingDirectoryAtURL: %@", url.path as NSString)

        // Do not initialize a new repository if we are in a sub-directory of the repository
        // The previous value of observedRepo is kept
        if observedRepo != nil && url.path.hasPrefix(observedRepo!.fileURL.path) {
            return
        }

        // We are now either entering a repository directory or a non-git directory
        // Reset observedRepo
        observedRepo = nil

        do {
            // if let repoURL = repositoryURL(for: url) {
            observedRepo = try GTRepository(url: url, flags: 0, ceilingDirs: nil)
            //}
        } catch let error {
            observedRepo = nil
            print("Failed to get repository information:  \(error)")
            return
        }
    }


    override func endObservingDirectory(at url: URL) {
        // The user is no longer seeing the container's contents.
        // NSLog("endObservingDirectoryAtURL: %@", url.path as NSString)
    }

    override func requestBadgeIdentifier(for url: URL) {
        NSLog("requestBadgeIdentifierForURL: %@", url.path as NSString)

        let isDirectory = url.hasDirectoryPath

        // If we are not inside a git repo, check to see if any folders in the current directory are git repos
        // Set different badge based wether the working directory is clean or pending commits
        if observedRepo == nil && isDirectory {
            // attempt to read if the directory is a repo
            if let repoURL = repositoryURL(for: url), let repo = try? GTRepository(url: repoURL) {
                if repo.isWorkingDirectoryClean {
                    FIFinderSyncController.default().setBadgeIdentifier(BadgeIdentifiers.cleanRepo, for: url)
                } else {
                    FIFinderSyncController.default().setBadgeIdentifier(BadgeIdentifiers.modifiedRepo, for: url)
                }
            }
            return
        }

        // Else, we are in a git repo, show to status of the current file
        if observedRepo != nil && filesStatus != nil {

            guard let fileName = url.relativePath(to: observedRepo!.fileURL) else {
                // unable to get a relative path
                return
            }

            // Check if dictionary contains status info for the request fileName
            if let status = filesStatus![fileName] {
                let badgeID = BadgeIdentifiers.badgeIdentifier(status: status)
                FIFinderSyncController.default().setBadgeIdentifier(badgeID, for: url)
                return
            }

            // If isDirectory, check if content is clean
            if isDirectory {
                // check if the filesStatus dictionary contains any non-unmodified or non-ignored files
                for fileStatus in filesStatus! {
                    if fileStatus.key.hasPrefix(fileName) {
                        if fileStatus.value != .unmodified && fileStatus.value != .ignored {
                            FIFinderSyncController.default().setBadgeIdentifier(BadgeIdentifiers.orange, for: url)
                            return
                        }
                    }
                }
                // Only unmodified or ignored files have been found. The directory is clean.
                // TODO: show ignored folders correctly
                FIFinderSyncController.default().setBadgeIdentifier(BadgeIdentifiers.green, for: url)
                return
            }
        }
        NSLog("FAILED requestBadgeIdentifierForURL: %@", url.path as NSString)

    }

    // MARK: - Menu and toolbar item support

    override var toolbarItemName: String {
        return "GitStatus"
    }

    override var toolbarItemToolTip: String {
        return "GitStatus: Click the toolbar item for a menu."
    }

    override var toolbarItemImage: NSImage {
        return NSImage(named: "git-branch")!
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        // Produce a menu for the extension.
        let menu = NSMenu(title: "")
        menu.addItem(withTitle: "TODO Menu Items", action: #selector(sampleAction(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "TODO Checkout another branch", action: #selector(sampleAction(_:)), keyEquivalent: "")
        return menu
    }

    @IBAction func sampleAction(_ sender: AnyObject?) {
        let target = FIFinderSyncController.default().targetedURL()
        let items = FIFinderSyncController.default().selectedItemURLs()

        let item = sender as! NSMenuItem
        NSLog("sampleAction: menu item: %@, target = %@, items = ", item.title as NSString, target!.path as NSString)
        for obj in items! {
            NSLog("%@", obj.path as NSString)
        }
    }

    /// Returns the repository URL or nil if it can't be made.
    /// If the URL is a file, it should have the extension '.git' - bare repository
    /// If the URL is a folder it should have the name '.git'
    /// If the URL is a folder, then it should contain a subfolder called '.git
    func repositoryURL(for url: URL) -> URL? {
        // https://github.com/Abizern/CommitViewer/blob/master/CommitViewer/AppDelegate.m
        let git = ".git"
        let endPoint = url.lastPathComponent

        if endPoint.lowercased().hasSuffix(git) {
            return url
        }

        if endPoint == git {
            return url
        }

        let possibleGitDir = url.appendingPathComponent(git, isDirectory: true)
        do {
            let isReachable = try possibleGitDir.checkResourceIsReachable()
            if  isReachable {
                return possibleGitDir
            }
        } catch let error {
            print(error)
            return nil
        }

        print("Not a valid path")
        return nil
    }

}

extension URL {

    /// Extract requested url filepath relative to the currently observed repo
    ///
    /// - parameter parentURL: Base URL. Self should be a sub-directory of parentURL
    ///
    /// - returns: Filename relative to the parentURL
    func relativePath(to parentURL: URL) -> String? {
        guard self.path.hasPrefix(parentURL.path) else {
            // self is not a contained in parentURL
            return nil
        }

        let parentURLEndIndex = parentURL.path.endIndex
        let fileName = String(
            self.path.substring(
                from: self.path.index(after: parentURLEndIndex)
            ).characters.dropFirst() // remove leading "/" to make filepath relative
        )
        return fileName
    }

}
