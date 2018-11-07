//
//  BBMemoryCache.swift
//  BBWebImage
//
//  Created by Kaibo Lu on 2018/10/29.
//  Copyright © 2018年 Kaibo Lu. All rights reserved.
//

import UIKit

private class BBLinkedMapNode {
    fileprivate weak var prev: BBLinkedMapNode?
    fileprivate weak var next: BBLinkedMapNode?
    fileprivate var value: Any
    fileprivate var cost: Int
    fileprivate var lastAccessTime: TimeInterval
    
    fileprivate init(value: Any) {
        self.value = value
        self.cost = 0
        self.lastAccessTime = CACurrentMediaTime()
    }
}

private class BBLinkedMap {
    fileprivate var dic: [String : BBLinkedMapNode]
    fileprivate var totalCost: Int
    fileprivate var totalCount: Int
    fileprivate var head: BBLinkedMapNode?
    fileprivate var tail: BBLinkedMapNode?
    
    init() {
        dic = [:]
        totalCost = 0
        totalCount = 0
    }
    
    fileprivate func bringNodeToHead(_ node: BBLinkedMapNode) {
        if head === node { return }
        if tail === node {
            tail = node.prev
            tail?.next = nil
        } else {
            node.prev?.next = node.next
            node.next?.prev = node.prev
        }
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
    }
    
    fileprivate func insertNodeAtHead(_ node: BBLinkedMapNode) {
        if head == nil {
            head = node
            tail = node
        } else {
            node.next = head
            head?.prev = node
            head = node
        }
        totalCost += node.cost
        totalCount += 1
    }
    
    fileprivate func remove(_ node: BBLinkedMapNode) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
        if head === node { head = node.next }
        if tail === node { tail = node.prev }
        totalCost -= node.cost
        totalCount -= 1
    }
    
    fileprivate func removeAll() {
        head = nil
        tail = nil
        totalCost = 0
        totalCount = 0
    }
}

public class BBMemoryCache {
    private let linkedMap: BBLinkedMap
    private var costLimit: Int
    private var countLimit: Int
    private var ageLimit: TimeInterval
    private var lock: pthread_mutex_t
    private var queue: DispatchQueue
    
