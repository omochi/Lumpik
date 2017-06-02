//
//  Fetcher.swift
//  Lumpik
//
//  Created by satoshi.namai on 2017/02/24.
//
//

import Foundation
import Redis

public protocol Fetcher: class {
    init(queues: [Queue])
    func retriveWork() throws -> UnitOfWork?
    func bulkRequeue(_ jobs: [UnitOfWork]) throws
}

final class BasicFetcher: Fetcher {
    private let queues: [Queue]

    init(queues: [Queue]) {
        self.queues = queues
    }

    func retriveWork() throws -> UnitOfWork? {
        return try Application.connectionPool { conn in
            try conn.dequeue(randomSortedQueues())
        }
    }
    
    func randomSortedQueues () -> [Queue] {
        var a = queues
        let n = a.count
        for i in 0..<n {
            let ai: Queue = a[i]
            let j = Int(Compat.random(n))
            if i != j {
                a[i] = a[j]
            }
            a[j] = ai
        }
        return a
    }
    
    func bulkRequeue(_ jobs: [UnitOfWork]) throws {
        _ = try Application.connectionPool { conn in
            let pipeline = conn.pipelined()
            let encoder = JsonConverter.default
        
            for job in jobs {
                let payload = try encoder.serialize(job.job)
                try pipeline.enqueue(Command("RPUSH"), [job.queue.key, payload.makeBytes()])
            }
        
            try pipeline.execute()
        }
    }
}