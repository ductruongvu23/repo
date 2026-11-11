// clang -fobjc-arc -Wall -Werror -framework Foundation CrashLog.m tests/CrashLogTests.m -o t && ./t
#import "../CrashLog.h"

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

static NSString *const JB = @"/private/preboot/1A2B3C/dopamine-AbCdEf/procursus";

// A .ips as iOS 15 writes it: a one-line JSON header, then the JSON report.
static NSData *IPS(NSString *bugType, NSDictionary *body) {
    NSDictionary *header = @{@"bug_type": bugType, @"name": body[@"procName"] ?: @"header-name"};
    NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:header options:0 error:nil] mutableCopy];
    [data appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [data appendData:[NSJSONSerialization dataWithJSONObject:body options:NSJSONWritingPrettyPrinted error:nil]];
    return data;
}

static NSDictionary *Frame(NSInteger image) { return @{@"imageIndex": @(image), @"imageOffset": @4096}; }
static NSDictionary *Image(NSString *path) { return @{@"path": path, @"name": path.lastPathComponent}; }
static NSDate *At(double seconds) { return [NSDate dateWithTimeIntervalSince1970:seconds]; }

static CrashLog *Parse(NSString *bugType, NSDictionary *body, NSDate *date) {
    return [CrashLog logWithData:IPS(bugType, body) path:@"/tmp/test.ips" date:date];
}

