//
//  SSHClient.h
//  Simple Viewer
//
//

#import <Foundation/Foundation.h>
@class Node;

NS_ASSUME_NONNULL_BEGIN

@interface SSHClient : NSObject

@property (nonatomic, strong) NSString *server;
@property (nonatomic, strong) NSString *user;
@property (nonatomic, strong) NSString *passphrase;
@property (nonatomic, strong) NSString *password;

- (BOOL) connect;


- (instancetype) initWithServer: (NSString *) server
                           user:(NSString *) user
                     passphrase:(NSString *) passphrase;

- (instancetype) initWithServer: (NSString *) server
                           user:(NSString *) user
                       password:(NSString *) password;
- (BOOL) fileExists: (NSString *)path;
- (NSArray<Node*> *) readDir: (NSString *) path;
- (NSInteger) uploadFile: (NSData *)data
               path: (NSString *)path
           progress:(void (^)(NSInteger)) progressBlock
completion: (void (^)(void)) completionBlock;


- (void) removeFolder: (NSString*) src;
- (void) copy: (NSString*) src
  destination: (NSString *) dest;
-(int) moveFile:(NSString*) file
          toPath:(NSString*) path;
- (NSInteger) download: (NSString *) path
         progress:(void (^)(NSInteger)) progressBlock
            completion: (nullable void(^)(NSData * _Nullable,  NSError * _Nullable)) completionBlock;
- (NSInteger) unlink: (NSString *) path;
- (void) stopTaskWithIdentifer: (NSInteger) identifer;
@end

NS_ASSUME_NONNULL_END
