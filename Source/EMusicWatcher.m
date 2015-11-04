/*

File: EMusicWatcher.m

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


#import "EMusicWatcher.h"
#import "Album.h"
#import "Artist.h"
#import "Genre.h"
#import "Label.h"
#import "Logging.h"
#import <PubSub/PubSub.h>


/* To find eMusic feed URLs, browse to the "Just Ripped" page of any genre or sub-genre,
   and simply click the "RSS" button in the Safari address bar. */


@implementation EMusicWatcher


+ (BOOL) handlesFeedURL: (NSURL*)url
{
    return [[[url host] lowercaseString] hasSuffix: @"emusic.com"];
}


static UInt64 eMusicIDFromURL( NSURL *url )
{
    if( ! url )
        return 0;
    SInt64 eMusicID = [[[[url path] lastPathComponent] stringByDeletingPathExtension] longLongValue];
    if( eMusicID <= 0 ) {
        Warn(@"Couldn't parse eMusic ID from <%@>",url);
        eMusicID = 0;
    }
    return eMusicID;
}


static UInt64 eMusicIDFromBrowseURL( NSURL *url )
{
    if( ! url )
        return 0;
    NSString *component = [[[url path] stringByDeletingLastPathComponent] lastPathComponent];
    SInt64 eMusicID = [[component stringByDeletingPathExtension] longLongValue];
    if( eMusicID <= 0 ) {
        Warn(@"Couldn't parse eMusic ID from <%@>",url);
        eMusicID = 0;
    }
    return eMusicID;
}


static NSArray* arrayForXPath( NSXMLElement *html, NSString *xpath )
{
    NSError *error = nil;
    NSArray *nodes = [html nodesForXPath: xpath error: &error];
    if( nodes == nil ) {
        Log(@"Error: Couldn't parse '%@': %@",xpath,[error localizedDescription]);
    }
    return nodes;
}


static NSString* strForXPath( NSXMLElement *html, NSString *xpath )
{
    NSArray *nodes = arrayForXPath(html,xpath);
    if( nodes == nil )
        return nil;
    if( [nodes count] == 0 ) {
        Warn(@"No results for '%@'",xpath);
        return nil;
    }
    if( [nodes count] > 1 ) {
        Warn(@"Got %u results for '%@'",[nodes count],xpath);
    }
    return [[nodes objectAtIndex: 0] stringValue];
}

static NSURL* URLForXPath( NSXMLElement *html, NSString *xpath )
{
    NSString *str = strForXPath(html,xpath);
    if( ! str )
        return nil;
    NSURL *url = [NSURL URLWithString: str];
    if( ! url ) {
        Warn(@"Invalid URL <%@> for '%@'",str,xpath);
    }
    return url;
}


