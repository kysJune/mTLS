//
//  mTLSClient.h
//  mTLSClient
//
//  Created by Arjun Radhakrishnan on 12/18/23.
//

#ifndef mTLSClient_h
#define mTLSClient_h

#import <Foundation/Foundation.h>
@class IdentityProvider;
@class Client;
NS_ASSUME_NONNULL_BEGIN

@protocol ClientDelegate <NSObject>
-(void)didConnect:(Client * _Nonnull)client;
-(void)didDisconnect:(Client * _Nonnull)client withError:(NSError * _Nullable)error;
-(void)didReceive:(NSData * _Nonnull)data from:(Client * _Nonnull)client;
@end

@interface Client : NSObject
-(instancetype)initWith:(id<ClientDelegate>)delegate;
-(void)setIdentityProvider:(IdentityProvider *)identityProvider;
-(BOOL)connectTo:(NSString *)host andPort:(NSString *)port;
-(void)send:(NSData *)msg;
-(BOOL)stop;
@end

NS_ASSUME_NONNULL_END
#endif /* mTLSClient_h */
