//
//  GlResult.swift
//  Swift2Demo
//
//  Created by MAC02 on 16/3/26.
//  Copyright © 2016年 MAC02. All rights reserved.
//

import Foundation


/**
 Used to represent whether a request was successful or encountered an error.
 
 - Success: The request and all post processing operations were successful resulting in the serialization of the
 provided associated value.
 - Failure: The request encountered an error resulting in a failure. The associated values are the original data
 provided by the server as well as the error that caused the failure.
 */
public enum GlResult<Value, Error: ErrorType> {
    case Success(Value)
    case Failure(Error)
    
    /// Returns `true` if the result is a success, `false` otherwise.
    public var isSuccess: Bool {
        switch self {
        case .Success:
            return true
        case .Failure:
            return false
        }
    }
    
    /// Returns `true` if the result is a failure, `false` otherwise.
    public var isFailure: Bool {
        return !isSuccess
    }
    
    /// Returns the associated value if the result is a success, `nil` otherwise.
    public var value: Value? {
        switch self {
        case .Success(let value):
            return value
        case .Failure:
            return nil
        }
    }
    
    /// Returns the associated error value if the result is a failure, `nil` otherwise.
    public var error: Error? {
        switch self {
        case .Success:
            return nil
        case .Failure(let error):
            return error
        }
    }
}

// MARK: - CustomStringConvertible

extension GlResult: CustomStringConvertible {
    /// The textual representation used when written to an output stream, which includes whether the result was a
    /// success or failure.
    public var description: String {
        switch self {
        case .Success:
            return "SUCCESS"
        case .Failure:
            return "FAILURE"
        }
    }
}

// MARK: - CustomDebugStringConvertible

extension GlResult: CustomDebugStringConvertible {
    /// The debug textual representation used when written to an output stream, which includes whether the result was a
    /// success or failure in addition to the value or error.
    public var debugDescription: String {
        switch self {
        case .Success(let value):
            return "SUCCESS: \(value)"
        case .Failure(let error):
            return "FAILURE: \(error)"
        }
    }
}
