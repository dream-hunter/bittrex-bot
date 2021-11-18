package MarketAnalysis;

use lib './bittrex-rest-api-pl/';

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

#use Exporter;
use JSON        qw(from_json);
use Digest::SHA qw(hmac_sha512_hex);
#use Data::Dumper;
#use HTTP::Request;
#use WWW::Curl::Easy;
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


$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(checkforbuy checkforsell
                 );
%EXPORT_TAGS =  ( DEFAULT =>
                    [qw(&checkforbuy &checkforsell
                    )]
                );

sub logmessage {
    my $string = $_[0];
    my $loglevel = $_[1];
    if (defined $loglevel && $loglevel > 5) { print $string; }
}

sub emacalc {
    my $candles = $_[0];
    my $alpha   = $_[1];
    my $depth   = $_[2];
    my $ema     = 0;
    my $length  = scalar @{ $candles };
    if (defined $depth && $depth > 0) {
        foreach my $i (reverse 1..$depth ) {
            my $candle = $candles->[$length-$i];
            if (defined $ema && $ema != 0) {
                $ema = $alpha * (($candle->{low} + $candle->{high}) / 2) + (1-$alpha) * $ema;
            } else {
                $ema = ($candle->{low} + $candle->{high}) / 2;
            }
        }
    }
    return $ema;
}

