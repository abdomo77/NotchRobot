// helper بيتحمّل جوه /usr/bin/perl عشان ياخد صلاحية MediaRemote (macOS 15.4+)
// NOTCHROBOT_MR=stream → يطبع JSON سطر كل ثانية
// NOTCHROBOT_MR=<رقم>  → يبعت أمر (2 = تشغيل/إيقاف، 4 = اللي بعده، 5 = اللي قبله)
// NOTCHROBOT_MR=seek:<ثواني> → يودّي الأغنية للثانية دي
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <unistd.h>
#import <objc/message.h>
#import <objc/runtime.h>

typedef Boolean (*SendCmdFn)(int, CFDictionaryRef);
typedef void (*SetElapsedFn)(double);

static NSString *lastArtId = @"";

// macOS 15.4+/26: MRMediaRemoteGetNowPlayingInfo بقت بترجع فاضي، فبنستخدم MRNowPlayingRequest
static id call(id target, const char *sel) {
    SEL s = sel_registerName(sel);
    if (!target || ![target respondsToSelector:s]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, s);
}

static void emit(void) {
    Class R = NSClassFromString(@"MRNowPlayingRequest");
    if (!R) return;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    id item = call(R, "localNowPlayingItem");
    NSDictionary *d = call(item, "nowPlayingInfo");
    if ([d isKindOfClass:[NSDictionary class]]) {
        if (d[@"kMRMediaRemoteNowPlayingInfoTitle"]) out[@"title"] = d[@"kMRMediaRemoteNowPlayingInfoTitle"];
        if (d[@"kMRMediaRemoteNowPlayingInfoArtist"]) out[@"artist"] = d[@"kMRMediaRemoteNowPlayingInfoArtist"];
        if (d[@"kMRMediaRemoteNowPlayingInfoDuration"]) out[@"duration"] = d[@"kMRMediaRemoteNowPlayingInfoDuration"];
        if (d[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]) out[@"elapsed"] = d[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
        NSNumber *rate = d[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
        if (rate) out[@"rate"] = rate;
        out[@"playing"] = @(rate.doubleValue > 0);
        NSDate *ts = d[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        if ([ts isKindOfClass:[NSDate class]]) out[@"timestamp"] = @([ts timeIntervalSince1970]);

        NSString *artId = d[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"] ?: @"";
        if (![artId isEqualToString:lastArtId]) {
            NSData *art = call(call(item, "artwork"), "imageData");
            if (!art) art = d[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
            if (art.length || artId.length == 0) {
                lastArtId = artId;
                out[@"artwork"] = art.length ? [art base64EncodedStringWithOptions:0] : @"";
            }
        }
    }
    id client = call(call(R, "localNowPlayingPlayerPath"), "client");
    NSString *bundle = call(client, "bundleIdentifier");
    if ([bundle isKindOfClass:[NSString class]]) out[@"bundle"] = bundle;

    NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
    if (json) { fwrite(json.bytes, 1, json.length, stdout); printf("\n"); fflush(stdout); }
}

__attribute__((constructor)) static void run(void) {
    const char *mode = getenv("NOTCHROBOT_MR");
    if (!mode) return;
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!h) exit(1);

    if (strncmp(mode, "seek:", 5) == 0) {
        SetElapsedFn seek = (SetElapsedFn)dlsym(h, "MRMediaRemoteSetElapsedTime");
        if (seek) seek(atof(mode + 5));
        usleep(100000);
        exit(0);
    }

    if (strcmp(mode, "stream") != 0) {
        SendCmdFn send = (SendCmdFn)dlsym(h, "MRMediaRemoteSendCommand");
        if (send) send(atoi(mode), NULL);
        usleep(100000);
        exit(0);
    }

    while (1) {
        if (getppid() == 1) exit(0); // التطبيق اتقفل
        @autoreleasepool { emit(); }
        usleep(1000000);
    }
}