    init() {
        linkedMap = BBLinkedMap()
        costLimit = .max
        countLimit = .max
        ageLimit = .greatestFiniteMagnitude
        lock = pthread_mutex_t()
        pthread_mutex_init(&lock, nil)
        queue = DispatchQueue(label: "com.Kaibo.BBWebImage.MemoryCache.queue", qos: .background)
        
        NotificationCenter.default.addObserver(self, selector: #selector(clear), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clear), name: UIApplication.didEnterBackgroundNotification, object: nil)
        
        trimRecursively()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        pthread_mutex_destroy(&lock)
    }
    
    public func image(forKey key: String) -> UIImage? {
        pthread_mutex_lock(&lock)
        var value: UIImage?
        if let node = linkedMap.dic[key] {
            value = node.value as? UIImage
            node.lastAccessTime = CACurrentMediaTime()
            linkedMap.bringNodeToHead(node)
        }
        pthread_mutex_unlock(&lock)
        return value
    }
    
    public func store(_ image: UIImage, forKey key: String, cost: Int = 0) {
        pthread_mutex_lock(&lock)
        let realCost: Int = cost > 0 ? cost : Int(image.size.width * image.size.height * image.scale)
        if let node = linkedMap.dic[key] {
            linkedMap.totalCost += realCost - node.cost
            node.value = image
            node.cost = realCost
            node.lastAccessTime = CACurrentMediaTime()
            linkedMap.bringNodeToHead(node)
        } else {
            let node = BBLinkedMapNode(value: image)
            node.cost = realCost
            linkedMap.dic[key] = node
            linkedMap.insertNodeAtHead(node)
            
            if linkedMap.totalCount > countLimit,
                let tail = linkedMap.tail {
                linkedMap.remove(tail)
            }
        }
        if linkedMap.totalCost > costLimit {
            queue.async { [weak self] in
                guard let self = self else { return }
                self.trim(toCost: self.costLimit)
            }
        }
        pthread_mutex_unlock(&lock)
    }
    
    public func removeImage(forKey key: String) {
        pthread_mutex_lock(&lock)
        if let node = linkedMap.dic[key] {
            linkedMap.dic[key] = nil
            linkedMap.remove(node)
        }
        pthread_mutex_unlock(&lock)
    }
    
    @objc public func clear() {
        pthread_mutex_lock(&lock)
        linkedMap.dic.removeAll()
        linkedMap.removeAll()
        pthread_mutex_unlock(&lock)
    }
    
    public func setCostLimit(_ cost: Int) {
        pthread_mutex_lock(&lock)
        costLimit = cost
        queue.async { [weak self] in
            guard let self = self else { return }
            self.trim(toCost: cost)
        }
        pthread_mutex_unlock(&lock)
    }
    
    public func setCountLimit(_ count: Int) {
        pthread_mutex_lock(&lock)
        countLimit = count
        queue.async { [weak self] in
            guard let self = self else { return }
            self.trim(toCount: count)
        }
        pthread_mutex_unlock(&lock)
    }
    
    public func setAgeLimit(_ age: TimeInterval) {
        pthread_mutex_lock(&lock)
        ageLimit = age
        queue.async { [weak self] in
            guard let self = self else { return }
            self.trim(toAge: age)
        }
        pthread_mutex_unlock(&lock)
    }
    
    private func trim(toCost cost: Int) {
        pthread_mutex_lock(&lock)
        let unlock: () -> Void = { pthread_mutex_unlock(&self.lock) }
        if cost <= 0 {
            linkedMap.dic.removeAll()
            linkedMap.removeAll()
            return unlock()
        } else if linkedMap.totalCost <= cost {
            return unlock()
        }
        unlock()
        
        while true {
            if pthread_mutex_trylock(&lock) == 0 {
                if linkedMap.totalCost > cost,
                    let tail = linkedMap.tail {
                    linkedMap.remove(tail)
                } else {
                    return unlock()
                }
                unlock()
            } else {
                usleep(10 * 1000) // 10 ms
            }
        }
    }
    
    private func trim(toCount count: Int) {
        pthread_mutex_lock(&lock)
        let unlock: () -> Void = { pthread_mutex_unlock(&self.lock) }
        if count <= 0 {
            linkedMap.dic.removeAll()
            linkedMap.removeAll()
            return unlock()
        } else if linkedMap.totalCount <= count {
            return unlock()
        }
        unlock()
        
        while true {
            if pthread_mutex_trylock(&lock) == 0 {
                if linkedMap.totalCount > count,
                    let tail = linkedMap.tail {
                    linkedMap.remove(tail)
                } else {
                    return unlock()
                }
                unlock()
            } else {
                usleep(10 * 1000) // 10 ms
            }
        }
    }
    
    private func trim(toAge age: TimeInterval) {
        pthread_mutex_lock(&lock)
        let unlock: () -> Void = { pthread_mutex_unlock(&self.lock) }
        let now = CACurrentMediaTime()
        if age <= 0 {
            linkedMap.dic.removeAll()
            linkedMap.removeAll()
            return unlock()
        } else if linkedMap.tail == nil || now - linkedMap.tail!.lastAccessTime <= age {
            return unlock()
        }
        unlock()
        
        while true {
            if pthread_mutex_trylock(&lock) == 0 {
                if let tail = linkedMap.tail,
                    now - tail.lastAccessTime > age {
                    linkedMap.remove(tail)
                } else {
                    return unlock()
                }
                unlock()
            } else {
                usleep(10 * 1000) // 10 ms
            }
        }
    }
    
    private func trimRecursively() {
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            self.trim(toAge: self.ageLimit)
            self.trimRecursively()
        }
    }
}