//
//  GlHttpManager.swift
//  Swift2Demo
//
//  Created by MAC02 on 16/3/16.
//  Copyright © 2016年 MAC02. All rights reserved.
//

import Foundation
public protocol URLStringConvertible {
    var URLString: String { get }
}
public protocol URLRequestConvertible {
    /// The URL request.
    var URLRequest: NSMutableURLRequest { get }
}
extension String: URLStringConvertible {
    public var URLString: String {
        return self
    }
}

extension NSURL: URLStringConvertible {
    public var URLString: String {
        return absoluteString
    }
}
extension NSURLComponents: URLStringConvertible {
    public var URLString: String {
        return URL!.URLString
    }
}
extension NSURLRequest: URLRequestConvertible {
    public var URLRequest: NSMutableURLRequest {
        return self.mutableCopy() as! NSMutableURLRequest
    }
}
public class GlHttpManager {

    class func request(method:GlMethod,_ URLString: URLStringConvertible,parameters: [String: AnyObject]? = nil,encoding: GlParameterEncoding = .URL,headers: [String: String]? = nil) -> GlRequest {
        
        return GlManager.shareInstance.request(method,URLString,parameters: parameters,
            encodeing:encoding,headers:headers)
    }

}

/**
 获取请求
 
 - parameter method:    get 或 post
 - parameter URLString: 请求的url
 - parameter headers:   请求头
 
 - returns: 请求 NSMutableURLRequest
 */
func URLRequest(method:GlMethod,
    _ URLString: URLStringConvertible,
    headers:[String: String]? = nil) -> NSMutableURLRequest
{
    let mutableURLRequest = NSMutableURLRequest(URL: NSURL(string: URLString.URLString)!)
    mutableURLRequest.HTTPMethod = method.rawValue //方法get post
    
    if let headers = headers {
        for(headerField,headerValue) in headers {
            mutableURLRequest.setValue(headerValue, forHTTPHeaderField: headerField)
        }
    }
    
    return mutableURLRequest
}



