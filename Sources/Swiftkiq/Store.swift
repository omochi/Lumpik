//
//  Store.swift
//  Swiftkiq
//
//  Created by Namai Satoshi on 2017/02/26.
//
//

import Foundation
import Mapper

public protocol Storable: Transactionable, ValueStorable, ListStorable, SetStorable, SortedSetStorable {
    static func makeStore() -> Storable
    @discardableResult func clear<K: StoreKeyConvertible>(_ key: K) throws -> Int
}

public protocol ValueStorable {
    func get<K: StoreKeyConvertible>(_ key: K) throws -> String?
    @discardableResult func set<K: StoreKeyConvertible>(_ key: K, value: String) throws -> Bool
    @discardableResult func increment<K: StoreKeyConvertible>(_ key: K, by count: Int) throws -> Int
}

public protocol ListStorable {
    @discardableResult func enqueue(_ job: [String: Any], to queue: Queue) throws -> Int
    func dequeue(_ queues: [Queue]) throws -> UnitOfWork?
}

public protocol SetStorable {
    @discardableResult func add(_ job: [String: Any], to set: Set) throws -> Int
    func members<T: JsonConvertible>(_ set: Set) throws -> [T]
    func size(_ set: Set) throws -> Int
}

public protocol SortedSetStorable {
    @discardableResult func add(_ job: [String: Any], with score: SortedSetScore, to sortedSet: SortedSet) throws -> Int
    @discardableResult func remove(_ member: [String: Any], to sortedSet: SortedSet) throws -> Bool
    func range(min: SortedSetScore, max: SortedSetScore, from sortedSet: SortedSet, offset: Int, count: Int) throws -> [[String: Any]]
    func size(_ sortedSet: SortedSet) throws -> Int
}

public protocol Transaction {
    @discardableResult func addCommand(_ name: String, params: [String]) throws -> Self
    @discardableResult func exec() throws -> Bool
}

public protocol Transactionable {
    func multi() throws -> Transaction
}

public enum SortedSetScore {
    case value(Double)
    case infinityPositive
    case infinityNegative
    
    var string: String {
        switch self {
        case .value(let double):
            return String(double)
        case .infinityPositive:
            return "+Inf"
        case .infinityNegative:
            return "-Inf"
        }
    }
}

extension StoreKeyConvertible where Self: RawRepresentable, Self.RawValue == String {
    public var name: String {
        return rawValue
    }
    
    public var hashValue: Int {
        return rawValue.hashValue
    }
}
