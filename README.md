# bittrex-bot

This opensource project was created for basic trade on bittrex global. Use on your own risks.

# Donations

If you wanna help my project, send your donations to the following wallets:

```
BTC: 17kZJHjouZqLmMwntg2M6zzdEW3Jivx79o
ETH: 0xda1be63336b49e25201d2f406f01b1989f6146c1
```
# Warnings

1. Restict access to server! Never use bot on servers with third party access! API key/secrets is unencrypted in config file.
2. Avoid to allow access even for configuration helpers.
3. Don't share any information about your trading server to avoid targeted network attacks.
4. Use SSHGuard and Firewalls to protect your server.
5. Don't store API keys/secrets on your home computer. Sometime generate new and delete/block old API keys.

Your security - your money!

# Advices

Do not use the bot for trading on more than 5 markets. This is about Bittrex Web API restictions - getting market information will be too slow for proper react.
It is possible to increase performance by writing a new bot that will use socket API. Current version is enough for me and nobody pays me for development.

# System prerequisites

 1. Installed linux OS (ubuntu/centos etc)
 2. Latest Perl with modules:
    - JSON
    - Data::Dumper
    - Digest::SHA
    - REST::Client
    - Time::HiRes
    - Storable
    - DateTime
    - DateTime::TimeZone::Local
    - HTTP::Request Exporter
    - WWW::Curl::Easy
 3. Installed git
 4. Verified Bittrex Account with activated Two-Factor Authentication
 5. Synchronized time on your host computer
 6. Internet access to Bittrex API endpoint https://api.bittrex.com/v3 / https://api.bittrex.com/api/v1.1

# Ubuntu libraries installation

```
sudo apt update
sudo apt upgrade
sudo apt install -y git perl build-essential cpanminus cpanoutdated screen libcurl4-openssl-dev libcurl4-gnutls-dev libwww-curl-perl libnamespace-autoclean-perl
sudo apt install librest-client-perl libjson-perl libdata-dumper-concise-perl libdigest-sha-perl libtime-hr-perl
cpan-outdated -p | cpanm --sudo
cpanm --sudo Storable DateTime DateTime::TimeZone::Local HTTP::Request Exporter
```
# Bot installation

```
git clone https://github.com/dream-hunter/bittrex-bot.git
cd bittrex-bot
git clone https://github.com/dream-hunter/bittrex-rest-api-pl.git
```

# Screen logging and logrotate

```
echo "logfile /var/log/screenlog" >> /etc/screenrc
cp screenlog.logrotate /etc/logrotate.d/screenlog
```

# Bot configuration

All settings stores in config.json file. To get started you have to:
1. Copy/rename config.json.example:

```
cp config.json.example config.json
```

2. Edit "apikey" and "apisecret" for bittrex authorization.
3. Enable markets that you want to trade. Sample file contains "BTC-EUR" and "ETH-EUR".

Market configuration example:

```
        "BTC-EUR" : {
                        "buy" : {
                                    "trend"         : "20",
                                    "stepforward"   : "2",
                                    "stepback"      : "3",
                                    "mintrend"      : "10",
                                    "maxtrend"      : "30",
                                    "diffratelow"   : "0.15",
                                    "diffratehigh"  : "0.4",
                                    "minspread"     : "-7",
                                    "orderquantity" : "0.003",
                                    "historycheck"  : "336",
                                    "shortemadepth" : "12",
                                    "longemadepth"  : "24",
                                    "nextbuyorder"  : "0.975"
                                    "orderprice"    : "50",
                                    "nextpriceinc"  : "1.05",
                                },
                        "sell": {
                                    "trend"         : "15",
                                    "stepforward"   : "2",
                                    "stepback"      : "3",
                                    "mintrend"      : "10",
                                    "maxtrend"      : "20"
                                    "nextsellorder" : "0.05",
                                    "stoploss"      : "0.75",
                                }
                    },
```

