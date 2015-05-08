@rem = '--*-Perl-*--
@echo off
if "%OS%" == "Windows_NT" goto WinNT
perl -x -S "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:WinNT
perl -x -S %0 %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto endofperl
@rem ';

#!perl

use strict;
# use warnings;
use LWP::UserAgent;
use Data::Dumper;
use Getopt::Long;
use JSON;
use List::Util qw(sum first);
use Encode;
use utf8;

$Data::Dumper::Indent = 1;
# set output encode
if($^O =~ /MSWin32/){
    binmode(STDOUT, ":encoding(gbk)"); 
}
else{
    binmode(STDOUT, ":encoding(utf8)");      
}

use constant HOST    => 'http://vip.stock.finance.sina.com.cn';
use constant NODE    => '/quotes_service/api/json_v2.php/Market_Center.getHQNodeData?num=3000';
use constant MARKETS => {
        INDUSTRY     => '/q/view/newFLJK.php?param=industry',
        CLASS        => '/q/view/newFLJK.php?param=class',
        AREA         => '/q/view/newFLJK.php?param=area',
        SINAHY       => '/q/view/newSinaHy.php',
};

our ($ua, $market, $node, $sort, $asc, $all, @search, $picture, $ua, $live);

$ua = new LWP::UserAgent;
$ua->agent("LWP::Simple/Perl");
# $ua->env_proxy;

$sort = 'changepercent';
$asc  = 0;

GetOptions(
    'market=s'     => \$market,
    'node=s'       => \$node,
    'sort=s'       => \$sort,
    'reverse'      => \$asc,
    'all'          => \$all,
    'search=s{,}'  => \@search,
    'picture'      => \$picture,
    'live'         => \$live,
    );

if(@search){
    my @list = getSearhList(@search);
    do{
        printSearchList(@list);
        sleep 3 if $live;
    }
    while($live);
}
elsif($picture){
    my @nodes = $node ? ($node) : qw(hs_a sh_a sz_a zxqy cyb);
    for(@nodes){
        printf "<=== %5s ===>\n", $_;
        printStatistic(getNodeList(getHTML(HOST.NODE."&asc=$asc"."&sort=$sort"."&node=$_")));
    }
}
elsif($market){
    my $param = first {/^$market/i} keys %{ MARKETS() };
    return unless $param;

    my @list = getHangyeList(getHTML(HOST. MARKETS->{$param}));
    if($node || $all){
        my @nodes = $node ? grep {$_->{code} =~ /$node/i} @list : @list;
        for my $item (@nodes){
            print "\n";
            printHangyeListSingle($item);
            printf "%s\n", '-'x140;
            printNodeList(getNodeList(getHTML(HOST.NODE."&asc=$asc"."&sort=$sort"."&node=".$item->{code})));
        }
    }
    else{
        printHangyeList(@list);
    }
}
elsif($node){
    printNodeList(getNodeList(getHTML(HOST.NODE."&asc=$asc"."&sort=$sort"."&node=$node")));
}

# 抓取网页
sub getHTML{
    my $url = shift;
    my $response = $ua->get($url);
    if($response->is_success){
        my $html = $response->content;
        return Encode::is_utf8($html) ? $html : decode("gbk", $html);    
    }
}

# 取板块列表
sub getHangyeList{
    my $html = shift;
    $html =~ s/^.*=//;
    my $json = from_json($html);
    
    # return [map {my %tmp; @tmp{qw(code name number avgprice pricechange changepercent volume amount)}=split /,/; \%tmp } values %$json];
    my @stocklist;
    for(values %$json){
        my %hangye;
        @hangye{qw(code name number avgprice pricechange changepercent volume amount)} = split /,/;
        push @stocklist, \%hangye if $hangye{code};
    }
    return sort { $b->{changepercent} <=> $a->{changepercent} } @stocklist;
}

# 输出板块列表
sub printHangyeListSingle{
    my $item = shift;
    $item->{volume} /= 10**4;
    $item->{amount} /= 10**8;
    printf "%4d%8.2f%\t%8.0f%8.2f\t%-12s%s\n", @$item{qw(number changepercent volume amount code name)};
}

sub printHangyeList{
    # printf "%4s%8s\t%8s%8s\t%-12s%s\n",qw(num % volume amount code name);
    # printf "%s\n", '-'x70;
    printHangyeListSingle($_) for @_;
}

# 取单个板块股票
sub getNodeList{
    my $html = shift;
    $html =~ s/:/=>/g;
    @{ eval "$html" };
}

# 输出单个板块股票
sub printNodeListSingle{
    my $item = shift;
    
    # B股则跳过不输出
    # return if $item->{code} =~/^[29]/;

    $item->{volume} /= 10**4;
    $item->{amount} /= 10**8;
    $item->{mktcap} /= 10**4;
    $item->{nmc}    /= 10**4;

    printf "%-6s\t%6s",          @$item{qw(name code)};
    printf "%8.2f%8.2f%%%8.2f",  @$item{qw(trade changepercent pricechange)};
    # 判断是否停牌，停牌输出样式有变化
    if($item->{open} > 0){
        printf " [%6.2f%7.2f ]", map {$_ - $item->{settlement}} @$item{qw(high low)};
        printf "%8.2f [%6.2f ]", $item->{settlement}, $item->{open} - $item->{settlement};
    }else{
        printf " [%6s%7s ]",     '--', '--';
        printf "%8.2f [%6s ]",   $item->{settlement}, '--'; 
    }
    printf "%8.2f%8.2f%8.2f",    @$item{qw(per pb turnoverratio)};
    printf "%8.0f%8.2f",         @$item{qw(volume amount)};
    printf "%10.2f%10.2f",       @$item{qw(mktcap nmc)};
    printf "\n";
}

