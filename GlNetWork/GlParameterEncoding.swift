//
//  GlParameterEncoding.swift
//  Swift2Demo
//
//  Created by MAC02 on 16/3/16.
//  Copyright © 2016年 MAC02. All rights reserved.
//

import Foundation

public enum GlMethod: String {
    case OPTIONS, GET, HEAD, POST, PUT, PATCH, DELETE, TRACE, CONNECT
}

public enum GlParameterEncoding {
    case URL
    case URLEncodedInURL
    case JSON
    case PropertyList(NSPropertyListFormat, NSPropertyListWriteOptions)
    case Custom((URLRequestConvertible, [String: AnyObject]?) -> (NSMutableURLRequest,NSError?))
//    case Custom((URLRequestConvertible, [String: AnyObject]?) -> (NSMutableURLRequest, NSError?))
    
    /**
     将参数压入请求
     
     - parameter URLRequest: The request to have parameters applied.
     - parameter parameters: The parameters to apply.
     
     - returns: 一个元组包含请求结构体和错误
     */
    public func encode(
        URLRequest: URLRequestConvertible,
        parameters: [String: AnyObject]?)
        -> (NSMutableURLRequest, NSError?)
    {
        var mutableURLRequest = URLRequest.URLRequest
        
        guard let parameters = parameters else { return (mutableURLRequest, nil) }
        
        var encodingError: NSError? = nil
        
        switch self {
        case .URL, .URLEncodedInURL:
            func query(parameters: [String: AnyObject]) -> String {
                var components: [(String, String)] = []
                
                for key in parameters.keys.sort(<) {
                    let value = parameters[key]!
                    components += queryComponents(key, value)
                }
                
                return (components.map { "\($0)=\($1)" } as [String]).joinWithSeparator("&")
            }
            
            func encodesParametersInURL(method: GlMethod) -> Bool {
                switch self {
                case .URLEncodedInURL:
                    return true
                default:
                    break
                }
                
                switch method {
                case .GET, .HEAD, .DELETE:
                    return true
                default:
                    return false
                }
            }
            
            if let method = GlMethod(rawValue: mutableURLRequest.HTTPMethod) where encodesParametersInURL(method) {//如果是get请求
                if let
                    URLComponents = NSURLComponents(URL: mutableURLRequest.URL!, resolvingAgainstBaseURL: false)
                    where !parameters.isEmpty
                {
                    let percentEncodedQuery = (URLComponents.percentEncodedQuery.map { $0 + "&" } ?? "") + query(parameters)
                    URLComponents.percentEncodedQuery = percentEncodedQuery
                    mutableURLRequest.URL = URLComponents.URL
                }
            } else {//post请求
                if mutableURLRequest.valueForHTTPHeaderField("Content-Type") == nil {
                    mutableURLRequest.setValue(
                        "application/x-www-form-urlencoded; charset=utf-8",
                        forHTTPHeaderField: "Content-Type"
                    )
                }
                
                mutableURLRequest.HTTPBody = query(parameters).dataUsingEncoding(
                    NSUTF8StringEncoding,
                    allowLossyConversion: false
                )
            }
        case .JSON:
            do {
                let options = NSJSONWritingOptions()
                let data = try NSJSONSerialization.dataWithJSONObject(parameters, options: options)
                
                if mutableURLRequest.valueForHTTPHeaderField("Content-Type") == nil {
                    mutableURLRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
                
                mutableURLRequest.HTTPBody = data//将参数存入消息体
            } catch {
                encodingError = error as NSError
            }
        case .PropertyList(let format, let options):
            do {
                let data = try NSPropertyListSerialization.dataWithPropertyList(
                    parameters,
                    format: format,
                    options: options
                )
                
                if mutableURLRequest.valueForHTTPHeaderField("Content-Type") == nil {
                    mutableURLRequest.setValue("application/x-plist", forHTTPHeaderField: "Content-Type")
                }
                
                mutableURLRequest.HTTPBody = data
            } catch {
                encodingError = error as NSError
            }
        case .Custom(let closure):
            (mutableURLRequest, encodingError) = closure(mutableURLRequest, parameters)
        }
        
        return (mutableURLRequest, encodingError)
    }
    
    /**
     Creates percent-escaped, URL encoded query string components from the given key-value pair using recursion.
     
     - parameter key:   The key of the query component.
     - parameter value: The value of the query component.
     
     - returns: The percent-escaped, URL encoded query string components.
     */
    public func queryComponents(key: String, _ value: AnyObject) -> [(String, String)] {
        var components: [(String, String)] = []
        
        if let dictionary = value as? [String: AnyObject] {
            for (nestedKey, value) in dictionary {
                components += queryComponents("\(key)[\(nestedKey)]", value)
            }
        } else if let array = value as? [AnyObject] {
            for value in array {
                components += queryComponents("\(key)[]", value)
            }
        } else {
            components.append((escape(key), escape("\(value)")))
        }
        
        return components
    }
    
    /**
     Returns a percent-escaped string following RFC 3986 for a query string key or value.
     
     RFC 3986 states that the following characters are "reserved" characters.
     
     - General Delimiters: ":", "#", "[", "]", "@", "?", "/"
     - Sub-Delimiters: "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "="
     
     In RFC 3986 - Section 3.4, it states that the "?" and "/" characters should not be escaped to allow
     query strings to include a URL. Therefore, all "reserved" characters with the exception of "?" and "/"
     should be percent-escaped in the query string.
     
     - parameter string: The string to be percent-escaped.
     
     - returns: The percent-escaped string.
     */
    public func escape(string: String) -> String {
        let generalDelimitersToEncode = ":#[]@" // does not include "?" or "/" due to RFC 3986 - Section 3.4
        let subDelimitersToEncode = "!$&'()*+,;="
        
        let allowedCharacterSet = NSCharacterSet.URLQueryAllowedCharacterSet().mutableCopy() as! NSMutableCharacterSet
        allowedCharacterSet.removeCharactersInString(generalDelimitersToEncode + subDelimitersToEncode)
        
        var escaped = ""
        
        //==========================================================================================================
        //
        //  Batching is required for escaping due to an internal bug in iOS 8.1 and 8.2. Encoding more than a few
        //  hundred Chinense characters causes various malloc error crashes. To avoid this issue until iOS 8 is no
        //  longer supported, batching MUST be used for encoding. This introduces roughly a 20% overhead. For more
        //  info, please refer to:
        //
        //      - https://github.com/Alamofire/Alamofire/issues/206
        //
        //==========================================================================================================
        
        if #available(iOS 8.3, OSX 10.10, *) {
            escaped = string.stringByAddingPercentEncodingWithAllowedCharacters(allowedCharacterSet) ?? string
        } else {
            let batchSize = 50
            var index = string.startIndex
            
            while index != string.endIndex {
                let startIndex = index
                let endIndex = index.advancedBy(batchSize, limit: string.endIndex)
                let range = Range(start: startIndex, end: endIndex)
                
                let substring = string.substringWithRange(range)
                
                escaped += substring.stringByAddingPercentEncodingWithAllowedCharacters(allowedCharacterSet) ?? substring
                
                index = endIndex
            }
        }
        
        return escaped
    }
}