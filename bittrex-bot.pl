#!/usr/local/bin/perl

use lib '.';
use lib './bittrex-rest-api-pl/';

use strict;
use warnings;

use POSIX;
use Data::Dumper;
use JSON::PP::Boolean;
use Storable qw(dclone);
use DateTime;
use DateTime::TimeZone::Local;
use feature qw( say );

use GetConfig qw(getconfig setconfig appendconfig);
use BittrexAPIv3 qw(
    get_bittrex_api
    get_account
    get_addresses
    post_addresses
    get_balances
    head_balances
    del_conditional_orders
    get_conditional_orders
    post_conditional_orders
    get_currencies
    get_deposits
    head_deposits
    get_markets
    head_markets
    del_orders
    head_orders
    get_orders
    post_orders
    get_ping
    get_subaccounts
    post_subaccounts
    get_transfers
    post_transfers
    get_withdrawals
    del_withdrawals
    post_withdrawals
);
use ServiceSubs qw(showcomparevalues compare_hashes get_hashed);
use MarketAnalysis qw (checkforbuy checkforsell);

print "Begin program:\nInit variables...\n";
###############################################################################################
# Global variables
###############################################################################################
my $result = undef;

my $loglevel    = 5;
my $logfile     = 'bittrex-bot.log';
my $configfile  = 'config.json';

$result        = get_currencies(undef, $loglevel-1);
my $currencies = dclone get_hashed($result, 'symbol', $loglevel-1);
$result        = get_markets(undef, undef, undef, $loglevel-1);
my $markets    = dclone get_hashed($result, 'symbol', $loglevel-1);
logmessage("\n  - Got " . scalar keys (%{ $currencies }) . " currencies\n  - Got " . scalar keys (%{ $markets }) . " markets\n Reading config files...", $loglevel);

my $config = getconfig($configfile,0);
my $api = $config->{API};

if (!defined $config) {
    logmessage( " - error;\nConfig file not found - exit\n", $loglevel);
    exit 0;
} else { logmessage(" - ok;\n", $loglevel); }


logmessage(" Reading balances data\n", $loglevel);
$result = get_balances($api, undef, $loglevel-1);
my $balances = get_hashed($result, "currencySymbol");
$result = get_addresses($api, undef, $loglevel-1);
my $addresses = get_hashed($result, "currencySymbol");

my $tradelist = get_tradelist($config, $markets, $loglevel-1);

my $orderbook = undef;
my $orderlow  = undef;
my $orderhigh  = undef;

foreach my $marketname (keys %{ $tradelist }) {
    print Dumper $markets->{$marketname};
    $orderbook->{$marketname} = getconfig("db-".$marketname.".json",0);
    if (defined $orderbook->{$marketname}->{OpenOrders}) {
        foreach my $orderId (keys %{ $orderbook->{$marketname}->{OpenOrders} }) {
            my $order = get_orders($api, $orderId, undef, $loglevel);
            if (defined $order && $order->{status} eq "CLOSED") {
                if ($order->{direction} eq "BUY" && $order->{fillQuantity} < $markets->{$marketname}->{minTradeSize}) {
                    print "BAD ORDER:" . Dumper $order;
                    delete $orderbook->{$marketname}->{OpenOrders}->{$orderId};
                } else {
                    $orderbook->{$marketname}->{ClosedOrders}->{$orderId} = dclone $order;
                    delete $orderbook->{$marketname}->{OpenOrders}->{$orderId};
                }
            }
        }
    }
    $orderbook->{$marketname} = del_filledorders($orderbook->{$marketname});
    $orderlow->{$marketname} = get_orderlow($orderbook->{$marketname}->{ClosedOrders}, "BUY");
    $orderhigh->{$marketname} = get_orderhigh($orderbook->{$marketname}->{ClosedOrders}, "BUY");
    setconfig ("db-".$marketname.".json", 0, $orderbook->{$marketname});
}
print Dumper $tradelist;
print Dumper $orderbook;
print Dumper $orderlow;
#print Dumper $orderhigh;


my $marketanalysis = undef;
print "Begin trade loop:\n";

