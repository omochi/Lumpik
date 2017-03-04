//
//  Worker.swift
//  Swiftkiq
//
//  Created by Namai Satoshi on 2017/02/26.
//
//

import Foundation

public protocol Argument {
    func toDictionary() -> [String: Any]
    static func from(_ dictionary: Dictionary<String, Any>) -> Self
}

public protocol Worker: class {
    associatedtype Args: Argument

    static var defaultQueue: Queue { get }
    static var defaultRetry: Int { get }

    var client: Client { get }
    var processorId: Int? { get set }
    var jid: String? { get set }
    var queue: Queue? { get set }
    var retry: Int? { get set }


    init()
    static func performAsync(_ args: Args, to queue: Queue) throws
    func perform(_ args: Args) throws -> ()
}


extension Worker {
    public var client: Client {
        return SwiftkiqClient.current(processorId!)
    }

    public static var defaultQueue: Queue {
        return Queue("default")
    }

    public static var defaultRetry: Int {
        return 25
    }

    public static func performAsync(_ args: Args, to queue: Queue = Self.defaultQueue) throws {
        // TODO: use cached connections every thread
        let client = SwiftkiqClient(store: SwiftkiqCore.makeStore())
        try client.enqueue(class: self, args: args, to: queue)
    }
}
