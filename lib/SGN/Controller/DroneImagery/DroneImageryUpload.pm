
=head1 NAME

=head1 DESCRIPTION

=head1 AUTHOR

=cut

package SGN::Controller::DroneImagery::DroneImageryUpload;

use Moose;
use Data::Dumper;
use JSON;
use SGN::Model::Cvterm;
use DateTime;
use Math::Round;
use Time::Piece;
use Time::Seconds;
use SGN::Image;
use CXGN::DroneImagery::ImagesSearch;
use File::Basename qw | basename dirname|;
use URI::Encode qw(uri_encode uri_decode);
use CXGN::Calendar;
use Image::Size;
use CXGN::DroneImagery::ImageTypes;
use LWP::UserAgent;
use CXGN::ZipFile;
use Text::CSV;
use SGN::Controller::AJAX::DroneImagery::DroneImagery;
use CXGN::Trial::TrialLayout;

BEGIN { extends 'Catalyst::Controller'; }

sub upload_drone_imagery : Path("/drone_imagery/upload_drone_imagery") :Args(0) {
    my $self = shift;
    my $c = shift;
    $c->response->headers->header( "Access-Control-Allow-Origin" => '*' );
    $c->response->headers->header( "Access-Control-Allow-Methods" => "POST, GET, PUT, DELETE" );
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    print STDERR Dumper $c->req->params();

    my $private_company_id = $c->req->param('private_company_id');
    my ($user_id, $user_name, $user_role) = _check_user_login_drone_imagery_upload($c, 'submitter', $private_company_id, 'submitter_access');

    if (!$private_company_id) {
        $c->stash->{message} = "Please select a company first!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    my $private_companies = CXGN::PrivateCompany->new( { schema=> $schema } );
    my ($private_companies_array, $private_companies_ids, $allowed_private_company_ids_hash, $allowed_private_company_access_hash, $private_company_access_is_private_hash) = $private_companies->get_users_private_companies($user_id, 0);
    my $company_is_private = $private_company_access_is_private_hash->{$private_company_id} ? 1 : 0;

    my $selected_trial_ids = $c->req->param('drone_run_field_trial_id');
    if (!$selected_trial_ids) {
        $c->stash->{message} = "Please select atleast one field trial first!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    my @selected_trial_ids = split ',', $selected_trial_ids;

    my $new_drone_run_names_string = $c->req->param('drone_run_name');
    my @new_drone_run_names = split ',', $new_drone_run_names_string;
    my $new_drone_run_names_string_safe = join '_', @new_drone_run_names;

    my $selected_drone_run_id = $c->req->param('drone_run_id');
    my $new_drone_run_type = $c->req->param('drone_run_type');
    my $new_drone_run_date = $c->req->param('drone_run_date');
    my $new_drone_base_date = $c->req->param('drone_run_base_date');
    my $new_drone_run_desc = $c->req->param('drone_run_description');
    my $new_drone_rig_desc = $c->req->param('drone_run_camera_rig_description');
    my $new_drone_run_vehicle_id = $c->req->param('drone_run_imaging_vehicle_id');
    my $new_drone_run_battery_name = $c->req->param('drone_run_imaging_vehicle_battery_name');

    my $dir = $c->tempfiles_subdir('/upload_drone_imagery_bulk_previous');

    if (!$new_drone_run_vehicle_id) {
        $c->stash->{message} = "Please give an imaging event vehicle id!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    if (!$selected_drone_run_id && !$new_drone_run_names_string) {
        $c->stash->{message} = "Please select an imaging event or create a new imaging event!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    if ($new_drone_run_names_string && !$new_drone_run_type){
        $c->stash->{message} = "Please give a new imaging event type!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    if ($new_drone_run_names_string && !$new_drone_run_date){
        $c->stash->{message} = "Please give a new imaging event date!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    if ($new_drone_run_names_string && $new_drone_run_date !~ /^\d{4}\/\d{2}\/\d{2}\s\d\d:\d\d:\d\d$/){
        $c->stash->{message} = "Please give a new imaging event date in the format YYYY/MM/DD HH:mm:ss!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    if ($new_drone_run_names_string && $new_drone_base_date && $new_drone_base_date !~ /^\d{4}\/\d{2}\/\d{2}\s\d\d:\d\d:\d\d$/){
        $c->stash->{message} = "Please give a new imaging event base date in the format YYYY/MM/DD HH:mm:ss!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    if ($new_drone_run_names_string && !$new_drone_run_desc){
        $c->stash->{message} = "Please give a new imaging event description!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    my $new_drone_run_camera_info = $c->req->param('drone_image_upload_camera_info');
    my $new_drone_run_band_numbers = $c->req->param('drone_run_band_number');
    my $new_drone_run_band_stitching = $c->req->param('drone_image_upload_drone_run_band_stitching');
    my $new_drone_run_band_stitching_odm_radiocalibration = $c->req->param('drone_image_upload_drone_run_band_stitching_odm_radiocalibration') eq "Yes" ? 1 : 0;

    if (!$new_drone_run_camera_info) {
        $c->stash->{message} = "Please indicate the type of camera!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    if ($new_drone_run_band_stitching eq 'no' && !$new_drone_run_band_numbers) {
        $c->stash->{message} = "Please give the number of new imaging event bands!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    if (!$new_drone_run_band_stitching) {
        $c->stash->{message} = "Please indicate if the images are stitched!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    my $odm_process_running_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_opendronemap_process_running', 'project_property')->cvterm_id();
    if ($new_drone_run_band_stitching eq 'yes_open_data_map_stitch') {
        my $upload_file = $c->req->upload('upload_drone_images_zipfile');
        my $upload_panel_file = $c->req->upload('upload_drone_images_panel_zipfile');
        if (!$upload_file) {
            $c->stash->{message} = "Please provide a zipfile of raw images!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        if (!$upload_panel_file && $new_drone_run_camera_info eq 'micasense_5') {
            $c->stash->{message} = "Please provide a zipfile of images of the Micasense radiometric calibration panels!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }

        my $q = "SELECT count(*) FROM projectprop WHERE type_id=$odm_process_running_cvterm_id AND value='1';";
        my $h = $schema->storage->dbh()->prepare($q);
        $h->execute();
        my ($odm_running_count) = $h->fetchrow_array();
        if ($odm_running_count >= $c->config->{opendronemap_max_processes}) {
            $c->stash->{message} = "There are already the maximum number of OpenDroneMap processes running on this machine! Please check back later when those processes are complete.";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
    }

    # if ($selected_drone_run_id && ($new_drone_run_band_stitching eq 'yes' || $new_drone_run_band_stitching eq 'yes_raw' || $new_drone_run_band_stitching eq 'yes_automated')) {
    #     $c->stash->{rest} = { error => "Please create a new drone run if you are uploading a zipfile of raw images!" };
    #     $c->detach();
    # }

    my $log_file_path = '';
    if ($c->config->{error_log}){
        $log_file_path = "--log_file_path '".$c->config->{error_log}."'";
    }

    my $q_priv = "UPDATE project SET private_company_id=?, is_private=? WHERE project_id=?;";
    my $h_priv = $schema->storage->dbh()->prepare($q_priv);

    my @selected_drone_run_infos;
    my @selected_drone_run_ids;
    if (!$selected_drone_run_id) {
        my $drone_run_field_trial_project_relationship_type_id_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_on_field_trial', 'project_relationship')->cvterm_id();
        my $drone_run_band_drone_run_project_relationship_type_id_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_on_drone_run', 'project_relationship')->cvterm_id();
        my $project_start_date_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'project_start_date', 'project_property')->cvterm_id();

        my $calendar_funcs = CXGN::Calendar->new({});

        my %seen_field_trial_drone_run_dates;
        my $drone_run_date_q = "SELECT drone_run_date.value
            FROM project AS drone_run_band_project
            JOIN project_relationship AS drone_run_band_rel ON (drone_run_band_rel.subject_project_id = drone_run_band_project.project_id AND drone_run_band_rel.type_id = $drone_run_band_drone_run_project_relationship_type_id_cvterm_id)
            JOIN project AS drone_run_project ON (drone_run_band_rel.object_project_id = drone_run_project.project_id)
            JOIN projectprop AS drone_run_date ON(drone_run_project.project_id=drone_run_date.project_id AND drone_run_date.type_id=$project_start_date_type_id)
            JOIN project_relationship AS field_trial_rel ON (drone_run_project.project_id = field_trial_rel.subject_project_id AND field_trial_rel.type_id=$drone_run_field_trial_project_relationship_type_id_cvterm_id)
            JOIN project AS field_trial ON (field_trial_rel.object_project_id = field_trial.project_id)
            WHERE field_trial.project_id IN ($selected_trial_ids);";
        my $drone_run_date_h = $schema->storage->dbh()->prepare($drone_run_date_q);
        $drone_run_date_h->execute();
        while( my ($drone_run_date) = $drone_run_date_h->fetchrow_array()) {
            my $drone_run_date_formatted = $drone_run_date ? $calendar_funcs->display_start_date($drone_run_date) : '';
            if ($drone_run_date_formatted) {
                my $date_obj = Time::Piece->strptime($drone_run_date_formatted, "%Y-%B-%d %H:%M:%S");
                my $epoch_seconds = $date_obj->epoch;
                $seen_field_trial_drone_run_dates{$epoch_seconds}++;
            }
        }
        my $drone_run_date_obj = Time::Piece->strptime($new_drone_run_date, "%Y/%m/%d %H:%M:%S");
        if (exists($seen_field_trial_drone_run_dates{$drone_run_date_obj->epoch})) {
            $c->stash->{rest} = { error => "An imaging event has already occured on these field trial(s) at the same date and time! Please give a unique date/time for each imaging event on a field trial!" };
            $c->detach();
        }

        my $drone_run_experiment_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_experiment', 'experiment_type')->cvterm_id();
        my $design_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'design', 'project_property')->cvterm_id();
        my $drone_run_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_project_type', 'project_property')->cvterm_id();
        my $drone_run_is_raw_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_is_raw_images', 'project_property')->cvterm_id();
        my $drone_run_camera_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_camera_type', 'project_property')->cvterm_id();
        my $drone_run_base_date_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_base_date', 'project_property')->cvterm_id();
        my $drone_run_rig_desc_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_camera_rig_description', 'project_property')->cvterm_id();
        my $drone_run_related_cvterms_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_related_time_cvterms_json', 'project_property')->cvterm_id();
        my $project_relationship_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_on_field_trial', 'project_relationship')->cvterm_id();
        my $field_trial_drone_runs_in_same_orthophoto_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'field_trial_drone_runs_in_same_orthophoto', 'experiment_type')->cvterm_id();
        my $imaging_vehicle_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'imaging_event_vehicle', 'stock_type')->cvterm_id();
        my $imaging_vehicle_properties_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'imaging_event_vehicle_json', 'stock_property')->cvterm_id();

        my $iterator = 0;
        my $field_trial_drone_runs_in_same_orthophoto_nd_experiment_id;
        foreach my $selected_trial_id (@selected_trial_ids) {
            my $new_drone_run_name = $new_drone_run_names[$iterator];

            my $trial = CXGN::Trial->new({ bcs_schema => $schema, trial_id => $selected_trial_id });
            my $trial_location_id = $trial->get_location()->[0];
            my $planting_date = $trial->get_planting_date();
            my $planting_date_time_object = Time::Piece->strptime($planting_date, "%Y-%B-%d");
            my $drone_run_date_time_object = Time::Piece->strptime($new_drone_run_date, "%Y/%m/%d %H:%M:%S");
            my $time_diff;
            my $base_date_event;
            if ($new_drone_base_date) {
                my $imaging_event_base_date_time_object = Time::Piece->strptime($new_drone_base_date, "%Y/%m/%d %H:%M:%S");
                $time_diff = $drone_run_date_time_object - $imaging_event_base_date_time_object;
                $base_date_event = $calendar_funcs->check_value_format($new_drone_base_date);
            }
            else {
                $time_diff = $drone_run_date_time_object - $planting_date_time_object;
            }
            my $time_diff_weeks = $time_diff->weeks;
            my $time_diff_days = $time_diff->days;
            my $time_diff_hours = $time_diff->hours;
            my $rounded_time_diff_weeks = round($time_diff_weeks);
            if ($rounded_time_diff_weeks == 0) {
                $rounded_time_diff_weeks = 1;
            }

            my $week_term_string = "week $rounded_time_diff_weeks";
            my $q = "SELECT t.cvterm_id FROM cvterm as t JOIN cv ON(t.cv_id=cv.cv_id) WHERE t.name=? and cv.name=?;";
            my $h = $schema->storage->dbh()->prepare($q);
            $h->execute($week_term_string, 'cxgn_time_ontology');
            my ($week_cvterm_id) = $h->fetchrow_array();

            if (!$week_cvterm_id) {
                my $new_week_term = $schema->resultset("Cv::Cvterm")->create_with({
                   name => $week_term_string,
                   cv => 'cxgn_time_ontology'
                });
                $week_cvterm_id = $new_week_term->cvterm_id();
            }

            my $day_term_string = "day $time_diff_days";
            $h->execute($day_term_string, 'cxgn_time_ontology');
            my ($day_cvterm_id) = $h->fetchrow_array();

            if (!$day_cvterm_id) {
                my $new_day_term = $schema->resultset("Cv::Cvterm")->create_with({
                   name => $day_term_string,
                   cv => 'cxgn_time_ontology'
                });
                $day_cvterm_id = $new_day_term->cvterm_id();
            }

            my $week_term = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $week_cvterm_id, 'extended');
            my $day_term = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $day_cvterm_id, 'extended');

            my %related_cvterms = (
                week => $week_term,
                day => $day_term
            );

            my $drone_run_event = $calendar_funcs->check_value_format($new_drone_run_date);

            my $drone_run_projectprops = [
                {type_id => $drone_run_type_cvterm_id, value => $new_drone_run_type},
                {type_id => $project_start_date_type_id, value => $drone_run_event},
                {type_id => $design_cvterm_id, value => 'drone_run'},
                {type_id => $drone_run_camera_type_cvterm_id, value => $new_drone_run_camera_info},
                {type_id => $drone_run_related_cvterms_cvterm_id, value => encode_json \%related_cvterms}
            ];

            if ($new_drone_run_band_stitching ne 'no') {
                push @$drone_run_projectprops, {type_id => $drone_run_is_raw_cvterm_id, value => 1};
            }
            if ($new_drone_base_date) {
                push @$drone_run_projectprops, {type_id => $drone_run_base_date_type_id, value => $base_date_event};
            }
            if ($new_drone_rig_desc) {
                push @$drone_run_projectprops, {type_id => $drone_run_rig_desc_type_id, value => $new_drone_rig_desc};
            }

            my $nd_experiment_rs = $schema->resultset("NaturalDiversity::NdExperiment")->create({
                nd_geolocation_id => $trial_location_id,
                type_id => $drone_run_experiment_type_id,
                nd_experiment_stocks => [{stock_id => $new_drone_run_vehicle_id, type_id => $drone_run_experiment_type_id}]
            });
            my $drone_run_nd_experiment_id = $nd_experiment_rs->nd_experiment_id();

            my @drone_run_nd_experiment_projects = ({nd_experiment_id => $drone_run_nd_experiment_id});

            if (scalar(@selected_trial_ids)>1) {
                if ($iterator == 0) {
                    my $nd_experiment_rs = $schema->resultset("NaturalDiversity::NdExperiment")->create({
                        nd_geolocation_id => $trial_location_id,
                        type_id => $field_trial_drone_runs_in_same_orthophoto_type_id,
                    });
                    $field_trial_drone_runs_in_same_orthophoto_nd_experiment_id = $nd_experiment_rs->nd_experiment_id();
                }
                push @drone_run_nd_experiment_projects, {nd_experiment_id => $field_trial_drone_runs_in_same_orthophoto_nd_experiment_id};
            }

            my $project_rs = $schema->resultset("Project::Project")->create({
                name => $new_drone_run_name,
                description => $new_drone_run_desc,
                projectprops => $drone_run_projectprops,
                project_relationship_subject_projects => [{type_id => $project_relationship_type_id, object_project_id => $selected_trial_id}],
                nd_experiment_projects => \@drone_run_nd_experiment_projects
            });
            $selected_drone_run_id = $project_rs->project_id();

            $h_priv->execute($private_company_id, $company_is_private, $selected_drone_run_id);

            push @selected_drone_run_infos, {
                drone_run_name => $new_drone_run_name,
                drone_run_id => $selected_drone_run_id,
                field_trial_id => $selected_trial_id,
                trial_location_id => $trial_location_id
            };
            push @selected_drone_run_ids, $selected_drone_run_id;

            $iterator++;
        }

        my $vehicle_prop = decode_json $schema->resultset("Stock::Stockprop")->search({stock_id => $new_drone_run_vehicle_id, type_id=>$imaging_vehicle_properties_cvterm_id})->first()->value();
        $vehicle_prop->{batteries}->{$new_drone_run_battery_name}->{usage}++;
        my $vehicle_prop_update = $schema->resultset('Stock::Stockprop')->update_or_create({
            type_id=>$imaging_vehicle_properties_cvterm_id,
            stock_id=>$new_drone_run_vehicle_id,
            rank=>0,
            value=>encode_json $vehicle_prop
        },
        {
            key=>'stockprop_c1'
        });
    }
    else {
        my $iterator = 0;
        foreach my $selected_trial_id (@selected_trial_ids) {
            my $new_drone_run_name = $new_drone_run_names[$iterator];

            my $trial = CXGN::Trial->new({ bcs_schema => $schema, trial_id => $selected_trial_id });
            my $trial_location_id = $trial->get_location()->[0];

            push @selected_drone_run_infos, {
                drone_run_name => $new_drone_run_name,
                drone_run_id => $selected_drone_run_id,
                field_trial_id => $selected_trial_id,
                trial_location_id => $trial_location_id
            };
            push @selected_drone_run_ids, $selected_drone_run_id;

            $iterator++;
        }
    }
    print STDERR Dumper \@selected_drone_run_infos;
    my $selected_drone_run_ids_string = join '_', @selected_drone_run_ids;

    my @nd_experiment_project_ids;
    foreach (@selected_drone_run_ids) {
        push @nd_experiment_project_ids, {project_id => $_};
    }

    my $drone_run_band_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_project_type', 'project_property')->cvterm_id();
    my $design_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'design', 'project_property')->cvterm_id();
    my $project_relationship_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_on_drone_run', 'project_relationship')->cvterm_id();
    my $geoparam_coordinates_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_geoparam_coordinates_type', 'project_property')->cvterm_id();
    my $geoparam_coordinates_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_geoparam_coordinates', 'project_property')->cvterm_id();
    my $original_image_resize_ratio_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_original_image_resize_ratio', 'project_property')->cvterm_id();
    my $rotated_image_resize_ratio_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_rotated_image_resize_ratio', 'project_property')->cvterm_id();

    my @return_drone_run_band_project_ids;
    my @return_drone_run_band_image_ids;
    my @return_drone_run_band_image_urls;
    my @raw_image_boundaries_temp_images;
    my %saved_image_stacks;
    my $output_path;
    my $alignment_output_path;
    my $cmd;

    my $computation_location_id = $schema->resultset("NaturalDiversity::NdGeolocation")->search({description=>'[Computation]'})->first->nd_geolocation_id();

    my $image_types_allowed = CXGN::DroneImagery::ImageTypes::get_all_drone_run_band_image_types()->{hash_ref};
    my %seen_image_types_upload;

    if ($new_drone_run_band_stitching eq 'no') {
        my @new_drone_run_bands;
        if ($new_drone_run_band_numbers eq 'one_bw' || $new_drone_run_band_numbers eq 'one_rgb') {
            my $new_drone_run_band_desc = $c->req->param('drone_run_band_description_1');
            my $new_drone_run_band_type = $c->req->param('drone_run_band_type_1');
            my $new_drone_run_band_coordinate_system = $c->req->param('drone_run_band_coordinate_system_1') || 'Pixels';
            if (!$new_drone_run_band_desc){
                $c->stash->{message} = "Please give a new imaging event band description!";
                $c->stash->{template} = 'generic_message.mas';
                return;
            }
            if (!$new_drone_run_band_type){
                $c->stash->{message} = "Please give a new imaging event band type!";
                $c->stash->{template} = 'generic_message.mas';
                return;
            }
            if (!exists($image_types_allowed->{$new_drone_run_band_type})) {
                $c->stash->{message} = "Imaging event band type not supported: $new_drone_run_band_type!";
                $c->stash->{template} = 'generic_message.mas';
                return;
            }
            if (exists($seen_image_types_upload{$new_drone_run_band_type})) {
                $c->stash->{message} = "Imaging event band type is repeated: $new_drone_run_band_type! Each imaging event band in an imaging event should have a unique type!";
                $c->stash->{template} = 'generic_message.mas';
                return;
            }
            $seen_image_types_upload{$new_drone_run_band_type}++;

            my $upload_file = $c->req->upload('drone_run_band_stitched_ortho_image_1');
            if (!$upload_file) {
                $c->stash->{message} = "Please provide a zipfile OR a stitched ortho image!";
                $c->stash->{template} = 'generic_message.mas';
                return;
            }

            push @new_drone_run_bands, {
                description => $new_drone_run_band_desc,
                type => $new_drone_run_band_type,
                upload_file => $upload_file,
                coordinate_system => $new_drone_run_band_coordinate_system
            };
        } else {
            foreach (1..$new_drone_run_band_numbers) {
                my $new_drone_run_band_desc = $c->req->param('drone_run_band_description_'.$_);
                my $new_drone_run_band_type = $c->req->param('drone_run_band_type_'.$_);
                my $new_drone_run_band_coordinate_system = $c->req->param('drone_run_band_coordinate_system_'.$_) || 'Pixels';
                if (!$new_drone_run_band_desc){
                    $c->stash->{message} = "Please give a new imaging event band description!";
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }
                if (!$new_drone_run_band_type){
                    $c->stash->{message} = "Please give a new imaging event band type!";
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }
                if (!exists($image_types_allowed->{$new_drone_run_band_type})) {
                    $c->stash->{message} = "Imaging event band type not supported: $new_drone_run_band_type!";
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }
                if (exists($seen_image_types_upload{$new_drone_run_band_type})) {
                    $c->stash->{message} = "Imaging event band type is repeated: $new_drone_run_band_type! Each imaging event band in an imaging event should have a unique type!";
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }
                $seen_image_types_upload{$new_drone_run_band_type}++;

                my $upload_file = $c->req->upload('drone_run_band_stitched_ortho_image_'.$_);
                if (!$upload_file) {
                    $c->stash->{message} = "Please provide a zipfile OR a stitched ortho image!";
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }

                push @new_drone_run_bands, {
                    description => $new_drone_run_band_desc,
                    type => $new_drone_run_band_type,
                    upload_file => $upload_file,
                    coordinate_system => $new_drone_run_band_coordinate_system
                };
            }
        }
        foreach (@new_drone_run_bands) {
            my $coordinate_system = $_->{coordinate_system};
            my $drone_run_band_description = $_->{description};
            my $drone_run_band_type = $_->{type};
            my $upload_file = $_->{upload_file};
            my $new_drone_run_input_image = $upload_file->tempname;

            my @drone_run_band_projectprops = (
                {type_id => $drone_run_band_type_cvterm_id, value => $drone_run_band_type},
                {type_id => $design_cvterm_id, value => 'drone_run_band'},
            );

            my $time = DateTime->now();
            my $timestamp = $time->ymd()."_".$time->hms();
            my $upload_original_name = $selected_drone_run_ids_string."_".$drone_run_band_type.".png";

            my $ortho_file;
            my $geoparams_projection;
            my @geoparams_coordinates;
            if ($coordinate_system eq 'Pixels') {
                $ortho_file = $new_drone_run_input_image;
                $geoparams_projection = $coordinate_system;
            }
            else {
                my @geoparams_coordinates;

                my $outfile_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_bulk_previous/imageXXXX').".png";
                my $outfile_geoparams = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_bulk_previous/fileXXXX').".csv";
                my $outfile_geoparams_projection = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_bulk_previous/fileXXXX').".csv";

                if ($drone_run_band_type eq 'RGB Color Image') {
                    my $outfile_image_r = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_bulk_previous/imageXXXX').".png";
                    my $outfile_image_g = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_bulk_previous/imageXXXX').".png";
                    my $outfile_image_b = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_bulk_previous/imageXXXX').".png";

                    my $geo_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/GDALOpenImageRGBGeoTiff.py --image_path $new_drone_run_input_image --outfile_path_image $outfile_image --outfile_path_image_1 $outfile_image_r --outfile_path_image_2 $outfile_image_g --outfile_path_image_3 $outfile_image_b --outfile_path_geo_params $outfile_geoparams --outfile_path_geo_projection $outfile_geoparams_projection";
                    print STDERR $geo_cmd."\n";
                    my $geo_cmd_status = system($geo_cmd);
                    $ortho_file = $outfile_image;

                    open(my $fh_geoparams, '<', $outfile_geoparams) or die "Could not open file '".$outfile_geoparams."' $!";
                        print STDERR "Opened ".$outfile_geoparams."\n";
                        my $geoparams = <$fh_geoparams>;
                        chomp $geoparams;
                        @geoparams_coordinates = split ',', $geoparams;
                        print STDERR Dumper [$geoparams, \@geoparams_coordinates];
                    close($fh_geoparams);

                    open(my $fh_geoparam_proj, '<', $outfile_geoparams_projection) or die "Could not open file '".$outfile_geoparams_projection."' $!";
                        print STDERR "Opened ".$outfile_geoparams_projection."\n";
                        my $geoparams_proj = <$fh_geoparam_proj>;
                        chomp $geoparams_proj;
                        $geoparams_proj =~ s/,//g;
                        my @geoparams_proj_arr = split "\"\"\"\"", $geoparams_proj;
                        $geoparams_projection = $geoparams_proj_arr[3];
                        $geoparams_projection =~ s/\s//g;
                        print STDERR Dumper [$geoparams_proj, $geoparams_projection];
                    close($fh_geoparam_proj);
                }
                else {
                    my $geo_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/GDALOpenSingleChannelImageGeoTiff.py --image_path $new_drone_run_input_image --outfile_path_image $outfile_image --outfile_path_geo_params $outfile_geoparams --outfile_path_geo_projection $outfile_geoparams_projection";
                    print STDERR $geo_cmd."\n";
                    my $geo_cmd_status = system($geo_cmd);
                    $ortho_file = $outfile_image;

                    open(my $fh_geoparams, '<', $outfile_geoparams) or die "Could not open file '".$outfile_geoparams."' $!";
                        print STDERR "Opened ".$outfile_geoparams."\n";
                        my $geoparams = <$fh_geoparams>;
                        chomp $geoparams;
                        @geoparams_coordinates = split ',', $geoparams;
                        print STDERR Dumper [$geoparams, \@geoparams_coordinates];
                    close($fh_geoparams);

                    open(my $fh_geoparam_proj, '<', $outfile_geoparams_projection) or die "Could not open file '".$outfile_geoparams_projection."' $!";
                        print STDERR "Opened ".$outfile_geoparams_projection."\n";
                        my $geoparams_proj = <$fh_geoparam_proj>;
                        chomp $geoparams_proj;
                        $geoparams_proj =~ s/,//g;
                        my @geoparams_proj_arr = split "\"\"\"\"", $geoparams_proj;
                        $geoparams_projection = $geoparams_proj_arr[3];
                        $geoparams_projection =~ s/\s//g;
                        print STDERR Dumper [$geoparams_proj, $geoparams_projection];
                    close($fh_geoparam_proj);
                }

                push @drone_run_band_projectprops, {type_id => $geoparam_coordinates_cvterm_id, value => encode_json \@geoparams_coordinates};
            }

            push @drone_run_band_projectprops, {type_id => $geoparam_coordinates_type_cvterm_id, value => $geoparams_projection};

            my $uploader = CXGN::UploadFile->new({
                tempfile => $ortho_file,
                subdirectory => "drone_imagery_upload",
                archive_path => $c->config->{archive_path},
                archive_filename => $upload_original_name,
                timestamp => $timestamp,
                user_id => $user_id,
                user_role => $user_role
            });
            my $archived_filename_with_path = $uploader->archive();
            my $md5 = $uploader->get_md5($archived_filename_with_path);
            if (!$archived_filename_with_path) {
                $c->stash->{message} = "Could not save file $upload_original_name in archive.";
                $c->stash->{template} = 'generic_message.mas';
                return;
            }
            unlink $new_drone_run_input_image;
            print STDERR "Archived Drone Image File: $archived_filename_with_path\n";

            my @original_image_resize_ratio = (1,1);
            if ($c->config->{drone_imagery_allow_resize}) {
                my ($check_image_width, $check_image_height) = imgsize($archived_filename_with_path);
                my $check_image_width_original = $check_image_width;
                my $check_image_height_original = $check_image_height;
                if ($check_image_width > 16384) {
                    my $cmd_resize = $c->config->{python_executable}.' '.$c->config->{rootpath}.'/DroneImageScripts/ImageProcess/Resize.py --image_path \''.$archived_filename_with_path.'\' --outfile_path \''.$archived_filename_with_path.'\' --width 16384';
                    print STDERR Dumper $cmd_resize;
                    my $status_resize = system($cmd_resize);
                    my ($check_image_width_resized, $check_image_height_resized) = imgsize($archived_filename_with_path);
                    $check_image_width = $check_image_width_resized;
                    $check_image_height = $check_image_height_resized;
                }
                if ($check_image_height > 16384) {
                    my $cmd_resize = $c->config->{python_executable}.' '.$c->config->{rootpath}.'/DroneImageScripts/ImageProcess/Resize.py --image_path \''.$archived_filename_with_path.'\' --outfile_path \''.$archived_filename_with_path.'\' --height 16384';
                    print STDERR Dumper $cmd_resize;
                    my $status_resize = system($cmd_resize);
                }
                my ($check_image_width_saved, $check_image_height_saved) = imgsize($archived_filename_with_path);
                @original_image_resize_ratio = ($check_image_width_original/$check_image_width_saved, $check_image_height_original/$check_image_height_saved);
            }

            push @drone_run_band_projectprops, {type_id => $original_image_resize_ratio_cvterm_id, value => encode_json \@original_image_resize_ratio};

            my $image = SGN::Image->new( $schema->storage->dbh, undef, $c );
            $image->set_sp_person_id($user_id);
            my $linking_table_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'stitched_drone_imagery', 'project_md_image')->cvterm_id();

            my $iterator = 0;
            foreach my $selected_drone_run_obj (@selected_drone_run_infos) {
                my $drone_run_name = $selected_drone_run_obj->{drone_run_name};
                my $drone_run_id = $selected_drone_run_obj->{drone_run_id};
                my $field_trial_id = $selected_drone_run_obj->{field_trial_id};
                my $trial_location_id = $selected_drone_run_obj->{trial_location_id};

                my $drone_run_band_name = $drone_run_name."_".$drone_run_band_type;

                my $project_rs = $schema->resultset("Project::Project")->create({
                    name => $drone_run_band_name,
                    description => $drone_run_band_description,
                    projectprops => \@drone_run_band_projectprops,
                    project_relationship_subject_projects => [{type_id => $project_relationship_type_id, object_project_id => $drone_run_id}]
                });
                my $selected_drone_run_band_id = $project_rs->project_id();

                $h_priv->execute($private_company_id, $company_is_private, $selected_drone_run_band_id);

                if ($iterator == 0) {
                    my $ret = $image->process_image($archived_filename_with_path, 'project', $selected_drone_run_band_id, $linking_table_type_id);
                }
                else {
                    my $ret = $image->associate_project($selected_drone_run_band_id, $linking_table_type_id);
                }

                push @return_drone_run_band_image_urls, $image->get_image_url('original');
                push @return_drone_run_band_image_ids, $image->get_image_id();
                push @return_drone_run_band_project_ids, $selected_drone_run_band_id;

                $iterator++;
            }
        }

        my $report_file = $c->req->upload('drone_run_band_stitched_ortho_report');
        if ($report_file) {
            my $upload_original_name = $report_file->filename();
            my $upload_tempfile = $report_file->tempname;
            my $time = DateTime->now();
            my $timestamp = $time->ymd()."_".$time->hms();

            my $uploader = CXGN::UploadFile->new({
                tempfile => $upload_tempfile,
                subdirectory => "drone_imagery_upload",
                archive_path => $c->config->{archive_path},
                archive_filename => $upload_original_name,
                timestamp => $timestamp,
                user_id => $user_id,
                user_role => $user_role
            });
            my $archived_filename_with_path = $uploader->archive();
            my $md5 = $uploader->get_md5($archived_filename_with_path);
            if (!$archived_filename_with_path) {
                $c->stash->{message} = "Could not save Report file $upload_original_name in archive.";
                $c->stash->{template} = 'generic_message.mas';
                return;
            }
            unlink $upload_tempfile;
            print STDERR "Archived User Provided Ortho Report: $archived_filename_with_path\n";

            my $nd_experiment_type_name = 'drone_run_experiment_stitched_report';
            my $nd_experiment_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, $nd_experiment_type_name, 'experiment_type')->cvterm_id();
            my $experiment = $schema->resultset('NaturalDiversity::NdExperiment')->create({
                nd_geolocation_id => $computation_location_id,
                type_id => $nd_experiment_type_id,
                nd_experiment_projects => \@nd_experiment_project_ids,
            });
            my $nd_experiment_id = $experiment->nd_experiment_id();

            my $md_row = $metadata_schema->resultset("MdMetadata")->create({create_person_id => $user_id});
            my $upload_file = CXGN::UploadFile->new();
            my $md5_save = $upload_file->get_md5($archived_filename_with_path);
            my $md5checksum = $md5_save->hexdigest();
            my $file_row = $metadata_schema->resultset("MdFiles")->create({
                basename => basename($archived_filename_with_path),
                dirname => dirname($archived_filename_with_path),
                filetype => $nd_experiment_type_name,
                md5checksum => $md5checksum,
                metadata_id => $md_row->metadata_id(),
            });
            my $file_id = $file_row->file_id();

            my $experiment_files = $phenome_schema->resultset("NdExperimentMdFiles")->create({
                nd_experiment_id => $nd_experiment_id,
                file_id => $file_id,
            });
        }

        if (scalar(@return_drone_run_band_project_ids) > 0 && scalar(@return_drone_run_band_project_ids) == scalar(@new_drone_run_bands)*scalar(@new_drone_run_names)) {
            $c->stash->{message} = "Successfully uploaded! Go to <a href='/breeders/drone_imagery'>Drone Imagery</a>";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        else {
            $c->stash->{message} = "An error occurred! Could not save your images!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
    }
    elsif ($new_drone_run_band_stitching eq 'yes_open_data_map_stitch') {
        my $upload_file = $c->req->upload('upload_drone_images_zipfile');
        my $upload_panel_file = $c->req->upload('upload_drone_images_panel_zipfile');

        my $upload_original_name = $upload_file->filename();
        my $upload_tempfile = $upload_file->tempname;
        my $time = DateTime->now();
        my $timestamp = $time->ymd()."_".$time->hms();
        print STDERR Dumper [$upload_original_name, $upload_tempfile];

        my $uploader = CXGN::UploadFile->new({
            tempfile => $upload_tempfile,
            subdirectory => "drone_imagery_upload_odm_zips",
            second_subdirectory => "$selected_drone_run_id",
            archive_path => $c->config->{archive_path},
            archive_filename => $upload_original_name,
            timestamp => $timestamp,
            user_id => $user_id,
            user_role => $user_role
        });
        my $archived_filename_with_path = $uploader->archive();
        my $md5 = $uploader->get_md5($archived_filename_with_path);
        if (!$archived_filename_with_path) {
            $c->stash->{message} = "Could not save file $upload_original_name in archive.";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        print STDERR "Archived Drone Image ODM Zip File: $archived_filename_with_path\n";

        my $uploader_original_zip = CXGN::UploadFile->new({
            tempfile => $upload_tempfile,
            subdirectory => "trial_additional_file_upload",
            archive_path => $c->config->{archive_path},
            archive_filename => $upload_original_name,
            timestamp => $timestamp,
            user_id => $user_id,
            user_role => $user_role
        });
        my $archived_filename_original_zip_with_path = $uploader_original_zip->archive();
        my $original_zip_md5 = $uploader_original_zip->get_md5($archived_filename_original_zip_with_path);
        if (!$archived_filename_original_zip_with_path) {
            $c->stash->{message} = "Could not save file $upload_original_name in archive.";
            $c->stash->{template} = 'generic_message.mas';
        }
        my $md5checksum_original_zip = $original_zip_md5->hexdigest();

        unlink $upload_tempfile;

        my $image = SGN::Image->new( $c->dbc->dbh, undef, $c );
        my $zipfile_return = $image->upload_drone_imagery_zipfile($archived_filename_with_path, $user_id, $selected_drone_run_id);
        # print STDERR Dumper $zipfile_return;
        if ($zipfile_return->{error}) {
            $c->stash->{message} = "Problem saving images!".$zipfile_return->{error};
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        my $image_paths = $zipfile_return->{image_files};

        my $example_archived_filename_with_path_odm_img;
        foreach my $i (@$image_paths) {
            my $uploader_odm_dir = CXGN::UploadFile->new({
                tempfile => $i,
                subdirectory => "drone_imagery_upload_odm_dir",
                second_subdirectory => "$selected_drone_run_id",
                third_subdirectory => 'images',
                archive_path => $c->config->{archive_path},
                archive_filename => basename($i),
                timestamp => $timestamp,
                user_id => $user_id,
                user_role => $user_role,
                include_timestamp => 0
            });
            my $archived_filename_with_path_odm_img = $uploader_odm_dir->archive();
            my $md5 = $uploader_odm_dir->get_md5($archived_filename_with_path_odm_img);
            if (!$archived_filename_with_path_odm_img) {
                $c->stash->{message} = "Could not save file $i in archive.";
                $c->stash->{template} = 'generic_message.mas';
                return;
            }
            print STDERR "Archived Drone Image ODM IMG File: $archived_filename_with_path_odm_img\n";
            $example_archived_filename_with_path_odm_img = $archived_filename_with_path_odm_img;
        }

        my $current_odm_image_count = scalar(@$image_paths);
        if ($current_odm_image_count < 25) {
            $c->stash->{message} = "Upload more than $current_odm_image_count images! Atleast 25 are required for OpenDroneMap to stitch.";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }

        print STDERR $example_archived_filename_with_path_odm_img."\n";
        my @img_path_split = split '\/', $example_archived_filename_with_path_odm_img;
        my $image_path_img_name = pop(@img_path_split);
        my $image_path_project_name = pop(@img_path_split);
        my $image_path_remaining = join '/', @img_path_split;
        # my $image_path_remaining_host = $image_path_remaining =~ s/cxgn\/sgn\/static\/documents\/tempfiles/tmp\/breedbase\-site/gr;
        my $hostpath = $c->config->{hostpath_archive};
        my $image_path_remaining_host = $image_path_remaining =~ s/\/home\/production/$hostpath/gr;
        print STDERR Dumper [$image_path_img_name, $image_path_project_name, $image_path_remaining, $image_path_remaining_host];

        my $dir = $c->tempfiles_subdir('/upload_drone_imagery_raw_images');
        my $dir_geocoords = $c->tempfiles_subdir('/upload_drone_imagery_geocoordinate_param');

        my $temp_file_docker_log = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_raw_images/fileXXXX');

        my $odm_check_prop = $schema->resultset("Project::Projectprop")->find_or_create({
            project_id => $selected_drone_run_id,
            type_id => $odm_process_running_cvterm_id
        });
        $odm_check_prop->value('1');
        $odm_check_prop->update();

        my @stitched_bands;
        my @stitched_result_files;
        eval {
            if ($new_drone_run_camera_info eq 'micasense_5') {
                my $upload_panel_original_name = $upload_panel_file->filename();
                my $upload_panel_tempfile = $upload_panel_file->tempname;

                my $uploader_panel = CXGN::UploadFile->new({
                    tempfile => $upload_panel_tempfile,
                    subdirectory => "drone_imagery_upload_odm_panel_zips",
                    second_subdirectory => "$selected_drone_run_id",
                    archive_path => $c->config->{archive_path},
                    archive_filename => $upload_panel_original_name,
                    timestamp => $timestamp,
                    user_id => $user_id,
                    user_role => $user_role
                });
                my $archived_filename_panel_with_path = $uploader_panel->archive();
                my $md5_panel = $uploader_panel->get_md5($archived_filename_panel_with_path);
                if (!$archived_filename_panel_with_path) {
                    $c->stash->{message} = "Could not save file $archived_filename_panel_with_path in archive.";
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }
                unlink $upload_panel_tempfile;
                print STDERR "Archived Drone Image ODM Zip File: $archived_filename_panel_with_path\n";

                # my $dtm_string = '';
                # my $ua       = LWP::UserAgent->new();
                # my $response = $ua->post( $c->config->{main_production_site_url}."/RunODMDocker.php", { 'file_path' => $image_path_remaining_host, 'dtm_string' => $dtm_string } );
                # my $content  = $response->decoded_content();
                # print STDERR Dumper $content;

                my $odm_radiometric_calibration = $new_drone_run_band_stitching_odm_radiocalibration ? '--radiometric-calibration camera' : '';
                my $odm_radiometric_calibration_open = $new_drone_run_band_stitching_odm_radiocalibration ? '--odm_radiocalibrated True' : '';

                my $odm_command = 'docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v '.$image_path_remaining_host.':/datasets/code opendronemap/odm --project-path /datasets --orthophoto-resolution 1 --dsm --dtm '.$odm_radiometric_calibration.' > '.$temp_file_docker_log;
                print STDERR $odm_command."\n";
                my $odm_status = system($odm_command);

                my $odm_b1 = "$image_path_remaining/odm_orthophoto/b1.png";
                my $odm_b2 = "$image_path_remaining/odm_orthophoto/b2.png";
                my $odm_b3 = "$image_path_remaining/odm_orthophoto/b3.png";
                my $odm_b4 = "$image_path_remaining/odm_orthophoto/b4.png";
                my $odm_b5 = "$image_path_remaining/odm_orthophoto/b5.png";

                my $odm_final_orthophoto = "$image_path_remaining/odm_orthophoto/odm_orthophoto.tif";
                my $odm_final_point_cloud = "$image_path_remaining/odm_filterpoints/point_cloud.ply";
                my $odm_final_report = "$image_path_remaining/odm_report/report.pdf";
                my $odm_final_report_stats = "$image_path_remaining/odm_report/stats.json";
                my $odm_final_report_shots = "$image_path_remaining/odm_report/shots.geojson";
                my $odm_final_sfm_reconstruction = "$image_path_remaining/opensfm/reconstruction.json";

                my $odm_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/ODMOpenImage.py --image_path $odm_final_orthophoto --outfile_path_b1 $odm_b1 --outfile_path_b2 $odm_b2 --outfile_path_b3 $odm_b3 --outfile_path_b4 $odm_b4 --outfile_path_b5 $odm_b5 $odm_radiometric_calibration_open";
                print STDERR $odm_cmd."\n";
                my $odm_open_status = system($odm_cmd);

                my $odm_dsm_png = "$image_path_remaining/odm_dem/dsm.png";
                my $odm_dtm_png = "$image_path_remaining/odm_dem/dtm.png";
                my $odm_subtract_png = "$image_path_remaining/odm_dem/subtract.png";
                my $odm_dem_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/ODMOpenImageDSM.py --image_path_dsm $image_path_remaining/odm_dem/dsm.tif --image_path_dtm $image_path_remaining/odm_dem/dtm.tif --outfile_path_dsm $odm_dsm_png --outfile_path_dtm $odm_dtm_png --outfile_path_subtract $odm_subtract_png --band_number 1";
                print STDERR $odm_dem_cmd."\n";
                my $odm_dem_open_status = system($odm_dem_cmd);

                my @odm_b1_image_size = imgsize($odm_b1);
                my $odm_b1_image_width = $odm_b1_image_size[0];
                my $odm_b1_image_length = $odm_b1_image_size[1];

                my @odm_b2_image_size = imgsize($odm_b2);
                my $odm_b2_image_width = $odm_b2_image_size[0];
                my $odm_b2_image_length = $odm_b2_image_size[1];

                my @odm_b3_image_size = imgsize($odm_b3);
                my $odm_b3_image_width = $odm_b3_image_size[0];
                my $odm_b3_image_length = $odm_b3_image_size[1];

                my @odm_b4_image_size = imgsize($odm_b4);
                my $odm_b4_image_width = $odm_b4_image_size[0];
                my $odm_b4_image_length = $odm_b4_image_size[1];

                my @odm_b5_image_size = imgsize($odm_b5);
                my $odm_b5_image_width = $odm_b5_image_size[0];
                my $odm_b5_image_length = $odm_b5_image_size[1];

                my @odm_dsm_image_size = imgsize($odm_dsm_png);
                my $odm_dsm_image_width = $odm_dsm_image_size[0];
                my $odm_dsm_image_length = $odm_dsm_image_size[1];

                if ($odm_b1_image_width != $odm_b2_image_width || $odm_b2_image_width != $odm_b3_image_width || $odm_b3_image_width != $odm_b4_image_width || $odm_b4_image_width != $odm_b5_image_width) {
                    my $error_message = "The ODM stitched 5-channel orthophotos are not all the same width! Something went wrong, please try again. It is possible ODM could not stitch your MicaSense image captures.";
                    print STDERR Dumper $error_message;
                    $c->stash->{message} = $error_message;
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }
                if ($odm_b1_image_length != $odm_b2_image_length || $odm_b2_image_length != $odm_b3_image_length || $odm_b3_image_length != $odm_b4_image_length || $odm_b4_image_length != $odm_b5_image_length) {
                    my $error_message = "The ODM stitched 5-channel orthophotos are not all the same length! Something went wrong, please try again. It is possible ODM could not stitch your MicaSense image captures.";
                    print STDERR Dumper $error_message;
                    $c->stash->{message} = $error_message;
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }
                # if ($odm_dsm_image_width != $odm_b1_image_width) {
                #     $c->stash->{message} = "The ODM stitched 5-channel orthophotos are not the same width as the DSM! Something went wrong, please try again. It is possible ODM could not stitch your MicaSense image captures.";
                #     $c->stash->{template} = 'generic_message.mas';
                #     return;
                # }
                # if ($odm_dsm_image_length != $odm_b1_image_length) {
                #     $c->stash->{message} = "The ODM stitched 5-channel orthophotos are not the same length as the DSM! Something went wrong, please try again. It is possible ODM could not stitch your MicaSense image captures.";
                #     $c->stash->{template} = 'generic_message.mas';
                #     return;
                # }

                my $odm_point_cloud_obj = "$image_path_remaining/odm_filterpoints/point_cloud.obj";
                my $odm_point_cloud_gltf = "$image_path_remaining/odm_filterpoints/point_cloud.gltf";
                my $odm_point_cloud_pcd = "$image_path_remaining/odm_filterpoints/point_cloud.pcd";
                my $odm_point_cloud_csv = "$image_path_remaining/odm_filterpoints/point_cloud.csv";
                my $odm_ply_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/Open3DConvertPLY.py --input_ply_path $odm_final_point_cloud --output_obj_path $odm_point_cloud_obj --output_pcd_path $odm_point_cloud_pcd --output_gltf_path $odm_point_cloud_gltf --output_vertices_path $odm_point_cloud_csv ";
                print STDERR $odm_ply_cmd."\n";
                my $odm_ply_status = system($odm_ply_cmd);

                push @stitched_result_files, ['drone_run_experiment_odm_stitched_image', $odm_final_orthophoto];

                push @stitched_result_files, ['drone_run_experiment_odm_stitched_dsm', $odm_dsm_png];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_dtm', $odm_dtm_png];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_dsm_minus_dtm', $odm_subtract_png];

                push @stitched_result_files, ['drone_run_experiment_odm_stitched_point_cloud', $odm_final_point_cloud];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_point_cloud_obj', $odm_point_cloud_obj];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_point_cloud_pcd', $odm_point_cloud_pcd];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_point_cloud_gltf', $odm_point_cloud_gltf];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_point_cloud_csv', $odm_point_cloud_csv];

                push @stitched_result_files, ['drone_run_experiment_odm_stitched_reconstruction', $odm_final_sfm_reconstruction];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_shots', $odm_final_report_shots];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_stats', $odm_final_report_stats];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_report', $odm_final_report];

                my @geoparams_coordinates;
                my $outfile_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/imageXXXX').".png";
                my $outfile_geoparams = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/fileXXXX').".csv";
                my $outfile_geoparams_projection = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/fileXXXX').".csv";

                my $geo_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/GDALOpenSingleChannelImageGeoTiff.py --image_path $odm_final_orthophoto --outfile_path_image $outfile_image --outfile_path_geo_params $outfile_geoparams --outfile_path_geo_projection $outfile_geoparams_projection";
                print STDERR $geo_cmd."\n";
                my $geo_cmd_status = system($geo_cmd);
                my $ortho_file = $outfile_image;

                open(my $fh_geoparams, '<', $outfile_geoparams) or die "Could not open file '".$outfile_geoparams."' $!";
                    print STDERR "Opened ".$outfile_geoparams."\n";
                    my $geoparams = <$fh_geoparams>;
                    chomp $geoparams;
                    @geoparams_coordinates = split ',', $geoparams;
                    print STDERR Dumper [$geoparams, \@geoparams_coordinates];
                close($fh_geoparams);

                my $geoparams_projection;
                open(my $fh_geoparam_proj, '<', $outfile_geoparams_projection) or die "Could not open file '".$outfile_geoparams_projection."' $!";
                    print STDERR "Opened ".$outfile_geoparams_projection."\n";
                    my $geoparams_proj = <$fh_geoparam_proj>;
                    chomp $geoparams_proj;
                    $geoparams_proj =~ s/,//g;
                    my @geoparams_proj_arr = split "\"\"\"\"", $geoparams_proj;
                    $geoparams_projection = $geoparams_proj_arr[3];
                    $geoparams_projection =~ s/\s//g;
                    print STDERR Dumper [$geoparams_proj, $geoparams_projection];
                close($fh_geoparam_proj);

                @stitched_bands = (
                    ["Band 1", "OpenDroneMap Blue", "Blue (450-520nm)", $odm_b1, \@geoparams_coordinates, $geoparams_projection],
                    ["Band 2", "OpenDroneMap Green", "Green (515-600nm)", $odm_b2, \@geoparams_coordinates, $geoparams_projection],
                    ["Band 3", "OpenDroneMap Red", "Red (600-690nm)", $odm_b3, \@geoparams_coordinates, $geoparams_projection],
                    ["Band 4", "OpenDroneMap NIR", "NIR (780-3000nm)", $odm_b4, \@geoparams_coordinates, $geoparams_projection],
                    ["Band 5", "OpenDroneMap RedEdge", "Red Edge (690-750nm)", $odm_b5, \@geoparams_coordinates, $geoparams_projection],
                    ["Band 6", "OpenDroneMap DSM", "Black and White Image", $odm_dsm_png, \@geoparams_coordinates, $geoparams_projection]
                );
            }
            elsif ($new_drone_run_camera_info eq 'ccd_color' || $new_drone_run_camera_info eq 'cmos_color') {
                my $odm_command = 'docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v '.$image_path_remaining_host.':/datasets/code opendronemap/odm --project-path /datasets --orthophoto-resolution 1 --dsm --dtm > '.$temp_file_docker_log;
                print STDERR $odm_command."\n";
                my $odm_status = system($odm_command);

                my $odm_rgb_orthophoto = "$image_path_remaining/odm_orthophoto/odm_orthophoto.tif";
                my $odm_final_point_cloud = "$image_path_remaining/odm_filterpoints/point_cloud.ply";
                my $odm_final_report = "$image_path_remaining/odm_report/report.pdf";
                my $odm_final_report_stats = "$image_path_remaining/odm_report/stats.json";
                my $odm_final_report_shots = "$image_path_remaining/odm_report/shots.geojson";
                my $odm_final_sfm_reconstruction = "$image_path_remaining/opensfm/reconstruction.json";

                my @odm_rgb_image_size = imgsize($odm_rgb_orthophoto);
                my $odm_rgb_image_width = $odm_rgb_image_size[0];
                my $odm_rgb_image_length = $odm_rgb_image_size[1];

                my $odm_dsm_png = "$image_path_remaining/odm_dem/dsm.png";
                my $odm_dtm_png = "$image_path_remaining/odm_dem/dtm.png";
                my $odm_subtract_png = "$image_path_remaining/odm_dem/subtract.png";
                my $odm_dem_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/ODMOpenImageDSM.py --image_path_dsm $image_path_remaining/odm_dem/dsm.tif --image_path_dtm $image_path_remaining/odm_dem/dtm.tif --outfile_path_dsm $odm_dsm_png --outfile_path_dtm $odm_dtm_png --outfile_path_subtract $odm_subtract_png --band_number 1";
                my $odm_dem_open_status = system($odm_dem_cmd);

                my @odm_rgb_dsm_image_size = imgsize($odm_dsm_png);
                my $odm_rgb_dsm_image_width = $odm_rgb_dsm_image_size[0];
                my $odm_rgb_dsm_image_length = $odm_rgb_dsm_image_size[1];

                # if ($odm_rgb_image_width != $odm_rgb_dsm_image_width) {
                #     $c->stash->{message} = "The ODM stitched RGB orthophoto is not the same width as the DSM! Something went wrong, please try again. It is possible ODM could not stitch your RGB image captures.";
                #     $c->stash->{template} = 'generic_message.mas';
                #     return;
                # }
                # if ($odm_rgb_image_length != $odm_rgb_dsm_image_length) {
                #     $c->stash->{message} = "The ODM stitched RGB orthophoto is not the same length as the DSM! Something went wrong, please try again. It is possible ODM could not stitch your RGB image captures.";
                #     $c->stash->{template} = 'generic_message.mas';
                #     return;
                # }

                my $odm_point_cloud_obj = "$image_path_remaining/odm_filterpoints/point_cloud.obj";
                my $odm_point_cloud_gltf = "$image_path_remaining/odm_filterpoints/point_cloud.gltf";
                my $odm_point_cloud_pcd = "$image_path_remaining/odm_filterpoints/point_cloud.pcd";
                my $odm_point_cloud_csv = "$image_path_remaining/odm_filterpoints/point_cloud.csv";
                my $odm_ply_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/Open3DConvertPLY.py --input_ply_path $odm_final_point_cloud --output_obj_path $odm_point_cloud_obj --output_pcd_path $odm_point_cloud_pcd --output_gltf_path $odm_point_cloud_gltf --output_vertices_path $odm_point_cloud_csv";
                print STDERR $odm_ply_cmd."\n";
                my $odm_ply_status = system($odm_ply_cmd);

                push @stitched_result_files, ['drone_run_experiment_odm_stitched_image', $odm_rgb_orthophoto];

                push @stitched_result_files, ['drone_run_experiment_odm_stitched_dsm', $odm_dsm_png];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_dtm', $odm_dtm_png];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_dsm_minus_dtm', $odm_subtract_png];

                push @stitched_result_files, ['drone_run_experiment_odm_stitched_point_cloud', $odm_final_point_cloud];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_point_cloud_obj', $odm_point_cloud_obj];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_point_cloud_pcd', $odm_point_cloud_pcd];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_point_cloud_gltf', $odm_point_cloud_gltf];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_point_cloud_csv', $odm_point_cloud_csv];

                push @stitched_result_files, ['drone_run_experiment_odm_stitched_reconstruction', $odm_final_sfm_reconstruction];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_shots', $odm_final_report_shots];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_stats', $odm_final_report_stats];
                push @stitched_result_files, ['drone_run_experiment_odm_stitched_report', $odm_final_report];

                my @geoparams_coordinates;
                my $outfile_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/imageXXXX').".png";
                my $outfile_image_r = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/imageXXXX').".png";
                my $outfile_image_g = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/imageXXXX').".png";
                my $outfile_image_b = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/imageXXXX').".png";
                my $outfile_geoparams = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/fileXXXX').".csv";
                my $outfile_geoparams_projection = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/fileXXXX').".csv";

                my $geo_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/GDALOpenImageRGBGeoTiff.py --image_path $odm_rgb_orthophoto --outfile_path_image $outfile_image --outfile_path_image_1 $outfile_image_r --outfile_path_image_2 $outfile_image_g --outfile_path_image_3 $outfile_image_b --outfile_path_geo_params $outfile_geoparams --outfile_path_geo_projection $outfile_geoparams_projection";
                print STDERR $geo_cmd."\n";
                my $geo_cmd_status = system($geo_cmd);
                my $ortho_file = $outfile_image;

                open(my $fh_geoparams, '<', $outfile_geoparams) or die "Could not open file '".$outfile_geoparams."' $!";
                    print STDERR "Opened ".$outfile_geoparams."\n";
                    my $geoparams = <$fh_geoparams>;
                    chomp $geoparams;
                    @geoparams_coordinates = split ',', $geoparams;
                    print STDERR Dumper [$geoparams, \@geoparams_coordinates];
                close($fh_geoparams);

                my $geoparams_projection;
                open(my $fh_geoparam_proj, '<', $outfile_geoparams_projection) or die "Could not open file '".$outfile_geoparams_projection."' $!";
                    print STDERR "Opened ".$outfile_geoparams_projection."\n";
                    my $geoparams_proj = <$fh_geoparam_proj>;
                    chomp $geoparams_proj;
                    $geoparams_proj =~ s/,//g;
                    my @geoparams_proj_arr = split "\"\"\"\"", $geoparams_proj;
                    $geoparams_projection = $geoparams_proj_arr[3];
                    $geoparams_projection =~ s/\s//g;
                    print STDERR Dumper [$geoparams_proj, $geoparams_projection];
                close($fh_geoparam_proj);

                @stitched_bands = (
                    ["Color Image", "OpenDroneMap RGB Color Image", "RGB Color Image", $odm_rgb_orthophoto, \@geoparams_coordinates, $geoparams_projection],
                    ["DSM", "OpenDroneMap DSM", "Black and White Image", $odm_dsm_png, \@geoparams_coordinates, $geoparams_projection]
                );
            }
            else {
                die "Camera info not supported for raw image upload ODM stitch: $new_drone_run_camera_info\n";
            }

            my $calibration_info = '';
            if ($new_drone_run_band_stitching_odm_radiocalibration && $new_drone_run_camera_info eq 'micasense_5') {
                $calibration_info = ' with radiocalibration';
            }
            elsif (!$new_drone_run_band_stitching_odm_radiocalibration && $new_drone_run_camera_info eq 'micasense_5') {
                $calibration_info = ' without radiocalibration';
            }

            print STDERR Dumper \@stitched_bands;

            foreach my $m (@stitched_bands) {
                my $drone_run_band_name_id = $m->[0];
                my $drone_run_band_type_desc = $m->[1];
                my $drone_run_band_type = $m->[2];
                my $drone_run_band_img = $m->[3];
                my $drone_run_band_geoparam_coordinates = $m->[4];
                my $drone_run_band_geoparam_coordinates_type = $m->[5];

                my $time = DateTime->now();
                my $timestamp = $time->ymd()."_".$time->hms();
                my $upload_original_name = $new_drone_run_names_string_safe."_ImageBreed_stitched_".$m->[1].".png";

                my $uploader = CXGN::UploadFile->new({
                    tempfile => $drone_run_band_img,
                    subdirectory => "drone_imagery_upload",
                    archive_path => $c->config->{archive_path},
                    archive_filename => $upload_original_name,
                    timestamp => $timestamp,
                    user_id => $user_id,
                    user_role => $user_role
                });
                my $archived_filename_with_path = $uploader->archive();
                my $md5 = $uploader->get_md5($archived_filename_with_path);
                if (!$archived_filename_with_path) {
                    $c->stash->{message} = "Could not save file $upload_original_name in archive.";
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }
                unlink $upload_tempfile;
                print STDERR "Archived Drone Image File: $archived_filename_with_path\n";

                my @original_image_resize_ratio = (1,1);
                if ($c->config->{drone_imagery_allow_resize}) {
                    my ($check_image_width, $check_image_height) = imgsize($archived_filename_with_path);
                    my $check_image_width_original = $check_image_width;
                    my $check_image_height_original = $check_image_height;
                    if ($check_image_width > 16384) {
                        my $cmd_resize = $c->config->{python_executable}.' '.$c->config->{rootpath}.'/DroneImageScripts/ImageProcess/Resize.py --image_path \''.$archived_filename_with_path.'\' --outfile_path \''.$archived_filename_with_path.'\' --width 16384';
                        print STDERR Dumper $cmd_resize;
                        my $status_resize = system($cmd_resize);
                        my ($check_image_width_resized, $check_image_height_resized) = imgsize($archived_filename_with_path);
                        $check_image_width = $check_image_width_resized;
                        $check_image_height = $check_image_height_resized;
                    }
                    if ($check_image_height > 16384) {
                        my $cmd_resize = $c->config->{python_executable}.' '.$c->config->{rootpath}.'/DroneImageScripts/ImageProcess/Resize.py --image_path \''.$archived_filename_with_path.'\' --outfile_path \''.$archived_filename_with_path.'\' --height 16384';
                        print STDERR Dumper $cmd_resize;
                        my $status_resize = system($cmd_resize);
                    }
                    my ($check_image_width_saved, $check_image_height_saved) = imgsize($archived_filename_with_path);
                    @original_image_resize_ratio = ($check_image_width_original/$check_image_width_saved, $check_image_height_original/$check_image_height_saved);
                }

                my $image = SGN::Image->new( $schema->storage->dbh, undef, $c );
                $image->set_sp_person_id($user_id);
                my $linking_table_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'stitched_drone_imagery', 'project_md_image')->cvterm_id();

                my $iterator = 0;
                foreach my $selected_drone_run_obj (@selected_drone_run_infos) {
                    my $drone_run_name = $selected_drone_run_obj->{drone_run_name};
                    my $drone_run_id = $selected_drone_run_obj->{drone_run_id};
                    my $field_trial_id = $selected_drone_run_obj->{field_trial_id};
                    my $trial_location_id = $selected_drone_run_obj->{trial_location_id};

                    my $drone_run_band_name = $drone_run_name."_".$drone_run_band_type;

                    my $project_rs = $schema->resultset("Project::Project")->create({
                        name => $drone_run_band_name,
                        description => $new_drone_run_desc.". ".$drone_run_band_name_id." ".$drone_run_band_type_desc.". Orthomosaic stitched by OpenDroneMap in ImageBreed".$calibration_info.".",
                        projectprops => [
                            {type_id => $drone_run_band_type_cvterm_id, value => $drone_run_band_type},
                            {type_id => $design_cvterm_id, value => 'drone_run_band'},
                            {type_id => $geoparam_coordinates_cvterm_id, value => encode_json $drone_run_band_geoparam_coordinates},
                            {type_id => $geoparam_coordinates_type_cvterm_id, value => $drone_run_band_geoparam_coordinates_type},
                            {type_id => $original_image_resize_ratio_cvterm_id, value => encode_json \@original_image_resize_ratio}
                        ],
                        project_relationship_subject_projects => [{type_id => $project_relationship_type_id, object_project_id => $drone_run_id}]
                    });
                    my $selected_drone_run_band_id = $project_rs->project_id();

                    $h_priv->execute($private_company_id, $company_is_private, $selected_drone_run_band_id);

                    if ($iterator == 0) {
                        my $ret = $image->process_image($archived_filename_with_path, 'project', $selected_drone_run_band_id, $linking_table_type_id);
                    }
                    else {
                        my $ret = $image->associate_project($selected_drone_run_band_id, $linking_table_type_id);
                    }

                    # Storing uploaded zipfile of raw images
                    my $trial = CXGN::Trial->new({
                        bcs_schema => $schema,
                        metadata_schema => $metadata_schema,
                        phenome_schema => $phenome_schema,
                        trial_id => $drone_run_id
                    });
                    my $result_save_original_zip = $trial->add_additional_uploaded_file($user_id, $archived_filename_original_zip_with_path, $md5checksum_original_zip);

                    push @return_drone_run_band_image_urls, $image->get_image_url('original');
                    push @return_drone_run_band_image_ids, $image->get_image_id();
                    push @return_drone_run_band_project_ids, $selected_drone_run_band_id;

                    $iterator++;
                }
            }

            print STDERR Dumper \@stitched_result_files;
            foreach (@stitched_result_files) {
                my $nd_experiment_type_name = $_->[0];
                my $file_name = $_->[1];

                my $nd_experiment_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, $nd_experiment_type_name, 'experiment_type')->cvterm_id();
                my $experiment = $schema->resultset('NaturalDiversity::NdExperiment')->create({
                    nd_geolocation_id => $computation_location_id,
                    type_id => $nd_experiment_type_id,
                    nd_experiment_projects => \@nd_experiment_project_ids,
                });
                my $nd_experiment_id = $experiment->nd_experiment_id();

                my $md_row = $metadata_schema->resultset("MdMetadata")->create({create_person_id => $user_id});
                my $upload_file = CXGN::UploadFile->new();
                my $md5 = $upload_file->get_md5($file_name);
                my $md5checksum = $md5->hexdigest();
                my $file_row = $metadata_schema->resultset("MdFiles")->create({
                    basename => basename($file_name),
                    dirname => dirname($file_name),
                    filetype => $nd_experiment_type_name,
                    md5checksum => $md5checksum,
                    metadata_id => $md_row->metadata_id(),
                });
                my $file_id = $file_row->file_id();

                my $experiment_files = $phenome_schema->resultset("NdExperimentMdFiles")->create({
                    nd_experiment_id => $nd_experiment_id,
                    file_id => $file_id,
                });
            }

        };
        if ($@) {
            print STDERR $@;
        }

        $odm_check_prop->value('0');
        $odm_check_prop->update();

        if (scalar(@return_drone_run_band_project_ids) > 0 && scalar(@return_drone_run_band_project_ids) == scalar(@stitched_bands)*scalar(@new_drone_run_names)) {
            $c->stash->{message} = "Successfully uploaded! Go to <a href='/breeders/drone_imagery'>Drone Imagery</a>";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        else {
            $c->stash->{message} = "An error occurred! It is possible OpenDroneMap could not stitch your images!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
    }

}

