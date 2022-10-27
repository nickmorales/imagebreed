#!/usr/bin/env perl


=head1 NAME

 AddEarthSenseCollectionsCvterms

=head1 SYNOPSIS

mx-run AddEarthSenseCollectionsCvterms [options] -H hostname -D dbname -u username [-F]

this is a subclass of L<CXGN::Metadata::Dbpatch>
see the perldoc of parent class for more details.

=head1 DESCRIPTION
This patch adds cvterms for saving EarthSense ground rover collection data
This subclass uses L<Moose>. The parent class uses L<MooseX::Runnable>

=head1 AUTHOR


=head1 COPYRIGHT & LICENSE

Copyright 2010 Boyce Thompson Institute for Plant Research

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


package AddEarthSenseCollectionsCvterms;

use Moose;
use Bio::Chado::Schema;
use Try::Tiny;
use SGN::Model::Cvterm;

extends 'CXGN::Metadata::Dbpatch';


has '+description' => ( default => <<'' );
This patch adds cvterms for EarthSense ground rover collection data

has '+prereq' => (
	default => sub {
        [],
    },

);

sub patch {
    my $self=shift;

    print STDOUT "Executing the patch:\n " .   $self->name . ".\n\nDescription:\n  ".  $self->description . ".\n\nExecuted by:\n " .  $self->username . " .";

    print STDOUT "\nChecking if this db_patch was executed before or if previous db_patches have been executed.\n";

    print STDOUT "\nExecuting the SQL commands.\n";
    my $schema = Bio::Chado::Schema->connect( sub { $self->dbh->clone } );


    print STDERR "INSERTING CV TERMS...\n";

    my $terms = {
        'project_property' => [
            'earthsense_ground_rover_collections_archived',
        ],
        'project_md_image' => [
            'rover_event_original_points_image',
            'rover_event_points_filtered_height_image',
            'rover_event_points_filtered_side_span_image',
            'rover_event_points_filtered_side_height_image'
        ],
        'experiment_type' => [
            'field_trial_drone_runs_in_same_rover_event'
        ]
    };

	foreach my $t (keys %$terms){
		foreach (@{$terms->{$t}}){
			$schema->resultset("Cv::Cvterm")->create_with({
				name => $_,
				cv => $t
			});
		}
	}

    print "You're done!\n";
}


####
1; #
####
