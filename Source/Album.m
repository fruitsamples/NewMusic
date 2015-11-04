/*

File: Album.m

Abstract: Use the PubSub framework to create a music new release browser.

Version: 1.0

Disclaimer: IMPORTANT:  This Apple software is supplied to you by 
Apple Inc. ("Apple") in consideration of your agreement to the
following terms, and your use, installation, modification or
redistribution of this Apple software constitutes acceptance of these
terms.  If you do not agree with these terms, please do not use,
install, modify or redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and
subject to these terms, Apple grants you a personal, non-exclusive
license, under Apple's copyrights in this original Apple software (the
"Apple Software"), to use, reproduce, modify and redistribute the Apple
Software, with or without modifications, in source and/or binary forms;
provided that if you redistribute the Apple Software in its entirety and
without modifications, you must retain this notice and the following
text and disclaimers in all such redistributions of the Apple Software. 
Neither the name, trademarks, service marks or logos of Apple Inc. 
may be used to endorse or promote products derived from the Apple
Software without specific prior written permission from Apple.  Except
as expressly stated in this notice, no other rights or licenses, express
or implied, are granted by Apple herein, including but not limited to
any patent rights that may be infringed by your derivative works or by
other works in which the Apple Software may be incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

Copyright © 2006-2007 Apple Inc. All Rights Reserved.

*/


#import "Album.h"
#import "Cover.h"
#import "Artist.h"
#import "Genre.h"
#import "Storage.h"
#import "mk.h"
#import "CoreDataUtils.h"
#import "Downloader.h"
#import "Logging.h"
#import <PubSub/PubSub.h>


@interface Album (CoreDataGeneratedPrimitiveAccessors)
- (NSNumber*)primitiveYear;
- (void)setPrimitiveYear:(NSNumber*)value;
- (NSNumber*)primitiveRead;
- (void)setPrimitiveRead:(NSNumber*)value;
- (NSNumber*)primitiveFlagged;
- (void)setPrimitiveFlagged:(NSNumber*)value;
@end

@interface Album ()
@property (retain) Cover* cover;
@end


@implementation Album


+ (void) initialize
{
    [self setKeys: mkarray(@"read",@"flagged")
        triggerChangeNotificationsForDependentKey: @"statusImage"];
}


+ (Album*) albumWithEntryID: (NSString*)entryID
{
    return [self instanceWithValue: entryID forKey: @"entryID"];
}


+ (Album*) createAlbumFromEntry: (PSEntry*)entry
{
    Log(@"Album: Creating new Album for %@",entry);
    Album *album = [NSEntityDescription insertNewObjectForEntityForName: @"Album"
                                            inManagedObjectContext: [[Storage sharedInstance] managedObjectContext]];
    album.read = [entry isRead];
    album.flagged = [entry isFlagged];
    NSDate *date = [entry dateCreated];
    if( ! date )
        date = entry.localDateCreated;
    if( ! date )
        date = [NSDate date];
    album.dateAdded = date;
    album.entryID = [entry identifier];
    return album;
}

- (void)didTurnIntoFault  
{
    [_sampleURLs release];
    [super didTurnIntoFault];
}


- (NSString*) formattedDescription
{
    return [NSString stringWithFormat: @"\"%@\"\n%@", self.name,self.artist.name];
}


- (NSString*) genresForDisplay
{
    NSMutableString *desc = [NSMutableString string];
    NSSet *set = self.genres;
    BOOL first = YES;
    for( Genre *g in set ) {
        if( first )
            first = NO;
        else
            [desc appendString: @", "];
        [desc appendString: g.name];
    }
    return desc;
}


- (NSImage*) statusImage
{
    if( ! self.read )
        return [NSImage imageNamed: @"unread.tiff"];
    else if( self.flagged )
        return [NSImage imageNamed: @"flagged.tiff"];
    else
        return nil;
}


- (PSEntry*) entry
{
    if( ! self.entryID )
        return nil;
    return [[PSClient applicationClient] entryWithIdentifier: self.entryID];
}


- (NSURL*) webURL
{
    NSString *urlStr;
    if( self.eMusicID ) {
        NSString *idstr = [NSString stringWithFormat: @"%05qu",self.eMusicID];
        urlStr = [NSString stringWithFormat: @"http://www.emusic.com/album/%@/%@.html",
                                [idstr substringWithRange: NSMakeRange(0,5)],
                                idstr];
    } else if( self.iTMSID ) {
        urlStr = [NSString stringWithFormat: @"itms://phobos.apple.com/WebObjects/MZStore.woa/wa/viewAlbum?id=%qu",
                                self.iTMSID];
    } else
        return nil;
    return [NSURL URLWithString: urlStr];
}


#pragma mark -
#pragma mark ALBUM COVER:


- (void) setCoverURL: (NSURL*)url
{
    Cover *cover = self.cover;
    if( ! cover ) {
        // If none exists yet, create one
        cover = [NSEntityDescription insertNewObjectForEntityForName: @"Cover"
                                              inManagedObjectContext: [[Storage sharedInstance] managedObjectContext]];
        self.cover = cover;
        [[Storage sharedInstance] saveSoon];
        Log(@"Created Cover for %@",self);
    }
    cover.URL = url;
}

- (NSURL*) coverURL                 {return self.cover.URL;}

- (NSData*) coverData               {return [self.cover loadData: NO];}
- (NSData*) coverDataSync           {return [self.cover loadData: YES];}
- (NSImage*) coverImage             {return self.cover.image;}


#pragma mark -
#pragma mark LOADING SAMPLES:


