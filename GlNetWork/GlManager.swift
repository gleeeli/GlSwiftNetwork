//
//  GlManager.swift
//  Swift2Demo
//
//  Created by MAC02 on 16/3/16.
//  Copyright © 2016年 MAC02. All rights reserved.
//

import Foundation

public class GlManager {
    public static let shareInstance: GlManager = {
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()//设置session工作模式为默认模式
        configuration.HTTPAdditionalHeaders  = GlManager.defaultHTTPHeaders
        
        return GlManager(configuration: configuration)
    }()
    
    public static let defaultHTTPHeaders: [String: String] = {
       let acceptEncoding: String = "gzip;q=1.0, compress;q=0.5" //浏览器发给服务器,声明浏览器支持的编码类型 q=0代表不接受改类型
        /*  告诉服务器支持的语言（zh-CN;q=0.9）
            1.此处为获取系统的前6个语言，
            [NSLocale preferredLanguages]:获取用户的语言偏好设置列表，该列表对应于IOS中Setting>General>Language弹出的面板中的语言列表。
        */
        //待测试
        let acceptLanguage = NSLocale.preferredLanguages().prefix(6).enumerate().map { index, languageCode in
            let quality = 1.0 - (Double(index) * 0.1)
            return "\(languageCode);q=\(quality)"
            }.joinWithSeparator(", ")
        
        //
        let userAgent: String = {
            if let info = NSBundle.mainBundle().infoDictionary {
                let executable: AnyObject = info[kCFBundleExecutableKey as String] ?? "Unknown"//项目名称
                let bundle: AnyObject = info[kCFBundleIdentifierKey as String] ?? "Unknown" //APP_ID
                let version: AnyObject = info[kCFBundleVersionKey as String] ?? "Unknown" //编译版本
                let os: AnyObject = NSProcessInfo.processInfo().operatingSystemVersionString ?? "Unknown"//系统版本
                
                var mutableUserAgent = NSMutableString(string: "\(executable)/\(bundle) (\(version); OS \(os))") as CFMutableString
                let transform = NSString(string: "Any-Latin; Latin-ASCII; [:^ASCII:] Remove") as CFString
                
                if CFStringTransform(mutableUserAgent, UnsafeMutablePointer<CFRange>(nil), transform, false) {//字符串音译
                    return mutableUserAgent as String
                }
            }
            
            return "Alamofire"
        }()
        
        return [
            "Accept-Encoding": acceptEncoding,
            "Accept-Language": acceptLanguage,
            "User-Agent": userAgent
        ]
    }()
    
    let queue = dispatch_queue_create(nil, DISPATCH_QUEUE_SERIAL)
    public let session: NSURLSession
    public let delegate: GlSessionDelegate
    public var startRequestsImmediately: Bool = true //是否立即开始请求，默认为true
    public var backgroundCompletionHandler: (() -> Void)?
    
    public init(configuration: NSURLSessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration(),
        deleagte: GlSessionDelegate = GlSessionDelegate(),serverTrustPolicyManager: GlServerTrustPolicyManager? = nil){
            self.delegate = deleagte
            self.session = NSURLSession(configuration: configuration,delegate: delegate,delegateQueue: nil)//初始化NSURLSession
            self .commonInit(serverTrustPolicyManager: serverTrustPolicyManager)
    }
    
    //给请求加载完成的block 赋值
    private func commonInit(serverTrustPolicyManager serverTrustPolicyManager: GlServerTrustPolicyManager?) {
        session.glServerTrustPolicyManager = serverTrustPolicyManager
        delegate.sessionDidFinishEventsForBackgroundURLSession = { [weak self] session in
            guard let strongSelf = self else { return }
            dispatch_async(dispatch_get_main_queue()){strongSelf.backgroundCompletionHandler?() }
        }
    }
    
    public func request (method: GlMethod,
        _ URLString: URLStringConvertible,
        parameters: [String: AnyObject]? = nil,
        encodeing: GlParameterEncoding = .URL,
        headers: [String: String]? = nil)
        -> GlRequest
    {
        let mutableURLRequest = URLRequest(method,URLString,headers: headers)//获得请求方式和url
        let encodeURLRequest = encodeing.encode(mutableURLRequest,parameters:parameters).0//参数集成
        return request(encodeURLRequest)//返回的请求代理已经有效
    }
    /**
     获取特殊请求，比如上传，下载
     
     - parameter URLRequest: 请求结构体
     
     - returns: 请求以及完成block
     */
    public func request(URLRequest: URLRequestConvertible) -> GlRequest {
        var dataTask: NSURLSessionDataTask!
        dispatch_sync(queue) { () -> Void in
            dataTask = self.session.dataTaskWithRequest(URLRequest.URLRequest)
        }
        let request = GlRequest(session: session, task: dataTask)
        delegate[request.delegate.task] = request.delegate //将请求的代理赋值给GlSessionDelegate的属性subdelegates
        
        if startRequestsImmediately {
            request.resume()//启动请求
        }
        return request
    }

    
    public final class GlSessionDelegate: NSObject, NSURLSessionDelegate,NSURLSessionTaskDelegate,NSURLSessionDataDelegate {
        private var subdelegates: [Int: GlRequest.TaskDelegate] = [:]
        private let subdelegateQueue = dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT)
        
