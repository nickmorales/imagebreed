#!/usr/bin/perl

=head1 NAME

ensure_only_one_variable_of_cvterm.pl - ensures only one VARIABLE_OF term exists in the database

=head1 DESCRIPTION

ensure_only_one_variable_of_cvterm.pl -H [database host] -D [database name] -U [database username] -P [database password]

Options:

 -H the database host
 -D the database name
 -U the database username
 -P the database password

This script ensures only one VARIABLE_OF term exists in the database

=head1 AUTHOR

=cut

use strict;
use warnings;
use Getopt::Std;
use DBI;

our ($opt_H, $opt_D, $opt_U, $opt_P);
getopts('H:D:U:P:');

print STDERR "Connecting to database...\n";
my $dsn = 'dbi:Pg:database='.$opt_D.";host=".$opt_H.";port=5432";
my $dbh = DBI->connect($dsn, $opt_U, $opt_P);

eval {
    my $q0 = "SELECT cvterm_id FROM cvterm WHERE name='VARIABLE_OF' ORDER BY cvterm_id ASC;";
    my $q1 = "UPDATE cvterm_relationship SET type_id=? WHERE type_id=?;";
    my $q2 = "DELETE FROM cvterm where cvterm_id=?;";

    my $h0 = $dbh->prepare($q0);
    my $h1 = $dbh->prepare($q1);
    my $h2 = $dbh->prepare($q2);

    $h0->execute();
    my ($good_cvterm_id) = $h0->fetchrow_array();
    while (my ($bad_cvterm_id) = $h0->fetchrow_array()) {
        $h1->execute($good_cvterm_id, $bad_cvterm_id);
        $h2->execute($bad_cvterm_id);
    }
};

if ($@) {
  $dbh->rollback();
  print STDERR $@;
} else {
  print STDERR "Done exiting ensure_only_one_variable_of_cvterm.pl \n";
}