- (NSURL*) m3uURL
{
    if( ! self.eMusicID )
        return nil;
    NSString *urlStr = [NSString stringWithFormat: @"http://www.emusic.com/samples/m3u/album/%qu/0.m3u",
                        self.eMusicID];
    return [NSURL URLWithString: urlStr];
}


- (BOOL) hasTrackSamples
{
    if( _sampleURLs )
        return [_sampleURLs count] > 0;
    else
        return self.eMusicID != 0;
}


static NSString* sampleURLToTitle( NSURL *url )
{
    NSMutableString *name = [[[[url path] lastPathComponent] stringByDeletingPathExtension] mutableCopy];
    [name replaceOccurrencesOfString: @"_" withString: @" " options: 0 range: NSMakeRange(0,[name length])];
    return name;
}

- (NSArray*) trackSampleURLs
{
    if( ! _sampleURLs ) {
        _sampleURLs = [[NSMutableArray alloc] init];
        _sampleTitles = [[NSMutableArray alloc] init];
        NSString *urlsStr = self.sampleURLsStr;
        if( ! urlsStr ) {
            // Download M3U file and save contents as my sampleURLsStr property:
            NSURL *m3uURL = [self m3uURL];
            if( m3uURL ) {
                [[Downloader alloc] initWithURL: m3uURL target: self action: @selector(_gotM3U:)];
                Log(@"Loading m3u for %@ from <%@>...",self,m3uURL);
            }
        } else {
            // Break up M3U data into URLs:
            NSString *sampleTitle = nil;
            for( NSString *str in [urlsStr componentsSeparatedByString: @"\r\n"] )
                if( [str length] ) {
                    if( [str hasPrefix: @"#"] ) {
                        // A comment:
                        if( [str hasPrefix: @"#EXTINF:"] ) {
                            sampleTitle = [str substringFromIndex: 8];
                            NSRange sep = [sampleTitle rangeOfString: @" - "];
                            if( sep.length > 0 )
                                sampleTitle = [sampleTitle substringFromIndex: sep.location+1];
                        }
                    } else {
                        // A URL:
                        NSURL *sampleURL = [NSURL URLWithString: str];
                        if( sampleURL ) {
                            [_sampleURLs addObject: sampleURL];
                            if( ! sampleTitle )
                                sampleTitle = sampleURLToTitle(sampleURL);
                            [_sampleTitles addObject: sampleTitle];
                        }
                        sampleTitle = nil;
                    }
                }
        }
    }
    return _sampleURLs;
}


- (NSArray*) trackSampleTitles
{
    if( ! _sampleTitles )
        [self trackSampleURLs];     // this will populate the titles as well
    return _sampleTitles;
}


- (void) _gotM3U: (NSData*)data
{
    Log(@"Got m3u for %@ (%u bytes)",self,[data length]);
    if( data ) {
        NSString *urlsStr = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
        if( [urlsStr length] ) {
            Log(@"Loaded sample URLs for %@",self);
            [self willChangeValueForKey: @"hasTrackSamples"];
            [self willChangeValueForKey: @"trackSampleURLs"];
            [self willChangeValueForKey: @"trackSampleTitles"];
            self.sampleURLsStr = urlsStr;
            [_sampleURLs release];
            _sampleURLs = nil;
            [_sampleTitles release];
            _sampleTitles = nil;
            [self didChangeValueForKey: @"trackSampleTitles"];
            [self didChangeValueForKey: @"trackSampleURLs"];
            [self didChangeValueForKey: @"hasTrackSamples"];
        }
    }
}


#pragma mark -
#pragma mark MANAGED PROPERTIES:


@dynamic artist,genres,label,dateAdded,sampleURLsStr,entryID,cover;


/* CoreData does not generate dynamic accessors for scalar-valued properties. */


- (SInt16) year {
    [self willAccessValueForKey:@"year"];
    SInt16 result = [[self primitiveYear] shortValue];
    [self didAccessValueForKey:@"year"];
    return result;
}

- (void) setYear:(SInt16)value {
    if( value != [self year] ) {
        [self willChangeValueForKey:@"year"];
        NSNumber* newyear = [[NSNumber alloc] initWithInt:value];
        [self setPrimitiveYear:newyear];
        [newyear release];
        [self didChangeValueForKey:@"year"];
    }
}


- (BOOL) read {
    [self willAccessValueForKey:@"read"];
    BOOL result = [[self primitiveRead] boolValue];
    [self didAccessValueForKey:@"read"];
    return result;
}

- (void) setRead:(BOOL)value {
    if( value != [self read] ) {
        [self willChangeValueForKey:@"read"];
        NSNumber* newRead = [[NSNumber alloc] initWithBool:value];
        [self setPrimitiveRead:newRead];
        [newRead release];
        
        // Update the PSEntry:
        [self entry].read = value;
        
        [self didChangeValueForKey:@"read"];
    }
}


- (BOOL) flagged {
    [self willAccessValueForKey:@"flagged"];
    BOOL result = [[self primitiveFlagged] boolValue];
    [self didAccessValueForKey:@"flagged"];
    return result;
}

- (void) setFlagged:(BOOL)value {
    if( value != [self flagged] ) {
        [self willChangeValueForKey:@"flagged"];
        NSNumber* newFlagged = [[NSNumber alloc] initWithBool:value];
        [self setPrimitiveFlagged:newFlagged];
        [newFlagged release];
        [self entry].flagged = value;
        [self didChangeValueForKey:@"flagged"];
    }
}


@end
