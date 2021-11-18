package ServiceSubs;

use strict;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use Data::Dumper;

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(showcomparevalues compare_hashes get_hashed);
%EXPORT_TAGS = ( DEFAULT => [qw(&showcomparevalues &compare_hashes get_hashed)]);

sub showcomparevalues {
    my $value_1 = $_[0];
    my $value_2 = $_[1];
    my $output;
    if ($value_1 > $value_2) {
        $output = "&arrowup";
    } elsif ($value_1 < $value_2) {
        $output = "&arrowdown";
    } else {
        $output = " ";
    }
    return $output;
}

sub compare_hashes {
    my $hash1 = $_[0];
    my $hash2 = $_[1];
    my $output = 1;
    foreach my $key (keys %{ $hash1 }) {
        if ($hash1->{$key} != $hash2->{$key}) { $output = 0; }
    }
    return $output;
}

sub get_hashed {
    my $array = $_[0];
    my $field = $_[1];
    my $result;
    foreach my $value (values @{ $array }) {
        if (defined $value->{$field}) {
            $result->{$value->{$field}} = $value;
        }
    }
    return $result;
}
1;
