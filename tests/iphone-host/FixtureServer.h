// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
@interface FixtureServer : NSObject
- (BOOL)start:(NSError **)error;
- (NSDictionary *)snapshot;
@end
