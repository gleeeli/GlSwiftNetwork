//
//  GlServerTrustPolicy.swift
//  Swift2Demo
//
//  Created by MAC02 on 16/3/16.
//  Copyright © 2016年 MAC02. All rights reserved.
//

import Foundation

public class GlServerTrustPolicyManager {
    public let policies: [String: GlServerTrustPolicy]
    
    public init(policies: [String: GlServerTrustPolicy]) {
        self.policies = policies
    }
    
    public func serverTrustPolicyForHost(host: String) -> GlServerTrustPolicy? {
        return policies[host]
    }
}
//给NSURLSession 添加属性
extension NSURLSession {
    private struct GlAssociatedKeys {
        static var ManagerKey = "NSURLSession.ServerTrustPolicyManager"
    }
    
    var glServerTrustPolicyManager: GlServerTrustPolicyManager? {
        get {
            return objc_getAssociatedObject(self, &GlAssociatedKeys.ManagerKey) as? GlServerTrustPolicyManager
        }
        set (manager) {
            objc_setAssociatedObject(self, &GlAssociatedKeys.ManagerKey, manager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
public enum GlServerTrustPolicy {
    case PerformDefaultEvaluation(validateHost: Bool)
    case PinCertificates(certificates: [SecCertificate], validateCertificateChain: Bool, validateHost: Bool)
    case PinPublicKeys(publicKeys: [SecKey], validateCertificateChain: Bool, validateHost: Bool)
    case DisableEvaluation
    case CustomEvaluation((serverTrust: SecTrust, host: String) -> Bool)
    
    
    public static func certificatesInBundle(bundle: NSBundle = NSBundle.mainBundle()) -> [SecCertificate] {
        var certificates: [SecCertificate] = []
        
        let paths = Set([".cer", ".CER", ".crt", ".CRT", ".der", ".DER"].map { fileExtension in
            bundle.pathsForResourcesOfType(fileExtension, inDirectory: nil)
            }.flatten())
        
        for path in paths {
            if let
                certificateData = NSData(contentsOfFile: path),
                certificate = SecCertificateCreateWithData(nil, certificateData)
            {
                certificates.append(certificate)
            }
        }
        
        return certificates
    }
    
    /**
     Returns all public keys within the given bundle with a `.cer` file extension.
     
     - parameter bundle: The bundle to search for all `*.cer` files.
     
     - returns: All public keys within the given bundle.
     */
    public static func publicKeysInBundle(bundle: NSBundle = NSBundle.mainBundle()) -> [SecKey] {
        var publicKeys: [SecKey] = []
        
        for certificate in certificatesInBundle(bundle) {
            if let publicKey = publicKeyForCertificate(certificate) {
                publicKeys.append(publicKey)
            }
        }
        
        return publicKeys
    }
    
    // MARK: - Evaluation
    
    /**
    Evaluates whether the server trust is valid for the given host.
    
    - parameter serverTrust: The server trust to evaluate.
    - parameter host:        The host of the challenge protection space.
    
    - returns: Whether the server trust is valid.
    */
    public func evaluateServerTrust(serverTrust: SecTrust, isValidForHost host: String) -> Bool {
        var serverTrustIsValid = false
        
        switch self {
        case let .PerformDefaultEvaluation(validateHost):
            let policy = SecPolicyCreateSSL(true, validateHost ? host as CFString : nil)
            SecTrustSetPolicies(serverTrust, [policy])
            
            serverTrustIsValid = trustIsValid(serverTrust)
        case let .PinCertificates(pinnedCertificates, validateCertificateChain, validateHost):
            if validateCertificateChain {
                let policy = SecPolicyCreateSSL(true, validateHost ? host as CFString : nil)
                SecTrustSetPolicies(serverTrust, [policy])
                
                SecTrustSetAnchorCertificates(serverTrust, pinnedCertificates)
                SecTrustSetAnchorCertificatesOnly(serverTrust, true)
                
                serverTrustIsValid = trustIsValid(serverTrust)
            } else {
                let serverCertificatesDataArray = certificateDataForTrust(serverTrust)
                let pinnedCertificatesDataArray = certificateDataForCertificates(pinnedCertificates)
                
                outerLoop: for serverCertificateData in serverCertificatesDataArray {
                    for pinnedCertificateData in pinnedCertificatesDataArray {
                        if serverCertificateData.isEqualToData(pinnedCertificateData) {
                            serverTrustIsValid = true
                            break outerLoop
                        }
                    }
                }
            }
        case let .PinPublicKeys(pinnedPublicKeys, validateCertificateChain, validateHost):
            var certificateChainEvaluationPassed = true
            
            if validateCertificateChain {
                let policy = SecPolicyCreateSSL(true, validateHost ? host as CFString : nil)
                SecTrustSetPolicies(serverTrust, [policy])
                
                certificateChainEvaluationPassed = trustIsValid(serverTrust)
            }
            
            if certificateChainEvaluationPassed {
                outerLoop: for serverPublicKey in GlServerTrustPolicy.publicKeysForTrust(serverTrust) as [AnyObject] {
                    for pinnedPublicKey in pinnedPublicKeys as [AnyObject] {
                        if serverPublicKey.isEqual(pinnedPublicKey) {
                            serverTrustIsValid = true
                            break outerLoop
                        }
                    }
                }
            }
        case .DisableEvaluation:
            serverTrustIsValid = true
        case let .CustomEvaluation(closure):
            serverTrustIsValid = closure(serverTrust: serverTrust, host: host)
        }
        
        return serverTrustIsValid
    }
    
    // MARK: - Private - Trust Validation
    
    private func trustIsValid(trust: SecTrust) -> Bool {
        var isValid = false
        
        var result = SecTrustResultType(kSecTrustResultInvalid)
        let status = SecTrustEvaluate(trust, &result)
        
        if status == errSecSuccess {
            let unspecified = SecTrustResultType(kSecTrustResultUnspecified)
            let proceed = SecTrustResultType(kSecTrustResultProceed)
            
            isValid = result == unspecified || result == proceed
        }
        
        return isValid
    }
    
    // MARK: - Private - Certificate Data
    
    private func certificateDataForTrust(trust: SecTrust) -> [NSData] {
        var certificates: [SecCertificate] = []
        
        for index in 0..<SecTrustGetCertificateCount(trust) {
            if let certificate = SecTrustGetCertificateAtIndex(trust, index) {
                certificates.append(certificate)
            }
        }
        
        return certificateDataForCertificates(certificates)
    }
    
    private func certificateDataForCertificates(certificates: [SecCertificate]) -> [NSData] {
        return certificates.map { SecCertificateCopyData($0) as NSData }
    }
    
    // MARK: - Private - Public Key Extraction
    
    private static func publicKeysForTrust(trust: SecTrust) -> [SecKey] {
        var publicKeys: [SecKey] = []
        
        for index in 0..<SecTrustGetCertificateCount(trust) {
            if let
                certificate = SecTrustGetCertificateAtIndex(trust, index),
                publicKey = publicKeyForCertificate(certificate)
            {
                publicKeys.append(publicKey)
            }
        }
        
        return publicKeys
    }
    
    private static func publicKeyForCertificate(certificate: SecCertificate) -> SecKey? {
        var publicKey: SecKey?
        
        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        let trustCreationStatus = SecTrustCreateWithCertificates(certificate, policy, &trust)
        
        if let trust = trust where trustCreationStatus == errSecSuccess {
            publicKey = SecTrustCopyPublicKey(trust)
        }
        
        return publicKey
    }


}