sub printNodeList{
    printNodeListSingle($_) for @_;
}

# 搜索股票，打印信息
sub printStatistic{
    # my $list = shift;
    my $statistic = {};
    my $summary   = ["","","","","","","","","","","","","","","","","","","","",""];
    # 排序从-10到10
    for my $stock (@_){
        my $mktcap = int($stock->{mktcap}/500000 + 1)*50;
        $mktcap = int($mktcap/1000 + 1)*1000 if $mktcap > 1000;
        $mktcap = '+5000' if $mktcap > 5000;
        my $change = int($stock->{changepercent} + 10.05);
        unless($statistic->{$mktcap}){
            $statistic->{$mktcap} = ["","","","","","","","","","",".","","","","","","","","","",""];
        }
        $statistic->{$mktcap}[$change]++;
        $summary->[$change]++;
    }
    
    sub printRow{
        printf "%5s"x22 ." | %5s\n", @_;   
    }

    sub printRowPercent{
        printf "%5s" ."%5.1f"x21 ." | %5s\n", @_;   
    }

    printRow('', reverse (-10..10));
    printRow(('-----')x23);
    for(sort {$b <=> $a} keys %{$statistic}){
        printRow($_, (reverse @{ $statistic->{$_} }), sum @{ $statistic->{$_} });
    }
    printRow(('-----')x23);
    printRow("total", (reverse @{ $summary }), sum @{ $summary });
    printRow(('-----')x23);
    my $total = sum @{ $summary };
    printRowPercent("%", map { $_/$total*100 } reverse @{ $summary });
    print "\n";
}

# 搜索股票，打印信息
sub getSearhList{
    my @list;
    for(@_){
        my $html = getHTML('http://suggest3.sinajs.cn/suggest/type=11&key='.$_);
        my @tmp = $html =~ /s[hz]\d{6}/g;
        push @list, @tmp;
    }
    return @list;
}

sub printSearchList{
    my $code = join ',', @_;
    my $html = getHTML('http://hq.sinajs.cn/list='.$code);

    for my $stock (split /\n/,$html){
        next unless $stock =~ /"(.+)"/;

        my @tmp = split /,/, $1;
        my ($code) = $stock =~ /(\d+)=/;
        printf "%-6s\t",             $tmp[0]; 
        if($tmp[1] == 0){
            printf "%8s\n", '--.--';
            printf "( %s )%s\n\n",   $code, '-'x80;
            next;
        }        
        printf "%8.2f%8.2f%%%8.2f",  $tmp[3], ($tmp[3]-$tmp[2])/$tmp[2]*100, $tmp[3]-$tmp[2];
        printf " [%6.2f%7.2f ]",     $tmp[4]-$tmp[2], $tmp[5]-$tmp[2];
        printf "%8.2f [%6.2f ]",     $tmp[2], $tmp[1]-$tmp[2];
        printf "%8.0f%8.2f",         $tmp[8]/10**4, $tmp[9]/10**8;
        printf "\n";

        map {$_ /= 100} @tmp[qw(10 12 14 16 18 20 22 24 26 28)];
        printf "( %s )%s\n", $code, '-'x80;
        printf "sell  [%6.2f%7.0f ] [%6.2f%7.0f ] [%6.2f%7.0f ] [%6.2f%7.0f ] [%6.2f%7.0f ]\n", @tmp[qw(21 20 23 22 25 24 27 26 29 28)];
        printf "buy   [%6.2f%7.0f ] [%6.2f%7.0f ] [%6.2f%7.0f ] [%6.2f%7.0f ] [%6.2f%7.0f ]\n", @tmp[qw(11 10 13 12 15 14 17 16 19 18)];
        printf "\n";
    }
}

# {f:'symbol', t:'代码', d:-2, s:49},
# {f:'name', t:'名称', d:-2, s:51},
# {f:'trade', t:'最新价', d:2, s:64, c:'colorize'},
# {f:'pricechange', t:'涨跌额', d:2, s:4, c:'colorize'},
# {f:'changepercent', t:'涨跌幅', d:3, s:4, c:'colorize', p:'$1%'},
# {f:'buy', t:'买入', d:2, c:'colorize'},
# {f:'sell', t:'卖出', d:2, c:'colorize'},
# {f:'settlement', t:'昨收', d:2, c:'colorize'},
# {f:'open', t:'今开', d:2, c:'colorize'},
# {f:'high', t:'最高', d:2, c:'colorize'},
# {f:'low', t:'最低', d:2, c:'colorize'},
# {f:'volume', t:'成交量/手', d:0, s:8},
# {f:'amount', t:'成交额/万', d:2, s:8},
# {f:'per', t:'市盈利率', d:3},
# {f:'pb', t:'市净率', d:3},
# {f:'mktcap', t:'市值', d:2, s:8},
# {f:'nmc', t:'流通市值', d:2, s:8},
# {f:'turnoverratio', t:'换手率', d:2, p:'$1%'},

# 所有node列表
# http://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodes

__END__
:endofperl
