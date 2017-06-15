#import <Foundation/Foundation.h>
#import "TradeItBrokerServices.h"
#import <JSONModel/JSONModel.h>

@protocol TradeItBroker

@end

@interface TradeItBroker : JSONModel

@property (nullable, nonatomic, copy) NSString *shortName;

@property (nullable, nonatomic, copy) NSString *longName;

@property (nonatomic) BOOL featuredStockBroker;
@property (nonatomic) BOOL featuredFxBroker;

@property (nonatomic, nullable) TradeItBrokerServices <Optional> *services;

- (nonnull id)initWithShortName:(NSString * _Nullable)brokerShortName
                       longName:(NSString * _Nullable)brokerLongName;

@property (nonatomic, nullable) NSString <Ignore> *brokerShortName;
@property (nonatomic, nullable) NSString <Ignore> *brokerLongName;

@end
