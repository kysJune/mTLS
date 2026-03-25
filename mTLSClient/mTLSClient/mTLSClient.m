//
//  mTLSClient.m
//  mTLSClient
//
//  Created by Arjun Radhakrishnan on 12/18/23.
//

#import <Foundation/Foundation.h>
#import "mTLSClient.h"
#import <Network/Network.h>
#import "IdentityProvider.h"
#import <dispatch/dispatch.h>

@interface Client ()
{
    SecCertificateRef anchorCert;
}
@property (nonatomic) nw_connection_t conn;
@property (nonatomic) IdentityProvider *provider;
@property (nonatomic,weak) id<ClientDelegate> delegate;
@property (nonatomic) BOOL isConnected;
@property (nonatomic) dispatch_queue_t connectionQueue;
@end


@implementation Client

-(void)setIdentityProvider:(IdentityProvider *)identityProvider {
    self.provider = identityProvider;
}

-(BOOL)stop {
    self.isConnected = FALSE;
    
    if (self.conn == nil) {
        NSLog(@"No active connection to disconnect");
        return FALSE;
    }
    
    NSLog(@"cancel connection");
    nw_connection_cancel(self.conn);
    return TRUE;
}

-(BOOL)connectTo:(NSString *)host andPort:(NSString *)port {
    
    if ([host length] < 1 || [port length] < 1) {
        NSLog(@"Either host or port is empty %@:%@",host,port);
        return false;
    }
    
    self.isConnected = FALSE;
    const char *_host =  [host cStringUsingEncoding:NSUTF8StringEncoding];
    const char *_port =  [port cStringUsingEncoding:NSUTF8StringEncoding];
    
    nw_endpoint_t endpoint =  nw_endpoint_create_host(_host, _port);
    nw_parameters_t parameters =  nw_parameters_create_secure_tcp(^(nw_protocol_options_t  _Nonnull options) {
        sec_protocol_options_t sec_options =  nw_tls_copy_sec_protocol_options(options);
        
        sec_protocol_options_set_verify_block(sec_options, ^(sec_protocol_metadata_t  _Nonnull metadata, sec_trust_t  _Nonnull trust_ref, sec_protocol_verify_complete_t  _Nonnull complete) {
            SecTrustRef trustRef =  sec_trust_copy_ref(trust_ref);
            if (trustRef == NULL) {
                complete(true);
                return;
            }
            
            CFArrayRef anchorCerts = CFArrayCreate(NULL, (const void **)&self->anchorCert, 1, NULL);
            SecTrustSetAnchorCertificates(trustRef, anchorCerts);
            
            SecPolicyRef policy = SecPolicyCreateSSL(true, NULL);
            CFArrayRef policies =  CFArrayCreate(kCFAllocatorDefault, (const void **)&policy, 1, NULL);
            SecTrustSetPolicies(trustRef, policies);
            
            CFErrorRef trustError;
            BOOL __unused trusted = SecTrustEvaluateWithError (trustRef, &trustError);
            if (trustError != NULL) {
                NSError *error = (__bridge_transfer NSError*)trustError;
                if (error.code != errSecInvalidExtendedKeyUsage) {
                    complete(false);
                    return;
                } else {
                    NSLog(@"Ignoring key usage error");
                }
            }
            
            CFRelease(anchorCerts);
            CFRelease(policies);
            CFRelease(policy);
            
            complete(true);
        }, self.connectionQueue);
        
        sec_protocol_options_set_challenge_block(sec_options, ^(sec_protocol_metadata_t  _Nonnull metadata, sec_protocol_challenge_complete_t  _Nonnull complete) {
            
            NSLog(@"Got cert request from server");
            __block SecIdentityRef creds = NULL;
            sec_protocol_metadata_access_distinguished_names(metadata, ^(dispatch_data_t  _Nonnull distinguished_name) {
                if (creds != NULL) {
                    NSLog(@"Already have creds for cert request");
                    return;
                }
                SecIdentityRef identity = [[self provider] findIdentifyFor:distinguished_name];
                if (identity != NULL) {
                    NSLog(@"Found cread (identity) for cert request");
                    creds = identity;
                }
                
            });
            
            sec_identity_t identity = sec_identity_create(creds);
            complete(identity);
        }, self.connectionQueue);
        
    }, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    
    //    nw_parameters_t tcpp =  nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    self.conn =  nw_connection_create(endpoint, parameters);
    
    nw_connection_set_state_changed_handler(self.conn, ^(nw_connection_state_t state, nw_error_t  _Nullable error) {
        switch (state) {
                
            case nw_connection_state_ready:
                NSLog(@"connection state : ready");
                self.isConnected = TRUE;
                [self.delegate didConnect:self];
                [self read];
                break;
            case nw_connection_state_preparing:
                NSLog(@"connection state : preparing");
                break;
            default:
                NSLog(@"connection state : %u",state);
                self.isConnected = FALSE;
                NSError *conError;
                if (error != nil) {
                    
                    nw_error_domain_t errorDomain = nw_error_get_error_domain(error);
                    int code = nw_error_get_error_code(error);
                    NSString *domain = @"unknown";
                    switch (errorDomain) {
                        case nw_error_domain_dns:
                            domain = @"nw_error_domain_dns";
                            break;
                            
                        case nw_error_domain_posix:
                            domain = @"nw_error_domain_posix";
                            break;
                            
                        case nw_error_domain_tls:
                            domain = @"nw_error_domain_tls";
                            break;
                            
                        case nw_error_domain_invalid:
                            domain = @"nw_error_domain_invalid";
                            break;
                    }
                    
                    conError = [[NSError alloc] initWithDomain:domain
                                                          code:code
                                                      userInfo:NULL];
                }
                
                [self.delegate didDisconnect:self withError:conError];
        }
    });
    
    NSLog(@"Connecting to %@ : %@",host,port);
    
    nw_connection_set_queue(self.conn, self.connectionQueue);
    nw_connection_start(self.conn);
    return true;
}

-(void)read {
    
    nw_connection_receive(self.conn, 0, 1024, ^(dispatch_data_t  _Nullable content, nw_content_context_t  _Nullable context, bool is_complete, nw_error_t  _Nullable error) {
        
        if (error != nil) {
            NSLog(@"Error reading, closing connection");
            nw_connection_cancel(self.conn);
            return;
        }
        
        NSData *data = (NSData *)content;
        
        if (data.length > 0 ) {
            [self.delegate didReceive:data from:self];
        } else {
            NSLog(@"Empty read close conenction");
            nw_connection_cancel(self.conn);
            return;
        }
        
        if (self.isConnected) {
            [self read];
        }
    });
}

-(void)loadAnchorCertificate {
    NSURL *trustedCertURL = [[NSBundle mainBundle] URLForResource:@"ca2-cert" withExtension:@"der"];
    if (trustedCertURL == nil) {
        return;
    }
    
    NSData *trustedCertData = [[NSData alloc] initWithContentsOfURL:trustedCertURL];
    
    if (trustedCertData == nil || [trustedCertData length] < 1) {
        return;
    }
    
    self->anchorCert =  SecCertificateCreateWithData(kCFAllocatorDefault, (CFDataRef)trustedCertData);
    
}
- (nonnull instancetype)initWith:(nonnull id<ClientDelegate>)delegate {
    
    self = [super init];
    if (self) {
        self.delegate = delegate;
        self.connectionQueue = dispatch_queue_create("com.conenction.queue", NULL);
        [self loadAnchorCertificate];
    }
    return self;
}

- (void)send:(nonnull NSData *)msg {
    
    dispatch_data_t data =  dispatch_data_create(msg.bytes, msg.length, dispatch_get_main_queue(), ^{});
    nw_connection_send(self.conn, data, NW_CONNECTION_DEFAULT_STREAM_CONTEXT, false, ^(nw_error_t  _Nullable error) {
        if (error != nil) {
            NSLog(@"error sending to server, closing connection");
            nw_connection_cancel(self.conn);
            return;
        }
    });
}

@end