        //根据任务类别将代理放入代理队列，或取出
        subscript(task: NSURLSessionTask) -> GlRequest.TaskDelegate? {
            get {
                var subdelegate: GlRequest.TaskDelegate?
                dispatch_sync(subdelegateQueue) { subdelegate = self.subdelegates[task.taskIdentifier] }
                
                return subdelegate
            }
            
            set {
                dispatch_barrier_async(subdelegateQueue) { self.subdelegates[task.taskIdentifier] = newValue }
            }
        }
        
        /// 覆写 NSURLSessionTaskDelegate method `URLSession:task:didCompleteWithError:`.
        public var taskDidComplete: ((NSURLSession, NSURLSessionTask, NSError?) -> Void)?
        
        //通知代理任务完成
        public func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
            print("***********任务已经完成*******")
            if let taskDidComplete = taskDidComplete {
                taskDidComplete(session, task, error)
            } else if let delegate = self[task] {
                delegate.URLSession(session, task: task, didCompleteWithError: error)
            }
            
            NSNotificationCenter.defaultCenter().postNotificationName(GlNotifications.Task.DidComplete, object: task)
            
            self[task] = nil
        }
        
        /// 覆写 NSURLSessionDataDelegate method `URLSession:dataTask:didReceiveResponse:completionHandler:`.
        public var dataTaskDidReceiveResponse: ((NSURLSession, NSURLSessionDataTask, NSURLResponse) -> NSURLSessionResponseDisposition)?
        public var sessionDidFinishEventsForBackgroundURLSession: ((NSURLSession) -> Void)?
        /// 复写 NSURLSessionDataDelegate 的方法 `URLSession:dataTask:didReceiveData:`.
        public var dataTaskDidReceiveData: ((NSURLSession, NSURLSessionDataTask, NSData) -> Void)?
        
        public var sessionDidBecomeInvalidWithError: ((NSURLSession, NSError?) -> Void)?
        
        //session失效
        public func URLSession(session: NSURLSession, didBecomeInvalidWithError error: NSError?) {
            sessionDidBecomeInvalidWithError?(session, error)
            print("sesssion error:\(error)")
        }
        /**
         返回服务的响应信息
         
         - parameter session:           The session containing the data task that received an initial reply.
         - parameter dataTask:          The data task that received an initial reply.
         - parameter response:          A URL response object populated with headers.
         - parameter completionHandler: A completion handler that your code calls to continue the transfer, passing a
         constant to indicate whether the transfer should continue as a data task or
         should become a download task.
         */
        public func URLSession(
            session: NSURLSession,
            dataTask: NSURLSessionDataTask,
            didReceiveResponse response: NSURLResponse,
            completionHandler: ((NSURLSessionResponseDisposition) -> Void))
        {
            print("收到响应Response:\(response)")
            var disposition: NSURLSessionResponseDisposition = .Allow
            
            if let dataTaskDidReceiveResponse = dataTaskDidReceiveResponse {
                disposition = dataTaskDidReceiveResponse(session, dataTask, response)
            }
            
            completionHandler(disposition)
        }
        
        //收到数据,(将GlRequest中的delegate声明为DataTaskDelegate，然后存入GlSessionDelegate的代理队列中)
        public func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
            print("收到数据data:\(data)")
            let str: NSString = NSString(data: data, encoding: NSUTF8StringEncoding)!
            print("收到数据str:\(str)\n")
            let mydelegate = self[dataTask]
            print("mydelegate:\(mydelegate)")
            let delegate = self[dataTask] as? GlRequest.DataTaskDelegate
            print("dataTaskDidReceiveData:\(dataTaskDidReceiveData)-----self[dataTask]=\(self[dataTask])---delegate=\(delegate)")
            if let dataTaskDidReceiveData = dataTaskDidReceiveData {//若block属性实现，则执行Block
                dataTaskDidReceiveData(session, dataTask, data)
            } else if let delegate = self[dataTask] as? GlRequest.DataTaskDelegate {//从任务队列中取出代理
                delegate.URLSession(session, dataTask: dataTask, didReceiveData: data)
            }
        }
        
    }
}


