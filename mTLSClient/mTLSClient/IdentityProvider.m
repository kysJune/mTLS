//
//  IdentityProvider.m
//  mTLSClient
//
//  Created by Arjun Radhakrishnan on 12/18/23.
//

#import <Foundation/Foundation.h>
#import "IdentityProvider.h"

@interface IdentityProvider ()
@property (nonatomic) NSMutableDictionary *identities;
@end

@implementation IdentityProvider

-(NSInteger)loadIdentities {
    
    self.identities = [[NSMutableDictionary alloc] init];
    //NSArray *identityFileNames = @[@"client1",@"client2"];
    NSArray *identityFileNames = @[@"client1"]; //  error case testing
    for (NSString *name in identityFileNames) {
        NSURL *url = [[NSBundle mainBundle] URLForResource:name withExtension:@"p12"];
        
        if (url == nil) { continue;}
        NSData *data = [[NSData alloc] initWithContentsOfURL:url];
        
        if (data == nil || data.length == 0 ) { continue; }
        
        NSString *password = @"password";
        
        CFArrayRef rawItems = NULL;
        NSDictionary* options = @{ (id)kSecImportExportPassphrase : password };
        OSStatus status = SecPKCS12Import((__bridge CFDataRef)data,
                                          (__bridge CFDictionaryRef)options,
                                          &rawItems);
        
        if (status != errSecSuccess) {
            continue;
            
        }
        
        NSArray* items = (NSArray*)CFBridgingRelease(rawItems);
        NSDictionary* firstItem = nil;
        if ((status == errSecSuccess) && ([items count]>0)) {
            firstItem = items[0];
        }
        
        if (firstItem != nil) {
            SecIdentityRef identity = (SecIdentityRef)CFBridgingRetain(firstItem[(id)kSecImportItemIdentity]);
            SecCertificateRef certificate = NULL;
            OSStatus status = SecIdentityCopyCertificate(identity,
                                                         &certificate);
            
            if (status == errSecSuccess && certificate != NULL) {
                NSData *issuerNameDER = (__bridge_transfer NSData*)SecCertificateCopyNormalizedIssuerSequence(certificate);
                self.identities[issuerNameDER] = CFBridgingRelease(identity);
            }
            
            if (certificate) { CFRelease(certificate); }
        }
    }
    return self.identities.allKeys.count;
}

-(SecIdentityRef _Nullable)findIdentifyFor:(dispatch_data_t)issuerName {
    NSData *issuerNameDER = (NSData *)issuerName;
    SecIdentityRef identity = (__bridge SecIdentityRef)(self.identities[issuerNameDER]);
    return identity;
}
@end
