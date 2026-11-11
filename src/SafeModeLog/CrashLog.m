#import "CrashLog.h"

// Crash reports are files on disk: only accept the JSON types we expect.
static id CLGet(id object, NSString *key, Class cls) {
    id value = [object isKindOfClass:NSDictionary.class] ? object[key] : nil;
    return [value isKindOfClass:cls] ? value : nil;
}

static id CLJSON(NSData *data) {
    return data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

// ".../TweakInject/BadTweak.dylib" -> "BadTweak", ".../FooPrefs.bundle/FooPrefs" -> "FooPrefs"
static NSString *CLName(NSString *path) {
    return path.lastPathComponent.stringByDeletingPathExtension;
}

// A tweak's own code: its injected dylib and its Settings pane.
static BOOL CLIsTweakCode(NSString *path) {
    return [path containsString:@"/DynamicLibraries/"] || [path containsString:@"/TweakInject/"]
        || [path containsString:@"/PreferenceBundles/"];
}

// Anything the jailbreak installed: /var/jb, its real path (/private/preboot/.../procursus), XinaA15's .jbroot.
static BOOL CLIsJailbreakCode(NSString *path) {
    return CLIsTweakCode(path) || [path hasPrefix:@"/var/jb/"] || [path hasPrefix:@"/private/var/jb/"]
        || [path containsString:@"/procursus/"] || [path containsString:@"/.jbroot-"];
}

// Hooking and injection plumbing sits in nearly every tweak stack, so blaming it is never useful.
static BOOL CLIsPlumbing(NSString *path) {
    static NSSet<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = [NSSet setWithArray:@[@"libellekit", @"ellekit", @"cydiasubstrate", @"libsubstrate",
            @"libsubstitute", @"libhooker", @"libblackjack", @"systemhook", @"tweakloader",
            @"tweakinject", @"libinjector", @"libroot", @"orion"]];
    });
    NSString *base = [path.lastPathComponent componentsSeparatedByString:@"."].firstObject.lowercaseString;
    return [path containsString:@"/basebin/"] || [path containsString:@"/ellekit/"] || [names containsObject:base];
}

static NSString *CLImagePath(id frame, NSArray *images) {
    NSNumber *index = CLGet(frame, @"imageIndex", NSNumber.class);
    if (!index || index.integerValue < 0 || (NSUInteger)index.integerValue >= images.count) return nil;
    id image = images[(NSUInteger)index.integerValue];
    return CLGet(image, @"path", NSString.class) ?: CLGet(image, @"name", NSString.class);
}

// The first tweak code in the stack (closest to the crash); a shared library only if no tweak code is there.
static NSString *CLBlame(NSArray *frames, NSArray *images, BOOL *isTweak, NSMutableOrderedSet *seen) {
    NSString *tweak = nil, *library = nil;
    for (id frame in frames) {
        NSString *path = CLImagePath(frame, images);
        if (!path || !CLIsJailbreakCode(path) || CLIsPlumbing(path)) continue;
        [seen addObject:CLName(path)];
        if (CLIsTweakCode(path)) {
            if (!tweak) tweak = CLName(path);
        } else if (!library) {
            library = CLName(path);
        }
    }
    *isTweak = tweak != nil;
    return tweak ?: library;
}

static void CLAppendFrames(NSMutableString *out, NSString *title, NSArray *frames, NSArray *images) {
    if (!frames.count) return;
    [out appendFormat:@"\n%@:\n", title];
    NSUInteger i = 0;
    for (id frame in frames) {
        NSString *path = CLImagePath(frame, images) ?: @"???";
        NSString *symbol = CLGet(frame, @"symbol", NSString.class);
        NSString *where = symbol
            ? [NSString stringWithFormat:@"%@ + %llu", symbol, [CLGet(frame, @"symbolLocation", NSNumber.class) unsignedLongLongValue]]
            : [NSString stringWithFormat:@"0x%llx", [CLGet(frame, @"imageOffset", NSNumber.class) unsignedLongLongValue]];
        BOOL mark = CLIsJailbreakCode(path) && !CLIsPlumbing(path);
        [out appendFormat:@"%2lu %@ %@ %@\n", (unsigned long)i++, mark ? @"▶" : @" ",
            [path.lastPathComponent stringByPaddingToLength:26 withString:@" " startingAtIndex:0], where];
    }
}