int main(void) {
    @autoreleasepool {
        NSArray *images = @[
            Image(@"/System/Library/CoreServices/SpringBoard.app/SpringBoard"),                       // 0
            Image(@"/usr/lib/libobjc.A.dylib"),                                                        // 1
            Image([JB stringByAppendingString:@"/usr/lib/libellekit.dylib"]),                          // 2 plumbing
            Image([JB stringByAppendingString:@"/usr/lib/TweakInject/BadTweak.dylib"]),                // 3
            Image([JB stringByAppendingString:@"/usr/lib/TweakInject/Bystander.dylib"]),               // 4
            Image([JB stringByAppendingString:@"/Library/Frameworks/Cephei.framework/Cephei"]),        // 5 library
            Image([JB stringByAppendingString:@"/Library/PreferenceBundles/FooPrefs.bundle/FooPrefs"]), // 6
            Image(@"/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"),              // 7
        ];

        // 1. SpringBoard segfault inside a hook: blame the tweak under ElleKit, ignore other threads.
        NSDictionary *springBoardCrash = @{
            @"procName": @"SpringBoard",
            @"exception": @{@"type": @"EXC_BAD_ACCESS", @"signal": @"SIGSEGV", @"subtype": @"KERN_INVALID_ADDRESS at 0x10"},
            @"threads": @[
                @{@"frames": @[Frame(4)]},
                @{@"triggered": @YES, @"frames": @[Frame(1), Frame(2), Frame(3), Frame(4), Frame(0)]},
            ],
            @"usedImages": images,
        };
        CrashLog *sb = Parse(@"309", springBoardCrash, At(200));
        CHECK([sb.process isEqualToString:@"SpringBoard"]);
        CHECK(sb.crashedSpringBoard);
        CHECK([sb.exception isEqualToString:@"EXC_BAD_ACCESS (SIGSEGV)"]);
        CHECK([sb.reasons containsObject:@"KERN_INVALID_ADDRESS at 0x10"]);
        CHECK([sb.suspect isEqualToString:@"BadTweak"] && sb.suspectIsTweak);
        CHECK([sb.jailbreakCodeInStack isEqualToArray:(@[@"BadTweak", @"Bystander"])]);
        CHECK([sb.readableText containsString:@"Suspect: BadTweak (tweak)"]);
        CHECK([sb.readableText containsString:@"▶ BadTweak.dylib"]);

        // 2. Uncaught exception thrown through Cephei from a Settings pane: the origin is in
        //    lastExceptionBacktrace, the pane beats the shared library, and the hook on the
        //    crashed thread (Bystander) is not blamed. Crashed thread found via faultingThread.
        CrashLog *prefs = Parse(@"309", @{
            @"procName": @"Preferences",
            @"exception": @{@"type": @"EXC_CRASH", @"signal": @"SIGABRT"},
            @"asi": @{@"CoreFoundation": @[@"*** Terminating app due to uncaught exception 'NSInvalidArgumentException'"]},
            @"lastExceptionBacktrace": @[Frame(7), Frame(1), Frame(5), Frame(6)],
            @"faultingThread": @0,
            @"threads": @[@{@"frames": @[Frame(1), Frame(4), Frame(7)]}],
            @"usedImages": images,
        }, At(100));
        CHECK([prefs.suspect isEqualToString:@"FooPrefs"] && prefs.suspectIsTweak);
        CHECK(!prefs.crashedSpringBoard);
        CHECK([prefs.reasons.firstObject containsString:@"NSInvalidArgumentException"]);
        CHECK([prefs.jailbreakCodeInStack isEqualToArray:(@[@"Cephei", @"FooPrefs", @"Bystander"])]);

        // 3. Only a shared library on the stack: blame it, flagged as a library.
        CrashLog *lib = Parse(@"309", @{
            @"procName": @"backboardd",
            @"threads": @[@{@"triggered": @YES, @"frames": @[Frame(5), Frame(7)]}],
            @"usedImages": images,
        }, At(300));
        CHECK([lib.suspect isEqualToString:@"Cephei"] && !lib.suspectIsTweak);
        CHECK(lib.crashedSpringBoard);

        // 4. Tweaks loaded but not on the crashing stack: no suspect.
        CrashLog *clean = Parse(@"309", @{
            @"procName": @"MobileSafari",
            @"threads": @[@{@"triggered": @YES, @"frames": @[Frame(7), Frame(1)]}, @{@"frames": @[Frame(3)]}],
            @"usedImages": images,
        }, At(50));
        CHECK(clean && !clean.suspect);
        CHECK([clean.readableText containsString:@"Suspect: none"]);

        // 5. Not crash reports: Jetsam events, panics, garbage.
        CHECK(!Parse(@"298", springBoardCrash, At(1)));
        CHECK(!Parse(@"210", @{@"panicString": @"panic"}, At(1)));
        CHECK(![CrashLog logWithData:[@"not json\n{" dataUsingEncoding:NSUTF8StringEncoding] path:@"/tmp/x.ips" date:At(1)]);

        // 6. Malformed fields must not crash the parser; the header name is the fallback process.
        CrashLog *junk = Parse(@"309", @{
            @"threads": @[@{@"triggered": @YES, @"frames": @[@{@"imageIndex": @99}, @"junk", @{@"imageIndex": @-1}]}],
            @"usedImages": @"junk",
            @"asi": @{@"x": @"not an array"},
            @"exception": @[@"not a dict"],
        }, At(1));
        CHECK(junk && !junk.suspect && [junk.process isEqualToString:@"header-name"]);

        // 7. Ranking: SpringBoard crashes first, then crash count, then most recent.
        CrashLog *sbOlder = Parse(@"309", springBoardCrash, At(150));
        NSArray<Suspect *> *suspects = [Suspect suspectsFromLogs:@[lib, sb, sbOlder, prefs, clean]];
        CHECK([[suspects valueForKey:@"name"] isEqualToArray:(@[@"BadTweak", @"Cephei", @"FooPrefs"])]);
        CHECK(suspects[0].crashes == 2 && suspects[0].springBoardCrashes == 2);
        CHECK([suspects[0].lastSeen isEqualToDate:At(200)]);
        CHECK([suspects[0].summary isEqualToString:@"2 crashes · SpringBoard ×2"]);
        CHECK([suspects[2].summary isEqualToString:@"1 crash · Preferences ×1"]);

        // 8. Scanning: subfolders included, newest first, non-.ips and Jetsam skipped, duplicates and limit handled.
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"crashlog-test"];
        [fm removeItemAtPath:dir error:nil];
        [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"Retired"] withIntermediateDirectories:YES attributes:nil error:nil];
        NSArray *files = @[@[@"old.ips", @"309", @10], @[@"Retired/new.ips", @"309", @20],
                           @[@"jetsam.ips", @"298", @30], @[@"notes.txt", @"309", @40]];
        for (NSArray *file in files) {
            NSString *path = [dir stringByAppendingPathComponent:file[0]];
            [IPS(file[1], springBoardCrash) writeToFile:path atomically:YES];
            [fm setAttributes:@{NSFileModificationDate: At([file[2] doubleValue])} ofItemAtPath:path error:nil];
        }
        NSArray<CrashLog *> *scanned = [CrashLog scanDirectories:@[dir, dir] limit:10];
        CHECK(scanned.count == 2);
        CHECK([scanned.firstObject.path hasSuffix:@"Retired/new.ips"]);
        CHECK([[CrashLog scanDirectories:@[dir] limit:1].firstObject.path hasSuffix:@"Retired/new.ips"]);
        CHECK([CrashLog scanDirectories:@[@"/nonexistent"] limit:10].count == 0);
        [fm removeItemAtPath:dir error:nil];

        if (failures) {
            fprintf(stderr, "%d check(s) failed\n", failures);
            return 1;
        }
        puts("All CrashLog checks passed");
    }
    return 0;
}
