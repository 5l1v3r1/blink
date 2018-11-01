////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2018 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////

#include <stdio.h>
#include "MCPSession.h"
#include "ios_system/ios_system.h"
//#include "ios_error.h"
#import "GeoManager.h"
#import <CoreLocation/CoreLocation.h>
#import <UserNotifications/UserNotifications.h>



NSString * _preauthorize_check_geo_premissions() {
  if (!CLLocationManager.locationServicesEnabled) {
    return @"Location services are disabled on this device.";
  }
  
  CLAuthorizationStatus status = CLLocationManager.authorizationStatus;
  switch(status) {
    case kCLAuthorizationStatusNotDetermined:
      return nil;
    case kCLAuthorizationStatusDenied:
      return @"Please allow blink to use geo in Settings.app.";
    case kCLAuthorizationStatusRestricted:
      return @"Geo services are restricted on this device.";
    case kCLAuthorizationStatusAuthorizedWhenInUse:
    case kCLAuthorizationStatusAuthorizedAlways:
      return @"Already authorized. Use `geo track` to start track location.";
      break;
  }
  
  return nil;
}

NSString * _prestart_check_geo_premissions() {
  if (!CLLocationManager.locationServicesEnabled) {
    return @"Location services are disabled on this device.";
  }
  
  CLAuthorizationStatus status = CLLocationManager.authorizationStatus;
  switch(status) {
    case kCLAuthorizationStatusNotDetermined:
      return @"Please run `geo authorize` command first.";
    case kCLAuthorizationStatusDenied:
      return @"Please allow blink to use geo in Settings.app.";
    case kCLAuthorizationStatusRestricted:
      return @"Geo services are restricted on this device.";
    case kCLAuthorizationStatusAuthorizedWhenInUse:
    case kCLAuthorizationStatusAuthorizedAlways:
      break;
  }

  return nil;
}

NSNumber * _parse_distance(NSString *str) {
  if (str == nil) {
    return nil;
  }
  
  str = [str lowercaseString];
  str = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  double scale = 1;
  if ([str hasSuffix:@"km"]) {
    scale = 1000;
  } else if ([str hasSuffix:@"mi"]) {
    scale = 1609.344;
  } else if ([str hasSuffix:@"ft"]) {
    scale = 0.3048;
  } else if ([str hasSuffix:@"m"]) {
    scale = 1;
  }
  
  return @(str.doubleValue * scale);
}

int geo_main(int argc, char *argv[]) {
  MCPSession *session = (__bridge MCPSession *)thread_context;
  TermDevice *device = session.device;
  
  NSString *usage = @"Usage: geo track | geo lock Nm | stop | authorize | current | last N";

  if (argc < 2) {
    [session.device writeOutLn:usage];
    return 1;
  }
  NSString *action = @(argv[1]);
  
  dispatch_sync(dispatch_get_main_queue(), ^{
    if ([@"track" isEqual:action] || [@"start" isEqual:action]) {
      NSString *reason = _prestart_check_geo_premissions();
      if (reason) {
        [session.device writeOutLn:reason];
        return;
      }
      if (GeoManager.shared.traking) {
        [device writeOutLn:@"Location tracking is already started."];
        return;
      }
      [[GeoManager shared] start];
      [device writeOutLn:@"Location tracking is started."];
    } else if ([@"lock" isEqual:action] && argc == 3) {
      NSNumber *distance = _parse_distance(@(argv[2]));
      if (distance == nil) {
        [session.device writeOutLn:@"Can't parse distance value. Example: 10m, 0.5km, 1mi"];
        return;
      }
      
      __block BOOL grantedNotifications = NO;
      
      dispatch_semaphore_t sema = dispatch_semaphore_create(0);
      
      UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
      [center requestAuthorizationWithOptions:
        (UNAuthorizationOptionAlert )
                            completionHandler:^(BOOL granted, NSError * _Nullable error) {
                              grantedNotifications = granted;
                              dispatch_semaphore_signal(sema);
                            }];
      
      dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
      NSString *reason = _prestart_check_geo_premissions();
      if (reason) {
        [session.device writeOutLn:reason];
        return;
      }
      if (GeoManager.shared.traking) {
        [device writeOutLn:@"Location tracking is already started."];
        return;
      }
      [[GeoManager shared] lockInDistance:distance];
      [device writeOutLn:[NSString stringWithFormat:@"Location locked within %@ meters.", distance]];
    } else if ([@"stop" isEqual:action]) {
      [[GeoManager shared] stop];
      [device writeOutLn:@"Location tracking is stopped."];
    } else if ([@"current" isEqual:action]) {
      [device writeOutLn:[GeoManager.shared currentJSON]];
    } else if ([@"last" isEqual:action] || [@"latest" isEqual:action]) {
      int n = 1;
      if (argc == 3) {
        NSString *nStr = [NSString stringWithUTF8String:argv[2]];
        n = [nStr intValue];
      }
      [device writeOutLn:[GeoManager.shared lastJSONN:n]];
    } else if ([@"authorize" isEqual:action]) {
      NSString *reason = _preauthorize_check_geo_premissions();
      if (reason) {
        [device writeOutLn:reason];
        return;
      }
      [[GeoManager shared] authorize];
    } else {
      [session.device writeOutLn:usage];
      return;
    }
  });

  return 0;
}
