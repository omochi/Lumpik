//
//  Manager.swift
//  Swiftkiq
//
//  Created by Namai Satoshi on 2017/02/26.
//
//

import Foundation
import Dispatch
import SwiftyBeaver

protocol ProcessorLifecycleDelegate: class {
    func stopped(processor: Processor)
    func died(processor: Processor, reason: String)
}

public class Manager: ProcessorLifecycleDelegate {
    let concurrency: Int
    let queues: [Queue]
    let strategy: Fetcher.Type
    let router: Routable
    
    private let mutex = Mutex()
    private let done = AtomicProperty<Bool>(false)

    lazy var processors: [Processor] = {
        return (1...self.concurrency).map { index in
            return Manager.makeProcessor(index: index, queues: self.queues, strategy: self.strategy,
                                         router: self.router, delegate: self)
        }
    }()

    static func makeProcessor(index: Int, queues: [Queue], strategy: Fetcher.Type, router: Routable, delegate: ProcessorLifecycleDelegate) -> Processor {
        let fetcher = strategy.init(queues: queues)
        let dispatchQueue = DispatchQueue(label: "swiftkiq-queue\(index)")
        return Processor(fetcher: fetcher, router: router, dispatchQueue: dispatchQueue, delegate: delegate)
    }
    
    init(concurrency: Int = 25, queues: [Queue], strategy: Fetcher.Type = BasicFetcher.self, router: Routable) {
        self.concurrency = concurrency
        self.router = router
        self.queues = queues
        self.strategy = strategy
    }

    func start() {
        processors.forEach { processor in
            processor.start()
        }
    }

    func quiet() {
        guard done.value != true else { return }
        done.value = true
        
        logger.info("Terminating quiet workers")
        processors.forEach { $0.terminate() }
        
        // fire event quite
    }

    static private let pauseTime: useconds_t = 500000
    
    func stop() {
        quiet()
        // fire event shutdown
        usleep(Manager.pauseTime)
        guard !processors.isEmpty else { return }
        
        logger.info("Pausing to allow workers to finish...")

        hardShutdown()
    }
    
    func hardShutdown() {
        fatalError("not implemented yet")
    }
    
    func stopped(processor: Processor) {
        logger.debug("stopped: \(processor)")
        
        mutex.synchronize {
            guard let index = processors.index(where: { $0 === processor }) else { return }
            processors.remove(at: index)
        }
    }

    func died(processor: Processor, reason: String) {
        logger.debug("died: \(processor)")
        
        mutex.synchronize {
            guard let index = processors.index(where: { $0 === processor }) else { return }
            processors.remove(at: index)
            
            if done.value != true {
                let processor = Manager.makeProcessor(index: processors.count, queues: queues,
                                                      strategy: strategy, router: router,
                                                      delegate: self)
                processors.append(processor)
            }
        }
    }
}
