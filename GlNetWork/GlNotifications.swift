//
//  GlNotifications.swift
//  Swift2Demo
//
//  Created by MAC02 on 16/3/26.
//  Copyright © 2016年 MAC02. All rights reserved.
//

import Foundation

public struct GlNotifications {
    /**
     *  给相关任务的通知命名
     */
    public struct Task {
        /// 通知开启请求任务
        public static let DidResume = "com.alamofire.notifications.task.didResume"
        
        /// Notification posted when an `NSURLSessionTask` is suspended. The notification `object` contains the
        /// suspended `NSURLSessionTask`.
        public static let DidSuspend = "com.alamofire.notifications.task.didSuspend"
        
        /// Notification posted when an `NSURLSessionTask` is cancelled. The notification `object` contains the
        /// cancelled `NSURLSessionTask`.
        public static let DidCancel = "com.alamofire.notifications.task.didCancel"
        
        /// Notification posted when an `NSURLSessionTask` is completed. The notification `object` contains the
        /// completed `NSURLSessionTask`.
        public static let DidComplete = "com.alamofire.notifications.task.didComplete"
    }
}