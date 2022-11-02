
=head1 NAME

SGN::Controller::AJAX::DroneRover::DroneRover - a REST controller class to provide the
functions for uploading and analyzing drone rover point clouds

=head1 DESCRIPTION

=head1 AUTHOR

=cut

package SGN::Controller::AJAX::DroneRover::DroneRover;

use Moose;
use Data::Dumper;
use LWP::UserAgent;
use JSON;
use SGN::Model::Cvterm;
use DateTime;
use CXGN::UploadFile;
use SGN::Image;
use URI::Encode qw(uri_encode uri_decode);
use File::Basename qw | basename dirname|;
use File::Slurp qw(write_file);
use File::Temp 'tempfile';
use File::Spec::Functions;
use File::Copy;
use CXGN::Calendar;
use Image::Size;
use Text::CSV;
use CXGN::Phenotypes::StorePhenotypes;
use CXGN::Onto;
use Time::Piece;
use POSIX;
use Math::Round;
use Parallel::ForkManager;
use List::MoreUtils qw(first_index);
use List::Util qw(sum);
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use CXGN::Location;
use CXGN::Trial;
use CXGN::Trial::TrialLayoutDownload;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON'  },
);

sub drone_rover_get_vehicles : Path('/api/drone_rover/rover_vehicles') : ActionClass('REST') { }
sub drone_rover_get_vehicles_GET : Args(0) {
    my $self = shift;
    my $c = shift;
    my $bcs_schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');
    my $private_company_id = $c->req->param('private_company_id');
    my ($user_id, $user_name, $user_role) = _check_user_login_drone_rover($c, 'user', $private_company_id, 'user_access');

    my $private_companies_sql = '';
    if ($private_company_id) {
        $private_companies_sql = $private_company_id;
    }
    else {
        my $private_companies = CXGN::PrivateCompany->new( { schema => $bcs_schema } );
        my ($private_companies_array, $private_companies_ids, $allowed_private_company_ids_hash, $allowed_private_company_access_hash, $private_company_access_is_private_hash) = $private_companies->get_users_private_companies($user_id, 0);
        $private_companies_sql = join ',', @$private_companies_ids;
    }

    my $imaging_vehicle_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($bcs_schema, 'imaging_event_vehicle_rover', 'stock_type')->cvterm_id();
    my $imaging_vehicle_properties_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($bcs_schema, 'imaging_event_vehicle_json', 'stock_property')->cvterm_id();

    my $q = "SELECT stock.stock_id, stock.uniquename, stock.description, stock.private_company_id, company.name, stockprop.value
        FROM stock
        JOIN sgn_people.private_company AS company ON(stock.private_company_id=company.private_company_id)
        JOIN stockprop ON(stock.stock_id=stockprop.stock_id AND stockprop.type_id=$imaging_vehicle_properties_cvterm_id)
        WHERE stock.type_id=$imaging_vehicle_cvterm_id AND stock.private_company_id IN($private_companies_sql);";
    my $h = $bcs_schema->storage->dbh()->prepare($q);
    $h->execute();
    my @vehicles;
    while (my ($stock_id, $name, $description, $private_company_id, $private_company_name, $prop) = $h->fetchrow_array()) {
        my $prop_hash = decode_json $prop;
        my @batt_info;
        foreach (sort keys %{$prop_hash->{batteries}}) {
            my $p = $prop_hash->{batteries}->{$_};
            push @batt_info, "$_: Usage = ".$p->{usage}." Obsolete = ".$p->{obsolete};
        }
        my $batt_info_string = join '<br/>', @batt_info;
        my $private_company = "<a href='/company/$private_company_id'>$private_company_name</a>";
        push @vehicles, [$name, $description, $private_company, $batt_info_string]
    }
    $h = undef;

    $c->stash->{rest} = { data => \@vehicles };
}

