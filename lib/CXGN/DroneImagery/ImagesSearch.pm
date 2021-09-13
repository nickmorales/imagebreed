package CXGN::DroneImagery::ImagesSearch;

=head1 NAME

CXGN::DroneImagery::ImagesSearch - an object to handle searching for raw drone imagery uploaded

=head1 USAGE

my $images_search = CXGN::DroneImagery::ImagesSearch->new({
    bcs_schema=>$schema,
    project_image_type_id=>$project_image_type_id,
    project_image_type_id_list=>$project_image_type_id_list,
    drone_run_project_id_list=>\@drone_run_project_ids,
    drone_run_project_name_list=>\@drone_run_project_names,
    drone_run_band_project_id_list=>\@drone_run_band_project_ids,
    stock_id_list=>\@stock_ids,
    image_id_list=>\@image_ids,
    accession_list=>\@accession_ids,
    accession_name_list=>\@accessions,
    location_list=>\@locations,
    program_list=>\@breeding_program_names,
    program_id_list=>\@breeding_programs_ids,
    year_list=>\@years,
    trial_type_list=>\@trial_types,
    trial_id_list=>\@trial_ids,
    trial_name_list=>\@trial_names,
    trial_name_is_exact=>1
});
my ($result, $total_count) = $images_search->search();

=head1 DESCRIPTION


=head1 AUTHORS

=cut

use strict;
use warnings;
use Moose;
use Try::Tiny;
use Data::Dumper;
use SGN::Model::Cvterm;
use CXGN::Calendar;
use JSON;

has 'bcs_schema' => ( isa => 'Bio::Chado::Schema',
    is => 'rw',
    required => 1,
);

has 'project_image_type_id' => (
    isa => 'Int|Undef',
    is => 'rw',
);

has 'project_image_type_id_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'image_id_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'drone_run_project_id_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'drone_run_project_name_list' => (
    isa => 'ArrayRef[Str]|Undef',
    is => 'rw',
);

has 'drone_run_band_project_id_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'program_list' => (
    isa => 'ArrayRef[Str]|Undef',
    is => 'rw',
);

has 'program_id_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'stock_id_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'location_list' => (
    isa => 'ArrayRef[Str]|Undef',
    is => 'rw',
);

has 'location_id_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'year_list' => (
    isa => 'ArrayRef[Str]|Undef',
    is => 'rw',
);

has 'trial_type_list' => (
    isa => 'ArrayRef[Str]|Undef',
    is => 'rw',
);

has 'trial_id_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'trial_name_list' => (
    isa => 'ArrayRef[Str]|Undef',
    is => 'rw',
);

has 'folder_id_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'folder_name_list' => (
    isa => 'ArrayRef[Str]|Undef',
    is => 'rw',
);

has 'trial_name_is_exact' => (
    isa => 'Bool|Undef',
    is => 'rw',
    default => 0
);

has 'accession_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'accession_name_list' => (
    isa => 'ArrayRef[Str]|Undef',
    is => 'rw',
);

has 'trial_design_list' => (
    isa => 'ArrayRef[Str]|Undef',
    is => 'rw',
);

has 'trait_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw',
);

has 'trial_has_tissue_samples' => (
    isa => 'Bool|Undef',
    is => 'rw',
    default => 0
);

has 'field_trials_only' => (
    isa => 'Bool|Undef',
    is => 'rw',
    default => 0
);

has 'sort_by' => (
    isa => 'Str|Undef',
    is => 'rw'
);

has 'order_by' => (
    isa => 'Str|Undef',
    is => 'rw'
);

has 'limit' => (
    isa => 'Int|Undef',
    is => 'rw'
);

has 'offset' => (
    isa => 'Int|Undef',
    is => 'rw'
);

