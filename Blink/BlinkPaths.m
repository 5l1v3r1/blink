//
//  BlinkPaths.m
//  Blink
//
//  Created by Yury Korolev on 5/14/18.
//  Copyright © 2018 Carlos Cabañero Projects SL. All rights reserved.
//

#import "BlinkPaths.h"

@implementation BlinkPaths

+ (NSString *)documents
{
  return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
}

+ (NSString *)historyFile
{
  return [[self documents] stringByAppendingPathComponent:@".blink_history"];
}

@end
