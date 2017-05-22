//
//  Heart.swift
//  Swiftkiq
//
//  Created by Namai Satoshi on 2017/03/20.
//
//

import Foundation
import Redis

public class Heart {
    lazy var formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "Y-M-d"
        return formatter
    }()
    
    let converter: Converter = JsonConverter.default

    private let concurrency: Int
    private let queues: [Queue]
    
    init(concurrency: Int, queues: [Queue]) {
        self.concurrency = concurrency
        self.queues = queues
    }
    
    func beat(done: Bool) throws {
        let processKey = ProcessIdentityGenerator.identity.rawValue
        let workerKey = "\(processKey):workers"
        
        var processed = 0
        var failed = 0
        Processor.processedCounter.update { processed = $0; return 0 }
        Processor.failureCounter.update { failed = $0; return 0 }
        
        do {
            try Application.connectionPoolForInternal { conn in
                let nowdate = formatter.string(from: Date())
                let transaction = try conn.pipelined()
                    .enqueue(Command("MULTI"))
                    .enqueue(Command("INCRBY"), ["stat:processed", "\(processed)"].map { $0.makeBytes() })
                    .enqueue(Command("INCRBY"), ["stat:failed", "\(failed)"].map { $0.makeBytes() })
                    .enqueue(Command("INCRBY"), ["stat:processed:\(nowdate)", "\(processed)"].map { $0.makeBytes() })
                    .enqueue(Command("INCRBY"), ["stat:failed:\(nowdate)", "\(processed)"].map { $0.makeBytes() })
                    .enqueue(.delete, [workerKey])
                
                for (jid, workerState) in Processor.workerStates {
                    try transaction.enqueue(Command("HSET"),
                                            [workerKey, jid.rawValue, converter.serialize(workerState.work.job)].map { $0.makeBytes() })
                }
                try transaction
                    .enqueue(Command("EXPIRE"), [workerKey, String(60)].map { $0.makeBytes() })
                    .enqueue(Command("EXEC"))
                    .execute()
                
                let processState = Process(
                    identity: ProcessIdentityGenerator.identity,
                    hostname: ProcessInfo.processInfo.hostName,
                    startedAt: Date(),
                    pid: Int(ProcessInfo.processInfo.processIdentifier),
                    tag: "",
                    concurrency: concurrency,
                    queues: queues,
                    labels: [""])
                
                try conn.pipelined()
                    .enqueue(Command("MULTI"))
                    .enqueue(Command("SADD"), ["processes", processKey].map { $0.makeBytes() })
                    .enqueue(Command("EXISTS"), [processKey].map { $0.makeBytes() })
                    .enqueue(Command("HMSET"), [
                        processKey,
                        "info", processState.json,
                        "busy", "\(Processor.workerStates.count)",
                        "beat", "\(Date().timeIntervalSince1970)",
                        "quit", "\(done)"].map { $0.makeBytes() })
                    .enqueue(Command("EXPIRE"), [processKey, "60"].map { $0.makeBytes() })
                    .enqueue(Command("RPOP"), ["\(processKey)-signals"].map { $0.makeBytes() })
                    .enqueue(Command("EXEC"))
                    .execute()
            }
        } catch let error {
            logger.error("heartbeat: \(error), \(error.localizedDescription)")
            Processor.processedCounter.increment(by: processed)
            Processor.failureCounter.increment(by: failed)
        }
    }
    
    func clear() {
        do {
            logger.debug("clear heartbeat!")
            _ = try Application.connectionPoolForInternal { conn in
                _ = try conn.pipelined()
                    .enqueue(Command("SREM"), ["processes".makeBytes(), ProcessIdentityGenerator.identity.rawValue.makeBytes()])
                    .enqueue(.delete, ["\(ProcessIdentityGenerator.identity):workers".makeBytes()])
                    .execute()
            }
        } catch {
            // best effort
        }
    }
}