sub upload_drone_imagery_bulk : Path("/drone_imagery/upload_drone_imagery_bulk") :Args(0) {
    my $self = shift;
    my $c = shift;
    $c->response->headers->header( "Access-Control-Allow-Origin" => '*' );
    $c->response->headers->header( "Access-Control-Allow-Methods" => "POST, GET, PUT, DELETE" );
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my $dbh = $c->dbc->dbh;
    my ($user_id, $user_name, $user_role) = _check_user_login_drone_imagery_upload($c, 'submitter', 0, 0);
    print STDERR Dumper $c->req->params();

    my $imaging_vehicle_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'imaging_event_vehicle', 'stock_type')->cvterm_id();
    my $imaging_vehicle_properties_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'imaging_event_vehicle_json', 'stock_property')->cvterm_id();
    my $drone_run_experiment_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_experiment', 'experiment_type')->cvterm_id();
    my $design_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'design', 'project_property')->cvterm_id();
    my $drone_run_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_project_type', 'project_property')->cvterm_id();
    my $drone_run_is_raw_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_is_raw_images', 'project_property')->cvterm_id();
    my $drone_run_camera_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_camera_type', 'project_property')->cvterm_id();
    my $project_start_date_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'project_start_date', 'project_property')->cvterm_id();
    my $drone_run_base_date_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_base_date', 'project_property')->cvterm_id();
    my $drone_run_rig_desc_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_camera_rig_description', 'project_property')->cvterm_id();
    my $drone_run_related_cvterms_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_related_time_cvterms_json', 'project_property')->cvterm_id();
    my $drone_run_band_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_project_type', 'project_property')->cvterm_id();
    my $project_relationship_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_on_field_trial', 'project_relationship')->cvterm_id();
    my $drone_run_drone_run_band_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_on_drone_run', 'project_relationship')->cvterm_id();
    my $geoparam_coordinates_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_geoparam_coordinates_type', 'project_property')->cvterm_id();
    my $geoparam_coordinates_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_geoparam_coordinates', 'project_property')->cvterm_id();
    my $original_image_resize_ratio_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_original_image_resize_ratio', 'project_property')->cvterm_id();
    my $rotated_image_resize_ratio_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_rotated_image_resize_ratio', 'project_property')->cvterm_id();
    my $calendar_funcs = CXGN::Calendar->new({});

    my $upload_file = $c->req->upload('upload_drone_imagery_bulk_images_zipfile');
    my $imaging_events_file = $c->req->upload('upload_drone_imagery_bulk_imaging_events');

    my $upload_original_name = $upload_file->filename();
    my $upload_tempfile = $upload_file->tempname;
    my $upload_imaging_events_file = $imaging_events_file->tempname;
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();

    my $uploader = CXGN::UploadFile->new({
        tempfile => $upload_tempfile,
        subdirectory => "drone_imagery_upload_bulk_orthophoto_zips",
        archive_path => $c->config->{archive_path},
        archive_filename => $upload_original_name,
        timestamp => $timestamp,
        user_id => $user_id,
        user_role => $user_role
    });
    my $archived_filename_with_path = $uploader->archive();
    my $md5 = $uploader->get_md5($archived_filename_with_path);
    if (!$archived_filename_with_path) {
        $c->stash->{message} = "Could not save file $upload_original_name in archive.";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    unlink $upload_tempfile;
    print STDERR "Archived Drone Image Bulk Orthophoto Zip File: $archived_filename_with_path\n";

    my $archived_zip = CXGN::ZipFile->new(archived_zipfile_path=>$archived_filename_with_path);
    my $file_members = $archived_zip->file_members();
    if (!$file_members){
        $c->stash->{message} = 'Could not read your orthophoto bulk zipfile. Is it .zip format?';
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    my %spectral_lookup = (
        blue => "Blue (450-520nm)",
        green => "Green (515-600nm)",
        red => "Red (600-690nm)",
        rededge => "Red Edge (690-750nm)",
        nir => "NIR (780-3000nm)",
        mir => "MIR (3000-50000nm)",
        fir => "FIR (50000-1000000nm)",
        thir => "Thermal IR (9000-14000nm)",
        rgb => "RGB Color Image",
        bw => "Black and White Image"
    );

    my %sensor_map = (
        "MicaSense 5 Channel Camera" => "micasense_5",
        "CCD Color Camera" => "ccd_color",
        "CMOS Color Camera" => "cmos_color"
    );

    my %filename_imaging_event_lookup;
    my %filename_imaging_event_band_check;
    foreach (@$file_members) {
        my $image = SGN::Image->new( $dbh, undef, $c );
        my $filename = $_->fileName();
        my @zipfile_comp = split '\/', $filename;
        my $filename_wext;
        if (scalar(@zipfile_comp)==1) {
            $filename_wext = $zipfile_comp[0];
        }
        else {
            $filename_wext = $zipfile_comp[1];
        }
        my @filename_comps = split '\.', $filename_wext;
        my $filename_only = $filename_comps[0];
        my @image_spectra = split '\_\_', $filename_only;
        my $temp_file = $image->upload_zipfile_images($_);
        my $imaging_event_name = $image_spectra[0];
        my $band = $image_spectra[1];

        if (!exists($spectral_lookup{$band})) {
            $c->stash->{message} = "The spectral band $band is not allowed in the provided orthophoto $filename_only. Make sure the orthophotos are saved as a concatenation of the imaging event name and the spectral band, with a double-underscore (__) as the separator (e.g. Ortho1_01012020__blue.tiff) and the allowed spectral bands are blue,green,red,rededge,nir,mir,fir,thir,rgb,bw.";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        my $spectral_band = $spectral_lookup{$band};
        print STDERR Dumper [$filename_wext, $filename, $temp_file, $imaging_event_name, $spectral_band];
        $filename_imaging_event_lookup{$filename_wext} = {
            file => $temp_file,
            band => $spectral_band,
            band_short => $band
        };
        if (exists($filename_imaging_event_band_check{$imaging_event_name}->{$spectral_band})) {
            $c->stash->{message} = "Do not upload duplicate spectral types for the same imaging event. There is already a $band image for $imaging_event_name in the zipfile! Make sure the orthophotos are saved as a concatenation of the imaging event name and the spectral band, with a double-underscore (__) as the separator (e.g. Ortho1_01012020__blue.tiff)";
            $c->stash->{template} = 'generic_message.mas';
            return;
        } else {
            $filename_imaging_event_band_check{$imaging_event_name} = $spectral_band;
        }
    }

    my @parse_csv_errors;
    my %field_trial_name_lookup;
    my %field_trial_ids_seen;
    my %vehicle_name_lookup;
    my %seen_field_trial_drone_run_dates;

    my $parser = Spreadsheet::ParseExcel->new();
    my $excel_obj = $parser->parse($upload_imaging_events_file);
    if (!$excel_obj) {
        $c->stash->{message} = 'The Excel (.xls) file could not be opened:'.$parser->error();
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    my $worksheet = ( $excel_obj->worksheets() )[0]; #support only one worksheet
    if (!$worksheet) {
        $c->stash->{message} = 'Spreadsheet must be on 1st tab in Excel (.xls) file.';
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    my ( $row_min, $row_max ) = $worksheet->row_range();
    my ( $col_min, $col_max ) = $worksheet->col_range();
    if (($col_max - $col_min)  < 1 || ($row_max - $row_min) < 1 ) { #must have header and at least one row of plot data
        $c->stash->{message} = 'Spreadsheet (.xls) is missing header or contains no rows.';
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    if ($worksheet->get_cell(0,0)->value() ne 'Imaging Event Name' ||
        $worksheet->get_cell(0,1)->value() ne 'Company' ||
        $worksheet->get_cell(0,2)->value() ne 'Type' ||
        $worksheet->get_cell(0,3)->value() ne 'Description' ||
        $worksheet->get_cell(0,4)->value() ne 'Date' ||
        $worksheet->get_cell(0,5)->value() ne 'Vehicle Name' ||
        $worksheet->get_cell(0,6)->value() ne 'Vehicle Battery Set' ||
        $worksheet->get_cell(0,7)->value() ne 'Sensor' ||
        $worksheet->get_cell(0,8)->value() ne 'Field Trial Name' ||
        $worksheet->get_cell(0,9)->value() ne 'Image Filenames' ||
        $worksheet->get_cell(0,10)->value() ne 'Coordinate System' ||
        $worksheet->get_cell(0,11)->value() ne 'Base Date' ||
        $worksheet->get_cell(0,12)->value() ne 'Camera Rig') {
            $c->stash->{message} = "The header row in the CSV spreadsheet must be 'Imaging Event Name,Company,Type,Description,Date,Vehicle Name,Vehicle Battery Set,Sensor,Field Trial Name,GeoJSON Filename,Image Filenames,Coordinate System,Base Date,Camera Rig'.";
            $c->stash->{template} = 'generic_message.mas';
            return;
    }

    my $private_companies = CXGN::PrivateCompany->new( { schema=> $schema } );
    my ($private_companies_array, $private_companies_ids, $allowed_private_company_ids_hash, $allowed_private_company_access_hash, $private_company_access_is_private_hash) = $private_companies->get_users_private_companies($user_id, 0);

    my $q_comp = "SELECT private_company_id FROM sgn_people.private_company WHERE name=?;";
    my $h_comp = $schema->storage->dbh()->prepare($q_comp);
    my %company_name_lookup;
    my %company_name_is_private_lookup;

    my $q_project = "SELECT private_company_id FROM project WHERE project_id=?;";
    my $h_project = $schema->storage->dbh()->prepare($q_project);

    my $q_stock = "SELECT private_company_id FROM stock WHERE stock_id=?;";
    my $h_stock = $schema->storage->dbh()->prepare($q_stock);

    my %seen_upload_dates;
    for my $row ( 1 .. $row_max ) {
        my $imaging_event_name;
        if ($worksheet->get_cell($row,0)) {
            $imaging_event_name = $worksheet->get_cell($row,0)->value();
        }
        my $company_name;
        if ($worksheet->get_cell($row,1)) {
            $company_name = $worksheet->get_cell($row,1)->value();
        }
        my $imaging_event_type;
        if ($worksheet->get_cell($row,2)) {
            $imaging_event_type = $worksheet->get_cell($row,2)->value();
        }
        my $imaging_event_desc;
        if ($worksheet->get_cell($row,3)) {
            $imaging_event_desc = $worksheet->get_cell($row,3)->value();
        }
        my $imaging_event_date;
        if ($worksheet->get_cell($row,4)) {
            $imaging_event_date = $worksheet->get_cell($row,4)->value();
        }
        my $vehicle_name;
        if ($worksheet->get_cell($row,5)) {
            $vehicle_name = $worksheet->get_cell($row,5)->value();
        }
        my $vehicle_battery = 'default_battery';
        if ($worksheet->get_cell($row,6)) {
            $vehicle_battery = $worksheet->get_cell($row,6)->value();
        }
        my $sensor;
        if ($worksheet->get_cell($row,7)) {
            $sensor = $worksheet->get_cell($row,7)->value();
        }
        my $field_trial_name;
        if ($worksheet->get_cell($row,8)) {
            $field_trial_name = $worksheet->get_cell($row,8)->value();
        }
        my $image_filenames;
        if ($worksheet->get_cell($row,9)) {
            $image_filenames = $worksheet->get_cell($row,9)->value();
        }
        my $coordinate_system;
        if ($worksheet->get_cell($row,10)) {
            $coordinate_system = $worksheet->get_cell($row,10)->value();
        }
        my $base_date;
        if ($worksheet->get_cell($row,11)) {
            $base_date = $worksheet->get_cell($row,11)->value();
        }
        my $rig_desc;
        if ($worksheet->get_cell($row,12)) {
            $rig_desc = $worksheet->get_cell($row,12)->value();
        }

        if (!$imaging_event_name){
            push @parse_csv_errors, "Please give a new imaging event name!";
        }

        my $private_company_id_current;
        if (!$company_name){
            push @parse_csv_errors, "Please give a company name!";
        }
        else {
            $h_comp->execute($company_name);
            my ($private_company_id) = $h_comp->fetchrow_array();
            if (!$private_company_id) {
                push @parse_csv_errors, "The company $company_name does not exist in the database!";
            }
            else {
                $private_company_id_current = $private_company_id;
                my $company_is_private = $private_company_access_is_private_hash->{$private_company_id} ? 1 : 0;

                if (!exists($allowed_private_company_ids_hash->{$private_company_id})) {
                    push @parse_csv_errors, "You do not belong to the company $company_name!";
                }
                if ($allowed_private_company_access_hash->{$private_company_id} ne 'curator_access' && $allowed_private_company_access_hash->{$private_company_id} ne 'submitter_access') {
                    push @parse_csv_errors, "You do not have submitter access or greater in company $company_name!";
                }
                $company_name_lookup{$company_name} = $private_company_id;
                $company_name_is_private_lookup{$company_name} = $company_is_private;
            }
        }

        if (!$imaging_event_type){
            push @parse_csv_errors, "Please give an imaging event type!";
        }
        if (!$imaging_event_desc){
            push @parse_csv_errors, "Please give an imaging event description!";
        }
        if (!$imaging_event_date){
            push @parse_csv_errors, "Please give an imaging event date!";
        }
        if (!$vehicle_name){
            push @parse_csv_errors, "Please give a vehicle name!";
        }
        if (!$sensor){
            push @parse_csv_errors, "Please give a sensor name!";
        }
        if (!$field_trial_name){
            push @parse_csv_errors, "Please give a field trial name!";
        }

        if ($coordinate_system ne 'UTM' && $coordinate_system ne 'WGS84' && $coordinate_system ne 'WGS84/UTM' && $coordinate_system ne 'Pixels') {
            push @parse_csv_errors, "The given coordinate system $coordinate_system is not one of: UTM, WGS84, WGS84/UTM, or Pixels!";
        }
        if ($coordinate_system ne 'Pixels') {
            $c->stash->{message} = "Only the Pixels coordinate system is currently supported for this upload. In the future GeoTIFFs will be supported, but for now please only upload simple raster images (.png, .tiff, .jpg).";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }

        my $field_trial_rs = $schema->resultset("Project::Project")->search({name=>$field_trial_name});
        if ($field_trial_rs->count != 1) {
            $c->stash->{message} = "The field trial $field_trial_name does not exist in the database already! Please add it first.";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        my $field_trial_id = $field_trial_rs->first->project_id();
        $field_trial_ids_seen{$field_trial_id}++;
        $field_trial_name_lookup{$field_trial_name} = $field_trial_id;

        $h_project->execute($field_trial_id);
        my ($trial_private_company_id) = $h_project->fetchrow_array();
        if ($private_company_id_current && $trial_private_company_id != $private_company_id_current) {
            push @parse_csv_errors, "The field trial $field_trial_name is not in the company $company_name! Cannot add an imaging event to a company that is different from the field trial.";
        }

        if ($imaging_event_date !~ /^\d{4}\/\d{2}\/\d{2}\s\d\d:\d\d:\d\d$/){
            $c->stash->{message} = "Please give a new imaging event date in the format YYYY/MM/DD HH:mm:ss! The provided $imaging_event_date is not correct!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        if ($imaging_event_type ne 'Aerial Medium to High Res' && $imaging_event_type ne 'Aerial Low Res'){
            $c->stash->{message} = "The imaging event type $imaging_event_type is not one of 'Aerial Low Res' or 'Aerial Medium to High Res'!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        if (!exists($sensor_map{$sensor})){
            $c->stash->{message} = "The sensor $sensor is not one of 'MicaSense 5 Channel Camera' or 'CCD Color Camera' or 'CMOS Color Camera'!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }

        my $project_rs = $schema->resultset("Project::Project")->search({name=>$imaging_event_name});
        if ($project_rs->count > 0) {
            push @parse_csv_errors, "Please use a globally unique imaging event name! The name you specified $imaging_event_name has already been used.";
        }

        my $vehicle_prop = $schema->resultset("Stock::Stock")->search({uniquename => $vehicle_name, type_id=>$imaging_vehicle_cvterm_id});
        if ($vehicle_prop->count != 1) {
            push @parse_csv_errors, "Imaging event vehicle $vehicle_name is not already in the database! Please add it first!";
        }
        else {
            my $vehicle_id = $vehicle_prop->first->stock_id;

            # $h_stock->execute($vehicle_id);
            # my ($vehicle_private_company_id) = $h_stock->fetchrow_array();
            # if ($private_company_id_current && $vehicle_private_company_id != $private_company_id_current) {
            #     push @parse_csv_errors, "The vehicle $vehicle_name is not in the company $company_name! Only use vehicles part of the same company!";
            # }

            $vehicle_name_lookup{$vehicle_name} = $vehicle_id;
        }

        my $trial = CXGN::Trial->new({ bcs_schema => $schema, trial_id => $field_trial_id });
        my $planting_date = $trial->get_planting_date();
        if (!$planting_date) {
            $c->stash->{message} = "The field trial $field_trial_name does not have a planting date set! Please set this first!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        my $planting_date_time_object = Time::Piece->strptime($planting_date, "%Y-%B-%d");
        my $imaging_event_date_time_object = Time::Piece->strptime($imaging_event_date, "%Y/%m/%d %H:%M:%S");

        $seen_upload_dates{$imaging_event_name} = {
            date => $imaging_event_date,
            time => $imaging_event_date_time_object->epoch,
            field_trial_name => $field_trial_name,
            field_trial_id => $field_trial_id
        };
        $seen_field_trial_drone_run_dates{$imaging_event_date_time_object->epoch}++;

        if ($imaging_event_date_time_object->epoch - $planting_date_time_object->epoch <= 0) {
            push @parse_csv_errors, "The date of the imaging event $imaging_event_date is not after the field trial planting date $planting_date!";
        }
        if ($base_date) {
            if ($base_date !~ /^\d{4}\/\d{2}\/\d{2}\s\d\d:\d\d:\d\d$/){
                $c->stash->{message} = "Please give a new imaging event base date in the format YYYY/MM/DD HH:mm:ss! The provided $base_date is not correct! Leave empty if not relevant!";
                $c->stash->{template} = 'generic_message.mas';
                return;
            }
            my $imaging_event_base_time_object = Time::Piece->strptime($base_date, "%Y/%m/%d %H:%M:%S");

            if ($imaging_event_date_time_object->epoch - $imaging_event_base_time_object->epoch < 0) {
                push @parse_csv_errors, "The date of the imaging event $imaging_event_date is not after the base date $base_date!";
            }
        }

        my @orthoimage_names = split ',', $image_filenames;
        foreach (@orthoimage_names) {
            if (!exists($filename_imaging_event_lookup{$_})) {
                push @parse_csv_errors, "The orthophoto filename $_ does not exist in the uploaded orthophoto zipfile. Make sure the orthophotos are saved as a concatenation of the ortho filename defined in the spreadsheet and the spectral band, with a double-underscore (__) as the separator (e.g. Ortho1_01012020__blue.tiff)";
            }
        }
    }

    # my $seen_field_trial_ids_check = join ',', keys %field_trial_ids_seen;
    # my $drone_run_date_q = "SELECT drone_run_date.value
    #     FROM project AS drone_run_band_project
    #     JOIN project_relationship AS drone_run_band_rel ON (drone_run_band_rel.subject_project_id = drone_run_band_project.project_id AND drone_run_band_rel.type_id = $drone_run_drone_run_band_type_id)
    #     JOIN project AS drone_run_project ON (drone_run_band_rel.object_project_id = drone_run_project.project_id)
    #     JOIN projectprop AS drone_run_date ON(drone_run_project.project_id=drone_run_date.project_id AND drone_run_date.type_id=$project_start_date_type_id)
    #     WHERE drone_run_project.project_id IN ($seen_field_trial_ids_check);";
    # my $drone_run_date_h = $schema->storage->dbh()->prepare($drone_run_date_q);
    # $drone_run_date_h->execute();
    # while( my ($drone_run_date) = $drone_run_date_h->fetchrow_array()) {
    #     my $drone_run_date_formatted = $drone_run_date ? $calendar_funcs->display_start_date($drone_run_date) : '';
    #     if ($drone_run_date_formatted) {
    #         my $date_obj = Time::Piece->strptime($drone_run_date_formatted, "%Y-%B-%d %H:%M:%S");
    #         $seen_field_trial_drone_run_dates{$date_obj->epoch}++;
    #     }
    # }
    #
    # while (my($imaging_event_name,$v) = each %seen_upload_dates) {
    #     my $time = $v->{time};
    #     my $date = $v->{date};
    #     my $field_trial_name = $v->{field_trial_name};
    #     my $field_trial_id = $v->{field_trial_id};
    #     if (exists($seen_field_trial_drone_run_dates{$time})) {
    #         $c->stash->{message} = "An imaging event has already occured on this field trial ($field_trial_name) at the same date and time ($date)! Please give a unique date/time for each imaging event!";
    #         $c->stash->{template} = 'generic_message.mas';
    #         return;
    #     }
    # }

    if (scalar(@parse_csv_errors) > 0) {
        my $error_string = join "<br/>", @parse_csv_errors;
        $c->stash->{message} = $error_string;
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    my $q_priv = "UPDATE project SET private_company_id=?, is_private=? WHERE project_id=?;";
    my $h_priv = $schema->storage->dbh()->prepare($q_priv);

    my @drone_run_project_ids;
    my %drone_run_band_hash;
    for my $row ( 1 .. $row_max ) {
        my $imaging_event_name = $worksheet->get_cell($row,0)->value();
        my $company_name = $worksheet->get_cell($row,1)->value();
        my $imaging_event_type = $worksheet->get_cell($row,2)->value();
        my $imaging_event_desc = $worksheet->get_cell($row,3)->value();
        my $imaging_event_date = $worksheet->get_cell($row,4)->value();
        my $vehicle_name = $worksheet->get_cell($row,5)->value();
        my $vehicle_battery = $worksheet->get_cell($row,6) ? $worksheet->get_cell($row,6)->value() : 'default_battery';
        my $sensor = $worksheet->get_cell($row,7)->value();
        my $field_trial_name = $worksheet->get_cell($row,8)->value();
        my $image_filenames = $worksheet->get_cell($row,9)->value();
        my $coordinate_system = $worksheet->get_cell($row,10)->value();
        my $base_date = $worksheet->get_cell($row,11) ? $worksheet->get_cell($row,11)->value() : '';
        my $rig_desc = $worksheet->get_cell($row,12) ? $worksheet->get_cell($row,12)->value() : '';

        my $private_company_id = $company_name_lookup{$company_name};
        my $private_company_is_private = $company_name_is_private_lookup{$company_name};
        my $new_drone_run_vehicle_id = $vehicle_name_lookup{$vehicle_name};
        my $selected_trial_id = $field_trial_name_lookup{$field_trial_name};
        my $new_drone_run_camera_info = $sensor_map{$sensor};
        my $trial = CXGN::Trial->new({ bcs_schema => $schema, trial_id => $selected_trial_id });
        my $trial_location_id = $trial->get_location()->[0];
        my $planting_date = $trial->get_planting_date();
        my $planting_date_time_object = Time::Piece->strptime($planting_date, "%Y-%B-%d");
        my $imaging_event_date_time_object = Time::Piece->strptime($imaging_event_date, "%Y/%m/%d %H:%M:%S");
        my $drone_run_event = $calendar_funcs->check_value_format($imaging_event_date);
        my $time_diff;
        my $base_date_event;
        if ($base_date) {
            my $imaging_event_base_date_time_object = Time::Piece->strptime($base_date, "%Y/%m/%d %H:%M:%S");
            $time_diff = $imaging_event_date_time_object - $imaging_event_base_date_time_object;
            $base_date_event = $calendar_funcs->check_value_format($base_date);
        }
        else {
            $time_diff = $imaging_event_date_time_object - $planting_date_time_object;
        }
        my $time_diff_weeks = $time_diff->weeks;
        my $time_diff_days = $time_diff->days;
        my $time_diff_hours = $time_diff->hours;
        my $rounded_time_diff_weeks = round($time_diff_weeks);
        if ($rounded_time_diff_weeks == 0) {
            $rounded_time_diff_weeks = 1;
        }

        my $week_term_string = "week $rounded_time_diff_weeks";
        my $q = "SELECT t.cvterm_id FROM cvterm as t JOIN cv ON(t.cv_id=cv.cv_id) WHERE t.name=? and cv.name=?;";
        my $h = $schema->storage->dbh()->prepare($q);
        $h->execute($week_term_string, 'cxgn_time_ontology');
        my ($week_cvterm_id) = $h->fetchrow_array();

        if (!$week_cvterm_id) {
            my $new_week_term = $schema->resultset("Cv::Cvterm")->create_with({
               name => $week_term_string,
               cv => 'cxgn_time_ontology'
            });
            $week_cvterm_id = $new_week_term->cvterm_id();
        }

        my $day_term_string = "day $time_diff_days";
        $h->execute($day_term_string, 'cxgn_time_ontology');
        my ($day_cvterm_id) = $h->fetchrow_array();

        if (!$day_cvterm_id) {
            my $new_day_term = $schema->resultset("Cv::Cvterm")->create_with({
               name => $day_term_string,
               cv => 'cxgn_time_ontology'
            });
            $day_cvterm_id = $new_day_term->cvterm_id();
        }

        my $week_term = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $week_cvterm_id, 'extended');
        my $day_term = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $day_cvterm_id, 'extended');

        my %related_cvterms = (
            week => $week_term,
            day => $day_term
        );

        my $drone_run_projectprops = [
            {type_id => $drone_run_type_cvterm_id, value => $imaging_event_type},
            {type_id => $project_start_date_type_id, value => $drone_run_event},
            {type_id => $design_cvterm_id, value => 'drone_run'},
            {type_id => $drone_run_camera_type_cvterm_id, value => $new_drone_run_camera_info},
            {type_id => $drone_run_related_cvterms_cvterm_id, value => encode_json \%related_cvterms}
        ];
        if ($base_date) {
            push @$drone_run_projectprops, {type_id => $drone_run_base_date_type_id, value => $base_date_event};
        }
        if ($rig_desc) {
            push @$drone_run_projectprops, {type_id => $drone_run_rig_desc_type_id, value => $rig_desc};
        }

        my $nd_experiment_rs = $schema->resultset("NaturalDiversity::NdExperiment")->create({
            nd_geolocation_id => $trial_location_id,
            type_id => $drone_run_experiment_type_id,
            nd_experiment_stocks => [{stock_id => $new_drone_run_vehicle_id, type_id => $drone_run_experiment_type_id}]
        });
        my $drone_run_nd_experiment_id = $nd_experiment_rs->nd_experiment_id();

        my $project_rs = $schema->resultset("Project::Project")->create({
            name => $imaging_event_name,
            description => $imaging_event_desc,
            projectprops => $drone_run_projectprops,
            project_relationship_subject_projects => [{type_id => $project_relationship_type_id, object_project_id => $selected_trial_id}],
            nd_experiment_projects => [{nd_experiment_id => $drone_run_nd_experiment_id}]
        });
        my $selected_drone_run_id = $project_rs->project_id();
        push @drone_run_project_ids, $selected_drone_run_id;

        $h_priv->execute($private_company_id, $private_company_is_private, $selected_drone_run_id);

        my $vehicle_prop = decode_json $schema->resultset("Stock::Stockprop")->search({stock_id => $new_drone_run_vehicle_id, type_id=>$imaging_vehicle_properties_cvterm_id})->first()->value();
        $vehicle_prop->{batteries}->{$vehicle_battery}->{usage}++;
        my $vehicle_prop_update = $schema->resultset('Stock::Stockprop')->update_or_create({
            type_id=>$imaging_vehicle_properties_cvterm_id,
            stock_id=>$new_drone_run_vehicle_id,
            rank=>0,
            value=>encode_json $vehicle_prop
        },
        {
            key=>'stockprop_c1'
        });

        my @orthoimage_names = split ',', $image_filenames;
        my @ortho_images;
        foreach (@orthoimage_names) {
            push @ortho_images, $filename_imaging_event_lookup{$_};
        }
        foreach my $m (@ortho_images) {
            my $project_relationship_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_on_drone_run', 'project_relationship')->cvterm_id();
            my $band = $m->{band};
            my $band_short = $m->{band_short};
            my $file = $m->{file};

            my $time = DateTime->now();
            my $timestamp = $time->ymd()."_".$time->hms();
            my $upload_original_name = $imaging_event_name."_".$band_short.".png";

            my $uploader = CXGN::UploadFile->new({
                tempfile => $file,
                subdirectory => "drone_imagery_upload",
                archive_path => $c->config->{archive_path},
                archive_filename => $upload_original_name,
                timestamp => $timestamp,
                user_id => $user_id,
                user_role => $user_role
            });
            my $archived_filename_with_path = $uploader->archive();
            my $md5 = $uploader->get_md5($archived_filename_with_path);
            if (!$archived_filename_with_path) {
                $c->stash->{rest} = { error => "Could not save file $upload_original_name in archive." };
                $c->detach();
            }
            unlink $upload_tempfile;
            print STDERR "Archived Bulk Orthophoto File: $archived_filename_with_path\n";

            my @original_image_resize_ratio = (1,1);
            if ($c->config->{drone_imagery_allow_resize}) {
                my ($check_image_width, $check_image_height) = imgsize($archived_filename_with_path);
                my $check_image_width_original = $check_image_width;
                my $check_image_height_original = $check_image_height;
                if ($check_image_width > 16384) {
                    my $cmd_resize = $c->config->{python_executable}.' '.$c->config->{rootpath}.'/DroneImageScripts/ImageProcess/Resize.py --image_path \''.$archived_filename_with_path.'\' --outfile_path \''.$archived_filename_with_path.'\' --width 16384';
                    print STDERR Dumper $cmd_resize;
                    my $status_resize = system($cmd_resize);
                    my ($check_image_width_resized, $check_image_height_resized) = imgsize($archived_filename_with_path);
                    $check_image_width = $check_image_width_resized;
                    $check_image_height = $check_image_height_resized;
                }
                if ($check_image_height > 16384) {
                    my $cmd_resize = $c->config->{python_executable}.' '.$c->config->{rootpath}.'/DroneImageScripts/ImageProcess/Resize.py --image_path \''.$archived_filename_with_path.'\' --outfile_path \''.$archived_filename_with_path.'\' --height 16384';
                    print STDERR Dumper $cmd_resize;
                    my $status_resize = system($cmd_resize);
                }
                my ($check_image_width_saved, $check_image_height_saved) = imgsize($archived_filename_with_path);
                @original_image_resize_ratio = ($check_image_width_original/$check_image_width_saved, $check_image_height_original/$check_image_height_saved);
            }

            my $project_rs = $schema->resultset("Project::Project")->create({
                name => $imaging_event_name."_".$band_short,
                description => $imaging_event_desc.". ".$band,
                projectprops => [
                    {type_id => $drone_run_band_type_cvterm_id, value => $band},
                    {type_id => $design_cvterm_id, value => 'drone_run_band'},
                    {type_id => $geoparam_coordinates_type_cvterm_id, value => $coordinate_system},
                    {type_id => $original_image_resize_ratio_cvterm_id, value => encode_json \@original_image_resize_ratio},
                ],
                project_relationship_subject_projects => [{type_id => $project_relationship_type_id, object_project_id => $selected_drone_run_id}]
            });
            my $selected_drone_run_band_id = $project_rs->project_id();

            $h_priv->execute($private_company_id, $private_company_is_private, $selected_drone_run_band_id);

            my $image = SGN::Image->new( $schema->storage->dbh, undef, $c );
            $image->set_sp_person_id($user_id);
            my $linking_table_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'stitched_drone_imagery', 'project_md_image')->cvterm_id();
            my $ret = $image->process_image($archived_filename_with_path, 'project', $selected_drone_run_band_id, $linking_table_type_id);

            push @{$drone_run_band_hash{$selected_drone_run_id}}, {
                drone_run_band_project_id => $selected_drone_run_band_id,
                band => $band
            };
        }
    }

    $c->stash->{message} = "Successfully uploaded! Go to <a href='/breeders/drone_imagery'>Drone Imagery</a>";
    $c->stash->{template} = 'generic_message.mas';
    return;
}

sub upload_drone_imagery_bulk_previous : Path("/drone_imagery/upload_drone_imagery_bulk_previous") :Args(0) {
    my $self = shift;
    my $c = shift;
    $c->response->headers->header( "Access-Control-Allow-Origin" => '*' );
    $c->response->headers->header( "Access-Control-Allow-Methods" => "POST, GET, PUT, DELETE" );
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my $dbh = $c->dbc->dbh;
    my ($user_id, $user_name, $user_role) = _check_user_login_drone_imagery_upload($c, 'submitter', 0, 0);
    print STDERR Dumper $c->req->params();

    my $imaging_vehicle_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'imaging_event_vehicle', 'stock_type')->cvterm_id();
    my $imaging_vehicle_properties_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'imaging_event_vehicle_json', 'stock_property')->cvterm_id();
    my $drone_run_experiment_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_experiment', 'experiment_type')->cvterm_id();
    my $design_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'design', 'project_property')->cvterm_id();
    my $geoparam_coordinates_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_geoparam_coordinates_type', 'project_property')->cvterm_id();
    my $geoparam_coordinates_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_geoparam_coordinates', 'project_property')->cvterm_id();
    my $geoparam_coordinates_plot_polygons_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_geoparam_coordinates_plot_polygons', 'project_property')->cvterm_id();
    my $drone_run_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_project_type', 'project_property')->cvterm_id();
    my $drone_run_is_raw_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_is_raw_images', 'project_property')->cvterm_id();
    my $drone_run_camera_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_camera_type', 'project_property')->cvterm_id();
    my $project_start_date_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'project_start_date', 'project_property')->cvterm_id();
    my $drone_run_base_date_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_base_date', 'project_property')->cvterm_id();
    my $drone_run_rig_desc_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_camera_rig_description', 'project_property')->cvterm_id();
    my $drone_run_related_cvterms_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_related_time_cvterms_json', 'project_property')->cvterm_id();
    my $drone_run_band_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_project_type', 'project_property')->cvterm_id();
    my $project_relationship_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_on_field_trial', 'project_relationship')->cvterm_id();
    my $process_indicator_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_standard_process_in_progress', 'project_property')->cvterm_id();
    my $processed_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_standard_process_completed', 'project_property')->cvterm_id();
    my $processed_minimal_vi_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_standard_process_vi_completed', 'project_property')->cvterm_id();
    my $rotate_angle_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_rotate_angle', 'project_property')->cvterm_id();
    my $cropping_polygon_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_cropped_polygon', 'project_property')->cvterm_id();
    my $plot_polygon_template_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_plot_polygons', 'project_property')->cvterm_id();
    my $project_image_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'stitched_drone_imagery', 'project_md_image')->cvterm_id();
    my $drone_run_drone_run_band_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_on_drone_run', 'project_relationship')->cvterm_id();
    my $original_image_resize_ratio_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_original_image_resize_ratio', 'project_property')->cvterm_id();
    my $rotated_image_resize_ratio_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_rotated_image_resize_ratio', 'project_property')->cvterm_id();
    my $calendar_funcs = CXGN::Calendar->new({});

    my %seen_field_trial_drone_run_dates;
    my $drone_run_date_q = "SELECT drone_run_date.value
        FROM project AS drone_run_band_project
        JOIN project_relationship AS drone_run_band_rel ON (drone_run_band_rel.subject_project_id = drone_run_band_project.project_id AND drone_run_band_rel.type_id = $drone_run_drone_run_band_type_id)
        JOIN project AS drone_run_project ON (drone_run_band_rel.object_project_id = drone_run_project.project_id)
        JOIN projectprop AS drone_run_date ON(drone_run_project.project_id=drone_run_date.project_id AND drone_run_date.type_id=$project_start_date_type_id);";
    my $drone_run_date_h = $schema->storage->dbh()->prepare($drone_run_date_q);
    $drone_run_date_h->execute();
    while( my ($drone_run_date) = $drone_run_date_h->fetchrow_array()) {
        my $drone_run_date_formatted = $drone_run_date ? $calendar_funcs->display_start_date($drone_run_date) : '';
        if ($drone_run_date_formatted) {
            my $date_obj = Time::Piece->strptime($drone_run_date_formatted, "%Y-%B-%d %H:%M:%S");
            $seen_field_trial_drone_run_dates{$date_obj->epoch}++;
        }
    }

    my %spectral_lookup = (
        blue => "Blue (450-520nm)",
        green => "Green (515-600nm)",
        red => "Red (600-690nm)",
        rededge => "Red Edge (690-750nm)",
        nir => "NIR (780-3000nm)",
        mir => "MIR (3000-50000nm)",
        fir => "FIR (50000-1000000nm)",
        thir => "Thermal IR (9000-14000nm)",
        rgb => "RGB Color Image",
        bw => "Black and White Image"
    );

    my %sensor_map = (
        "MicaSense 5 Channel Camera" => "micasense_5",
        "CCD Color Camera" => "ccd_color",
        "CMOS Color Camera" => "cmos_color"
    );

    my $upload_file = $c->req->upload('upload_drone_imagery_bulk_images_zipfile_previous');
    my $upload_geojson_file = $c->req->upload('upload_drone_imagery_bulk_geojson_zipfile_previous');
    my $imaging_events_file = $c->req->upload('upload_drone_imagery_bulk_imaging_events_previous');

    my $upload_original_name = $upload_file->filename();
    my $upload_tempfile = $upload_file->tempname;
    my $upload_geojson_original_name = $upload_geojson_file->filename();
    my $upload_geojson_tempfile = $upload_geojson_file->tempname;
    my $upload_imaging_events_file = $imaging_events_file->tempname;
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();

    my $uploader = CXGN::UploadFile->new({
        tempfile => $upload_tempfile,
        subdirectory => "drone_imagery_upload_bulk_previous_orthophoto_zips",
        archive_path => $c->config->{archive_path},
        archive_filename => $upload_original_name,
        timestamp => $timestamp,
        user_id => $user_id,
        user_role => $user_role
    });
    my $archived_filename_with_path = $uploader->archive();
    my $md5 = $uploader->get_md5($archived_filename_with_path);
    if (!$archived_filename_with_path) {
        $c->stash->{rest} = { error => "Could not save file $upload_original_name in archive." };
        $c->detach();
    }
    unlink $upload_tempfile;
    print STDERR "Archived Drone Image Bulk Previous Orthophoto Zip File: $archived_filename_with_path\n";

    my $archived_zip = CXGN::ZipFile->new(archived_zipfile_path=>$archived_filename_with_path);
    my $file_members = $archived_zip->file_members();
    if (!$file_members){
        $c->stash->{message} = 'Could not read your orthophoto bulk zipfile. Is it .zip format';
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    my %filename_imaging_event_lookup;
    my %filename_imaging_event_band_check;
    foreach (@$file_members) {
        my $image = SGN::Image->new( $dbh, undef, $c );
        my $filename = $_->fileName();
        my @zipfile_comp = split '\/', $filename;
        my $filename_wext;
        if (scalar(@zipfile_comp)==1) {
            $filename_wext = $zipfile_comp[0];
        }
        else {
            $filename_wext = $zipfile_comp[1];
        }
        my @filename_comps = split '\.', $filename_wext;
        my $filename_only = $filename_comps[0];
        my @image_spectra = split '\_\_', $filename_only;
        my $temp_file = $image->upload_zipfile_images($_);
        my $imaging_event_name = $image_spectra[0];
        my $band = $image_spectra[1];

        if (!exists($spectral_lookup{$band})) {
            $c->stash->{message} = "The spectral band $band is not allowed in the provided orthophoto $filename. Make sure the orthophotos are saved as a concatenation with the spectral band, with a double-underscore (__) as the separator (e.g. Ortho1_01012020__blue.tiff) and the allowed spectral bands are blue,green,red,rededge,nir,mir,fir,thir,rgb,bw.";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        my $spectral_band = $spectral_lookup{$band};
        print STDERR Dumper [$filename_wext, $filename, $temp_file, $imaging_event_name, $spectral_band];
        $filename_imaging_event_lookup{$filename_wext} = {
            file => $temp_file,
            band => $spectral_band,
            band_short => $band
        };
        if (exists($filename_imaging_event_band_check{$imaging_event_name}->{$spectral_band})) {
            $c->stash->{message} = "Do not upload duplicate spectral types for the same imaging event. There is already a $band image for $imaging_event_name in the zipfile! Make sure the orthophotos are saved as a concatenation of the imaging event name and the spectral band, with a double-underscore (__) as the separator (e.g. Ortho1_01012020__blue.tiff)";
            $c->stash->{template} = 'generic_message.mas';
            return;
        } else {
            $filename_imaging_event_band_check{$imaging_event_name}->{$spectral_band}++;
        }
    }

    my $uploader_geojson = CXGN::UploadFile->new({
        tempfile => $upload_geojson_tempfile,
        subdirectory => "drone_imagery_upload_bulk_previous_geojson_zips",
        archive_path => $c->config->{archive_path},
        archive_filename => $upload_geojson_original_name,
        timestamp => $timestamp,
        user_id => $user_id,
        user_role => $user_role
    });
    my $geojson_archived_filename_with_path = $uploader_geojson->archive();
    my $md5_geojson = $uploader_geojson->get_md5($geojson_archived_filename_with_path);
    if (!$geojson_archived_filename_with_path) {
        $c->stash->{message} = "Could not save file $upload_geojson_original_name in archive.";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    unlink $upload_geojson_tempfile;
    print STDERR "Archived Drone Image Bulk Previous GeoJSON Zip File: $geojson_archived_filename_with_path\n";

    my $archived_zip_geojson = CXGN::ZipFile->new(archived_zipfile_path=>$geojson_archived_filename_with_path);
    my $file_members_geojson = $archived_zip_geojson->file_members();
    if (!$file_members_geojson){
        $c->stash->{message} = 'Could not read your geojson bulk zipfile. Is it .zip format?';
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    my %filename_imaging_event_geojson_lookup;
    foreach (@$file_members_geojson) {
        my $image = SGN::Image->new( $dbh, undef, $c );
        my $filename = $_->fileName();
        my $temp_file = $image->upload_zipfile_images($_);

        my @zipfile_comp = split '\/', $filename;
        my $filename_wext;
        if (scalar(@zipfile_comp) == 1) {
            $filename_wext = $zipfile_comp[0];
        }
        else {
            $filename_wext = $zipfile_comp[1];
        }

        print STDERR Dumper [$filename, $temp_file, $filename_wext];
        $filename_imaging_event_geojson_lookup{$filename_wext} = $temp_file;

        open(my $fh_geojson_check, '<', $temp_file) or die "Could not open file '$temp_file' $!";
            print STDERR "Opened $temp_file\n";
            my $geojson_value_check = decode_json <$fh_geojson_check>;
            # print STDERR Dumper $geojson_value_check;
            if (!$geojson_value_check->{features}) {
                $c->stash->{message} = 'The GeoJSON file '.$filename.' does not have a \'features\' key in it. Make sure the GeoJSON is formatted correctly.';
                $c->stash->{template} = 'generic_message.mas';
                return;
            }
            foreach (@{$geojson_value_check->{features}}) {
                if (!$_->{properties}) {
                    $c->stash->{message} = 'The GeoJSON file '.$filename.' does not have a \'properties\' key in it. Make sure the GeoJSON is formatted correctly.';
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }
                if (!$_->{properties}->{ID}) {
                    $c->stash->{message} = 'The GeoJSON file '.$filename.' does not have an \'ID\' key in the \'properties\' object. Make sure the GeoJSON is formatted correctly.';
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }
                if (!$_->{geometry}) {
                    $c->stash->{message} = 'The GeoJSON file '.$filename.' does not have a \'geometry\' key in it. Make sure the GeoJSON is formatted correctly.';
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }
                if (!$_->{geometry}->{coordinates}) {
                    $c->stash->{message} = 'The GeoJSON file '.$filename.' does not have a \'coordinates\' key in the \'geometry\' object. Make sure the GeoJSON is formatted correctly.';
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }
                if (scalar(@{$_->{geometry}->{coordinates}->[0]}) != 5) {
                    $c->stash->{message} = 'The GeoJSON file '.$filename.' \'coordinates\' first object does not have 5 objects in it. The polygons must be rectangular Make sure the GeoJSON is formatted correctly.';
                    $c->stash->{template} = 'generic_message.mas';
                    return;
                }
            }
        close($fh_geojson_check);
    }

    my $private_companies = CXGN::PrivateCompany->new( { schema=> $schema } );
    my ($private_companies_array, $private_companies_ids, $allowed_private_company_ids_hash, $allowed_private_company_access_hash, $private_company_access_is_private_hash) = $private_companies->get_users_private_companies($user_id, 0);

    my $q_comp = "SELECT private_company_id FROM sgn_people.private_company WHERE name=?;";
    my $h_comp = $schema->storage->dbh()->prepare($q_comp);
    my %company_name_lookup;
    my %company_name_is_private_lookup;

    my $q_project = "SELECT private_company_id FROM project WHERE project_id=?;";
    my $h_project = $schema->storage->dbh()->prepare($q_project);

    my $q_stock = "SELECT private_company_id FROM stock WHERE stock_id=?;";
    my $h_stock = $schema->storage->dbh()->prepare($q_stock);

    my @parse_csv_errors;
    my %field_trial_name_lookup;
    my %field_trial_layout_lookup;
    my %vehicle_name_lookup;

    my $parser = Spreadsheet::ParseExcel->new();
    my $excel_obj = $parser->parse($upload_imaging_events_file);
    if (!$excel_obj) {
        $c->stash->{message} = 'The Excel (.xls) file could not be opened:'.$parser->error();
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    my $worksheet = ( $excel_obj->worksheets() )[0]; #support only one worksheet
    if (!$worksheet) {
        $c->stash->{message} = 'Spreadsheet must be on 1st tab in Excel (.xls) file.';
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    my ( $row_min, $row_max ) = $worksheet->row_range();
    my ( $col_min, $col_max ) = $worksheet->col_range();
    if (($col_max - $col_min)  < 1 || ($row_max - $row_min) < 1 ) { #must have header and at least one row of plot data
        $c->stash->{message} = 'Spreadsheet (.xls) is missing header or contains no rows.';
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    if ($worksheet->get_cell(0,0)->value() ne 'Imaging Event Name' ||
        $worksheet->get_cell(0,1)->value() ne 'Company' ||
        $worksheet->get_cell(0,2)->value() ne 'Type' ||
        $worksheet->get_cell(0,3)->value() ne 'Description' ||
        $worksheet->get_cell(0,4)->value() ne 'Date' ||
        $worksheet->get_cell(0,5)->value() ne 'Vehicle Name' ||
        $worksheet->get_cell(0,6)->value() ne 'Vehicle Battery Set' ||
        $worksheet->get_cell(0,7)->value() ne 'Sensor' ||
        $worksheet->get_cell(0,8)->value() ne 'Field Trial Name' ||
        $worksheet->get_cell(0,9)->value() ne 'GeoJSON Filename' ||
        $worksheet->get_cell(0,10)->value() ne 'Image Filenames' ||
        $worksheet->get_cell(0,11)->value() ne 'Coordinate System' ||
        $worksheet->get_cell(0,12)->value() ne 'Rotation Angle' ||
        $worksheet->get_cell(0,13)->value() ne 'Base Date' ||
        $worksheet->get_cell(0,14)->value() ne 'Camera Rig') {
            $c->stash->{message} = "The header row in the CSV spreadsheet must be 'Imaging Event Name,Company,Type,Description,Date,Vehicle Name,Vehicle Battery Set,Sensor,Field Trial Name,GeoJSON Filename,Image Filenames,Coordinate System,Rotation Angle,Base Date,Camera Rig'.";
            $c->stash->{template} = 'generic_message.mas';
            return;
    }

    my %seen_upload_dates;
    for my $row ( 1 .. $row_max ) {
        my $imaging_event_name;
        if ($worksheet->get_cell($row,0)) {
            $imaging_event_name = $worksheet->get_cell($row,0)->value();
        }
        my $company_name;
        if ($worksheet->get_cell($row,1)) {
            $company_name = $worksheet->get_cell($row,1)->value();
        }
        my $imaging_event_type;
        if ($worksheet->get_cell($row,2)) {
            $imaging_event_type = $worksheet->get_cell($row,2)->value();
        }
        my $imaging_event_desc;
        if ($worksheet->get_cell($row,3)) {
            $imaging_event_desc = $worksheet->get_cell($row,3)->value();
        }
        my $imaging_event_date;
        if ($worksheet->get_cell($row,4)) {
            $imaging_event_date = $worksheet->get_cell($row,4)->value();
        }
        my $vehicle_name;
        if ($worksheet->get_cell($row,5)) {
            $vehicle_name = $worksheet->get_cell($row,5)->value();
        }
        my $vehicle_battery = 'default_battery';
        if ($worksheet->get_cell($row,6)) {
            $vehicle_battery = $worksheet->get_cell($row,6)->value();
        }
        my $sensor;
        if ($worksheet->get_cell($row,7)) {
            $sensor = $worksheet->get_cell($row,7)->value();
        }
        my $field_trial_name;
        if ($worksheet->get_cell($row,8)) {
            $field_trial_name = $worksheet->get_cell($row,8)->value();
        }
        my $geojson_filename;
        if ($worksheet->get_cell($row,9)) {
            $geojson_filename = $worksheet->get_cell($row,9)->value();
        }
        my $image_filenames;
        if ($worksheet->get_cell($row,10)) {
            $image_filenames = $worksheet->get_cell($row,10)->value();
        }
        my $coordinate_system;
        if ($worksheet->get_cell($row,11)) {
            $coordinate_system = $worksheet->get_cell($row,11)->value();
        }
        my $rotation_angle;
        if ($worksheet->get_cell($row,12)) {
            $rotation_angle = $worksheet->get_cell($row,12)->value();
        }
        my $base_date;
        if ($worksheet->get_cell($row,13)) {
            $base_date = $worksheet->get_cell($row,13)->value();
        }
        my $rig_desc;
        if ($worksheet->get_cell($row,14)) {
            $rig_desc = $worksheet->get_cell($row,14)->value();
        }

        if (!$imaging_event_name){
            push @parse_csv_errors, "Please give a new imaging event name!";
        }

        my $private_company_id_current;
        if (!$company_name){
            push @parse_csv_errors, "Please give a company name!";
        }
        else {
            $h_comp->execute($company_name);
            my ($private_company_id) = $h_comp->fetchrow_array();
            if (!$private_company_id) {
                push @parse_csv_errors, "The company $company_name does not exist in the database!";
            }
            else {
                $private_company_id_current = $private_company_id;
                my $company_is_private = $private_company_access_is_private_hash->{$private_company_id} ? 1 : 0;

                if (!exists($allowed_private_company_ids_hash->{$private_company_id})) {
                    push @parse_csv_errors, "You do not belong to the company $company_name!";
                }
                if ($allowed_private_company_access_hash->{$private_company_id} ne 'curator_access' && $allowed_private_company_access_hash->{$private_company_id} ne 'submitter_access') {
                    push @parse_csv_errors, "You do not have submitter access or greater in company $company_name!";
                }
                $company_name_lookup{$company_name} = $private_company_id;
                $company_name_is_private_lookup{$company_name} = $company_is_private;
            }
        }

        if (!$imaging_event_type){
            push @parse_csv_errors, "Please give an imaging event type!";
        }
        if (!$imaging_event_desc){
            push @parse_csv_errors, "Please give an imaging event description!";
        }
        if (!$imaging_event_date){
            push @parse_csv_errors, "Please give an imaging event date!";
        }
        if (!$vehicle_name){
            push @parse_csv_errors, "Please give a vehicle name!";
        }
        if (!$sensor){
            push @parse_csv_errors, "Please give a sensor name!";
        }
        if (!$field_trial_name){
            push @parse_csv_errors, "Please give a field trial name!";
        }
        if (defined($rotation_angle) && ($rotation_angle < 0 || $rotation_angle > 360) ) {
            push @parse_csv_errors, "Rotation angle $rotation_angle not valid! Must be clock-wise between 0 and 360!";
        }

        if ($coordinate_system ne 'UTM' && $coordinate_system ne 'WGS84' && $coordinate_system ne 'WGS84/UTM' && $coordinate_system ne 'Pixels') {
            push @parse_csv_errors, "The given coordinate system $coordinate_system is not one of: UTM, WGS84, WGS84/UTM, or Pixels!";
        }
        # if ($coordinate_system ne 'Pixels') {
        #     $c->stash->{rest} = {error => "Only the Pixels coordinate system is currently supported. In the future GeoTIFFs will be supported, but for now please only upload simple raster images (.png, .tiff, .jpg)." };
        #     $c->detach;
        # }

        my $field_trial_rs = $schema->resultset("Project::Project")->search({name=>$field_trial_name});
        if ($field_trial_rs->count != 1) {
            $c->stash->{message} = "The field trial $field_trial_name does not exist in the database already! Please add it first.";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        my $field_trial_id = $field_trial_rs->first->project_id();
        $field_trial_name_lookup{$field_trial_name} = $field_trial_id;

        $h_project->execute($field_trial_id);
        my ($trial_private_company_id) = $h_project->fetchrow_array();
        if ($private_company_id_current && $trial_private_company_id != $private_company_id_current) {
            push @parse_csv_errors, "The field trial $field_trial_name is not in the company $company_name! Cannot add an imaging event to a company that is different from the field trial.";
        }

        if ($imaging_event_date !~ /^\d{4}\/\d{2}\/\d{2}\s\d\d:\d\d:\d\d$/){
            $c->stash->{message} = "Please give a new imaging event date in the format YYYY/MM/DD HH:mm:ss! The provided $imaging_event_date is not correct!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        if ($imaging_event_type ne 'Aerial Medium to High Res' && $imaging_event_type ne 'Aerial Low Res'){
            $c->stash->{message} = "The imaging event type $imaging_event_type is not one of 'Aerial Low Res' or 'Aerial Medium to High Res'!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        if (!exists($sensor_map{$sensor})){
            $c->stash->{message} = "The sensor $sensor is not one of 'MicaSense 5 Channel Camera' or 'CCD Color Camera' or 'CMOS Color Camera'!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }

        my $project_rs = $schema->resultset("Project::Project")->search({name=>$imaging_event_name});
        if ($project_rs->count > 0) {
            push @parse_csv_errors, "Please use a globally unique imaging event name! The name you specified $imaging_event_name has already been used.";
        }

        my $vehicle_prop = $schema->resultset("Stock::Stock")->search({uniquename => $vehicle_name, type_id=>$imaging_vehicle_cvterm_id});
        if ($vehicle_prop->count != 1) {
            push @parse_csv_errors, "Imaging event vehicle $vehicle_name is not already in the database! Please add it first!";
        }
        else {
            my $vehicle_id = $vehicle_prop->first->stock_id;

            # $h_stock->execute($vehicle_id);
            # my ($vehicle_private_company_id) = $h_stock->fetchrow_array();
            # if ($private_company_id_current && $vehicle_private_company_id != $private_company_id_current) {
            #     push @parse_csv_errors, "The vehicle $vehicle_name is not in the company $company_name! Only use vehicles part of the same company!";
            # }

            $vehicle_name_lookup{$vehicle_name} = $vehicle_id;
        }

        my $trial = CXGN::Trial->new({ bcs_schema => $schema, trial_id => $field_trial_id });
        my $trial_layout = $trial->get_layout()->get_design();
        $field_trial_layout_lookup{$field_trial_id} = $trial_layout;

        my $planting_date = $trial->get_planting_date();
        if (!$planting_date) {
            $c->stash->{message} = "The field trial $field_trial_name does not have a planting date set! Please set this first!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        my $planting_date_time_object = Time::Piece->strptime($planting_date, "%Y-%B-%d");
        my $imaging_event_date_time_object = Time::Piece->strptime($imaging_event_date, "%Y/%m/%d %H:%M:%S");

        if (exists($seen_field_trial_drone_run_dates{$imaging_event_date_time_object->epoch})) {
            $c->stash->{message} = "An imaging event has already occured on this field trial at the same date and time ($imaging_event_date)! Please give a unique date/time for each imaging event!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        $seen_field_trial_drone_run_dates{$imaging_event_date_time_object->epoch}++;

        if ($imaging_event_date_time_object->epoch - $planting_date_time_object->epoch <= 0) {
            push @parse_csv_errors, "The date of the imaging event $imaging_event_date is not after the field trial planting date $planting_date!";
        }
        if ($base_date) {
            if ($base_date !~ /^\d{4}\/\d{2}\/\d{2}\s\d\d:\d\d:\d\d$/){
                $c->stash->{message} = "Please give a new imaging event base date in the format YYYY/MM/DD HH:mm:ss! The provided $base_date is not correct! Leave empty if not relevant!";
                $c->stash->{template} = 'generic_message.mas';
                return;
            }
            my $imaging_event_base_time_object = Time::Piece->strptime($base_date, "%Y/%m/%d %H:%M:%S");

            if ($imaging_event_date_time_object->epoch - $imaging_event_base_time_object->epoch < 0) {
                push @parse_csv_errors, "The date of the imaging event $imaging_event_date is not after the base date $base_date!";
            }
        }

        my @orthoimage_names = split ',', $image_filenames;
        foreach (@orthoimage_names) {
            if (!exists($filename_imaging_event_lookup{$_})) {
                push @parse_csv_errors, "The orthophoto filename $_ does not exist in the uploaded orthophoto zipfile. Make sure the orthophotos are saved as a concatenation of the ortho filename defined in the spreadsheet and the spectral band, with a double-underscore (__) as the separator (e.g. Ortho1_01012020__blue.tiff)";
            }
        }
        if (!exists($filename_imaging_event_geojson_lookup{$geojson_filename})) {
            push @parse_csv_errors, "The GeoJSON filename $geojson_filename does not exist in the uploaded GeoJSON zipfile!";
        }
        open(my $fh_geojson_check, '<', $filename_imaging_event_geojson_lookup{$geojson_filename}) or die "Could not open file '".$filename_imaging_event_geojson_lookup{$geojson_filename}."' $!";
            print STDERR "Opened ".$filename_imaging_event_geojson_lookup{$geojson_filename}."\n";
            my $geojson_value_check = decode_json <$fh_geojson_check>;
            foreach (@{$geojson_value_check->{features}}) {
                my $plot_number = $_->{properties}->{ID};
                if (!exists($trial_layout->{$plot_number})) {
                    push @parse_csv_errors, "The ID $plot_number in the GeoJSON file $geojson_filename does not exist in the field trial $field_trial_name!";
                }
            }
        close($fh_geojson_check);
    }

    if (scalar(@parse_csv_errors) > 0) {
        my $error_string = join "<br/>", @parse_csv_errors;
        $c->stash->{message} = $error_string;
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    my $q_priv = "UPDATE project SET private_company_id=?, is_private=? WHERE project_id=?;";
    my $h_priv = $schema->storage->dbh()->prepare($q_priv);

    my $dir = $c->tempfiles_subdir('/upload_drone_imagery_bulk_previous');

    my @drone_run_project_ids;
    my @drone_run_projects;
    my %drone_run_project_info;
    for my $row ( 1 .. $row_max ) {
        my $imaging_event_name = $worksheet->get_cell($row,0)->value();
        my $company_name = $worksheet->get_cell($row,1)->value();
        my $imaging_event_type = $worksheet->get_cell($row,2)->value();
        my $imaging_event_desc = $worksheet->get_cell($row,3)->value();
        my $imaging_event_date = $worksheet->get_cell($row,4)->value();
        my $vehicle_name = $worksheet->get_cell($row,5)->value();
        my $vehicle_battery = $worksheet->get_cell($row,6) ? $worksheet->get_cell($row,6)->value() : 'default_battery';
        my $sensor = $worksheet->get_cell($row,7)->value();
        my $field_trial_name = $worksheet->get_cell($row,8)->value();
        my $geojson_filename = $worksheet->get_cell($row,9)->value();
        my $image_filenames = $worksheet->get_cell($row,10)->value();
        my $coordinate_system = $worksheet->get_cell($row,11)->value();
        my $rotation_angle = $worksheet->get_cell($row,12) ? $worksheet->get_cell($row,12)->value() : 0;
        my $base_date = $worksheet->get_cell($row,13) ? $worksheet->get_cell($row,13)->value() : '';
        my $rig_desc = $worksheet->get_cell($row,14) ? $worksheet->get_cell($row,14)->value() : '';

        my $private_company_id = $company_name_lookup{$company_name};
        my $private_company_is_private = $company_name_is_private_lookup{$company_name};
        my $new_drone_run_vehicle_id = $vehicle_name_lookup{$vehicle_name};
        my $selected_trial_id = $field_trial_name_lookup{$field_trial_name};
        my $new_drone_run_camera_info = $sensor_map{$sensor};
        my $trial = CXGN::Trial->new({ bcs_schema => $schema, trial_id => $selected_trial_id });
        my $trial_location_id = $trial->get_location()->[0];
        my $planting_date = $trial->get_planting_date();
        my $planting_date_time_object = Time::Piece->strptime($planting_date, "%Y-%B-%d");
        my $imaging_event_date_time_object = Time::Piece->strptime($imaging_event_date, "%Y/%m/%d %H:%M:%S");
        my $drone_run_event = $calendar_funcs->check_value_format($imaging_event_date);
        my $time_diff;
        my $base_date_event;
        if ($base_date) {
            my $imaging_event_base_date_time_object = Time::Piece->strptime($base_date, "%Y/%m/%d %H:%M:%S");
            $time_diff = $imaging_event_date_time_object - $imaging_event_base_date_time_object;
            $base_date_event = $calendar_funcs->check_value_format($base_date);
        }
        else {
            $time_diff = $imaging_event_date_time_object - $planting_date_time_object;
        }
        my $time_diff_weeks = $time_diff->weeks;
        my $time_diff_days = $time_diff->days;
        my $time_diff_hours = $time_diff->hours;
        my $rounded_time_diff_weeks = round($time_diff_weeks);
        if ($rounded_time_diff_weeks == 0) {
            $rounded_time_diff_weeks = 1;
        }

        my $week_term_string = "week $rounded_time_diff_weeks";
        my $q = "SELECT t.cvterm_id FROM cvterm as t JOIN cv ON(t.cv_id=cv.cv_id) WHERE t.name=? and cv.name=?;";
        my $h = $schema->storage->dbh()->prepare($q);
        $h->execute($week_term_string, 'cxgn_time_ontology');
        my ($week_cvterm_id) = $h->fetchrow_array();

        if (!$week_cvterm_id) {
            my $new_week_term = $schema->resultset("Cv::Cvterm")->create_with({
               name => $week_term_string,
               cv => 'cxgn_time_ontology'
            });
            $week_cvterm_id = $new_week_term->cvterm_id();
        }

        my $day_term_string = "day $time_diff_days";
        $h->execute($day_term_string, 'cxgn_time_ontology');
        my ($day_cvterm_id) = $h->fetchrow_array();

        if (!$day_cvterm_id) {
            my $new_day_term = $schema->resultset("Cv::Cvterm")->create_with({
               name => $day_term_string,
               cv => 'cxgn_time_ontology'
            });
            $day_cvterm_id = $new_day_term->cvterm_id();
        }

        my $week_term = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $week_cvterm_id, 'extended');
        my $day_term = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $day_cvterm_id, 'extended');

        my %related_cvterms = (
            week => $week_term,
            day => $day_term
        );

        my $drone_run_projectprops = [
            {type_id => $drone_run_type_cvterm_id, value => $imaging_event_type},
            {type_id => $project_start_date_type_id, value => $drone_run_event},
            {type_id => $design_cvterm_id, value => 'drone_run'},
            {type_id => $drone_run_camera_type_cvterm_id, value => $new_drone_run_camera_info},
            {type_id => $drone_run_related_cvterms_cvterm_id, value => encode_json \%related_cvterms}
        ];
        if ($base_date) {
            push @$drone_run_projectprops, {type_id => $drone_run_base_date_type_id, value => $base_date_event};
        }
        if ($rig_desc) {
            push @$drone_run_projectprops, {type_id => $drone_run_rig_desc_type_id, value => $rig_desc};
        }

        my $nd_experiment_rs = $schema->resultset("NaturalDiversity::NdExperiment")->create({
            nd_geolocation_id => $trial_location_id,
            type_id => $drone_run_experiment_type_id,
            nd_experiment_stocks => [{stock_id => $new_drone_run_vehicle_id, type_id => $drone_run_experiment_type_id}]
        });
        my $drone_run_nd_experiment_id = $nd_experiment_rs->nd_experiment_id();

        my $project_rs = $schema->resultset("Project::Project")->create({
            name => $imaging_event_name,
            description => $imaging_event_desc,
            projectprops => $drone_run_projectprops,
            project_relationship_subject_projects => [{type_id => $project_relationship_type_id, object_project_id => $selected_trial_id}],
            nd_experiment_projects => [{nd_experiment_id => $drone_run_nd_experiment_id}]
        });
        my $selected_drone_run_id = $project_rs->project_id();
        push @drone_run_project_ids, $selected_drone_run_id;

        $h_priv->execute($private_company_id, $private_company_is_private, $selected_drone_run_id);

        my $vehicle_prop = decode_json $schema->resultset("Stock::Stockprop")->search({stock_id => $new_drone_run_vehicle_id, type_id=>$imaging_vehicle_properties_cvterm_id})->first()->value();
        $vehicle_prop->{batteries}->{$vehicle_battery}->{usage}++;
        my $vehicle_prop_update = $schema->resultset('Stock::Stockprop')->update_or_create({
            type_id=>$imaging_vehicle_properties_cvterm_id,
            stock_id=>$new_drone_run_vehicle_id,
            rank=>0,
            value=>encode_json $vehicle_prop
        },
        {
            key=>'stockprop_c1'
        });

        my @orthoimage_names = split ',', $image_filenames;
        my @ortho_images;
        foreach (@orthoimage_names) {
            push @ortho_images, $filename_imaging_event_lookup{$_};
        }
        my @drone_run_band_projects;
        my @drone_run_band_project_ids;
        my @drone_run_band_geoparams_coordinates;

        my $geojson_temp_filename = $filename_imaging_event_geojson_lookup{$geojson_filename};
        my $geojson_value;

        foreach my $m (@ortho_images) {
            my $project_relationship_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_on_drone_run', 'project_relationship')->cvterm_id();
            my $band = $m->{band};
            my $band_short = $m->{band_short};
            my $file = $m->{file};

            my $time = DateTime->now();
            my $timestamp = $time->ymd()."_".$time->hms();
            my $upload_original_name = $imaging_event_name."_".$band_short.".png";

            my $ortho_file;
            my @geoparams_coordinates;
            my $geoparams_projection;
            if ($coordinate_system eq 'Pixels') {
                $ortho_file = $file;
                $geoparams_projection = $coordinate_system;
            }
            else {
                my $outfile_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_bulk_previous/imageXXXX').".png";
                my $outfile_geoparams = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_bulk_previous/fileXXXX').".csv";
                my $outfile_geoparams_projection = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_bulk_previous/fileXXXX').".csv";

                if ($band_short eq 'rgb') {
                    my $outfile_image_r = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_bulk_previous/imageXXXX').".png";
                    my $outfile_image_g = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_bulk_previous/imageXXXX').".png";
                    my $outfile_image_b = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_bulk_previous/imageXXXX').".png";

                    my $geo_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/GDALOpenImageRGBGeoTiff.py --image_path $file --outfile_path_image $outfile_image --outfile_path_image_1 $outfile_image_r --outfile_path_image_2 $outfile_image_g --outfile_path_image_3 $outfile_image_b --outfile_path_geo_params $outfile_geoparams --outfile_path_geo_projection $outfile_geoparams_projection";
                    print STDERR $geo_cmd."\n";
                    my $geo_cmd_status = system($geo_cmd);
                    $ortho_file = $outfile_image;

                    open(my $fh_geoparams, '<', $outfile_geoparams) or die "Could not open file '".$outfile_geoparams."' $!";
                        print STDERR "Opened ".$outfile_geoparams."\n";
                        my $geoparams = <$fh_geoparams>;
                        chomp $geoparams;
                        @geoparams_coordinates = split ',', $geoparams;
                        print STDERR Dumper [$geoparams, \@geoparams_coordinates];
                    close($fh_geoparams);

                    open(my $fh_geoparam_proj, '<', $outfile_geoparams_projection) or die "Could not open file '".$outfile_geoparams_projection."' $!";
                        print STDERR "Opened ".$outfile_geoparams_projection."\n";
                        my $geoparams_proj = <$fh_geoparam_proj>;
                        chomp $geoparams_proj;
                        $geoparams_proj =~ s/,//g;
                        my @geoparams_proj_arr = split "\"\"\"\"", $geoparams_proj;
                        $geoparams_projection = $geoparams_proj_arr[3];
                        $geoparams_projection =~ s/\s//g;
                        print STDERR Dumper [$geoparams_proj, $geoparams_projection];
                    close($fh_geoparam_proj);
                }
                else {
                    my $geo_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/GDALOpenSingleChannelImageGeoTiff.py --image_path $file --outfile_path_image $outfile_image --outfile_path_geo_params $outfile_geoparams --outfile_path_geo_projection $outfile_geoparams_projection";
                    print STDERR $geo_cmd."\n";
                    my $geo_cmd_status = system($geo_cmd);
                    $ortho_file = $outfile_image;

                    open(my $fh_geoparams, '<', $outfile_geoparams) or die "Could not open file '".$outfile_geoparams."' $!";
                        print STDERR "Opened ".$outfile_geoparams."\n";
                        my $geoparams = <$fh_geoparams>;
                        chomp $geoparams;
                        @geoparams_coordinates = split ',', $geoparams;
                        print STDERR Dumper [$geoparams, \@geoparams_coordinates];
                    close($fh_geoparams);

                    open(my $fh_geoparam_proj, '<', $outfile_geoparams_projection) or die "Could not open file '".$outfile_geoparams_projection."' $!";
                        print STDERR "Opened ".$outfile_geoparams_projection."\n";
                        my $geoparams_proj = <$fh_geoparam_proj>;
                        chomp $geoparams_proj;
                        $geoparams_proj =~ s/,//g;
                        my @geoparams_proj_arr = split "\"\"\"\"", $geoparams_proj;
                        $geoparams_projection = $geoparams_proj_arr[3];
                        $geoparams_projection =~ s/\s//g;
                        print STDERR Dumper [$geoparams_proj, $geoparams_projection];
                    close($fh_geoparam_proj);
                }
            }
            push @drone_run_band_geoparams_coordinates, \@geoparams_coordinates;

            open(my $fh_geojson, '<', $geojson_temp_filename) or die "Could not open file '$geojson_temp_filename' $!";
                print STDERR "Opened $geojson_temp_filename\n";
                $geojson_value = decode_json <$fh_geojson>;
            close($fh_geojson);

            my $trial_lookup = $field_trial_layout_lookup{$selected_trial_id};

            my %geocoord_plot_polygons;
            # foreach (@{$geojson_value->{features}}) {
            #     my $plot_number = $_->{properties}->{ID};
            #     my $coordinates = $_->{geometry}->{coordinates};
            #     my $stock_name = $trial_lookup->{$plot_number}->{plot_name};
            #     my @coords;
            #     foreach my $crd (@{$coordinates->[0]}) {
            #         push @coords, [$crd->[0], $crd->[1]];
            #     }
            #     my $last_element = pop @coords;
            #     $geocoord_plot_polygons{$stock_name} = \@coords;
            # }

            my $uploader = CXGN::UploadFile->new({
                tempfile => $ortho_file,
                subdirectory => "drone_imagery_upload",
                archive_path => $c->config->{archive_path},
                archive_filename => $upload_original_name,
                timestamp => $timestamp,
                user_id => $user_id,
                user_role => $user_role
            });
            my $archived_filename_with_path = $uploader->archive();
            my $md5 = $uploader->get_md5($archived_filename_with_path);
            if (!$archived_filename_with_path) {
                $c->stash->{rest} = { error => "Could not save file $upload_original_name in archive." };
                $c->detach();
            }
            unlink $upload_tempfile;
            print STDERR "Archived Bulk Orthophoto File: $archived_filename_with_path\n";

            my @original_image_resize_ratio = (1,1);
            if ($c->config->{drone_imagery_allow_resize}) {
                my ($check_image_width, $check_image_height) = imgsize($archived_filename_with_path);
                my $check_image_width_original = $check_image_width;
                my $check_image_height_original = $check_image_height;
                if ($check_image_width > 16384) {
                    my $cmd_resize = $c->config->{python_executable}.' '.$c->config->{rootpath}.'/DroneImageScripts/ImageProcess/Resize.py --image_path \''.$archived_filename_with_path.'\' --outfile_path \''.$archived_filename_with_path.'\' --width 16384';
                    print STDERR Dumper $cmd_resize;
                    my $status_resize = system($cmd_resize);
                    my ($check_image_width_resized, $check_image_height_resized) = imgsize($archived_filename_with_path);
                    $check_image_width = $check_image_width_resized;
                    $check_image_height = $check_image_height_resized;
                }
                if ($check_image_height > 16384) {
                    my $cmd_resize = $c->config->{python_executable}.' '.$c->config->{rootpath}.'/DroneImageScripts/ImageProcess/Resize.py --image_path \''.$archived_filename_with_path.'\' --outfile_path \''.$archived_filename_with_path.'\' --height 16384';
                    print STDERR Dumper $cmd_resize;
                    my $status_resize = system($cmd_resize);
                }
                my ($check_image_width_saved, $check_image_height_saved) = imgsize($archived_filename_with_path);
                @original_image_resize_ratio = ($check_image_width_original/$check_image_width_saved, $check_image_height_original/$check_image_height_saved);
            }

            my $project_rs = $schema->resultset("Project::Project")->create({
                name => $imaging_event_name."_".$band_short,
                description => $imaging_event_desc.". ".$band,
                projectprops => [
                    {type_id => $drone_run_band_type_cvterm_id, value => $band},
                    {type_id => $design_cvterm_id, value => 'drone_run_band'},
                    {type_id => $geoparam_coordinates_type_cvterm_id, value => $geoparams_projection},
                    {type_id => $geoparam_coordinates_cvterm_id, value => encode_json \@geoparams_coordinates},
                    {type_id => $geoparam_coordinates_plot_polygons_cvterm_id, value => encode_json \%geocoord_plot_polygons},
                    {type_id => $original_image_resize_ratio_cvterm_id, value => encode_json \@original_image_resize_ratio},
                ],
                project_relationship_subject_projects => [{type_id => $project_relationship_type_id, object_project_id => $selected_drone_run_id}]
            });
            my $selected_drone_run_band_id = $project_rs->project_id();

            $h_priv->execute($private_company_id, $private_company_is_private, $selected_drone_run_band_id);

            my $image = SGN::Image->new( $schema->storage->dbh, undef, $c );
            $image->set_sp_person_id($user_id);
            my $linking_table_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'stitched_drone_imagery', 'project_md_image')->cvterm_id();
            my $ret = $image->process_image($archived_filename_with_path, 'project', $selected_drone_run_band_id, $linking_table_type_id);

            push @drone_run_band_projects, {
                drone_run_band_project_id => $selected_drone_run_band_id,
                band => $band,
                original_image_resize_ratio => \@original_image_resize_ratio
            };
            push @drone_run_band_project_ids, $selected_drone_run_band_id;
        }

        push @drone_run_projects, {
            private_company_id => $private_company_id,
            private_company_is_private => $private_company_is_private,
            drone_run_project_id => $selected_drone_run_id,
            drone_run_band_projects => \@drone_run_band_projects,
            drone_run_band_project_ids => \@drone_run_band_project_ids,
            geojson_temp_filename => $geojson_temp_filename,
            geojson_value => $geojson_value,
            time_cvterm_id => $day_cvterm_id,
            field_trial_id => $selected_trial_id,
            coordinate_system => $coordinate_system,
            drone_run_band_geoparams_coordinates => \@drone_run_band_geoparams_coordinates,
            rotation_angle => $rotation_angle
        };

        $drone_run_project_info{$selected_drone_run_id} = {
            name => $project_rs->name()
        };
    }

    my $vegetative_indices = ['VARI', 'TGI', 'NDRE', 'NDVI', 'CCC'];
    my $phenotype_methods = ['zonal'];
    my $standard_process_type = 'minimal';

    my $rad_conversion = 0.0174533;
    foreach (@drone_run_projects) {
        my $private_company_id = $_->{private_company_id};
        my $private_company_is_private = $_->{private_company_is_private};
        my $drone_run_project_id_in = $_->{drone_run_project_id};
        my $time_cvterm_id = $_->{time_cvterm_id};
        my $apply_drone_run_band_project_ids = $_->{drone_run_band_project_ids};
        my $geojson_filename = $_->{geojson_temp_filename};
        my $geojson_value = $_->{geojson_value};
        my $field_trial_id = $_->{field_trial_id};
        my $coordinate_system = $_->{coordinate_system};
        my $drone_run_band_geoparams_coordinates = $_->{drone_run_band_geoparams_coordinates};
        my $rotate_value = $_->{rotation_angle}*-1;
        my $apply_drone_run_band_projects = $_->{drone_run_band_projects};
        # my $rotate_value = 0;

        my $drone_run_process_in_progress = $schema->resultset('Project::Projectprop')->update_or_create({
            type_id=>$process_indicator_cvterm_id,
            project_id=>$drone_run_project_id_in,
            rank=>0,
            value=>1
        },
        {
            key=>'projectprop_c1'
        });

        my $drone_run_process_completed = $schema->resultset('Project::Projectprop')->update_or_create({
            type_id=>$processed_cvterm_id,
            project_id=>$drone_run_project_id_in,
            rank=>0,
            value=>0
        },
        {
            key=>'projectprop_c1'
        });

        my $drone_run_process_minimal_vi_completed = $schema->resultset('Project::Projectprop')->update_or_create({
            type_id=>$processed_minimal_vi_cvterm_id,
            project_id=>$drone_run_project_id_in,
            rank=>0,
            value=>0
        },
        {
            key=>'projectprop_c1'
        });

        my %vegetative_indices_hash;
        foreach (@$vegetative_indices) {
            $vegetative_indices_hash{$_}++;
        }

        my $trial_lookup = $field_trial_layout_lookup{$field_trial_id};

        my %selected_drone_run_band_types;
        my $q2 = "SELECT project_md_image.image_id, drone_run_band_type.value, drone_run_band.project_id
            FROM project AS drone_run_band
            JOIN projectprop AS drone_run_band_type ON(drone_run_band_type.project_id = drone_run_band.project_id AND drone_run_band_type.type_id = $drone_run_band_type_cvterm_id)
            JOIN phenome.project_md_image AS project_md_image ON(project_md_image.project_id = drone_run_band.project_id)
            JOIN metadata.md_image ON(project_md_image.image_id = metadata.md_image.image_id)
            WHERE project_md_image.type_id = $project_image_type_id
            AND drone_run_band.project_id = ?
            AND metadata.md_image.obsolete = 'f';";

        my $h2 = $schema->storage->dbh()->prepare($q2);

        my $term_map = CXGN::DroneImagery::ImageTypes::get_base_imagery_observation_unit_plot_polygon_term_map();

        my %drone_run_band_info;
        my $drone_run_band_counter = 0;
        foreach my $apply_drone_run_band_project_id (@$apply_drone_run_band_project_ids) {
            my $apply_drone_run_band_project = $apply_drone_run_band_projects->[$drone_run_band_counter];
            my $apply_original_image_resize_ratio = $apply_drone_run_band_project->{original_image_resize_ratio};
            my $apply_original_image_resize_ratio_x = $apply_original_image_resize_ratio->[0];
            my $apply_original_image_resize_ratio_y = $apply_original_image_resize_ratio->[1];
            print STDERR Dumper $apply_original_image_resize_ratio;

            my $h2 = $schema->storage->dbh()->prepare($q2);
            $h2->execute($apply_drone_run_band_project_id);
            my ($image_id, $drone_run_band_type, $drone_run_band_project_id) = $h2->fetchrow_array();
            $selected_drone_run_band_types{$drone_run_band_type} = $drone_run_band_project_id;

            my $apply_image_width_ratio = 1;
            my $apply_image_height_ratio = 1;

            my $dir = $c->tempfiles_subdir('/drone_imagery_rotate');
            my $archive_rotate_temp_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'drone_imagery_rotate/imageXXXX');
            $archive_rotate_temp_image .= '.png';

            my $rotate_return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_image_rotate($c, $schema, $metadata_schema, $drone_run_band_project_id, [], $image_id, $rotate_value, 0, $user_id, $user_name, $user_role, $archive_rotate_temp_image, 0, 0, 1, 1, $private_company_id, $private_company_is_private);
            my $rotated_image_id = $rotate_return->{rotated_image_id};

            my $image = SGN::Image->new( $schema->storage->dbh, $rotated_image_id, $c );
            my $image_fullpath = $image->get_filename('original_converted', 'full');

            my @size = imgsize($image_fullpath);
            my $width = $size[0];
            my $length = $size[1];
            my $x_center = $width/2;
            my $y_center = $length/2;

            my $cropping_x_offset = 0;
            my $cropping_y_offset = 0;
            my $cropping_value = encode_json [[{x=>$cropping_x_offset, y=>$cropping_y_offset}, {x=>$width, y=>$cropping_y_offset}, {x=>$width, y=>$length}, {x=>$cropping_x_offset, y=>$length}]];

            my $plot_polygons_value;
            my %geocoord_plot_polygons;
            foreach (@{$geojson_value->{features}}) {
                my $plot_number = $_->{properties}->{ID};
                my $coordinates = $_->{geometry}->{coordinates};
                my $stock_name = $trial_lookup->{$plot_number}->{plot_name};
                my @coords;
                my @geojson_coords_original;
                foreach my $crd (@{$coordinates->[0]}) {
                    if ($coordinate_system eq 'Pixels') {
                        push @coords, {
                            x => $crd->[0],
                            y => $crd->[1],
                        };
                    }
                    else {
                        my $geocoords = $drone_run_band_geoparams_coordinates->[$drone_run_band_counter];

                        my $xOrigin = $geocoords->[0];
                        my $yOrigin = $geocoords->[3];
                        my $pixelWidth = $geocoords->[1];
                        my $pixelHeight = -1*$geocoords->[5];
                        my $x_pos = ($crd->[0] - $xOrigin) / $pixelWidth;
                        my $y_pos = ($yOrigin - $crd->[1] ) / $pixelHeight;

                        my $x_pos_rotated = ($x_pos - $x_center)*cos($rad_conversion*$rotate_value*-1) - ($y_pos - $y_center)*sin($rad_conversion*$rotate_value*-1) + $x_center;
                        my $y_pos_rotated = ($y_pos - $y_center)*cos($rad_conversion*$rotate_value*-1) + ($x_pos - $x_center)*sin($rad_conversion*$rotate_value*-1) + $y_center;

                        my $poly = {
                            x => round($x_pos_rotated),
                            y => round($y_pos_rotated),
                        };

                        push @coords, $poly;

                        my $x_pos_geo = $poly->{x} + $cropping_x_offset;
                        my $y_pos_geo = $poly->{y} + $cropping_y_offset;

                        my $x_pos_rotated_geo = round( ($x_pos_geo - $x_center)*cos($rad_conversion*$rotate_value*-1) - ($y_pos_geo - $y_center)*sin($rad_conversion*$rotate_value*-1) + $x_center );
                        my $y_pos_rotated_geo = round( ($y_pos_geo - $y_center)*cos($rad_conversion*$rotate_value*-1) + ($x_pos_geo - $x_center)*sin($rad_conversion*$rotate_value*-1) + $y_center );

                        my $x_coord = ($x_pos_rotated_geo * $pixelWidth) + $xOrigin;
                        my $y_coord = $yOrigin - ($y_pos_rotated_geo * $pixelHeight);

                        push @geojson_coords_original, [$x_coord, $y_coord];
                    }
                }
                my $last_point = pop @coords;
                my $last_point_geo = pop @geojson_coords_original;
                $plot_polygons_value->{$stock_name} = \@coords;
                $geocoord_plot_polygons{$stock_name} = \@geojson_coords_original;
            }
            $plot_polygons_value = encode_json $plot_polygons_value;

            my $drone_run_band_geoparam_coordinates_polygons_rs = $schema->resultset('Project::Projectprop')->update_or_create({
                type_id=>$geoparam_coordinates_plot_polygons_cvterm_id,
                project_id=>$drone_run_band_project_id,
                rank=>0,
                value=> encode_json \%geocoord_plot_polygons
            },
            {
                key=>'projectprop_c1'
            });

            $dir = $c->tempfiles_subdir('/drone_imagery_cropped_image');
            my $archive_temp_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'drone_imagery_cropped_image/imageXXXX');
            $archive_temp_image .= '.png';

            my $cropping_return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_image_cropping($c, $schema, $drone_run_band_project_id, [], $rotated_image_id, $cropping_value, $user_id, $user_name, $user_role, $archive_temp_image, $apply_image_width_ratio, $apply_image_height_ratio, $private_company_id, $private_company_is_private);
            my $cropped_image_id = $cropping_return->{cropped_image_id};

            $dir = $c->tempfiles_subdir('/drone_imagery_denoise');
            my $archive_denoise_temp_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'drone_imagery_denoise/imageXXXX');
            $archive_denoise_temp_image .= '.png';

            my $denoise_return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_image_denoise($c, $schema, $metadata_schema, $cropped_image_id, $drone_run_band_project_id, [], $user_id, $user_name, $user_role, $archive_denoise_temp_image, $private_company_id, $private_company_is_private);
            my $denoised_image_id = $denoise_return->{denoised_image_id};

            $drone_run_band_info{$drone_run_band_project_id} = {
                denoised_image_id => $denoised_image_id,
                rotate_value => $rotate_value,
                cropping_value => $cropping_value,
                drone_run_band_type => $drone_run_band_type,
                drone_run_project_id => $drone_run_project_id_in,
                drone_run_project_name => $drone_run_project_info{$drone_run_project_id_in}->{name},
                plot_polygons_value => $plot_polygons_value,
                check_resize => 1,
                keep_original_size_rotate => 1,
                threshold_values => "Lower Threshold Percentage:25. Upper Threshold Percentage:25"
            };

            my @denoised_plot_polygon_type = @{$term_map->{$drone_run_band_type}->{observation_unit_plot_polygon_types}->{base}};
            my @denoised_background_threshold_removed_imagery_types = @{$term_map->{$drone_run_band_type}->{imagery_types}->{threshold_background}};
            my @denoised_background_threshold_removed_plot_polygon_types = @{$term_map->{$drone_run_band_type}->{observation_unit_plot_polygon_types}->{threshold_background}};

            my $polygon_type = '';
            if ($rotate_value != 0) {
                $polygon_type = 'rectangular_square';
            } else {
                $polygon_type = 'rectangular_polygon';
            }

            foreach (@denoised_plot_polygon_type) {
                my $plot_polygon_original_denoised_return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_plot_polygon_assign($c, $schema, $metadata_schema, $denoised_image_id, $drone_run_band_project_id, [], $plot_polygons_value, $_, $user_id, $user_name, $user_role, 0, 0, $apply_image_width_ratio, $apply_image_height_ratio, $polygon_type, 0, 0, $private_company_id, $private_company_is_private);
            }

            for my $iterator (0..(scalar(@denoised_background_threshold_removed_imagery_types)-1)) {
                $dir = $c->tempfiles_subdir('/drone_imagery_remove_background');
                my $archive_remove_background_temp_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'drone_imagery_remove_background/imageXXXX');
                $archive_remove_background_temp_image .= '.png';

                my $background_removed_threshold_return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_image_background_remove_threshold_percentage($c, $schema, $denoised_image_id, $drone_run_band_project_id, [], $denoised_background_threshold_removed_imagery_types[$iterator], '25', '25', $user_id, $user_name, $user_role, $archive_remove_background_temp_image, $private_company_id, $private_company_is_private);

                my $plot_polygon_return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_plot_polygon_assign($c, $schema, $metadata_schema, $background_removed_threshold_return->{removed_background_image_id}, $drone_run_band_project_id, [], $plot_polygons_value, $denoised_background_threshold_removed_plot_polygon_types[$iterator], $user_id, $user_name, $user_role, 0, 0, $apply_image_width_ratio, $apply_image_height_ratio, $polygon_type, 0, 0, $private_company_id, $private_company_is_private);
            }

            $drone_run_band_counter++;
        }

        print STDERR Dumper \%selected_drone_run_band_types;
        print STDERR Dumper \%vegetative_indices_hash;

        SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_minimal_vi_standard_process($c, $schema, $metadata_schema, \%vegetative_indices_hash, \%selected_drone_run_band_types, [], {},  \%drone_run_band_info, $user_id, $user_name, $user_role, 'rectangular_polygon', $private_company_id, $private_company_is_private);

        $drone_run_process_in_progress = $schema->resultset('Project::Projectprop')->update_or_create({
            type_id=>$process_indicator_cvterm_id,
            project_id=>$drone_run_project_id_in,
            rank=>0,
            value=>0
        },
        {
            key=>'projectprop_c1'
        });

        $drone_run_process_completed = $schema->resultset('Project::Projectprop')->update_or_create({
            type_id=>$processed_cvterm_id,
            project_id=>$drone_run_project_id_in,
            rank=>0,
            value=>1
        },
        {
            key=>'projectprop_c1'
        });

        $drone_run_process_minimal_vi_completed = $schema->resultset('Project::Projectprop')->update_or_create({
            type_id=>$processed_minimal_vi_cvterm_id,
            project_id=>$drone_run_project_id_in,
            rank=>0,
            value=>1
        },
        {
            key=>'projectprop_c1'
        });

        my $plot_margin_top_bottom = 5;
        my $plot_margin_left_right = 5;

        my $return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_phenotype_automated($c, $schema, $metadata_schema, $phenome_schema, $drone_run_project_id_in, $time_cvterm_id, $phenotype_methods, $standard_process_type, 1, undef, $plot_margin_top_bottom, $plot_margin_left_right, $user_id, $user_name, $user_role, $private_company_id, $private_company_is_private);
    }

    $c->stash->{message} = "Successfully uploaded! Go to <a href='/breeders/drone_imagery'>Drone Imagery</a>";
    $c->stash->{template} = 'generic_message.mas';
    return;
}

sub upload_drone_imagery_geocoordinate_param : Path("/drone_imagery/upload_drone_imagery_geocoordinate_param") :Args(0) {
    my $self = shift;
    my $c = shift;
    $c->response->headers->header( "Access-Control-Allow-Origin" => '*' );
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my $dbh = $c->dbc->dbh;
    my ($user_id, $user_name, $user_role) = _check_user_login_drone_imagery_upload($c, 'submitter', 0, 0);
    # print STDERR Dumper $c->req->params();

    my $overwrite_geojson = $c->req->param('upload_drone_imagery_geocoordinate_param_overwrite_geojson') eq 'yes' ? 1 : 0;
    my $image_type = $c->req->param('upload_drone_imagery_geocoordinate_param_type');
    my $field_trial_id = $c->req->param('upload_drone_imagery_geocoordinate_param_field_trial_id');
    my $drone_run_id = $c->req->param('upload_drone_imagery_geocoordinate_param_drone_run_id');
    my $upload_file = $c->req->upload('upload_drone_imagery_geocoordinate_param_geotiff');

    my $dir = $c->tempfiles_subdir('/upload_drone_imagery_geocoordinate_param');

    my $upload_original_name = $upload_file->filename();
    my $upload_tempfile = $upload_file->tempname;
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();

    my $project_relationship_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_on_drone_run', 'project_relationship')->cvterm_id();
    my $drone_run_band_plot_polygons_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_plot_polygons', 'project_property')->cvterm_id();
    my $rotate_angle_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_rotate_angle', 'project_property')->cvterm_id();
    my $cropping_polygon_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_cropped_polygon', 'project_property')->cvterm_id();
    my $geoparam_coordinates_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_geoparam_coordinates_type', 'project_property')->cvterm_id();
    my $geoparam_coordinates_plot_polygons_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_geoparam_coordinates_plot_polygons', 'project_property')->cvterm_id();
    my $geoparam_coordinates_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_geoparam_coordinates', 'project_property')->cvterm_id();
    my $stock_geo_json_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot_geo_json', 'stock_property');
    my $field_trial_project_relationship_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_on_field_trial', 'project_relationship')->cvterm_id();
    my $rotated_stitched_drone_imagery_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'rotated_stitched_drone_imagery', 'project_md_image')->cvterm_id();
    my $cropped_stitched_drone_imagery_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'cropped_stitched_drone_imagery', 'project_md_image')->cvterm_id();
    my $denoised_stitched_drone_imagery_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'denoised_stitched_drone_imagery', 'project_md_image')->cvterm_id();
    my $original_stitched_drone_imagery_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'stitched_drone_imagery', 'project_md_image')->cvterm_id();
    my $original_image_resize_ratio_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_original_image_resize_ratio', 'project_property')->cvterm_id();
    my $rotated_image_resize_ratio_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_rotated_image_resize_ratio', 'project_property')->cvterm_id();

    my @geoparams_coordinates;
    my $geoparams_projection;
    my $ortho_file;
    my $outfile_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/imageXXXX').".png";
    my $outfile_geoparams = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/fileXXXX').".csv";
    my $outfile_geoparams_projection = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/fileXXXX').".csv";

    if ($image_type eq 'rgb') {
        my $outfile_image_r = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/imageXXXX').".png";
        my $outfile_image_g = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/imageXXXX').".png";
        my $outfile_image_b = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'upload_drone_imagery_geocoordinate_param/imageXXXX').".png";

        my $geo_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/GDALOpenImageRGBGeoTiff.py --image_path $upload_tempfile --outfile_path_image $outfile_image --outfile_path_image_1 $outfile_image_r --outfile_path_image_2 $outfile_image_g --outfile_path_image_3 $outfile_image_b --outfile_path_geo_params $outfile_geoparams --outfile_path_geo_projection $outfile_geoparams_projection";
        print STDERR $geo_cmd."\n";
        my $geo_cmd_status = system($geo_cmd);
        $ortho_file = $outfile_image;

        open(my $fh_geoparams, '<', $outfile_geoparams) or die "Could not open file '".$outfile_geoparams."' $!";
            print STDERR "Opened ".$outfile_geoparams."\n";
            my $geoparams = <$fh_geoparams>;
            chomp $geoparams;
            @geoparams_coordinates = split ',', $geoparams;
            print STDERR Dumper [$geoparams, \@geoparams_coordinates];
        close($fh_geoparams);

        open(my $fh_geoparam_proj, '<', $outfile_geoparams_projection) or die "Could not open file '".$outfile_geoparams_projection."' $!";
            print STDERR "Opened ".$outfile_geoparams_projection."\n";
            my $geoparams_proj = <$fh_geoparam_proj>;
            chomp $geoparams_proj;
            $geoparams_proj =~ s/,//g;
            my @geoparams_proj_arr = split "\"\"\"\"", $geoparams_proj;
            $geoparams_projection = $geoparams_proj_arr[3];
            $geoparams_projection =~ s/\s//g;
            print STDERR Dumper [$geoparams_proj, $geoparams_projection];
        close($fh_geoparam_proj);
    }
    else {
        my $geo_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/GDALOpenSingleChannelImageGeoTiff.py --image_path $upload_tempfile --outfile_path_image $outfile_image --outfile_path_geo_params $outfile_geoparams --outfile_path_geo_projection $outfile_geoparams_projection";
        print STDERR $geo_cmd."\n";
        my $geo_cmd_status = system($geo_cmd);
        $ortho_file = $outfile_image;

        open(my $fh_geoparams, '<', $outfile_geoparams) or die "Could not open file '".$outfile_geoparams."' $!";
            print STDERR "Opened ".$outfile_geoparams."\n";
            my $geoparams = <$fh_geoparams>;
            chomp $geoparams;
            @geoparams_coordinates = split ',', $geoparams;
            print STDERR Dumper [$geoparams, \@geoparams_coordinates];
        close($fh_geoparams);

        open(my $fh_geoparam_proj, '<', $outfile_geoparams_projection) or die "Could not open file '".$outfile_geoparams_projection."' $!";
            print STDERR "Opened ".$outfile_geoparams_projection."\n";
            my $geoparams_proj = <$fh_geoparam_proj>;
            chomp $geoparams_proj;
            $geoparams_proj =~ s/,//g;
            my @geoparams_proj_arr = split "\"\"\"\"", $geoparams_proj;
            $geoparams_projection = $geoparams_proj_arr[3];
            $geoparams_projection =~ s/\s//g;
            print STDERR Dumper [$geoparams_proj, $geoparams_projection];
        close($fh_geoparam_proj);
    }

    my @input_image_size = imgsize($outfile_image);
    my $input_image_width = $input_image_size[0];
    my $input_image_length = $input_image_size[1];

    my $rad_conversion = 0.0174533;
    my $xOrigin = $geoparams_coordinates[0];
    my $yOrigin = $geoparams_coordinates[3];
    my $pixelWidth = $geoparams_coordinates[1];
    my $pixelHeight = -1*$geoparams_coordinates[5];

    my $drone_run_band_q = "SELECT drone_run_band.project_id, field_trial.project_id, plot_polygons.value, rotate_value.value, cropped_polygon.value, rotated_image.image_id, cropped_image.image_id, denoised_image.image_id, original_image.image_id, original_image_resize.value, rotated_image_resize.value
        FROM project AS drone_run
        JOIN project_relationship ON (drone_run.project_id=project_relationship.object_project_id AND project_relationship.type_id=$project_relationship_type_id)
        JOIN project AS drone_run_band ON(project_relationship.subject_project_id=drone_run_band.project_id)
        JOIN projectprop AS plot_polygons ON(drone_run_band.project_id=plot_polygons.project_id AND plot_polygons.type_id=$drone_run_band_plot_polygons_type_id)
        JOIN projectprop AS rotate_value ON(drone_run_band.project_id=rotate_value.project_id AND rotate_value.type_id=$rotate_angle_type_id)
        JOIN projectprop AS cropped_polygon ON(drone_run_band.project_id=cropped_polygon.project_id AND cropped_polygon.type_id=$cropping_polygon_type_id)
        LEFT JOIN projectprop AS original_image_resize ON(drone_run_band.project_id=original_image_resize.project_id AND original_image_resize.type_id=$original_image_resize_ratio_cvterm_id)
        LEFT JOIN projectprop AS rotated_image_resize ON(drone_run_band.project_id=rotated_image_resize.project_id AND rotated_image_resize.type_id=$rotated_image_resize_ratio_cvterm_id)
        JOIN project_relationship AS field_trial_rel ON (drone_run.project_id=field_trial_rel.subject_project_id AND field_trial_rel.type_id=$field_trial_project_relationship_type_id)
        JOIN project AS field_trial ON (field_trial_rel.object_project_id=field_trial.project_id)
        JOIN phenome.project_md_image AS rotated_image ON (drone_run_band.project_id=rotated_image.project_id AND rotated_image.type_id=$rotated_stitched_drone_imagery_type_id)
        JOIN phenome.project_md_image AS cropped_image ON (drone_run_band.project_id=cropped_image.project_id AND cropped_image.type_id=$cropped_stitched_drone_imagery_type_id)
        JOIN phenome.project_md_image AS denoised_image ON (drone_run_band.project_id=denoised_image.project_id AND denoised_image.type_id=$denoised_stitched_drone_imagery_type_id)
        JOIN phenome.project_md_image AS original_image ON (drone_run_band.project_id=original_image.project_id AND original_image.type_id=$original_stitched_drone_imagery_type_id)
        JOIN metadata.md_image AS rotated_md_image ON (rotated_md_image.image_id=rotated_image.image_id)
        JOIN metadata.md_image AS cropped_md_image ON (cropped_md_image.image_id=cropped_image.image_id)
        JOIN metadata.md_image AS denoised_md_image ON (denoised_md_image.image_id=denoised_image.image_id)
        JOIN metadata.md_image AS original_md_image ON (original_md_image.image_id=original_image.image_id)
        WHERE drone_run.project_id=? AND rotated_md_image.obsolete='f' AND cropped_md_image.obsolete='f' AND denoised_md_image.obsolete='f' AND original_md_image.obsolete='f';";
    my $drone_run_band_h = $schema->storage->dbh()->prepare($drone_run_band_q);
    $drone_run_band_h->execute($drone_run_id);

    my $stock_q = "SELECT stock_id FROM stock WHERE uniquename = ?;";
    my $stock_h = $schema->storage->dbh()->prepare($stock_q);

    my %seen_field_trial_ids;
    my @drone_run_band_results;
    while (my ($drone_run_band_project_id, $field_trial_id, $plot_polygon_json, $rotate_value, $cropped_polygon_json, $rotated_image_id, $cropped_image_id, $denoised_image_id, $original_image_id, $original_image_resize_json, $rotated_image_resize_json) = $drone_run_band_h->fetchrow_array()) {
        my $original_image = SGN::Image->new( $schema->storage->dbh, $original_image_id, $c );
        my $original_image_fullpath = $original_image->get_filename('original_converted', 'full');

        my @original_image_size = imgsize($original_image_fullpath);
        my $original_image_width = $original_image_size[0];
        my $original_image_length = $original_image_size[1];

        if ($original_image_width != $input_image_width) {
            $c->stash->{message} = "The provided GeoTIFF width ($input_image_width) does not match the previously uploaded orthophotos width ($original_image_width) for $original_image_id.";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        if ($original_image_length != $input_image_length) {
            $c->stash->{message} = "The provided GeoTIFF length ($input_image_length) does not match the previously uploaded orthophotos length ($original_image_length) for $original_image_id.";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }

        push @drone_run_band_results, [$drone_run_band_project_id, $field_trial_id, $plot_polygon_json, $rotate_value, $cropped_polygon_json, $rotated_image_id, $cropped_image_id, $denoised_image_id, $original_image_id, $original_image_width, $original_image_length, $original_image_resize_json, $rotated_image_resize_json];
    }

    print STDERR Dumper \@drone_run_band_results;
    foreach my $d (@drone_run_band_results) {
        my ($drone_run_band_project_id, $field_trial_id, $plot_polygon_json, $rotate_value, $cropped_polygon_json, $rotated_image_id, $cropped_image_id, $denoised_image_id, $original_image_id, $original_image_width, $original_image_length, $original_image_resize_json, $rotated_image_resize_json) = @$d;

        my $original_image_resize = $original_image_resize_json ? decode_json $original_image_resize_json : [1,1];
        my $rotated_image_resize = $rotated_image_resize_json ? decode_json $rotated_image_resize_json : [1,1];

        my $original_image_resize_x = $original_image_resize->[0];
        my $original_image_resize_y = $original_image_resize->[1];
        my $rotated_image_resize_x = $rotated_image_resize->[0];
        my $rotated_image_resize_y = $rotated_image_resize->[1];

        my $rotated_image = SGN::Image->new( $schema->storage->dbh, $rotated_image_id, $c );
        my $rotated_image_fullpath = $rotated_image->get_filename('original_converted', 'full');

        my @rotated_image_size = imgsize($rotated_image_fullpath);
        my $rotated_image_width = $rotated_image_size[0];
        my $rotated_image_length = $rotated_image_size[1];

        my $x_center = $rotated_image_width/2;
        my $y_center = $rotated_image_length/2;

        my $plot_polygon = decode_json $plot_polygon_json;
        my $cropped_polygon = decode_json $cropped_polygon_json;
        # print STDERR Dumper $plot_polygon;
        # print STDERR Dumper $cropped_polygon;
        my $cropping_x_offset = $cropped_polygon->[0]->[0]->{x};
        my $cropping_y_offset = $cropped_polygon->[0]->[0]->{y};

        my %geocoord_plot_polygons;
        while (my($stock_name, $polygon_arr) = each %$plot_polygon) {

            $stock_h->execute($stock_name);
            my ($stock_id) = $stock_h->fetchrow_array();

            my $plot = $schema->resultset("Stock::Stock")->find({stock_id => $stock_id});

            my @geojson_coords_original;
            foreach my $poly (@$polygon_arr) {
                my $x_pos = $poly->{x} + $cropping_x_offset;
                my $y_pos = $poly->{y} + $cropping_y_offset;

                my $x_pos_rotated = round( ($x_pos - $x_center)*cos($rad_conversion*$rotate_value*-1) - ($y_pos - $y_center)*sin($rad_conversion*$rotate_value*-1) + $x_center );
                my $y_pos_rotated = round( ($y_pos - $y_center)*cos($rad_conversion*$rotate_value*-1) + ($x_pos - $x_center)*sin($rad_conversion*$rotate_value*-1) + $y_center );

                $x_pos_rotated = $x_pos_rotated*$rotated_image_resize_x;
                $y_pos_rotated = $y_pos_rotated*$rotated_image_resize_y;

                $x_pos_rotated = $x_pos_rotated*$original_image_resize_x;
                $y_pos_rotated = $y_pos_rotated*$original_image_resize_y;

                my $x_coord = ($x_pos_rotated * $pixelWidth) + $xOrigin;
                my $y_coord = $yOrigin - ($y_pos_rotated * $pixelHeight);

                push @geojson_coords_original, [$x_coord, $y_coord];
            }
            $geocoord_plot_polygons{$stock_name} = \@geojson_coords_original;
            # print STDERR Dumper \@geojson_coords_original;

            my $first_geojson = $geojson_coords_original[0];
            my @geojson_coords = ($first_geojson, @geojson_coords_original);

            my $geo_json = {
                "type"=> "Feature",
                "geometry"=> {
                    "type"=> "Polygon",
                    "coordinates"=> [
                        \@geojson_coords
                    ]
                },
                "properties"=> {
                    "format"=> $geoparams_projection,
                }
            };
            my $geno_json_string = encode_json $geo_json;
            print STDERR $geno_json_string."\n";

            if ($overwrite_geojson) {
                my $previous_plot_gps_rs = $schema->resultset("Stock::Stockprop")->search({stock_id=>$plot->stock_id, type_id=>$stock_geo_json_cvterm->cvterm_id});
                $previous_plot_gps_rs->delete_all();
                $plot->create_stockprops({$stock_geo_json_cvterm->name() => $geno_json_string});

                $seen_field_trial_ids{$field_trial_id}++;
            }
        }

        my $drone_run_band_coordinate_system_type_rs = $schema->resultset('Project::Projectprop')->update_or_create({
            type_id=>$geoparam_coordinates_type_cvterm_id,
            project_id=>$drone_run_band_project_id,
            rank=>0,
            value=> $geoparams_projection
        },
        {
            key=>'projectprop_c1'
        });

        my $drone_run_band_geoparam_coordinates_rs = $schema->resultset('Project::Projectprop')->update_or_create({
            type_id=>$geoparam_coordinates_cvterm_id,
            project_id=>$drone_run_band_project_id,
            rank=>0,
            value=> encode_json \@geoparams_coordinates
        },
        {
            key=>'projectprop_c1'
        });

        my $drone_run_band_geoparam_coordinates_polygons_rs = $schema->resultset('Project::Projectprop')->update_or_create({
            type_id=>$geoparam_coordinates_plot_polygons_cvterm_id,
            project_id=>$drone_run_band_project_id,
            rank=>0,
            value=> encode_json \%geocoord_plot_polygons
        },
        {
            key=>'projectprop_c1'
        });
    }

    foreach my $trial_id (keys %seen_field_trial_ids) {
        my $layout = CXGN::Trial::TrialLayout->new({
            schema => $schema,
            trial_id => $trial_id,
            experiment_type => 'field_layout'
        });
        $layout->generate_and_cache_layout();
    }

    $c->stash->{message} = "Successfully uploaded! Go to <a href='/breeders/drone_imagery'>Drone Imagery</a>";
    $c->stash->{template} = 'generic_message.mas';
    return;
}

sub upload_drone_imagery_standard_process_previous_geotiff : Path("/drone_imagery/standard_process_previous_geotiff") :Args(0) {
    my $self = shift;
    my $c = shift;
    $c->response->headers->header( "Access-Control-Allow-Origin" => '*' );
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my $dbh = $c->dbc->dbh;
    my ($user_id, $user_name, $user_role) = _check_user_login_drone_imagery_upload($c, 'submitter', 0, 0);
    # print STDERR Dumper $c->req->params();

    my $upload_file = $c->req->upload('manage_drone_imagery_standard_process_geotiff_params_geotiff');
    my $image_type = $c->req->param('manage_drone_imagery_standard_process_geotiff_params_type');

    my $drone_run_project_id_in = $c->req->param('manage_drone_imagery_standard_process_geotiff_params_drone_run_project_id');
    my $rotate_value = $c->req->param('manage_drone_imagery_standard_process_geotiff_params_angle') || 0;
    my $geoparam_drone_run_project_id_input = $c->req->param('manage_drone_imagery_standard_process_geotiff_params_previous_drone_run_project_id');
    my $time_cvterm_id = $c->req->param('manage_drone_imagery_standard_process_geotiff_params_time_cvterm_id');

    my $dir = $c->tempfiles_subdir('/standard_process_drone_imagery_geocoordinate_param');

    my $imaging_vehicle_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'imaging_event_vehicle', 'stock_type')->cvterm_id();
    my $imaging_vehicle_properties_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'imaging_event_vehicle_json', 'stock_property')->cvterm_id();
    my $drone_run_experiment_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_experiment', 'experiment_type')->cvterm_id();
    my $design_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'design', 'project_property')->cvterm_id();
    my $geoparam_coordinates_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_geoparam_coordinates_type', 'project_property')->cvterm_id();
    my $geoparam_coordinates_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_geoparam_coordinates', 'project_property')->cvterm_id();
    my $geoparam_coordinates_plot_polygons_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_geoparam_coordinates_plot_polygons', 'project_property')->cvterm_id();
    my $drone_run_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_project_type', 'project_property')->cvterm_id();
    my $drone_run_is_raw_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_is_raw_images', 'project_property')->cvterm_id();
    my $drone_run_camera_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_camera_type', 'project_property')->cvterm_id();
    my $project_start_date_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'project_start_date', 'project_property')->cvterm_id();
    my $drone_run_base_date_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_base_date', 'project_property')->cvterm_id();
    my $drone_run_rig_desc_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_camera_rig_description', 'project_property')->cvterm_id();
    my $drone_run_related_cvterms_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_related_time_cvterms_json', 'project_property')->cvterm_id();
    my $drone_run_band_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_project_type', 'project_property')->cvterm_id();
    my $process_indicator_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_standard_process_in_progress', 'project_property')->cvterm_id();
    my $processed_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_standard_process_completed', 'project_property')->cvterm_id();
    my $processed_minimal_vi_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_standard_process_vi_completed', 'project_property')->cvterm_id();
    my $rotate_angle_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_rotate_angle', 'project_property')->cvterm_id();
    my $cropping_polygon_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_cropped_polygon', 'project_property')->cvterm_id();
    my $plot_polygon_template_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_plot_polygons', 'project_property')->cvterm_id();
    my $project_image_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'stitched_drone_imagery', 'project_md_image')->cvterm_id();
    my $rotated_stitched_drone_imagery_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'rotated_stitched_drone_imagery', 'project_md_image')->cvterm_id();
    my $cropped_stitched_drone_imagery_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'cropped_stitched_drone_imagery', 'project_md_image')->cvterm_id();
    my $denoised_stitched_drone_imagery_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'denoised_stitched_drone_imagery', 'project_md_image')->cvterm_id();
    my $drone_run_drone_run_band_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_on_drone_run', 'project_relationship')->cvterm_id();
    my $field_trial_project_relationship_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_on_field_trial', 'project_relationship')->cvterm_id();
    my $drone_run_band_rotate_keep_original_size_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_rotate_keep_original_size', 'project_property')->cvterm_id();
    my $stock_geo_json_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot_geo_json', 'stock_property');
    my $original_image_resize_ratio_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_original_image_resize_ratio', 'project_property')->cvterm_id();
    my $rotated_image_resize_ratio_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_rotated_image_resize_ratio', 'project_property')->cvterm_id();
    my $calendar_funcs = CXGN::Calendar->new({});

    my %drone_run_project_info;
    my @apply_drone_run_band_project_ids;
    my $drone_run_band_q = "SELECT drone_run.project_id, drone_run.name, drone_run_band.project_id, field_trial.project_id, original_image.image_id, original_image_resize.value
        FROM project AS drone_run
        JOIN project_relationship ON (drone_run.project_id=project_relationship.object_project_id AND project_relationship.type_id=$drone_run_drone_run_band_type_id)
        JOIN project AS drone_run_band ON(project_relationship.subject_project_id=drone_run_band.project_id)
        JOIN project_relationship AS field_trial_rel ON (drone_run.project_id=field_trial_rel.subject_project_id AND field_trial_rel.type_id=$field_trial_project_relationship_type_id)
        JOIN project AS field_trial ON (field_trial_rel.object_project_id=field_trial.project_id)
        JOIN phenome.project_md_image AS original_image ON (drone_run_band.project_id=original_image.project_id AND original_image.type_id=$project_image_type_id)
        LEFT JOIN projectprop AS original_image_resize ON(drone_run_band.project_id=original_image_resize.project_id AND original_image_resize.type_id=$original_image_resize_ratio_cvterm_id)
        WHERE drone_run.project_id=?;";
    my $drone_run_band_h = $schema->storage->dbh()->prepare($drone_run_band_q);
    $drone_run_band_h->execute($drone_run_project_id_in);

    while (my ($drone_run_project_id, $drone_run_name, $drone_run_band_project_id, $field_trial_id, $original_image_id, $original_image_resize_json) = $drone_run_band_h->fetchrow_array()) {
        my $original_image_resize = $original_image_resize_json ? decode_json $original_image_resize_json : [1,1];
        $drone_run_project_info{$drone_run_band_project_id}->{original_image_resize} = $original_image_resize;
        $drone_run_project_info{$drone_run_project_id}->{name} = $drone_run_name;
        push @apply_drone_run_band_project_ids, $drone_run_band_project_id;
    }

    my $apply_geocood_polygons_q = "SELECT geocoord_polygons.value, rotate_keep_original_size.value, cropped_polygon.value, original_image_resize.value, rotated_image_resize.value
        FROM project AS drone_run
        JOIN project_relationship ON (drone_run.project_id=project_relationship.object_project_id AND project_relationship.type_id=$drone_run_drone_run_band_type_id)
        JOIN project AS drone_run_band ON(project_relationship.subject_project_id=drone_run_band.project_id)
        JOIN projectprop AS geocoord_polygons ON(drone_run_band.project_id=geocoord_polygons.project_id AND geocoord_polygons.type_id=$geoparam_coordinates_plot_polygons_cvterm_id)
        LEFT JOIN projectprop AS rotate_keep_original_size ON(drone_run_band.project_id=rotate_keep_original_size.project_id AND rotate_keep_original_size.type_id=$drone_run_band_rotate_keep_original_size_cvterm_id)
        JOIN projectprop AS cropped_polygon ON(drone_run_band.project_id=cropped_polygon.project_id AND cropped_polygon.type_id=$cropping_polygon_type_id)
        LEFT JOIN projectprop AS original_image_resize ON(drone_run_band.project_id=original_image_resize.project_id AND original_image_resize.type_id=$original_image_resize_ratio_cvterm_id)
        LEFT JOIN projectprop AS rotated_image_resize ON(drone_run_band.project_id=rotated_image_resize.project_id AND rotated_image_resize.type_id=$rotated_image_resize_ratio_cvterm_id)
        WHERE drone_run.project_id=? LIMIT 1;";
    my $apply_geocood_polygons_h = $schema->storage->dbh()->prepare($apply_geocood_polygons_q);
    $apply_geocood_polygons_h->execute($geoparam_drone_run_project_id_input);
    my ($previous_geocoord_polygon_json, $rotate_keep_original_size, $previous_cropped_polygon_json, $original_image_resize_json, $rotated_image_resize_json) = $apply_geocood_polygons_h->fetchrow_array();
    my $previous_geocoord_polygons = decode_json $previous_geocoord_polygon_json;
    my $previous_cropped_polygon = decode_json $previous_cropped_polygon_json;
    my $original_image_resize = $original_image_resize_json ? decode_json $original_image_resize_json : [1,1];
    my $rotated_image_resize = $rotated_image_resize_json ? decode_json $rotated_image_resize_json : [1,1];

    my $cropping_x_offset = $previous_cropped_polygon->[0]->[0]->{x};
    my $cropping_y_offset = $previous_cropped_polygon->[0]->[0]->{y};

    my $upload_original_name = $upload_file->filename();
    my $upload_tempfile = $upload_file->tempname;
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();

    my @geoparams_coordinates;
    my $geoparams_projection;
    my $ortho_file;
    my $outfile_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'standard_process_drone_imagery_geocoordinate_param/imageXXXX').".png";
    my $outfile_geoparams = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'standard_process_drone_imagery_geocoordinate_param/fileXXXX').".csv";
    my $outfile_geoparams_projection = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'standard_process_drone_imagery_geocoordinate_param/fileXXXX').".csv";

    if ($image_type eq 'rgb') {
        my $outfile_image_r = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'standard_process_drone_imagery_geocoordinate_param/imageXXXX').".png";
        my $outfile_image_g = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'standard_process_drone_imagery_geocoordinate_param/imageXXXX').".png";
        my $outfile_image_b = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'standard_process_drone_imagery_geocoordinate_param/imageXXXX').".png";

        my $geo_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/GDALOpenImageRGBGeoTiff.py --image_path $upload_tempfile --outfile_path_image $outfile_image --outfile_path_image_1 $outfile_image_r --outfile_path_image_2 $outfile_image_g --outfile_path_image_3 $outfile_image_b --outfile_path_geo_params $outfile_geoparams --outfile_path_geo_projection $outfile_geoparams_projection";
        print STDERR $geo_cmd."\n";
        my $geo_cmd_status = system($geo_cmd);
        $ortho_file = $outfile_image;

        open(my $fh_geoparams, '<', $outfile_geoparams) or die "Could not open file '".$outfile_geoparams."' $!";
            print STDERR "Opened ".$outfile_geoparams."\n";
            my $geoparams = <$fh_geoparams>;
            chomp $geoparams;
            @geoparams_coordinates = split ',', $geoparams;
            print STDERR Dumper [$geoparams, \@geoparams_coordinates];
        close($fh_geoparams);

        open(my $fh_geoparam_proj, '<', $outfile_geoparams_projection) or die "Could not open file '".$outfile_geoparams_projection."' $!";
            print STDERR "Opened ".$outfile_geoparams_projection."\n";
            my $geoparams_proj = <$fh_geoparam_proj>;
            chomp $geoparams_proj;
            $geoparams_proj =~ s/,//g;
            my @geoparams_proj_arr = split "\"\"\"\"", $geoparams_proj;
            $geoparams_projection = $geoparams_proj_arr[3];
            $geoparams_projection =~ s/\s//g;
            print STDERR Dumper [$geoparams_proj, $geoparams_projection];
        close($fh_geoparam_proj);
    }
    else {
        my $geo_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/ImageProcess/GDALOpenSingleChannelImageGeoTiff.py --image_path $upload_tempfile --outfile_path_image $outfile_image --outfile_path_geo_params $outfile_geoparams --outfile_path_geo_projection $outfile_geoparams_projection";
        print STDERR $geo_cmd."\n";
        my $geo_cmd_status = system($geo_cmd);
        $ortho_file = $outfile_image;

        open(my $fh_geoparams, '<', $outfile_geoparams) or die "Could not open file '".$outfile_geoparams."' $!";
            print STDERR "Opened ".$outfile_geoparams."\n";
            my $geoparams = <$fh_geoparams>;
            chomp $geoparams;
            @geoparams_coordinates = split ',', $geoparams;
            print STDERR Dumper [$geoparams, \@geoparams_coordinates];
        close($fh_geoparams);

        open(my $fh_geoparam_proj, '<', $outfile_geoparams_projection) or die "Could not open file '".$outfile_geoparams_projection."' $!";
            print STDERR "Opened ".$outfile_geoparams_projection."\n";
            my $geoparams_proj = <$fh_geoparam_proj>;
            chomp $geoparams_proj;
            $geoparams_proj =~ s/,//g;
            my @geoparams_proj_arr = split "\"\"\"\"", $geoparams_proj;
            $geoparams_projection = $geoparams_proj_arr[3];
            $geoparams_projection =~ s/\s//g;
            print STDERR Dumper [$geoparams_proj, $geoparams_projection];
        close($fh_geoparam_proj);
    }

    my $vegetative_indices = ['VARI', 'TGI', 'NDRE', 'NDVI', 'CCC'];
    my $phenotype_methods = ['zonal'];
    my $standard_process_type = 'minimal';

    my $rad_conversion = 0.0174533;

    my $drone_run_process_in_progress = $schema->resultset('Project::Projectprop')->update_or_create({
        type_id=>$process_indicator_cvterm_id,
        project_id=>$drone_run_project_id_in,
        rank=>0,
        value=>1
    },
    {
        key=>'projectprop_c1'
    });

    my $drone_run_process_completed = $schema->resultset('Project::Projectprop')->update_or_create({
        type_id=>$processed_cvterm_id,
        project_id=>$drone_run_project_id_in,
        rank=>0,
        value=>0
    },
    {
        key=>'projectprop_c1'
    });

    my $drone_run_process_minimal_vi_completed = $schema->resultset('Project::Projectprop')->update_or_create({
        type_id=>$processed_minimal_vi_cvterm_id,
        project_id=>$drone_run_project_id_in,
        rank=>0,
        value=>0
    },
    {
        key=>'projectprop_c1'
    });

    my %vegetative_indices_hash;
    foreach (@$vegetative_indices) {
        $vegetative_indices_hash{$_}++;
    }

    my %selected_drone_run_band_types;
    my $q2 = "SELECT project_md_image.image_id, drone_run_band_type.value, drone_run_band.project_id
        FROM project AS drone_run_band
        JOIN projectprop AS drone_run_band_type ON(drone_run_band_type.project_id = drone_run_band.project_id AND drone_run_band_type.type_id = $drone_run_band_type_cvterm_id)
        JOIN phenome.project_md_image AS project_md_image ON(project_md_image.project_id = drone_run_band.project_id)
        JOIN metadata.md_image ON(project_md_image.image_id = metadata.md_image.image_id)
        WHERE project_md_image.type_id = $project_image_type_id
        AND drone_run_band.project_id = ?
        AND metadata.md_image.obsolete = 'f';";

    my $h2 = $schema->storage->dbh()->prepare($q2);

    my $term_map = CXGN::DroneImagery::ImageTypes::get_base_imagery_observation_unit_plot_polygon_term_map();

    my %drone_run_band_info;
    foreach my $apply_drone_run_band_project_id (@apply_drone_run_band_project_ids) {
        my $apply_original_image_resize = $drone_run_project_info{$apply_drone_run_band_project_id}->{original_image_resize};
        my $apply_original_image_resize_x = $apply_original_image_resize->[0];
        my $apply_original_image_resize_y = $apply_original_image_resize->[1];
        print STDERR Dumper $apply_original_image_resize;

        my $h2 = $schema->storage->dbh()->prepare($q2);
        $h2->execute($apply_drone_run_band_project_id);
        my ($image_id, $drone_run_band_type, $drone_run_band_project_id) = $h2->fetchrow_array();
        $selected_drone_run_band_types{$drone_run_band_type} = $drone_run_band_project_id;

        my $apply_image_width_ratio = 1;
        my $apply_image_height_ratio = 1;

        my $dir = $c->tempfiles_subdir('/drone_imagery_rotate');
        my $archive_rotate_temp_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'drone_imagery_rotate/imageXXXX');
        $archive_rotate_temp_image .= '.png';

        my $rotate_return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_image_rotate($c, $schema, $metadata_schema, $drone_run_band_project_id, [], $image_id, $rotate_value*-1, 0, $user_id, $user_name, $user_role, $archive_rotate_temp_image, 0, 0, 1, $rotate_keep_original_size);
        my $rotated_image_id = $rotate_return->{rotated_image_id};
        my $apply_rotated_image_resize = $rotate_return->{original_image_resize_ratio};
        my $apply_rotated_image_resize_x = $apply_rotated_image_resize->[0];
        my $apply_rotated_image_resize_y = $apply_rotated_image_resize->[1];
        print STDERR Dumper $apply_rotated_image_resize;

        my $image = SGN::Image->new( $schema->storage->dbh, $rotated_image_id, $c );
        my $image_fullpath = $image->get_filename('original_converted', 'full');

        my @size = imgsize($image_fullpath);
        my $width = $size[0];
        my $length = $size[1];
        my $x_center = $width/2;
        my $y_center = $length/2;

        my $cropping_value = encode_json [[{x=>0, y=>0}, {x=>$width, y=>0}, {x=>$width, y=>$length}, {x=>0, y=>$length}]];

        my $plot_polygons_value;
        while( my ($stock_name, $polygons) = each %$previous_geocoord_polygons) {
            my @coords;
            foreach my $crd (@$polygons) {
                my $xOrigin = $geoparams_coordinates[0];
                my $yOrigin = $geoparams_coordinates[3];
                my $pixelWidth = $geoparams_coordinates[1];
                my $pixelHeight = -1*$geoparams_coordinates[5];
                my $x_pos = ($crd->[0] - $xOrigin) / $pixelWidth;
                my $y_pos = ($yOrigin - $crd->[1] ) / $pixelHeight;

                $x_pos = $x_pos/$apply_original_image_resize_x;
                $y_pos = $y_pos/$apply_original_image_resize_y;

                $x_pos = $x_pos/$apply_rotated_image_resize_x;
                $y_pos = $y_pos/$apply_rotated_image_resize_y;

                my $x_pos_rotated = ($x_pos - $x_center)*cos($rad_conversion*$rotate_value*-1) - ($y_pos - $y_center)*sin($rad_conversion*$rotate_value*-1) + $x_center;
                my $y_pos_rotated = ($y_pos - $y_center)*cos($rad_conversion*$rotate_value*-1) + ($x_pos - $x_center)*sin($rad_conversion*$rotate_value*-1) + $y_center;

                push @coords, {
                    x => round($x_pos_rotated),
                    y => round($y_pos_rotated),
                };
            }
            $plot_polygons_value->{$stock_name} = \@coords;
        }
        $plot_polygons_value = encode_json $plot_polygons_value;

        $dir = $c->tempfiles_subdir('/drone_imagery_cropped_image');
        my $archive_temp_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'drone_imagery_cropped_image/imageXXXX');
        $archive_temp_image .= '.png';

        my $cropping_return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_image_cropping($c, $schema, $drone_run_band_project_id, [], $rotated_image_id, $cropping_value, $user_id, $user_name, $user_role, $archive_temp_image, $apply_image_width_ratio, $apply_image_height_ratio);
        my $cropped_image_id = $cropping_return->{cropped_image_id};

        $dir = $c->tempfiles_subdir('/drone_imagery_denoise');
        my $archive_denoise_temp_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'drone_imagery_denoise/imageXXXX');
        $archive_denoise_temp_image .= '.png';

        my $denoise_return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_image_denoise($c, $schema, $metadata_schema, $cropped_image_id, $drone_run_band_project_id, [], $user_id, $user_name, $user_role, $archive_denoise_temp_image);
        my $denoised_image_id = $denoise_return->{denoised_image_id};

        $drone_run_band_info{$drone_run_band_project_id} = {
            denoised_image_id => $denoised_image_id,
            rotate_value => $rotate_value,
            cropping_value => $cropping_value,
            drone_run_band_type => $drone_run_band_type,
            drone_run_project_id => $drone_run_project_id_in,
            drone_run_project_name => $drone_run_project_info{$drone_run_project_id_in}->{name},
            plot_polygons_value => $plot_polygons_value,
            check_resize => 1,
            keep_original_size_rotate => 1,
            threshold_values => "Lower Threshold Percentage:25. Upper Threshold Percentage:25"
        };

        my @denoised_plot_polygon_type = @{$term_map->{$drone_run_band_type}->{observation_unit_plot_polygon_types}->{base}};
        my @denoised_background_threshold_removed_imagery_types = @{$term_map->{$drone_run_band_type}->{imagery_types}->{threshold_background}};
        my @denoised_background_threshold_removed_plot_polygon_types = @{$term_map->{$drone_run_band_type}->{observation_unit_plot_polygon_types}->{threshold_background}};

        my $polygon_type = '';
        if ($rotate_value != 0) {
            $polygon_type = 'rectangular_square';
        } else {
            $polygon_type = 'rectangular_polygon';
        }

        foreach (@denoised_plot_polygon_type) {
            my $plot_polygon_original_denoised_return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_plot_polygon_assign($c, $schema, $metadata_schema, $denoised_image_id, $drone_run_band_project_id, [], $plot_polygons_value, $_, $user_id, $user_name, $user_role, 0, 0, $apply_image_width_ratio, $apply_image_height_ratio, $polygon_type, 0, 0);
        }

        for my $iterator (0..(scalar(@denoised_background_threshold_removed_imagery_types)-1)) {
            $dir = $c->tempfiles_subdir('/drone_imagery_remove_background');
            my $archive_remove_background_temp_image = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'drone_imagery_remove_background/imageXXXX');
            $archive_remove_background_temp_image .= '.png';

            my $background_removed_threshold_return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_image_background_remove_threshold_percentage($c, $schema, $denoised_image_id, $drone_run_band_project_id, [], $denoised_background_threshold_removed_imagery_types[$iterator], '25', '25', $user_id, $user_name, $user_role, $archive_remove_background_temp_image);

            my $plot_polygon_return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_plot_polygon_assign($c, $schema, $metadata_schema, $background_removed_threshold_return->{removed_background_image_id}, $drone_run_band_project_id, [], $plot_polygons_value, $denoised_background_threshold_removed_plot_polygon_types[$iterator], $user_id, $user_name, $user_role, 0, 0, $apply_image_width_ratio, $apply_image_height_ratio, $polygon_type, 0, 0);
        }

        my $drone_run_band_coordinate_system_type_rs = $schema->resultset('Project::Projectprop')->update_or_create({
            type_id=>$geoparam_coordinates_type_cvterm_id,
            project_id=>$drone_run_band_project_id,
            rank=>0,
            value=> $geoparams_projection
        },
        {
            key=>'projectprop_c1'
        });

        my $drone_run_band_geoparam_coordinates_rs = $schema->resultset('Project::Projectprop')->update_or_create({
            type_id=>$geoparam_coordinates_cvterm_id,
            project_id=>$drone_run_band_project_id,
            rank=>0,
            value=> encode_json \@geoparams_coordinates
        },
        {
            key=>'projectprop_c1'
        });

        my $drone_run_band_geoparam_coordinates_polygons_rs = $schema->resultset('Project::Projectprop')->update_or_create({
            type_id=>$geoparam_coordinates_plot_polygons_cvterm_id,
            project_id=>$drone_run_band_project_id,
            rank=>0,
            value=> $previous_geocoord_polygon_json
        },
        {
            key=>'projectprop_c1'
        });
    }

    print STDERR Dumper \%selected_drone_run_band_types;
    print STDERR Dumper \%vegetative_indices_hash;

    SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_minimal_vi_standard_process($c, $schema, $metadata_schema, \%vegetative_indices_hash, \%selected_drone_run_band_types, [], {},  \%drone_run_band_info, $user_id, $user_name, $user_role, 'rectangular_polygon');

    $drone_run_process_in_progress = $schema->resultset('Project::Projectprop')->update_or_create({
        type_id=>$process_indicator_cvterm_id,
        project_id=>$drone_run_project_id_in,
        rank=>0,
        value=>0
    },
    {
        key=>'projectprop_c1'
    });

    $drone_run_process_completed = $schema->resultset('Project::Projectprop')->update_or_create({
        type_id=>$processed_cvterm_id,
        project_id=>$drone_run_project_id_in,
        rank=>0,
        value=>1
    },
    {
        key=>'projectprop_c1'
    });

    $drone_run_process_minimal_vi_completed = $schema->resultset('Project::Projectprop')->update_or_create({
        type_id=>$processed_minimal_vi_cvterm_id,
        project_id=>$drone_run_project_id_in,
        rank=>0,
        value=>1
    },
    {
        key=>'projectprop_c1'
    });

    my $plot_margin_top_bottom = 5;
    my $plot_margin_left_right = 5;

    my $return = SGN::Controller::AJAX::DroneImagery::DroneImagery::_perform_phenotype_automated($c, $schema, $metadata_schema, $phenome_schema, $drone_run_project_id_in, $time_cvterm_id, $phenotype_methods, $standard_process_type, 1, undef, $plot_margin_top_bottom, $plot_margin_left_right, $user_id, $user_name, $user_role);

    $c->stash->{message} = "Successfully uploaded! Go to <a href='/breeders/drone_imagery'>Drone Imagery</a>";
    $c->stash->{template} = 'generic_message.mas';
    return;
}