while(1) {
    my $datetime = sprintf ("%s %s",DateTime->now(time_zone => "local")->ymd ,DateTime->now(time_zone => "local")->hms);
    $marketanalysis->{current} = undef;
    my $marketsummaries = undef;
    $result = get_markets(undef, "tickers", undef, $loglevel);
    my $markettickers = get_hashed($result, "symbol");
    if (defined $markettickers) {
        foreach my $marketname (keys %{ $tradelist }) {
            if (!defined $marketanalysis->{new}->{$marketname}) {
                $marketanalysis->{new}->{$marketname}->{ticker}  = dclone $markettickers->{$marketname};
                $marketanalysis->{new}->{$marketname}->{trend}->{buy}  = $tradelist->{$marketname}->{buy}->{trend};
                $marketanalysis->{new}->{$marketname}->{trend}->{flag} = $tradelist->{$marketname}->{buy}->{flag};
                $marketanalysis->{new}->{$marketname}->{trend}->{sell} = $tradelist->{$marketname}->{sell}->{trend};
            } elsif (!defined $marketanalysis->{old}->{$marketname}) {
                $marketanalysis->{old}->{$marketname}->{ticker}  = dclone $marketanalysis->{new}->{$marketname}->{ticker};
                $marketanalysis->{old}->{$marketname}->{trend}->{buy}  = $marketanalysis->{new}->{$marketname}->{trend}->{buy};
                $marketanalysis->{old}->{$marketname}->{trend}->{flag} = $marketanalysis->{new}->{$marketname}->{trend}->{flag};
                $marketanalysis->{old}->{$marketname}->{trend}->{sell} = $marketanalysis->{new}->{$marketname}->{trend}->{sell};
                $marketanalysis->{new}->{$marketname}->{ticker}  = dclone $markettickers->{$marketname};
            } else {
                if ($marketanalysis->{new}->{$marketname}->{ticker}->{lastTradeRate} != $markettickers->{$marketname}->{lastTradeRate}) {
                    $marketanalysis->{old}->{$marketname}->{ticker}  = dclone $marketanalysis->{new}->{$marketname}->{ticker};
                    $marketanalysis->{new}->{$marketname}->{ticker}  = dclone $markettickers->{$marketname};
                    $marketanalysis->{old}->{$marketname}->{trend}->{buy}  = $marketanalysis->{new}->{$marketname}->{trend}->{buy};
                    $marketanalysis->{old}->{$marketname}->{trend}->{flag} = $marketanalysis->{new}->{$marketname}->{trend}->{flag};
                    $marketanalysis->{old}->{$marketname}->{trend}->{sell} = $marketanalysis->{new}->{$marketname}->{trend}->{sell};
                    if ($marketanalysis->{new}->{$marketname}->{ticker}->{lastTradeRate} <= $marketanalysis->{new}->{$marketname}->{ticker}->{bidRate}) {
                        $marketanalysis->{new}->{$marketname}->{trend}->{buy} += $tradelist->{$marketname}->{buy}->{stepback};
                        if ($marketanalysis->{new}->{$marketname}->{trend}->{buy} > $tradelist->{$marketname}->{buy}->{maxtrend}) {
                            $marketanalysis->{new}->{$marketname}->{trend}->{buy} = $tradelist->{$marketname}->{buy}->{maxtrend};
                        }
                        $marketanalysis->{new}->{$marketname}->{trend}->{sell} -= $tradelist->{$marketname}->{sell}->{stepforward};
                        if ($marketanalysis->{new}->{$marketname}->{trend}->{sell} < 0) {
                            $marketanalysis->{new}->{$marketname}->{trend}->{sell} = 0;
                        }
                    } elsif ($marketanalysis->{new}->{$marketname}->{ticker}->{lastTradeRate} >= $marketanalysis->{new}->{$marketname}->{ticker}->{askRate}) {
                        $marketanalysis->{new}->{$marketname}->{trend}->{buy} -= $tradelist->{$marketname}->{buy}->{stepforward};
                        if ($marketanalysis->{new}->{$marketname}->{trend}->{buy} < 0) {
                            $marketanalysis->{new}->{$marketname}->{trend}->{buy} = 0;
                        }
                        $marketanalysis->{new}->{$marketname}->{trend}->{sell} += $tradelist->{$marketname}->{sell}->{stepback};
                        if ($marketanalysis->{new}->{$marketname}->{trend}->{sell} > $tradelist->{$marketname}->{sell}->{maxtrend}) {
                            $marketanalysis->{new}->{$marketname}->{trend}->{sell} = $tradelist->{$marketname}->{sell}->{maxtrend};
                        }
                    }
                    if (!defined $marketsummaries) {
                        $result = get_markets(undef, "summaries", undef, $loglevel);
                        $marketsummaries = get_hashed($result, "symbol");
                    }
                    my $candles_short = get_markets($marketname, "candles/MIDPOINT/MINUTE_5/recent", undef, $loglevel); # MINUTE_1: 1 day, MINUTE_5: 1 day, HOUR_1: 31 days, DAY_1: 366 days
                    my $candles_long  = get_markets($marketname, "candles/MIDPOINT/HOUR_1/recent", undef, $loglevel); # MINUTE_1: 1 day, MINUTE_5: 1 day, HOUR_1: 31 days, DAY_1: 366 days
                    if (defined $marketsummaries->{$marketname} && defined $candles_short && defined $candles_long) {
                        $marketanalysis->{current}->{$marketname}->{ticker}  = dclone $markettickers->{$marketname};
                        $marketanalysis->{current}->{$marketname}->{summary} = dclone $marketsummaries->{$marketname};
                        $marketanalysis->{current}->{$marketname}->{config}  = dclone $tradelist->{$marketname};
                        $marketanalysis->{current}->{$marketname}->{trend}   = dclone $marketanalysis->{new}->{$marketname}->{trend};
                        $marketanalysis->{current}->{$marketname}->{candles_short} = dclone $candles_short;
                        $marketanalysis->{current}->{$marketname}->{candles_long}  = dclone $candles_long;
                    }
                }
            }
            if (defined $orderbook->{$marketname}->{OpenOrders} && scalar keys %{ $orderbook->{$marketname}->{OpenOrders} } > 0) {
                foreach my $orderId (keys %{ $orderbook->{$marketname}->{OpenOrders} }) {
                    my $order = get_orders($api, $orderId, undef, $loglevel);
                    if (defined $order) {
                        if ($order->{status} ne "CLOSED") {
                            print "\n!!!!!!!!!!!!!!!!!               Order with id $orderId not closed - cancel it\n";
                            my $orders = del_orders($api, $orderId, undef, $loglevel);
                            print Dumper $orders;
                            delete $orderbook->{$marketname}->{OpenOrders}->{$orderId};
                        } else {
                            if ($order->{direction} eq "BUY" && $order->{fillQuantity} < $markets->{$marketname}->{minTradeSize}) {
                                print "BAD ORDER:" . Dumper $order;
                                delete $orderbook->{$marketname}->{OpenOrders}->{$orderId};
                            } else {
                                $orderbook->{$marketname}->{ClosedOrders}->{$orderId} = dclone $order;
                                if (defined $orderbook->{$marketname}->{OpenOrders}->{$orderId}->{StopLoss} && $orderbook->{$marketname}->{OpenOrders}->{$orderId}->{StopLoss} == 1) {
                                    $orderbook->{$marketname}->{ClosedOrders}->{$orderId}->{StopLoss} = 1;
                                }
                                delete $orderbook->{$marketname}->{OpenOrders}->{$orderId};
                                $marketanalysis->{new}->{$marketname}->{trend}->{flag} = 0;
                            }
                        }
                    }
                }
                $orderbook->{$marketname} = del_filledorders($orderbook->{$marketname});
                $orderlow->{$marketname} = get_orderlow($orderbook->{$marketname}->{ClosedOrders}, "BUY");
                $orderhigh->{$marketname} = get_orderhigh($orderbook->{$marketname}->{ClosedOrders}, "BUY");
                print Dumper $orderbook;
                print Dumper $orderlow;
                print Dumper $orderhigh;
                setconfig ("db-".$marketname.".json", 0, $orderbook->{$marketname});
            }
        }
    } else {
        $marketanalysis = undef;
        logmessage("Warning: Undefined values\n", $loglevel);
    }
    if (defined $marketanalysis->{current}) {
        foreach my $marketname (keys %{ $marketanalysis->{current} }) {
            my $change = "( )";
            if ($marketanalysis->{current}->{$marketname}->{ticker}->{lastTradeRate} > $marketanalysis->{old}->{$marketname}->{ticker}->{lastTradeRate}) {
                $change = "(+)";
            } else {
                $change = "(-)";
            }
            my @output = (
                $datetime,
                $marketname,
                $marketanalysis->{current}->{$marketname}->{ticker}->{bidRate},
                $marketanalysis->{current}->{$marketname}->{ticker}->{askRate},
                $change,
                $marketanalysis->{current}->{$marketname}->{ticker}->{lastTradeRate},
                $marketanalysis->{current}->{$marketname}->{trend}->{buy},
                $marketanalysis->{current}->{$marketname}->{trend}->{sell}
            );
            printf ("%s %s --> TICKER   Bid: %.8f; Ask: %.8f;    Last %s: %.8f; Buytrend: %d; Selltrend: %d;\n", @output);
            @output = (
                $datetime,
                $marketname,
                $marketanalysis->{current}->{$marketname}->{summary}->{high},
                $marketanalysis->{current}->{$marketname}->{summary}->{low},
                ($marketanalysis->{current}->{$marketname}->{summary}->{high} + $marketanalysis->{current}->{$marketname}->{summary}->{low})/2,
                $marketanalysis->{current}->{$marketname}->{summary}->{percentChange},
                $marketanalysis->{current}->{$marketname}->{trend}->{flag}
            );
            printf ("%s %s --> SUMMARY High: %.8f; Low: %.8f; 24h Average: %.8f; Spread: %.2f; Flag: %s\n", @output);

            print "$datetime $marketname --> Check for sell:\n";
            my $sellcheck = undef;
            if (defined $orderlow->{$marketname} && defined $orderhigh->{$marketname}) {
                $sellcheck = checkforsell($marketanalysis->{current}->{$marketname}, $orderlow->{$marketname}, $orderhigh->{$marketname}, $loglevel);
                if ($sellcheck) {
                    appendconfig($logfile,0, "$datetime $marketname --> !!!Wanna sell!!!");
                    my $limit = $marketanalysis->{current}->{$marketname}->{ticker}->{bidRate};
                    my $quantity = undef;
                    if ($sellcheck == 1) {
                        $quantity = $orderlow->{$marketname}->{fillQuantity};
                    } else {
                        $quantity = $orderhigh->{$marketname}->{fillQuantity};
                    }
                    my $newOrder = {
                        marketSymbol  => $marketname,                 #
                        direction     => "SELL",                      # BUY, SELL
                        type          => "LIMIT",                     # LIMIT, MARKET, CEILING_LIMIT, CEILING_MARKET
                        quantity      => sprintf ("%.8f", $quantity), #
                        limit         => sprintf ("%.8f", $limit),    #
                        timeInForce   => "FILL_OR_KILL"               # GOOD_TIL_CANCELLED, IMMEDIATE_OR_CANCEL, FILL_OR_KILL, POST_ONLY_GOOD_TIL_CANCELLED, BUY_NOW
                    };
                    print Dumper $newOrder;
                    my $order = post_orders($api, $newOrder, $loglevel);
                    if (defined $order) {
                        $orderbook->{$marketname}->{OpenOrders}->{$order->{id}} = dclone $order;
                        if ($sellcheck == 2) {
                            $orderbook->{$marketname}->{OpenOrders}->{$order->{id}}->{StopLoss} = 1;
                        }
                        setconfig("db-".$marketname.".json", 0, $orderbook->{$marketname});
                        print Dumper $orderbook;
                    }
                }
            } else {
                print "$datetime $marketname --> No orders for sell\n";
            }

            print "$datetime $marketname --> Check for buy:\n";
            my $buycheck = undef;
            if (defined $orderlow->{$marketname} && defined $orderlow->{$marketname}->{limit} && $orderlow->{$marketname}->{limit} > 0) {
                my $nextorder = $marketanalysis->{current}->{$marketname}->{ticker}->{askRate} / $orderlow->{$marketname}->{limit};
                printf ("$datetime $marketname --> nextorder = %.3f\n", $nextorder);
                if ($nextorder < $marketanalysis->{current}->{$marketname}->{config}->{buy}->{nextbuyorder}) {
                    $buycheck = checkforbuy($marketanalysis->{current}->{$marketname}, $loglevel);
                }
            } else {
                $buycheck = checkforbuy($marketanalysis->{current}->{$marketname}, $loglevel);
            }
            if ($buycheck) {
                if ($buycheck == 2) {
                    $marketanalysis->{new}->{$marketname}->{trend}->{flag} = 1;
                } elsif ($buycheck == 3) {
                    $marketanalysis->{new}->{$marketname}->{trend}->{flag} = 0;
                } else {
                    appendconfig($logfile,0, "$datetime $marketname --> !!!Wanna buy!!!");
                    my $limit    = $marketanalysis->{current}->{$marketname}->{ticker}->{askRate};
                    my $quantity = $tradelist->{$marketname}->{buy}->{orderquantity};
                    if (defined $tradelist->{$marketname}->{buy}->{orderprice} && $tradelist->{$marketname}->{buy}->{orderprice} * $tradelist->{$marketname}->{sell}->{stoploss} * 0.95 > $markets->{$marketname}->{minTradeSize} * $limit) {
                        $quantity = $tradelist->{$marketname}->{buy}->{orderprice} / $limit;
                    }
                    if (defined $orderlow->{$marketname}->{quantity} && defined $tradelist->{$marketname}->{buy}->{nextpriceinc}) {
                        $quantity = $orderlow->{$marketname}->{quantity} * $tradelist->{$marketname}->{buy}->{nextpriceinc};
                    }
                    my $newOrder = {
                        marketSymbol  => $marketname,                   #
                        direction     => "BUY",                         # BUY, SELL
                        type          => "LIMIT",                       # LIMIT, MARKET, CEILING_LIMIT, CEILING_MARKET
                        quantity      => sprintf ("%.8f", $quantity),   #
                        limit         => sprintf ("%.8f", $limit),      #
                        timeInForce   => "FILL_OR_KILL"                 # GOOD_TIL_CANCELLED, IMMEDIATE_OR_CANCEL, FILL_OR_KILL, POST_ONLY_GOOD_TIL_CANCELLED, BUY_NOW
                    };
                    print Dumper $newOrder;
                    my $order = post_orders($api, $newOrder, 10);
                    if (defined $order) {
                        $orderbook->{$marketname}->{OpenOrders}->{$order->{id}} = dclone $order;
                        setconfig("db-".$marketname.".json", 0, $orderbook->{$marketname});
                        print Dumper $orderbook;
                    }
                }
            }
        }
    }
}

