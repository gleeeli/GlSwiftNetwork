//
//  GlRequest.swift
//  Swift2Demo
//
//  Created by MAC02 on 16/3/16.
//  Copyright © 2016年 MAC02. All rights reserved.
//

import Foundation

public class GlRequest {
    
    public let delegate: TaskDelegate
    public var task: NSURLSessionTask { return delegate.task}//任务类别
    public let session: NSURLSession
    public var request: NSURLRequest? { return task.originalRequest }
    /// 响应
    public var response: NSHTTPURLResponse? { return task.response as? NSHTTPURLResponse }
    
    var startTime: CFAbsoluteTime?
    var endTime: CFAbsoluteTime?
    /**
     初始化请求的返回代理
     */
    init(session: NSURLSession, task: NSURLSessionTask) {
        self.session = session
        
        switch task {
        case is NSURLSessionUploadTask:
            //delegate = UploadTaskDelegate(task: task)
            delegate = TaskDelegate(task: task);
        case is NSURLSessionDataTask:
            delegate = DataTaskDelegate(task: task)
        case is NSURLSessionDownloadTask:
            //delegate = DownloadTaskDelegate(task: task)
            delegate = TaskDelegate(task: task);
        default:
            delegate = TaskDelegate(task: task)
        }
        delegate.queue.addOperationWithBlock { self.endTime = CFAbsoluteTimeGetCurrent() }
        print("TaskDelegate:\(delegate)\n")
    }
    //开启请求
    public func resume() {
        if startTime == nil { startTime = CFAbsoluteTimeGetCurrent() }
        
        task.resume()
        //发送开启任务的通知
        NSNotificationCenter.defaultCenter().postNotificationName(GlNotifications.Task.DidResume, object: task)
    }
        
    public class TaskDelegate: NSObject {
        
        /// The serial operation queue used to execute all operations after the task completes.
        public let queue: NSOperationQueue
        
        let task: NSURLSessionTask
        let progress: NSProgress
        
        var data: NSData? { return nil }
        var error: NSError?
        
        var initialResponseTime: CFAbsoluteTime?
        var credential: NSURLCredential?
        
        init(task: NSURLSessionTask) {
            self.task = task
            self.progress = NSProgress(totalUnitCount: 0)
            self.queue = {
                let operationQueue = NSOperationQueue()
                operationQueue.maxConcurrentOperationCount = 1//最大线程数
                operationQueue.suspended = true//暂停队列
                
                if #available(OSX 10.10, *) {
                    operationQueue.qualityOfService = NSQualityOfService.Utility
                }
                
                return operationQueue
                }()
            print("self.queue:\(self.queue)")
            
        }
        
        deinit {
            queue.cancelAllOperations()
            queue.suspended = false //开启队列
        }
        
        // MARK: - NSURLSessionTaskDelegate
        
        // MARK: Override Closures
        
        var taskWillPerformHTTPRedirection: ((NSURLSession, NSURLSessionTask, NSHTTPURLResponse, NSURLRequest) -> NSURLRequest?)?
        var taskDidReceiveChallenge: ((NSURLSession, NSURLSessionTask, NSURLAuthenticationChallenge) -> (NSURLSessionAuthChallengeDisposition, NSURLCredential?))?
        var taskNeedNewBodyStream: ((NSURLSession, NSURLSessionTask) -> NSInputStream?)?
        var taskDidCompleteWithError: ((NSURLSession, NSURLSessionTask, NSError?) -> Void)?
        
        // MARK: Delegate Methods
        
        func URLSession(
            session: NSURLSession,
            task: NSURLSessionTask,
            willPerformHTTPRedirection response: NSHTTPURLResponse,
            newRequest request: NSURLRequest,
            completionHandler: ((NSURLRequest?) -> Void))
        {
            var redirectRequest: NSURLRequest? = request
            
            if let taskWillPerformHTTPRedirection = taskWillPerformHTTPRedirection {
                redirectRequest = taskWillPerformHTTPRedirection(session, task, response, request)
            }
            
            completionHandler(redirectRequest)
        }
        
