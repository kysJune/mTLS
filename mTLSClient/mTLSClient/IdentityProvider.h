//
//  IdentityProvider.h
//  mTLSClient
//
//  Created by Arjun Radhakrishnan on 12/18/23.
//

#ifndef IdentityProvider_h
#define IdentityProvider_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IdentityProvider : NSObject
-(NSInteger)loadIdentities;
-(SecIdentityRef _Nullable)findIdentifyFor:(dispatch_data_t)issuerName;
@end

NS_ASSUME_NONNULL_END

#endif /* IdentityProvider_h */
