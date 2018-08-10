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

#include <openssl/bio.h>
#include <openssl/bn.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rsa.h>
#include <openssl/dsa.h>
#include <openssl/ec.h>
#include <openssl/ecdsa.h>
#include <libssh/callbacks.h>


#import "BKPubKey.h"
#import "UICKeyChainStore/UICKeyChainStore.h"

#import "BlinkPaths.h"



NSMutableArray *Identities;

static UICKeyChainStore *Keychain = nil;

@implementation Pki {
  ssh_key _ssh_key;
}

int __ssh_auth_callback (const char *prompt, char *buf, size_t len,
                                  int echo, int verify, void *userdata) {
  return 0;
}

- (Pki *)initFromPrivateKey:(NSString *)privateKey
{
  self = [super init];

  int rc = ssh_pki_import_privkey_base64(privateKey.UTF8String, NULL, __ssh_auth_callback, (__bridge void *)self, &_ssh_key);
  
  if (rc != SSH_OK) {
    return nil;
  }
  return self;
}

- (Pki *)initRSAWithLength:(int)bits
{
  self = [super init];
  
  int rc = ssh_pki_generate(SSH_KEYTYPE_RSA, bits, &_ssh_key);
  if (rc != SSH_OK) {
    return nil;
  }
  
  return self;
}

- (NSString *)privateKey
{
  ssh_string blob = NULL;
  ssh_pki_export_privkey_blob(_ssh_key, NULL, NULL, NULL, &blob);
  
  NSString *key = [[NSString alloc] initWithBytes:ssh_string_data(blob) length:ssh_string_len(blob) encoding:NSUTF8StringEncoding];
  
  ssh_string_burn(blob);
  ssh_string_free(blob);
  
  return key;
}

// Generate OpenSSH or PEM public key
- (NSString *)publicKeyWithComment:(NSString*)comment
{
  ssh_key pubkey = NULL;
  int rc = ssh_pki_export_privkey_to_pubkey(_ssh_key, &pubkey);
  if (rc != SSH_OK) {
    return nil;
  }
  char *buf = NULL;
  rc = ssh_pki_export_pubkey_base64(pubkey, &buf);
  if (rc != SSH_OK) {
    ssh_key_free(pubkey);
    return nil;
  }
  NSString *key = @(buf);
  ssh_key_free(pubkey);
  
  NSString *commentedKey = [NSString stringWithFormat:@"%@ %@",key, comment];
  return commentedKey;
}

- (void)dealloc
{
  if (_ssh_key) {
    ssh_key_free(_ssh_key);
    _ssh_key = NULL;
  }
}
@end

@implementation BKPubKey {
  NSString *_privateKeyRef;
  NSString *_publicKey;
}

+ (void)initialize
{
  // Maintain compatibility with previous version of the class
  [NSKeyedUnarchiver setClass:self forClassName:@"PKCard"];
  Keychain = [UICKeyChainStore keyChainStoreWithService:@"sh.blink.pkcard"];
}

+ (instancetype)withID:(NSString *)ID
{
  // Find the ID and return it.
  for (BKPubKey *i in Identities) {
    if ([i->_ID isEqualToString:ID]) {
      return i;
    }
  }

  return nil;
}

+ (NSMutableArray *)all
{
  return Identities;
}

+ (BOOL)saveIDS
{
  // Save IDs to file
  return [NSKeyedArchiver archiveRootObject:Identities toFile:[BlinkPaths blinkKeysFile]];
}

+ (void)loadIDS
{
  // Load IDs from file
  if ((Identities = [NSKeyedUnarchiver unarchiveObjectWithFile:[BlinkPaths blinkKeysFile]]) == nil) {
    // Initialize the structure if it doesn't exist, with a default id_rsa key
    Identities = [[NSMutableArray alloc] init];
    Pki *defaultKey = [[Pki alloc] initRSAWithLength:4096];
    [self saveCard:@"id_rsa" privateKey:defaultKey.privateKey publicKey:[defaultKey publicKeyWithComment:@""]];
  }
}

+ (id)saveCard:(NSString *)ID privateKey:(NSString *)privateKey publicKey:(NSString *)publicKey
{
  if (!privateKey || !publicKey) {
    return nil;
  }
  // Save privateKey to storage
  // If the card already exists, then it is replaced
  NSString *privateKeyRef = [ID stringByAppendingString:@".pem"];
  NSError *error;
  if (![Keychain setString:privateKey forKey:privateKeyRef error:&error]) {
    return nil;
  }

  BKPubKey *card = [BKPubKey withID:ID];
  if (!card) {
    card = [[BKPubKey alloc] initWithID:ID privateKeyRef:privateKeyRef publicKey:publicKey];
    [Identities addObject:card];
  } else {
    card->_privateKeyRef = privateKeyRef;
    card->_publicKey = publicKey;
  }

  if (![BKPubKey saveIDS]) {
    // This should never fail, but it is kept for testing purposes.
    return nil;
  }

  return card;
}

+ (NSInteger)count
{
  return [Identities count];
}

- (id)initWithCoder:(NSCoder *)coder
{
  _ID = [coder decodeObjectForKey:@"ID"];
  _privateKeyRef = [coder decodeObjectForKey:@"privateKeyRef"];
  _publicKey = [coder decodeObjectForKey:@"publicKey"];

  return [self initWithID:_ID privateKeyRef:_privateKeyRef publicKey:_publicKey];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:_ID forKey:@"ID"];
  [coder encodeObject:_privateKeyRef forKey:@"privateKeyRef"];
  [coder encodeObject:_publicKey forKey:@"publicKey"];
}

- (id)initWithID:(NSString *)ID privateKeyRef:(NSString *)privateKeyRef publicKey:(NSString *)publicKey
{
  self = [self init];
  if (self == nil)
    return nil;

  _ID = ID;
  _privateKeyRef = privateKeyRef;
  _publicKey = publicKey;

  return self;
}

- (NSString *)publicKey
{
  return _publicKey;
}

- (NSString *)privateKey
{
  return [Keychain stringForKey:_privateKeyRef];
}

// UIActivityItemSource methods
- (id)activityViewControllerPlaceholderItem:(UIActivityViewController *)activityViewController
{
  return _publicKey;
}

- (id)activityViewController:(UIActivityViewController *)activityViewController itemForActivityType:(UIActivityType)activityType
{
  if ([activityType  isEqualToString:UIActivityTypeMail] || [activityType isEqualToString:UIActivityTypeAirDrop]) {
    // Create a file to return if sharing through Mail or AirDrop
    NSString *tempFilename = [NSString stringWithFormat:@"%@.pub", _ID];
    NSString *publicKeyString = _publicKey;
    
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingString:tempFilename]];
    NSData *data = [publicKeyString dataUsingEncoding:NSUTF8StringEncoding];
    
    [data writeToURL:url atomically:NO];
    
    [activityViewController setCompletionWithItemsHandler:^(NSString *activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
      // Delete the file when
      NSError *errorBlock;
      if([[NSFileManager defaultManager] removeItemAtURL:url error:&errorBlock] == NO) {
        NSLog(@"Error deleting temporary public key file %@",errorBlock);
        return;
      }
    }];
    
    return url;
  }
  return _publicKey;
}

- (NSString *)activityViewController:(UIActivityViewController *)activityViewController
              subjectForActivityType:(UIActivityType)activityType
{
  return [NSString stringWithFormat:@"Blink Public Key: %@", _ID];
}

- (NSString *)activityViewController:(UIActivityViewController *)activityViewController dataTypeIdentifierForActivityType:(UIActivityType)activityType
{
  return @"public.text";
}

@end