@implementation CrashLog

+ (instancetype)logWithData:(NSData *)data path:(NSString *)path date:(NSDate *)date {
    // iOS 15+ .ips: line 1 is a JSON header, the rest is the JSON report.
    NSRange newline = [data rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, data.length)];
    if (newline.location == NSNotFound) return nil;
    id header = CLJSON([data subdataWithRange:NSMakeRange(0, newline.location)]);
    // Jetsam events are the most numerous reports and never crashes: skip them before parsing the body.
    if ([CLGet(header, @"bug_type", NSString.class) isEqualToString:@"298"]) return nil;
    id body = CLJSON([data subdataWithRange:NSMakeRange(NSMaxRange(newline), data.length - NSMaxRange(newline))]);
    NSArray *threads = CLGet(body, @"threads", NSArray.class);
    if (!threads) return nil;

    CrashLog *log = [self new];
    log.path = path;
    log.date = date;
    log.process = CLGet(body, @"procName", NSString.class) ?: CLGet(header, @"name", NSString.class)
        ?: [path.lastPathComponent componentsSeparatedByString:@"-"].firstObject;

    NSDictionary *exception = CLGet(body, @"exception", NSDictionary.class);
    NSString *type = CLGet(exception, @"type", NSString.class);
    NSString *signal = CLGet(exception, @"signal", NSString.class);
    log.exception = type && signal ? [NSString stringWithFormat:@"%@ (%@)", type, signal] : (type ?: signal);

    NSMutableArray<NSString *> *reasons = [NSMutableArray array];
    NSString *subtype = CLGet(exception, @"subtype", NSString.class);
    if (subtype) [reasons addObject:subtype];
    for (id lines in [CLGet(body, @"asi", NSDictionary.class) allValues])
        for (id line in ([lines isKindOfClass:NSArray.class] ? lines : @[]))
            if ([line isKindOfClass:NSString.class]) [reasons addObject:line];
    for (id line in CLGet(CLGet(body, @"termination", NSDictionary.class), @"reasons", NSArray.class))
        if ([line isKindOfClass:NSString.class]) [reasons addObject:line];
    log.reasons = reasons;

    id crashed = nil;
    for (id thread in threads) {
        if ([CLGet(thread, @"triggered", NSNumber.class) boolValue]) { crashed = thread; break; }
    }
    NSNumber *faulting = CLGet(body, @"faultingThread", NSNumber.class);
    if (!crashed && faulting && faulting.integerValue >= 0 && (NSUInteger)faulting.integerValue < threads.count)
        crashed = threads[(NSUInteger)faulting.integerValue];

    NSArray *images = CLGet(body, @"usedImages", NSArray.class) ?: @[];
    NSArray *exceptionFrames = CLGet(body, @"lastExceptionBacktrace", NSArray.class) ?: @[];
    NSArray *crashedFrames = CLGet(crashed, @"frames", NSArray.class) ?: @[];

    // An uncaught exception's origin is only in lastExceptionBacktrace (the crashed thread
    // then just shows abort()), so look there first and fall back to the crashed thread.
    NSMutableOrderedSet<NSString *> *seen = [NSMutableOrderedSet orderedSet];
    BOOL isTweak = NO, crashedIsTweak = NO;
    NSString *suspect = CLBlame(exceptionFrames, images, &isTweak, seen);
    NSString *crashedSuspect = CLBlame(crashedFrames, images, &crashedIsTweak, seen);
    if (!suspect) {
        suspect = crashedSuspect;
        isTweak = crashedIsTweak;
    }
    log.suspect = suspect;
    log.suspectIsTweak = isTweak;
    log.jailbreakCodeInStack = seen.array;

    NSMutableString *text = [NSMutableString stringWithFormat:@"%@\n%@\n", log.process,
        [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle]];
    if (log.exception) [text appendFormat:@"Exception: %@\n", log.exception];
    for (NSString *reason in reasons) [text appendFormat:@"Reason: %@\n", reason];
    [text appendFormat:@"\nSuspect: %@\n", suspect
        ? [NSString stringWithFormat:@"%@ (%@)", suspect, isTweak ? @"tweak" : @"jailbreak library"]
        : @"none, no jailbreak code in the crashing stack"];
    if (seen.count) [text appendFormat:@"Jailbreak code in the stack: %@\n", [seen.array componentsJoinedByString:@", "]];
    CLAppendFrames(text, @"Last Exception Backtrace", exceptionFrames, images);
    CLAppendFrames(text, @"Crashed Thread", crashedFrames, images);
    log.readableText = text;
    return log;
}