- (BOOL) updateAlbum: (Album*)album fromEntry: (PSEntry*)entry
{
    // Check the album ID:
    UInt64 albumID = eMusicIDFromURL([entry alternateURL]);
    if( albumID == 0 )
        return NO;
    if( album.eMusicID ) {
        if( album.eMusicID != albumID ) {
            Warn(@"EMusic album ID conflict for %@",entry);
            return NO;
        }
    } else {
        album.eMusicID = albumID;
        Log(@"EMusic ID = %qu",albumID);
    }
    
    // Parse the HTML contents:
    NSError *error = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString: [[entry content] HTMLString]
                                                            options: NSXMLDocumentTidyHTML
                                                            error: &error];
    if( ! doc ) {
        Log(@"Couldn't parse content of %@: %@",entry,error);
        return NO;
    }
    NSXMLElement *html = [doc rootElement];
    
    // Get the album title:
    album.name = strForXPath(html,@"//a[starts-with(@href,'http://www.emusic.com/album/')]/child::text()");
    
    // Get the artist:
    UInt64 artistID = eMusicIDFromURL(URLForXPath(html,@"//a[starts-with(@href,'http://www.emusic.com/artist/')]/@href"));
    if( ! artistID )
        return NO;
    Artist *artist = [Artist instanceWithEMusicID: artistID];
    if( ! artist ) {
        NSString *artistName = strForXPath(html,@"//a[starts-with(@href,'http://www.emusic.com/artist/')]/child::text()");
        if( ! artistName )
            return NO;
        artist = [Artist createInstanceWithEMusicID: artistID named: artistName];
    }
    album.artist = artist;

    Log(@"Artist = '%@', Album = '%@'",album.artist.name,album.name);
    
    // Get the label:
    UInt64 labelID = eMusicIDFromURL(URLForXPath(html,@"//a[starts-with(@href,'http://www.emusic.com/label/')]/@href"));
    if( labelID ) {
        Label *label = [Label instanceWithEMusicID: labelID];
        if( ! label ) {
            NSString *labelName = strForXPath(html,@"//a[starts-with(@href,'http://www.emusic.com/label/')]/child::text()");
            if( ! labelName )
                return NO;
            label = [Label createInstanceWithEMusicID: labelID named: labelName];
        }
        album.label = label;
        Log(@"Label  = '%@' (%qu)", label.name,label.eMusicID);
    }
    
    // Get the genres:
    NSArray *genreLinks = arrayForXPath(html,@"//a[starts-with(@href,'http://www.emusic.com/browse/')]");
    for( NSXMLElement *genreElem in genreLinks ) {
        NSString *href = [[genreElem attributeForName: @"href"] stringValue];
        UInt64 genreID = eMusicIDFromBrowseURL( [NSURL URLWithString: href] );
        NSString *name = [genreElem stringValue];
        if( genreID && name ) {
            Genre *genre = [Genre createInstanceWithEMusicID: genreID named: name];
            [album.genres addObject: genre];
            Log(@"Genre  = '%@' (%qu)",genre.name,genre.eMusicID);
        }
    }
    
    // Cover URL for eMusic albums can be generated from the eMusic ID.
    NSString *idstr = [NSString stringWithFormat: @"%06qu",albumID];
    NSString *urlStr = [NSString stringWithFormat: @"http://www.emusic.com/img/album/%@/%@/%@_155_155.jpeg",
                        [idstr substringWithRange: NSMakeRange(0,3)],
                        [idstr substringWithRange: NSMakeRange(3,3)],
                        idstr];
    album.coverURL = [NSURL URLWithString: urlStr];    
    
    [doc release];
    return YES;
}


@end


/* Sample item:
 
 <item>
 <pubDate>Fri Jul 21 00:00:00 EDT 2006</pubDate>
 <title>Garibaldi Guard! - U.S. Bombs</title>
 <link>http://www.emusic.com/album/10943/10943391.html</link>
 <category>album</category>
 <description>
 &lt;a href="http://www.emusic.com/album/10943/10943391.html">Garibaldi Guard!&lt;/a> (1996) 
 &lt;a href="http://www.emusic.com/artist/10559/10559304.html">U.S. Bombs&lt;/a>&lt;br>				
 &lt;TABLE BORDER=0 WIDTH="100%">&lt;TR>&lt;TD>&lt;table border="0" width="100%" cellspacing="0" cellpadding="0">
 &lt;tr valign="top" align="left">
 &lt;td ALIGN=CENTER WIDTH=166 VALIGN=TOP>
 &lt;a href="http://www.emusic.com/album/10943/10943391.html">&lt;img border="0" src="http://www.emusic.com/img/album/109/433/10943391_155_155.jpeg">&lt;/a>&lt;br>
 &lt;a href="http://www.emusic.com/samples/m3u/album/10943391/0.m3u">&lt;img src="http://www.emusic.com/images/ctlg/album/icons/listen2.png" alt="Listen" width="61" height="21" border="0" />&lt;/a>
 &lt;/td>
 &lt;td width="10">&lt;img alt="" width="10" height="1" src="http://www.emusic.com/images/spacer.gif">&lt;/td>
 &lt;td width="95%">
 &lt;font size="3" FACE="Helvetica,Arial">
 &lt;B>Genre:&lt;/B> &lt;a href="http://www.emusic.com/browse/b/b/-dbm/a/0-0/1200000284/0.html">Alternative/Punk&lt;/a>&lt;br>
 &lt;B>Styles:&lt;/B> &lt;a href="http://www.emusic.com/browse/b/b/-dbm/a/0-0/1200000303/0.html">Punk&lt;/a>&lt;br>
 &lt;B>Label:&lt;/B> &lt;a href="http://www.emusic.com/label/89/89934.html">Marilyn / Bomp! Records / Lumberjack Mordam&lt;/a>
 &lt;/font>
 &lt;/td>
 &lt;/tr>
 &lt;/table>&lt;/TD>&lt;/TR>
 &lt;/TABLE>
 </description>
 </item>
 */