sub drone_rover_get_collection : Path('/api/drone_rover/get_collection') : ActionClass('REST') { }
sub drone_rover_get_collection_GET : Args(0) {
    my $self = shift;
    my $c = shift;
    my $bcs_schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');
    my $drone_run_project_id = $c->req->param('drone_run_project_id');
    my $collection_number = $c->req->param('collection_number');
    my ($user_id, $user_name, $user_role) = _check_user_login_drone_rover($c, 'user', undef, undef);

    my $earthsense_collections_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($bcs_schema, 'earthsense_ground_rover_collections_archived', 'project_property')->cvterm_id();

    my $q = "SELECT projectprop.value
        FROM projectprop
        WHERE projectprop.type_id=$earthsense_collections_cvterm_id AND projectprop.project_id=?;";
    my $h = $bcs_schema->storage->dbh()->prepare($q);
    $h->execute($drone_run_project_id);
    my ($prop_json) = $h->fetchrow_array();
    $h = undef;
    my $collections = decode_json $prop_json;
    my $collection = $collections->{$collection_number} || {};

    if (exists($collection->{plot_polygons})) {
        foreach my $stock_id (sort keys %{$collection->{plot_polygons}} ) {
            my $file_id = $collection->{plot_polygons}->{$stock_id}->{file_id};
            my $stock = $bcs_schema->resultset("Stock::Stock")->find({stock_id => $stock_id});
            my $stock_name = $stock->uniquename;

            push @{$collection->{plot_polygons_names}}, [$stock_name, $file_id];
        }
    }

    $c->stash->{rest} = $collection;
}

sub check_maximum_plot_polygon_processes : Path('/api/drone_rover/check_maximum_plot_polygon_processes') : ActionClass('REST') { }
sub check_maximum_plot_polygon_processes_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my $bcs_schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my ($user_id, $user_name, $user_role) = _check_user_login_drone_rover($c, 0, 0, 0);

    my $process_indicator_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($bcs_schema, 'drone_rover_plot_polygon_in_progress', 'project_property')->cvterm_id();

    my $rover_process_in_progress_count = $bcs_schema->resultset('Project::Projectprop')->search({type_id=>$process_indicator_cvterm_id, value=>1})->count;
    print STDERR Dumper $rover_process_in_progress_count;
    if ($rover_process_in_progress_count >= $c->config->{drone_rover_max_plot_polygon_processes}) {
        $c->stash->{rest} = { error => "The maximum number of rover plot polygon processes has been reached on this server! Please wait until one of those processes finishes and try again." };
        $c->detach();
    }
    $c->stash->{rest} = { success => 1 };
}

sub drone_rover_get_point_cloud : Path('/api/drone_rover/get_point_cloud') : ActionClass('REST') { }
sub drone_rover_get_point_cloud_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my $bcs_schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');
    my $point_cloud_file_id = $c->req->param('point_cloud_file_id');
    my ($user_id, $user_name, $user_role) = _check_user_login_drone_rover($c, 'user', 0, 0);

    my $file_row = $metadata_schema->resultset("MdFiles")->find({file_id=>$point_cloud_file_id});
    my $point_cloud_file = $file_row->dirname."/".$file_row->basename;

    my @points;
    open(my $fh, "<", $point_cloud_file) || die "Can't open file ".$point_cloud_file;
        while ( my $row = <$fh> ){
            my ($x, $y, $z) = split ' ', $row;
            push @points, {
                x => $x,
                y => $y,
                z => $z
            };
        }
    close($fh);

    $c->stash->{rest} = { success => 1, points => \@points };
}

