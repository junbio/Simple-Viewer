//
//  SSHClient.m
//  Simple Viewer
//
//

#import "SSHClient.h"
#import "Simple_Viewer-Swift.h"
#include <libssh/sftp.h>

#include <string.h>


NSString* escapeString(NSString *str)
{
    return [str stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

int isSpecialPath(const char *path)
{
    return *path == '.';
}

@interface SSHClient ()
@property (nonatomic, strong) NSOperationQueue *queue;
@property (nonatomic, strong) NSMutableArray *pendingOperations;

@property (nonatomic, assign) NSInteger taskIdentifier;

@end

@interface SSHOperation : NSObject
@property (nonatomic, assign) BOOL stop;
@property (nonatomic, assign) NSInteger identifier;
@end

@implementation SSHOperation

@end

@implementation SSHClient
{
    ssh_session _session;
    sftp_session _sftp;
}

- (void) copy: (NSString*) src
  destination: (NSString *) dest
{
    ssh_channel channel;
    
    channel = ssh_channel_new(_session);
    
    ssh_channel_open_session(channel);
    
    size_t size = 32768;
    char *cmd = malloc(size);
    snprintf(cmd, size, "cp \"%s\" \"%s\"", [escapeString(src) UTF8String], [escapeString(dest) UTF8String]);
    ssh_channel_request_exec(channel, cmd);
    free(cmd);
    ssh_channel_close(channel);
    ssh_channel_free(channel);
}


- (void) removeFolder: (NSString*) src
{
    ssh_channel channel;
    
    channel = ssh_channel_new(_session);
    
    ssh_channel_open_session(channel);
    size_t size = 32768;
    char *cmd = malloc(size);
    snprintf(cmd, 32768, "rm -rf \"%s\"", [escapeString(src) UTF8String]);
    ssh_channel_request_exec(channel, cmd);
    free(cmd);
    ssh_channel_close(channel);
    ssh_channel_free(channel);
}


- (BOOL) connect
{
    _session = ssh_new();
    ssh_options_set(_session, SSH_OPTIONS_USER, [self.user cStringUsingEncoding:NSUTF8StringEncoding]);
    ssh_options_set(_session, SSH_OPTIONS_HOST, [self.server cStringUsingEncoding:NSUTF8StringEncoding]);

    ssh_connect(_session);
    if (self.password)
    {
        ssh_userauth_password(_session, [self.user UTF8String], [self.password UTF8String]);
    }  else {
        ssh_userauth_autopubkey(_session, [self.passphrase cStringUsingEncoding:NSUTF8StringEncoding]);
    }
 
    _sftp = sftp_new(_session);
    if (!_sftp){
        return NO;
    }
    sftp_init(_sftp);
    return YES;
    
}

- (BOOL) fileExists:(NSString *)path
{
    sftp_attributes attributes= sftp_stat(_sftp, [path UTF8String]);
    

    return attributes!=NULL;
}
- (int) move: (NSString *) source
  destination: (NSString *) destination
{
    return sftp_rename(_sftp, [source cStringUsingEncoding:NSUTF8StringEncoding], [destination cStringUsingEncoding:NSUTF8StringEncoding]);
}

- (NSArray<Node*> *) readDir: (NSString *) path
{
    NSMutableArray<Node*> *files = [NSMutableArray new];
    sftp_dir dir = sftp_opendir(_sftp, [path cStringUsingEncoding:NSUTF8StringEncoding]);
    if (dir){
        sftp_attributes attr;
        while ((attr = sftp_readdir(_sftp, dir)) != NULL){
            size_t sz = attr->size;
            
            if (isSpecialPath(attr->name))
                continue;
            
            NSString *name = [NSString stringWithCString:attr->name encoding:NSUTF8StringEncoding];
            BOOL isFolder = attr->type == SSH_FILEXFER_TYPE_DIRECTORY;
            
            NSRange range = [name rangeOfString:@"." options:NSBackwardsSearch];
            NSString *extension = @"";
            if (range.location != NSNotFound){
                extension = [name substringFromIndex:range.location + 1];
            }
            NSString *url = [path stringByAppendingPathComponent:name];
            NSString * identifier;
            if (isFolder){
                identifier = (__bridge NSString*) kUTTypeFolder;
            } else {
                identifier = (__bridge_transfer  NSString *) UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef) extension, nil);
            }
            NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFileType:identifier];
            NSDate *created = [NSDate dateWithTimeIntervalSince1970:attr->createtime];
            NSDate *modified = [NSDate dateWithTimeIntervalSince1970:attr->mtime];
            
            NSURL *fileURL = [NSURL fileURLWithPath:url];
            url = [fileURL.absoluteString substringFromIndex:7];
            Node *node = [[Node alloc] initWithPath:url name:name created:created modified:modified icon:icon size:sz permissions:attr->permissions isFolder:isFolder];
            [files addObject:node];
            sftp_attributes_free(attr);
        }
        sftp_closedir(dir);

    }
    return files;
}

