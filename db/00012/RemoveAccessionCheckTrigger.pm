#!/usr/bin/env perl


=head1 NAME

 SampleDbpatchMoose.pm

=head1 SYNOPSIS

mx-run ThisPackageName [options] -H hostname -D dbname -u username [-F]
    
this is a subclass of L<CXGN::Metadata::Dbpatch>
see the perldoc of parent class for more details.
    
=head1 DESCRIPTION

This is a test dummy patch. 
This subclass uses L<Moose>. The parent class uses L<MooseX::Runnable>
    
=head1 AUTHOR

 Naama Menda<nm249@cornell.edu>

=head1 COPYRIGHT & LICENSE

Copyright 2010 Boyce Thompson Institute for Plant Research

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


package RemoveAccessionCheckTrigger;

use Moose;
extends 'CXGN::Metadata::Dbpatch';


sub init_patch {
    my $self=shift;
    my $name = __PACKAGE__;
    print "dbpatch name is ':" .  $name . "\n\n";
    my $description = 'Testing a Moose dbpatch';
    my @previous_requested_patches = (); #ADD HERE 
    
    $self->name($name);
    $self->description($description);
    $self->prereq(\@previous_requested_patches);
    
}

sub patch {
    my $self=shift;
    
   
    print STDOUT "Executing the patch:\n " .   $self->name . ".\n\nDescription:\n  ".  $self->description . ".\n\nExecuted by:\n " .  $self->username . " .";
    
    print STDOUT "\nChecking if this db_patch was executed before or if previous db_patches have been executed.\n";

    

    print STDOUT "\nExecuting the SQL commands.\n";
    
    $self->dbh->do(<<EOSQL); 
--do your SQL here
--

drop trigger pcr_accession_check_trigger on sgn.pcr_exp_accession;
    alter table sgn.pcr_exp_accession drop constraint accession_id_check;
   
EOSQL

print "You're done!\n";
    
}


####
1; #
####
