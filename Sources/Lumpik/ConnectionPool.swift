//
//  ConnectionPool.swift
//  Lumpik
//
//  Created by Namai Satoshi on 2017/05/13.
//
//

import Foundation
import Dispatch

public protocol Connectable {
    static func makeConnection() throws -> Self
    func releaseConnection() throws
}

public protocol ConnectablePool {
    associatedtype Connection: Connectable
    
    func borrow() throws -> Connection
    func checkin(_ connection: Connection)
    func with<T>(handler: (Connection) -> (T)) throws -> T
    func with<T>(handler: (Connection) throws -> (T)) throws -> T
}

public enum ConnectablePoolError: Error {
    case timeout
}

public class ConnectionPool<T: Connectable>: ConnectablePool {
    public typealias Connection = T
    
    public let maxCapacity: Int
    
    private var pool = [Connection]()
    private let mutex = Mutex()
    private let semaphore: DispatchSemaphore
    private let poolCounter = AtomicCounter<Int>(0)
    
    public init(maxCapacity: Int) {
        self.maxCapacity = maxCapacity
        self.semaphore = DispatchSemaphore(value: maxCapacity)
    }
    
    deinit {
        pool.forEach { conn in
            try? conn.releaseConnection()
        }
    }
    
    public func borrow() throws -> Connection {
        // double check locking
        if poolCounter.value < maxCapacity {
            try mutex.synchronize {
                if poolCounter.value < maxCapacity {
                    let conn = try Connection.makeConnection()
                    pool.append(conn)
                    poolCounter.increment()
                }
            }
        }
        
        let deadline = DispatchTime(secondsFromNow: 1.0)
        repeat {
            let result = semaphore.wait(timeout: DispatchTime(secondsFromNow: 0.3))
            switch result {
            case .success:
                mutex.lock()
                defer { mutex.unlock() }
                if let conn = pool.popLast() {
                    return conn
                }
                fatalError("can't find connection item from pool")
            case .timedOut:
                continue
            }
        } while deadline < DispatchTime.now()
        
        throw ConnectablePoolError.timeout
    }
    
    public func checkin(_ connection: Connection) {
        mutex.synchronize {
            precondition(pool.count < maxCapacity)
            pool.append(connection)
        }
        semaphore.signal()
    }
}

extension ConnectablePool {
    @discardableResult
    public func with<T>(handler: (Connection) -> (T)) throws -> T {
        let conn = try borrow()
        defer { checkin(conn) }
        return handler(conn)
    }
    
    @discardableResult
    public func with<T>(handler: (Connection) throws -> (T)) throws -> T {
        let conn = try borrow()
        defer { checkin(conn) }
        return try handler(conn)
    }
}

public struct AnyConnectablePool<T: Connectable>: ConnectablePool {
    let _borrow: () throws -> T
    let _checkin: (T) -> ()

    public init<CP: ConnectablePool>(_ connectionPool: CP) where CP.Connection == T {
        self._borrow = connectionPool.borrow
        self._checkin = connectionPool.checkin
    }
    
    public func borrow() throws -> T {
        return try _borrow()
    }
    
    public func checkin(_ connection: T) {
        _checkin(connection)
    }

}
