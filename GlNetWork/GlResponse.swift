//
//  GlResponse.swift
//  Swift2Demo
//
//  Created by MAC02 on 16/3/26.
//  Copyright © 2016年 MAC02. All rights reserved.
//

import Foundation

/**
 *  用来存储请求返回的所有响应数据
 */
public struct GlResponse<Value, Error: ErrorType> {
    /// 发送给服务器的请求
    public let request: NSURLRequest?
    
    /// 服务器的响应
    public let response: NSHTTPURLResponse?
    
    /// 服务器返回的数据
    public let data: NSData?
    
    /// 响应的序列化
    public let result: GlResult<Value, Error>
    
    /// The timeline of the complete lifecycle of the `Request`.
    public let timeline: GlTimeline
    
    public init(
        request: NSURLRequest?,
        response: NSHTTPURLResponse?,
        data: NSData?,
        result: GlResult<Value, Error>,
        timeline: GlTimeline = GlTimeline())
    {
        self.request = request
        self.response = response
        self.data = data
        self.result = result
        self.timeline = timeline
    }
}

// MARK: -  增加description属性，代表错误描述

extension GlResponse: CustomStringConvertible {
    /// The textual representation used when written to an output stream, which includes whether the result was a
    /// success or failure.
    public var description: String {
        return result.debugDescription
    }
}

// MARK: - CustomDebugStringConvertible

extension GlResponse: CustomDebugStringConvertible {
    /// The debug textual representation used when written to an output stream, which includes the URL request, the URL
    /// response, the server data and the response serialization result.
    public var debugDescription: String {
        var output: [String] = []
        
        output.append(request != nil ? "[Request]: \(request!)" : "[Request]: nil")
        output.append(response != nil ? "[Response]: \(response!)" : "[Response]: nil")
        output.append("[Data]: \(data?.length ?? 0) bytes")
        output.append("[Result]: \(result.debugDescription)")
        output.append("[Timeline]: \(timeline.debugDescription)")
        
        return output.joinWithSeparator("\n")
    }
}