sub search {
    my $self = shift;
    my $schema = $self->bcs_schema();
    my $project_image_type_id = $self->project_image_type_id();
    my $project_image_type_id_list = $self->project_image_type_id_list;
    my $image_id_list = $self->image_id_list;
    my $drone_run_project_id_list = $self->drone_run_project_id_list;
    my $drone_run_project_name_list = $self->drone_run_project_name_list;
    my $drone_run_band_project_id_list = $self->drone_run_band_project_id_list;
    my $program_list = $self->program_list;
    my $program_id_list = $self->program_id_list;
    my $stock_id_list = $self->stock_id_list;
    my $location_list = $self->location_list;
    my $location_id_list = $self->location_id_list;
    my $year_list = $self->year_list;
    my $trial_type_list = $self->trial_type_list;
    my $trial_id_list = $self->trial_id_list;
    my $trial_name_list = $self->trial_name_list;
    my $folder_id_list = $self->folder_id_list;
    my $folder_name_list = $self->folder_name_list;
    my $trial_design_list = $self->trial_design_list;
    my $trial_name_is_exact = $self->trial_name_is_exact;
    my $accession_list = $self->accession_list;
    my $accession_name_list = $self->accession_name_list;
    my $trial_has_tissue_samples = $self->trial_has_tissue_samples;
    my $trait_list = $self->trait_list;
    my $limit = $self->limit;
    my $offset = $self->offset;
    my $sort_by = $self->sort_by;
    my $order_by = $self->order_by;

    my $accession_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'accession', 'stock_type')->cvterm_id();
    my $breeding_program_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'breeding_program', 'project_property')->cvterm_id();
    my $breeding_program_trial_relationship_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'breeding_program_trial_relationship', 'project_relationship')->cvterm_id();
    my $drone_run_trial_relationship_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_on_field_trial', 'project_relationship')->cvterm_id();
    my $drone_run_band_drone_run_relationship_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_on_drone_run', 'project_relationship')->cvterm_id();
    my $trial_folder_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'trial_folder', 'project_property')->cvterm_id();
    my $project_start_date_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'project_start_date', 'project_property')->cvterm_id();
    my $drone_run_project_type_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_project_type', 'project_property')->cvterm_id();
    my $drone_run_project_averaged_temperature_gdd_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_averaged_temperature_growing_degree_days', 'project_property')->cvterm_id();
    my $drone_run_related_time_cvterms_json_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_related_time_cvterms_json', 'project_property')->cvterm_id();
    my $drone_run_band_rotate_angle_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_rotate_angle', 'project_property')->cvterm_id();
    my $drone_run_band_cropped_polygon_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_cropped_polygon', 'project_property')->cvterm_id();
    my $drone_run_band_background_removed_tgi_threshold_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_background_removed_tgi_threshold', 'project_property')->cvterm_id();
    my $drone_run_band_background_removed_vari_threshold_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_background_removed_vari_threshold', 'project_property')->cvterm_id();
    my $drone_run_band_background_removed_ndvi_threshold_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_background_removed_ndvi_threshold', 'project_property')->cvterm_id();
    my $drone_run_band_background_removed_threshold_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_background_removed_threshold', 'project_property')->cvterm_id();
    my $drone_run_band_plot_polygons_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_plot_polygons', 'project_property')->cvterm_id();
    my $drone_run_band_plot_polygons_phenotype_margins_json_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_plot_polygons_phenotype_margins_json', 'project_property')->cvterm_id();
    my $cross_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'cross', 'stock_type')->cvterm_id();
    my $location_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'project location', 'project_property')->cvterm_id();
    my $year_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'project year', 'project_property')->cvterm_id();
    my $design_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'design', 'project_property')->cvterm_id();
    my $harvest_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'project_harvest_date', 'project_property')->cvterm_id();
    my $planting_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'project_planting_date', 'project_property')->cvterm_id();
    my $process_indicator_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_standard_process_in_progress', 'project_property')->cvterm_id();
    my $processed_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_standard_process_completed', 'project_property')->cvterm_id();
    my $processed_extended_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_standard_process_extended_completed', 'project_property')->cvterm_id();
    my $processed_vi_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_standard_process_vi_completed', 'project_property')->cvterm_id();
    my $phenotypes_processed_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_standard_process_phenotype_calculation_in_progress', 'project_property')->cvterm_id();
    my $drone_run_band_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_band_project_type', 'project_property')->cvterm_id();
    my $project_has_tissue_sample_entries = SGN::Model::Cvterm->get_cvterm_row($schema, 'project_has_tissue_sample_entries', 'project_property')->cvterm_id();
    my $genotyping_facility_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'genotyping_facility', 'project_property')->cvterm_id();
    my $genotyping_facility_submitted_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'genotyping_facility_submitted', 'project_property')->cvterm_id();
    my $genotyping_facility_status_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'genotyping_facility_status', 'project_property')->cvterm_id();
    my $genotyping_plate_format_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'genotyping_plate_format', 'project_property')->cvterm_id();
    my $genotyping_plate_sample_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'genotyping_plate_sample_type', 'project_property')->cvterm_id();
    my $genotyping_facility_plate_id_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'genotyping_facility_plate_id', 'project_property')->cvterm_id();
    my $calendar_funcs = CXGN::Calendar->new({});

    my $project_type_cv_id = $schema->resultset("Cv::Cv")->find( { name => "project_type" } )->cv_id();
    my $project_type_rs = $schema->resultset("Cv::Cvterm")->search( { cv_id => $project_type_cv_id } );
    my %trial_types;
    while ( my $row = $project_type_rs->next() ) {
        $trial_types{ $row->cvterm_id } = $row->name();
    }
    my $trial_types_sql = join ("," , keys %trial_types);

    my %locations;
    my $location_rs = $schema->resultset("NaturalDiversity::NdGeolocation")->search( {} );
    while ( my $row = $location_rs->next() ) {
        $locations{ $row->nd_geolocation_id() } = $row->description();
    }

    my @where_clause;

    if ($drone_run_band_project_id_list && scalar(@$drone_run_band_project_id_list)>0) {
        my $sql = join ("," , @$drone_run_band_project_id_list);
        push @where_clause, "drone_run_band.project_id in ($sql)";
    }

    if ($drone_run_project_id_list && scalar(@$drone_run_project_id_list)>0) {
        my $sql = join ("," , @$drone_run_project_id_list);
        push @where_clause, "drone_run.project_id in ($sql)";
    }

    if ($image_id_list && scalar(@$image_id_list)>0) {
        my $sql = join ("," , @$image_id_list);
        push @where_clause, "md_image.image_id in ($sql)";
    }

    if ($trial_has_tissue_samples){
        push @where_clause, "trial_has_tissue_samples.value IS NOT NULL";
    }

    if ($project_image_type_id){
        push @where_clause, "project_image.type_id = $project_image_type_id";
    }

    if ($project_image_type_id_list && scalar(@$project_image_type_id_list)>0) {
        my $sql = join ("," , @$project_image_type_id_list);
        push @where_clause, "project_image.type_id in ($sql)";
    }

    if ($stock_id_list && scalar(@$stock_id_list)>0) {
        my $sql = join ("," , @$stock_id_list);
        push @where_clause, "stock.stock_id in ($sql)";
    }

    if ($program_id_list && scalar(@$program_id_list)>0) {
        my $sql = join ("," , @$program_id_list);
        push @where_clause, "breeding_program.project_id in ($sql)";
    }
    if ($program_list && scalar(@$program_list)>0) {
        my $sql = join ("','" , @$program_list);
        my $program_sql = "'" . $sql . "'";
        push @where_clause, "breeding_program.name in ($program_sql)";
    }
    if ($year_list && scalar(@$year_list)>0) {
        my $sql = join ("','" , @$year_list);
        my $year_sql = "'" . $sql . "'";
        push @where_clause, "year.value in ($year_sql)";
    }
    if ($trial_type_list && scalar(@$trial_type_list)>0) {
        my $sql = join ("','" , @$trial_type_list);
        my $trial_type_sql = "'" . $sql . "'";
        push @where_clause, "trial_type_name.name in ($trial_type_sql)";
    }
    if ($trial_id_list && scalar(@$trial_id_list)>0) {
        my $sql = join ("," , @$trial_id_list);
        push @where_clause, "study.project_id in ($sql)";
    }
    if ($trial_name_is_exact){
        if ($trial_name_list && scalar(@$trial_name_list)>0) {
            my $sql = join ("','" , @$trial_name_list);
            my $trial_sql = "'" . $sql . "'";
            push @where_clause, "study.name in ($trial_sql)";
        }
    } else {
        if ($trial_name_list && scalar(@$trial_name_list)>0) {
            my @or_clause;
            foreach (@$trial_name_list){
                push @or_clause, "study.name LIKE '%".$_."%'";
            }
            my $sql = join (" OR " , @or_clause);
            push @where_clause, "($sql)";
        }
    }
    if ($folder_id_list && scalar(@$folder_id_list)>0) {
        my $sql = join ("," , @$folder_id_list);
        push @where_clause, "folder.project_id in ($sql)";
    }
    if ($folder_name_list && scalar(@$folder_name_list)>0) {
        my $sql = join ("','" , @$folder_name_list);
        my $folder_sql = "'" . $sql . "'";
        push @where_clause, "folder.name in ($folder_sql)";
    }
    if ($trial_design_list && scalar(@$trial_design_list)>0) {
        my $sql = join ("','" , @$trial_design_list);
        my $design_sql = "'" . $sql . "'";
        push @where_clause, "design.value in ($design_sql)";
    }
    if ($location_id_list && scalar(@$location_id_list)>0) {
        my $sql = join ("','" , @$location_id_list);
        my $location_sql = "'" . $sql . "'";
        push @where_clause, "location.value in ($location_sql)";
    }
    my $accession_join = '';
    if ( ($accession_list && scalar(@$accession_list)>0) || ($accession_name_list && scalar(@$accession_name_list)>0) ) {
        $accession_join = " JOIN nd_experiment_project ON(study.project_id=nd_experiment_project.project_id) JOIN nd_experiment USING(nd_experiment_id) JOIN nd_experiment_stock USING(nd_experiment_id) JOIN stock AS obs_unit ON(nd_experiment_stock.stock_id=obs_unit.stock_id) JOIN stock_relationship ON(stock_relationship.subject_id=obs_unit.stock_id) JOIN stock AS accession ON(stock_relationship.object_id=accession.stock_id AND accession.type_id=$accession_cvterm_id) ";
    }
    if ($accession_list && scalar(@$accession_list)>0) {
        my $sql = join ("," , @$accession_list);
        push @where_clause, "accession.stock_id in ($sql)";
    }
    if ($accession_name_list && scalar(@$accession_name_list)>0) {
        my $sql = join ("','" , @$accession_name_list);
        my $accession_sql = "'" . $sql . "'";
        push @where_clause, "accession.uniquename in ($accession_sql)";
    }

    my $trait_join = '';
    if ($trait_list && scalar(@$trait_list)>0) {
        my $sql = join ("," , @$trait_list);
        push @where_clause, "phenotype.cvalue_id in ($sql)";
        $trait_join = " JOIN nd_experiment_project ON(study.project_id=nd_experiment_project.project_id)
            JOIN nd_experiment AS trial_experiment ON(trial_experiment.nd_experiment_id=nd_experiment_project.nd_experiment_id)
            JOIN nd_experiment_stock ON(trial_experiment.nd_experiment_id=nd_experiment_stock.nd_experiment_id)
            JOIN nd_experiment_phenotype_bridge ON(nd_experiment_phenotype_bridge.stock_id=nd_experiment_stock.stock_id)
            JOIN phenotype USING(phenotype_id) ";
    }
    push @where_clause, "md_image.obsolete = 'f'";

    my $where_clause = scalar(@where_clause)>0 ? " WHERE " . (join (" AND " , @where_clause)) : '';

    my $q = "SELECT drone_run_band.project_id, drone_run_band.name, drone_run_band.description, drone_run_band_type.value, drone_run_band_rotate_angle.value, drone_run_band_cropped_polygon.value, drone_run_band_removed_background_tgi_threshold.value, drone_run_band_removed_background_vari_threshold.value, drone_run_band_removed_background_ndvi_threshold.value, drone_run_band_removed_background_threshold.value, drone_run_band_plot_polygons.value, drone_run.project_id, drone_run.name, drone_run.description, drone_run_type.value, drone_run_date.value, drone_run_averaged_temperature_gdd.value, drone_run_related_time_cvterm_json.value, drone_run_indicator.value, drone_run_phenotypes_indicator.value, drone_run_processed.value, drone_run_processed_extended.value, drone_run_processed_vi.value, drone_run_phenotype_plot_margins.value, study.name, study.project_id, study.description, folder.name, folder.project_id, folder.description, trial_type_name.cvterm_id, trial_type_name.name, year.value, location.value, breeding_program.name, breeding_program.project_id, breeding_program.description, harvest_date.value, planting_date.value, design.value, project_image_type.cvterm_id, project_image_type.name, md_image.image_id, md_image.description, md_image.original_filename, md_image.sp_person_id, md_image.create_date, md_image.modified_date, md_image.md5sum, image_person.username, image_person.first_name, image_person.last_name, stock.stock_id, stock.uniquename, stock.type_id, stock_image.stock_image_id, count(study.project_id) OVER() AS full_count ";
    $q .= "FROM project AS drone_run_band
        JOIN projectprop AS drone_run_band_type ON(drone_run_band.project_id=drone_run_band_type.project_id AND drone_run_band_type.type_id=$drone_run_band_type_cvterm_id)
        LEFT JOIN projectprop AS drone_run_band_rotate_angle ON(drone_run_band.project_id=drone_run_band_rotate_angle.project_id AND drone_run_band_rotate_angle.type_id=$drone_run_band_rotate_angle_type_id)
        LEFT JOIN projectprop AS drone_run_band_cropped_polygon ON(drone_run_band.project_id=drone_run_band_cropped_polygon.project_id AND drone_run_band_cropped_polygon.type_id=$drone_run_band_cropped_polygon_type_id)
        LEFT JOIN projectprop AS drone_run_band_removed_background_tgi_threshold ON(drone_run_band.project_id=drone_run_band_removed_background_tgi_threshold.project_id AND drone_run_band_removed_background_tgi_threshold.type_id=$drone_run_band_background_removed_tgi_threshold_type_id)
        LEFT JOIN projectprop AS drone_run_band_removed_background_vari_threshold ON(drone_run_band.project_id=drone_run_band_removed_background_vari_threshold.project_id AND drone_run_band_removed_background_vari_threshold.type_id=$drone_run_band_background_removed_vari_threshold_type_id)
        LEFT JOIN projectprop AS drone_run_band_removed_background_ndvi_threshold ON(drone_run_band.project_id=drone_run_band_removed_background_ndvi_threshold.project_id AND drone_run_band_removed_background_ndvi_threshold.type_id=$drone_run_band_background_removed_ndvi_threshold_type_id)
        LEFT JOIN projectprop AS drone_run_band_removed_background_threshold ON(drone_run_band.project_id=drone_run_band_removed_background_threshold.project_id AND drone_run_band_removed_background_threshold.type_id=$drone_run_band_background_removed_threshold_type_id)
        LEFT JOIN projectprop AS drone_run_band_plot_polygons ON(drone_run_band.project_id=drone_run_band_plot_polygons.project_id AND drone_run_band_plot_polygons.type_id=$drone_run_band_plot_polygons_type_id)
        JOIN project_relationship AS drone_run_band_rel ON(drone_run_band.project_id=drone_run_band_rel.subject_project_id AND drone_run_band_rel.type_id=$drone_run_band_drone_run_relationship_id)
        JOIN project AS drone_run ON(drone_run.project_id=drone_run_band_rel.object_project_id)
        LEFT JOIN projectprop AS drone_run_type ON(drone_run.project_id=drone_run_type.project_id AND drone_run_type.type_id=$drone_run_project_type_type_id)
        JOIN projectprop AS drone_run_date ON(drone_run.project_id=drone_run_date.project_id AND drone_run_date.type_id=$project_start_date_type_id)
        JOIN projectprop AS drone_run_design ON(drone_run.project_id=drone_run_design.project_id AND drone_run_design.type_id=$design_cvterm_id AND drone_run_design.value='drone_run')
        LEFT JOIN projectprop AS drone_run_averaged_temperature_gdd ON(drone_run.project_id=drone_run_averaged_temperature_gdd.project_id AND drone_run_averaged_temperature_gdd.type_id=$drone_run_project_averaged_temperature_gdd_type_id)
        LEFT JOIN projectprop AS drone_run_related_time_cvterm_json ON(drone_run_related_time_cvterm_json.project_id = drone_run.project_id AND drone_run_related_time_cvterm_json.type_id = $drone_run_related_time_cvterms_json_type_id)
        LEFT JOIN projectprop AS drone_run_indicator ON(drone_run_indicator.project_id = drone_run.project_id AND drone_run_indicator.type_id = $process_indicator_cvterm_id)
        LEFT JOIN projectprop AS drone_run_phenotypes_indicator ON(drone_run_phenotypes_indicator.project_id = drone_run.project_id AND drone_run_phenotypes_indicator.type_id = $phenotypes_processed_cvterm_id)
        LEFT JOIN projectprop AS drone_run_processed ON(drone_run_processed.project_id = drone_run.project_id AND drone_run_processed.type_id = $processed_cvterm_id)
        LEFT JOIN projectprop AS drone_run_processed_extended ON(drone_run_processed_extended.project_id = drone_run.project_id AND drone_run_processed_extended.type_id = $processed_extended_cvterm_id)
        LEFT JOIN projectprop AS drone_run_processed_vi ON(drone_run_processed_vi.project_id = drone_run.project_id AND drone_run_processed_vi.type_id = $processed_vi_cvterm_id)
        LEFT JOIN projectprop AS drone_run_phenotype_plot_margins ON(drone_run_phenotype_plot_margins.project_id = drone_run.project_id AND drone_run_phenotype_plot_margins.type_id = $drone_run_band_plot_polygons_phenotype_margins_json_type_id)
        JOIN project_relationship AS drone_run_rel ON(drone_run.project_id=drone_run_rel.subject_project_id AND drone_run_rel.type_id=$drone_run_trial_relationship_id)
        JOIN project AS study ON(study.project_id=drone_run_rel.object_project_id)
        JOIN project_relationship AS bp_rel ON(study.project_id=bp_rel.subject_project_id AND bp_rel.type_id=$breeding_program_trial_relationship_id)
        JOIN project AS breeding_program ON(bp_rel.object_project_id=breeding_program.project_id)
        JOIN phenome.project_md_image AS project_image ON(drone_run_band.project_id=project_image.project_id)
        JOIN cvterm AS project_image_type ON(project_image_type.cvterm_id=project_image.type_id)
        JOIN metadata.md_image AS md_image ON(project_image.image_id=md_image.image_id)
        LEFT JOIN phenome.stock_image AS stock_image ON(stock_image.image_id=md_image.image_id)
        LEFT JOIN stock ON(stock_image.stock_id=stock.stock_id)
        JOIN sgn_people.sp_person AS image_person ON(md_image.sp_person_id=image_person.sp_person_id)
        LEFT JOIN project_relationship AS folder_rel ON(study.project_id=folder_rel.subject_project_id AND folder_rel.type_id=$trial_folder_cvterm_id)
        LEFT JOIN project AS folder ON(folder_rel.object_project_id=folder.project_id)
        LEFT JOIN projectprop ON(study.project_id=projectprop.project_id AND projectprop.type_id IN ($trial_types_sql))
        LEFT JOIN cvterm AS trial_type_name ON(projectprop.type_id=trial_type_name.cvterm_id)
        LEFT JOIN cv AS project_type ON(trial_type_name.cv_id=project_type.cv_id AND project_type.name='project_type')
        LEFT JOIN projectprop AS year ON(study.project_id=year.project_id AND year.type_id=$year_cvterm_id)
        LEFT JOIN projectprop AS location ON(study.project_id=location.project_id AND location.type_id=$location_cvterm_id)
        LEFT JOIN projectprop AS harvest_date ON(study.project_id=harvest_date.project_id AND harvest_date.type_id=$harvest_cvterm_id)
        LEFT JOIN projectprop AS planting_date ON(study.project_id=planting_date.project_id AND planting_date.type_id=$planting_cvterm_id)
        LEFT JOIN projectprop AS design ON(study.project_id=design.project_id AND design.type_id=$design_cvterm_id)
        $accession_join
        $trait_join
        $where_clause
        GROUP BY(drone_run_band.project_id, drone_run_band.name, drone_run_band.description, drone_run_band_type.value, drone_run_band_rotate_angle.value, drone_run_band_cropped_polygon.value, drone_run_band_removed_background_tgi_threshold.value, drone_run_band_removed_background_vari_threshold.value, drone_run_band_removed_background_ndvi_threshold.value, drone_run_band_removed_background_threshold.value, drone_run_band_plot_polygons.value, drone_run.project_id, drone_run.name, drone_run.description, drone_run_type.value, drone_run_date.value, drone_run_averaged_temperature_gdd.value, drone_run_related_time_cvterm_json.value, drone_run_indicator.value, drone_run_phenotypes_indicator.value, drone_run_processed.value, drone_run_processed_extended.value, drone_run_processed_vi.value, drone_run_phenotype_plot_margins.value, study.name, study.project_id, study.description, folder.name, folder.project_id, folder.description, trial_type_name.cvterm_id, trial_type_name.name, year.value, location.value, breeding_program.name, breeding_program.project_id, breeding_program.description, harvest_date.value, planting_date.value, design.value, project_image_type.cvterm_id, project_image_type.name, md_image.image_id, md_image.description, md_image.original_filename, md_image.sp_person_id, md_image.create_date, md_image.modified_date, md_image.md5sum, image_person.username, image_person.first_name, image_person.last_name, stock.stock_id, stock.uniquename, stock.type_id, stock_image.stock_image_id)
        ORDER BY study.name, md_image.image_id;";

    #print STDERR Dumper $q;
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute();

    my @result;
    my $total_count = 0;
    my $subtract_count = 0;
    while (my ($drone_run_band_project_id, $drone_run_band_project_name, $drone_run_band_description, $drone_run_band_type, $drone_run_band_rotate_angle, $drone_run_band_cropped_polygon, $drone_run_band_removed_background_tgi_threshold, $drone_run_band_removed_background_vari_threshold, $drone_run_band_removed_background_ndvi_threshold, $drone_run_band_removed_background_threshold, $drone_run_band_plot_polygons, $drone_run_project_id, $drone_run_project_name, $drone_run_project_description, $drone_run_type, $drone_run_date, $drone_run_averaged_temperature_gdd, $drone_run_related_time_cvterm_json, $drone_run_indicator, $drone_run_phenotypes_indicator, $drone_run_processed, $drone_run_processed_extended, $drone_run_processed_vi, $drone_run_phenotype_plot_margins_json, $study_name, $study_id, $study_description, $folder_name, $folder_id, $folder_description, $trial_type_id, $trial_type_name, $year, $location_id, $breeding_program_name, $breeding_program_id, $breeding_program_description, $harvest_date, $planting_date, $design, $project_image_type_id, $project_image_type_name, $image_id, $image_description, $image_original_filename, $image_person_id, $image_create_date, $image_modified_date, $image_md5sum, $username, $first_name, $last_name, $stock_id, $stock_uniquename, $stock_type_id, $stock_image_id, $full_count) = $h->fetchrow_array()) {
        my $location_name = $location_id ? $locations{$location_id} : '';
        my $project_harvest_date = $harvest_date ? $calendar_funcs->display_start_date($harvest_date) : '';
        my $project_planting_date = $planting_date ? $calendar_funcs->display_start_date($planting_date) : '';
        my $drone_run_related_time_cvterm_hash = $drone_run_related_time_cvterm_json ? decode_json $drone_run_related_time_cvterm_json : {};
        my $drone_run_phenotype_plot_margins = $drone_run_phenotype_plot_margins_json ? decode_json $drone_run_phenotype_plot_margins_json : {};

        push @result, {
            drone_run_band_project_id => $drone_run_band_project_id,
            drone_run_band_project_name => $drone_run_band_project_name,
            drone_run_band_project_description => $drone_run_band_description,
            drone_run_band_project_type => $drone_run_band_type,
            drone_run_band_rotate_angle => $drone_run_band_rotate_angle,
            drone_run_band_cropped_polygon => $drone_run_band_cropped_polygon,
            drone_run_band_removed_background_tgi_threshold => $drone_run_band_removed_background_tgi_threshold,
            drone_run_band_removed_background_vari_threshold => $drone_run_band_removed_background_vari_threshold,
            drone_run_band_removed_background_ndvi_threshold => $drone_run_band_removed_background_ndvi_threshold,
            drone_run_band_removed_background_threshold => $drone_run_band_removed_background_threshold,
            drone_run_band_plot_polygons => $drone_run_band_plot_polygons,
            drone_run_project_id => $drone_run_project_id,
            drone_run_project_name => $drone_run_project_name,
            drone_run_project_description => $drone_run_project_description,
            drone_run_date => $drone_run_date,
            drone_run_averaged_temperature_gdd => $drone_run_averaged_temperature_gdd,
            drone_run_related_time_cvterm_json => $drone_run_related_time_cvterm_hash,
            drone_run_type => $drone_run_type,
            drone_run_indicator => $drone_run_indicator,
            drone_run_processed => $drone_run_processed,
            drone_run_processed_minimal_vi => $drone_run_processed_vi,
            drone_run_processed_extended => $drone_run_processed_extended,
            drone_run_phenotypes_indicator => $drone_run_phenotypes_indicator,
            drone_run_phenotype_plot_margins => $drone_run_phenotype_plot_margins,
            trial_id => $study_id,
            trial_name => $study_name,
            description => $study_description,
            folder_id => $folder_id,
            folder_name => $folder_name,
            folder_description => $folder_description,
            trial_type => $trial_type_name,
            year => $year,
            location_id => $location_id,
            location_name => $location_name,
            breeding_program_id => $breeding_program_id,
            breeding_program_name => $breeding_program_name,
            breeding_program_description => $breeding_program_description,
            project_harvest_date => $project_harvest_date,
            project_planting_date => $project_planting_date,
            design => $design,
            project_image_type_id => $project_image_type_id,
            project_image_type_name => $project_image_type_name,
            image_id => $image_id,
            image_description => $image_description,
            image_original_filename => $image_original_filename,
            image_create_date => $image_create_date,
            image_modified_date => $image_modified_date,
            image_md5sum => $image_md5sum,
            sp_person_id => $image_person_id,
            username => $username,
            first_name => $first_name,
            last_name => $last_name,
            stock_id => $stock_id,
            stock_uniquename => $stock_uniquename,
            stock_type_id => $stock_type_id,
            stock_image_id => $stock_image_id
        };
        $total_count = $full_count;
    }
    #print STDERR Dumper \@result;

    return (\@result, $total_count);
}

1;
