//
//  SecureStorageManager.swift
//  bitchat
//

import Foundation

/// A wrapper class that replaces UserDefaults for sensitive settings,
/// storing them securely in the Keychain instead.
/// It uses PropertyListSerialization to support all types that UserDefaults supports
/// (Data, String, Number, Date, Array, Dictionary).
final class SecureStorageManager {
    static let shared = SecureStorageManager()
    
    private let serviceName = "com.gapmesh.secureDefaults"
    private var cache: [String: Any] = [:]
    private let queue = DispatchQueue(label: "com.gapmesh.SecureStorageManager", attributes: .concurrent)
    
    init() { }
    
    func set(_ value: Any?, forKey key: String) {
        queue.async(flags: .barrier) {
            guard let value = value else {
                KeychainManager().delete(key: key, service: self.serviceName)
                self.cache.removeValue(forKey: key)
                return
            }
            
            self.cache[key] = value
            
            if let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0) {
                KeychainManager().save(key: key, data: data, service: self.serviceName, accessible: nil)
            }
        }
    }
    
    func object(forKey key: String) -> Any? {
        return queue.sync {
            if let cached = cache[key] { return cached }
            
            guard let data = KeychainManager().load(key: key, service: serviceName),
                  let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
                return nil
            }
            cache[key] = value
            return value
        }
    }
    
    func bool(forKey key: String) -> Bool {
        return object(forKey: key) as? Bool ?? false
    }
    
    func string(forKey key: String) -> String? {
        return object(forKey: key) as? String
    }
    
    func stringArray(forKey key: String) -> [String]? {
        return object(forKey: key) as? [String]
    }
    
    func data(forKey key: String) -> Data? {
        return object(forKey: key) as? Data
    }
    
    func array(forKey key: String) -> [Any]? {
        return object(forKey: key) as? [Any]
    }
}
