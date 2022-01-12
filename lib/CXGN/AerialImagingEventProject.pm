
package CXGN::AerialImagingEventProject;

use Moose;

extends 'CXGN::Project';

use SGN::Model::Cvterm;
use CXGN::Calendar;

=head2 function get_associated_image_band_projects()

 Usage:
 Desc:         returns the associated image band projects for this imaging event project
 Ret:          returns an arrayref [ id, name ] of arrayrefs
 Args:
 Side Effects:
 Example:

=cut

sub get_associated_image_band_projects {
    my $self = shift;
    my $drone_run_on_drone_run_band_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_band_on_drone_run', 'project_relationship')->cvterm_id();
    my $q = "SELECT drone_run_band.project_id, drone_run_band.name
        FROM project AS drone_run
        JOIN project_relationship on (drone_run.project_id = project_relationship.object_project_id AND project_relationship.type_id = $drone_run_on_drone_run_band_type_id)
        JOIN project AS drone_run_band ON (drone_run_band.project_id = project_relationship.subject_project_id)
        WHERE drone_run.project_id = ?;";
    my $h = $self->bcs_schema->storage->dbh()->prepare($q);
    $h->execute($self->get_trial_id);
    my @image_band_projects;
    while (my ($drone_run_band_project_id, $drone_run_band_name) = $h->fetchrow_array()) {
        push @image_band_projects, [$drone_run_band_project_id, $drone_run_band_name];
    }
    return \@image_band_projects;
}

=head2 function get_field_trial_drone_run_projects_in_same_orthophoto()

 Usage:
 Desc:         returns the other imaging event projects that are in the same orthophoto
 Ret:          returns an arrayref [ id, name ] of arrayrefs
 Args:
 Side Effects:
 Example:

=cut

sub get_field_trial_drone_run_projects_in_same_orthophoto {
    my $self = shift;
    my $schema = $self->bcs_schema;

    my $field_trial_drone_runs_in_same_orthophoto_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'field_trial_drone_runs_in_same_orthophoto', 'experiment_type')->cvterm_id();

    my @related_imaging_events;

    my $q = "SELECT nd_experiment.nd_experiment_id
        FROM nd_experiment_project
        JOIN nd_experiment ON (nd_experiment_project.nd_experiment_id = nd_experiment.nd_experiment_id)
        WHERE nd_experiment.type_id = ? and project_id = ?;";
    my $h = $self->bcs_schema->storage->dbh()->prepare($q);
    $h->execute($field_trial_drone_runs_in_same_orthophoto_type_id, $self->get_trial_id);
    my @nd_experiment_ids;
    while (my ($nd_experiment_id) = $h->fetchrow_array()) {
        push @nd_experiment_ids, $nd_experiment_id;
    }
    if (scalar(@nd_experiment_ids)>1) {
        die "It should not be possible to save an imaging event into more than one orthophoto!\n";
    }
    elsif (scalar(@nd_experiment_ids)==1) {
        my $nd_experiment_id = $nd_experiment_ids[0];
        my $q = "SELECT project.project_id, project.name
            FROM nd_experiment_project
            JOIN nd_experiment ON (nd_experiment_project.nd_experiment_id = nd_experiment.nd_experiment_id)
            JOIN project ON (project.project_id = nd_experiment_project.project_id)
            WHERE nd_experiment.type_id = ? AND nd_experiment_project.nd_experiment_id = ? AND project.project_id != ?;";
        my $h = $self->bcs_schema->storage->dbh()->prepare($q);
        $h->execute($field_trial_drone_runs_in_same_orthophoto_type_id, $nd_experiment_id, $self->get_trial_id);
        while (my ($project_id, $project_name) = $h->fetchrow_array()) {
            push @related_imaging_events, [$project_id, $project_name];
        }
    }

    return \@related_imaging_events;
}


=head2 accessors get_drone_run_date(), set_drone_run_date()

 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub get_drone_run_date {
    my $self = shift;

    my $date_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'project_start_date', 'project_property')->cvterm_id();
    my $row = $self->bcs_schema->resultset('Project::Projectprop')->find({
        project_id => $self->get_trial_id(),
        type_id => $date_cvterm_id,
    });

    my $calendar_funcs = CXGN::Calendar->new({});

    if ($row) {
        my $date = $calendar_funcs->display_start_date($row->value());
        return $date;
    } else {
        return;
    }
}

sub set_drone_run_date {
    my $self = shift;
    my $date = shift;

    my $calendar_funcs = CXGN::Calendar->new({});

    if (my $event = $calendar_funcs->check_value_format($date) ) {

        my $date_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'project_start_date', 'project_property')->cvterm_id();

        my $row = $self->bcs_schema->resultset('Project::Projectprop')->find_or_create({
            project_id => $self->get_trial_id(),
            type_id => $date_cvterm_id,
        });

        $row->value($event);
        $row->update();
    } else {
        print STDERR "date format did not pass check: $date \n";
    }
}

1;