- (BOOL)crashedSpringBoard {
    return [self.process isEqualToString:@"SpringBoard"] || [self.process isEqualToString:@"backboardd"];
}

+ (NSArray<NSString *> *)logDirectories {
    return @[@"/var/mobile/Library/Logs/CrashReporter",
             @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.osanalytics/DiagnosticReports"];
}

+ (NSArray<CrashLog *> *)scanDirectories:(NSArray<NSString *> *)dirs limit:(NSUInteger)limit {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableDictionary<NSString *, NSDate *> *files = [NSMutableDictionary dictionary];
    for (NSString *dir in dirs) {
        // Both folders may be the same folder behind a symlink; resolving dedupes them.
        NSString *root = dir.stringByResolvingSymlinksInPath;
        NSDirectoryEnumerator *e = [fm enumeratorAtPath:root];
        for (NSString *relative in e) {
            NSDate *date = e.fileAttributes[NSFileModificationDate];
            if (date && [relative.lastPathComponent containsString:@".ips"])
                files[[root stringByAppendingPathComponent:relative]] = date;
        }
    }
    NSArray<NSString *> *newestFirst = [files keysSortedByValueUsingComparator:^NSComparisonResult(NSDate *a, NSDate *b) {
        return [b compare:a];
    }];
    NSMutableArray<CrashLog *> *logs = [NSMutableArray array];
    for (NSString *path in newestFirst) {
        if (logs.count >= limit) break;
        @autoreleasepool {
            NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
            CrashLog *log = data ? [self logWithData:data path:path date:files[path]] : nil;
            if (log) [logs addObject:log];
        }
    }
    return logs;
}

@end

@implementation Suspect

+ (NSArray<Suspect *> *)suspectsFromLogs:(NSArray<CrashLog *> *)logs {
    NSMutableDictionary<NSString *, Suspect *> *byName = [NSMutableDictionary dictionary];
    for (CrashLog *log in logs) {
        if (!log.suspect) continue;
        Suspect *s = byName[log.suspect];
        if (!s) {  // logs are newest first, so the first one seen is the latest
            s = [Suspect new];
            s.name = log.suspect;
            s.isTweak = log.suspectIsTweak;
            s.lastSeen = log.date;
            s.processes = [NSCountedSet set];
            byName[log.suspect] = s;
        }
        s.crashes++;
        if (log.crashedSpringBoard) s.springBoardCrashes++;
        [s.processes addObject:log.process];
    }
    return [byName.allValues sortedArrayUsingComparator:^NSComparisonResult(Suspect *a, Suspect *b) {
        if (a.springBoardCrashes != b.springBoardCrashes)
            return a.springBoardCrashes > b.springBoardCrashes ? NSOrderedAscending : NSOrderedDescending;
        if (a.crashes != b.crashes) return a.crashes > b.crashes ? NSOrderedAscending : NSOrderedDescending;
        return [b.lastSeen compare:a.lastSeen];
    }];
}

- (NSString *)summary {
    NSArray<NSString *> *byCount = [self.processes.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSUInteger ca = [self.processes countForObject:a], cb = [self.processes countForObject:b];
        return ca == cb ? [a compare:b] : (ca > cb ? NSOrderedAscending : NSOrderedDescending);
    }];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *process in byCount)
        [parts addObject:[NSString stringWithFormat:@"%@ ×%lu", process, (unsigned long)[self.processes countForObject:process]]];
    return [NSString stringWithFormat:@"%lu crash%@ · %@", (unsigned long)self.crashes,
        self.crashes == 1 ? @"" : @"es", [parts componentsJoinedByString:@", "]];
}

@end