sub drone_rover_plot_polygons_process_apply : Path('/api/drone_rover/plot_polygons_process_apply') : ActionClass('REST') { }
sub drone_rover_plot_polygons_process_apply_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    print STDERR Dumper $c->req->params();
    my $bcs_schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');
    my $phenome_schema = $c->dbic_schema('CXGN::Phenome::Schema');
    my $drone_run_project_id = $c->req->param('drone_run_project_id');
    my $drone_run_collection_number = $c->req->param('drone_run_collection_number');
    my $drone_run_collection_project_id = $c->req->param('drone_run_collection_project_id');
    my $phenotype_types = decode_json $c->req->param('phenotype_types');
    my $field_trial_id = $c->req->param('field_trial_id');
    my $polygon_template_metadata = decode_json $c->req->param('polygon_template_metadata');
    my $polygons_to_plot_names = decode_json $c->req->param('polygons_to_plot_names');
    my $private_company_id = $c->req->param('company_id');
    my $private_company_is_private = $c->req->param('is_private');
    my ($user_id, $user_name, $user_role) = _check_user_login_drone_rover($c, 'submitter', $private_company_id, 'submitter_access');

    my $earthsense_collections_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($bcs_schema, 'earthsense_ground_rover_collections_archived', 'project_property')->cvterm_id();
    my $project_md_file_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($bcs_schema, 'rover_collection_filtered_plot_point_cloud', 'project_md_file')->cvterm_id();
    my $stock_md_file_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($bcs_schema, 'stock_filtered_plot_point_cloud', 'stock_md_file')->cvterm_id();

    my %stock_ids_all;
    foreach my $stock_name (keys %$polygons_to_plot_names) {
        my $stock = $bcs_schema->resultset("Stock::Stock")->find({uniquename => $stock_name});
        if (!$stock) {
            $c->stash->{rest} = {error=>'Error: Stock name '.$stock_name.' does not exist in the database!'};
            $c->detach();
        }
        $stock_ids_all{$stock_name} = $stock->stock_id;
    }

    my $project = CXGN::Trial->new({ bcs_schema => $bcs_schema, trial_id => $drone_run_project_id });
    my ($field_trial_drone_run_project_ids_in_same_orthophoto, $field_trial_drone_run_project_names_in_same_orthophoto, $field_trial_ids_in_same_orthophoto, $field_trial_names_in_same_orthophoto,  $field_trial_drone_run_projects_in_same_orthophoto, $field_trial_drone_run_band_projects_in_same_orthophoto, $field_trial_drone_run_band_project_ids_in_same_orthophoto_project_type_hash, $related_rover_event_collections, $related_rover_event_collections_hash) = $project->get_field_trial_drone_run_projects_in_same_orthophoto();
    print STDERR Dumper $related_rover_event_collections;
    print STDERR Dumper $related_rover_event_collections_hash;

    my @all_field_trial_ids = ($field_trial_id);
    push @all_field_trial_ids, @$field_trial_ids_in_same_orthophoto;

    my %all_field_trial_layouts;
    foreach my $trial_id (@all_field_trial_ids) {
        my $trial_layout = CXGN::Trial::TrialLayout->new({schema => $bcs_schema, trial_id => $trial_id, experiment_type => 'field_layout'});
        my $design = $trial_layout->get_design();
        foreach my $p (values %$design) {
            $all_field_trial_layouts{$p->{plot_id}} = $related_rover_event_collections_hash->{$trial_id}->{$drone_run_collection_number};
        }
    }

    my $image_width = $polygon_template_metadata->{image_width};
    my $image_height = $polygon_template_metadata->{image_height};

    my $q = "SELECT value FROM projectprop WHERE project_id = ? AND type_id=$earthsense_collections_cvterm_id;";
    my $h = $bcs_schema->storage->dbh()->prepare($q);
    $h->execute($drone_run_collection_project_id);
    my ($prop_json) = $h->fetchrow_array();
    my $earthsense_collection = decode_json $prop_json;
    $h = undef;
    # print STDERR Dumper $earthsense_collection;
    my $point_cloud_file = $earthsense_collection->{processing}->{point_cloud_side_filtered_output};

    my $dir = $c->tempfiles_subdir('/drone_rover_plot_polygons');
    my $bulk_input_temp_file = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'drone_rover_plot_polygons/bulkinputXXXX');

    my @plot_polygons_cut;

    open(my $F, ">", $bulk_input_temp_file) || die "Can't open file ".$bulk_input_temp_file;
    while (my($plot_name, $polygon) = each %$polygons_to_plot_names) {
        my $stock_id = $stock_ids_all{$plot_name};

        my $x1_ratio = $polygon->[0]->[0]/$image_width;
        my $y1_ratio = $polygon->[0]->[1]/$image_height;
        my $x2_ratio = $polygon->[1]->[0]/$image_width;
        my $y2_ratio = $polygon->[3]->[1]/$image_height;

        my $plot_polygons_temp_file = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'drone_rover_plot_polygons/plotpointcloudXXXX');
        $plot_polygons_temp_file .= '.xyz';

        print $F "$stock_id\t$plot_polygons_temp_file\t$x1_ratio\t$y1_ratio\t$x2_ratio\t$y2_ratio\n";

        push @plot_polygons_cut, {
            stock_id => $stock_id,
            temp_file => $plot_polygons_temp_file,
            polygon_ratios => {
                x1 => $x1_ratio,
                x2 => $x2_ratio,
                y1 => $y1_ratio,
                y2 => $y2_ratio
            }
        };
    }
    close($F);

    my $lidar_point_cloud_plot_polygons_cmd = $c->config->{python_executable}." ".$c->config->{rootpath}."/DroneImageScripts/PointCloudProcess/PointCloudPlotPolygons.py --pointcloud_xyz_file $point_cloud_file --plot_polygons_ratio_file $bulk_input_temp_file ";
    print STDERR $lidar_point_cloud_plot_polygons_cmd."\n";
    my $lidar_point_cloud_plot_polygons_status = system($lidar_point_cloud_plot_polygons_cmd);

    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();

    my $q_project_md_file = "INSERT INTO phenome.project_md_file (project_id, file_id, type_id) VALUES (?,?,?);";
    my $h_project_md_file = $bcs_schema->storage->dbh()->prepare($q_project_md_file);

    my $q_stock_md_file = "INSERT INTO phenome.stock_md_file (stock_id, file_id, type_id) VALUES (?,?,?);";
    my $h_stock_md_file = $bcs_schema->storage->dbh()->prepare($q_stock_md_file);

    my $md_row = $metadata_schema->resultset("MdMetadata")->create({create_person_id => $user_id});

    my %saved_point_cloud_files;
    foreach (@plot_polygons_cut) {
        my $stock_id = $_->{stock_id};
        my $temp_file = $_->{temp_file};
        my $polygon_ratios = $_->{polygon_ratios};
        my $drone_run_project_id = $all_field_trial_layouts{$stock_id}->{drone_run_project_id};
        my $project_collection_id = $all_field_trial_layouts{$stock_id}->{drone_run_collection_project_id};
        my $collection_number = $all_field_trial_layouts{$stock_id}->{drone_run_collection_number};

        my $temp_filename = basename($temp_file);
        my $uploader = CXGN::UploadFile->new({
            tempfile => $temp_file,
            subdirectory => "earthsense_rover_collections_plot_polygons",
            second_subdirectory => "$drone_run_collection_project_id",
            archive_path => $c->config->{archive_path},
            archive_filename => $temp_filename,
            timestamp => $timestamp,
            user_id => $user_id,
            user_role => $user_role
        });
        my $archived_filename_with_path = $uploader->archive();
        my $md5 = $uploader->get_md5($archived_filename_with_path);
        if (!$archived_filename_with_path) {
            $c->stash->{rest} = {error=>'Could not archive '.$temp_filename.'!'};
            $c->detach();
        }

        my $file_row = $metadata_schema->resultset("MdFiles")->create({
            basename => basename($archived_filename_with_path),
            dirname => dirname($archived_filename_with_path),
            filetype => "earthsense_rover_collections_plot_polygon_point_clouds",
            md5checksum => $md5->hexdigest(),
            metadata_id => $md_row->metadata_id()
        });
        my $plot_polygon_file_id = $file_row->file_id();

        $h_project_md_file->execute($project_collection_id, $plot_polygon_file_id, $project_md_file_cvterm_id);
        $h_stock_md_file->execute($stock_id, $plot_polygon_file_id, $stock_md_file_cvterm_id);

        $saved_point_cloud_files{$drone_run_project_id}->{$project_collection_id}->{$collection_number}->{$stock_id} = {
            file_id => $plot_polygon_file_id,
            polygon_ratios => $polygon_ratios
        };
    }
    print STDERR Dumper \%saved_point_cloud_files;

    $h_project_md_file = undef;
    $h_stock_md_file = undef;

    while (my($drone_run_project_id, $o1) = each %saved_point_cloud_files) {

        my $earthsense_collections_drone_run_projectprop_rs = $bcs_schema->resultset("Project::Projectprop")->search({
            project_id => $drone_run_project_id,
            type_id => $earthsense_collections_cvterm_id
        });
        if ($earthsense_collections_drone_run_projectprop_rs->count > 1) {
            $c->stash->{rest} = {error => "There should not be more than one EarthSense collections projectprop!"};
            $c->detach();
        }
        my $earthsense_collections_drone_run_projectprop_rs_first = $earthsense_collections_drone_run_projectprop_rs->first;
        my $earthsense_collections_drone_run = decode_json $earthsense_collections_drone_run_projectprop_rs_first->value();

        while (my($drone_run_collection_project_id, $o2) = each %$o1) {
            while (my($drone_run_collection_number, $plot_polygons) = each %$o2) {

                my $earthsense_collections_projectprop_rs = $bcs_schema->resultset("Project::Projectprop")->search({
                    project_id => $drone_run_collection_project_id,
                    type_id => $earthsense_collections_cvterm_id
                });
                if ($earthsense_collections_projectprop_rs->count > 1) {
                    $c->stash->{rest} = {error => "There should not be more than one EarthSense collections projectprop!"};
                    $c->detach();
                }
                my $earthsense_collections_projectprop_rs_first = $earthsense_collections_projectprop_rs->first;
                my $earthsense_collections = decode_json $earthsense_collections_projectprop_rs_first->value();

                $earthsense_collections->{plot_polygons} = $plot_polygons;
                $earthsense_collections->{polygon_template_metadata} = $polygon_template_metadata;

                $earthsense_collections_projectprop_rs_first->value(encode_json $earthsense_collections);
                $earthsense_collections_projectprop_rs_first->update();

                $earthsense_collections_drone_run->{$drone_run_collection_number}->{plot_polygons} = $plot_polygons;
                $earthsense_collections_drone_run->{$drone_run_collection_number}->{polygon_template_metadata} = $polygon_template_metadata;
            }
        }

        $earthsense_collections_drone_run_projectprop_rs_first->value(encode_json $earthsense_collections_drone_run);
        $earthsense_collections_drone_run_projectprop_rs_first->update();
    }

    $c->stash->{rest} = \%saved_point_cloud_files;
}

