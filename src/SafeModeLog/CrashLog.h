#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// One crash report (.ips) and the jailbreak code blamed for it.
@interface CrashLog : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *process;
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, copy, nullable) NSString *exception;  // "EXC_BAD_ACCESS (SIGSEGV)"
@property (nonatomic, copy) NSArray<NSString *> *reasons;    // subtype, abort message, watchdog reason
@property (nonatomic, copy, nullable) NSString *suspect;    // nil: no jailbreak code where it crashed
@property (nonatomic) BOOL suspectIsTweak;                   // NO: a shared library (Cephei, AltList...)
@property (nonatomic, copy) NSArray<NSString *> *jailbreakCodeInStack;
@property (nonatomic, copy) NSString *readableText;
@property (nonatomic, readonly) BOOL crashedSpringBoard;     // SpringBoard/backboardd: what triggers Safe Mode

// nil when the data is not a crash report (Jetsam events, panics, other diagnostics).
+ (nullable instancetype)logWithData:(NSData *)data path:(NSString *)path date:(NSDate *)date;
+ (NSArray<NSString *> *)logDirectories;
// Newest first.
+ (NSArray<CrashLog *> *)scanDirectories:(NSArray<NSString *> *)dirs limit:(NSUInteger)limit;
@end

// Crashes per blamed name. Names that crashed SpringBoard come first.
@interface Suspect : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL isTweak;
@property (nonatomic, strong) NSDate *lastSeen;
@property (nonatomic) NSUInteger crashes;
@property (nonatomic) NSUInteger springBoardCrashes;
@property (nonatomic, strong) NSCountedSet<NSString *> *processes;
@property (nonatomic, readonly) NSString *summary;           // "3 crashes · SpringBoard ×2, Preferences ×1"

+ (NSArray<Suspect *> *)suspectsFromLogs:(NSArray<CrashLog *> *)logs;  // logs newest first
@end

NS_ASSUME_NONNULL_END
