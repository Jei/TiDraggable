/**
 * An enhanced fork of the original TiDraggable module by Pedro Enrique,
 * allows for simple creation of "draggable" views.
 *
 * Copyright (C) 2013 Seth Benjamin
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * -- Original License --
 *
 * Copyright 2012 Pedro Enrique
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "TiDraggableGesture.h"
#import <libkern/OSAtomic.h>

@implementation TiDraggableGesture

- (id)initWithProxy:(TiViewProxy*)proxy andOptions:(NSDictionary *)options
{
    if (self = [super init])
    {
        self.proxy = proxy;

        [self rememberProxy:self.proxy];
        [self setValuesForKeysWithDictionary:options];
        [self correctMappedProxyPositions];
        
        [self.proxy setValue:self forKey:@"draggable"];
        [self.proxy.view addGestureRecognizer:[[[UIPanGestureRecognizer alloc]
                                                initWithTarget:self
                                                action:@selector(panDetected:)] autorelease]];
    }
    
    return self;
}

- (void)dealloc
{
    [self forgetProxy:self.proxy];
    
    RELEASE_TO_NIL_AUTORELEASE(self.proxy);
    RELEASE_TO_NIL_AUTORELEASE(monitorTimer);
    
    [super dealloc];
}

- (void)setConfig:(id)args
{
    BOOL didUpdateConfig = NO;
    
    if ([args isKindOfClass:[NSDictionary class]])
    {
        [self setValuesForKeysWithDictionary:args];
        
        didUpdateConfig = YES;
    }
    else if ([args isKindOfClass:[NSArray class]] && [args count] >= 2)
    {
        NSString* key;
        id value = [args objectAtIndex:1];
        
        ENSURE_ARG_AT_INDEX(key, args, 0, NSString);
        
        NSMutableDictionary* params = [[self valueForKey:@"config"] mutableCopy];
        
        if (! params)
        {
            params = [[NSMutableDictionary alloc] init];
        }
        
        [params setValue:value forKeyPath:key];
        
        [self setValuesForKeysWithDictionary:[[params copy] autorelease]];
        
        [params release];
        
        didUpdateConfig = YES;
    }
    
    if (didUpdateConfig)
    {
        [self correctMappedProxyPositions];
    }
}

- (void)panDetected:(UIPanGestureRecognizer *)panRecognizer
{
    ENSURE_UI_THREAD_1_ARG(panRecognizer);
    
    CGPoint translation = [panRecognizer translationInView:self.proxy.view];
    CGPoint newCenter = self.proxy.view.center;
    CGSize size = self.proxy.view.frame.size;
    
    float tmpTranslationX;
    float tmpTranslationY;
    
    if ([panRecognizer state] == UIGestureRecognizerStateBegan)
    {
        touchStart = self.proxy.view.frame.origin;
    }
    else if ([panRecognizer state] == UIGestureRecognizerStateEnded)
    {
        touchEnd = self.proxy.view.frame.origin;
    }
    
    if([[self valueForKey:@"axis"] isEqualToString:@"x"])
    {
        tmpTranslationX = translation.x;
        
        newCenter.x += translation.x;
        newCenter.y = newCenter.y;
    }
    else if([[self valueForKey:@"axis"] isEqualToString:@"y"])
    {
        tmpTranslationY = translation.y;
        
        newCenter.x = newCenter.x;
        newCenter.y += translation.y;
    }
    else
    {
        tmpTranslationX = translation.x;
        tmpTranslationY = translation.y;
        
        newCenter.x += translation.x;
        newCenter.y += translation.y;
    }
    
    NSString* axis = [self valueForKey:@"axis"];
    NSInteger maxLeft = [[self valueForKey:@"maxLeft"] floatValue];
    NSInteger minLeft = [[self valueForKey:@"minLeft"] floatValue];
    NSInteger maxTop = [[self valueForKey:@"maxTop"] floatValue];
    NSInteger minTop = [[self valueForKey:@"minTop"] floatValue];
    BOOL hasMaxLeft = [self valueForKey:@"maxLeft"] != nil;
    BOOL hasMinLeft = [self valueForKey:@"minLeft"] != nil;
    BOOL hasMaxTop = [self valueForKey:@"maxTop"] != nil;
    BOOL hasMinTop = [self valueForKey:@"minTop"] != nil;
    BOOL ensureRight = [TiUtils boolValue:[self valueForKey:@"ensureRight"] def:NO];
    BOOL ensureBottom = [TiUtils boolValue:[self valueForKey:@"ensureBottom"] def:NO];
    
    if(hasMaxLeft || hasMaxTop || hasMinLeft || hasMinTop)
    {
        if(hasMaxLeft && newCenter.x - size.width / 2 > maxLeft)
        {
            newCenter.x = maxLeft + size.width / 2;
        }
        else if(hasMinLeft && newCenter.x - size.width / 2 < minLeft)
        {
            newCenter.x = minLeft + size.width / 2;
        }
        
        if(hasMaxTop && newCenter.y - size.height / 2 > maxTop)
        {
            newCenter.y = maxTop + size.height / 2;
        }
        else if(hasMinTop && newCenter.y - size.height / 2 < minTop)
        {
            newCenter.y = minTop + size.height / 2;
        }
    }
    
    self.proxy.view.center = newCenter;
    
    [panRecognizer setTranslation:CGPointZero inView:self.proxy.view];
    
    [self mapProxyOriginToCollection:[self valueForKey:@"maps"]
                    withTranslationX:tmpTranslationX
                     andTranslationY:tmpTranslationY];
    
    TiViewProxy* panningProxy = (TiViewProxy*)[self.proxy.view proxy];
    
    float left = [panningProxy view].frame.origin.x;
    float top = [panningProxy view].frame.origin.y;
    
    if ([self valueForKey:@"axis"] == nil || [[self valueForKey:@"axis"] isEqualToString:@"x"])
    {
        [panningProxy setLeft:[NSNumber numberWithFloat:left]];
        
        if (ensureRight)
        {
            [panningProxy setRight:[NSNumber numberWithFloat:left * -1]];
        }
    }
    
    if ([self valueForKey:@"axis"] == nil || [[self valueForKey:@"axis"] isEqualToString:@"y"])
    {
        [panningProxy setTop:[NSNumber numberWithFloat:top]];
        
        if (ensureBottom)
        {
            [panningProxy setBottom:[NSNumber numberWithFloat:top * -1]];
        }
    }
    
    NSMutableDictionary *tiProps = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithFloat:left], @"left",
                                    [NSNumber numberWithFloat:top], @"top",
                                    [TiUtils pointToDictionary:self.proxy.view.center], @"center",
                                    [TiUtils pointToDictionary:[panRecognizer velocityInView:self.proxy.view]], @"velocity",
                                    nil];
    
    if([panningProxy _hasListeners:@"start"] && [panRecognizer state] == UIGestureRecognizerStateBegan)
    {
        [panningProxy fireEvent:@"start" withObject:tiProps];
    }
    else if([panningProxy _hasListeners:@"move"] && [panRecognizer state] == UIGestureRecognizerStateChanged)
    {
        [panningProxy fireEvent:@"move" withObject:tiProps];
    }
    else if([panRecognizer state] == UIGestureRecognizerStateEnded || [panRecognizer state] == UIGestureRecognizerStateCancelled)
    {
        [tiProps setValue:[NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithFloat:touchEnd.x - touchStart.x], @"x",
                           [NSNumber numberWithFloat:touchEnd.y - touchStart.y], @"y",
                           nil] forKey:@"distance"];
        
        [panningProxy fireEvent:([panRecognizer state] == UIGestureRecognizerStateCancelled ? @"cancel" : @"end")
                     withObject:tiProps];
    }
}

- (void)correctMappedProxyPositions
{
    NSArray* maps = [self valueForKey:@"maps"];
    
    if ([maps isKindOfClass:[NSArray class]])
    {
        [maps enumerateObjectsUsingBlock:^(id map, NSUInteger index, BOOL *stop) {
            TiViewProxy* proxy = [map objectForKey:@"view"];
            NSDictionary* constraints = [map objectForKey:@"constrain"];
            NSDictionary* constraintX = [constraints objectForKey:@"x"];
            NSDictionary* constraintY = [constraints objectForKey:@"y"];
            BOOL fromCenterX = [TiUtils boolValue:[constraintX objectForKey:@"fromCenter"] def:NO];
            BOOL fromCenterY = [TiUtils boolValue:[constraintY objectForKey:@"fromCenter"] def:NO];
            
            CGSize proxySize = [proxy view].frame.size;
            CGPoint proxyCenter = [proxy view].center;
            
            NSNumber* parallaxAmount = [TiUtils numberFromObject:[map objectForKey:@"parallaxAmount"]];
            
            if (! parallaxAmount)
            {
                parallaxAmount = [NSNumber numberWithInteger:1];
            }
            
            if (constraintX)
            {
                NSNumber* startX = [constraintX objectForKey:@"start"];
                
                if (fromCenterX)
                {
                    proxyCenter.x = [startX floatValue];
                    proxyCenter.x += [proxy.parent view].frame.size.width / 2;
                }
                else
                {
                    proxyCenter.x = [startX floatValue] / [parallaxAmount floatValue];
                    proxyCenter.x += proxySize.width / 2;
                }
            }
            
            if (constraintY)
            {
                NSNumber* startY = [constraintY objectForKey:@"start"];
                
                if (fromCenterY)
                {
                    proxyCenter.y = [startY floatValue];
                    proxyCenter.y += [proxy.parent view].frame.size.height / 2;
                }
                else
                {
                    proxyCenter.y = [startY floatValue] / [parallaxAmount floatValue];
                    proxyCenter.y += proxySize.height / 2;
                }
            }
            
            if (constraintX || constraintY)
            {
                [proxy view].center = proxyCenter;
            }
            
            if (constraintX)
            {
                [proxy setLeft:[NSNumber numberWithFloat:[proxy view].frame.origin.x]];
            }
            
            if (constraintY)
            {
                [proxy setTop:[NSNumber numberWithFloat:[proxy view].frame.origin.y]];
            }
        }];
    }
}

- (void)mapProxyOriginToCollection:(NSArray*)proxies withTranslationX:(float)translationX andTranslationY:(float)translationY
{
    if ([proxies isKindOfClass:[NSArray class]])
    {
        [proxies enumerateObjectsUsingBlock:^(id map, NSUInteger index, BOOL *stop) {
            TiViewProxy* proxy = [map objectForKey:@"view"];
            
            CGPoint proxyCenter = [proxy view].center;
            CGSize proxySize = [proxy view].frame.size;
            CGSize parentSize = [[proxy.parent view] frame].size;
            
            NSNumber* parallaxAmount = [TiUtils numberFromObject:[map objectForKey:@"parallaxAmount"]];
            
            if (! parallaxAmount)
            {
                parallaxAmount = [NSNumber numberWithInteger:1];
            }
            
            NSDictionary* constraints = [map objectForKey:@"constrain"];
            NSDictionary* constraintX = [constraints objectForKey:@"x"];
            NSDictionary* constraintY = [constraints objectForKey:@"y"];
            NSString* constraintAxis = [constraints objectForKey:@"axis"];
            
            TiProxy* proxyDraggable = [proxy valueForKey:@"draggable"];
            
            NSInteger maxLeft = [[proxyDraggable valueForKey:@"maxLeft"] floatValue];
            NSInteger minLeft = [[proxyDraggable valueForKey:@"minLeft"] floatValue];
            NSInteger maxTop = [[proxyDraggable valueForKey:@"maxTop"] floatValue];
            NSInteger minTop = [[proxyDraggable valueForKey:@"minTop"] floatValue];
            BOOL hasMaxLeft = [proxyDraggable valueForKey:@"maxLeft"] != nil;
            BOOL hasMinLeft = [proxyDraggable valueForKey:@"minLeft"] != nil;
            BOOL hasMaxTop = [proxyDraggable valueForKey:@"maxTop"] != nil;
            BOOL hasMinTop = [proxyDraggable valueForKey:@"minTop"] != nil;
            BOOL ensureRight = [TiUtils boolValue:[proxyDraggable valueForKey:@"ensureRight"] def:NO];
            BOOL ensureBottom = [TiUtils boolValue:[proxyDraggable valueForKey:@"ensureBottom"] def:NO];
            
            if (constraints)
            {
                if (constraintX && ([constraintAxis isEqualToString:@"x"] || constraintAxis == nil))
                {
                    BOOL fromCenterX = [TiUtils boolValue:[constraintX objectForKey:@"fromCenter"] def:NO];
                    NSNumber* startX = [constraintX objectForKey:@"start"];
                    NSNumber* endX = [constraintX objectForKey:@"end"];
                    float offsetWidth = proxySize.width;
                    
                    if (startX && endX)
                    {
                        startX = [NSNumber numberWithFloat:[startX floatValue] / [parallaxAmount floatValue]];
                        endX = [NSNumber numberWithFloat:[endX floatValue] / [parallaxAmount floatValue]];
                        offsetWidth = fabsf([startX floatValue]) + fabsf([endX floatValue]);
                    }
                    else
                    {
                        offsetWidth /= [parallaxAmount floatValue];
                    }
                    
                    float ratioW = (offsetWidth / 2) / (proxySize.width / 2);
                    
                    proxyCenter.x += translationX * ratioW;
                    
                    if(startX && endX)
                    {
                        if (fromCenterX)
                        {
                            startX = [NSNumber numberWithFloat:[startX floatValue] + (parentSize.width / 2 - proxySize.width / 2)];
                            endX = [NSNumber numberWithFloat:[endX floatValue] + (parentSize.width / 2 - proxySize.width / 2)];
                        }
                        
                        if(endX && proxyCenter.x - proxySize.width / 2 > [endX floatValue])
                        {
                            proxyCenter.x = [endX floatValue] + proxySize.width / 2;
                        }
                        else if(startX && proxyCenter.x - proxySize.width / 2 < [startX floatValue])
                        {
                            proxyCenter.x = [startX floatValue] + proxySize.width / 2;
                        }
                    }
                }
                else if ([constraintAxis isEqualToString:@"x"])
                {
                    proxyCenter.x += translationX / [parallaxAmount floatValue];
                }
                
                if (constraintY && ([constraintAxis isEqualToString:@"y"] || constraintAxis == nil))
                {
                    BOOL fromCenterY = [TiUtils boolValue:[constraintY objectForKey:@"fromCenter"] def:NO];
                    NSNumber* startY = [constraintY objectForKey:@"start"];
                    NSNumber* endY = [constraintY objectForKey:@"end"];
                    float offsetHeight = proxySize.height;
                    
                    if (startY && endY)
                    {
                        startY = [NSNumber numberWithFloat:[startY floatValue] / [parallaxAmount floatValue]];
                        endY = [NSNumber numberWithFloat:[endY floatValue] / [parallaxAmount floatValue]];
                        offsetHeight = fabsf([startY floatValue]) + fabsf([endY floatValue]);
                    }
                    else
                    {
                        offsetHeight /= [parallaxAmount floatValue];
                    }
                    
                    float ratioH = (offsetHeight / 2) / (proxySize.height / 2);
                    
                    proxyCenter.y += translationY * ratioH;
                    
                    if(startY && endY)
                    {
                        if (fromCenterY)
                        {
                            startY = [NSNumber numberWithFloat:[startY floatValue] + (parentSize.height / 2 - proxySize.height / 2)];
                            endY = [NSNumber numberWithFloat:[endY floatValue] + (parentSize.height / 2 - proxySize.height / 2)];
                        }
                        
                        if(endY && proxyCenter.y - proxySize.height / 2 > [endY floatValue])
                        {
                            proxyCenter.y = [endY floatValue] + proxySize.height / 2;
                        }
                        else if(startY && proxyCenter.y - proxySize.height / 2 < [startY floatValue])
                        {
                            proxyCenter.y = [startY floatValue] + proxySize.height / 2;
                        }
                    }
                }
                else if ([constraintAxis isEqualToString:@"y"])
                {
                    proxyCenter.y += translationY / [parallaxAmount floatValue];
                }
            }
            else
            {
                proxyCenter.x += translationX / [parallaxAmount floatValue];
                proxyCenter.y += translationY / [parallaxAmount floatValue];
            }
            
            if(hasMaxLeft || hasMaxTop || hasMinLeft || hasMinTop)
            {
                if(hasMaxLeft && proxyCenter.x - proxySize.width / 2 > maxLeft)
                {
                    proxyCenter.x = maxLeft + proxySize.width / 2;
                }
                else if(hasMinLeft && proxyCenter.x - proxySize.width / 2 < minLeft)
                {
                    proxyCenter.x = minLeft + proxySize.width / 2;
                }
                
                if(hasMaxTop && proxyCenter.y - proxySize.height / 2 > maxTop)
                {
                    proxyCenter.y = maxTop + proxySize.height / 2;
                }
                else if(hasMinTop && proxyCenter.y - proxySize.height / 2 < minTop)
                {
                    proxyCenter.y = minTop + proxySize.height / 2;
                }
            }
            
            [proxy view].center = proxyCenter;
            
            float left = [proxy view].frame.origin.x;
            float top = [proxy view].frame.origin.y;
            
            if (constraintAxis == nil || [constraintAxis isEqualToString:@"x"])
            {
                [proxy setLeft:[NSNumber numberWithFloat:left]];
                
                if (ensureRight)
                {
                    [proxy setRight:[NSNumber numberWithFloat:left * -1]];
                }
            }
            
            if (constraintAxis == nil || [constraintAxis isEqualToString:@"y"])
            {
                [proxy setTop:[NSNumber numberWithFloat:top]];
                
                if (ensureBottom)
                {
                    [proxy setBottom:[NSNumber numberWithFloat:top * -1]];
                }
            }
        }];
    }
}

@end