sub processed_plot_point_cloud_count : Path('/api/drone_rover/processed_plot_point_cloud_count') : ActionClass('REST') { }
sub processed_plot_point_cloud_count_GET : Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my ($user_id, $user_name, $user_role) = _check_user_login_drone_rover($c, 0, 0, 0);

    my $project_collection_relationship_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_collection_on_drone_run', 'project_relationship')->cvterm_id();
    my $project_md_file_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'rover_collection_filtered_plot_point_cloud', 'project_md_file')->cvterm_id();
    my $earthsense_collection_number_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'earthsense_collection_number', 'project_property')->cvterm_id();

    my $q = "SELECT drone_run.project_id, project_md_file.type_id, collection_number.value
        FROM project AS drone_rover_collection
        JOIN projectprop AS collection_number ON(drone_rover_collection.project_id=collection_number.project_id AND collection_number.type_id=$earthsense_collection_number_cvterm_id)
        JOIN project_relationship AS drone_rover_collection_rel ON(drone_rover_collection.project_id=drone_rover_collection_rel.subject_project_id AND drone_rover_collection_rel.type_id=$project_collection_relationship_type_id)
        JOIN project AS drone_run ON(drone_run.project_id=drone_rover_collection_rel.object_project_id)
        JOIN phenome.project_md_file AS project_md_file ON(drone_rover_collection.project_id=project_md_file.project_id)
        JOIN metadata.md_files AS md_file ON(md_file.file_id=project_md_file.file_id)
        WHERE project_md_file.type_id = $project_md_file_cvterm_id;";

    #print STDERR Dumper $q;
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute();

    my %unique_drone_runs;
    while (my ($drone_run_project_id, $project_md_file_type_id, $collection_number) = $h->fetchrow_array()) {
        $unique_drone_runs{$drone_run_project_id}->{$collection_number}++;
        $unique_drone_runs{$drone_run_project_id}->{total_plot_point_cloud_count}++;
    }
    $h = undef;
    # print STDERR Dumper \%unique_drone_runs;

    $c->stash->{rest} = { data => \%unique_drone_runs };
}

sub _check_user_login_drone_rover {
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
