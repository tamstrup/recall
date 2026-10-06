import CoreData
import Foundation

// A deliberately small native SQLite store. Codable payloads preserve the exact
// transcript structure; audio stays in separate files, never in database blobs.
@MainActor final class RecordingPersistence {
    private let context: NSManagedObjectContext
    private var objects: [UUID: NSManagedObject] = [:]
    private(set) var recordings: [Recording] = []

    init(url: URL? = nil) throws {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "StoredRecording"
        entity.managedObjectClassName = "NSManagedObject"
        let id = NSAttributeDescription()
        id.name = "id"; id.attributeType = .UUIDAttributeType; id.isOptional = false
        let payload = NSAttributeDescription()
        payload.name = "payload"; payload.attributeType = .binaryDataAttributeType; payload.isOptional = false
        entity.properties = [id, payload]
        entity.uniquenessConstraints = [["id"]]
        model.entities = [entity]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: url == nil ? NSInMemoryStoreType : NSSQLiteStoreType,
            configurationName: nil, at: url, options: [NSMigratePersistentStoresAutomaticallyOption: true,
                                                    NSInferMappingModelAutomaticallyOption: true])
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let request = NSFetchRequest<NSManagedObject>(entityName: "StoredRecording")
        for object in try context.fetch(request) {
            guard let data = object.value(forKey: "payload") as? Data else {
                throw RecallError(message: "A recording in the library is unreadable. The original library has been preserved.")
            }
            let recording = try JSONDecoder().decode(Recording.self, from: data)
            recordings.append(recording)
            objects[recording.id] = object
        }
        recordings.sort { $0.importedAt > $1.importedAt }
    }

    func save(_ recordings: [Recording]) throws {
        // Encode all changes before mutating the context so encoding failures are atomic.
        let encoded = try recordings.map { ($0.id, try JSONEncoder().encode($0)) }
        do {
            for (id, data) in encoded {
                let object = objects[id] ?? NSEntityDescription.insertNewObject(forEntityName: "StoredRecording", into: context)
                object.setValue(id, forKey: "id")
                if object.value(forKey: "payload") as? Data != data { object.setValue(data, forKey: "payload") }
                objects[id] = object
            }
            let retained = Set(recordings.map(\.id))
            for id in Array(objects.keys) where !retained.contains(id) {
                if let object = objects.removeValue(forKey: id) { context.delete(object) }
            }
            try context.save()
            self.recordings = recordings
        } catch {
            context.rollback()
            objects = Dictionary(uniqueKeysWithValues: try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "StoredRecording")).compactMap {
                guard let id = $0.value(forKey: "id") as? UUID else { return nil }
                return (id, $0)
            })
            throw error
        }
    }
}
