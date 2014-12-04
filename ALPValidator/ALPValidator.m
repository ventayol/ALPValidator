/*
 
 ALPValidator.m
 ALPValidator
 
 Created by @adamwaite.
 
 Copyright (c) 2014 Adam Waite. All rights reserved.
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 
 */

#import "ALPValidator.h"
#import "ALPStringValidator.h"
#import "ALPNumericValidator.h"
#import "ALPValidatorRule.h"
#import "ALPValidatorEqualRule.h"
#import "ALPValidatorCustomRule.h"
#import "ALPValidatorRemoteRule.h"

const NSString * NSStringFromALPValidatorType(ALPValidatorType type) {
    switch (type) {
        case ALPValidatorTypeString: return @"String";
        case ALPValidatorTypeNumeric: return @"Numeric";
        default: return nil;
    }
}

const NSString * NSStringFromALPValidatorState(ALPValidatorState state) {
    switch (state) {
        case ALPValidatorValidationStateInvalid: return @"Invalid";
        case ALPValidatorValidationStateValid: return @"Valid";
        case ALPValidatorValidationStateWaitingForRemote: return @"Waiting for remote validation";
        default: return nil;
    }
}

NSString * const ALPValidatorRegularExpressionPatternEmail = @"^[_A-Za-z0-9-+]+(\\.[_A-Za-z0-9-+]+)*@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*(\\.[A-Za-z‌​]{2,4})$";

NSString * const ALPValidatorRegularExpressionPatternContainsNumber = @".*\\d.*";

@interface ALPValidator ()

@property (nonatomic) ALPValidatorType type;
@property (nonatomic) ALPValidatorState state;
@property (copy, nonatomic) NSMutableArray *rules;
@property (nonatomic) BOOL localConditionsSatisfied;
@property (copy, nonatomic) NSArray *errorMessages;
@property (copy, nonatomic) NSMutableArray *mutableErrorMessages;
@property (nonatomic, strong) id sender;

@end

@implementation ALPValidator

#pragma mark Init

+ (instancetype)validator
{
    return [[ALPValidator alloc] initWithType:ALPValidatorTypeGeneric];
}

+ (instancetype)validatorWithType:(ALPValidatorType)type
{
    switch (type) {
        case ALPValidatorTypeGeneric:
            return [ALPValidator validator];
        case ALPValidatorTypeString:
            return [[ALPStringValidator alloc] init];
        case ALPValidatorTypeNumeric:
            return [[ALPNumericValidator alloc] init];
    }
}

- (id)init
{
    [NSException raise:@"ALPValidator Error" format:@"Use the designated initialiser (%@) to create validators, %s", NSStringFromSelector(@selector(validatorWithType:)), __PRETTY_FUNCTION__];
    return nil;
}

- (id)initWithType:(ALPValidatorType)type
{
    self = [super init];
    if (self) {
        _type = type;
        _rules = [NSMutableArray array];
        _mutableErrorMessages = [NSMutableArray array];
    }
    return self;
}

#pragma mark Description

- (NSString *)description
{
    NSDictionary *output = @{
        @"state": @(self.state),
        @"state as string": NSStringFromALPValidatorState(self.state),
        @"errorMessages": self.errorMessages
    };
    
    return [NSString stringWithFormat:@"%@ %p: %@", [self class], self, output];
}

- (NSString *)debugDescription
{
    return [self description];
}

#pragma mark Add Rules

- (void)addValidationRule:(ALPValidatorRule *)rule
{
    [self.rules addObject:rule];
}

- (void)addValidationToEnsurePresenceWithInvalidMessage:(NSString *)message
{
    [self raiseIncompatibilityException];
}

- (void)addValidationToEnsureMinimumLength:(NSUInteger)minLength invalidMessage:(NSString *)message
{
    [self raiseIncompatibilityException];
}

- (void)addValidationToEnsureMaximumLength:(NSUInteger)maxLength invalidMessage:(NSString *)message
{
    [self raiseIncompatibilityException];
}

- (void)addValidationToEnsureRangeWithMinimum:(NSNumber *)min maximum:(NSNumber *)max invalidMessage:(NSString *)message
{
    [self raiseIncompatibilityException];
}

- (void)addValidationToEnsureInstanceIsTheSameAs:(id)otherInstance invalidMessage:(NSString *)message
{
    ALPValidatorEqualRule *rule = [[ALPValidatorEqualRule alloc] initWithType:ALPValidatorRuleTypeEqual invalidMessage:message otherInstance:otherInstance];
    [self addValidationRule:rule];
}

- (void)addValidationToEnsureRegularExpressionIsMetWithPattern:(NSString *)pattern invalidMessage:(NSString *)message
{
    [self raiseIncompatibilityException];
}

- (void)addValidationToEnsureValidEmailWithInvalidMessage:(NSString *)message
{
    [self raiseIncompatibilityException];
}

