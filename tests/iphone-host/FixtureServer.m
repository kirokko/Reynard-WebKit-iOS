// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded, loopback-only synthetic fixture. NEVER a proxy or a file server.
#import "FixtureServer.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

@interface FixtureServer ()
@property int socketFD;
@property dispatch_source_t source;
@property dispatch_queue_t queue;
@property NSMutableDictionary *hits;
@property NSUInteger active;
@end
@implementation FixtureServer
- (instancetype)init { if ((self = [super init])) { _socketFD = -1; _hits = [NSMutableDictionary new]; _queue = dispatch_queue_create("net.kirokko.fixture", DISPATCH_QUEUE_SERIAL); } return self; }
- (BOOL)start:(NSError **)error {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    int yes = 1;
    if (fd >= 0) setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in address = {0}; address.sin_len = sizeof(address); address.sin_family = AF_INET;
    address.sin_port = htons(8765); inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    if (fd < 0 || bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(fd, 8) != 0) {
        int code = errno; if (fd >= 0) close(fd);
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil]; return NO;
    }
    fcntl(fd, F_SETFL, O_NONBLOCK); self.socketFD = fd;
    self.source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, self.queue);
    __weak FixtureServer *weak = self;
    dispatch_source_set_event_handler(self.source, ^{
        FixtureServer *server = weak; if (!server) return;
        int client;
        while ((client = accept(fd, NULL, NULL)) >= 0) {
            if (server.active >= 8) { close(client); continue; }
            server.active++;
            fcntl(client, F_SETFL, fcntl(client, F_GETFL, 0) & ~O_NONBLOCK);
            int peer = client;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                [server serve:peer]; close(peer);
                dispatch_async(server.queue, ^{ server.active--; });
            });
        }
    });
    dispatch_source_set_cancel_handler(self.source, ^{ close(fd); });
    dispatch_resume(self.source); return YES;
}
- (NSDictionary *)snapshot {
    __block NSDictionary *value;
    dispatch_sync(self.queue, ^{ value = [[NSDictionary alloc] initWithDictionary:self.hits copyItems:YES]; });
    return value;
}
- (void)serve:(int)fd {
    struct timeval timeout = {3, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    int yes = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    NSMutableData *request = [NSMutableData new]; char bytes[2048];
    while (request.length < 8192) {
        ssize_t n = recv(fd, bytes, MIN(sizeof(bytes), 8192 - request.length), 0);
        if (n <= 0) return; [request appendBytes:bytes length:(NSUInteger)n];
        if ([request rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0, request.length)].location != NSNotFound) break;
    }
    NSString *head = [[NSString alloc] initWithData:request encoding:NSUTF8StringEncoding];
    NSString *first = [head componentsSeparatedByString:@"\r\n"].firstObject;
    NSArray *parts = [first componentsSeparatedByString:@" "];
    if (parts.count < 3 || ![parts[0] isEqual:@"GET"] || ![parts[1] hasPrefix:@"/port/"]) return;
    NSURLComponents *url = [NSURLComponents componentsWithString:[@"http://127.0.0.1:8765" stringByAppendingString:parts[1]]];
    NSString *path = url.path ?: @""; NSString *token = @"none";
    for (NSURLQueryItem *item in url.queryItems) if ([item.name isEqual:@"token"] && item.value.length <= 80) token = item.value;
    __block NSDictionary *counts;
    dispatch_sync(self.queue, ^{
        if (!self.hits[token]) { if (self.hits.count >= 128) [self.hits removeAllObjects]; self.hits[token] = [NSMutableDictionary new]; }
        NSMutableDictionary *counter = self.hits[token]; counter[path] = @([counter[path] unsignedIntegerValue] + 1); counts = [counter copy];
    });
    NSString *type = @"text/plain; charset=utf-8";
    NSData *body = [[@"REACHED_SERVER:" stringByAppendingString:path] dataUsingEncoding:NSUTF8StringEncoding];
    if ([path isEqual:@"/port/index.html"]) {
        type = @"text/html; charset=utf-8"; body = [NSData dataWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"fixture" withExtension:@"html"]];
    } else if ([path isEqual:@"/port/control.png"] || [path isEqual:@"/port/image-only.txt"]) {
        type = @"image/png"; body = [[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==" options:0];
    } else if ([path isEqual:@"/port/hits.json"]) {
        type = @"application/json"; body = [NSJSONSerialization dataWithJSONObject:counts options:0 error:nil];
    }
    if (!body) return;
    NSString *headers = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: %@\r\nContent-Length: %lu\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n", type, (unsigned long)body.length];
    NSMutableData *response = [[headers dataUsingEncoding:NSUTF8StringEncoding] mutableCopy]; [response appendData:body];
    NSUInteger sent = 0;
    while (sent < response.length) {
        ssize_t n = send(fd, (const char *)response.bytes + sent, response.length - sent, 0); if (n <= 0) break; sent += (NSUInteger)n;
    }
}
- (void)dealloc { if (_source) dispatch_source_cancel(_source); }
@end
