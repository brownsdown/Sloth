/*
 Copyright (c) 2003-2017, Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 2. Redistributions in binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or other
 materials provided with the distribution.
 
 3. Neither the name of the copyright holder nor the names of its contributors may
 be used to endorse or promote products derived from this software without specific
 prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
*/

#import "NSWorkspace+Additions.h"

@implementation NSWorkspace (Additions)

#pragma mark - Handler apps

- (NSArray *)handlerApplicationsForFile:(NSString *)filePath {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    NSMutableArray *appPaths = [[NSMutableArray alloc] initWithCapacity:256];
    
    NSArray *applications = (NSArray *)CFBridgingRelease(LSCopyApplicationURLsForURL((__bridge CFURLRef)url, kLSRolesAll));
    if (applications == nil) {
        return @[];
    }
    
    for (NSURL *appURL in applications) {
        [appPaths addObject:[appURL path]];
    }
    return [NSArray arrayWithArray:appPaths];
}

- (NSString *)defaultHandlerApplicationForFile:(NSString *)filePath {
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:fileURL];
    return [appURL path];
}

// Generate Open With menu for a given file. If no target and action are provided, we use our own.
// If no menu is supplied as parameter, a new menu is created and returned.
- (NSMenu *)openWithMenuForFile:(NSString *)path target:(id)t action:(SEL)s menu:(NSMenu *)menu {
    [menu removeAllItems];

    NSMenuItem *noneMenuItem = [[NSMenuItem alloc] initWithTitle:@"<None>" action:nil keyEquivalent:@""];
    NSString *defaultApp = [self defaultHandlerApplicationForFile:path];
    if ([self canRevealFileAtPath:path] == NO) {
        [menu addItem:noneMenuItem];
        return menu;
    }

    id target = t ? t : self;
    SEL selector = s ? s : @selector(openWith:);
    
    NSMenu *submenu = menu ? menu : [[NSMenu alloc] init];
    [submenu setTitle:path]; // Used by selector
    
    int numOtherApps = 0;
    if (defaultApp) {
        
        // Add menu item for default app
        NSString *defaultAppName = [NSString stringWithFormat:@"%@ (default)", [[NSFileManager defaultManager] displayNameAtPath:defaultApp]];
        NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:defaultApp];
        [icon setSize:NSMakeSize(16,16)];
        
        NSMenuItem *defaultAppItem = [submenu addItemWithTitle:defaultAppName action:selector keyEquivalent:@""];
        [defaultAppItem setImage:icon];
        [defaultAppItem setTarget:target];
        [defaultAppItem setToolTip:defaultApp];
        
        [submenu addItem:[NSMenuItem separatorItem]];
        
        // Add items for all other apps that can open this file
        NSArray *apps = [self handlerApplicationsForFile:path];
        if ([apps count]) {
        
            apps = [apps sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        
            for (NSString *appPath in apps) {
                if ([appPath isEqualToString:defaultApp]) {
                    continue; // Skip previously listed default app
                }
                
                numOtherApps++;
                NSString *title = [[NSFileManager defaultManager] displayNameAtPath:appPath];
                
                NSMenuItem *item = [submenu addItemWithTitle:title action:selector keyEquivalent:@""];
                [item setTarget:target];
                [item setToolTip:appPath];
                
                NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:appPath];
                if (icon) {
                    [icon setSize:NSMakeSize(16,16)];
                    [item setImage:icon];
                }
            }
            
        } else {
            [submenu addItem:noneMenuItem];
        }
    }
    
    if (numOtherApps) {
        [submenu addItem:[NSMenuItem separatorItem]];
    }

    NSMenuItem *selectItem = [submenu addItemWithTitle:@"Select..." action:selector keyEquivalent:@""];
    [selectItem setTarget:target];
    
    return submenu;
}

// Handler for when user selects item in Open With menu
- (void)openWith:(id)sender {
    NSString *appPath = [sender toolTip];
    NSString *filePath = [[sender menu] title];
    
    if ([[sender title] isEqualToString:@"Select..."]) {
        // Create open panel
        NSOpenPanel *oPanel = [NSOpenPanel openPanel];
        [oPanel setAllowsMultipleSelection:NO];
        [oPanel setCanChooseDirectories:NO];
        [oPanel setAllowedFileTypes:@[(NSString *)kUTTypeApplicationBundle]];
        
        // Set Applications folder as default directory
        NSArray *applicationFolderPaths = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationDirectory inDomains:NSLocalDomainMask];
        if ([applicationFolderPaths count]) {
            [oPanel setDirectoryURL:applicationFolderPaths[0]];
        }
        
        // Run
        if ([oPanel runModal] == NSModalResponseOK) {
            appPath = [[oPanel URLs][0] path];
        } else {
            return;
        }
    }
    
    [self openFile:filePath withApplication:appPath];
}


#pragma mark -

- (NSString *)kindStringForFile:(NSString *)filePath {
    CFStringRef kindCFStr = nil;
    NSString *kindStr = nil;
    LSCopyKindStringForURL((__bridge CFURLRef)[NSURL fileURLWithPath:filePath], &kindCFStr);
    if (kindCFStr) {
        kindStr = [NSString stringWithString:(__bridge NSString *)kindCFStr];
        CFRelease(kindCFStr);
    } else {
        kindStr = @"Unknown";
    }
    return kindStr;
}

- (BOOL)canRevealFileAtPath:(NSString *)path {
    return path && [[NSFileManager defaultManager] fileExistsAtPath:path] && ![path hasPrefix:@"/dev/"];
}

#pragma mark - File/folder size

- (NSString *)fileSizeAsHumanReadableString:(UInt64)size {
    if (size < 1024ULL) {
        return [NSString stringWithFormat:@"%u bytes", (unsigned int)size];
    } else if (size < 1048576ULL) {
        return [NSString stringWithFormat:@"%llu KB", (UInt64)size / 1024];
    } else if (size < 1073741824ULL) {
        return [NSString stringWithFormat:@"%.1f MB", size / 1048576.0];
    }
    return [NSString stringWithFormat:@"%.1f GB", size / 1073741824.0];
}

#pragma mark - Finder

- (BOOL)showFinderGetInfoForFile:(NSString *)path {
    if ([self canRevealFileAtPath:path] == NO) {
        return NO;
    }
    BOOL isDir;
    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    NSString *type = isDir && ![self isFilePackageAtPath:path] ? @"folder" : @"file";
    
    NSString *source = [NSString stringWithFormat:
@"set aFile to (POSIX file \"%@\") as text\n\
tell application \"Finder\"\n\
\tactivate\n\
\topen information window of %@ aFile\n\
end tell", path, type];
    
    return [self runAppleScript:source];
}

- (BOOL)moveFileToTrash:(NSString *)path {
    if ([self canRevealFileAtPath:path] == NO) {
        return NO;
    }
    
    NSString *source = [NSString stringWithFormat:
@"tell application \"Finder\"\n\
move POSIX file \"%@\" to trash\n\
end tell", path];
    
    return [self runAppleScript:source];    
}

#pragma mark -

- (BOOL)runAppleScript:(NSString *)scriptSource {
    
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:scriptSource];
    if (appleScript != nil) {
        NSDictionary *errorInfo;
        if ([appleScript executeAndReturnError:&errorInfo] == nil) {
            NSLog(@"%@", [errorInfo description]);
            return NO;
        }
    }
    
    return YES;
}

@end
