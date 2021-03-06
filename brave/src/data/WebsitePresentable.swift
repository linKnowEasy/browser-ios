/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import CoreData
import SwiftyJSON

@objc protocol WebsitePresentable {
    var title: String? { get }
    var url: String? { get }
}

protocol Syncable {
    // Used to enforce CD conformity
    /* @NSManaged */ var syncDisplayUUID: String? { get set }
    /* @NSManaged */ var created: Date? { get set}

    static func entity(context:NSManagedObjectContext) -> NSEntityDescription

    var syncUUID: [Int]? { get }
    
    func asDictionary(deviceId: [Int]?, action: Int?) -> [String: Any]
    
    func update(syncRecord record: SyncRecord)
    
    @discardableResult static func add(rootObject root: SyncRecord?, save: Bool, sendToSync: Bool, context: NSManagedObjectContext) -> Syncable?
}

// ??
extension Syncable where Self: Syncable {
    static func get(syncUUIDs: [[Int]]?, context: NSManagedObjectContext) -> [NSManagedObject]? {
        
        guard let syncUUIDs = syncUUIDs else {
            return nil
        }
        
        // TODO: filter a unique set of syncUUIDs
        
        let searchableUUIDs = syncUUIDs.map { SyncHelpers.syncDisplay(fromUUID: $0) }.flatMap { $0 }
        return get(predicate: NSPredicate(format: "syncDisplayUUID IN %@", searchableUUIDs), context: context)
    }
    
    static func get(predicate: NSPredicate?, context: NSManagedObjectContext) -> [NSManagedObject]? {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>()
        
        fetchRequest.entity = Self.entity(context: context)
        fetchRequest.predicate = predicate
        
        var result: [NSManagedObject]? = nil
        context.performAndWait {
            
        
            do {
                result = try context.fetch(fetchRequest) as? [NSManagedObject]
            } catch {
                let fetchError = error as NSError
                print(fetchError)
            }
        }
        
        return result
    }
}

//extension Syncable where Self: NSManagedObject {
extension Syncable {
    
    // Is conveted to better store in CD
    var syncUUID: [Int]? { 
        get { return SyncHelpers.syncUUID(fromString: syncDisplayUUID) }
        set(value) { syncDisplayUUID = SyncHelpers.syncDisplay(fromUUID: value) }
    }
    
    // Maybe use 'self'?
    static func get<T: NSManagedObject where T: Syncable>(predicate: NSPredicate?, context: NSManagedObjectContext?) -> [T]? {
        guard let context = context else {
            // error
            return nil
        }
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>()
        
        fetchRequest.entity = T.entity(context: context)
        fetchRequest.predicate = predicate
        
        do {
            return try context.fetch(fetchRequest) as? [T]
        } catch {
            let fetchError = error as NSError
            print(fetchError)
        }
        
        return nil
    }
}

extension Syncable /* where Self: NSManagedObject */ {
    func remove(save: Bool) {
        
        // This is r annoying, and can be fixed in Swift 4, but since objects can't be cast to a class & protocol,
        //  but given extension on Syncable, if this passes the object is both Syncable and an NSManagedObject subclass
        guard let s = self as? NSManagedObject, let context = s.managedObjectContext else { return }
        
        // Must happen before, otherwise bookmark is gone
        
        // TODO: Make type dynamic
        Sync.shared.sendSyncRecords(recordType: .bookmark, action: .delete, records: [self])
        
        context.delete(s)
        if save {
            DataController.saveContext(context: context)
        }
    }
}

class SyncHelpers {
    // Converters
    
    /// UUID -> DisplayUUID
    static func syncDisplay(fromUUID uuid: [Int]?) -> String? {
        return uuid?.map{ $0.description }.joined(separator: ",")
    }
    
    /// DisplayUUID -> UUID
    static func syncUUID(fromString string: String?) -> [Int]? {
        return string?.components(separatedBy: ",").flatMap { Int($0) }
    }
    
    static func syncUUID(fromJSON json: JSON?) -> [Int]? {
        return json?.array?.flatMap { $0.int }
    }
}
