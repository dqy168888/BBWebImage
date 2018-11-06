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
    fileprivate var cost: Int = 0
    fileprivate var lastAccessTime: TimeInterval
    
    fileprivate init(value: Any) {
        self.value = value
        self.lastAccessTime = CACurrentMediaTime()
    }
}

private class BBLinkedMap {
    fileprivate var dic: [String : BBLinkedMapNode] = [:]
    fileprivate var totalCost: Int = 0
    fileprivate var totalCount: Int = 0
    fileprivate var head: BBLinkedMapNode?
    fileprivate var tail: BBLinkedMapNode?
    
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
    private let linkedMap = BBLinkedMap()
    private var costLimit: Int = Int.max
    private var countLimit: Int = Int.max
    private var ageLimit: TimeInterval = .greatestFiniteMagnitude
    private var lock = pthread_mutex_t()
    
    init() {
        pthread_mutex_init(&lock, nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(clear), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clear), name: UIApplication.didEnterBackgroundNotification, object: nil)
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
        }
        pthread_mutex_unlock(&lock)
        // TODO: Trim
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
}