sub checkforbuy {
    my $marketanalysis = $_[0];
    my $loglevel       = $_[1];
    my $marketname     = $marketanalysis->{summary}->{symbol};
    my $datetime = sprintf ("%s %s",DateTime->now(time_zone => "local")->ymd ,DateTime->now(time_zone => "local")->hms);
# EMA short/long
    if (!defined $marketanalysis->{trend}->{flag} || $marketanalysis->{trend}->{flag} != 1) {
        my $alpha     = 0.125;
        my $ema_short = emacalc($marketanalysis->{candles_short}, $alpha, $marketanalysis->{config}->{buy}->{shortemadepth});
        my $ema_long  = emacalc($marketanalysis->{candles_long}, $alpha, $marketanalysis->{config}->{buy}->{longemadepth});
        printf "$datetime $marketname --> EMA short: %.8f; long: %.8f\n", $ema_short, $ema_long;
        if ($ema_short < $ema_long) {
            return 2;
        }
        return undef;
    };
# Spread
    if (!defined $marketanalysis->{summary}->{percentChange} || $marketanalysis->{summary}->{percentChange} < $marketanalysis->{config}->{buy}->{minspread}) {
        print "$datetime $marketname --> spread is too low: " . $marketanalysis->{summary}->{percentChange} . "\n";
        return undef;
    } else {
        print "$datetime $marketname --> spread is fine: " . $marketanalysis->{summary}->{percentChange} . "\n"
    }
# Trend
    if (!defined $marketanalysis->{trend}->{buy} || $marketanalysis->{trend}->{buy} > $marketanalysis->{config}->{buy}->{mintrend}) {
        print "$datetime $marketname --> trend is too high: " . $marketanalysis->{trend}->{buy} . "\n";
        return undef;
    } else {
        print "$datetime $marketname --> trend is fine: " . $marketanalysis->{trend}->{buy} . "\n"
    }
# DiffRate
    if (!defined $marketanalysis->{ticker}->{lastTradeRate}) {
        print "$datetime $marketname --> not enough data\n";
        return undef;
    } else {
#        my $markets = get_markets($marketname, "candles", "candleInterval=HOUR_1", $loglevel); # MINUTE_1, MINUTE_5, HOUR_1, DAY_1
        my $candles = $marketanalysis->{candles_long};
        my $counter = 0;
        my $maxvalue = 0;
        my $minvalue = 0;
        foreach my $candle (reverse @{ $candles }) {
            if ($minvalue == 0 || $minvalue > $candle->{"low"}) {
                $minvalue = $candle->{low};
            }
            if ($maxvalue == 0 || $maxvalue < $candle->{"high"}) {
                $maxvalue = $candle->{high};
            }
            last if ($counter ++ >= $marketanalysis->{config}->{buy}->{historycheck});
        }
        print "$datetime $marketname --> $marketanalysis->{config}->{buy}->{historycheck} hours minvalue = $minvalue;\n";
        print "$datetime $marketname --> $marketanalysis->{config}->{buy}->{historycheck} hours maxvalue = $maxvalue;\n";

        my $diffrate = $maxvalue - $minvalue;
        if (($maxvalue - $diffrate * $marketanalysis->{config}->{buy}->{diffratehigh}) <= $marketanalysis->{ticker}->{lastTradeRate}) {
            print "$datetime $marketname --> high extremum check not good: " . $marketanalysis->{ticker}->{lastTradeRate} . " >= ".($maxvalue - $diffrate * $marketanalysis->{config}->{buy}->{diffratehigh}) . "\n";
            return 3;
        } else {
            print "$datetime $marketname --> high extremum check is fine: " . $marketanalysis->{ticker}->{lastTradeRate} . " < ".($maxvalue - $diffrate * $marketanalysis->{config}->{buy}->{diffratehigh}) . "\n";
        }
        if (($minvalue + $diffrate * $marketanalysis->{config}->{buy}->{diffratelow}) >= $marketanalysis->{ticker}->{lastTradeRate}) {
            print "$datetime $marketname --> low extremum check not good: " . $marketanalysis->{ticker}->{lastTradeRate} . " <= ".($minvalue + $diffrate * $marketanalysis->{config}->{buy}->{diffratelow}) . "\n";
            return undef;
        } else {
            print "$datetime $marketname --> low extremum check is fine: " . $marketanalysis->{ticker}->{lastTradeRate} . " > ".($minvalue + $diffrate * $marketanalysis->{config}->{buy}->{diffratelow}) . "\n";
        }
    }
#Sells more than buy
    my $markethistory = get_markets($marketname, "trades", undef, $loglevel);
    if (defined $markethistory) {
        my $BuyQuantity  = 0;
        my $SellQuantity = 0;
        foreach my $value (values @{ $markethistory }) {
            if ($value->{takerSide} eq "SELL") {
                $SellQuantity++;
            }
            if ($value->{takerSide} eq "BUY") {
                $BuyQuantity++;
            }
        }
        print "$datetime $marketname --> Bids - Sells = $BuyQuantity - $SellQuantity = ". ($BuyQuantity - $SellQuantity);
        if (($BuyQuantity - $SellQuantity) <= 10) {
            print " <= 10 - bad;\n";
            return (undef);
        } else {
            print " > 10 - good;\n";
        }
    } else {
        print "$datetime $marketname --> No market data\n";
        return undef;
    }
#Moving average
# EMA
# EMA (t) = EMA (t-1)+ 2 *(P(t) . EMA (t-1))
# N . число периодов расчета скользящей средней;
# t . период расчета;
# t-1 . период, предшествующий периоду расчета;
# P(t) . цена закрытия за период расчета;
# EMA(t-1) . экспоненциальная средняя за период, предшествующий периоду расчета
    my $candles = $marketanalysis->{candles_short};
    my $alpha   = 0.125;
    my $ema     = 0;
    foreach my $candle (values @{ $candles }) {
        if (defined $ema && $ema != 0) {
            $ema = $alpha * (($candle->{low} + $candle->{high}) / 2) + (1-$alpha) * $ema;
        } else {
            $ema = ($candle->{low} + $candle->{high}) / 2;
        }
    }
    printf "$datetime $marketname --> Last: %s Ema: %s Div: %.2f\n", $marketanalysis->{ticker}->{lastTradeRate}, $ema, $marketanalysis->{ticker}->{lastTradeRate}/$ema*100;
    if (!defined $marketanalysis->{ticker}->{lastTradeRate} || !defined $ema || $marketanalysis->{ticker}->{lastTradeRate}/$ema < $marketanalysis->{config}->{buy}->{div}) {
        print "$datetime $marketname --> Ema-Div is too low\n";
        return undef;
    } else {
        print "$datetime $marketname --> Ema-Div is fine to buy\n";
    }
    print "\n!!!Wanna buy!!!\n";
#    appendconfig($logfile,0, "!!!Wanna buy!!!");
    return 1;
}

