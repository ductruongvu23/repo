#import <UIKit/UIKit.h>
#import "CrashLog.h"

static NSString *DateText(NSDate *date) {
    return [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
}

// The readable summary of one crash, with a button to share the full original report.
@interface LogDetailController : UIViewController
- (instancetype)initWithLog:(CrashLog *)log;
@end

@implementation LogDetailController {
    CrashLog *_log;
}

- (instancetype)initWithLog:(CrashLog *)log {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _log = log;
        self.title = log.process;
    }
    return self;
}

- (void)loadView {
    UITextView *text = [UITextView new];
    text.editable = NO;
    text.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    text.text = _log.readableText;
    self.view = text;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share:)];
}

// Tweak developers want the full .ips, not the summary. Shared as text: share
// extensions are sandboxed and cannot open a file URL outside ours.
- (void)share:(UIBarButtonItem *)sender {
    NSString *raw = [NSString stringWithContentsOfFile:_log.path encoding:NSUTF8StringEncoding error:nil] ?: _log.readableText;
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[raw] applicationActivities:nil];
    sheet.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

// Root screen: suspects ranked, then every crash log. Also used for one suspect's crashes.
@interface LogListController : UITableViewController
@end

@implementation LogListController {
    NSArray<CrashLog *> *_logs;
    NSArray<Suspect *> *_suspects;
    NSString *_filter;  // set: only this suspect's crashes, no scanning
    BOOL _loaded;
}

- (instancetype)initWithSuspect:(Suspect *)suspect logs:(NSArray<CrashLog *> *)logs {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _filter = suspect.name;
        _logs = [logs filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"suspect == %@", suspect.name]];
        _loaded = YES;
        self.title = suspect.name;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (_filter) return;
    self.title = @"SafeModeLog";
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [self reload];
}

- (void)reload {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<CrashLog *> *logs = [CrashLog scanDirectories:CrashLog.logDirectories limit:300];
        NSArray<Suspect *> *suspects = [Suspect suspectsFromLogs:logs];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_logs = logs;
            self->_suspects = suspects;
            self->_loaded = YES;
            [self.refreshControl endRefreshing];
            [self.tableView reloadData];
        });
    });
}

- (BOOL)isSuspectSection:(NSInteger)section {
    return _suspects.count && section == 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _suspects.count ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self isSuspectSection:section] ? _suspects.count : _logs.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self isSuspectSection:section]) return @"Suspects";
    return _filter ? @"Crashes blamed on it" : @"Crash logs";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if ([self isSuspectSection:section])
        return @"Red: crashed SpringBoard or backboardd, the crashes that put the device into Safe Mode. "
               @"A suspect is the first tweak code found where the crash happened: usually the cause, not always.";
    if (!_loaded) return @"Reading crash logs…";
    if (_logs.count) return nil;
    NSMutableString *text = [NSMutableString stringWithString:@"No crash logs found. Searched:"];
    for (NSString *dir in CrashLog.logDirectories)
        [text appendFormat:@"\n%@%@", dir, [NSFileManager.defaultManager isReadableFileAtPath:dir] ? @"" : @" (missing or not readable)"];
    return text;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
    UIListContentConfiguration *content = UIListContentConfiguration.subtitleCellConfiguration;
    BOOL safeMode;
    if ([self isSuspectSection:indexPath.section]) {
        Suspect *suspect = _suspects[indexPath.row];
        content.text = suspect.isTweak ? suspect.name : [suspect.name stringByAppendingString:@" (library)"];
        content.secondaryText = [NSString stringWithFormat:@"%@\nLast: %@", suspect.summary, DateText(suspect.lastSeen)];
        safeMode = suspect.springBoardCrashes > 0;
    } else {
        CrashLog *log = _logs[indexPath.row];
        content.text = log.process;
        content.secondaryText = [NSString stringWithFormat:@"%@\n%@", DateText(log.date),
            log.suspect ? [@"Suspect: " stringByAppendingString:log.suspect] : @"No tweak code where it crashed"];
        safeMode = log.crashedSpringBoard;
    }
    if (safeMode) content.textProperties.color = UIColor.systemRedColor;
    cell.contentConfiguration = content;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UIViewController *next;
    if ([self isSuspectSection:indexPath.section])
        next = [[LogListController alloc] initWithSuspect:_suspects[indexPath.row] logs:_logs];
    else
        next = [[LogDetailController alloc] initWithLog:_logs[indexPath.row]];
    [self.navigationController pushViewController:next animated:YES];
}

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UINavigationController *nav = [[UINavigationController alloc]
        initWithRootViewController:[[LogListController alloc] initWithStyle:UITableViewStyleInsetGrouped]];
    nav.navigationBar.prefersLargeTitles = YES;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
