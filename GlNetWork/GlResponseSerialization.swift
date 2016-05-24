//
//  GlResponseSerialization.swift
//  Swift2Demo
//
//  Created by MAC02 on 16/3/26.
//  Copyright © 2016年 MAC02. All rights reserved.
//

import Foundation

public protocol GlResponseSerializerType {
    /// The type of serialized object to be created by this `ResponseSerializerType`.
    typealias SerializedObject
    
    /// The type of error to be created by this `ResponseSerializer` if serialization fails.
    typealias ErrorObject: ErrorType
    
    /**
     A closure used by response handlers that takes a request, response, data and error and returns a result.
     */
    var serializeResponse: (NSURLRequest?, NSHTTPURLResponse?, NSData?, NSError?) -> GlResult<SerializedObject, ErrorObject> { get }
}


extension GlRequest {
    
    /**
     请求完成后调用block
     
     - parameter queue: 完成后将被杀死的队列
     - parameter completionHandler: 请求完成后执行的block
     
     - returns: The request.
     */
    public func response(
        queue queue: dispatch_queue_t? = nil,
        completionHandler: (NSURLRequest?, NSHTTPURLResponse?, NSData?, NSError?) -> Void)
        -> Self
    {
        delegate.queue.addOperationWithBlock {
            dispatch_async(queue ?? dispatch_get_main_queue()) {
                completionHandler(self.request, self.response, self.delegate.data, self.delegate.error)
            }
        }
        
        return self
    }
    
    /**
     请求完成后调用block
     - parameter queue:              完成后将被杀死的队列
     - parameter responseSerializer: The response serializer responsible for serializing the request, response,
     and data.
     - parameter completionHandler:  请求完成后执行的block
     
     - returns: The request.
     */
    public func response<T: GlResponseSerializerType>(
        queue queue: dispatch_queue_t? = nil,
        responseSerializer: T,
        completionHandler: GlResponse<T.SerializedObject, T.ErrorObject> -> Void)
        -> Self
    {
        /*如果你有一个简单的操作不需要被继承，你可以将它当做一个块（block）传递给队列。如果你需要从块那里传递回任何数据，记得你不应该传递任何强引用的指针给块；相反，你必须使用弱引用。而且，如果你想要在块中做一些跟UI有关的事情，你必须在主线程中做。*/
        print("delegate:\(delegate)")
        print("delegateQueue:\(delegate.queue)")
        delegate.queue.addOperationWithBlock {
            //返回一个GlResult对象，传入四个参数初始化，
            let result = responseSerializer.serializeResponse(
                self.request,
                self.response,
                self.delegate.data,
                self.delegate.error
            )
            
            let requestCompletedTime = self.endTime ?? CFAbsoluteTimeGetCurrent()
            let initialResponseTime = self.delegate.initialResponseTime ?? requestCompletedTime
            
            let timeline = GlTimeline(
                requestStartTime: self.startTime ?? CFAbsoluteTimeGetCurrent(),
                initialResponseTime: initialResponseTime,
                requestCompletedTime: requestCompletedTime,
                serializationCompletedTime: CFAbsoluteTimeGetCurrent()
            )
            
            let response = GlResponse<T.SerializedObject, T.ErrorObject>(
                request: self.request,
                response: self.response,
                data: self.delegate.data,
                result: result,
                timeline: timeline
            )
            
            dispatch_async(queue ?? dispatch_get_main_queue()) { completionHandler(response) }//block回到主线程响应
        }
        
        return self
    }
}

// MARK: - JSON
public struct GlResponseSerializer<Value, Error: ErrorType>: GlResponseSerializerType {
    /// The type of serialized object to be created by this `ResponseSerializer`.
    public typealias SerializedObject = Value
    
    /// The type of error to be created by this `ResponseSerializer` if serialization fails.
    public typealias ErrorObject = Error
    
    /**
     A closure used by response handlers that takes a request, response, data and error and returns a result.
     */
    public var serializeResponse: (NSURLRequest?, NSHTTPURLResponse?, NSData?, NSError?) -> GlResult<Value, Error>
    
    /**
     Initializes the `ResponseSerializer` instance with the given serialize response closure.
     
     - parameter serializeResponse: The closure used to serialize the response.
     
     - returns: The new generic response serializer instance.
     */
    public init(serializeResponse: (NSURLRequest?, NSHTTPURLResponse?, NSData?, NSError?) -> GlResult<Value, Error>) {
        self.serializeResponse = serializeResponse
    }
}
extension GlRequest {
    
    /**
     将返回的NSData序列号为JSON
     `NSJSONSerialization` with the specified reading options.
     
     - parameter options: The JSON 序列化得方式`.
     AllowFragments` 为默认值，表示允许根节点 可以不是NSArray,NSDictionary.
     MutableLeaves 叶子节点是可变的
     MutableContainers 容器是可变的，转成的结果是可变的类型
     
     - returns: JSON对象
     */
    public static func JSONResponseSerializer(
        options options: NSJSONReadingOptions = .AllowFragments)
        -> GlResponseSerializer<AnyObject, NSError>
    {
        //返回一个GlResponseSerializer，此时初始化的时候实现block
        return GlResponseSerializer { _, response, data, error in
            guard error == nil else { return .Failure(error!) }
            
            if let response = response where response.statusCode == 204 { return .Success(NSNull()) }
            
            guard let validData = data where validData.length > 0 else {//长度小于0切data为空
                let failureReason = "JSON could not be serialized. Input data was nil or zero length."
                let error = GlError.errorWithCode(.JSONSerializationFailed, failureReason: failureReason)
                return .Failure(error)
            }
            
            do {
                print("序列化前：\(validData)")
                let JSON = try NSJSONSerialization.JSONObjectWithData(validData, options: options)
                print("序列化后：\(JSON)")
                return .Success(JSON)
            } catch {
                return .Failure(error as NSError)
            }
        }
    }
    
    /**
     请求结束返回该block
     
     - parameter options:           The JSON serialization reading options. `.AllowFragments` by default.
     - parameter completionHandler: 请求结束时执行闭包
     
     - returns: 当前请求
     */
    public func responseJSON(
        options options: NSJSONReadingOptions = .AllowFragments,
        completionHandler: GlResponse<AnyObject, NSError> -> Void)
        -> Self
    {
        return response(
            responseSerializer: GlRequest.JSONResponseSerializer(options: options),
            completionHandler: completionHandler
        )
    }
}