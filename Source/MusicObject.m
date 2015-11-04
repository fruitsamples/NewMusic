/*

File: MusicObject.m

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


#import "MusicObject.h"
#import "Storage.h"
#import "CoreDataUtils.h"
#import "mk.h"
#import "Logging.h"


@interface MusicObject (CoreDataGeneratedPrimitiveAccessors)
- (NSNumber*)primitiveRating;
- (void)setPrimitiveRating:(NSNumber*)value;
- (NSNumber*)primitiveITMSID;
- (void)setPrimitiveITMSID:(NSNumber*)value;
- (NSNumber*)primitiveEMusicID;
- (void)setPrimitiveEMusicID:(NSNumber*)value;
@end


@implementation MusicObject


+ (id) instanceWithValue: (id)value forKey: (NSString*)key
{
    NSString *template = [NSString stringWithFormat: @"%@_with_%@",
                            [self description],key];
    return [[[Storage sharedInstance] managedObjectContext]
                                            fetchUniqueObjectWithTemplate: template
                                                                parameters: mkdict({key,value})];
}

+ (id) instanceWithEMusicID: (UInt64)eMusicID
{
    return [self instanceWithValue: box(eMusicID) forKey: @"eMusicID"];
}

+ (id) instanceWithITMSID: (UInt64)iTMSID
{
    return [self instanceWithValue: box(iTMSID) forKey: @"iTMSID"];
}

+ (id) instanceWithName: (NSString*)name
{
    return [self instanceWithValue: name forKey: @"name"];
}


+ (id) createInstanceWithValue: (id)value forKey: (NSString*)key named: (NSString*)name
{
    MusicObject *instance = value ?[self instanceWithValue: value forKey: key] :nil;
    if( ! instance && name ) {
        Log(@"Creating new %@ '%@' (%@=%@)",[self description],name,key,value);
        instance = [self instanceWithName: name];
        if( instance==nil || [instance valueForKey: key] != nil ) {
            // OK, we actually have to create a new instance:
            instance = [NSEntityDescription insertNewObjectForEntityForName: [self description]
                            inManagedObjectContext: [[Storage sharedInstance] managedObjectContext]];
            instance.name = name;
        }
        [instance setValue: value forKey: key];
    }
    return instance;
}

+ (id) createInstanceWithEMusicID: (UInt64)eMusicID named: (NSString*)name
{
    return [self createInstanceWithValue: box(eMusicID) forKey: @"eMusicID" named: name];
}

+ (id) createInstanceWithITMSID: (UInt64)iTMSID named: (NSString*)name;
{
    return [self createInstanceWithValue: box(iTMSID) forKey: @"iTMSID" named: name];
}


- (void) dealloc
{
    [_nameForSorting release];
    [super dealloc];
}


- (NSString*) description
{
    if( [self isFault] )
        return [super description];
    else
        return [NSString stringWithFormat: @"%@['%@']", [self class],self.name];
}


- (NSString*) nameForSorting
{
    if( ! _nameForSorting ) {
        _nameForSorting = [self.name uppercaseString];
        unsigned start = 0;
        if( [_nameForSorting hasPrefix: @"THE "] )
            start = 4;
        else if( [_nameForSorting hasPrefix: @"A "] )
            start = 2;
        _nameForSorting = [[_nameForSorting substringFromIndex: start] copy];
    }
    return _nameForSorting;
}


#pragma mark -
#pragma mark MANAGED PROPERTIES:


@dynamic name;


/* CoreData does not generate dynamic accessors for scalar-valued properties. */


- (int) rating {
    [self willAccessValueForKey:@"rating"];
    int result = [[self primitiveRating] shortValue];
    [self didAccessValueForKey:@"rating"];
    return result;
}

- (void) setRating:(int)value {
    if( value != [self rating] ) {
        [self willChangeValueForKey:@"rating"];
        NSNumber* newRating = [[NSNumber alloc] initWithInt:value];
        [self setPrimitiveRating:newRating];
        [newRating release];
        [self didChangeValueForKey:@"rating"];
    }
}


- (UInt64) iTMSID {
    [self willAccessValueForKey:@"iTMSID"];
    UInt64 result = [[self primitiveITMSID] unsignedLongLongValue];
    [self didAccessValueForKey:@"iTMSID"];
    return result;
}

- (void) setITMSID:(UInt64)value {
    if( value != [self iTMSID] ) {
        [self willChangeValueForKey:@"iTMSID"];
        NSNumber* newITMSID = [[NSNumber alloc] initWithUnsignedLongLong:value];
        [self setPrimitiveITMSID:newITMSID];
        [newITMSID release];
        [self didChangeValueForKey:@"iTMSID"];
    }
}



- (UInt64) eMusicID {
    [self willAccessValueForKey:@"eMusicID"];
    UInt64 result = [[self primitiveEMusicID] unsignedLongLongValue];
    [self didAccessValueForKey:@"eMusicID"];
    return result;
}

- (void) setEMusicID:(UInt64)value {
    if( value != [self eMusicID] ) {
        [self willChangeValueForKey:@"eMusicID"];
        NSNumber* newEMusicID = [[NSNumber alloc] initWithUnsignedLongLong:value];
        [self setPrimitiveEMusicID:newEMusicID];
        [newEMusicID release];
        [self didChangeValueForKey:@"eMusicID"];
    }
}


@end