- (void)addValidationToEnsureCustomConditionIsSatisfiedWithBlock:(ALPValidatorCustomRuleBlock)block invalidMessage:(NSString *)message
{
    ALPValidatorCustomRule *rule = [[ALPValidatorCustomRule alloc] initWithType:ALPValidatorRuleTypeCustom block:block invalidMessage:message];
    [self addValidationRule:rule];
}

- (void)addValidationToEnsureRemoteConditionIsSatisfiedAtURL:(NSURL *)url invalidMessage:(NSString *)message
{
    __typeof__(self) __weak weakSelf = self;
    
    ALPValidatorRemoteRule *rule = [[ALPValidatorRemoteRule alloc] initWithType:ALPValidatorRuleTypeRemote serviceURL:(NSURL *)url invalidMessage:message completionHandler:^(BOOL remoteConditionSatisfied, NSError *error) {
        
        if (!error) {
            if (remoteConditionSatisfied) {
                [weakSelf removeValidationMessage:message];
                if (weakSelf.localConditionsSatisfied) {
                    weakSelf.state = ALPValidatorValidationStateValid;
                }
                else {
                    weakSelf.state = ALPValidatorValidationStateInvalid;
                }
            }
            else {
                weakSelf.state = ALPValidatorValidationStateInvalid;
            }
            
            if (weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(validator:remoteValidationAtURL:receivedResult:)]) {
                [weakSelf.delegate validator:self remoteValidationAtURL:url receivedResult:remoteConditionSatisfied];
            }
        }
        else {
            weakSelf.state = ALPValidatorValidationStateInvalid;
            if (weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(validator:remoteValidationAtURL:failedWithError:)]) {
                [weakSelf.delegate validator:self remoteValidationAtURL:url failedWithError:error];
            }
        }
    }];
    
    [self addValidationRule:rule];
}

- (void)addValidationToEnsureStringContainsNumberWithInvalidMessage:(NSString *)message
{
    [self raiseIncompatibilityException];
}

#pragma mark Incompatible Rules

- (void)raiseIncompatibilityException
{
    [NSException raise:@"ALPValidator Error" format:@"Attempted to add validation rule that is not compatible for validator type %@, %s", NSStringFromALPValidatorType(self.type), __PRETTY_FUNCTION__];
}

#pragma mark Validate

- (BOOL)isValid
{
    return (self.state == ALPValidatorValidationStateValid);
}

- (void)validate:(id)instance
{
    [self validate:instance parameters:nil sender:nil];
}

- (void)validate:(id)instance sender:(id)sender
{
    [self validate:instance parameters:nil sender:sender];
}

- (void)validate:(id)instance parameters:(NSDictionary *)parameters
{
    [self validate:instance parameters:parameters sender:nil];
}

- (void)validate:(id)instance parameters:(NSDictionary *)parameters sender:(id)sender
{

    [self clearErrorMessages];
    
    self.localConditionsSatisfied = YES;
    __block ALPValidatorState newState = ALPValidatorValidationStateValid;
    
    [self.rules enumerateObjectsUsingBlock:^(ALPValidatorRule *rule, NSUInteger idx, BOOL *stop) {
        
        switch (rule.type) {
            
            case ALPValidatorRuleTypeRemote: {
                ALPValidatorRemoteRule *remoteRule = (ALPValidatorRemoteRule *)rule;
                [self addErrorMessageForRule:rule];
                newState = ALPValidatorValidationStateWaitingForRemote;
                [remoteRule startRequestToValidateInstance:instance withParams:parameters];
                break;
            }
                
            default: {
                if (![rule isValidationRuleSatisfied:instance]) {
                    [self addErrorMessageForRule:rule];
                    self.localConditionsSatisfied = NO;
                    newState = ALPValidatorValidationStateInvalid;
                }
                break;
            }
        }
    }];
    
    [self updatePublicErrorMessages];
    
    if (sender)
        _sender = sender;
    
    self.state = newState;

    _sender = nil;
}

#pragma mark State Change

- (void)setState:(ALPValidatorState)state
{
    _state = state;
    if (self.validatorStateChangedHandler) {
        self.validatorStateChangedHandler(state, _sender);
    }
}

#pragma mark Messages

- (void)addErrorMessageForRule:(ALPValidatorRule *)rule
{
    [self.mutableErrorMessages addObject:rule.errorMessage];
}

- (void)clearErrorMessages
{
    [self.mutableErrorMessages removeAllObjects];
}

- (void)removeValidationMessage:(NSString *)message
{
    [self.mutableErrorMessages removeObjectIdenticalTo:message];
    [self updatePublicErrorMessages];
}

- (void)updatePublicErrorMessages
{
    self.errorMessages = [NSArray arrayWithArray:self.mutableErrorMessages];
}

#pragma mark Utilty

- (NSUInteger)ruleCount
{
    return [self.rules count];
}

@end