sub upload_drone_imagery_additional_raw_images : Path("/drone_imagery/upload_drone_imagery_additional_raw_images") :Args(0) {
    my $self = shift;
    my $c = shift;
    $c->response->headers->header( "Access-Control-Allow-Origin" => '*' );
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my $dbh = $c->dbc->dbh;
    # print STDERR Dumper $c->req->params();

    my $upload = $c->req->upload('upload_drone_imagery_additional_raw_images_zipfile');
    my $private_company_id = $c->req->param('upload_drone_imagery_additional_raw_images_private_company_id');
    my $private_company_is_private = $c->req->param('upload_drone_imagery_additional_raw_images_private_company_is_private');
    my $drone_run_id = $c->req->param('upload_drone_imagery_additional_raw_images_drone_run_id');
    my $field_trial_id = $c->req->param('upload_drone_imagery_additional_raw_images_field_trial_id');

    my ($user_id, $user_name, $user_role) = _check_user_login_drone_imagery_upload($c, 'submitter', $private_company_id, 'submitter_access');

    my $trial = CXGN::Trial->new({
        bcs_schema => $schema,
        metadata_schema => $metadata_schema,
        phenome_schema => $phenome_schema,
        trial_id => $drone_run_id
    });

    my $subdirectory = "trial_additional_file_upload";
    my $upload_original_name = $upload->filename();
    my $upload_tempfile = $upload->tempname;
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();

    ## Store uploaded temporary file in archive
    my $uploader = CXGN::UploadFile->new({
        tempfile => $upload_tempfile,
        subdirectory => $subdirectory,
        archive_path => $c->config->{archive_path},
        archive_filename => $upload_original_name,
        timestamp => $timestamp,
        user_id => $user_id,
        user_role => $user_role
    });
    my $archived_filename_with_path = $uploader->archive();
    my $md5 = $uploader->get_md5($archived_filename_with_path);
    if (!$archived_filename_with_path) {
        $c->stash->{rest} = {error => "Could not save file $upload_original_name in archive",};
        $c->detach();
    }
    unlink $upload_tempfile;
    my $md5checksum = $md5->hexdigest();

    my $result = $trial->add_additional_uploaded_file($user_id, $archived_filename_with_path, $md5checksum);

    $c->stash->{message} = "Successfully uploaded! Go to <a href='/breeders/drone_imagery'>Drone Imagery</a>";
    $c->stash->{template} = 'generic_message.mas';
    return;
}

sub _check_user_login_drone_imagery_upload {
    my $c = shift;
    my $check_priv = shift;
    my $original_private_company_id = shift;
    my $user_access = shift;

    my $login_check_return = CXGN::Login::_check_user_login($c, $check_priv, $original_private_company_id, $user_access);
    if ($login_check_return->{error}) {
        $c->stash->{rest} = $login_check_return;
        $c->detach();
    }
    my ($user_id, $user_name, $user_role) = @{$login_check_return->{info}};

    return ($user_id, $user_name, $user_role);
}

1;