- (void) doUpload: (NSData *) data
               path: (NSString *) path
        operation: (SSHOperation *) operation
           progress: (void (^)(NSInteger)) progressBlock
       completion: (void(^)(void)) completionBlock
{
    sftp_file handle = sftp_open(self->_sftp, [path cStringUsingEncoding:NSUTF8StringEncoding], O_RDWR | O_CREAT, S_IRWXU);
    
    if (handle){
    
        int len = [data length];
        const char *bytes = [data bytes];
        int bytesWritten = 0;
        int n;
        while ((n = sftp_write(handle, bytes + bytesWritten, MIN(1024*16,len - bytesWritten))) > 0 && !operation.stop){
            bytesWritten += n;
            float done = (float) bytesWritten/(float)len;
            if (progressBlock){
                progressBlock(bytesWritten);
            }
            NSLog(@"%f", done);
        }
        if (!operation.stop)
            if (completionBlock){
                completionBlock();
            }
        sftp_close(handle);
    }
}

- (NSInteger) unlink: (NSString *) path
{
    return sftp_unlink(_sftp, [path cStringUsingEncoding:NSUTF8StringEncoding]);
}

- (NSInteger) uploadFile: (NSData *) data
               path: (NSString *) path
           progress: (void (^)(NSInteger)) progressBlock
         completion:  (void (^)(void) )  completionBlock
{
    
    SSHOperation *operation = [[SSHOperation alloc] init];
    operation.identifier = self.taskIdentifier++;
    operation.stop = NO;
    __typeof(self) __weak weakSelf = self;
    [self.pendingOperations addObject:operation];

    [self.queue addOperationWithBlock:^{
        [weakSelf doUpload:data path:path operation:operation progress:progressBlock completion:completionBlock];
        
        [weakSelf.pendingOperations removeObject:operation];
        
    }];
    return operation.identifier;
    
}

- (instancetype) initWithServer: (NSString *) server
                           user:(NSString *) user
                     password:(NSString *) password
{
    self = [super init];
    if (self){
        self.server = server;
        self.user = user;
        self.password = password;
        self.taskIdentifier = 0;
        self.queue = [[NSOperationQueue alloc] init];
        self.queue.maxConcurrentOperationCount = 1;
        self.pendingOperations = [NSMutableArray array];
    }
    return self;
}

- (instancetype) initWithServer: (NSString *) server
                           user:(NSString *) user
                     passphrase:(NSString *) passphrase
{
    self = [super init];
    if (self){
        self.server = server;
        self.user = user;
        self.passphrase = passphrase;
        self.taskIdentifier = 0;
        self.queue = [[NSOperationQueue alloc] init];
        self.queue.maxConcurrentOperationCount = 1;
        self.pendingOperations = [NSMutableArray array];
    }
    return self;
}

- (NSInteger) download: (NSString *) path
         progress:(void (^)(NSInteger)) progressBlock
       completion: (void(^)(NSData *, NSError*)) completionBlock
{
    // todo: download...
    
    __typeof(self) __weak weakSelf = self;
    
    SSHOperation *operation = [[SSHOperation alloc] init];
    operation.identifier = self.taskIdentifier++;
    operation.stop = NO;
    [self.pendingOperations addObject:operation];

    [self.queue addOperationWithBlock:^{
        NSError *error = nil;
        NSData *data = [weakSelf downloadFile:path operation:operation progress:progressBlock error:&error];
        completionBlock(data, error);
        [weakSelf.pendingOperations removeObject:operation];
    }];
    return operation.identifier;
}

- (void) stopTaskWithIdentifer: (NSInteger) identifer
{
    NSInteger idx = [self.pendingOperations indexOfObjectPassingTest:^BOOL(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        SSHOperation *task = obj;
        
        return task.identifier == identifer;
    }];
    if (idx != NSNotFound){
        SSHOperation *task = self.pendingOperations[idx];
        task.stop = YES;
    }
}

- (NSData *) downloadFile: (NSString *) path
                operation: (SSHOperation *) operation
                 progress: (void (^)(NSInteger)) progressBlock
                    error: (NSError * __autoreleasing *) error
{
    size_t bytesRead = 0;
    sftp_file handle = sftp_open(_sftp, [path cStringUsingEncoding:NSUTF8StringEncoding], O_RDONLY, 0);

    NSMutableData *data = [NSMutableData new];
    if (handle){
        size_t sz = 512 * 1024;
        char *buffer = malloc(sz);
        size_t len;
        while ((len = sftp_read(handle, buffer, sz)) > 0 && !operation.stop){
            // todo: read...
            [data appendBytes:buffer length:len];
            bytesRead += len;
            if (progressBlock){
                progressBlock(bytesRead);
            }
        }
        free(buffer);
        sftp_close(handle);
    }
    if (!operation.stop)
        return data;
    if (error){
        NSError *theError = [[NSError alloc] init];
        *error = theError;
    }
    return nil;
}

- (int) moveFile:(NSString*) file
          toPath:(NSString*) path
{
    return sftp_rename(_sftp, [file cStringUsingEncoding:NSUTF8StringEncoding], [path cStringUsingEncoding:NSUTF8StringEncoding]);
}

- (void) dealloc
{
    if (_sftp){
        sftp_free(_sftp);
    }
    if (_session){
        ssh_disconnect(_session);
        ssh_free(_session);
    }
}
@end
