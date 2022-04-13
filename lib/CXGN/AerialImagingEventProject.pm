
package CXGN::AerialImagingEventProject;

use Moose;

extends 'CXGN::Project';

use SGN::Model::Cvterm;
use CXGN::Calendar;
use Data::Dumper;

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
    $h = undef;
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
    my $drone_run_drone_run_band_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_on_drone_run', 'project_relationship')->cvterm_id();
    my $drone_run_band_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_project_type', 'project_property')->cvterm_id();
    my $drone_run_field_trial_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_on_field_trial', 'project_relationship')->cvterm_id();

    my @related_imaging_event_ids;
    my @related_imaging_event_names;
    my @related_imaging_events;
    my @related_imaging_event_bands;
    my %related_imaging_event_bands_type_hash;
    my @related_imaging_event_field_trial_ids;
    my @related_imaging_event_field_trial_names;

    my $q = "SELECT nd_experiment.nd_experiment_id
        FROM nd_experiment_project
        JOIN nd_experiment ON (nd_experiment_project.nd_experiment_id = nd_experiment.nd_experiment_id)
        WHERE nd_experiment.type_id = ? and project_id = ?;";
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute($field_trial_drone_runs_in_same_orthophoto_type_id, $self->get_trial_id);
    my @nd_experiment_ids;
    while (my ($nd_experiment_id) = $h->fetchrow_array()) {
        push @nd_experiment_ids, $nd_experiment_id;
    }
    $h = undef;
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
        my $h = $schema->storage->dbh()->prepare($q);
        $h->execute($field_trial_drone_runs_in_same_orthophoto_type_id, $nd_experiment_id, $self->get_trial_id);
        while (my ($project_id, $project_name) = $h->fetchrow_array()) {
            push @related_imaging_events, [$project_id, $project_name];
            push @related_imaging_event_ids, $project_id;
            push @related_imaging_event_names, $project_name;
        }
        $h = undef;

        my $q2 = "SELECT drone_run.project_id, drone_run.name, drone_run_band.project_id, drone_run_band.name, drone_run_band_project_type.value
            FROM nd_experiment_project
            JOIN nd_experiment ON (nd_experiment_project.nd_experiment_id = nd_experiment.nd_experiment_id)
            JOIN project AS drone_run ON (drone_run.project_id = nd_experiment_project.project_id)
            JOIN project_relationship ON (drone_run.project_id = project_relationship.object_project_id AND project_relationship.type_id = $drone_run_drone_run_band_type_id)
            JOIN project AS drone_run_band ON (drone_run_band.project_id = project_relationship.subject_project_id)
            JOIN projectprop AS drone_run_band_project_type ON (drone_run_band.project_id = drone_run_band_project_type.project_id AND drone_run_band_project_type.type_id = $drone_run_band_type_cvterm_id)
            WHERE nd_experiment.type_id = ? AND nd_experiment_project.nd_experiment_id = ? AND drone_run.project_id != ?;";
        my $h2 = $schema->storage->dbh()->prepare($q2);
        $h2->execute($field_trial_drone_runs_in_same_orthophoto_type_id, $nd_experiment_id, $self->get_trial_id);
        while (my ($drone_run_project_id, $drone_run_project_name, $drone_run_band_project_id, $drone_run_band_project_name, $drone_run_band_project_type) = $h2->fetchrow_array()) {
            push @related_imaging_event_bands, {
                drone_run_id => $drone_run_project_id,
                drone_run_name => $drone_run_project_name,
                drone_run_band_id => $drone_run_band_project_id,
                drone_run_band_name => $drone_run_band_project_name,
                drone_run_band_type => $drone_run_band_project_type
            };
            push @{$related_imaging_event_bands_type_hash{$drone_run_band_project_type}}, $drone_run_band_project_id;
        }
        $h2 = undef;

        if (scalar(@related_imaging_event_ids)>0) {
            my $related_imaging_event_ids_string = join ',', @related_imaging_event_ids;
            my $q3 = "SELECT field_trial.project_id, field_trial.name
                FROM project AS drone_run
                JOIN project_relationship ON (drone_run.project_id = project_relationship.subject_project_id AND project_relationship.type_id = $drone_run_field_trial_type_id)
                JOIN project AS field_trial ON (field_trial.project_id = project_relationship.object_project_id)
                WHERE drone_run.project_id IN ($related_imaging_event_ids_string);";
            my $h3 = $schema->storage->dbh()->prepare($q3);
            $h3->execute();
            while (my ($project_id, $project_name) = $h3->fetchrow_array()) {
                push @related_imaging_event_field_trial_ids, $project_id;
                push @related_imaging_event_field_trial_names, $project_name;
            }
            $h3 = undef;
        }
    }

    return (\@related_imaging_event_ids, \@related_imaging_event_names, \@related_imaging_event_field_trial_ids, \@related_imaging_event_field_trial_names, \@related_imaging_events, \@related_imaging_event_bands, \%related_imaging_event_bands_type_hash);
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

