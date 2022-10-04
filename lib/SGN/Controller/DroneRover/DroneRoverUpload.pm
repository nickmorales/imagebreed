
=head1 NAME

=head1 DESCRIPTION

=head1 AUTHOR

=cut

package SGN::Controller::DroneRover::DroneRoverUpload;

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
use LWP::UserAgent;
use CXGN::ZipFile;
use Text::CSV;
use CXGN::Trial::TrialLayout;

BEGIN { extends 'Catalyst::Controller'; }

sub upload_drone_rover : Path("/drone_rover/upload_drone_rover") :Args(0) {
    my $self = shift;
    my $c = shift;
    $c->response->headers->header( "Access-Control-Allow-Origin" => '*' );
    $c->response->headers->header( "Access-Control-Allow-Methods" => "POST, GET, PUT, DELETE" );
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    print STDERR Dumper $c->req->params();

    my $private_company_id = $c->req->param('rover_run_company_id');
    my ($user_id, $user_name, $user_role) = _check_user_login_drone_rover_upload($c, 'submitter', $private_company_id, 'submitter_access');

    if (!$private_company_id) {
        $c->stash->{message} = "Please select a company first!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    my $private_companies = CXGN::PrivateCompany->new( { schema=> $schema } );
    my ($private_companies_array, $private_companies_ids, $allowed_private_company_ids_hash, $allowed_private_company_access_hash, $private_company_access_is_private_hash) = $private_companies->get_users_private_companies($user_id, 0);
    my $company_is_private = $private_company_access_is_private_hash->{$private_company_id} ? 1 : 0;

    my $selected_trial_ids = $c->req->param('rover_run_field_trial_id');
    if (!$selected_trial_ids) {
        $c->stash->{message} = "Please select atleast one field trial first!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    my @selected_trial_ids = split ',', $selected_trial_ids;

    my $new_drone_run_names_string = $c->req->param('rover_run_name');
    my @new_drone_run_names = split ',', $new_drone_run_names_string;
    my $new_drone_run_names_string_safe = join '_', @new_drone_run_names;

    my $selected_drone_run_id = $c->req->param('rover_run_id');
    my $new_drone_run_type = $c->req->param('rover_run_rover_type');
    my $new_drone_run_data_type = $c->req->param('rover_run_rover_data_type');
    my $new_drone_run_camera_info = $c->req->param('rover_run_sensor_type');
    my $new_drone_run_date = $c->req->param('rover_run_date');
    my $new_drone_run_desc = $c->req->param('rover_run_description');
    my $new_drone_run_vehicle_id = $c->req->param('rover_run_vehicle_id');
    my $new_drone_run_battery_name = $c->req->param('rover_run_vehicle_battery_name');

    my $dir = $c->tempfiles_subdir('/upload_drone_rover');

    if (!$new_drone_run_vehicle_id) {
        $c->stash->{message} = "Please give a rover event vehicle id!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    if (!$selected_drone_run_id && !$new_drone_run_names_string) {
        $c->stash->{message} = "Please select a rover event or create a new rover event!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    if ($new_drone_run_names_string && !$new_drone_run_type){
        $c->stash->{message} = "Please give a new rover event type!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    if ($new_drone_run_names_string && !$new_drone_run_data_type){
        $c->stash->{message} = "Please give a new rover event data type!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    if ($new_drone_run_names_string && !$new_drone_run_date){
        $c->stash->{message} = "Please give a new rover event date!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    if ($new_drone_run_names_string && $new_drone_run_date !~ /^\d{4}\/\d{2}\/\d{2}\s\d\d:\d\d:\d\d$/){
        $c->stash->{message} = "Please give a new rover event date in the format YYYY/MM/DD HH:mm:ss!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    if ($new_drone_run_names_string && !$new_drone_run_desc){
        $c->stash->{message} = "Please give a new rover event description!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    if (!$new_drone_run_camera_info) {
        $c->stash->{message} = "Please indicate the type of sensor!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    if ($new_drone_run_data_type eq 'earthsense_plot_point_clouds' && $new_drone_run_camera_info ne 'earthsense_lidar') {
        $c->stash->{message} = "If the rover data type is Separated Earthsense Plot Point Clouds then the sensor must be EarthSense Lidar!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
    if ($new_drone_run_data_type eq 'earthsense_plot_point_clouds' && $new_drone_run_type ne 'earthsense') {
        $c->stash->{message} = "If the rover data type is Separated Earthsense Plot Point Clouds then the rover must be EarthSense!";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }

    my $q_priv = "UPDATE project SET private_company_id=?, is_private=? WHERE project_id=?;";
    my $h_priv = $schema->storage->dbh()->prepare($q_priv);

    my $drone_run_experiment_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_experiment', 'experiment_type')->cvterm_id();
    my $design_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'design', 'project_property')->cvterm_id();
    my $drone_run_camera_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_camera_type', 'project_property')->cvterm_id();
    my $drone_run_related_cvterms_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_related_time_cvterms_json', 'project_property')->cvterm_id();
    my $project_relationship_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_on_field_trial', 'project_relationship')->cvterm_id();
    my $field_trial_drone_runs_in_same_orthophoto_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'field_trial_drone_runs_in_same_orthophoto', 'experiment_type')->cvterm_id();
    my $imaging_vehicle_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'imaging_event_vehicle_rover', 'stock_type')->cvterm_id();
    my $imaging_vehicle_properties_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'imaging_event_vehicle_json', 'stock_property')->cvterm_id();
    my $drone_run_is_rover_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_is_rover', 'project_property')->cvterm_id();

    my @selected_drone_run_infos;
    my @selected_drone_run_ids;
    if (!$selected_drone_run_id) {
        my $drone_run_field_trial_project_relationship_type_id_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_on_field_trial', 'project_relationship')->cvterm_id();
        my $project_start_date_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'project_start_date', 'project_property')->cvterm_id();

        my $calendar_funcs = CXGN::Calendar->new({});

        my %seen_field_trial_drone_run_dates;
        my $drone_run_date_q = "SELECT drone_run_date.value
            FROM project AS drone_run_project
            JOIN projectprop AS drone_run_date ON(drone_run_project.project_id=drone_run_date.project_id AND drone_run_date.type_id=$project_start_date_type_id)
            JOIN projectprop AS is_rover ON (drone_run_project.project_id=is_rover.project_id AND is_rover.type_id=$drone_run_is_rover_type_cvterm_id)
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
        $drone_run_date_h = undef;

        my $drone_run_date_obj = Time::Piece->strptime($new_drone_run_date, "%Y/%m/%d %H:%M:%S");
        if (exists($seen_field_trial_drone_run_dates{$drone_run_date_obj->epoch})) {
            $c->stash->{message} = "A ground rover event has already occured on these field trial(s) at the same date and time! Please give a unique date/time for each ground rover event on a field trial!";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }

        my $iterator = 0;
        my $field_trial_drone_runs_in_same_orthophoto_nd_experiment_id;
        foreach my $selected_trial_id (@selected_trial_ids) {
            my $new_drone_run_name = $new_drone_run_names[$iterator];

            my $trial = CXGN::Trial->new({ bcs_schema => $schema, trial_id => $selected_trial_id });
            my $trial_location_id = $trial->get_location()->[0];
            my $planting_date = $trial->get_planting_date();
            my $planting_date_time_object = Time::Piece->strptime($planting_date, "%Y-%B-%d");
            my $drone_run_date_time_object = Time::Piece->strptime($new_drone_run_date, "%Y/%m/%d %H:%M:%S");
            my $time_diff = $drone_run_date_time_object - $planting_date_time_object;
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
            $h = undef;

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
                {type_id => $drone_run_is_rover_type_cvterm_id, value => $new_drone_run_type},
                {type_id => $project_start_date_type_id, value => $drone_run_event},
                {type_id => $design_cvterm_id, value => 'drone_run'},
                {type_id => $drone_run_camera_type_cvterm_id, value => $new_drone_run_camera_info},
                {type_id => $drone_run_related_cvterms_cvterm_id, value => encode_json \%related_cvterms}
            ];

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

    if ($new_drone_run_data_type eq 'earthsense_plot_point_clouds') {
        my $upload_file = $c->req->upload('upload_drone_rover_zipfile_lidar_earthsense_plot_txt');
        my $upload_file_plot_names = $c->req->upload('upload_drone_rover_earthsense_txt_plot_names');

        my $upload_original_name = $upload_file->filename();
        my $upload_tempfile = $upload_file->tempname;
        my $time = DateTime->now();
        my $timestamp = $time->ymd()."_".$time->hms();
        print STDERR Dumper [$upload_original_name, $upload_tempfile];

        my $uploader = CXGN::UploadFile->new({
            tempfile => $upload_tempfile,
            subdirectory => "drone_imagery_upload_rover_zips",
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
        print STDERR "Archived Rover Zip File: $archived_filename_with_path\n";
        unlink $upload_tempfile;

        my $upload_plot_names_original_name = $upload_file_plot_names->filename();
        my $upload_plot_names_tempfile = $upload_file_plot_names->tempname;
        print STDERR Dumper [$upload_plot_names_original_name, $upload_plot_names_tempfile];

        my $uploader_plot_names = CXGN::UploadFile->new({
            tempfile => $upload_plot_names_tempfile,
            subdirectory => "drone_imagery_upload_rover_zips",
            second_subdirectory => "$selected_drone_run_id",
            archive_path => $c->config->{archive_path},
            archive_filename => $upload_plot_names_original_name,
            timestamp => $timestamp,
            user_id => $user_id,
            user_role => $user_role
        });
        my $archived_plot_names_filename_with_path = $uploader_plot_names->archive();
        my $md5_plot_names = $uploader_plot_names->get_md5($archived_plot_names_filename_with_path);
        if (!$archived_plot_names_filename_with_path) {
            $c->stash->{message} = "Could not save file $upload_plot_names_original_name in archive.";
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        print STDERR "Archived Rover Zip Plot Names File: $archived_plot_names_filename_with_path\n";
        unlink $upload_plot_names_tempfile;

        my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_plot_names_filename_with_path);
        $parser->load_plugin('EarthSenseTXTPointCloudsToPlotNamesCSV');
        my $parsed_data = $parser->parse();
        #print STDERR Dumper $parsed_data;

        if (!$parsed_data) {
            my $return_error = '';
            my $parse_errors;
            if (!$parser->has_parse_errors() ){
                $c->stash->{message} = "Could not get parsing errors";
                $c->stash->{template} = 'generic_message.mas';
                return;
            } else {
                $parse_errors = $parser->get_parse_errors();
                #print STDERR Dumper $parse_errors;

                foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                    $return_error .= $error_string."<br>";
                }
            }
            $c->stash->{message} = $return_error;
            $c->stash->{template} = 'generic_message.mas';
            return;
        }

        my $parsed_entries = $parsed_data->{data};

        my $image = SGN::Image->new( $c->dbc->dbh, undef, $c );
        my $zipfile_return = $image->upload_drone_imagery_zipfile($archived_filename_with_path, $user_id, $selected_drone_run_id);
        # print STDERR Dumper $zipfile_return;
        if ($zipfile_return->{error}) {
            $c->stash->{message} = "Problem saving images!".$zipfile_return->{error};
            $c->stash->{template} = 'generic_message.mas';
            return;
        }
        my $image_paths = $zipfile_return->{image_files};

        foreach my $i (@$image_paths) {

        }

        $c->stash->{message} = "Successfully uploaded! Go to <a href='/breeders/drone_rover'>Ground Rover Data</a>";
        $c->stash->{template} = 'generic_message.mas';
        return;
    }
}

sub _check_user_login_drone_rover_upload {
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