sub checkforsell {
    my $marketanalysis = $_[0];
    my $orderlow       = $_[1];
    my $orderhigh      = $_[2];
    my $loglevel       = $_[3];
    my $marketname = $marketanalysis->{summary}->{symbol};
    my $datetime = sprintf ("%s %s", DateTime->now(time_zone => "local")->ymd, DateTime->now(time_zone => "local")->hms);
# Stoploss
    if (defined $orderhigh && $orderhigh->{limit} * $marketanalysis->{config}->{sell}->{stoploss} > $marketanalysis->{ticker}->{bidRate}) {
        print "$datetime $marketname --> Stoploss required: " . $orderhigh->{limit} * $marketanalysis->{config}->{sell}->{stoploss} . " > " . $marketanalysis->{ticker}->{bidRate} . "\n";
        return 2;
    }
# Trend
    if (!defined $marketanalysis->{trend}->{sell} || $marketanalysis->{trend}->{sell} > $marketanalysis->{config}->{sell}->{mintrend}) {
        print "$datetime $marketname --> trend is too high: " . $marketanalysis->{trend}->{sell} . "\n";
        return undef;
    } else {
        print "$datetime $marketname --> trend is fine: " . $marketanalysis->{trend}->{sell} . "\n"
    }
# Limit check
    if (!defined $orderlow || ($marketanalysis->{ticker}->{bidRate}/$orderlow->{limit} <= (1+$marketanalysis->{config}->{sell}->{nextsellorder}))) {
        printf ("$datetime $marketname --> sell limit is too low: %.4f <= %.4f\n", ($marketanalysis->{ticker}->{bidRate}/$orderlow->{limit}), (1+$marketanalysis->{config}->{sell}->{nextsellorder}));
        return undef;
    } else {
        printf ("$datetime $marketname --> sell limit is good: %.4f > %.4f\n", ($marketanalysis->{ticker}->{bidRate}/$orderlow->{limit}), (1+$marketanalysis->{config}->{sell}->{nextsellorder}));
    }
# EMA
    my $marketname = $marketname;
    my $candles = get_markets($marketname, "candles/MIDPOINT/MINUTE_5/recent", undef, $loglevel); # MINUTE_1, MINUTE_5, HOUR_1, DAY_1
    my $alpha   = 0.125;
    my $ema     = 0;
    foreach my $candle (values @{ $candles }) {
        if (defined $ema && $ema != 0) {
            $ema = $alpha * (($candle->{low} + $candle->{high}) / 2) + (1-$alpha) * $ema;
        } else {
            $ema = ($candle->{low} + $candle->{high}) / 2;
        }
    }
#    my $ticker = get_markets($marketname, "ticker", undef, $loglevel);
#    print "Datetime : ", DateTime->now(time_zone => "local")->hms;
    printf "$datetime $marketname --> Last: %s Ema: %s Div: %.2f\n", $marketanalysis->{ticker}->{lastTradeRate}, $ema, $marketanalysis->{ticker}->{lastTradeRate}/$ema*100;
    if (!defined $marketanalysis->{ticker}->{lastTradeRate} || !defined $ema || $marketanalysis->{ticker}->{lastTradeRate}/$ema > $marketanalysis->{config}->{sell}->{div}) {
        print "$datetime $marketname --> Ema-Div is too high\n";
        return undef;
    } else {
        print "$datetime $marketname --> Ema-Div is fine to sell\n";
    }
    return 1;
}

1;
