#!/usr/bin/env perl

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

###############################################################################################
# Global variables
###############################################################################################
my $result = undef;

my $loglevel    = 5;
my $logfile     = 'bittrex-bot.log';
my $configfile  = 'config.json';
my $config      = undef;
my $market      = undef;
my $marketname  = undef;
my $orderbook   = undef;

if (!defined $ARGV[0] || $ARGV[0] eq "-h" || $ARGV[0] eq "?") {
    print "\nUsage:\n";
    print "\n-h - prints these message\n Example:\n  ./bittrex-orders.pl -h\n";
    print "\n-m <marketname> - requred parameter;\n Example:\n  ./bittrex-orders.pl -m BTC-USD\n";
    print "\n-l - list of CLOSED orders;\n Example:\n  ./bittrex-orders.pl -m BTC-USD -l\n";
    print "\n-a - add order to orderbook with following order-Id;\n Example:\n  ./bittrex-orders.pl -m BTC-USD -a 1a84083a-8e6e-4d60-b172-8ed1a92ecf4a\n";
    print "\n-d - delete order from orderbook with following order-Id;\n Example:\n  ./bittrex-orders.pl -m BTC-USD -d 1a84083a-8e6e-4d60-b172-8ed1a92ecf4a\n\n";
}
if (defined $ARGV[0] && $ARGV[0] eq "-m" && defined $ARGV[1]) {
    $market     = get_markets($ARGV[1], undef, undef, $loglevel);
    if (defined $market) {
        $marketname = $ARGV[1];
        $config     = getconfig($configfile, $loglevel);
        $orderbook  = getconfig("db-".$marketname.".json",0);
#        print Dumper $market;
    } else {
        logmessage("\nMarket not exists\n", 10);
        exit 0;
    }
}

if (defined $market && defined $ARGV[2] && $ARGV[2] eq "-l") {
    my $orders = get_orders($config->{API}, "closed", "marketSymbol=".$market->{symbol}, $loglevel);
    logmessage ("\nLoading from bittrex:\n", 10);
    print_orders($orders);
    logmessage ("\nLoading from orderbook:\n", 10);
    $orders = undef;
    foreach my $orderid (keys %{ $orderbook->{ClosedOrders} }) {
        my $order = $orderbook->{ClosedOrders}->{$orderid};
        push @{ $orders }, $order;
    }
    if (defined $orders) {
        print_orders($orders);
    } else {
        print ("\nOrderbook is empty.\n");
    }
}
if (defined $market && defined $ARGV[2] && $ARGV[2] eq "-a" && defined $ARGV[3]) {
    logmessage ("\nAppend order with ID $ARGV[3] to orderbook...", 10);
    my $orderId = $ARGV[3];
    my $order = get_orders($config->{API}, $orderId, undef, $loglevel);
#    print Dumper $order;
    if (defined $order && $order->{marketSymbol} eq $market->{symbol}) {
        $orderbook->{ClosedOrders}->{$orderId} = $order;
        setconfig("db-".$marketname.".json", 0, $orderbook);
        logmessage (" - success\n", 10);
    } else {
        logmessage (" - error\n", 10);
    }
#    print Dumper $orderbook;
}
if (defined $market && defined $ARGV[2] && $ARGV[2] eq "-d" && defined $ARGV[3]) {
    logmessage ("\nDelete order with ID $ARGV[3] from orderbook...", 10);
    my $orderId = $ARGV[3];
    if (defined $orderbook->{ClosedOrders}->{$orderId}) {
        delete $orderbook->{ClosedOrders}->{$orderId};
        setconfig("db-".$marketname.".json", 0, $orderbook);
        logmessage (" - success\n", 10);
    } else {
        logmessage (" - error\n", 10);
    }
}

sub print_orders {
    my $orders = $_[0];
    logmessage ("\nclosedAt direction  quantity fillQuantity limit proceeds (include commission) id\n", 10);
    foreach my $order ( @{ $orders }) {
        my $str = sprintf ("%-25s %-4s %.8f %.8f %.8f %.8f (%.8f) %s\n",
            $order->{closedAt},
            $order->{direction},
            $order->{quantity},
            $order->{fillQuantity},
            $order->{limit},
            $order->{proceeds},
            $order->{commission},
            $order->{id}
        );
        logmessage($str, 10);
    }
}

sub logmessage {
    my $string = $_[0];
    my $loglevel = $_[1];
    if (defined $loglevel && $loglevel > 5) { print $string; }
}
