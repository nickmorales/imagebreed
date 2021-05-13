#!/usr/bin/perl

=head1 NAME

refresh_matviews.pl - run PL/pgSQL functions to do a basic or concurrent refresh of all database materialized views

=head1 DESCRIPTION

refresh_matviews.pl -H [database handle] -D [database name]  -c [to run concurrent refresh] -m [materialized view select]

Options:

 -H the database host
 -D the database name
 -c flag; if present, run concurrent refresh
 -m materialized view select. can be either 'fullview' or 'stockprop'

All materialized views that are included in the refresh function will be refreshed
If -c is used, the refresh will be done concurrently, a process that takes longer than a standard refresh but that is completed without locking the views.

=head1 AUTHOR

Bryan Ellerbrock <bje24@cornell.edu>

=cut

use strict;
use warnings;
use Getopt::Std;
use DBI;
#use CXGN::DB::InsertDBH;

our ($opt_H, $opt_D, $opt_U, $opt_P, $opt_m, $opt_c, $refresh, $status);
getopts('H:D:U:P:m:c');

print STDERR "Connecting to database...\n";
my $dsn = 'dbi:Pg:database='.$opt_D.";host=".$opt_H.";port=5432";
my $dbh = DBI->connect($dsn, $opt_U, $opt_P);

eval {
    print STDERR "Refreshing materialized views . . ." . localtime() . "\n";

    my $start_q = "UPDATE matviews SET refresh_start = now() where mv_name = ?";
    my $end_q = "UPDATE matviews SET last_refresh = now() where mv_name = ?";
    my $start_h = $dbh->prepare($start_q);
    my $end_h = $dbh->prepare($end_q);
    my $start_q_all = "UPDATE matviews SET refresh_start = now()";
    my $end_q_all = "UPDATE matviews SET last_refresh = now()";
    my $start_h_all = $dbh->prepare($start_q_all);
    my $end_h_all = $dbh->prepare($end_q_all);

    if ($opt_m eq 'fullview'){
        $start_h_all->execute();

        my $q = "UPDATE public.matviews SET currently_refreshing=?";
        my $state = 'TRUE';
        my $h = $dbh->prepare($q);
        $h->execute($state);

        if ($opt_c) {
            $refresh = 'SELECT refresh_materialized_views_concurrently()';
        } else {
            $refresh = 'SELECT refresh_materialized_views()';
        }

        $h = $dbh->prepare($refresh);
        $status = $h->execute();

        if ($opt_c) {
          $refresh = 'SELECT refresh_materialized_stockprop_concurrently()';
        } else {
          $refresh = 'SELECT refresh_materialized_stockprop()';
        }

        $h = $dbh->prepare($refresh);
        $status = $h->execute();

        if ($opt_c) {
          $refresh = 'SELECT refresh_materialized_phenotype_jsonb_table_concurrently()';
        } else {
          $refresh = 'SELECT refresh_materialized_phenotype_jsonb_table()';
        }

        $h = $dbh->prepare($refresh);
        $status = $h->execute();

        $q = "UPDATE public.matviews SET currently_refreshing=?";
        $state = 'FALSE';
        $h = $dbh->prepare($q);
        $h->execute($state);

        $end_h_all->execute();
    }

    if ($opt_m eq 'stockprop'){
        $start_h->execute('materialized_stockprop');

        if ($opt_c) {
          $refresh = 'SELECT refresh_materialized_stockprop_concurrently()';
        } else {
          $refresh = 'SELECT refresh_materialized_stockprop()';
        }

        my $h = $dbh->prepare($refresh);
        $status = $h->execute();

        $end_h->execute('materialized_stockprop');
    }

    print STDERR "Materialized views refreshed! Status: $status" . localtime() . "\n";
};

if ($@) {
  $dbh->rollback();
  print STDERR $@;
} else {
  print STDERR "Done, exiting refresh_matviews.pl \n";
}