Note: *every market have 'symbol', 'baseCurrencySymbol' and 'quoteCurrencySymbol' as showed below*
```
{
  'precision' => 3,
  'tags' => [],
  'createdAt' => '2020-03-30T06:12:04.86Z',
  'baseCurrencySymbol' => 'BTC',
  'associatedTermsOfService' => [],
  'quoteCurrencySymbol' => 'EUR',
  'prohibitedIn' => [
                      'US'
                    ],
  'status' => 'ONLINE',
  'minTradeSize' => '0.00044994',
  'symbol' => 'BTC-EUR'
};
```
### 1. buy configuration:
 - **trend** - initial trend value. It is recommended use value in a middle between **mintrend** and **maxtrend**.  
   *default value -* 15
 - **stepforward** - values that substracts from **trend** when somebody sell an order on market.  
   *default value -* 2
 - **stepback** - values that adds to **trend** when somebody buy an order on market.  
   *default value -* 3
 - **maxtrend** - Limit value for **trend** calculation. **trend** can't be greater than **maxtrend** and lesser than 0.  
   *default value -* 30
 - **mintrend** - Limit value for buy condition. Condition for trade: 0 <= **trend** <= **mintrend**.  
   *default value -* 10
 - **historycheck** defines number of hours for calculation *diffratehigh** and **diffratelow**.  
   *default value -* 48
 - **diffratehigh**/**diffratelow** - historical check in percent between highest and lowest price of orders for last **historycheck** hours.
   After find historical high/low price, it compares with diffratehigh/low values.  
   For example Bot checks last 336 hours and finds that highest price is 50000 EUR and lowest 35000 EUR;  
   First bot calculates diffrate: 50000 - 35000 = 15000;  
   **diffratehigh** is 0.4 (40%). So 15000 * 0.4 = 6000;  
   Next bot check current price - it costs 45000;  
   50000 (historical max price) - 6000 (**diffratehigh**) = 44000 < 45000 (current price);  
   So bot will avoid buy currency cause of it too expensive.  
   The calculation of the **diffratelow** works in a similar way, but it adds value to lower historical price and compares with current price. Current price should be greater.  
   *default value -* 0.3/0.15
 - **minspread** - this value compares with 24 hours change.  
   *default value -* -7
 - **shortemadepth**/**longemadepth** - parameters that uses for widely known Moving Average Strategy.  
   *default value -* 12/24
 - **orderquantity** and **orderprice** - this parameters excludes each other. **orderprice** - the prefer parameter (if defined). It's sets price in 'quoteCurrencySymbol'.  
   **orderquantity** - is secondary parameter and sets price in 'baseCurrencySymbol". So, as showed in exampe, the bot will prefer buy orders for 50 EUR. !!!Warning!!! Result should be greater than 'minTradeSize'.  
   *default value for orderquantity -* minTradeSize &#42; 2
 - **nextbuyorder** - parameter that allows you buy order for lower price than already bought. Bot can hold base with infinite count buy orders able to sell it with profit.  
   *default value -* 0.975
 - **nextpriceinc** is the multiplier of lowest order's price. The result uses for calculation next order. Example shows that next order will be increased for 5%.  
   *default value -* not defined
### 2. sell configuration:
 - **trend** - initial trend value. It is recommended use value in a middle between **mintrend** and **maxtrend**.  
   *default value -* 15
 - **stepforward** - values that adds to **trend** when somebody sell an order on market.  
   *default value -* 2
 - **stepback** - values that substracts from **trend** when somebody buy an order on market.  
   *default value -* 3
 - **maxtrend** - Limit value for **trend** calculation. **trend** can't be greater than **maxtrend** and lesser than 0.  
   *default value -* 30
 - **mintrend** - Limit value for buy condition. Condition for trade: 0 <= **trend** <= **mintrend**.  
   *default value -* 10
 - **nextsellorder** - literally profit that you excpect to get from each order.  
   *default value -* 0.03
 - **stoploss** - Decreasing market price, after that order will be sold.  
   *default value -* 0.75

# Bot launch

After installing and configuration you can start it. First launch script to make sure that everything is fine (Ctrl+C to break):

```
/usr/bin/perl bittrex-bot.pl
```

If program runs normaly, you can run it in background mode via screen. There is shell script to maintain this process:

```
/bin/bash tasked-bot-bg.sh
```

This script starts bittrex-bot.pl in background. To chek if it works:

```
# ps -axj | grep bittrex-bot.pl
15088 16955 16954 15088 pts/1    16954 S+       0   0:00 grep bittrex-bot.pl
***    1 32202 32202 32202 ?           -1 Ss       0   0:04 SCREEN -L -S btcbot -d -m ./bittrex-bot.pl***
32202 32203 32203 32203 pts/2    32203 Ss+      0 467:13 /usr/bin/perl ./bittrex-bot.pl
```

Make sure that you started only one process. Else you have to kill it and start properly.
You can also recover background process:

```
/bin/bash tasked-bot-bg-recover.sh
```

If everything is fine and you need to pull it back - press Ctrl+A and Ctrl+D.
If you wanna stop process - press Ctrl+C

# Logging

If you properly done logging configuration, your logs should be placed in /var/log/screenlog. After start program in background you can check logs:
```
cat /var/log/screenlog
```
# Order database maintenance

You can freely trade while bot working. Main point - do not touch funds that uses bot.
However if you crossed line or you decided to buy some extra orders (and apply it to bot database) you have to perform the following steps:

1. Stop the bot running;
2. Use the bittrex-orders.pl to delete/add orders from/to database:
```
./bittrex-orders.pl

Usage:

-h - prints these message
 Example:
  ./bittrex-orders.pl -h

-m <marketname> - requred parameter;
 Example:
  ./bittrex-orders.pl -m BTC-USD

-l - list of CLOSED orders;
 Example:
  ./bittrex-orders.pl -m BTC-USD -l

-a - add order to orderbook with following order-Id;
 Example:
  ./bittrex-orders.pl -m BTC-USD -a 1a84083a-8e6e-4d60-b172-8ed1a92ecf4a

-d - delete order from orderbook with following order-Id;
 Example:
  ./bittrex-orders.pl -m BTC-USD -d 1a84083a-8e6e-4d60-b172-8ed1a92ecf4a

```
All trading information stores in *.json files. So you can also remove <market>.json file for total cleanup.
3. Start bot again.

# Changelog

 **2020-11-18** - Project shared to public access.