=head2 function get_aerial_imaging_event_report_file_metadata()

 Usage:        $trial->get_aerial_imaging_event_report_file_metadata();
 Desc:         retrieves metadata.md_file entries for this trial
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub get_aerial_imaging_event_report_file_metadata {
    my $self = shift;
    my $trial_id = $self->get_trial_id();

    my $drone_run_experiment_stitched_report_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_stitched_report', 'experiment_type')->cvterm_id();
    my $drone_run_experiment_odm_stitched_image_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_odm_stitched_image', 'experiment_type')->cvterm_id();
    my $drone_run_experiment_odm_stitched_report_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_odm_stitched_report', 'experiment_type')->cvterm_id();
    my $drone_run_experiment_odm_stitched_stats_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_odm_stitched_stats', 'experiment_type')->cvterm_id();
    my $drone_run_experiment_odm_stitched_shots_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_odm_stitched_shots', 'experiment_type')->cvterm_id();
    my $drone_run_experiment_odm_stitched_reconstruction_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_odm_stitched_reconstruction', 'experiment_type')->cvterm_id();

    my $drone_run_experiment_odm_stitched_dsm_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_odm_stitched_dsm', 'experiment_type')->cvterm_id();
    my $drone_run_experiment_odm_stitched_dtm_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_odm_stitched_dtm', 'experiment_type')->cvterm_id();
    my $drone_run_experiment_odm_stitched_dsm_dtm_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_odm_stitched_dsm_minus_dtm', 'experiment_type')->cvterm_id();

    my $drone_run_experiment_odm_stitched_point_cloud_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_odm_stitched_point_cloud', 'experiment_type')->cvterm_id();
    my $drone_run_experiment_odm_stitched_point_cloud_obj_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_odm_stitched_point_cloud_obj', 'experiment_type')->cvterm_id();
    my $drone_run_experiment_odm_stitched_point_cloud_pcd_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_odm_stitched_point_cloud_pcd', 'experiment_type')->cvterm_id();
    my $drone_run_experiment_odm_stitched_point_cloud_gltf_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_odm_stitched_point_cloud_gltf', 'experiment_type')->cvterm_id();
    my $drone_run_experiment_odm_stitched_point_cloud_csv_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'drone_run_experiment_odm_stitched_point_cloud_csv', 'experiment_type')->cvterm_id();

    my @type_ids = (
        $drone_run_experiment_stitched_report_type_id,
        $drone_run_experiment_odm_stitched_image_type_id,
        $drone_run_experiment_odm_stitched_point_cloud_type_id,
        $drone_run_experiment_odm_stitched_point_cloud_obj_type_id,
        $drone_run_experiment_odm_stitched_point_cloud_pcd_type_id,
        $drone_run_experiment_odm_stitched_point_cloud_gltf_type_id,
        $drone_run_experiment_odm_stitched_point_cloud_csv_type_id,
        $drone_run_experiment_odm_stitched_report_type_id,
        $drone_run_experiment_odm_stitched_stats_type_id,
        $drone_run_experiment_odm_stitched_shots_type_id,
        $drone_run_experiment_odm_stitched_reconstruction_type_id,
        $drone_run_experiment_odm_stitched_dsm_type_id,
        $drone_run_experiment_odm_stitched_dtm_type_id,
        $drone_run_experiment_odm_stitched_dsm_dtm_type_id
    );
    my $type_ids_string = join ',', @type_ids;

    my @file_array;
    my %file_info;
    my $q = "SELECT a.file_id, m.create_date, p.sp_person_id, p.username, a.basename, a.dirname, a.filetype
        FROM metadata.md_files AS a
        JOIN phenome.nd_experiment_md_files AS b ON(a.file_id = b.file_id)
        JOIN nd_experiment ON(b.nd_experiment_id = nd_experiment.nd_experiment_id AND nd_experiment.type_id IN ($type_ids_string))
        JOIN nd_experiment_project ON(nd_experiment_project.nd_experiment_id = nd_experiment.nd_experiment_id)
        LEFT JOIN metadata.md_metadata as m using(metadata_id)
        LEFT JOIN sgn_people.sp_person as p ON (p.sp_person_id=m.create_person_id)
        WHERE project_id=? and m.obsolete = 0
        ORDER BY file_id ASC";
    my $h = $self->bcs_schema->storage()->dbh()->prepare($q);
    $h->execute($trial_id);

    while (my ($file_id, $create_date, $person_id, $username, $basename, $dirname, $filetype) = $h->fetchrow_array()) {
        $file_info{$file_id} = [$file_id, $create_date, $person_id, $username, $basename, $dirname, $filetype];
    }
    foreach (keys %file_info){
        push @file_array, $file_info{$_};
    }
    return \@file_array;
}

1;