        func URLSession(
            session: NSURLSession,
            task: NSURLSessionTask,
            didReceiveChallenge challenge: NSURLAuthenticationChallenge,
            completionHandler: ((NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void))
        {
            var disposition: NSURLSessionAuthChallengeDisposition = .PerformDefaultHandling
            var credential: NSURLCredential?
            
            if let taskDidReceiveChallenge = taskDidReceiveChallenge {
                (disposition, credential) = taskDidReceiveChallenge(session, task, challenge)
            } else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                let host = challenge.protectionSpace.host
                
                if let
                    serverTrustPolicy = session.glServerTrustPolicyManager?.serverTrustPolicyForHost(host),
                    serverTrust = challenge.protectionSpace.serverTrust
                {
                    if serverTrustPolicy.evaluateServerTrust(serverTrust, isValidForHost: host) {
                        disposition = .UseCredential
                        credential = NSURLCredential(forTrust: serverTrust)
                    } else {
                        disposition = .CancelAuthenticationChallenge
                    }
                }
            } else {
                if challenge.previousFailureCount > 0 {
                    disposition = .CancelAuthenticationChallenge
                } else {
                    credential = self.credential ?? session.configuration.URLCredentialStorage?.defaultCredentialForProtectionSpace(challenge.protectionSpace)
                    
                    if credential != nil {
                        disposition = .UseCredential
                    }
                }
            }
            
            completionHandler(disposition, credential)
        }
        
        func URLSession(
            session: NSURLSession,
            task: NSURLSessionTask,
            needNewBodyStream completionHandler: ((NSInputStream?) -> Void))
        {
            var bodyStream: NSInputStream?
            
            if let taskNeedNewBodyStream = taskNeedNewBodyStream {
                bodyStream = taskNeedNewBodyStream(session, task)
            }
            
            completionHandler(bodyStream)
        }
        