###############################################################################################
# Subroutines
###############################################################################################

sub get_orderlow {
    my $orders   = $_[0];
    my $direcion = $_[1];
    my $orderlow = undef;
    if (defined $orders) {
        foreach my $orderId  (keys %{ $orders }) {
            my $order = $orders->{$orderId};
            if ($order->{direction} eq $direcion && (!defined $orderlow || $orderlow->{limit} > $order->{limit})) {
                $orderlow = dclone $order;
            }
        }
    }
    return $orderlow;
}

sub get_orderhigh {
    my $orders   = $_[0];
    my $direcion = $_[1];
    my $orderhigh = undef;
    if (defined $orders) {
        foreach my $orderId  (keys %{ $orders }) {
            my $order = $orders->{$orderId};
            if ($order->{direction} eq $direcion && (!defined $orderhigh || $orderhigh->{limit} < $order->{limit})) {
                $orderhigh = dclone $order;
            }
        }
    }
    return $orderhigh;
}

sub del_filledorders {
    my $orderbook = $_[0];
    print Dumper $orderbook;
    my $sellorderlow = get_orderlow($orderbook->{ClosedOrders}, "SELL");
    my $buyorderlow  = get_orderlow($orderbook->{ClosedOrders}, "BUY");
#    my $sellorderhigh = get_orderhigh($orderbook->{ClosedOrders}, "SELL");
    my $buyorderhigh  = get_orderhigh($orderbook->{ClosedOrders}, "BUY");
    while (defined $sellorderlow) {
        if (defined $sellorderlow->{StopLoss}) {
            print "Found stoploss order! - removing buy(high)+sell orders\n";
            delete $orderbook->{ClosedOrders}->{$buyorderhigh->{id}};
            delete $orderbook->{ClosedOrders}->{$sellorderlow->{id}};
        } elsif ($sellorderlow->{limit} >= $buyorderlow->{limit}) {
            print "Found fullfilled order! - removing buy+sell orders\n";
            delete $orderbook->{ClosedOrders}->{$buyorderlow->{id}};
            delete $orderbook->{ClosedOrders}->{$sellorderlow->{id}};
        } elsif ($sellorderlow->{limit} < $buyorderlow->{limit}) {
            print "Found stoploss order! - removing buy(low)+sell orders\n";
            delete $orderbook->{ClosedOrders}->{$buyorderlow->{id}};
            delete $orderbook->{ClosedOrders}->{$sellorderlow->{id}};
        }
        $sellorderlow = get_orderlow($orderbook->{ClosedOrders}, "SELL");
        $buyorderlow  = get_orderlow($orderbook->{ClosedOrders}, "BUY");
        $buyorderhigh = get_orderhigh($orderbook->{ClosedOrders}, "BUY");
    }
    return $orderbook;
}

