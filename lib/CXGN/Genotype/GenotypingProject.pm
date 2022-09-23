
=head1 NAME

CXGN::Genotype::GenotypingProject - an object representing a genotyping project in the database

=head1 DESCRIPTION

    my $genotyping_project = CXGN::Genotype::GenotypingProject->new( { schema => $schema, trial_id => 37347 });


=head1 AUTHORS

    Titima Tantikanjana

=head1 METHODS

=cut
package CXGN::Genotype::GenotypingProject;

use Moose;
use SGN::Model::Cvterm;
use Data::Dumper;
use JSON;
use CXGN::Trial::Search;
use Try::Tiny;
use CXGN::Trial;

has 'bcs_schema' => (
    isa => 'Bio::Chado::Schema',
    is => 'rw',
    required => 1,
);

has 'project_id' => (
    isa => 'Int',
    is => 'rw',
    required => 1,
);

has 'project_facility' => (isa => 'Str',
    is => 'rw',
    required => 0,
);

has 'project_and_plate_relationship_cvterm_id' => (
    isa => 'Int',
    is => 'rw',
);

has 'genotyping_plate_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'new_genotyping_plate_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'subscription_model' => (
    isa => 'Bool',
    is => 'rw',
    required => 1
);

sub BUILD {

    my $self = shift;
    my $schema = $self->bcs_schema();
    my $genotyping_project_id = $self->project_id();

    my $genotyping_project = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $genotyping_project_id });
    my $project_facility = $genotyping_project->get_genotyping_facility();

    my $genotyping_project_relationship_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'genotyping_project_and_plate_relationship', 'project_relationship');
    my $project_and_plate_relationship_cvterm_id = $genotyping_project_relationship_cvterm->cvterm_id();
    my $relationships_rs = $schema->resultset("Project::ProjectRelationship")->search ({
        object_project_id => $genotyping_project_id,
        type_id => $project_and_plate_relationship_cvterm_id
    });

    my @plate_list;
    if ($relationships_rs) {
        while (my $each_relationship = $relationships_rs->next()) {
    	    push @plate_list, $each_relationship->subject_project_id();
        }
    }
    $self->project_facility($project_facility);
    $self->project_and_plate_relationship_cvterm_id($project_and_plate_relationship_cvterm_id);
    $self->genotyping_plate_list(\@plate_list);

}


sub get_genotyping_plate_ids {
    my $self = shift;
    my $plate_list = $self->genotyping_plate_list();
    return $plate_list;
}


sub validate_relationship {
    my $self = shift;
    my $schema = $self->bcs_schema();
    my $new_plate_ids = $self->new_genotyping_plate_list();
    my $genotyping_project_id = $self->project_id();
    my $project_facility = $self->project_facility();
    my @plate_ids = @$new_plate_ids;
    my @genotyping_plate_errors;

    foreach my $plate_id (@plate_ids) {
        my $genotyping_plate = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $plate_id });
        my $plate_facility = $genotyping_plate->get_genotyping_facility();

        if (($plate_facility ne 'None') && ($project_facility ne 'None')) {
            if ($plate_facility ne $project_facility) {
                my $genotyping_plate_name = $genotyping_plate->get_name();
                push @genotyping_plate_errors, $genotyping_plate_name;
            }
        }
    }

    return {error_messages => \@genotyping_plate_errors}
}


sub set_project_for_genotyping_plate {
    my $self = shift;
    my $schema = $self->bcs_schema();
    my $genotyping_project_id = $self->project_id();
    my $new_genotyping_plate_list = $self->new_genotyping_plate_list();
    my @new_genotyping_plates = @$new_genotyping_plate_list;
    my $transaction_error;

    my $coderef = sub {

        foreach my $plate_id (@new_genotyping_plates) {
            my $relationship_rs = $schema->resultset("Project::ProjectRelationship")->find ({
                subject_project_id => $plate_id,
                type_id => $self->project_and_plate_relationship_cvterm_id()
            });

            if($relationship_rs){
                print STDERR "UPDATING...."."\n";
                $relationship_rs->object_project_id($genotyping_project_id);
                $relationship_rs->update();
            } else {
                $relationship_rs = $schema->resultset('Project::ProjectRelationship')->create({
        		    object_project_id => $genotyping_project_id,
        		    subject_project_id => $plate_id,
        		    type_id => $self->project_and_plate_relationship_cvterm_id()
                });
                $relationship_rs->insert();
            }
        }
    };

    try {
        $schema->txn_do($coderef);
    } catch {
        $transaction_error =  $_;
    };

    if ($transaction_error) {
        print STDERR "Transaction error associating genotyping plate: $transaction_error\n";
        return;
    }

    return 1;

}


sub get_plate_info {
    my $self = shift;
    my $schema = $self->bcs_schema();
    my $plate_list = $self->genotyping_plate_list();
    my $number_of_plate = scalar (@$plate_list);
    my $data;
    my $total_count;
    if ($number_of_plate > 0) {
        my $trial_search = CXGN::Trial::Search->new({
            bcs_schema => $schema,
            trial_design_list => ['genotyping_plate'],
            trial_id_list => $plate_list,
            subscription_model => $self->subscription_model()
        });
        ($data, $total_count) = $trial_search->search();
    }

    return $data;

}


1;