        //任务完成，开启队列，此时delegate.queue.addOperationWithBlock中的block开始执行
        func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
            if let taskDidCompleteWithError = taskDidCompleteWithError {
                taskDidCompleteWithError(session, task, error)
            } else {//没有错误
                if let error = error {
                    self.error = error
                    
                    if let
                        downloadDelegate = self as? DownloadTaskDelegate,
                        userInfo = error.userInfo as? [String: AnyObject],
                        resumeData = userInfo[NSURLSessionDownloadTaskResumeData] as? NSData
                    {
                        downloadDelegate.resumeData = resumeData
                    }
                }
                
                queue.suspended = false //开启队列
            }
        }
    }
    // MARK: - DataTaskDelegate
    
    class DataTaskDelegate: TaskDelegate, NSURLSessionDataDelegate {
        var dataTask: NSURLSessionDataTask? { return task as? NSURLSessionDataTask }
        
        private var totalBytesReceived: Int64 = 0
        private var mutableData: NSMutableData
        override var data: NSData? {
            if dataStream != nil {
                return nil
            } else {
                return mutableData
            }
        }
        
        private var expectedContentLength: Int64?
        private var dataProgress: ((bytesReceived: Int64, totalBytesReceived: Int64, totalBytesExpectedToReceive: Int64) -> Void)?
        private var dataStream: ((data: NSData) -> Void)?
        
        override init(task: NSURLSessionTask) {
            mutableData = NSMutableData()
            super.init(task: task)
        }
        
        // MARK: - NSURLSessionDataDelegate
        
        // MARK: Override Closures
        
        var dataTaskDidReceiveResponse: ((NSURLSession, NSURLSessionDataTask, NSURLResponse) -> NSURLSessionResponseDisposition)?
        var dataTaskDidBecomeDownloadTask: ((NSURLSession, NSURLSessionDataTask, NSURLSessionDownloadTask) -> Void)?
        var dataTaskDidReceiveData: ((NSURLSession, NSURLSessionDataTask, NSData) -> Void)?
        var dataTaskWillCacheResponse: ((NSURLSession, NSURLSessionDataTask, NSCachedURLResponse) -> NSCachedURLResponse?)?
        
        // MARK: Delegate Methods
        
        func URLSession(
            session: NSURLSession,
            dataTask: NSURLSessionDataTask,
            didReceiveResponse response: NSURLResponse,
            completionHandler: (NSURLSessionResponseDisposition -> Void))
        {
            var disposition: NSURLSessionResponseDisposition = .Allow
            
            expectedContentLength = response.expectedContentLength
            
            if let dataTaskDidReceiveResponse = dataTaskDidReceiveResponse {
                disposition = dataTaskDidReceiveResponse(session, dataTask, response)
            }
            
            completionHandler(disposition)
        }
        
        func URLSession(
            session: NSURLSession,
            dataTask: NSURLSessionDataTask,
            didBecomeDownloadTask downloadTask: NSURLSessionDownloadTask)
        {
            dataTaskDidBecomeDownloadTask?(session, dataTask, downloadTask)
        }
        
        //收到数据，代理是从GlManager传过来的
        func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
            if initialResponseTime == nil { initialResponseTime = CFAbsoluteTimeGetCurrent() }
            
            if let dataTaskDidReceiveData = dataTaskDidReceiveData {
                dataTaskDidReceiveData(session, dataTask, data)
            } else {
                if let dataStream = dataStream {
                    dataStream(data: data)
                } else {
                    mutableData.appendData(data)
                }
                
                totalBytesReceived += data.length
                let totalBytesExpected = dataTask.response?.expectedContentLength ?? NSURLSessionTransferSizeUnknown
                
                progress.totalUnitCount = totalBytesExpected
                progress.completedUnitCount = totalBytesReceived
                
                dataProgress?(
                    bytesReceived: Int64(data.length),
                    totalBytesReceived: totalBytesReceived,
                    totalBytesExpectedToReceive: totalBytesExpected
                )
            }
        }
        
        func URLSession(
            session: NSURLSession,
            dataTask: NSURLSessionDataTask,
            willCacheResponse proposedResponse: NSCachedURLResponse,
            completionHandler: ((NSCachedURLResponse?) -> Void))
        {
            var cachedResponse: NSCachedURLResponse? = proposedResponse
            
            if let dataTaskWillCacheResponse = dataTaskWillCacheResponse {
                cachedResponse = dataTaskWillCacheResponse(session, dataTask, proposedResponse)
            }
            
            completionHandler(cachedResponse)
        }
    }
    // MARK: - DownloadTaskDelegate
    
    class DownloadTaskDelegate: TaskDelegate, NSURLSessionDownloadDelegate {
        var downloadTask: NSURLSessionDownloadTask? { return task as? NSURLSessionDownloadTask }
        var downloadProgress: ((Int64, Int64, Int64) -> Void)?
        
        var resumeData: NSData?
        override var data: NSData? { return resumeData }
        
        // MARK: - NSURLSessionDownloadDelegate
        
        // MARK: Override Closures
        
        var downloadTaskDidFinishDownloadingToURL: ((NSURLSession, NSURLSessionDownloadTask, NSURL) -> NSURL)?
        var downloadTaskDidWriteData: ((NSURLSession, NSURLSessionDownloadTask, Int64, Int64, Int64) -> Void)?
        var downloadTaskDidResumeAtOffset: ((NSURLSession, NSURLSessionDownloadTask, Int64, Int64) -> Void)?
        
        // MARK: Delegate Methods
        
        func URLSession(
            session: NSURLSession,
            downloadTask: NSURLSessionDownloadTask,
            didFinishDownloadingToURL location: NSURL)
        {
            if let downloadTaskDidFinishDownloadingToURL = downloadTaskDidFinishDownloadingToURL {
                do {
                    let destination = downloadTaskDidFinishDownloadingToURL(session, downloadTask, location)
                    try NSFileManager.defaultManager().moveItemAtURL(location, toURL: destination)
                } catch {
                    self.error = error as NSError
                }
            }
        }
        
        //下载进度更新时调用的方法
        func URLSession(
            session: NSURLSession,
            downloadTask: NSURLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64)
        {
            if initialResponseTime == nil { initialResponseTime = CFAbsoluteTimeGetCurrent() }
            
            if let downloadTaskDidWriteData = downloadTaskDidWriteData {
                downloadTaskDidWriteData(
                    session,
                    downloadTask,
                    bytesWritten,
                    totalBytesWritten,
                    totalBytesExpectedToWrite
                )
            } else {
                progress.totalUnitCount = totalBytesExpectedToWrite
                progress.completedUnitCount = totalBytesWritten
                
                downloadProgress?(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
            }
        }
        
        func URLSession(
            session: NSURLSession,
            downloadTask: NSURLSessionDownloadTask,
            didResumeAtOffset fileOffset: Int64,
            expectedTotalBytes: Int64)
        {
            if let downloadTaskDidResumeAtOffset = downloadTaskDidResumeAtOffset {
                downloadTaskDidResumeAtOffset(session, downloadTask, fileOffset, expectedTotalBytes)
            } else {
                progress.totalUnitCount = expectedTotalBytes
                progress.completedUnitCount = fileOffset
            }
        }
    }

}