sub get_tradelist {
    my $config   = $_[0];
    my $markets  = $_[1];
    my $loglevel = $_[2];
    my $result   = undef;
    if (scalar keys(%{ $config->{Markets} }) > 0 ) {
        logmessage (" Found " .  scalar keys(%{ $config->{Markets} }) . " markets for trade:\n", $loglevel);
        foreach my $marketname (keys %{ $config->{Markets} }) {
            logmessage ("\t" . $marketname, $loglevel);
            if (defined $markets->{$marketname}) {
                logmessage (" - looks good, added for trade\n", $loglevel);
                my $defaultlimits = {
                    "buy" => {
                        "trend"         => 15,
                        "mintrend"      => 10,
                        "maxtrend"      => 30,
                        "stepforward"   => 2,
                        "stepback"      => 3,
                        "diffratelow"   => 0.15,
                        "diffratehigh"  => 0.3,
                        "minspread"     => -7,
                        "orderquantity" => $markets->{$marketname}->{minTradeSize}*2,
                        "summarylimit"  => undef,
                        "historycheck"  => 48,
                        "div"           => 1,
                        "nextbuyorder"  => 0.975,
                        "flag"          => 0,
                        "shortemadepth" => 12,
                        "longemadepth"  => 24,
#                        "orderprice"    => 10,
                        "nextpriceinc"  => 1.05
                    },
                    "sell" => {
                        "trend"         => 10,
                        "mintrend"      => 4,
                        "maxtrend"      => 35,
                        "stepforward"   => 2,
                        "stepback"      => 3,
                        "nextsellorder" => 0.03,
                        "stoploss"      => 0.75,
                        "div"           => 1
                    }
                };
                $result->{$marketname} = dclone $defaultlimits;
                foreach my $key (keys %{ $config->{Markets}->{$marketname}->{buy} }) {
                    $result->{$marketname}->{buy}->{$key} = $config->{Markets}->{$marketname}->{buy}->{$key};
                }
                foreach my $key (keys %{ $config->{Markets}->{$marketname}->{sell} }) {
                    $result->{$marketname}->{sell}->{$key} = $config->{Markets}->{$marketname}->{sell}->{$key};
                }
            } else {
                logmessage (" - not exists, skip\n", $loglevel);
            }
        }
    } else {
        logmessage ("Error, no markets for trade; exit\n", $loglevel);
        exit 0;
    }
    return $result;
}

sub logmessage {
    my $string = $_[0];
    my $loglevel = $_[1];
    if (defined $loglevel && $loglevel > 5) { print $string; }
}
