package SGN::Controller::AJAX::TrialMetadata;

use Moose;
use Data::Dumper;
use Bio::Chado::Schema;
use CXGN::Trial;
use CXGN::Trial::TrialLookup;
use Math::Round::Var;
use File::Temp 'tempfile';
use Text::CSV;
use CXGN::Trial::FieldMap;
use JSON;
use CXGN::Phenotypes::PhenotypeMatrix;
use CXGN::Cross;

use CXGN::Phenotypes::TrialPhenotype;
use CXGN::Login;
use CXGN::UploadFile;
use CXGN::Stock::Seedlot;
use CXGN::Stock::Seedlot::Transaction;
use File::Basename qw | basename dirname|;
use File::Slurp qw | read_file |;
use List::MoreUtils qw | :all !before !after |;
use Try::Tiny;
use CXGN::BreederSearch;
use CXGN::Page::FormattingHelpers qw / html_optional_show /;
use SGN::Image;
use CXGN::Trial::TrialLayoutDownload;
use CXGN::Genotype::DownloadFactory;
use POSIX qw | !qsort !bsearch |;
use CXGN::Phenotypes::StorePhenotypes;
use Statistics::Descriptive::Full;
use CXGN::TrialStatus;
use List::Util qw | sum |;
use CXGN::BreedersToolbox::SoilData;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON'  },
   );

has 'schema' => (
		 is       => 'rw',
		 isa      => 'DBIx::Class::Schema',
		 lazy_build => 1,
		);


sub trial : Chained('/') PathPart('ajax/breeders/trial') CaptureArgs(1) {
    my $self = shift;
    my $c = shift;
    my $trial_id = shift;

    my $bcs_schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');
    my $phenome_schema = $c->dbic_schema('CXGN::Phenome::Schema');

    $c->stash->{trial_id} = $trial_id;
    $c->stash->{schema} = $bcs_schema;
    $c->stash->{metadata_schema} = $metadata_schema;
    $c->stash->{phenome_schema} = $phenome_schema;
    $c->stash->{trial} = CXGN::Trial->new({
        bcs_schema => $bcs_schema,
        metadata_schema => $metadata_schema,
        phenome_schema => $phenome_schema,
        trial_id => $trial_id
    });

    if (!$c->stash->{trial}) {
        $c->stash->{rest} = { error => "The specified trial with id $trial_id does not exist" };
        return;
    }

    my $cxgn_project_type_obj = $c->stash->{trial}->get_cxgn_project_type();
    my $cxgn_project_type = $cxgn_project_type_obj->{cxgn_project_type};

    print STDERR Dumper $cxgn_project_type;
    if ($cxgn_project_type ne 'drone_run_project' && $cxgn_project_type ne 'drone_run_band_project') {
        try {
            my %param = ( schema => $bcs_schema, trial_id => $trial_id );
            if ($c->stash->{trial}->get_design_type() eq 'genotyping_plate'){
                $param{experiment_type} = 'genotyping_layout';
            } else {
                $param{experiment_type} = 'field_layout';
            }
            $c->stash->{trial_layout} = CXGN::Trial::TrialLayout->new(\%param);
            # print STDERR "Trial Layout: ".Dumper($c->stash->{trial_layout})."\n";
        }
        catch {
            print STDERR "Trial Layout for $trial_id does not exist. @_\n";
        }
    }

}

=head2 delete_trial_by_file
 Usage:
 Desc:
 Ret:
 Args:
 Side Effects:
 Example:
=cut

sub delete_trial_data : Local() ActionClass('REST');

sub delete_trial_data_GET : Chained('trial') PathPart('delete') Args(1) {
    my $self = shift;
    my $c = shift;
    my $datatype = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'curator', 'curator_access');
    my $schema = $c->stash->{schema};
    my $metadata_schema = $c->stash->{metadata_schema};
    my $phenome_schema = $c->stash->{phenome_schema};

    my $error = "";

    if ($datatype eq 'phenotypes') {
        $error = $c->stash->{trial}->delete_phenotype_metadata($metadata_schema, $phenome_schema);
        $error .= $c->stash->{trial}->delete_phenotype_data($c->config->{basepath}, $c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass});
    }

    elsif ($datatype eq 'layout') {

        my $project_relationship_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_run_on_field_trial', 'project_relationship')->cvterm_id();
        my $drone_image_check_q = "SELECT count(subject_project_id) FROM project_relationship WHERE object_project_id = ? AND type_id = ?;";
        my $drone_image_check_h = $schema->storage->dbh()->prepare($drone_image_check_q);;
        $drone_image_check_h->execute($c->stash->{trial_id}, $project_relationship_type_id);
        my ($drone_run_count) = $drone_image_check_h->fetchrow_array();
        $drone_image_check_h = undef;

        if ($drone_run_count > 0) {
            $c->stash->{rest} = { error => "Please delete the imaging events belonging to this field trial first!" };
            return;
        }

        $error = $c->stash->{trial}->delete_metadata();
        $error .= $c->stash->{trial}->delete_field_layout();
        $error .= $c->stash->{trial}->delete_project_entry();

        my $dbh = $c->dbc->dbh();
        my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
        my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});
    }
    elsif ($datatype eq 'entry') {
        $error = $c->stash->{trial}->delete_project_entry();
    }
    elsif ($datatype eq 'crossing_experiment') {
        $error = $c->stash->{trial}->delete_empty_crossing_experiment();
    }
    else {
        $c->stash->{rest} = { error => "unknown delete action for $datatype" };
        return;
    }
    if ($error) {
        $c->stash->{rest} = { error => $error };
        return;
    }
    $c->stash->{rest} = { message => "Successfully deleted trial data.", success => 1 };
}

sub trial_phenotypes_fully_uploaded : Chained('trial') PathPart('phenotypes_fully_uploaded') Args(0) ActionClass('REST') {};

sub trial_phenotypes_fully_uploaded_GET   {
    my $self = shift;
    my $c = shift;
    my $trial = $c->stash->{trial};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    $c->stash->{rest} = { phenotypes_fully_uploaded => $trial->get_phenotypes_fully_uploaded() };
}

sub trial_phenotypes_fully_uploaded_POST  {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $value = $c->req->param("phenotypes_fully_uploaded");
    my $trial = $c->stash->{trial};
    eval {
        $trial->set_phenotypes_fully_uploaded($value);
    };
    if ($@) {
        $c->stash->{rest} = { error => "An error occurred setting phenotypes_fully_uploaded: $@" };
    }
    else {
        $c->stash->{rest} = { success => 1 };
    }
}

sub trial_details : Chained('trial') PathPart('details') Args(0) ActionClass('REST') {};

sub trial_details_GET   {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = $c->stash->{trial};
    my $planting_date = $trial->get_planting_date();
    my $harvest_date = $trial->get_harvest_date();
    my $get_location_noaa_station_id = $trial->get_location_noaa_station_id();

    $c->stash->{rest} = {
        details => {
            planting_date => $planting_date,
            harvest_date => $harvest_date,
            location_noaa_station_id => $get_location_noaa_station_id
        }
    };

}

sub trial_details_POST  {
    my $self = shift;
    my $c = shift;
    my $trial_id = $c->stash->{trial_id};
    my $trial = $c->stash->{trial};
    my $schema = $c->stash->{schema};
    my $metadata_schema = $c->stash->{metadata_schema};
    my $phenome_schema = $c->stash->{phenome_schema};

    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my @categories = $c->req->param("categories[]");

    my $details = {};
    foreach my $category (@categories) {
        $details->{$category} = $c->req->param("details[$category]");
    }

    if (!%{$details}) {
        $c->stash->{rest} = { error => "No values were edited, so no changes could be made for this trial's details." };
        $c->detach();
    }
    else {
        print STDERR "Here are the deets: " . Dumper($details) . "\n";
    }

    my $program_object = CXGN::BreedersToolbox::Projects->new( { schema => $schema });
    my $program_ref = $program_object->get_breeding_programs_by_trial($trial_id);

    my $program_array = @$program_ref[0];
    my $breeding_program_name = @$program_array[1];

    # set each new detail that is defined
    #print STDERR Dumper $details;
    eval {
        if ($details->{name}) { $trial->set_name($details->{name}); }
        if ($details->{breeding_program}) { $trial->set_breeding_program($details->{breeding_program}); }
        if ($details->{location}) { $trial->set_location($details->{location}); }
        if ($details->{year}) { $trial->set_year($details->{year}); }
        if ($details->{type}) { $trial->set_project_type($details->{type}); }
        if ($details->{planting_date}) {
            if ($details->{planting_date} eq 'remove') { $trial->remove_planting_date($trial->get_planting_date()); }
            else { $trial->set_planting_date($details->{planting_date}); }
        }
        if ($details->{harvest_date}) {
            if ($details->{harvest_date} eq 'remove') { $trial->remove_harvest_date($trial->get_harvest_date()); }
            else { $trial->set_harvest_date($details->{harvest_date}); }
        }
        if ($details->{description}) { $trial->set_description($details->{description}); }
        if ($details->{field_size}) { $trial->set_field_size($details->{field_size}); }
        if ($details->{plot_width}) { $trial->set_plot_width($details->{plot_width}); }
        if ($details->{plot_length}) { $trial->set_plot_length($details->{plot_length}); }
        if ($details->{plan_to_genotype}) { $trial->set_field_trial_is_planned_to_be_genotyped($details->{plan_to_genotype}); }
        if ($details->{plan_to_cross}) { $trial->set_field_trial_is_planned_to_cross($details->{plan_to_cross}); }
    };

    if ($details->{company}) { $trial->set_private_company($details->{company}); }
    if ($details->{plate_format}) { $trial->set_genotyping_plate_format($details->{plate_format}); }
    if ($details->{plate_sample_type}) { $trial->set_genotyping_plate_sample_type($details->{plate_sample_type}); }
    if ($details->{facility}) { $trial->set_genotyping_facility($details->{facility}); }
    if ($details->{facility_submitted}) { $trial->set_genotyping_facility_submitted($details->{facility_submitted}); }
    if ($details->{facility_status}) { $trial->set_genotyping_facility_status($details->{set_genotyping_facility_status}); }
    if ($details->{raw_data_link}) { $trial->set_raw_data_link($details->{raw_data_link}); }

    if ($@) {
        $c->stash->{rest} = { error => "An error occurred setting the new trial details: $@" };
    }
    else {
        $c->stash->{rest} = { success => 1 };
    }
}

sub traits_assayed : Chained('trial') PathPart('traits_assayed') Args(0) {
    my $self = shift;
    my $c = shift;
    my $stock_type = $c->req->param('stock_type');
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my @traits_assayed  = $c->stash->{trial}->get_traits_assayed($stock_type);
    $c->stash->{rest} = { traits_assayed => \@traits_assayed };
}

sub trait_phenotypes : Chained('trial') PathPart('trait_phenotypes') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);
    my $schema = $c->stash->{schema};

    #get userinfo from db
    my $display = $c->req->param('display');
    my $trait = $c->req->param('trait');
    my $phenotypes_search = CXGN::Phenotypes::PhenotypeMatrix->new(
        bcs_schema=> $schema,
        search_type => "MaterializedViewTable",
        data_level => $display,
        trait_list=> [$trait],
        trial_list => [$c->stash->{trial_id}]
    );
    my @data = $phenotypes_search->get_phenotype_matrix();
    $c->stash->{rest} = {
      status => "success",
      data => \@data
   };
}

sub phenotype_summary : Chained('trial') PathPart('phenotypes') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $schema = $c->stash->{schema};
    my $round = Math::Round::Var->new(0.01);
    my $dbh = $c->dbc->dbh();
    my $trial_id = $c->stash->{trial_id};
    my $display = $c->req->param('display');
    my $trial_stock_type = $c->req->param('trial_stock_type');
    my $select_clause_additional = '';
    my $group_by_additional = '';
    my $order_by_additional = '';
    my $stock_type_id;
    my $rel_type_id;
    my $total_complete_number;
    if ($display eq 'plots') {
        $stock_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot', 'stock_type')->cvterm_id();
        $rel_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot_of', 'stock_relationship')->cvterm_id();
        my $plots = $c->stash->{trial}->get_plots();
        $total_complete_number = scalar (@$plots);
    }
    if ($display eq 'plants') {
        $stock_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plant', 'stock_type')->cvterm_id();
        $rel_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plant_of', 'stock_relationship')->cvterm_id();
        my $plants = $c->stash->{trial}->get_plants();
        $total_complete_number = scalar (@$plants);
    }
    if ($display eq 'subplots') {
        $stock_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'subplot', 'stock_type')->cvterm_id();
        $rel_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'subplot_of', 'stock_relationship')->cvterm_id();
        my $subplots = $c->stash->{trial}->get_subplots();
        $total_complete_number = scalar (@$subplots);
    }
    if ($display eq 'tissue_samples') {
        $stock_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'tissue_sample', 'stock_type')->cvterm_id();
        $rel_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'tissue_sample_of', 'stock_relationship')->cvterm_id();
        my $subplots = $c->stash->{trial}->get_subplots();
        $total_complete_number = scalar (@$subplots);
    }
    my $stocks_per_accession;
    if ($display eq 'plots_accession') {
        $stock_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot', 'stock_type')->cvterm_id();
        $rel_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot_of', 'stock_relationship')->cvterm_id();
        $select_clause_additional = ', accession.uniquename, accession.stock_id';
        $group_by_additional = ', accession.stock_id, accession.uniquename';
        $stocks_per_accession = $c->stash->{trial}->get_plots_per_accession();
        $order_by_additional = ' ,accession.uniquename DESC';
    }
    if ($display eq 'plants_accession') {
        $stock_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plant', 'stock_type')->cvterm_id();
        $rel_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plant_of', 'stock_relationship')->cvterm_id();
        $select_clause_additional = ', accession.uniquename, accession.stock_id';
        $group_by_additional = ', accession.stock_id, accession.uniquename';
        $stocks_per_accession = $c->stash->{trial}->get_plants_per_accession();
        $order_by_additional = ' ,accession.uniquename DESC';
    }
    if ($display eq 'tissue_samples_accession') {
        $stock_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'tissue_sample', 'stock_type')->cvterm_id();
        $rel_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'tissue_sample_of', 'stock_relationship')->cvterm_id();
        $select_clause_additional = ', accession.uniquename, accession.stock_id';
        $group_by_additional = ', accession.stock_id, accession.uniquename';
        $stocks_per_accession = $c->stash->{trial}->get_plants_per_accession();
        $order_by_additional = ' ,accession.uniquename DESC';
    }
    if ($display eq 'analysis_instance') {
        $stock_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analysis_instance', 'stock_type')->cvterm_id();
        $rel_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analysis_of', 'stock_relationship')->cvterm_id();
        # my $plots = $c->stash->{trial}->get_plots();
        # $total_complete_number = scalar (@$plots);
    }
    my $accesion_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'accession', 'stock_type')->cvterm_id();
    my $family_name_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'family_name', 'stock_type')->cvterm_id();
    my $cross_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'cross', 'stock_type')->cvterm_id();
    my $trial_stock_type_id;
    if ($trial_stock_type eq 'family_name') {
        $trial_stock_type_id = $family_name_type_id;
    } elsif ($trial_stock_type eq 'cross') {
        $trial_stock_type_id = $cross_type_id;
    } else {
        $trial_stock_type_id = $accesion_type_id;
    }

    my $q = "SELECT (((cvterm.name::text || '|'::text) || db.name::text) || ':'::text) || dbxref.accession::text AS trait,
        cvterm.cvterm_id,
        count(phenotype.value),
        to_char(avg(phenotype.value::real), 'FM999990.990'),
        to_char(max(phenotype.value::real), 'FM999990.990'),
        to_char(min(phenotype.value::real), 'FM999990.990'),
        to_char(stddev(phenotype.value::real), 'FM999990.990')
        $select_clause_additional
        FROM cvterm
            JOIN phenotype ON (cvterm_id=cvalue_id)
            JOIN nd_experiment_phenotype_bridge ON(nd_experiment_phenotype_bridge.phenotype_id=phenotype.phenotype_id)
            JOIN stock as plot ON(plot.stock_id=nd_experiment_phenotype_bridge.stock_id)
            JOIN stock_relationship on (plot.stock_id = stock_relationship.subject_id)
            JOIN stock as accession on (accession.stock_id = stock_relationship.object_id)
            JOIN dbxref ON cvterm.dbxref_id = dbxref.dbxref_id JOIN db ON dbxref.db_id = db.db_id
        WHERE project_id=?
            AND phenotype.value~?
            AND stock_relationship.type_id=$rel_type_id
            AND plot.type_id=$stock_type_id
            AND accession.type_id=$trial_stock_type_id
        GROUP BY (((cvterm.name::text || '|'::text) || db.name::text) || ':'::text) || dbxref.accession::text, cvterm.cvterm_id $group_by_additional
        ORDER BY cvterm.name ASC
        $order_by_additional;";
    print STDERR $q."\n";
    my $h = $dbh->prepare($q);

    my $numeric_regex = '^-?[0-9]+([,.][0-9]+)?$';
    $h->execute($c->stash->{trial_id}, $numeric_regex);

    my @phenotype_data;

    while (my ($trait, $trait_id, $count, $average, $max, $min, $stddev, $stock_name, $stock_id) = $h->fetchrow_array()) {

        my $cv = 0;
        if ($stddev && $average != 0) {
            $cv = ($stddev /  $average) * 100;
            $cv = $round->round($cv) . '%';
        }
        if ($average) { $average = $round->round($average); }
        if ($min) { $min = $round->round($min); }
        if ($max) { $max = $round->round($max); }
        if ($stddev) { $stddev = $round->round($stddev); }

        my @return_array;
        if ($stock_name && $stock_id) {
            $total_complete_number = scalar (@{$stocks_per_accession->{$stock_id}});
            push @return_array, qq{<a href="/stock/$stock_id/view">$stock_name</a>};
        }
        my $percent_missing = '';
        if ($total_complete_number > $count){
            $percent_missing = sprintf("%.2f", 100 -(($count/$total_complete_number)*100))."%";
        } else {
            $percent_missing = "0%";
        }

        push @return_array, ( qq{<a href="/cvterm/$trait_id/view">$trait</a>}, $average, $min, $max, $stddev, $cv, $count, $percent_missing, qq{<a href="#raw_data_histogram_well" onclick="trait_summary_hist_change($trait_id)"><span class="glyphicon glyphicon-stats"></span></a>} );
        push @phenotype_data, \@return_array;
    }
    # print STDERR Dumper \@phenotype_data;

    $c->stash->{rest} = { data => \@phenotype_data };
}

sub trait_histogram : Chained('trial') PathPart('trait_histogram') Args(1) {
    my $self = shift;
    my $c = shift;
    my $trait_id = shift;
    my $stock_type = $c->req->param('stock_type') || 'plot';
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my @data = $c->stash->{trial}->get_phenotypes_for_trait($trait_id, $stock_type);

    $c->stash->{rest} = { data => \@data };
}

sub get_trial_folder :Chained('trial') PathPart('folder') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $project_parent = $c->stash->{trial}->get_folder();

    $c->stash->{rest} = { folder => [ $project_parent->project_id(), $project_parent->name() ] };

}

sub get_trial_location :Chained('trial') PathPart('location') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $location = $c->stash->{trial}->get_location;
    $c->stash->{rest} = { location => $location };
}

sub trial_accessions : Chained('trial') PathPart('accessions') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);
    my $schema = $c->stash->{schema};

    my $trial = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });

    my @data = $trial->get_accessions();

    $c->stash->{rest} = { accessions => \@data };
}

sub trial_stocks : Chained('trial') PathPart('stocks') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);
    my $schema = $c->stash->{schema};

    my $trial = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });

    my $stocks = $trial->get_accessions();

    $c->stash->{rest} = { data => $stocks };
}

sub trial_tissue_sources : Chained('trial') PathPart('tissue_sources') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);
    my $schema = $c->stash->{schema};

    my $trial = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });
    my $data = $trial->get_tissue_sources();
    #print STDERR Dumper $data;
    $c->stash->{rest} = { tissue_sources => $data };
}

sub trial_seedlots : Chained('trial') PathPart('seedlots') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);
    my $schema = $c->stash->{schema};

    my $trial = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });

    my @data = $trial->get_seedlots();

    $c->stash->{rest} = { seedlots => \@data };
}

sub trial_used_seedlots_upload : Chained('trial') PathPart('upload_used_seedlots') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $upload = $c->req->upload('trial_upload_used_seedlot_file');
    my $subdirectory = "trial_used_seedlot_upload";
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
    my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('TrialUsedSeedlotsXLS');
    my $parsed_data = $parser->parse();
    #print STDERR Dumper $parsed_data;

    if (!$parsed_data) {
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
            $c->detach();
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;

            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error_string => $return_error, missing_seedlots => $parse_errors->{'missing_seedlots'}, missing_plots => $parse_errors->{'missing_plots'}};
        $c->detach();
    }

    my $upload_used_seedlots_txn = sub {
        while (my ($key, $val) = each(%$parsed_data)){
            my $sl = CXGN::Stock::Seedlot->new(schema => $schema, seedlot_id => $val->{seedlot_stock_id});

            my $transaction = CXGN::Stock::Seedlot::Transaction->new(schema => $schema);
            $transaction->factor(1);
            $transaction->from_stock([$val->{seedlot_stock_id}, $val->{seedlot_name}]);
            $transaction->to_stock([$val->{plot_stock_id}, $val->{plot_name}]);
            $transaction->amount($val->{amount});
            $transaction->weight_gram($val->{weight_gram});
            $transaction->timestamp($timestamp);
            $transaction->description($val->{description});
            $transaction->operator($user_name);
            $transaction->store();

            $sl->set_current_count_property();
            $sl->set_current_weight_property();
        }
        my $layout = $c->stash->{trial_layout};
        $layout->generate_and_cache_layout();
    };
    eval {
        $schema->txn_do($upload_used_seedlots_txn);
    };
    if ($@) {
        $c->stash->{rest} = { error => $@ };
        print STDERR "An error condition occurred, was not able to upload trial used seedlots. ($@).\n";
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = { success => 1 };
}

sub trial_upload_plants : Chained('trial') PathPart('upload_plants') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $upload = $c->req->upload('trial_upload_plants_file');
    my $inherits_plot_treatments = $c->req->param('upload_plants_per_plot_inherit_treatments');
    my $plants_per_plot = $c->req->param('upload_plants_per_plot_number');

    my $subdirectory = "trial_plants_upload";
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
    my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('TrialPlantsXLS');
    my $parsed_data = $parser->parse();
    #print STDERR Dumper $parsed_data;

    if (!$parsed_data) {
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
            $c->detach();
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;

            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error_string => $return_error, missing_plots => $parse_errors->{'missing_plots'}};
        $c->detach();
    }

    my $upload_plants_txn = sub {
        my %plot_plant_hash;
        my $parsed_entries = $parsed_data->{data};
        foreach (@$parsed_entries){
            $plot_plant_hash{$_->{plot_stock_id}}->{plot_name} = $_->{plot_name};
            push @{$plot_plant_hash{$_->{plot_stock_id}}->{plant_names}}, $_->{plant_name};
        }
        my $t = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });
        $t->save_plant_entries(\%plot_plant_hash, $plants_per_plot, $inherits_plot_treatments, $user_id);

        my $layout = $c->stash->{trial_layout};
        $layout->generate_and_cache_layout();
    };
    eval {
        $schema->txn_do($upload_plants_txn);
    };
    if ($@) {
        $c->stash->{rest} = { error => $@ };
        print STDERR "An error condition occurred, was not able to upload trial plants. ($@).\n";
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = { success => 1 };
}

sub trial_upload_plants_subplot : Chained('trial') PathPart('upload_plants_subplot') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $upload = $c->req->upload('trial_upload_plants_subplot_file');
    my $inherits_plot_treatments = $c->req->param('upload_plants_per_subplot_inherit_treatments');
    my $plants_per_subplot = $c->req->param('upload_plants_per_subplot_number');

    my $subdirectory = "trial_plants_upload";
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
    my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('TrialPlantsSubplotXLS');
    my $parsed_data = $parser->parse();
    #print STDERR Dumper $parsed_data;

    if (!$parsed_data) {
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
            $c->detach();
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;

            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error_string => $return_error, missing_subplots => $parse_errors->{'missing_subplots'}};
        $c->detach();
    }

    my $upload_plants_txn = sub {
        my %subplot_plant_hash;
        my $parsed_entries = $parsed_data->{data};
        foreach (@$parsed_entries){
            $subplot_plant_hash{$_->{subplot_stock_id}}->{subplot_name} = $_->{subplot_name};
            push @{$subplot_plant_hash{$_->{subplot_stock_id}}->{plant_names}}, $_->{plant_name};
        }
        my $t = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });
        $t->save_plant_subplot_entries(\%subplot_plant_hash, $plants_per_subplot, $inherits_plot_treatments, $user_id);

        my $layout = $c->stash->{trial_layout};
        $layout->generate_and_cache_layout();
    };
    eval {
        $schema->txn_do($upload_plants_txn);
    };
    if ($@) {
        $c->stash->{rest} = { error => $@ };
        print STDERR "An error condition occurred, was not able to upload trial plants. ($@).\n";
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = { success => 1 };
}

sub trial_upload_subplots : Chained('trial') PathPart('upload_subplots') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $upload = $c->req->upload('trial_upload_subplots_file');
    my $inherits_plot_treatments = $c->req->param('upload_subplots_per_plot_inherit_treatments');
    my $subplots_per_plot = $c->req->param('upload_subplots_per_plot_number');

    my $subdirectory = "trial_subplots_upload";
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
    my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('TrialSubplotsXLS');
    my $parsed_data = $parser->parse();
    #print STDERR Dumper $parsed_data;

    if (!$parsed_data) {
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
            $c->detach();
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;

            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error_string => $return_error, missing_plots => $parse_errors->{'missing_plots'}};
        $c->detach();
    }

    my $upload_subplots_txn = sub {
        my %plot_subplot_hash;
        my $parsed_entries = $parsed_data->{data};
        foreach (@$parsed_entries){
            $plot_subplot_hash{$_->{plot_stock_id}}->{plot_name} = $_->{plot_name};
            push @{$plot_subplot_hash{$_->{plot_stock_id}}->{subplot_names}}, $_->{subplot_name};
        }
        my $t = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });
        $t->save_subplot_entries(\%plot_subplot_hash, $subplots_per_plot, $inherits_plot_treatments, $user_id);

        my $layout = $c->stash->{trial_layout};
        $layout->generate_and_cache_layout();
    };
    eval {
        $schema->txn_do($upload_subplots_txn);
    };
    if ($@) {
        $c->stash->{rest} = { error => $@ };
        print STDERR "An error condition occurred, was not able to upload trial subplots. ($@).\n";
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = { success => 1 };
}

sub trial_upload_plants_with_index_number : Chained('trial') PathPart('upload_plants_with_plant_index_number') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $upload = $c->req->upload('trial_upload_plants_with_index_number_file');
    my $inherits_plot_treatments = $c->req->param('upload_plants_with_index_number_inherit_treatments');
    my $plants_per_plot = $c->req->param('upload_plants_with_index_number_per_plot_number');

    my $subdirectory = "trial_plants_upload";
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
    my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('TrialPlantsWithPlantNumberXLS');
    my $parsed_data = $parser->parse();
    #print STDERR Dumper $parsed_data;

    if (!$parsed_data) {
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
            $c->detach();
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;

            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error_string => $return_error, missing_plots => $parse_errors->{'missing_plots'}};
        $c->detach();
    }

    my $upload_plants_txn = sub {
        my %plot_plant_hash;
        my $parsed_entries = $parsed_data->{data};
        foreach (@$parsed_entries){
            $plot_plant_hash{$_->{plot_stock_id}}->{plot_name} = $_->{plot_name};
            push @{$plot_plant_hash{$_->{plot_stock_id}}->{plant_names}}, $_->{plant_name};
            push @{$plot_plant_hash{$_->{plot_stock_id}}->{plant_index_numbers}}, $_->{plant_index_number};
        }
        my $t = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });
        $t->save_plant_entries(\%plot_plant_hash, $plants_per_plot, $inherits_plot_treatments, $user_id);

        my $layout = $c->stash->{trial_layout};
        $layout->generate_and_cache_layout();
    };
    eval {
        $schema->txn_do($upload_plants_txn);
    };
    if ($@) {
        $c->stash->{rest} = { error => $@ };
        print STDERR "An error condition occurred, was not able to upload trial plants. ($@).\n";
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = { success => 1 };
}

sub trial_upload_plants_subplot_with_index_number : Chained('trial') PathPart('upload_plants_subplot_with_plant_index_number') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $upload = $c->req->upload('trial_upload_plants_subplot_with_index_number_file');
    my $inherits_plot_treatments = $c->req->param('upload_plants_subplot_with_index_number_inherit_treatments');
    my $plants_per_subplot = $c->req->param('upload_plants_subplot_with_index_number_per_subplot_number');

    my $subdirectory = "trial_plants_upload";
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
    my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('TrialPlantsSubplotWithPlantNumberXLS');
    my $parsed_data = $parser->parse();
    #print STDERR Dumper $parsed_data;

    if (!$parsed_data) {
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
            $c->detach();
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;

            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error_string => $return_error, missing_subplots => $parse_errors->{'missing_subplots'}};
        $c->detach();
    }

    my $upload_plants_txn = sub {
        my %subplot_plant_hash;
        my $parsed_entries = $parsed_data->{data};
        foreach (@$parsed_entries){
            $subplot_plant_hash{$_->{subplot_stock_id}}->{subplot_name} = $_->{subplot_name};
            push @{$subplot_plant_hash{$_->{subplot_stock_id}}->{plant_names}}, $_->{plant_name};
            push @{$subplot_plant_hash{$_->{subplot_stock_id}}->{plant_index_numbers}}, $_->{plant_index_number};
        }
        my $t = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });
        $t->save_plant_subplot_entries(\%subplot_plant_hash, $plants_per_subplot, $inherits_plot_treatments, $user_id);

        my $layout = $c->stash->{trial_layout};
        $layout->generate_and_cache_layout();
    };
    eval {
        $schema->txn_do($upload_plants_txn);
    };
    if ($@) {
        $c->stash->{rest} = { error => $@ };
        print STDERR "An error condition occurred, was not able to upload trial plants. ($@).\n";
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = { success => 1 };
}

sub trial_upload_subplots_with_index_number : Chained('trial') PathPart('upload_subplots_with_subplot_index_number') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $upload = $c->req->upload('trial_upload_subplots_with_index_number_file');
    my $inherits_plot_treatments = $c->req->param('upload_subplots_with_index_number_inherit_treatments');
    my $subplots_per_plot = $c->req->param('upload_subplots_with_index_number_per_plot_number');

    my $subdirectory = "trial_subplots_upload";
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
    my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('TrialSubplotsWithSubplotNumberXLS');
    my $parsed_data = $parser->parse();
    #print STDERR Dumper $parsed_data;

    if (!$parsed_data) {
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
            $c->detach();
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;

            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error_string => $return_error, missing_plots => $parse_errors->{'missing_plots'}};
        $c->detach();
    }

    my $upload_subplots_txn = sub {
        my %plot_subplot_hash;
        my $parsed_entries = $parsed_data->{data};
        foreach (@$parsed_entries){
            $plot_subplot_hash{$_->{plot_stock_id}}->{plot_name} = $_->{plot_name};
            push @{$plot_subplot_hash{$_->{plot_stock_id}}->{subplot_names}}, $_->{subplot_name};
            push @{$plot_subplot_hash{$_->{plot_stock_id}}->{subplot_index_numbers}}, $_->{subplot_index_number};
        }
        my $t = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });
        $t->save_subplot_entries(\%plot_subplot_hash, $subplots_per_plot, $inherits_plot_treatments, $user_id);

        my $layout = $c->stash->{trial_layout};
        $layout->generate_and_cache_layout();
    };
    eval {
        $schema->txn_do($upload_subplots_txn);
    };
    if ($@) {
        $c->stash->{rest} = { error => $@ };
        print STDERR "An error condition occurred, was not able to upload trial subplots. ($@).\n";
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = { success => 1 };
}

sub trial_upload_plants_with_number_of_plants : Chained('trial') PathPart('upload_plants_with_number_of_plants') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $upload = $c->req->upload('trial_upload_plants_with_number_of_plants_file');
    my $inherits_plot_treatments = $c->req->param('upload_plants_with_num_plants_inherit_treatments');
    my $plants_per_plot = $c->req->param('upload_plants_with_num_plants_per_plot_number');

    my $subdirectory = "trial_plants_upload";
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
    my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('TrialPlantsWithNumberOfPlantsXLS');
    my $parsed_data = $parser->parse();
    #print STDERR Dumper $parsed_data;

    if (!$parsed_data) {
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
            $c->detach();
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;

            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error_string => $return_error, missing_plots => $parse_errors->{'missing_plots'}};
        $c->detach();
    }

    my $upload_plants_txn = sub {
        my %plot_plant_hash;
        my $parsed_entries = $parsed_data->{data};
        foreach (@$parsed_entries){
            $plot_plant_hash{$_->{plot_stock_id}}->{plot_name} = $_->{plot_name};
            push @{$plot_plant_hash{$_->{plot_stock_id}}->{plant_names}}, $_->{plant_name};
            push @{$plot_plant_hash{$_->{plot_stock_id}}->{plant_index_numbers}}, $_->{plant_index_number};
        }
        my $t = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });
        $t->save_plant_entries(\%plot_plant_hash, $plants_per_plot, $inherits_plot_treatments, $user_id);

        my $layout = $c->stash->{trial_layout};
        $layout->generate_and_cache_layout();
    };
    eval {
        $schema->txn_do($upload_plants_txn);
    };
    if ($@) {
        $c->stash->{rest} = { error => $@ };
        print STDERR "An error condition occurred, was not able to upload trial plants. ($@).\n";
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = { success => 1 };
}

sub trial_upload_plants_subplot_with_number_of_plants : Chained('trial') PathPart('upload_plants_subplot_with_number_of_plants') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $upload = $c->req->upload('trial_upload_plants_subplot_with_number_of_plants_file');
    my $inherits_plot_treatments = $c->req->param('upload_plants_subplot_with_num_plants_inherit_treatments');
    my $plants_per_subplot = $c->req->param('upload_plants_subplot_with_num_plants_per_subplot_number');

    my $subdirectory = "trial_plants_upload";
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
    my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('TrialPlantsSubplotWithNumberOfPlantsXLS');
    my $parsed_data = $parser->parse();
    #print STDERR Dumper $parsed_data;

    if (!$parsed_data) {
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
            $c->detach();
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;

            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error_string => $return_error, missing_subplots => $parse_errors->{'missing_subplots'}};
        $c->detach();
    }

    my $upload_plants_txn = sub {
        my %subplot_plant_hash;
        my $parsed_entries = $parsed_data->{data};
        foreach (@$parsed_entries){
            $subplot_plant_hash{$_->{subplot_stock_id}}->{subplot_name} = $_->{subplot_name};
            push @{$subplot_plant_hash{$_->{subplot_stock_id}}->{plant_names}}, $_->{plant_name};
            push @{$subplot_plant_hash{$_->{subplot_stock_id}}->{plant_index_numbers}}, $_->{plant_index_number};
        }
        my $t = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });
        $t->save_plant_subplot_entries(\%subplot_plant_hash, $plants_per_subplot, $inherits_plot_treatments, $user_id);

        my $layout = $c->stash->{trial_layout};
        $layout->generate_and_cache_layout();
    };
    eval {
        $schema->txn_do($upload_plants_txn);
    };
    if ($@) {
        $c->stash->{rest} = { error => $@ };
        print STDERR "An error condition occurred, was not able to upload trial plants. ($@).\n";
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = { success => 1 };
}

sub trial_upload_subplots_with_number_of_subplots : Chained('trial') PathPart('upload_subplots_with_number_of_subplots') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $upload = $c->req->upload('trial_upload_subplots_with_number_of_subplots_file');
    my $inherits_plot_treatments = $c->req->param('upload_subplots_with_num_subplots_inherit_treatments');
    my $subplots_per_plot = $c->req->param('upload_subplots_with_num_subplots_per_plot_number');

    my $subdirectory = "trial_subplots_upload";
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
    my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('TrialSubplotsWithNumberOfSubplotsXLS');
    my $parsed_data = $parser->parse();
    #print STDERR Dumper $parsed_data;

    if (!$parsed_data) {
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
            $c->detach();
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;

            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error_string => $return_error, missing_plots => $parse_errors->{'missing_plots'}};
        $c->detach();
    }

    my $upload_subplots_txn = sub {
        my %plot_subplot_hash;
        my $parsed_entries = $parsed_data->{data};
        foreach (@$parsed_entries){
            $plot_subplot_hash{$_->{plot_stock_id}}->{plot_name} = $_->{plot_name};
            push @{$plot_subplot_hash{$_->{plot_stock_id}}->{subplot_names}}, $_->{subplot_name};
            push @{$plot_subplot_hash{$_->{plot_stock_id}}->{subplot_index_numbers}}, $_->{subplot_index_number};
        }
        my $t = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });
        $t->save_subplot_entries(\%plot_subplot_hash, $subplots_per_plot, $inherits_plot_treatments, $user_id);

        my $layout = $c->stash->{trial_layout};
        $layout->generate_and_cache_layout();
    };
    eval {
        $schema->txn_do($upload_subplots_txn);
    };
    if ($@) {
        $c->stash->{rest} = { error => $@ };
        print STDERR "An error condition occurred, was not able to upload trial subplots. ($@).\n";
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = { success => 1 };
}

sub trial_plot_gps_upload : Chained('trial') PathPart('upload_plot_gps') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};

    #Check that trial has a location set
    my $field_experiment_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'field_layout', 'experiment_type')->cvterm_id();
    my $nd_geolocation_rs = $schema->resultset('NaturalDiversity::NdGeolocation')->search(
        {'nd_experiments.type_id'=>$field_experiment_cvterm_id, 'project.project_id'=>$c->stash->{trial_id}},
        { 'join' => { 'nd_experiments' => {'nd_experiment_projects'=>'project'} } }
    );
    my $nd_geolocation = $nd_geolocation_rs->first;
    if (!$nd_geolocation){
        $c->stash->{rest} = {error=>'This trial has no location set!'};
        $c->detach();
    }

    my $upload = $c->req->upload('trial_upload_plot_gps_file');
    my $subdirectory = "trial_plot_gps_upload";
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
    my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('TrialPlotGPSCoordinatesXLS');
    my $parsed_data = $parser->parse();
    #print STDERR Dumper $parsed_data;

    if (!$parsed_data) {
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
            $c->detach();
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;

            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error_string => $return_error, missing_plots => $parse_errors->{'missing_plots'}};
        $c->detach();
    }

    my $stock_geo_json_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot_geo_json', 'stock_property');

    my $upload_plot_gps_txn = sub {
        my %plot_stock_ids_hash;
        while (my ($key, $val) = each(%$parsed_data)){
            $plot_stock_ids_hash{$val->{plot_stock_id}} = $val;
        }
        my @plot_stock_ids = keys %plot_stock_ids_hash;
        my $plots_rs = $schema->resultset("Stock::Stock")->search({stock_id => {-in=>\@plot_stock_ids}});
        while (my $plot=$plots_rs->next){
            my $coords = $plot_stock_ids_hash{$plot->stock_id};
            my $geo_json = {
                "type"=> "Feature",
                "geometry"=> {
                    "type"=> "Polygon",
                    "coordinates"=> [
                        [
                            [$coords->{WGS84_bottom_left_x}, $coords->{WGS84_bottom_left_y}],
                            [$coords->{WGS84_bottom_right_x}, $coords->{WGS84_bottom_right_y}],
                            [$coords->{WGS84_top_right_x}, $coords->{WGS84_top_right_y}],
                            [$coords->{WGS84_top_left_x}, $coords->{WGS84_top_left_y}],
                            [$coords->{WGS84_bottom_left_x}, $coords->{WGS84_bottom_left_y}],
                        ]
                    ]
                },
                "properties"=> {
                    "format"=> "WGS84",
                }
            };
            my $geno_json_string = encode_json $geo_json;
            #print STDERR $geno_json_string."\n";
            my $previous_plot_gps_rs = $schema->resultset("Stock::Stockprop")->search({stock_id=>$plot->stock_id, type_id=>$stock_geo_json_cvterm->cvterm_id});
            $previous_plot_gps_rs->delete_all();
            $plot->create_stockprops({$stock_geo_json_cvterm->name() => $geno_json_string});
        }
        my $layout = $c->stash->{trial_layout};
        $layout->generate_and_cache_layout();
    };
    eval {
        $schema->txn_do($upload_plot_gps_txn);
    };
    if ($@) {
        $c->stash->{rest} = { error => $@ };
        print STDERR "An error condition occurred, was not able to upload trial plot GPS coordinates. ($@).\n";
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = { success => 1 };
}

sub trial_plot_gps_delete : Chained('trial') PathPart('delete_plot_gps') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $trial = $c->stash->{trial};

    my $data = $trial->get_plots();

    my $stock_geo_json_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot_geo_json', 'stock_property')->cvterm_id();

    my $delete_plot_gps_txn = sub {
        foreach my $plot (@$data) {
            my $previous_plot_gps_rs = $schema->resultset("Stock::Stockprop")->search({stock_id=>$plot->[0], type_id=>$stock_geo_json_cvterm});
            $previous_plot_gps_rs->delete_all();
        }
        my $layout = $c->stash->{trial_layout};
        $layout->generate_and_cache_layout();
    };
    eval {
        $schema->txn_do($delete_plot_gps_txn);
    };
    if ($@) {
        $c->stash->{rest} = { error => $@ };
        print STDERR "An error condition occurred, was not able to delete trial plot GPS coordinates. ($@).\n";
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = { success => 1 };
}

sub trial_change_plot_accessions_upload : Chained('trial') PathPart('change_plot_accessions_using_file') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $trial_id = $c->stash->{trial_id};
    my $schema = $c->stash->{schema};

    my $upload = $c->req->upload('trial_design_change_accessions_file');
    my $subdirectory = "trial_change_plot_accessions_upload";
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
    my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path, trial_id => $trial_id);
    $parser->load_plugin('TrialChangePlotAccessionsCSV');
    my $parsed_data = $parser->parse();
    #print STDERR Dumper $parsed_data;

    if (!$parsed_data) {
        my $return_error = '';
        my $parse_errors;
        if (!$parser->has_parse_errors() ){
            $c->stash->{rest} = {error_string => "Could not get parsing errors"};
            $c->detach();
        } else {
            $parse_errors = $parser->get_parse_errors();
            #print STDERR Dumper $parse_errors;
            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error .= $error_string."<br>";
            }
        }
        $c->stash->{rest} = {error => $return_error};
        return;
    }

    my $plot_of_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot_of', 'stock_relationship')->cvterm_id();
    my $plot_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot', 'stock_type')->cvterm_id();

    my $replace_accession_fieldmap = CXGN::Trial::FieldMap->new({
    bcs_schema => $schema,
    trial_id => $trial_id,
    });

    my $return_error = $replace_accession_fieldmap->update_fieldmap_precheck();
     if ($return_error) {
       $c->stash->{rest} = { error => $return_error };
       return;
     }

    my $upload_change_plot_accessions_txn = sub {
        my @stock_names;
        print STDERR Dumper $parsed_data;
        while (my ($key, $val) = each(%$parsed_data)){
            my $plot_name = $val->{plot_name};
            my $accession_name = $val->{accession_name};
            my $new_plot_name = $val->{new_plot_name};
            push @stock_names, $plot_name;
            push @stock_names, $accession_name;
        }
        my %stock_id_map;
        my $stock_rs = $schema->resultset("Stock::Stock")->search({
            uniquename => {'-in' => \@stock_names}
        });
        while (my $r = $stock_rs->next()){
            $stock_id_map{$r->uniquename} = $r->stock_id;
        }
        print STDERR Dumper \%stock_id_map;
        while (my ($key, $val) = each(%$parsed_data)){
            my $plot_id = $stock_id_map{$val->{plot_name}};
            my $accession_id = $stock_id_map{$val->{accession_name}};
            my $plot_name = $val->{plot_name};
            my $new_plot_name = $val->{new_plot_name};

            my $replace_accession_error = $replace_accession_fieldmap->replace_plot_accession_fieldMap($plot_id, $accession_id, $plot_of_type_id);
            if ($replace_accession_error) {
                $c->stash->{rest} = { error => $replace_accession_error};
                return;
            }

            if ($new_plot_name) {
                my $replace_plot_name_error = $replace_accession_fieldmap->replace_plot_name_fieldMap($plot_id, $new_plot_name);
                if ($replace_plot_name_error) {
                    $c->stash->{rest} = { error => $replace_plot_name_error};
                    return;
                }
            }
        }
    };
    eval {
        $schema->txn_do($upload_change_plot_accessions_txn);
    };
    if ($@) {
        $c->stash->{rest} = { error => $@ };
        print STDERR "An error condition occurred, was not able to change plot accessions. ($@).\n";
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = { success => 1 };
}

sub trial_additional_file_upload : Chained('trial') PathPart('upload_additional_file') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $upload = $c->req->upload('trial_upload_additional_file');
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

    my $result = $c->stash->{trial}->add_additional_uploaded_file($user_id, $archived_filename_with_path, $md5checksum);
    if ($result->{error}){
        $c->stash->{rest} = {error=>$result->{error}};
        $c->detach();
    }
    $c->stash->{rest} = { success => 1, file_id => $result->{file_id} };
}

sub get_trial_additional_file_uploaded : Chained('trial') PathPart('get_uploaded_additional_file') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $files = $c->stash->{trial}->get_additional_uploaded_files();
    $c->stash->{rest} = {success=>1, files=>$files};
}

sub obsolete_trial_additional_file_uploaded :Chained('trial') PathPart('obsolete_uploaded_additional_file') Args(1) {
    my $self = shift;
    my $c = shift;
    my $file_id = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'curator', 'curator_access');

    my $result = $c->stash->{trial}->obsolete_additional_uploaded_file($file_id, $user_id, $user_role);

    if (exists($result->{errors})) {
        $c->stash->{rest} = { error => $result->{errors} };
    }
    else {
        $c->stash->{rest} = { success => 1 };
    }
}


sub trial_controls : Chained('trial') PathPart('controls') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });

    my @data = $trial->get_controls();

    $c->stash->{rest} = { accessions => \@data };
}

sub controls_by_plot : Chained('trial') PathPart('controls_by_plot') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my @plot_ids = $c->req->param('plot_ids[]');
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = CXGN::Trial->new({ bcs_schema => $schema, trial_id => $c->stash->{trial_id} });

    my @data = $trial->get_controls_by_plot(\@plot_ids);

    $c->stash->{rest} = { accessions => \@data };
}

sub trial_plots : Chained('trial') PathPart('plots') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = $c->stash->{trial};

    my @data = $trial->get_plots();
#    print STDERR "PLOTS =".Dumper(\@data)."\n";

    $c->stash->{rest} = { plots => \@data };
}

sub trial_has_data_levels : Chained('trial') PathPart('has_data_levels') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = $c->stash->{trial};
    $c->stash->{rest} = {
        has_plants => $trial->has_plant_entries(),
        has_subplots => $trial->has_subplot_entries(),
        has_tissue_samples => $trial->has_tissue_sample_entries(),
        trial_name => $trial->get_name
    };
}

sub trial_has_subplots : Chained('trial') PathPart('has_subplots') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = $c->stash->{trial};
    $c->stash->{rest} = { has_subplots => $trial->has_subplot_entries(), trial_name => $trial->get_name };
}

sub trial_subplots : Chained('trial') PathPart('subplots') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = $c->stash->{trial};

    my @data = $trial->get_subplots();

    $c->stash->{rest} = { subplots => \@data };
}

sub trial_has_plants : Chained('trial') PathPart('has_plants') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = $c->stash->{trial};
    $c->stash->{rest} = { has_plants => $trial->has_plant_entries(), trial_name => $trial->get_name };
}

sub trial_plants : Chained('trial') PathPart('plants') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = $c->stash->{trial};

    my @data = $trial->get_plants();

    $c->stash->{rest} = { plants => \@data };
}

sub trial_has_tissue_samples : Chained('trial') PathPart('has_tissue_samples') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = $c->stash->{trial};
    $c->stash->{rest} = { has_tissue_samples => $trial->has_tissue_sample_entries(), trial_name => $trial->get_name };
}

sub trial_tissue_samples : Chained('trial') PathPart('tissue_samples') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = $c->stash->{trial};

    my $data = $trial->get_tissue_samples();

    $c->stash->{rest} = { trial_tissue_samples => $data };
}

sub trial_phenotype_metadata : Chained('trial') PathPart('phenotype_metadata') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = $c->stash->{trial};
    my $data = $trial->get_phenotype_metadata();

    $c->stash->{rest} = { data => $data };
}

sub trial_aerial_imaging_event_report_files : Chained('trial') PathPart('aerial_imaging_event_report_files') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = $c->stash->{trial};
    my $data = $trial->get_aerial_imaging_event_report_file_metadata();

    $c->stash->{rest} = { data => $data };
}

sub trial_treatments : Chained('trial') PathPart('treatments') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial = $c->stash->{trial};

    my $data = $trial->get_treatments();

    $c->stash->{rest} = { treatments => $data };
}

sub trial_add_treatment : Chained('trial') PathPart('add_treatment') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $trial_id = $c->stash->{trial_id};
    my $trial = $c->stash->{trial};
    my $design = decode_json $c->req->param('design');
    my $new_treatment_has_plant_entries = $c->req->param('has_plant_entries');
    my $new_treatment_has_subplot_entries = $c->req->param('has_subplot_entries');
    my $new_treatment_has_tissue_entries = $c->req->param('has_tissue_sample_entries');
    my $new_treatment_year = $c->req->param('treatment_year');
    my $new_treatment_date = $c->req->param('treatment_date');
    my $new_treatment_type = $c->req->param('treatment_type');

    my $trial_design_store = CXGN::Trial::TrialDesignStore->new({
		bcs_schema => $schema,
		trial_id => $trial_id,
        trial_name => $trial->get_name(),
		nd_geolocation_id => $trial->get_location()->[0],
		design_type => $trial->get_design_type(),
		design => $design,
        new_treatment_has_plant_entries => $new_treatment_has_plant_entries,
        new_treatment_has_subplot_entries => $new_treatment_has_subplot_entries,
        new_treatment_has_tissue_sample_entries => $new_treatment_has_tissue_entries,
        new_treatment_date => $new_treatment_date,
        new_treatment_year => $new_treatment_year,
        new_treatment_type => $new_treatment_type,
        operator => $user_name
	});
    my $error = $trial_design_store->store();
    if ($error){
        $c->stash->{rest} = {error => "Treatment not added: ".$error};
    } else {
        $c->stash->{rest} = {success => 1};
    }
}

sub trial_layout : Chained('trial') PathPart('layout') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $layout = $c->stash->{trial_layout};

    my $design = $layout->get_design();
    $c->stash->{rest} = {design => $design};
}

sub trial_layout_table : Chained('trial') PathPart('layout_table') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my $selected_cols = $c->req->param('selected_columns') ? decode_json $c->req->param('selected_columns') : {"plot_name"=>1,"plot_number"=>1,"block_number"=>1,"accession_name"=>1,"is_a_control"=>1,"rep_number"=>1,"row_number"=>1,"col_number"=>1};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_layout_download = CXGN::Trial::TrialLayoutDownload->new({
        schema => $schema,
        trial_id => $c->stash->{trial_id},
        data_level => 'plots',
        #treatment_project_ids => [1,2],
        selected_columns => $selected_cols,
        include_measured => "false"
    });
    my $output = $trial_layout_download->get_layout_output();

    $c->stash->{rest} = $output;
}

sub trial_design : Chained('trial') PathPart('design') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $layout = $c->stash->{trial_layout};

    my $design = $layout->get_design();
    my $design_type = $layout->get_design_type();

    my $plot_length = '';
    my $plot_width = '';
    my $subplots_per_plot = '';
    my $plants_per_plot = '';
    my $number_of_blocks = '';
    if ($design_type ne 'genotyping_plate') {
        my $plot_dimensions = $layout->get_plot_dimensions();
        $plot_length = $plot_dimensions->[0] ? $plot_dimensions->[0] : '';
        $plot_width = $plot_dimensions->[1] ? $plot_dimensions->[1] : '';
        $plants_per_plot = $plot_dimensions->[2] ? $plot_dimensions->[2] : '';
        $subplots_per_plot = $plot_dimensions->[3] ? $plot_dimensions->[3] : '';

        my $block_numbers = $layout->get_block_numbers();
        if ($block_numbers) {
            $number_of_blocks = scalar(@{$block_numbers});
        }
    }

    my $replicate_numbers = $layout->get_replicate_numbers();
    my $number_of_replicates = '';
    if ($replicate_numbers) {
        $number_of_replicates = scalar(@{$replicate_numbers});
    }

    my $plot_names = $layout->get_plot_names();
    my $number_of_plots = '';
    if ($plot_names){
        $number_of_plots = scalar(@{$plot_names});
    }

    $c->stash->{rest} = {
        design_type => $design_type,
        num_blocks => $number_of_blocks,
        num_reps => $number_of_replicates,
        plot_length => $plot_length,
        plot_width => $plot_width,
        subplots_per_plot => $subplots_per_plot,
        plants_per_plot => $plants_per_plot,
        total_number_plots => $number_of_plots,
        design => $design
    };
}

sub get_spatial_layout : Chained('trial') PathPart('coords') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $cxgn_project_type = $c->stash->{trial}->get_cxgn_project_type();

    my $fieldmap = CXGN::Trial::FieldMap->new({
      bcs_schema => $schema,
      trial_id => $c->stash->{trial_id},
      experiment_type => $cxgn_project_type->{experiment_type}
    });
    my $return = $fieldmap->display_fieldmap();

    $c->stash->{rest} = $return;
}

sub retrieve_trial_info :  Path('/ajax/breeders/trial_phenotyping_info') : ActionClass('REST') { }
sub retrieve_trial_info_POST : Args(0) {
#sub retrieve_trial_info : chained('trial') Pathpart("trial_phenotyping_info") Args(0) {
    my $self =shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $trial_id = $c->req->param('trial_id');
    my $layout = CXGN::Trial::TrialLayout->new({schema => $schema, trial_id => $trial_id, experiment_type=>'field_layout'});
  	my $design = $layout-> get_design();
    #print STDERR Dumper($design);

    my @layout_info;
  	foreach my $plot_number (keys %{$design}) {
  		push @layout_info, {
        plot_id => $design->{$plot_number}->{plot_id},
  		plot_number => $plot_number,
  		row_number => $design->{$plot_number}->{row_number},
  		col_number => $design->{$plot_number}->{col_number},
  		block_number=> $design->{$plot_number}-> {block_number},
  		rep_number =>  $design->{$plot_number}-> {rep_number},
  		plot_name => $design->{$plot_number}-> {plot_name},
  		accession_name => $design->{$plot_number}-> {accession_name},
  		plant_names => $design->{$plot_number}-> {plant_names},
  		};
        @layout_info = sort { $a->{plot_number} <=> $b->{plot_number} } @layout_info;
  	}

    #print STDERR Dumper(@layout_info);
    $c->stash->{rest} = {trial_info => \@layout_info};
    #$c->stash->{layout_info} = \@layout_info;
}


sub trial_completion_layout_section : Chained('trial') PathPart('trial_completion_layout_section') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my $experiment_type = $c->req->param('experiment_type') || 'field_layout';
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_layout = CXGN::Trial::TrialLayout->new({schema => $schema, trial_id => $c->stash->{trial_id}, experiment_type => $experiment_type, verify_layout=>1, verify_physical_map=>1});
    my $trial_errors = $trial_layout->generate_and_cache_layout();
    my $has_layout_check = $trial_errors->{errors}->{layout_errors} || $trial_errors->{error} ? 0 : 1;
    my $has_physical_map_check = $trial_errors->{errors}->{physical_map_errors} || $trial_errors->{error} ? 0 : 1;
    my $has_seedlots = $trial_errors->{errors}->{seedlot_errors} || $trial_errors->{error} ? 0 : 1;
    my $error_string = $trial_errors->{error} ? $trial_errors->{error} : '';
    my $layout_error_string = $trial_errors->{errors}->{layout_errors} ? join ', ', @{$trial_errors->{errors}->{layout_errors}} : '';
    my $map_error_string = $trial_errors->{errors}->{physical_map_errors} ? join ', ', @{$trial_errors->{errors}->{physical_map_errors}} : '';
    my $seedlot_error_string = $trial_errors->{errors}->{seedlot_errors} ? join ', ', @{$trial_errors->{errors}->{seedlot_errors}} : '';

    $c->stash->{rest} = {
        has_layout => $has_layout_check,
        layout_errors => $error_string." ".$layout_error_string,
        has_physical_map => $has_physical_map_check,
        physical_map_errors => $error_string." ".$map_error_string,
        has_seedlots => $has_seedlots,
        seedlot_errors => $error_string." ".$seedlot_error_string
    };
}

sub trial_completion_phenotype_section : Chained('trial') PathPart('trial_completion_phenotype_section') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $plot_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot', 'stock_type')->cvterm_id();
    my $plant_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plant', 'stock_type')->cvterm_id();

    my $q = "SELECT phenotype.phenotype_id
        FROM phenotype
        JOIN nd_experiment_phenotype_bridge ON(phenotype.phenotype_id=nd_experiment_phenotype_bridge.phenotype_id)
        JOIN stock USING(stock_id)
        WHERE phenotype.value != '' AND stock.type_id IN ($plot_type_id, $plant_type_id) AND project_id = ?
        LIMIT 1;";
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute($c->stash->{trial_id});
    my ($phenotype_id) = $h->fetchrow_array();
    $h = undef;
    my $has_phenotypes = $phenotype_id ? 1 : 0;
    $c->stash->{rest} = {has_phenotypes => $has_phenotypes};
}

sub delete_field_coord : Chained('trial') PathPart('delete_field_coords') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');
    my $schema = $c->stash->{schema};
    my $trial_id = $c->stash->{trial_id};

    my $fieldmap = CXGN::Trial::FieldMap->new({
        bcs_schema => $schema,
        trial_id => $trial_id,
    });
    my $delete_return_error = $fieldmap->delete_fieldmap();
    if ($delete_return_error) {
        $c->stash->{rest} = { error => $delete_return_error };
        return;
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});
    my $trial_layout = CXGN::Trial::TrialLayout->new({ schema => $schema, trial_id => $trial_id, experiment_type => 'field_layout' });
    $trial_layout->generate_and_cache_layout();

    $c->stash->{rest} = {success => 1};
}

sub replace_trial_stock : Chained('trial') PathPart('replace_stock') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $old_stock_id = $c->req->param('old_stock_id');
    my $new_stock = $c->req->param('new_stock');
    my $trial_stock_type = $c->req->param('trial_stock_type');
    my $trial_id = $c->stash->{trial_id};

    if (!$new_stock){
        $c->stash->{rest} = { error => "Provide new stock name." };
        return;
    }

    my $replace_stock_fieldmap = CXGN::Trial::FieldMap->new({
        bcs_schema => $schema,
        trial_id => $trial_id,
        trial_stock_type => $trial_stock_type,
    });

    my $return_error = $replace_stock_fieldmap->update_fieldmap_precheck();
    if ($return_error) {
        $c->stash->{rest} = { error => $return_error };
        return;
    }

    my $replace_return_error = $replace_stock_fieldmap->replace_trial_stock_fieldMap($new_stock, $old_stock_id);
    if ($replace_return_error) {
        $c->stash->{rest} = { error => $replace_return_error };
        return;
    }

    $c->stash->{rest} = { success => 1};
}

sub replace_plot_accession : Chained('trial') PathPart('replace_plot_accessions') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $old_accession = $c->req->param('old_accession');
    my $new_accession = $c->req->param('new_accession');
    my $plot_id = $c->req->param('old_plot_id');
    my $old_plot_name = $c->req->param('old_plot_name');
    my $new_plot_name = $c->req->param('new_plot_name');
    my $override = $c->req->param('override');
    my $trial_id = $c->stash->{trial_id};

    if (!$new_accession) {
        $c->stash->{rest} = { error => "Provide new accession name." };
        return;
    }

    my $replace_plot_accession_fieldmap = CXGN::Trial::FieldMap->new({
        trial_id => $trial_id,
        bcs_schema => $schema,
    });

    my $return_error = $replace_plot_accession_fieldmap->update_fieldmap_precheck();

    if ($return_error) {
        $c->stash->{rest} = { error => $return_error};
        return;
    }

    my $plot_of_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot_of', 'stock_relationship')->cvterm_id();
    my $accession_rs = $schema->resultset("Stock::Stock")->search({
        uniquename => $new_accession
    });
    $accession_rs = $accession_rs->next();
    my $accession_id = $accession_rs->stock_id;

    print "Calling Replace Function...............\n";
    my $replace_return_error = $replace_plot_accession_fieldmap->replace_plot_accession_fieldMap($plot_id, $accession_id, $plot_of_type_id);
    if ($replace_return_error) {
        $c->stash->{rest} = { error => $replace_return_error };
        return;
    }

    if ($new_plot_name) {
        my $replace_plot_name_return_error = $replace_plot_accession_fieldmap->replace_plot_name_fieldMap($plot_id, $new_plot_name);
        if ($replace_plot_name_return_error) {
            $c->stash->{rest} = { error => $replace_plot_name_return_error };
            return;
        }
    }

    my $bs = CXGN::BreederSearch->new( { dbh=>$c->dbc->dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    print "OldAccession: $old_accession, NewAcc: $new_accession, OldPlotName: $old_plot_name, NewPlotName: $new_plot_name OldPlotId: $plot_id\n";
    $c->stash->{rest} = { success => 1};
}

sub replace_well_accession : Chained('trial') PathPart('replace_well_accessions') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $old_accession = $c->req->param('old_accession');
    my $new_accession = $c->req->param('new_accession');
    my $old_plot_id = $c->req->param('old_plot_id');
    my $old_plot_name = $c->req->param('old_plot_name');
    my $trial_id = $c->stash->{trial_id};

    if (!$new_accession){
        $c->stash->{rest} = { error => "Provide new accession name." };
        return;
    }
    my $cxgn_project_type = $c->stash->{trial}->get_cxgn_project_type();

    my $replace_plot_accession_fieldmap = CXGN::Trial::FieldMap->new({
        bcs_schema => $schema,
        trial_id => $trial_id,
        new_accession => $new_accession,
        old_accession => $old_accession,
        old_plot_id => $old_plot_id,
        old_plot_name => $old_plot_name,
        experiment_type => $cxgn_project_type->{experiment_type}
    });

    my $return_error = $replace_plot_accession_fieldmap->update_fieldmap_precheck();
    if ($return_error) {
        $c->stash->{rest} = { error => $return_error };
        return;
    }

    print "Calling Replace Function...............\n";
    my $replace_return_error = $replace_plot_accession_fieldmap->replace_plot_accession_fieldMap();
    if ($replace_return_error) {
        $c->stash->{rest} = { error => $replace_return_error };
        return;
    }

    print "OldAccession: $old_accession, NewAcc: $new_accession, OldWellId: $old_plot_id\n";
    $c->stash->{rest} = { success => 1};
}

sub substitute_stock : Chained('trial') PathPart('substitute_stock') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $trial_id = $c->stash->{trial_id};
    my $plot_1_info = $c->req->param('plot_1_info');
    my $plot_2_info = $c->req->param('plot_2_info');

    my ($plot_1_id, $accession_1) = split /,/, $plot_1_info;
    my ($plot_2_id, $accession_2) = split /,/, $plot_2_info;

    if ($plot_1_id == $plot_2_id){
        $c->stash->{rest} = { error => "Choose a different plot/stock in 'select plot 2' to perform this operation." };
        return;
    }

    my @controls;
    my @ids;

    my $fieldmap = CXGN::Trial::FieldMap->new({
        bcs_schema => $schema,
        trial_id => $trial_id,
        first_plot_selected => $plot_1_id,
        second_plot_selected => $plot_2_id,
        first_accession_selected => $accession_1,
        second_accession_selected => $accession_2,
    });

    my $return_error = $fieldmap->update_fieldmap_precheck();
    if ($return_error) {
        $c->stash->{rest} = { error => $return_error };
        return;
    }

    my $return_check_error = $fieldmap->substitute_accession_precheck();
    if ($return_check_error) {
        $c->stash->{rest} = { error => $return_check_error };
        return;
    }

    my $update_return_error = $fieldmap->substitute_accession_fieldmap();
    if ($update_return_error) {
        $c->stash->{rest} = { error => $update_return_error };
        return;
    }

    $c->stash->{rest} = { success => 1};
}

sub create_plant_plot_entries : Chained('trial') PathPart('create_plant_entries') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $plants_per_plot = $c->req->param("plants_per_plot") || 8;
    my $inherits_plot_treatments = $c->req->param("inherits_plot_treatments");
    my $plants_with_treatments;
    if($inherits_plot_treatments eq '1'){
        $plants_with_treatments = 1;
    }

    if (!$plants_per_plot || $plants_per_plot > 500) {
        $c->stash->{rest} = { error => "Plants per plot number is required and must be smaller than 500." };
        return;
    }

    my $t = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });

    if ($t->create_plant_entities($plants_per_plot, $plants_with_treatments, $user_id)) {

        my $dbh = $c->dbc->dbh();
        my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
        my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

        $c->stash->{rest} = {success => 1};
        return;
    } else {
        $c->stash->{rest} = { error => "Error creating plant entries in controller." };
    	return;
    }

}

sub edit_management_factor_details : Chained('trial') PathPart('edit_management_factor_details') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $treatment_date = $c->req->param("treatment_date");
    my $treatment_name = $c->req->param("treatment_name");
    my $treatment_description = $c->req->param("treatment_description");
    my $treatment_type = $c->req->param("treatment_type");
    my $treatment_year = $c->req->param("treatment_year");

    if (!$treatment_name) {
        $c->stash->{rest} = { error => 'No treatment name given!' };
        return;
    }
    if (!$treatment_description) {
        $c->stash->{rest} = { error => 'No treatment description given!' };
        return;
    }
    if (!$treatment_date) {
        $c->stash->{rest} = { error => 'No treatment date given!' };
        return;
    }
    if (!$treatment_type) {
        $c->stash->{rest} = { error => 'No treatment type given!' };
        return;
    }
    if (!$treatment_year) {
        $c->stash->{rest} = { error => 'No treatment year given!' };
        return;
    }

    my $t = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });
    my $trial_name = $t->get_name();

    if ($trial_name ne $treatment_name) {
        my $trial_rs = $schema->resultset('Project::Project')->search({name => $treatment_name});
        if ($trial_rs->count() > 0) {
            $c->stash->{rest} = { error => 'Please use a different management factor name! That name is already in use.' };
            return;
        }
    }

    $t->set_name($treatment_name);
    $t->set_management_factor_date($treatment_date);
    $t->set_management_factor_type($treatment_type);
    $t->set_description($treatment_description);
    $t->set_year($treatment_year);

    $c->stash->{rest} = { success => 1 };
}

sub create_plant_subplot_entries : Chained('trial') PathPart('create_plant_subplot_entries') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $plants_per_subplot = $c->req->param("plants_per_subplot") || 8;
    my $inherits_plot_treatments = $c->req->param("inherits_plot_treatments");
    my $plants_with_treatments;
    if($inherits_plot_treatments eq '1'){
        $plants_with_treatments = 1;
    }

    if (!$plants_per_subplot || $plants_per_subplot > 500) {
        $c->stash->{rest} = { error => "Plants per subplot number is required and must be smaller than 500." };
        return;
    }

    my $t = CXGN::Trial->new( { bcs_schema => $schema, trial_id => $c->stash->{trial_id} });

    if ($t->create_plant_subplot_entities($plants_per_subplot, $plants_with_treatments, $user_id)) {

        my $dbh = $c->dbc->dbh();
        my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
        my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

        $c->stash->{rest} = {success => 1};
        return;
    } else {
        $c->stash->{rest} = { error => "Error creating plant entries for subplots in controller." };
    	return;
    }

}

sub create_subplot_entries : Chained('trial') PathPart('create_subplot_entries') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $subplots_per_plot = $c->req->param("subplots_per_plot") || 4;
    my $inherits_plot_treatments = $c->req->param("inherits_plot_treatments");
    my $subplots_with_treatments;
    if($inherits_plot_treatments eq '1'){
        $subplots_with_treatments = 1;
    }

    if (!$subplots_per_plot || $subplots_per_plot > 500) {
        $c->stash->{rest} = { error => "Subplots per plot number is required and must be smaller than 500." };
        return;
    }

    my $t = $c->stash->{trial};
    if ($t->create_subplot_entities($subplots_per_plot, $subplots_with_treatments, $user_id)) {

        my $dbh = $c->dbc->dbh();
        my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
        my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

        $c->stash->{rest} = {success => 1};
        return;
    } else {
        $c->stash->{rest} = { error => "Error creating subplot entries in controller." };
    	return;
    }

}

sub create_tissue_samples : Chained('trial') PathPart('create_tissue_samples') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $tissues_per_plant = $c->req->param("tissue_samples_per_plant") || 3;
    my $tissue_names = decode_json $c->req->param("tissue_samples_names");
    my $inherits_plot_treatments = $c->req->param("inherits_plot_treatments");
    my $tissues_with_treatments;
    if($inherits_plot_treatments eq '1'){
        $tissues_with_treatments = 1;
    }

    if (!$c->stash->{trial}->has_plant_entries){
        $c->stash->{rest} = { error => "Trial must have plant entries before you can add tissue samples entries. Plant entries are added from the trial detail page." };
        $c->detach;
    }

    if (!$tissue_names || scalar(@$tissue_names) < 1){
        $c->stash->{rest} = { error => "You must provide tissue name(s) for your samples" };
        $c->detach;
    }

    if (!$tissues_per_plant || $tissues_per_plant > 50) {
        $c->stash->{rest} = { error => "Tissues per plant is required and must be smaller than 50." };
        $c->detach;
    }

    my $t = CXGN::Trial->new({ bcs_schema => $schema, trial_id => $c->stash->{trial_id} });

    if ($t->create_tissue_samples($tissue_names, $inherits_plot_treatments, $user_id)) {
        my $dbh = $c->dbc->dbh();
        my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
        my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

        $c->stash->{rest} = {success => 1};
        $c->detach;;
    } else {
        $c->stash->{rest} = { error => "Error creating tissues samples in controller." };
        $c->detach;;
    }

}

sub upload_trial_coordinates : Chained('trial') PathPart('coordsupload') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $trial_id = $c->stash->{trial_id};
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();
    my $subdirectory = 'trial_coords_upload';
    my $upload = $c->req->upload('trial_coordinates_uploaded_file');
    my $upload_tempfile  = $upload->tempname;
    my $upload_original_name  = $upload->filename();
    my $md5;
    my %upload_metadata;

    # Store uploaded temporary file in archive
    print STDERR "TEMP FILE: $upload_tempfile\n";
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

    if (!$archived_filename_with_path) {
    	$c->stash->{rest} = {error => "Could not save file $upload_original_name in archive",};
    	return;
    }

    $md5 = $uploader->get_md5($archived_filename_with_path);
    unlink $upload_tempfile;

    my $error_string = '';
   # open file and remove return of line
    open(my $F, "< :encoding(UTF-8)", $archived_filename_with_path) || die "Can't open archive file $archived_filename_with_path";
    my $header = <$F>;
    while (<$F>) {
    	chomp;
    	$_ =~ s/\r//g;
    	my ($plot,$row,$col) = split /\t/ ;
    	my $rs = $schema->resultset("Stock::Stock")->search({uniquename=> $plot });
    	if ($rs->count()== 1) {
      	my $r =  $rs->first();
      	print STDERR "The plots $plot was found.\n Loading row $row col $col\n";
      	$r->create_stockprops({row_number => $row, col_number => $col});
      }
      else {
      	print STDERR "WARNING! $plot was not found in the database.\n";
        $error_string .= "WARNING! $plot was not found in the database.";
      }
    }

    my $trial_layout = CXGN::Trial::TrialLayout->new({ schema => $schema, trial_id => $trial_id, experiment_type => 'field_layout' });
    $trial_layout->generate_and_cache_layout();

    if ($error_string){
        $c->stash->{rest} = {error_string => $error_string};
        $c->detach();
    }

    my $dbh = $c->dbc->dbh();
    my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = {success => 1};
}

sub crosses_in_crossingtrial : Chained('trial') PathPart('crosses_in_crossingtrial') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $trial = CXGN::Cross->new({schema => $schema, trial_id => $trial_id});

    my $result = $trial->get_crosses_in_crossing_experiment();
    my @crosses;
    foreach my $r (@$result){
        my ($cross_id, $cross_name) =@$r;
        push @crosses, {
            cross_id => $cross_id,
            cross_name => $cross_name,
        };
    }

    $c->stash->{rest} = { data => \@crosses };
}

sub crosses_and_details_in_trial : Chained('trial') PathPart('crosses_and_details_in_trial') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);
    my $schema = $c->stash->{schema};

    my $trial_id = $c->stash->{trial_id};
    my $trial = CXGN::Cross->new({ schema => $schema, trial_id => $trial_id});

    my $result = $trial->get_crosses_and_details_in_crossingtrial();
    my @crosses;
    foreach my $r (@$result){
        my ($cross_id, $cross_name, $cross_combination, $cross_type, $female_parent_id, $female_parent_name, $female_ploidy, $male_parent_id, $male_parent_name, $male_ploidy, $female_plot_id, $female_plot_name, $male_plot_id, $male_plot_name, $female_plant_id, $female_plant_name, $male_plant_id, $male_plant_name) =@$r;
        push @crosses, {
            cross_id => $cross_id,
            cross_name => $cross_name,
            cross_combination => $cross_combination,
            cross_type => $cross_type,
            female_parent_id => $female_parent_id,
            female_parent_name => $female_parent_name,
            female_ploidy_level => $female_ploidy,
            male_parent_id => $male_parent_id,
            male_parent_name => $male_parent_name,
            male_ploidy_level => $male_ploidy,
            female_plot_id => $female_plot_id,
            female_plot_name => $female_plot_name,
            male_plot_id => $male_plot_id,
            male_plot_name => $male_plot_name,
            female_plant_id => $female_plant_id,
            female_plant_name => $female_plant_name,
            male_plant_id => $male_plant_id,
            male_plant_name => $male_plant_name
        };
    }

    $c->stash->{rest} = { data => \@crosses };
}

sub cross_properties_trial : Chained('trial') PathPart('cross_properties_trial') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $trial = CXGN::Cross->new({ schema => $schema, trial_id => $trial_id});

    my $result = $trial->get_cross_properties_trial();

    my $cross_properties = $c->config->{cross_properties};
    my @column_order = split ',', $cross_properties;

    my @crosses;
    foreach my $r (@$result){
        my ($cross_id, $cross_name, $cross_combination, $cross_props_hash) =@$r;

        my @row = ( qq{<a href = "/cross/$cross_id">$cross_name</a>}, $cross_combination );
        foreach my $key (@column_order){
          push @row, $cross_props_hash->{$key};
        }

        push @crosses, \@row;
    }

    $c->stash->{rest} = { data => \@crosses };
}

sub cross_progenies_trial : Chained('trial') PathPart('cross_progenies_trial') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $trial = CXGN::Cross->new({ schema => $schema, trial_id => $trial_id});

    my $result = $trial->get_cross_progenies_trial();
    my @crosses;
    foreach my $r (@$result){
        my ($cross_id, $cross_name, $cross_combination, $family_id, $family_name, $progeny_number) =@$r;
        push @crosses, [qq{<a href = "/cross/$cross_id">$cross_name</a>}, $cross_combination, $progeny_number, qq{<a href = "/family/$family_id/">$family_name</a>}];
    }

    $c->stash->{rest} = { data => \@crosses };
}


sub seedlots_from_crossingtrial : Chained('trial') PathPart('seedlots_from_crossingtrial') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $trial = CXGN::Cross->new({schema => $schema, trial_id => $trial_id});

    my $result = $trial->get_seedlots_from_crossingtrial();
    my @crosses;
    foreach my $r (@$result){
        my ($cross_id, $cross_name, $seedlot_id, $seedlot_name) =@$r;
        push @crosses, {
            cross_id => $cross_id,
            cross_name => $cross_name,
            seedlot_id => $seedlot_id,
            seedlot_name => $seedlot_name
        };
    }

    $c->stash->{rest} = { data => \@crosses };

}


sub get_crosses : Chained('trial') PathPart('get_crosses') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $trial = CXGN::Cross->new({ schema => $schema, trial_id => $trial_id});

    my $result = $trial->get_crosses_in_crossing_experiment();
    my @data = @$result;
#    print STDERR "CROSSES =".Dumper(\@data)."\n";

    $c->stash->{rest} = { crosses => \@data };
}


sub get_female_accessions : Chained('trial') PathPart('get_female_accessions') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $trial = CXGN::Cross->new({ schema => $schema, trial_id => $trial_id});

    my $result = $trial->get_female_accessions_in_crossing_experiment();
    my @data = @$result;
#    print STDERR "FEMALE ACCESSIONS =".Dumper(\@data)."\n";

    $c->stash->{rest} = { female_accessions => \@data };
}


sub get_male_accessions : Chained('trial') PathPart('get_male_accessions') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $trial = CXGN::Cross->new({ schema => $schema, trial_id => $trial_id});

    my $result = $trial->get_male_accessions_in_crossing_experiment();
    my @data = @$result;

    $c->stash->{rest} = { male_accessions => \@data };
}


sub get_female_plots : Chained('trial') PathPart('get_female_plots') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $trial = CXGN::Cross->new({ schema => $schema, trial_id => $trial_id});

    my $result = $trial->get_female_plots_in_crossing_experiment();
    my @data = @$result;

    $c->stash->{rest} = { female_plots => \@data };
}


sub get_male_plots : Chained('trial') PathPart('get_male_plots') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $trial = CXGN::Cross->new({ schema => $schema, trial_id => $trial_id});

    my $result = $trial->get_male_plots_in_crossing_experiment();
    my @data = @$result;

    $c->stash->{rest} = { male_plots => \@data };
}


sub get_female_plants : Chained('trial') PathPart('get_female_plants') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $trial = CXGN::Cross->new({ schema => $schema, trial_id => $trial_id});

    my $result = $trial->get_female_plants_in_crossing_experiment();
    my @data = @$result;
#    print STDERR "FEMALE PLANTS =".Dumper(\@data)."\n";

    $c->stash->{rest} = { female_plants => \@data };
}


sub get_male_plants : Chained('trial') PathPart('get_male_plants') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $trial = CXGN::Cross->new({ schema => $schema, trial_id => $trial_id});

    my $result = $trial->get_male_plants_in_crossing_experiment();
    my @data = @$result;

    $c->stash->{rest} = { male_plants => \@data };
}


sub delete_all_crosses_in_crossingtrial : Chained('trial') PathPart('delete_all_crosses_in_crossingtrial') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $trial_id = $c->stash->{trial_id};

    my $trial = CXGN::Cross->new({schema => $schema, trial_id => $trial_id});

    my $result = $trial->get_crosses_in_crossing_experiment();

    foreach my $r (@$result){
        my ($cross_stock_id, $cross_name) =@$r;
        my $cross = CXGN::Cross->new( { schema => $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado'), cross_stock_id => $cross_stock_id });
        my $error = $cross->delete();
        print STDERR "ERROR = $error\n";

        if ($error) {
            $c->stash->{rest} = { error => "An error occurred attempting to delete a cross. ($@)" };
            return;
        }
    }

    $c->stash->{rest} = { success => 1 };
}


sub cross_additional_info_trial : Chained('trial') PathPart('cross_additional_info_trial') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $trial = CXGN::Cross->new({ schema => $schema, trial_id => $trial_id});
    my $result = $trial->get_cross_additional_info_trial();
#    print STDERR "ADDITIONAL INFO =".Dumper($result)."\n";

    my $cross_additional_info_string = $c->config->{cross_additional_info};
    my @column_order = split ',', $cross_additional_info_string;

    my @crosses;
    foreach my $r (@$result){
        my ($cross_id, $cross_name, $cross_combination, $cross_additional_info_hash) =@$r;

        my @row = ( qq{<a href = "/cross/$cross_id">$cross_name</a>}, $cross_combination );
        foreach my $key (@column_order){
          push @row, $cross_additional_info_hash->{$key};
        }

        push @crosses, \@row;
    }

    $c->stash->{rest} = { data => \@crosses };
}


sub downloaded_intercross_file_metadata : Chained('trial') PathPart('downloaded_intercross_file_metadata') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $crosses = CXGN::Cross->new({ schema => $schema, trial_id => $trial_id, file_type => 'intercross_download'});
    my $result = $crosses->get_intercross_file_metadata();

    $c->stash->{rest} = { data => $result };
}


sub uploaded_intercross_file_metadata : Chained('trial') PathPart('uploaded_intercross_file_metadata') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $crosses = CXGN::Cross->new({ schema => $schema, trial_id => $trial_id, file_type => 'intercross_upload'});
    my $result = $crosses->get_intercross_file_metadata();

    $c->stash->{rest} = { data => $result };
}


sub phenotype_heatmap : Chained('trial') PathPart('heatmap') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my $trial_id = $c->stash->{trial_id};
    my $trait_id = $c->req->param("selected");
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my @items = map {@{$_}[0]} @{$c->stash->{trial}->get_plots()};
    #print STDERR Dumper(\@items);
    my @trait_ids = ($trait_id);

    my $layout = $c->stash->{trial_layout};
    my $design_type = $layout->get_design_type();

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        "Native",
        {
            bcs_schema=> $schema,
            data_level=> 'plot',
            trait_list=> \@trait_ids,
            plot_list=>  \@items,
        }
    );
    my $data = $phenotypes_search->search();
    my (@col_No, @row_No, @pheno_val, @plot_Name, @stock_Name, @plot_No, @block_No, @rep_No, @msg, $result, @phenoID);
    foreach my $d (@$data) {
        my $stock_id = $d->{accession_stock_id};
        my $stock_name = $d->{accession_uniquename};
        my $value = $d->{phenotype_value};
        my $plot_id = $d->{obsunit_stock_id};
        my $plot_name = $d->{obsunit_uniquename};
        my $rep = $d->{rep};
        my $block_number = $d->{block};
        my $plot_number = $d->{plot_number};
        my $row_number = $d->{row_number};
        my $col_number = $d->{col_number};
        my $design = $d->{design};
        my $phenotype_id = $d->{phenotype_id};
        if (!$row_number && !$col_number){
            if ($block_number && $design_type ne 'splitplot'){
                $row_number = $block_number;
            } elsif ($rep && !$block_number && $design_type ne 'splitplot'){
                $row_number = $rep;
            } elsif ($design_type eq 'splitplot'){
                $row_number = $rep;
            }
        }

        my $plot_popUp = $plot_name."\nplot_No:".$plot_number."\nblock_No:".$block_number."\nrep_No:".$rep."\nstock:".$stock_name."\nvalue:".$value;
        push @$result, {
            plotname => $plot_name,
            stock => $stock_name,
            plotn => $plot_number,
            blkn=>$block_number,
            rep=>$rep,
            row=>$row_number,
            col=>$col_number,
            pheno=>$value,
            plot_msg=>$plot_popUp,
            pheno_id=>$phenotype_id
        };
        if ($col_number){
            push @col_No, $col_number;
        }
        push @row_No, $row_number;
        push @pheno_val, $value;
        push @plot_Name, $plot_name;
        push @stock_Name, $stock_name;
        push @plot_No, $plot_number;
        push @block_No, $block_number;
        push @rep_No, $rep;
        push @phenoID, $phenotype_id;
    }

    my $false_coord;
    if (!$col_No[0]){
        @col_No = ();
        $false_coord = 'false_coord';
        my @row_instances = uniq @row_No;
        my %unique_row_counts;
        $unique_row_counts{$_}++ for @row_No;
        my @col_number2;
        for my $key (keys %unique_row_counts){
            push @col_number2, (1..$unique_row_counts{$key});
        }
        for (my $i=0; $i < scalar(@$result); $i++){
            @$result[$i]->{'col'} = $col_number2[$i];
            push @col_No, $col_number2[$i];
        }
	}

    my ($min_col, $max_col) = minmax @col_No;
    my ($min_row, $max_row) = minmax @row_No;
    my (@unique_col,@unique_row);
    for my $x (1..$max_col){
        push @unique_col, $x;
    }
    for my $y (1..$max_row){
        push @unique_row, $y;
    }

    my $trial = CXGN::Trial->new({
        bcs_schema => $schema,
        trial_id => $trial_id
    });
    my $data_check = $trial->get_controls();
    my @control_name;
    foreach my $cntrl (@{$data_check}) {
        push @control_name, $cntrl->{'accession_name'};
    }
    #print STDERR Dumper($result);
    $c->stash->{rest} = {
        #phenotypes => $phenotype,
        col => \@col_No,
        row => \@row_No,
        pheno => \@pheno_val,
        plotName => \@plot_Name,
        stock => \@stock_Name,
        plot => \@plot_No,
        block => \@block_No,
        rep => \@rep_No,
        result => $result,
        plot_msg => \@msg,
        col_max => $max_col,
        row_max => $max_row,
        unique_col => \@unique_col,
        unique_row => \@unique_row,
        false_coord => $false_coord,
        phenoID => \@phenoID,
        controls => \@control_name
    };
}

sub get_suppress_plot_phenotype : Chained('trial') PathPart('suppress_phenotype') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'curator', 'curator_access');

    my $schema = $c->stash->{schema};
    my $plot_name = $c->req->param('plot_name');
    my $plot_pheno_value = $c->req->param('phenotype_value');
    my $trait_id = $c->req->param('trait_id');
    my $phenotype_id = $c->req->param('phenotype_id');
    my $trial_id = $c->stash->{trial_id};
    my $trial = $c->stash->{trial};
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();

    my $suppress_return_error = $trial->suppress_plot_phenotype($trait_id, $plot_name, $plot_pheno_value, $phenotype_id, $user_name, $timestamp);
    if ($suppress_return_error) {
        $c->stash->{rest} = { error => $suppress_return_error };
        return;
    }

    $c->stash->{rest} = { success => 1};
}

sub delete_single_assayed_trait : Chained('trial') PathPart('delete_single_trait') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $pheno_ids = $c->req->param('pheno_id') ? JSON::decode_json($c->req->param('pheno_id')) : [];
    my $trait_ids = $c->req->param('traits_id') ? JSON::decode_json($c->req->param('traits_id')) : [];
    my $schema = $c->stash->{schema};
    my $trial = $c->stash->{trial};

    my $delete_trait_return_error = $trial->delete_assayed_trait($c->config->{basepath}, $c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, $pheno_ids, $trait_ids);

    if ($delete_trait_return_error) {
        $c->stash->{rest} = { error => $delete_trait_return_error };
    } else {
        $c->stash->{rest} = { success => 1};
    }
}

sub retrieve_plot_image : Chained('trial') PathPart('retrieve_plot_images') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my $image_ids =  decode_json $c->req->param('image_ids');
    my $plot_name = $c->req->param('plot_name');
    my $plot_id = $c->req->param('plot_id');

    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_id = $c->stash->{trial_id};
    my $stockref;
    my $image_objects;
    my $dbh = $c->dbc->dbh;
    $stockref->{dbh} = $dbh;
    $stockref->{image_ids} =  $image_ids || [] ;
    my $images = $stockref->{image_ids};
    $dbh = $stockref->{dbh};

    #print STDERR Dumper($stockref);
    print "$plot_name and $plot_id and $image_ids\n";

    my $image_html     = "";
    my $m_image_html   = "";
    my $count;
    my @more_is;

    if ($images && !$image_objects) {
        my @image_object_list = map { SGN::Image->new( $dbh , $_ ) }  @$images ;
        $image_objects = \@image_object_list;
    }

    if ($image_objects)  { # don't display anything for empty list of images
        $image_html .= qq|<table cellpadding="5">|;
        foreach my $image_ob (@$image_objects) {
            $count++;
            my $image_id = $image_ob->get_image_id;
            my $image_name = $image_ob->get_name();
            my $image_description = $image_ob->get_description();
            my $image_img  = $image_ob->get_image_url("medium");
            my $small_image = $image_ob->get_image_url("thumbnail");
            my $image_page  = "/image/view/$image_id";

            my $colorbox = qq|<a href="$image_img"  class="stock_image_group" rel="gallery-figures"><img src="$small_image" alt="$image_description" onclick="close_view_plot_image_dialog()"/></a> |;
            my $fhtml = qq|<tr><td width=120>|
              . $colorbox
                . $image_name
                  . "</td><td>"
                    . $image_description
                      . "</td></tr>";

            if ( $count < 3 ) {
                $image_html .= $fhtml;
            }
            else {
                push @more_is, $fhtml;
            }    #more than 3 figures- show these in a hidden div
        }
        $image_html .= "</table>";  #close the table tag or the first 3 figures

        $image_html .= "<script> jQuery(document).ready(function() { jQuery('a.stock_image_group').colorbox(); }); </script>\n";
    }
    $m_image_html .= "<table cellpadding=5>";  #open table tag for the hidden figures #4 and on

    my $more = scalar(@more_is);
    foreach (@more_is) {
        $m_image_html .= $_;
    }

    $m_image_html .= "</table>";    #close tabletag for the hidden figures

    if (@more_is) {    #html_optional_show if there are more than 3 figures
        $image_html .= html_optional_show(
            "Images",
            "<b>See $more more images...</b>",
            qq| $m_image_html |,
            0, #< do not show by default
            'abstract_optional_show', #< don't use the default button-like style
        );
    }

    $c->stash->{rest} = { image_html => $image_html};
}

sub field_trial_from_field_trial : Chained('trial') PathPart('field_trial_from_field_trial') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);


    my $source_field_trials_for_this_trial = $c->stash->{trial}->get_field_trials_source_field_trials();
    my $field_trials_sourced_from_this_trial = $c->stash->{trial}->get_field_trials_sourced_from_field_trials();

    $c->stash->{rest} = {success => 1, source_field_trials => $source_field_trials_for_this_trial, field_trials_sourced => $field_trials_sourced_from_this_trial};
}

sub genotyping_trial_from_field_trial : Chained('trial') PathPart('genotyping_trial_from_field_trial') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $genotyping_trials_from_field_trial = $c->stash->{trial}->get_genotyping_trials_from_field_trial();
    my $field_trials_source_of_genotyping_trial = $c->stash->{trial}->get_field_trials_source_of_genotyping_trial();

    $c->stash->{rest} = {success => 1, genotyping_trials_from_field_trial => $genotyping_trials_from_field_trial, field_trials_source_of_genotyping_trial => $field_trials_source_of_genotyping_trial};
}

sub delete_genotyping_plate_from_field_trial_linkage : Chained('trial') PathPart('delete_genotyping_plate_from_field_trial_linkage') Args(1) {
    my $self = shift;
    my $c = shift;
    my $field_trial_id = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");

    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'curator', 'curator_access');

    my $result = $c->stash->{trial}->delete_genotyping_plate_from_field_trial_linkage($field_trial_id, $user_role);

    if (exists($result->{errors})) {
        $c->stash->{rest} = { error => $result->{errors} };
    }
    else {
        $c->stash->{rest} = { success => 1 };
    }
}

sub crossing_trial_from_field_trial : Chained('trial') PathPart('crossing_trial_from_field_trial') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $crossing_trials_from_field_trial = $c->stash->{trial}->get_crossing_trials_from_field_trial();
    my $field_trials_source_of_crossing_trial = $c->stash->{trial}->get_field_trials_source_of_crossing_trial();

    $c->stash->{rest} = {success => 1, crossing_trials_from_field_trial => $crossing_trials_from_field_trial, field_trials_source_of_crossing_trial => $field_trials_source_of_crossing_trial};
}

sub trial_correlate_traits : Chained('trial') PathPart('correlate_traits') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $schema = $c->stash->{schema};
    my $trait_ids = decode_json $c->req->param('trait_ids');
    my $obsunit_level = $c->req->param('observation_unit_level');
    my $correlation_type = $c->req->param('correlation_type');

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$schema,
            data_level=>$obsunit_level,
            trait_list=>$trait_ids,
            trial_list=>[$c->stash->{trial_id}],
            include_timestamp=>0,
            exclude_phenotype_outlier=>0
        }
    );
    my ($data, $unique_traits) = $phenotypes_search->search();
    my @sorted_trait_names = sort keys %$unique_traits;

    if (scalar(@$data) == 0) {
        $c->stash->{rest} = { error => "There are no phenotypes for the trials and traits you have selected!"};
        return;
    }

    my %phenotype_data;
    my %trait_hash;
    my %seen_obsunit_ids;
    foreach my $obs_unit (@$data){
        my $obsunit_id = $obs_unit->{observationunit_stock_id};
        my $observations = $obs_unit->{observations};
        foreach (@$observations){
            $phenotype_data{$obsunit_id}->{$_->{trait_id}} = $_->{value};
            $trait_hash{$_->{trait_id}} = $_->{trait_name};
        }
        $seen_obsunit_ids{$obsunit_id}++;
    }
    my @sorted_obs_units = sort keys %seen_obsunit_ids;

    my $header_string = join ',', @$trait_ids;

    my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
    my $tmp_stats_dir = $shared_cluster_dir_config."/tmp_trial_correlation";
    mkdir $tmp_stats_dir if ! -d $tmp_stats_dir;
    my ($stats_tempfile_fh, $stats_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_fh, $stats_out_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);

    open(my $F, ">", $stats_tempfile) || die "Can't open file ".$stats_tempfile;
        print $F $header_string."\n";
        foreach my $s (@sorted_obs_units) {
            my @line = ();
            foreach my $t (@$trait_ids) {
                my $val = $phenotype_data{$s}->{$t};
                if (!$val && $val != 0) {
                    $val = 'NA';
                }
                push @line, $val;
            }
            my $line_string = join ',', @line;
            print $F "$line_string\n";
        }
    close($F);

    my $cmd = 'R -e "library(data.table);
    mat <- fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\');
    res <- cor(mat, method=\''.$correlation_type.'\', use = \'complete.obs\')
    res_rounded <- round(res, 2)
    write.table(res_rounded, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');"';
    print STDERR Dumper $cmd;
    my $status = system($cmd);

    my $csv = Text::CSV->new({ sep_char => "\t" });
    my @result;
    open(my $fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
        print STDERR "Opened $stats_out_tempfile\n";
        my $header = <$fh>;
        my @header_cols;
        if ($csv->parse($header)) {
            @header_cols = $csv->fields();
        }

        my @header_trait_names = ("Trait");
        foreach (@header_cols) {
            push @header_trait_names, $trait_hash{$_};
        }
        push @result, \@header_trait_names;

        while (my $row = <$fh>) {
            my @columns;
            if ($csv->parse($row)) {
                @columns = $csv->fields();
            }

            my $trait_id = shift @columns;
            my @line = ($trait_hash{$trait_id});
            push @line, @columns;
            push @result, \@line;
        }
    close($fh);

    $c->stash->{rest} = {success => 1, result => \@result};
}

sub trial_spatial_2dspl_correct_traits : Chained('trial') PathPart('spatial_2dspl_correct_traits') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $schema = $c->stash->{schema};
    my $trial_id = $c->stash->{trial_id};
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $trait_ids = decode_json $c->req->param('trait_ids');
    my $obsunit_level = $c->req->param('observation_unit_level');
    my $model_type = $c->req->param('model_type');
    my $tolparinv = $c->req->param('tolparinv');
    my $genomic_relationship_type = $c->req->param('genomic_relationship_type');
    my $genomic_relationship_protocol_id = $genomic_relationship_type eq 'grm' ? $c->req->param('genomic_relationship_protocol_id') : undef;

    my $csv = Text::CSV->new({ sep_char => "\t" });
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$schema,
            data_level=>$obsunit_level,
            trait_list=>$trait_ids,
            trial_list=>[$c->stash->{trial_id}],
            include_timestamp=>0,
            exclude_phenotype_outlier=>0
        }
    );
    my ($data, $unique_traits) = $phenotypes_search->search();
    my @sorted_trait_names = sort keys %$unique_traits;

    if (scalar(@$data) == 0) {
        $c->stash->{rest} = { error => "There are no phenotypes for the trials and traits you have selected!"};
        return;
    }

    my %seen_trial_ids;
    my @plot_ids_ordered;
    my %obsunit_row_col;
    my %seen_rows;
    my %seen_cols;
    my $min_row = 1000000000000000;
    my $max_row = -1000000000000000;
    my $min_col = 1000000000000000;
    my $max_col = -1000000000000000;
    my %plot_id_map;
    my %seen_plot_names;
    my %seen_plots;
    my %stock_row_col;
    my %stock_name_row_col;
    my %stock_row_col_id;
    my %unique_accessions;
    my %stock_info;
    my %phenotype_data_original;
    my %seen_trait_names;
    my $phenotype_min_original = 1000000000000000;
    my $phenotype_max_original = -1000000000000000;
    my %trait_to_time_map;
    my %trait_time_map;
    foreach my $obs_unit (@$data) {
        my $obsunit_stock_uniquename = $obs_unit->{observationunit_uniquename};

        my $observations = $obs_unit->{observations};
        foreach (@$observations){
            my $value = $_->{value};
            my $trait_name = $_->{trait_name};
            my $trait_id = $_->{trait_id};
            $phenotype_data_original{$obsunit_stock_uniquename}->{$trait_name} = $value;
            $seen_trait_names{$trait_name} = $trait_id;

            if ($value < $phenotype_min_original) {
                $phenotype_min_original = $value;
            }
            elsif ($value >= $phenotype_max_original) {
                $phenotype_max_original = $value;
            }

            if ($_->{associated_image_project_time_json}) {
                my $related_time_terms_json = decode_json $_->{associated_image_project_time_json};
                my $time_days_cvterm = $related_time_terms_json->{day};
                my $time_term_string = $time_days_cvterm;
                my $time_days = (split '\|', $time_days_cvterm)[0];
                my $time_value = (split ' ', $time_days)[1];
                $trait_to_time_map{$trait_name} = $time_value;
                $trait_time_map{$trait_name} = $time_days_cvterm;
            }
        }
    }

    my $phenotypes_search_all = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$schema,
            data_level=>$obsunit_level,
            trial_list=>[$c->stash->{trial_id}],
            include_timestamp=>0,
            exclude_phenotype_outlier=>0
        }
    );
    my ($data_all, $unique_traits_all) = $phenotypes_search_all->search();
    my @sorted_trait_names_all = sort keys %$unique_traits_all;

    if (scalar(@$data_all) == 0) {
        $c->stash->{rest} = { error => "There are no phenotypes for the trials and traits you have selected!"};
        return;
    }

    foreach my $obs_unit (@$data_all) {
        my $germplasm_name = $obs_unit->{germplasm_uniquename};
        my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
        my $replicate_number = $obs_unit->{obsunit_rep} || '';
        my $block_number = $obs_unit->{obsunit_block} || '';
        my $obsunit_stock_id = $obs_unit->{observationunit_stock_id};
        my $obsunit_stock_uniquename = $obs_unit->{observationunit_uniquename};
        my $row_number = $obs_unit->{obsunit_row_number} || '';
        my $col_number = $obs_unit->{obsunit_col_number} || '';
        $seen_trial_ids{$obs_unit->{trial_id}}++;
        push @plot_ids_ordered, $obsunit_stock_id;

        if ($row_number < $min_row) {
            $min_row = $row_number;
        }
        elsif ($row_number >= $max_row) {
            $max_row = $row_number;
        }
        if ($col_number < $min_col) {
            $min_col = $col_number;
        }
        elsif ($col_number >= $max_col) {
            $max_col = $col_number;
        }

        $obsunit_row_col{$row_number}->{$col_number} = {
            stock_id => $obsunit_stock_id,
            stock_uniquename => $obsunit_stock_uniquename
        };
        $seen_rows{$row_number}++;
        $seen_cols{$col_number}++;
        $plot_id_map{$obsunit_stock_id} = $obsunit_stock_uniquename;
        $seen_plot_names{$obsunit_stock_uniquename}++;
        $seen_plots{$obsunit_stock_id} = $obsunit_stock_uniquename;
        $stock_row_col{$obsunit_stock_id} = {
            row_number => $row_number,
            col_number => $col_number,
            obsunit_stock_id => $obsunit_stock_id,
            obsunit_name => $obsunit_stock_uniquename,
            rep => $replicate_number,
            block => $block_number,
            germplasm_stock_id => $germplasm_stock_id,
            germplasm_name => $germplasm_name
        };
        $stock_name_row_col{$obsunit_stock_uniquename} = {
            row_number => $row_number,
            col_number => $col_number,
            obsunit_stock_id => $obsunit_stock_id,
            obsunit_name => $obsunit_stock_uniquename,
            rep => $replicate_number,
            block => $block_number,
            germplasm_stock_id => $germplasm_stock_id,
            germplasm_name => $germplasm_name
        };
        $stock_row_col_id{$row_number}->{$col_number} = $obsunit_stock_id;
        $unique_accessions{$germplasm_name}++;
        $stock_info{"S".$germplasm_stock_id} = {
            uniquename => $germplasm_name
        };
    }
    my @unique_plot_names = sort keys %seen_plot_names;

    if (scalar(keys %seen_cols) < 2) {
        $c->stash->{rest} = { error => "There are no columns in this field trial! Upload the row and column number information in the Field Layout Tools section!"};
        return;
    }
    if (scalar(keys %seen_rows) < 2) {
        $c->stash->{rest} = { error => "There are no rows in this field trial! Upload the row and column number information in the Field Layout Tools section!"};
        return;
    }

    my $trait_name_encoded = 1;
    my %trait_name_encoder;
    my %trait_name_encoder_rev;
    foreach my $trait_name (@sorted_trait_names) {
        if (!exists($trait_name_encoder{$trait_name})) {
            my $trait_name_e = 't'.$trait_name_encoded;
            $trait_name_encoder{$trait_name} = $trait_name_e;
            $trait_name_encoder_rev{$trait_name_e} = $trait_name;
            $trait_name_encoded++;
        }
    }
    print STDERR Dumper \%trait_name_encoder;
    print STDERR Dumper \%trait_name_encoder_rev;
    print STDERR Dumper \%trait_to_time_map;
    print STDERR Dumper \%trait_time_map;

    my @data_matrix_original;
    foreach my $p (@unique_plot_names) {
        my $obsunit_stock_id = $stock_name_row_col{$p}->{obsunit_stock_id};
        my $row_number = $stock_name_row_col{$p}->{row_number};
        my $col_number = $stock_name_row_col{$p}->{col_number};
        my $replicate = $stock_name_row_col{$p}->{rep};
        my $block = $stock_name_row_col{$p}->{block};
        my $germplasm_stock_id = $stock_name_row_col{$p}->{germplasm_stock_id};
        my $germplasm_name = $stock_name_row_col{$p}->{germplasm_name};

        my @row = ($replicate, $block, "S".$germplasm_stock_id, $obsunit_stock_id, $row_number, $col_number, $row_number, $col_number);

        foreach my $t (@sorted_trait_names) {
            if (defined($phenotype_data_original{$p}->{$t})) {
                push @row, $phenotype_data_original{$p}->{$t};
            } else {
                print STDERR $p." : $t : $germplasm_name : NA \n";
                push @row, 'NA';
            }
        }
        push @data_matrix_original, \@row;
    }

    my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
    my $tmp_stats_dir = $shared_cluster_dir_config."/tmp_trial_2dspl";
    mkdir $tmp_stats_dir if ! -d $tmp_stats_dir;
    my $dir = $c->tempfiles_subdir('/tmp_trial_2dspl');
    my ($stats_tempfile_fh, $stats_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_fh, $stats_out_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_residual_fh, $stats_out_tempfile_residual) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_varcomp_fh, $stats_out_tempfile_varcomp) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_2dspl_fh, $stats_out_tempfile_2dspl) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_heritability_fh, $stats_out_tempfile_heritability) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_pheno_heatmaps_fh, $stats_out_tempfile_pheno_heatmaps) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_spatial_heatmaps_fh, $stats_out_tempfile_spatial_heatmaps) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_fitted_heatmaps_fh, $stats_out_tempfile_fitted_heatmaps) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_residuals_heatmaps_fh, $stats_out_tempfile_residuals_heatmaps) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($effects_original_line_chart_tempfile_fh, $effects_original_line_chart_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);

    my ($grm_tempfile_fh, $grm_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);

    my ($stats_out_tempfile_rds_fh, $stats_out_tempfile_rds) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    $stats_out_tempfile_rds .= '.rds';

    my @phenotype_header = ("replicate", "block", "id", "plot_id", "rowNumber", "colNumber", "rowNumberFactor", "colNumberFactor");
    foreach (@sorted_trait_names) {
        push @phenotype_header, $trait_name_encoder{$_};
    }
    my $header_string = join ',', @phenotype_header;

    open(my $F, ">", $stats_tempfile) || die "Can't open file ".$stats_tempfile;
        print $F $header_string."\n";
        foreach (@data_matrix_original) {
            my $line = join ',', @$_;
            print $F "$line\n";
        }
    close($F);

    if (!$genomic_relationship_protocol_id) {
        $genomic_relationship_protocol_id = undef;
    }

    my $geno = CXGN::Genotype::GRM->new({
        bcs_schema=>$schema,
        people_schema=>$people_schema,
        grm_temp_file=>$grm_tempfile,
        cache_root=>$c->config->{cache_file_path},
        trial_id_list=>[$trial_id],
        protocol_id=>$genomic_relationship_protocol_id,
        download_format=>'three_column_reciprocal'
    });
    my $grm_data = $geno->download_grm(
        'data',
        $shared_cluster_dir_config,
        $c->config->{backend},
        $c->config->{cluster_host},
        $c->config->{'web_cluster_queue'},
        $c->config->{basepath}
    );

    open(my $F2, ">", $grm_out_tempfile) || die "Can't open file ".$grm_out_tempfile;
        print $F2 $grm_data;
    close($F2);
    my $grm_file = $grm_out_tempfile;

    my @encoded_traits = values %trait_name_encoder;
    my $encoded_trait_string = join ',', @encoded_traits;
    my $number_traits = scalar(@encoded_traits);
    my $cbind_string = $number_traits > 1 ? "cbind($encoded_trait_string)" : $encoded_trait_string;

    my $statistics_cmd_reading = 'R -e "library(sommer); library(data.table); library(reshape2);
    mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
    geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
    geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
    geno_mat[is.na(geno_mat)] <- 0;
    mat\$rowNumber <- as.numeric(mat\$rowNumber);
    mat\$colNumber <- as.numeric(mat\$colNumber);
    ';

    my $multivariate_cmd_model = 'mix <- mmer('.$cbind_string.'~1 + replicate, random=~vs(id, Gu=geno_mat, Gtc=unsm('.$number_traits.')) + spl2Da(rowNumber, colNumber), rcov=~vs(units, Gtc=unsm('.$number_traits.')), data=mat, tolparinv='.$tolparinv.');
    if (!is.null(mix\$U)) {
    #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
    write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');
    write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\'\t\');
    write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');
    spatial_blup_results <- data.frame(plot_id = mat\$plot_id);
    W <- with(mat, spl2Da(rowNumber, colNumber));
    X <- W\$Z\$\`A:all\`;
    ';
    my $trait_index = 1;
    foreach my $enc_trait_name (@encoded_traits) {
        $multivariate_cmd_model .= '
    blups'.$trait_index.' <- mix\$U\$\`A:all\`\$'.$enc_trait_name.';
    spatial_blup_results\$'.$enc_trait_name.' <- X %*% blups'.$trait_index.';
        ';
        $trait_index++;
    }
    $multivariate_cmd_model .= 'write.table(spatial_blup_results, file=\''.$stats_out_tempfile_2dspl.'\', row.names=FALSE, col.names=TRUE, sep=\'\t\');
    h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V3) );
    e2 <- vpredict(mix, e2 ~ (V2) / ( V2+V3) );
    write.table(data.frame(h2=h2\$Estimate, hse=h2\$SE, e2=e2\$Estimate, ese=e2\$SE), file=\''.$stats_out_tempfile_heritability.'\', row.names=FALSE, col.names=TRUE, sep=\'\t\');
    saveRDS(mix, file=\''.$stats_out_tempfile_rds.'\');
    }
    "';

    my %result_blup_data_original;
    my $genetic_effect_min_original = 10000000000000;
    my $genetic_effect_max_original = -10000000000000;
    my $genetic_effect_sum_original = 0;
    my $genetic_effect_sum_square_original = 0;
    my %result_blup_spatial_data_original;
    my $env_effect_min_original = 10000000000000;
    my $env_effect_max_original = -10000000000000;
    my $env_effect_sum_original = 0;
    my $env_effect_sum_square_original = 0;
    my %result_residual_data_original;
    my $residual_sum_original = 0;
    my $residual_sum_square_original = 0;
    my %result_fitted_data_original;
    my $model_sum_square_residual_original = 0;
    my @varcomp_original;
    my @varcomp_herit;
    my @model_rds_files;
    my $statistics_cvterm_name = '';

    if ($model_type eq 'sommer_2dspl_multi') {
        $statistics_cvterm_name = 'Multivariate linear mixed model 2D spline spatial BLUPs using genetic relationship matrix and row and column spatial effects computed using Sommer R|SGNSTAT:0000003';

        my $statistics_cmd = $statistics_cmd_reading.$multivariate_cmd_model;

        eval {
            my $status = system($statistics_cmd);
        };
        my $run_stats_fault = 0;
        if ($@) {
            print STDERR "R ERROR\n";
            print STDERR Dumper $@;
            $run_stats_fault = 1;
        }

        push @model_rds_files, $stats_out_tempfile_rds;

        my $current_gen_row_count = 0;
        my $current_env_row_count = 0;

        open(my $fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header = <$fh>;
            my @header_cols;
            if ($csv->parse($header)) {
                @header_cols = $csv->fields();
            }

            while (my $row = <$fh>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $col_counter = 0;
                foreach my $encoded_trait (@header_cols) {
                    my $trait = $trait_name_encoder_rev{$encoded_trait};
                    my $stock_id = $columns[0];

                    my $stock_name = $stock_info{$stock_id}->{uniquename};
                    my $value = $columns[$col_counter+1];
                    if (defined $value && $value ne '') {
                        $result_blup_data_original{$stock_name}->{$trait} = [$value, $timestamp, $user_name, '', ''];

                        if ($value < $genetic_effect_min_original) {
                            $genetic_effect_min_original = $value;
                        }
                        elsif ($value >= $genetic_effect_max_original) {
                            $genetic_effect_max_original = $value;
                        }

                        $genetic_effect_sum_original += abs($value);
                        $genetic_effect_sum_square_original = $genetic_effect_sum_square_original + $value*$value;
                    }
                    $col_counter++;
                }
                $current_gen_row_count++;
            }
        close($fh);

        open(my $fh_2dspl, '<', $stats_out_tempfile_2dspl) or die "Could not open file '$stats_out_tempfile_2dspl' $!";
            print STDERR "Opened $stats_out_tempfile_2dspl\n";
            my $header_2dspl = <$fh_2dspl>;
            my @header_cols_2dspl;
            if ($csv->parse($header_2dspl)) {
                @header_cols_2dspl = $csv->fields();
            }
            shift @header_cols_2dspl;
            while (my $row_2dspl = <$fh_2dspl>) {
                my @columns;
                if ($csv->parse($row_2dspl)) {
                    @columns = $csv->fields();
                }
                my $col_counter = 0;
                foreach my $encoded_trait (@header_cols_2dspl) {
                    my $trait = $trait_name_encoder_rev{$encoded_trait};
                    my $plot_id = $columns[0];

                    my $plot_name = $plot_id_map{$plot_id};
                    my $value = $columns[$col_counter+1];
                    if (defined $value && $value ne '') {
                        $result_blup_spatial_data_original{$plot_name}->{$trait} = [$value, $timestamp, $user_name, '', ''];

                        if ($value < $env_effect_min_original) {
                            $env_effect_min_original = $value;
                        }
                        elsif ($value >= $env_effect_max_original) {
                            $env_effect_max_original = $value;
                        }

                        $env_effect_sum_original += abs($value);
                        $env_effect_sum_square_original = $env_effect_sum_square_original + $value*$value;
                    }
                    $col_counter++;
                }
                $current_env_row_count++;
            }
        close($fh_2dspl);

        open(my $fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual = <$fh_residual>;
            my @header_cols_residual;
            if ($csv->parse($header_residual)) {
                @header_cols_residual = $csv->fields();
            }
            while (my $row = <$fh_residual>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                foreach (0..$number_traits-1) {
                    my $trait_name = $sorted_trait_names[$_];
                    my $residual = $columns[1 + $_];
                    my $fitted = $columns[1 + $number_traits + $_];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_original{$stock_name}->{$trait_name} = [$residual, $timestamp, $user_name, '', ''];
                        $residual_sum_original += abs($residual);
                        $residual_sum_square_original = $residual_sum_square_original + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_original{$stock_name}->{$trait_name} = [$fitted, $timestamp, $user_name, '', ''];
                    }
                    $model_sum_square_residual_original = $model_sum_square_residual_original + $residual*$residual;
                }
            }
        close($fh_residual);

        open(my $fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
            print STDERR "Opened $stats_out_tempfile_varcomp\n";
            my $header_varcomp = <$fh_varcomp>;
            my @header_cols_varcomp;
            if ($csv->parse($header_varcomp)) {
                @header_cols_varcomp = $csv->fields();
            }
            while (my $row = <$fh_varcomp>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_original, \@columns;
            }
        close($fh_varcomp);

        open(my $fh_herit, '<', $stats_out_tempfile_heritability) or die "Could not open file '$stats_out_tempfile_heritability' $!";
            print STDERR "Opened $stats_out_tempfile_heritability\n";
            my $header_herit = <$fh_herit>;
            my @header_cols_herit;
            if ($csv->parse($header_herit)) {
                @header_cols_herit = $csv->fields();
            }
            while (my $row = <$fh_herit>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_herit, \@columns;
            }
        close($fh_herit);

        if ($current_env_row_count == 0 || $current_gen_row_count == 0) {
            $run_stats_fault = 1;
        }

        if ($run_stats_fault == 1) {
            print STDERR "ERROR IN R CMD\n";
            return {error=>'Error in R! Try a larger tolerance'};
        }
    }
    elsif ($model_type eq 'sommer_2dspl_uni') {
        $statistics_cvterm_name = 'Univariate linear mixed model 2D spline spatial BLUPs using genetic relationship matrix and row and column spatial effects computed using Sommer R|SGNSTAT:0000039';

        foreach my $t (@encoded_traits) {

            my ($stats_out_tempfile_rds_fh, $stats_out_tempfile_rds) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
            $stats_out_tempfile_rds .= '.rds';

            my $univariate_cmd_model = 'mix <- mmer('.$t.'~1 + replicate, random=~vs(id, Gu=geno_mat) + spl2Da(rowNumber, colNumber), rcov=~vs(units), data=mat, tolparinv='.$tolparinv.');
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\'\t\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');
            spatial_blup_results <- data.frame(plot_id = mat\$plot_id);
            W <- with(mat, spl2Da(rowNumber, colNumber));
            X <- W\$Z\$\`A:all\`;
            blups1 <- mix\$U\$\`A:all\`\$'.$t.';
            spatial_blup_results\$'.$t.' <- X %*% blups1;
            write.table(spatial_blup_results, file=\''.$stats_out_tempfile_2dspl.'\', row.names=FALSE, col.names=TRUE, sep=\'\t\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V3) );
            e2 <- vpredict(mix, e2 ~ (V2) / ( V2+V3) );
            write.table(data.frame(h2=h2\$Estimate, hse=h2\$SE, e2=e2\$Estimate, ese=e2\$SE), file=\''.$stats_out_tempfile_heritability.'\', row.names=FALSE, col.names=TRUE, sep=\'\t\');
            saveRDS(mix, file=\''.$stats_out_tempfile_rds.'\');
            }
            "';

            my $statistics_cmd = $statistics_cmd_reading.$univariate_cmd_model;

            eval {
                my $status = system($statistics_cmd);
            };
            my $run_stats_fault = 0;
            if ($@) {
                print STDERR "R ERROR\n";
                print STDERR Dumper $@;
                $run_stats_fault = 1;
            }

            push @model_rds_files, $stats_out_tempfile_rds;

            my $current_gen_row_count = 0;
            my $current_env_row_count = 0;

            open(my $fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                my $header = <$fh>;
                my @header_cols;
                if ($csv->parse($header)) {
                    @header_cols = $csv->fields();
                }

                while (my $row = <$fh>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    my $col_counter = 0;
                    foreach my $encoded_trait (@header_cols) {
                        if ($encoded_trait eq $t) {
                            my $trait = $trait_name_encoder_rev{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_original{$stock_name}->{$trait} = [$value, $timestamp, $user_name, '', ''];

                                if ($value < $genetic_effect_min_original) {
                                    $genetic_effect_min_original = $value;
                                }
                                elsif ($value >= $genetic_effect_max_original) {
                                    $genetic_effect_max_original = $value;
                                }

                                $genetic_effect_sum_original += abs($value);
                                $genetic_effect_sum_square_original = $genetic_effect_sum_square_original + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                    $current_gen_row_count++;
                }
            close($fh);

            open(my $fh_2dspl, '<', $stats_out_tempfile_2dspl) or die "Could not open file '$stats_out_tempfile_2dspl' $!";
                print STDERR "Opened $stats_out_tempfile_2dspl\n";
                my $header_2dspl = <$fh_2dspl>;
                my @header_cols_2dspl;
                if ($csv->parse($header_2dspl)) {
                    @header_cols_2dspl = $csv->fields();
                }
                shift @header_cols_2dspl;
                while (my $row_2dspl = <$fh_2dspl>) {
                    my @columns;
                    if ($csv->parse($row_2dspl)) {
                        @columns = $csv->fields();
                    }
                    my $col_counter = 0;
                    foreach my $encoded_trait (@header_cols_2dspl) {
                        if ($encoded_trait eq $t) {
                            my $trait = $trait_name_encoder_rev{$encoded_trait};
                            my $plot_id = $columns[0];

                            my $plot_name = $plot_id_map{$plot_id};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_spatial_data_original{$plot_name}->{$trait} = [$value, $timestamp, $user_name, '', ''];

                                if ($value < $env_effect_min_original) {
                                    $env_effect_min_original = $value;
                                }
                                elsif ($value >= $env_effect_max_original) {
                                    $env_effect_max_original = $value;
                                }

                                $env_effect_sum_original += abs($value);
                                $env_effect_sum_square_original = $env_effect_sum_square_original + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                    $current_env_row_count++;
                }
            close($fh_2dspl);

            open(my $fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                my $header_residual = <$fh_residual>;
                my @header_cols_residual;
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev{$t};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_original{$stock_name}->{$trait_name} = [$residual, $timestamp, $user_name, '', ''];
                        $residual_sum_original += abs($residual);
                        $residual_sum_square_original = $residual_sum_square_original + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_original{$stock_name}->{$trait_name} = [$fitted, $timestamp, $user_name, '', ''];
                    }
                    $model_sum_square_residual_original = $model_sum_square_residual_original + $residual*$residual;
                }
            close($fh_residual);

            open(my $fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                my $header_varcomp = <$fh_varcomp>;
                my @header_cols_varcomp;
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original, \@columns;
                }
            close($fh_varcomp);

            open(my $fh_herit, '<', $stats_out_tempfile_heritability) or die "Could not open file '$stats_out_tempfile_heritability' $!";
                print STDERR "Opened $stats_out_tempfile_heritability\n";
                my $header_herit = <$fh_herit>;
                my @header_cols_herit;
                if ($csv->parse($header_herit)) {
                    @header_cols_herit = $csv->fields();
                }
                while (my $row = <$fh_herit>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_herit, \@columns;
                }
            close($fh_herit);

            if ($current_env_row_count == 0 || $current_gen_row_count == 0) {
                $run_stats_fault = 1;
            }

            if ($run_stats_fault == 1) {
                print STDERR "ERROR IN R CMD\n";
                return {error=>'Error in R! Try a larger tolerance'};
            }
        }
    }

    open(my $F_pheno, ">", $stats_out_tempfile_pheno_heatmaps) || die "Can't open file ".$stats_out_tempfile_pheno_heatmaps;
        print $F_pheno "trait_type,row,col,value\n";
        foreach my $p (@unique_plot_names) {
            foreach my $t (@sorted_trait_names) {
                my $trait = defined($trait_to_time_map{$t}) ? $trait_to_time_map{$t}." DAP" : $t;
                my $val = $phenotype_data_original{$p}->{$t};
                my @row = ($trait, $stock_name_row_col{$p}->{row_number}, $stock_name_row_col{$p}->{col_number}, $val);
                my $line = join ',', @row;
                print $F_pheno "$line\n";
            }
        }
    close($F_pheno);

    open(my $F_eff, ">", $stats_out_tempfile_spatial_heatmaps) || die "Can't open file ".$stats_out_tempfile_spatial_heatmaps;
        print $F_eff "trait_type,row,col,value\n";
        foreach my $p (@unique_plot_names) {
            foreach my $t (@sorted_trait_names) {
                my $val = defined($result_blup_spatial_data_original{$p}->{$t}->[0]) ? $result_blup_spatial_data_original{$p}->{$t}->[0] : 'NA';
                my @row = ($trait_name_encoder{$t}." Spatial Effect", $stock_name_row_col{$p}->{row_number}, $stock_name_row_col{$p}->{col_number}, $val);
                my $line = join ',', @row;
                print $F_eff "$line\n";
            }
        }
    close($F_eff);

    open(my $F_fitted, ">", $stats_out_tempfile_fitted_heatmaps) || die "Can't open file ".$stats_out_tempfile_fitted_heatmaps;
        print $F_fitted "trait_type,row,col,value\n";
        foreach my $p (@unique_plot_names) {
            foreach my $t (@sorted_trait_names) {
                my $val = defined($result_fitted_data_original{$p}->{$t}->[0]) ? $result_fitted_data_original{$p}->{$t}->[0] : 'NA';
                my @row = ($trait_name_encoder{$t}." Fitted Value", $stock_name_row_col{$p}->{row_number}, $stock_name_row_col{$p}->{col_number}, $val);
                my $line = join ',', @row;
                print $F_fitted "$line\n";
            }
        }
    close($F_fitted);

    open(my $F_res, ">", $stats_out_tempfile_residuals_heatmaps) || die "Can't open file ".$stats_out_tempfile_residuals_heatmaps;
        print $F_res "trait_type,row,col,value\n";
        foreach my $p (@unique_plot_names) {
            foreach my $t (@sorted_trait_names) {
                my $val = defined($result_residual_data_original{$p}->{$t}->[0]) ? $result_residual_data_original{$p}->{$t}->[0] : 'NA';
                my @row = ($trait_name_encoder{$t}." Residual Value", $stock_name_row_col{$p}->{row_number}, $stock_name_row_col{$p}->{col_number}, $val);
                my $line = join ',', @row;
                print $F_res "$line\n";
            }
        }
    close($F_res);

    my $stats_out_tempfile_spatial_heatmaps_plot_string = $c->tempfile( TEMPLATE => 'tmp_trial_2dspl/figureXXXX');
    $stats_out_tempfile_spatial_heatmaps_plot_string .= '.png';
    my $stats_out_tempfile_spatial_heatmaps_plot = $c->config->{basepath}."/".$stats_out_tempfile_spatial_heatmaps_plot_string;

    my $output_plot_row = 'row';
    my $output_plot_col = 'col';
    if ($max_col > $max_row) {
        $output_plot_row = 'col';
        $output_plot_col = 'row';
    }

    my $cmd_spatialfirst_plot_1 = 'R -e "library(data.table); library(ggplot2); library(dplyr); library(viridis); library(GGally); library(gridExtra); library(grid);
    mat_orig <- fread(\''.$stats_out_tempfile_pheno_heatmaps.'\', header=TRUE, sep=\',\');
    mat_eff <- fread(\''.$stats_out_tempfile_spatial_heatmaps.'\', header=TRUE, sep=\',\');
    mat_fit <- fread(\''.$stats_out_tempfile_fitted_heatmaps.'\', header=TRUE, sep=\',\');
    mat_res <- fread(\''.$stats_out_tempfile_residuals_heatmaps.'\', header=TRUE, sep=\',\');
    gg1 <- ggplot(mat_orig, aes('.$output_plot_col.', '.$output_plot_row.', fill=value)) + geom_tile() + scale_fill_viridis(discrete=FALSE) + coord_equal() + facet_wrap(~trait_type, ncol='.scalar(@sorted_trait_names).');
    gg2 <- ggplot(mat_eff, aes('.$output_plot_col.', '.$output_plot_row.', fill=value)) + geom_tile() + scale_fill_viridis(discrete=FALSE) + coord_equal() + facet_wrap(~trait_type, ncol='.scalar(@sorted_trait_names).');
    gg3 <- ggplot(mat_fit, aes('.$output_plot_col.', '.$output_plot_row.', fill=value)) + geom_tile() + scale_fill_viridis(discrete=FALSE) + coord_equal() + facet_wrap(~trait_type, ncol='.scalar(@sorted_trait_names).');
    gg4 <- ggplot(mat_res, aes('.$output_plot_col.', '.$output_plot_row.', fill=value)) + geom_tile() + scale_fill_viridis(discrete=FALSE) + coord_equal() + facet_wrap(~trait_type, ncol='.scalar(@sorted_trait_names).');
    gg <- grid.arrange(gg1, gg2, gg3, gg4, ncol=1, top=textGrob(\'Phenotypes, Spatial Effects, Fitted and Residual Values\'), bottom=textGrob(\'Time\') );
    ggsave(\''.$stats_out_tempfile_spatial_heatmaps_plot.'\', gg, device=\'png\', width=20, height=30, units=\'in\');
    "';
    # print STDERR Dumper $cmd_spatialfirst_plot_1;
    my $status_spatialfirst_plot_1 = system($cmd_spatialfirst_plot_1);


    my @sorted_germplasm_names = sort keys %unique_accessions;

    open(my $F_gen, ">", $effects_original_line_chart_tempfile) || die "Can't open file ".$effects_original_line_chart_tempfile;
        print $F_gen "germplasmName,time,value\n";
        foreach my $p (@sorted_germplasm_names) {
            foreach my $t (@sorted_trait_names) {
                my $val = $result_blup_data_original{$p}->{$t}->[0];
                my @row = ($p, $trait_to_time_map{$t}, $val);
                my $line = join ',', @row;
                print $F_gen "$line\n";
            }
        }
    close($F_gen);

    my @set = ('0' ..'9', 'A' .. 'F');
    my @colors;
    for (1..scalar(@sorted_germplasm_names)) {
        my $str = join '' => map $set[rand @set], 1 .. 6;
        push @colors, '#'.$str;
    }
    my $color_string = join '\',\'', @colors;

    my $genetic_effects_figure_tempfile_string = $c->tempfile( TEMPLATE => 'tmp_trial_2dspl/figureXXXX');
    $genetic_effects_figure_tempfile_string .= '.png';
    my $genetic_effects_figure_tempfile = $c->config->{basepath}."/".$genetic_effects_figure_tempfile_string;

    my $cmd_gen_plot = 'R -e "library(data.table); library(ggplot2); library(GGally); library(gridExtra);
    mat <- fread(\''.$effects_original_line_chart_tempfile.'\', header=TRUE, sep=\',\');
    mat\$time <- as.numeric(as.character(mat\$time));
    options(device=\'png\');
    par();
    sp <- ggplot(mat, aes(x = time, y = value)) +
        geom_line(aes(color = germplasmName), size = 1) +
        scale_fill_manual(values = c(\''.$color_string.'\')) +
        theme_minimal();
    sp <- sp + guides(shape = guide_legend(override.aes = list(size = 0.5)));
    sp <- sp + guides(color = guide_legend(override.aes = list(size = 0.5)));
    sp <- sp + theme(legend.title = element_text(size = 3), legend.text = element_text(size = 3));
    sp <- sp + labs(title = \'Genetic Effects\');';
    if (scalar(@sorted_germplasm_names) > 100) {
        $cmd_gen_plot .= 'sp <- sp + theme(legend.position = \'none\');';
    }
    $cmd_gen_plot .= 'ggsave(\''.$genetic_effects_figure_tempfile.'\', sp, device=\'png\', width=12, height=6, units=\'in\');
    "';
    # print STDERR Dumper $cmd_gen_plot;
    my $status_gen_plot = system($cmd_gen_plot);

    my @response_trait_ids;
    my %postcomposing_info;
    my $statistics_cvterm_id = SGN::Model::Cvterm->get_cvterm_row_from_trait_name($schema, $statistics_cvterm_name)->cvterm_id();
    foreach my $trait_name (@sorted_trait_names) {
        my $trait_id = $seen_trait_names{$trait_name};
        push @response_trait_ids, $trait_id;

        my @comp;
        push @comp, {
            category_name => 'attribute',
            cvterm_id => $statistics_cvterm_id
        };

        my $time_cvterm_name = $trait_time_map{$trait_name};
        if ($time_cvterm_name) {
            my $time_cvterm_id = SGN::Model::Cvterm->get_cvterm_row_from_trait_name($schema, $time_cvterm_name)->cvterm_id();
            push @comp, {
                category_name => 'toy',
                cvterm_id => $time_cvterm_id
            };
        }

        $postcomposing_info{$trait_id} = \@comp;
    }

    $c->stash->{rest} = {
        success => 1,
        result_blup_data_original => \%result_blup_data_original,
        genetic_effect_min_original => $genetic_effect_min_original,
        genetic_effect_max_original => $genetic_effect_max_original,
        genetic_effect_sum_original => $genetic_effect_sum_original,
        genetic_effect_sum_square_original => $genetic_effect_sum_square_original,
        result_blup_spatial_data_original => \%result_blup_spatial_data_original,
        env_effect_min_original => $env_effect_min_original,
        env_effect_max_original => $env_effect_max_original,
        env_effect_sum_original => $env_effect_sum_original,
        env_effect_sum_square_original => $env_effect_sum_square_original,
        result_residual_data_original => \%result_residual_data_original,
        residual_sum_original => $residual_sum_original,
        residual_sum_square_original => $residual_sum_square_original,
        result_fitted_data_original => \%result_fitted_data_original,
        model_sum_square_residual_original => $model_sum_square_residual_original,
        varcomp_original => \@varcomp_original,
        varcomp_herit => \@varcomp_herit,
        heatmaps_plot => $stats_out_tempfile_spatial_heatmaps_plot_string,
        gen_effects_line_plot => $genetic_effects_figure_tempfile_string,
        model_rds_files => \@model_rds_files,
        postcomposing_info => \%postcomposing_info,
        trait_ids => \@response_trait_ids
    };
}

sub trial_random_regression_correct_traits : Chained('trial') PathPart('random_regression_correct_traits') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $schema = $c->stash->{schema};
    my $trial_id = $c->stash->{trial_id};
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $trait_ids = decode_json $c->req->param('trait_ids');
    my $obsunit_level = $c->req->param('observation_unit_level');
    my $model_type = $c->req->param('model_type');
    my $tolparinv = $c->req->param('tolparinv');
    my $legendre_order_number = $c->req->param('legendre_order');
    my $genomic_relationship_type = $c->req->param('genomic_relationship_type');
    my $genomic_relationship_protocol_id = $genomic_relationship_type eq 'grm' ? $c->req->param('genomic_relationship_protocol_id') : undef;

    my $csv = Text::CSV->new({ sep_char => "\t" });
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$schema,
            data_level=>$obsunit_level,
            trait_list=>$trait_ids,
            trial_list=>[$c->stash->{trial_id}],
            include_timestamp=>0,
            exclude_phenotype_outlier=>0
        }
    );
    my ($data, $unique_traits) = $phenotypes_search->search();
    my @sorted_trait_names = sort keys %$unique_traits;

    if (scalar(@$data) == 0) {
        $c->stash->{rest} = { error => "There are no phenotypes for the trials and traits you have selected!"};
        return;
    }

    my %seen_trial_ids;
    my @plot_ids_ordered;
    my %obsunit_row_col;
    my %seen_rows;
    my %seen_cols;
    my $min_row = 1000000000000000;
    my $max_row = -1000000000000000;
    my $min_col = 1000000000000000;
    my $max_col = -1000000000000000;
    my %plot_id_map;
    my %seen_plot_names;
    my %seen_plots;
    my %stock_row_col;
    my %stock_name_row_col;
    my %stock_row_col_id;
    my %unique_accessions;
    my %stock_info;
    my %plot_info;
    my %phenotype_data_original;
    my %seen_trait_names;
    my %seen_times;
    my $phenotype_min_original = 1000000000000000;
    my $phenotype_max_original = -1000000000000000;
    my %seen_days_after_plantings;
    my %trait_to_time_map;
    my %trait_time_map;
    my %trait_id_map;
    foreach my $obs_unit (@$data) {
        my $germplasm_name = $obs_unit->{germplasm_uniquename};
        my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
        my $replicate_number = $obs_unit->{obsunit_rep} || '';
        my $block_number = $obs_unit->{obsunit_block} || '';
        my $obsunit_stock_id = $obs_unit->{observationunit_stock_id};
        my $obsunit_stock_uniquename = $obs_unit->{observationunit_uniquename};
        my $row_number = $obs_unit->{obsunit_row_number} || '';
        my $col_number = $obs_unit->{obsunit_col_number} || '';
        $seen_trial_ids{$obs_unit->{trial_id}}++;
        push @plot_ids_ordered, $obsunit_stock_id;

        if ($row_number < $min_row) {
            $min_row = $row_number;
        }
        elsif ($row_number >= $max_row) {
            $max_row = $row_number;
        }
        if ($col_number < $min_col) {
            $min_col = $col_number;
        }
        elsif ($col_number >= $max_col) {
            $max_col = $col_number;
        }

        $obsunit_row_col{$row_number}->{$col_number} = {
            stock_id => $obsunit_stock_id,
            stock_uniquename => $obsunit_stock_uniquename
        };
        $seen_rows{$row_number}++;
        $seen_cols{$col_number}++;
        $plot_id_map{"S".$obsunit_stock_id} = $obsunit_stock_uniquename;
        $seen_plot_names{$obsunit_stock_uniquename}++;
        $seen_plots{$obsunit_stock_id} = $obsunit_stock_uniquename;
        $stock_row_col{$obsunit_stock_id} = {
            row_number => $row_number,
            col_number => $col_number,
            obsunit_stock_id => $obsunit_stock_id,
            obsunit_name => $obsunit_stock_uniquename,
            rep => $replicate_number,
            block => $block_number,
            germplasm_stock_id => $germplasm_stock_id,
            germplasm_name => $germplasm_name
        };
        $stock_name_row_col{$obsunit_stock_uniquename} = {
            row_number => $row_number,
            col_number => $col_number,
            obsunit_stock_id => $obsunit_stock_id,
            obsunit_name => $obsunit_stock_uniquename,
            rep => $replicate_number,
            block => $block_number,
            germplasm_stock_id => $germplasm_stock_id,
            germplasm_name => $germplasm_name
        };
        $stock_row_col_id{$row_number}->{$col_number} = $obsunit_stock_id;
        $unique_accessions{$germplasm_name}++;
        $stock_info{"S".$germplasm_stock_id} = {
            uniquename => $germplasm_name
        };
        $plot_info{"S".$obsunit_stock_id} = {
            uniquename => $obsunit_stock_uniquename
        };
        my $observations = $obs_unit->{observations};
        foreach (@$observations){
            if ($_->{associated_image_project_time_json}) {
                my $value = $_->{value};
                my $trait_name = $_->{trait_name};
                my $trait_id = $_->{trait_id};

                if ($value < $phenotype_min_original) {
                    $phenotype_min_original = $value;
                }
                elsif ($value >= $phenotype_max_original) {
                    $phenotype_max_original = $value;
                }

                my $related_time_terms_json = decode_json $_->{associated_image_project_time_json};
                my $time_days_cvterm = $related_time_terms_json->{day};
                my $time_term_string = $time_days_cvterm;
                my $time_days = (split '\|', $time_days_cvterm)[0];
                my $time_value = (split ' ', $time_days)[1] + 0;
                $seen_days_after_plantings{$time_value}++;
                $phenotype_data_original{$obsunit_stock_uniquename}->{$time_value} = $value;
                $seen_times{$time_value} = $trait_name;
                $seen_trait_names{$trait_name} = $time_term_string;
                $trait_to_time_map{$trait_name} = $time_value;
                $trait_time_map{$trait_name} = $time_days_cvterm;
                $trait_id_map{$trait_name} = $trait_id;
            }
        }
    }
    my @unique_plot_names = sort keys %seen_plot_names;
    @sorted_trait_names = sort {$a <=> $b} keys %seen_times;
    # print STDERR Dumper \@sorted_trait_names;
    my @unique_accession_names = sort keys %unique_accessions;
    my $number_traits = scalar(@sorted_trait_names);

    my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
    my $tmp_stats_dir = $shared_cluster_dir_config."/tmp_trial_2dspl";
    mkdir $tmp_stats_dir if ! -d $tmp_stats_dir;
    my $dir = $c->tempfiles_subdir('/tmp_trial_2dspl');
    my ($stats_tempfile_fh, $stats_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_fh, $stats_out_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_log_tempfile_fh, $stats_out_log_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_prep_tempfile_fh, $stats_prep_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_tempfile_2_fh, $stats_tempfile_2) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_prep2_tempfile_fh, $stats_prep2_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_param_tempfile_fh, $stats_out_param_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($parameter_tempfile_fh, $parameter_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_prep_factor_tempfile_fh, $stats_prep_factor_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_prep_leg_tempfile_fh, $stats_prep_leg_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_residual_fh, $stats_out_tempfile_residual) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_varcomp_fh, $stats_out_tempfile_varcomp) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_pe_fh, $stats_out_tempfile_pe) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_heritability_fh, $stats_out_tempfile_heritability) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_pheno_heatmaps_fh, $stats_out_tempfile_pheno_heatmaps) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_spatial_heatmaps_fh, $stats_out_tempfile_spatial_heatmaps) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_fitted_heatmaps_fh, $stats_out_tempfile_fitted_heatmaps) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($stats_out_tempfile_residuals_heatmaps_fh, $stats_out_tempfile_residuals_heatmaps) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($effects_original_line_chart_tempfile_fh, $effects_original_line_chart_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);

    my ($grm_tempfile_fh, $grm_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($grm_rr_tempfile_fh, $grm_rr_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($grm_rr_out_tempfile_fh, $grm_rr_out_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    my ($grm_rename_tempfile_fh, $grm_rename_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);

    my ($stats_out_tempfile_rds_fh, $stats_out_tempfile_rds) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);
    $stats_out_tempfile_rds .= '.rds';

    my %trait_name_encoder;
    my %trait_name_encoder_rev;
    my $trait_name_encoded = 1;
    foreach my $trait_name (@sorted_trait_names) {
        if (!exists($trait_name_encoder{$trait_name})) {
            my $trait_name_e = 't'.$trait_name_encoded;
            $trait_name_encoder{$trait_name} = $trait_name_e;
            $trait_name_encoder_rev{$trait_name_e} = $trait_name;
            $trait_name_encoded++;
        }
    }
    print STDERR Dumper \%trait_name_encoder;
    print STDERR Dumper \%trait_name_encoder_rev;
    print STDERR Dumper \%seen_days_after_plantings;
    print STDERR Dumper \%trait_to_time_map;
    print STDERR Dumper \%seen_times;

    my $time_min = 10000000000000;
    my $time_max = -10000000000000;
    foreach (@sorted_trait_names) {
        if ($_ < $time_min) {
            $time_min = $_;
        }
        if ($_ >= $time_max) {
            $time_max = $_;
        }
    }
    print STDERR Dumper [$time_min, $time_max];

    my %trait_composing_info;
    while ( my ($trait_name, $time_term) = each %seen_trait_names) {
        push @{$trait_composing_info{$trait_name}}, $time_term;
    }

    if ($legendre_order_number >= scalar(@sorted_trait_names)) {
        $legendre_order_number = scalar(@sorted_trait_names) - 1;
    }

    my @sorted_trait_names_scaled;
    my $leg_pos_counter = 0;
    my @sorted_scaled_ln_times;
    foreach (@sorted_trait_names) {
        my $scaled_time = ($_ - $time_min)/($time_max - $time_min);
        my $scaled_time_ortho = 2*($_ - $time_min)/($time_max - $time_min) - 1;
        push @sorted_trait_names_scaled, $scaled_time_ortho;
        if ($leg_pos_counter < $legendre_order_number+1) {
            push @sorted_scaled_ln_times, log($scaled_time+0.0001);
        }
        $leg_pos_counter++;
    }
    my $sorted_trait_names_scaled_string = join ',', @sorted_trait_names_scaled;

    my $cmd = 'R -e "library(sommer); library(orthopolynom);
    polynomials <- leg(c('.$sorted_trait_names_scaled_string.'), n='.$legendre_order_number.', intercept=TRUE);
    write.table(polynomials, file=\''.$stats_prep_leg_tempfile.'\', row.names=FALSE, col.names=TRUE, sep=\'\t\');"';
    my $status = system($cmd);

    my %polynomial_map;
    open(my $fh, '<', $stats_prep_leg_tempfile) or die "Could not open file '$stats_prep_leg_tempfile' $!";
        print STDERR "Opened $stats_prep_leg_tempfile\n";
        my $header = <$fh>;
        my @header_cols;
        if ($csv->parse($header)) {
            @header_cols = $csv->fields();
        }

        my $p_counter = 0;
        while (my $row = <$fh>) {
            my @columns;
            if ($csv->parse($row)) {
                @columns = $csv->fields();
            }
            my $time = $sorted_trait_names[$p_counter];
            $polynomial_map{$time} = \@columns;
            $p_counter++;
        }
    close($fh);

    open(my $F_prep, ">", $stats_prep_tempfile) || die "Can't open file ".$stats_prep_tempfile;
        print $F_prep "accession_id,accession_id_factor,plot_id,plot_id_factor,replicate,time,replicate_time,ind_replicate\n";
        foreach my $p (@unique_plot_names) {
            my $replicate = $stock_name_row_col{$p}->{rep};
            my $germplasm_stock_id = $stock_name_row_col{$p}->{germplasm_stock_id};
            my $obsunit_stock_id = $stock_name_row_col{$p}->{obsunit_stock_id};
            foreach my $t (@sorted_trait_names) {
                print $F_prep "$germplasm_stock_id,,$obsunit_stock_id,,$replicate,$t,$replicate"."_"."$t,$germplasm_stock_id"."_"."$replicate\n";
            }
        }
    close($F_prep);

    my $cmd_factor = 'R -e "library(data.table); library(dplyr);
    mat <- fread(\''.$stats_prep_tempfile.'\', header=TRUE, sep=\',\');
    mat\$replicate_time <- as.numeric(as.factor(mat\$replicate_time));
    mat\$ind_replicate <- as.numeric(as.factor(mat\$ind_replicate));
    mat\$accession_id_factor <- as.numeric(as.factor(mat\$accession_id));
    mat\$plot_id_factor <- as.numeric(as.factor(mat\$plot_id));
    write.table(mat, file=\''.$stats_prep_factor_tempfile.'\', row.names=FALSE, col.names=TRUE, sep=\'\t\');"';
    my $status_factor = system($cmd_factor);

    my %plot_rep_time_factor_map;
    my %seen_rep_times;
    my %seen_ind_reps;
    my %accession_id_factor_map;
    my %accession_id_factor_map_reverse;
    my %plot_id_factor_map_reverse;
    my %plot_id_count_map_reverse;
    my %time_count_map_reverse;
    open(my $fh_factor, '<', $stats_prep_factor_tempfile) or die "Could not open file '$stats_prep_factor_tempfile' $!";
        print STDERR "Opened $stats_prep_factor_tempfile\n";
        $header = <$fh_factor>;
        if ($csv->parse($header)) {
            @header_cols = $csv->fields();
        }

        my $line_factor_count = 0;
        while (my $row = <$fh_factor>) {
            my @columns;
            if ($csv->parse($row)) {
                @columns = $csv->fields();
            }
            my $accession_id = $columns[0];
            my $accession_id_factor = $columns[1];
            my $plot_id = $columns[2];
            my $plot_id_factor = $columns[3];
            my $rep = $columns[4];
            my $time = $columns[5];
            my $rep_time = $columns[6];
            my $ind_rep = $columns[7];
            $stock_row_col{$plot_id}->{plot_id_factor} = $plot_id_factor;
            $stock_name_row_col{$plot_id_map{"S".$plot_id}}->{plot_id_factor} = $plot_id_factor;
            $plot_rep_time_factor_map{$plot_id}->{$rep}->{$time} = $rep_time;
            $seen_rep_times{$rep_time}++;
            $seen_ind_reps{$plot_id_factor}++;
            $accession_id_factor_map{$accession_id} = $accession_id_factor;
            $accession_id_factor_map_reverse{$accession_id_factor} = $stock_info{"S".$accession_id}->{uniquename};
            $plot_id_factor_map_reverse{$plot_id_factor} = $seen_plots{$plot_id};
            $plot_id_count_map_reverse{$line_factor_count} = $seen_plots{$plot_id};
            $time_count_map_reverse{$line_factor_count} = $time;
            $line_factor_count++;
        }
    close($fh_factor);
    my @rep_time_factors = sort keys %seen_rep_times;
    my @ind_rep_factors = sort keys %seen_ind_reps;

    my @data_matrix_original;
    my @data_matrix_phenotypes_original;
    foreach my $p (@unique_plot_names) {
        my $row_number = $stock_name_row_col{$p}->{row_number};
        my $col_number = $stock_name_row_col{$p}->{col_number};
        my $replicate = $stock_name_row_col{$p}->{rep};
        my $block = $stock_name_row_col{$p}->{block};
        my $germplasm_stock_id = $stock_name_row_col{$p}->{germplasm_stock_id};
        my $germplasm_name = $stock_name_row_col{$p}->{germplasm_name};
        my $obsunit_stock_id = $stock_name_row_col{$p}->{obsunit_stock_id};

        my @data_matrix_phenotypes_row;
        my $current_trait_index = 0;
        foreach my $t (@sorted_trait_names) {
            my @row = ();
            if ($model_type eq 'airemlf90_legendre_rr') {
                push @row, (
                    $accession_id_factor_map{$germplasm_stock_id},
                    $obsunit_stock_id
                );
            }
            if ($model_type eq 'sommer_legendre_rr') {
                push @row, (
                    "S".$germplasm_stock_id,
                    "S".$obsunit_stock_id
                );
            }

            push @row, (
                $replicate
            );

            if ($model_type eq 'airemlf90_legendre_rr') {
                push @row, $t;
            }
            if ($model_type eq 'sommer_legendre_rr') {
                my $time = ($t - $time_min)/($time_max - $time_min);
                push @row, $time;
            }

            push @row, (
                $plot_rep_time_factor_map{$obsunit_stock_id}->{$replicate}->{$t},
                $stock_row_col{$obsunit_stock_id}->{plot_id_factor}
            );

            my $polys = $polynomial_map{$t};
            push @row, @$polys;

            if (defined($phenotype_data_original{$p}->{$t})) {
                # if ($use_area_under_curve) {
                #     my $val = 0;
                #     foreach my $counter (0..$current_trait_index) {
                #         if ($counter == 0) {
                #             $val = $val + $phenotype_data_original{$p}->{$sorted_trait_names[$counter]} + 0;
                #         }
                #         else {
                #             my $t1 = $sorted_trait_names[$counter-1];
                #             my $t2 = $sorted_trait_names[$counter];
                #             my $p1 = $phenotype_data_original{$p}->{$t1} + 0;
                #             my $p2 = $phenotype_data_original{$p}->{$t2} + 0;
                #             my $neg = 1;
                #             my $min_val = $p1;
                #             if ($p2 < $p1) {
                #                 $neg = -1;
                #                 $min_val = $p2;
                #             }
                #             $val = $val + (($neg*($p2-$p1)*($t2-$t1))/2)+($t2-$t1)*$min_val;
                #         }
                #     }
                #
                #     push @row, $val;
                #     push @data_matrix_phenotypes_row, $val;
                # }
                # else {
                    push @row, $phenotype_data_original{$p}->{$t} + 0;
                    push @data_matrix_phenotypes_row, $phenotype_data_original{$p}->{$t} + 0;
                # }
            } else {
                print STDERR $p." : $t : $germplasm_name : NA \n";
                push @row, '';
                push @data_matrix_phenotypes_row, 'NA';
            }

            push @data_matrix_original, \@row;
            push @data_matrix_phenotypes_original, \@data_matrix_phenotypes_row;

            $current_trait_index++;
        }
    }

    my @legs_header;
    for (0..$legendre_order_number) {
        push @legs_header, "legendre$_";
    }
    my @phenotype_header = ("id", "plot_id", "replicate", "time", "replicate_time", "ind_replicate", @legs_header, "phenotype");
    my $phenotype_header_line = join ' ', @phenotype_header;
    open(my $F, ">", $stats_tempfile_2) || die "Can't open file ".$stats_tempfile_2;

        if ($model_type eq 'sommer_legendre_rr') {
            print $F "$phenotype_header_line\n";
        }

        foreach (@data_matrix_original) {
            my $line = join ' ', @$_;
            print $F "$line\n";
        }
    close($F);

    open(my $F2, ">", $stats_prep2_tempfile) || die "Can't open file ".$stats_prep2_tempfile;
        foreach (@data_matrix_phenotypes_original) {
            my $line = join ',', @$_;
            print $F2 "$line\n";
        }
    close($F2);

    my $effect_1_levels = scalar(@rep_time_factors);
    my $effect_grm_levels = scalar(@unique_accession_names);
    my $effect_pe_levels = scalar(@ind_rep_factors);


    if (!$genomic_relationship_protocol_id) {
        $genomic_relationship_protocol_id = undef;
    }

    my $geno = CXGN::Genotype::GRM->new({
        bcs_schema=>$schema,
        people_schema=>$people_schema,
        grm_temp_file=>$grm_tempfile,
        cache_root=>$c->config->{cache_file_path},
        trial_id_list=>[$trial_id],
        protocol_id=>$genomic_relationship_protocol_id,
        download_format=>'three_column_reciprocal'
    });
    my $grm_data = $geno->download_grm(
        'data',
        $shared_cluster_dir_config,
        $c->config->{backend},
        $c->config->{cluster_host},
        $c->config->{'web_cluster_queue'},
        $c->config->{basepath}
    );

    open(my $F_grm, ">", $grm_out_tempfile) || die "Can't open file ".$grm_out_tempfile;
        print $F_grm $grm_data;
    close($F_grm);

    my $geno_rr = CXGN::Genotype::GRM->new({
        bcs_schema=>$schema,
        people_schema=>$people_schema,
        grm_temp_file=>$grm_rr_tempfile,
        cache_root=>$c->config->{cache_file_path},
        trial_id_list=>[$trial_id],
        protocol_id=>$genomic_relationship_protocol_id,
        download_format=>'three_column_stock_id_integer'
    });
    my $grm_rr_data = $geno_rr->download_grm(
        'data',
        $shared_cluster_dir_config,
        $c->config->{backend},
        $c->config->{cluster_host},
        $c->config->{'web_cluster_queue'},
        $c->config->{basepath}
    );

    open(my $F_grm2, ">", $grm_rr_out_tempfile) || die "Can't open file ".$grm_rr_out_tempfile;
        print $F_grm2 $grm_rr_data;
    close($F_grm2);
    my $grm_file = $grm_rr_out_tempfile;


    my @legendre_coeff_exec = (
        '1 * $b',
        '($time**1)*$b',
        '($time**2)*$b',
        '($time**3)*$b',
        '($time**4)*$b',
        '($time**5)*$b',
        '($time**6)*$b'
    );

    my %fixed_effects_original;
    my %rr_genetic_coefficients_original;
    my %rr_temporal_coefficients_original;
    my %result_blup_data_original;
    my $genetic_effect_min_original = 10000000000000;
    my $genetic_effect_max_original = -10000000000000;
    my $genetic_effect_sum_original = 0;
    my $genetic_effect_sum_square_original = 0;
    my %result_blup_spatial_data_original;
    my $env_effect_min_original = 10000000000000;
    my $env_effect_max_original = -10000000000000;
    my $env_effect_sum_original = 0;
    my $env_effect_sum_square_original = 0;
    my %result_residual_data_original;
    my $residual_sum_original = 0;
    my $residual_sum_square_original = 0;
    my %result_fitted_data_original;
    my $model_sum_square_residual_original = 0;
    my @varcomp_original;
    my @varcomp_herit;
    my @model_rds_files;
    my $statistics_cvterm_name = '';

    my @rr_coeff_genetic_covariance_original;
    my @rr_coeff_env_covariance_original;
    my @rr_coeff_genetic_correlation_original;
    my @rr_coeff_env_correlation_original;
    my $rr_residual_variance_original;
    if ($model_type eq 'airemlf90_legendre_rr') {
        $statistics_cvterm_name = 'Multivariate linear mixed model permanent environment BLUPs using genetic relationship matrix and temporal Legendre polynomial random regression on days after planting computed using AIREMLf90|SGNSTAT:0000019';

        my $pheno_var_pos = $legendre_order_number+1;

        my $statistics_cmd = 'R -e "
            pheno <- read.csv(\''.$stats_prep2_tempfile.'\', header=FALSE, sep=\',\');
            v <- var(pheno);
            v <- v[1:'.$pheno_var_pos.', 1:'.$pheno_var_pos.'];
            #v <- matrix(rep(0.1, '.$pheno_var_pos.'*'.$pheno_var_pos.'), nrow = '.$pheno_var_pos.');
            #diag(v) <- rep(1, '.$pheno_var_pos.');
            write.table(v, file=\''.$stats_out_param_tempfile.'\', row.names=FALSE, col.names=FALSE, sep=\'\t\');
        "';
        my $status_r = system($statistics_cmd);

        my @pheno_var;
        open(my $fh_r, '<', $stats_out_param_tempfile) or die "Could not open file '$stats_out_param_tempfile' $!";
            print STDERR "Opened $stats_out_param_tempfile\n";

            while (my $row = <$fh_r>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @pheno_var, \@columns;
            }
        close($fh_r);
        # print STDERR Dumper \@pheno_var;

        my @grm_old;
        open(my $fh_grm_old, '<', $grm_file) or die "Could not open file '$grm_file' $!";
            print STDERR "Opened $grm_file\n";

            while (my $row = <$fh_grm_old>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @grm_old, \@columns;
            }
        close($fh_grm_old);

        my %grm_hash_ordered;
        foreach (@grm_old) {
            my $l1 = $accession_id_factor_map{$_->[0]};
            my $l2 = $accession_id_factor_map{$_->[1]};
            my $val = sprintf("%.8f", $_->[2]);
            if ($l1 < $l2) {
                $grm_hash_ordered{$l1}->{$l2} = $val;
            }
            else {
                $grm_hash_ordered{$l2}->{$l1} = $val;
            }
        }

        open(my $fh_grm_new, '>', $grm_rename_tempfile) or die "Could not open file '$grm_rename_tempfile' $!";
            print STDERR "Opened $grm_rename_tempfile\n";

            foreach my $i (sort {$a <=> $b} keys %grm_hash_ordered) {
                my $v = $grm_hash_ordered{$i};
                foreach my $j (sort {$a <=> $b} keys %$v) {
                    my $val = $v->{$j};
                    print $fh_grm_new "$i $j $val\n";
                }
            }
        close($fh_grm_new);

        my $stats_tempfile_2_basename = basename($stats_tempfile_2);
        my $grm_file_basename = basename($grm_rename_tempfile);

        my @param_file_rows_data = ('DATAFILE', $stats_tempfile_2_basename);
        my @param_file_rows_1 = (
            'NUMBER_OF_TRAITS',
            '1',
            'NUMBER_OF_EFFECTS',
            ($legendre_order_number + 1)*2 + 1,
            'OBSERVATION(S)',
            $legendre_order_number + 1 + 6 + 1,
            'WEIGHT(S)',
            '',
            'EFFECTS: POSITION_IN_DATAFILE NUMBER_OF_LEVELS TYPE_OF_EFFECT',
            '5 '.$effect_1_levels.' cross',
        );
        my $p_counter = 1;
        foreach (0 .. $legendre_order_number) {
            push @param_file_rows_1, 6+$p_counter.' '.$effect_grm_levels.' cov 1';
            $p_counter++;
        }
        my $p2_counter = 1;
        my @hetres_group;
        foreach (0 .. $legendre_order_number) {
            push @param_file_rows_1, 6+$p2_counter.' '.$effect_pe_levels.' cov 6';
            push @hetres_group, 6+$p2_counter;
            $p2_counter++;
        }
        my @random_group1;
        foreach (1..$legendre_order_number+1) {
            push @random_group1, 1+$_;
        }
        my $random_group_string1 = join ' ', @random_group1;
        my @random_group2;
        foreach (1..$legendre_order_number+1) {
            push @random_group2, 1+scalar(@random_group1)+$_;
        }
        my $random_group_string2 = join ' ', @random_group2;
        my $hetres_group_string = join ' ', @hetres_group;
        push @param_file_rows_1, (
            'RANDOM_RESIDUAL VALUES',
            '1',
            'RANDOM_GROUP',
            $random_group_string1,
            'RANDOM_TYPE'
        );
        if (!$genomic_relationship_protocol_id) {
            push @param_file_rows_1, (
                'diagonal',
                'FILE',
                ''
            );
        }
        else {
            push @param_file_rows_1, (
                'user_file_inv',
                'FILE',
                $grm_file_basename
            );
        }
        my @param_file_rows_2 = (
            '(CO)VARIANCES'
        );
        foreach (@pheno_var) {
            my $s = join ' ', @$_;
            push @param_file_rows_2, $s;
        }
        my @param_file_rows_3 = (
            'RANDOM_GROUP',
            $random_group_string2,
            'RANDOM_TYPE'
        );
        push @param_file_rows_3, (
            'diagonal',
            'FILE',
            ''
        );
        my @param_file_rows_4 = (
            '(CO)VARIANCES'
        );
        foreach (@pheno_var) {
            my $s = join ' ', @$_;
            push @param_file_rows_4, $s;
        }
        my $hetres_pol_string = join ' ', @sorted_scaled_ln_times;
        my @param_file_rows_5 = (
            'OPTION hetres_pos '.$hetres_group_string,
            'OPTION hetres_pol '.$hetres_pol_string,
            'OPTION conv_crit '.$tolparinv,
            'OPTION missing -999',
            'OPTION residual',
        );

        open(my $Fp, ">", $parameter_tempfile) || die "Can't open file ".$parameter_tempfile;
            foreach ((@param_file_rows_data, @param_file_rows_1, @param_file_rows_2, @param_file_rows_3, @param_file_rows_4, @param_file_rows_5)) {
                print $Fp "$_\n";
            }
        close($Fp);

        my $parameter_tempfile_basename = basename($parameter_tempfile);

        $stats_out_log_tempfile .= '.log';
        my $cmd_f90 = 'cd '.$tmp_stats_dir.'; echo '.$parameter_tempfile_basename.' | airemlf90 > '.$stats_out_log_tempfile;
        print STDERR Dumper $cmd_f90;
        my $status = system($cmd_f90);

        my @log_output_rows;
        open(my $fh_log, '<', $stats_out_log_tempfile) or die "Could not open file '$stats_out_log_tempfile' $!";
            print STDERR "Opened $stats_out_log_tempfile\n";
            while (my $row = <$fh_log>) {
                print STDERR $row;
                push @log_output_rows, $row;
            }
        close($fh_log);

        my $legendre_order_number_env_var_pos = $legendre_order_number+1+2;

        my $log_output = join '', @log_output_rows;
        my ($gen_var_string) = $log_output =~ /Genetic variance\(s\) for effect  2(.*?)correlations/gs;
        @rr_coeff_genetic_covariance_original = split ' ', $gen_var_string;
        print STDERR Dumper \@rr_coeff_genetic_covariance_original;
        my ($env_var_string) = $log_output =~ /Genetic variance\(s\) for effect  $legendre_order_number_env_var_pos(.*?)correlations/gs;
        @rr_coeff_env_covariance_original = split ' ', $env_var_string;
        print STDERR Dumper \@rr_coeff_env_covariance_original;
        my (@gen_cor_string) = $log_output =~ /correlations(.*?)eigenvectors/gs;
        @rr_coeff_genetic_correlation_original = split ' ', $gen_cor_string[0];
        print STDERR Dumper \@rr_coeff_genetic_correlation_original;
        @rr_coeff_env_correlation_original = split ' ', $gen_cor_string[1];
        print STDERR Dumper \@rr_coeff_env_correlation_original;
        my ($res_se_string) = $log_output =~ /SE for R(.*?)\* FINISHED \(AIREMLF90\)/gs;
        print STDERR Dumper $res_se_string;
        # $rr_residual_variance_original = ($res_se_string**2)*$number_plots;
        $rr_residual_variance_original = $res_se_string;
        print STDERR Dumper $rr_residual_variance_original;

        my %rr_residual_unique_traits;
        my $yhat_residual_tempfile = $tmp_stats_dir."/yhat_residual";
        open(my $fh_yhat_res, '<', $yhat_residual_tempfile) or die "Could not open file '$yhat_residual_tempfile' $!";
            print STDERR "Opened $yhat_residual_tempfile\n";

            my $pred_res_counter = 0;
            my $trait_counter = 0;
            while (my $row = <$fh_yhat_res>) {
                # print STDERR $row;
                my @vals = split ' ', $row;
                my $pred = $vals[0];
                my $residual = $vals[1];
                $model_sum_square_residual_original = $model_sum_square_residual_original + $residual*$residual;

                my $plot_name = $plot_id_count_map_reverse{$pred_res_counter};
                my $time = $time_count_map_reverse{$pred_res_counter};

                $rr_residual_unique_traits{$seen_times{$time}}++;

                if (defined $residual && $residual ne '') {
                    $result_residual_data_original{$plot_name}->{$seen_times{$time}} = [$residual, $timestamp, $user_name, '', ''];
                    $residual_sum_original += abs($residual);
                    $residual_sum_square_original = $residual_sum_square_original + $residual*$residual;
                }
                if (defined $pred && $pred ne '') {
                    $result_fitted_data_original{$plot_name}->{$seen_times{$time}} = [$pred, $timestamp, $user_name, '', ''];
                }

                $pred_res_counter++;
            }
        close($fh_yhat_res);

        my $blupf90_solutions_tempfile = $tmp_stats_dir."/solutions";
        open(my $fh_sol, '<', $blupf90_solutions_tempfile) or die "Could not open file '$blupf90_solutions_tempfile' $!";
            print STDERR "Opened $blupf90_solutions_tempfile\n";

            my $head = <$fh_sol>;
            print STDERR $head;

            my $solution_file_counter = 0;
            my $grm_sol_counter = 0;
            my $grm_sol_trait_counter = 0;
            my $pe_sol_counter = 0;
            my $pe_sol_trait_counter = 0;
            while (defined(my $row = <$fh_sol>)) {
                # print STDERR $row;
                my @vals = split ' ', $row;
                my $level = $vals[2];
                my $value = $vals[3];
                if ($solution_file_counter < $effect_1_levels) {
                    $fixed_effects_original{$solution_file_counter}->{$level} = $value;
                }
                elsif ($solution_file_counter < $effect_1_levels + $effect_grm_levels*($legendre_order_number+1)) {
                    my $accession_name = $accession_id_factor_map_reverse{$level};
                    if ($grm_sol_counter < $effect_grm_levels-1) {
                        $grm_sol_counter++;
                    }
                    else {
                        $grm_sol_counter = 0;
                        $grm_sol_trait_counter++;
                    }
                    if (defined $value && $value ne '') {
                        push @{$rr_genetic_coefficients_original{$accession_name}}, $value;
                    }
                }
                else {
                    my $plot_name = $plot_id_factor_map_reverse{$level};
                    if ($pe_sol_counter < $effect_pe_levels-1) {
                        $pe_sol_counter++;
                    }
                    else {
                        $pe_sol_counter = 0;
                        $pe_sol_trait_counter++;
                    }
                    if (defined $value && $value ne '') {
                        push @{$rr_temporal_coefficients_original{$plot_name}}, $value;
                    }
                }
                $solution_file_counter++;
            }
        close($fh_sol);

        while ( my ($accession_name, $coeffs) = each %rr_genetic_coefficients_original) {
            foreach my $time_term (@sorted_trait_names) {
                my $time = ($time_term - $time_min)/($time_max - $time_min);
                my $value = 0;
                my $coeff_counter = 0;
                foreach my $b (@$coeffs) {
                    my $eval_string = $legendre_coeff_exec[$coeff_counter];
                    # print STDERR Dumper [$eval_string, $b, $time];
                    $value += eval $eval_string;
                    $coeff_counter++;
                }

                $result_blup_data_original{$accession_name}->{$seen_times{$time_term}} = [$value, $timestamp, $user_name, '', ''];

                if ($value < $genetic_effect_min_original) {
                    $genetic_effect_min_original = $value;
                }
                elsif ($value >= $genetic_effect_max_original) {
                    $genetic_effect_max_original = $value;
                }

                $genetic_effect_sum_original += abs($value);
                $genetic_effect_sum_square_original = $genetic_effect_sum_square_original + $value*$value;
            }
        }

        while ( my ($plot_name, $coeffs) = each %rr_temporal_coefficients_original) {
            foreach my $time_term (@sorted_trait_names) {
                my $time = ($time_term - $time_min)/($time_max - $time_min);
                my $value = 0;
                my $coeff_counter = 0;
                foreach my $b (@$coeffs) {
                    my $eval_string = $legendre_coeff_exec[$coeff_counter];
                    # print STDERR Dumper [$eval_string, $b, $time];
                    $value += eval $eval_string;
                    $coeff_counter++;
                }

                $result_blup_spatial_data_original{$plot_name}->{$seen_times{$time_term}} = [$value, $timestamp, $user_name, '', ''];

                if ($value < $env_effect_min_original) {
                    $env_effect_min_original = $value;
                }
                elsif ($value >= $env_effect_max_original) {
                    $env_effect_max_original = $value;
                }

                $env_effect_sum_original += abs($value);
                $env_effect_sum_square_original = $env_effect_sum_square_original + $value*$value;
            }
        }
    }
    elsif ($model_type eq 'sommer_legendre_rr') {
        $statistics_cvterm_name = "Multivariate linear mixed model permanent environment BLUPs using genetic relationship matrix and temporal Legendre polynomial random regression on days after planting computed using Sommer R|SGNSTAT:0000005";

        # my @phenotype_header = ("id", "plot_id", "replicate", "time", "replicate_time", "ind_replicate", @legs_header, "phenotype");

        my $statistics_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(orthopolynom);
        mat <- data.frame(fread(\''.$stats_tempfile_2.'\', header=TRUE, sep=\' \'));
        geno_mat_3col <- data.frame(fread(\''.$grm_out_tempfile.'\', header=FALSE, sep=\'\t\'));
        geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
        geno_mat[is.na(geno_mat)] <- 0;
        mix <- mmer(phenotype~1 + replicate, random=~vs(us(leg(time,'.$legendre_order_number.')), id, Gu=geno_mat) +vs(us(leg(time,'.$legendre_order_number.')), plot_id), rcov=~vs(units), data=mat, tolparinv='.$tolparinv.');
        if (!is.null(mix\$U)) {
        #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
        gen_rr <- data.frame(g_l0 <- mix\$U\$\`leg0:id\`\$phenotype , g_l1 <- mix\$U\$\`leg1:id\`\$phenotype, g_l2 <- mix\$U\$\`leg2:id\`\$phenotype, g_l3 <- mix\$U\$\`leg3:id\`\$phenotype);
        pe_rr <- data.frame(g_l0 <- mix\$U\$\`leg0:plot_id\`\$phenotype , g_l1 <- mix\$U\$\`leg1:plot_id\`\$phenotype, g_l2 <- mix\$U\$\`leg2:plot_id\`\$phenotype, g_l3 <- mix\$U\$\`leg3:plot_id\`\$phenotype);
        write.table(gen_rr, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');
        write.table(pe_rr, file=\''.$stats_out_tempfile_pe.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');
        write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\'\t\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');
        h2_l0 <- vpredict(mix, h2 ~ (V1) / ( V1+V21) ); h2_l1 <- vpredict(mix, h2 ~ (V3) / ( V3+V21) ); h2_l2 <- vpredict(mix, h2 ~ (V6) / ( V6+V21) ); h2_l3 <- vpredict(mix, h2 ~ (V10) / ( V10+V21) );
        e2_l0 <- vpredict(mix, e2 ~ (V11) / ( V11+V21) ); e2_l1 <- vpredict(mix, e2 ~ (V13) / ( V13+V21) ); e2_l2 <- vpredict(mix, e2 ~ (V16) / ( V16+V21) ); e2_l3 <- vpredict(mix, e2 ~ (V20) / ( V20+V21) );
        write.table(data.frame(h2_l0=h2_l0\$Estimate, hse_l0=h2_l0\$SE, h2_l1=h2_l1\$Estimate, hse_l1=h2_l1\$SE, h2_l2=h2_l2\$Estimate, hse_l2=h2_l2\$SE, h2_l3=h2_l3\$Estimate, hse_l3=h2_l3\$SE, e2_l0=e2_l0\$Estimate, ese_l0=e2_l0\$SE, e2_l1=e2_l1\$Estimate, ese_l1=e2_l1\$SE, e2_l2=e2_l2\$Estimate, ese_l2=e2_l2\$SE, e2_l3=e2_l3\$Estimate, ese_l3=e2_l3\$SE), file=\''.$stats_out_tempfile_heritability.'\', row.names=FALSE, col.names=TRUE, sep=\'\t\');
        saveRDS(mix, file=\''.$stats_out_tempfile_rds.'\');
        }
        "';

        eval {
            my $status = system($statistics_cmd);
        };
        my $run_stats_fault = 0;
        if ($@) {
            print STDERR "R ERROR\n";
            print STDERR Dumper $@;
            $run_stats_fault = 1;
        }

        push @model_rds_files, $stats_out_tempfile_rds;

        my $current_gen_row_count = 0;
        my $current_env_row_count = 0;

        open(my $fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header = <$fh>;
            my @header_cols;
            if ($csv->parse($header)) {
                @header_cols = $csv->fields();
            }

            while (my $row = <$fh>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $b_coeff_0 = $columns[1];
                my $b_coeff_1 = $columns[2];
                my $b_coeff_2 = $columns[3];
                my $b_coeff_3 = $columns[4];
                my @coeffs = ($b_coeff_0, $b_coeff_1, $b_coeff_2, $b_coeff_3);

                my $accession_name = $stock_info{$stock_id}->{uniquename};

                foreach my $time_term (@sorted_trait_names) {
                    my $time = ($time_term - $time_min)/($time_max - $time_min);
                    my $value = 0;
                    my $coeff_counter = 0;
                    foreach my $b (@coeffs) {
                        my $eval_string = $legendre_coeff_exec[$coeff_counter];
                        # print STDERR Dumper [$eval_string, $b, $time];
                        $value += eval $eval_string;
                        $coeff_counter++;
                    }

                    $result_blup_data_original{$accession_name}->{$seen_times{$time_term}} = [$value, $timestamp, $user_name, '', ''];

                    if ($value < $genetic_effect_min_original) {
                        $genetic_effect_min_original = $value;
                    }
                    elsif ($value >= $genetic_effect_max_original) {
                        $genetic_effect_max_original = $value;
                    }

                    $genetic_effect_sum_original += abs($value);
                    $genetic_effect_sum_square_original = $genetic_effect_sum_square_original + $value*$value;
                }

                $current_gen_row_count++;
            }
        close($fh);

        open(my $fh_2dspl, '<', $stats_out_tempfile_pe) or die "Could not open file '$stats_out_tempfile_pe' $!";
            print STDERR "Opened $stats_out_tempfile_pe\n";
            my $header_2dspl = <$fh_2dspl>;
            my @header_cols_2dspl;
            if ($csv->parse($header_2dspl)) {
                @header_cols_2dspl = $csv->fields();
            }
            shift @header_cols_2dspl;
            while (my $row_2dspl = <$fh_2dspl>) {
                my @columns;
                if ($csv->parse($row_2dspl)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $b_coeff_0 = $columns[1];
                my $b_coeff_1 = $columns[2];
                my $b_coeff_2 = $columns[3];
                my $b_coeff_3 = $columns[4];
                my @coeffs = ($b_coeff_0, $b_coeff_1, $b_coeff_2, $b_coeff_3);
                my $plot_name = $plot_id_map{$stock_id};

                foreach my $time_term (@sorted_trait_names) {
                    my $time = ($time_term - $time_min)/($time_max - $time_min);
                    my $value = 0;
                    my $coeff_counter = 0;
                    foreach my $b (@coeffs) {
                        my $eval_string = $legendre_coeff_exec[$coeff_counter];
                        # print STDERR Dumper [$eval_string, $b, $time];
                        $value += eval $eval_string;
                        $coeff_counter++;
                    }

                    $result_blup_spatial_data_original{$plot_name}->{$seen_times{$time_term}} = [$value, $timestamp, $user_name, '', ''];

                    if ($value < $env_effect_min_original) {
                        $env_effect_min_original = $value;
                    }
                    elsif ($value >= $env_effect_max_original) {
                        $env_effect_max_original = $value;
                    }

                    $env_effect_sum_original += abs($value);
                    $env_effect_sum_square_original = $env_effect_sum_square_original + $value*$value;
                }

                $current_env_row_count++;
            }
        close($fh_2dspl);

        open(my $fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual = <$fh_residual>;
            my @header_cols_residual;
            if ($csv->parse($header_residual)) {
                @header_cols_residual = $csv->fields();
            }
            my $residual_line_trait_count = 0;
            while (my $row = <$fh_residual>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                if ($residual_line_trait_count >= $number_traits) {
                    $residual_line_trait_count = 0;
                }

                my $trait_name = $seen_times{$sorted_trait_names[$residual_line_trait_count]};
                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                if (defined $residual && $residual ne '') {
                    $result_residual_data_original{$stock_name}->{$trait_name} = [$residual, $timestamp, $user_name, '', ''];
                    $residual_sum_original += abs($residual);
                    $residual_sum_square_original = $residual_sum_square_original + $residual*$residual;
                }
                if (defined $fitted && $fitted ne '') {
                    $result_fitted_data_original{$stock_name}->{$trait_name} = [$fitted, $timestamp, $user_name, '', ''];
                }
                $model_sum_square_residual_original = $model_sum_square_residual_original + $residual*$residual;

                $residual_line_trait_count++;
            }
        close($fh_residual);

        open(my $fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
            print STDERR "Opened $stats_out_tempfile_varcomp\n";
            my $header_varcomp = <$fh_varcomp>;
            my @header_cols_varcomp;
            if ($csv->parse($header_varcomp)) {
                @header_cols_varcomp = $csv->fields();
            }
            while (my $row = <$fh_varcomp>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_original, \@columns;
            }
        close($fh_varcomp);

        open(my $fh_herit, '<', $stats_out_tempfile_heritability) or die "Could not open file '$stats_out_tempfile_heritability' $!";
            print STDERR "Opened $stats_out_tempfile_heritability\n";
            my $header_herit = <$fh_herit>;
            my @header_cols_herit;
            if ($csv->parse($header_herit)) {
                @header_cols_herit = $csv->fields();
            }
            while (my $row = <$fh_herit>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_herit, \@columns;
            }
        close($fh_herit);

        if ($current_env_row_count == 0 || $current_gen_row_count == 0) {
            $run_stats_fault = 1;
        }

        if ($run_stats_fault == 1) {
            print STDERR "ERROR IN R CMD\n";
            return {error=>'Error in R! Try a larger tolerance'};
        }
    }

    open(my $F_pheno, ">", $stats_out_tempfile_pheno_heatmaps) || die "Can't open file ".$stats_out_tempfile_pheno_heatmaps;
        print $F_pheno "trait_type,row,col,value\n";
        foreach my $p (@unique_plot_names) {
            foreach my $t (@sorted_trait_names) {
                my $trait = defined($trait_to_time_map{$t}) ? $trait_to_time_map{$t}." DAP" : $t;
                my $val = $phenotype_data_original{$p}->{$t};
                my @row = ($trait, $stock_name_row_col{$p}->{row_number}, $stock_name_row_col{$p}->{col_number}, $val);
                my $line = join ',', @row;
                print $F_pheno "$line\n";
            }
        }
    close($F_pheno);

    open(my $F_eff, ">", $stats_out_tempfile_spatial_heatmaps) || die "Can't open file ".$stats_out_tempfile_spatial_heatmaps;
        print $F_eff "trait_type,row,col,value\n";
        foreach my $p (@unique_plot_names) {
            foreach my $time (@sorted_trait_names) {
                my $t = $seen_times{$time};
                my $val = defined($result_blup_spatial_data_original{$p}->{$t}->[0]) ? $result_blup_spatial_data_original{$p}->{$t}->[0] : 'NA';
                my @row = ($trait_name_encoder{$time}." PE Effect", $stock_name_row_col{$p}->{row_number}, $stock_name_row_col{$p}->{col_number}, $val);
                my $line = join ',', @row;
                print $F_eff "$line\n";
            }
        }
    close($F_eff);

    open(my $F_fitted, ">", $stats_out_tempfile_fitted_heatmaps) || die "Can't open file ".$stats_out_tempfile_fitted_heatmaps;
        print $F_fitted "trait_type,row,col,value\n";
        foreach my $p (@unique_plot_names) {
            foreach my $time (@sorted_trait_names) {
                my $t = $seen_times{$time};
                my $val = defined($result_fitted_data_original{$p}->{$t}->[0]) ? $result_fitted_data_original{$p}->{$t}->[0] : 'NA';
                my @row = ($trait_name_encoder{$time}." Fitted Value", $stock_name_row_col{$p}->{row_number}, $stock_name_row_col{$p}->{col_number}, $val);
                my $line = join ',', @row;
                print $F_fitted "$line\n";
            }
        }
    close($F_fitted);

    open(my $F_res, ">", $stats_out_tempfile_residuals_heatmaps) || die "Can't open file ".$stats_out_tempfile_residuals_heatmaps;
        print $F_res "trait_type,row,col,value\n";
        foreach my $p (@unique_plot_names) {
            foreach my $time (@sorted_trait_names) {
                my $t = $seen_times{$time};
                my $val = defined($result_residual_data_original{$p}->{$t}->[0]) ? $result_residual_data_original{$p}->{$t}->[0] : 'NA';
                my @row = ($trait_name_encoder{$time}." Residual Value", $stock_name_row_col{$p}->{row_number}, $stock_name_row_col{$p}->{col_number}, $val);
                my $line = join ',', @row;
                print $F_res "$line\n";
            }
        }
    close($F_res);

    my $stats_out_tempfile_spatial_heatmaps_plot_string = $c->tempfile( TEMPLATE => 'tmp_trial_2dspl/figureXXXX');
    $stats_out_tempfile_spatial_heatmaps_plot_string .= '.png';
    my $stats_out_tempfile_spatial_heatmaps_plot = $c->config->{basepath}."/".$stats_out_tempfile_spatial_heatmaps_plot_string;

    my $output_plot_row = 'row';
    my $output_plot_col = 'col';
    if ($max_col > $max_row) {
        $output_plot_row = 'col';
        $output_plot_col = 'row';
    }

    my $cmd_spatialfirst_plot_1 = 'R -e "library(data.table); library(ggplot2); library(dplyr); library(viridis); library(GGally); library(gridExtra); library(grid);
    mat_orig <- fread(\''.$stats_out_tempfile_pheno_heatmaps.'\', header=TRUE, sep=\',\');
    mat_eff <- fread(\''.$stats_out_tempfile_spatial_heatmaps.'\', header=TRUE, sep=\',\');
    mat_fit <- fread(\''.$stats_out_tempfile_fitted_heatmaps.'\', header=TRUE, sep=\',\');
    mat_res <- fread(\''.$stats_out_tempfile_residuals_heatmaps.'\', header=TRUE, sep=\',\');
    gg1 <- ggplot(mat_orig, aes('.$output_plot_col.', '.$output_plot_row.', fill=value)) + geom_tile() + scale_fill_viridis(discrete=FALSE) + coord_equal() + facet_wrap(~trait_type, ncol='.scalar(@sorted_trait_names).');
    gg2 <- ggplot(mat_eff, aes('.$output_plot_col.', '.$output_plot_row.', fill=value)) + geom_tile() + scale_fill_viridis(discrete=FALSE) + coord_equal() + facet_wrap(~trait_type, ncol='.scalar(@sorted_trait_names).');
    gg3 <- ggplot(mat_fit, aes('.$output_plot_col.', '.$output_plot_row.', fill=value)) + geom_tile() + scale_fill_viridis(discrete=FALSE) + coord_equal() + facet_wrap(~trait_type, ncol='.scalar(@sorted_trait_names).');
    gg4 <- ggplot(mat_res, aes('.$output_plot_col.', '.$output_plot_row.', fill=value)) + geom_tile() + scale_fill_viridis(discrete=FALSE) + coord_equal() + facet_wrap(~trait_type, ncol='.scalar(@sorted_trait_names).');
    gg <- grid.arrange(gg1, gg2, gg3, gg4, ncol=1, top=textGrob(\'Phenotypes, Permanent Environment (PE) Effects, Fitted and Residual Values\'), bottom=textGrob(\'Time\') );
    ggsave(\''.$stats_out_tempfile_spatial_heatmaps_plot.'\', gg, device=\'png\', width=20, height=30, units=\'in\');
    "';
    # print STDERR Dumper $cmd_spatialfirst_plot_1;
    my $status_spatialfirst_plot_1 = system($cmd_spatialfirst_plot_1);


    my @sorted_germplasm_names = sort keys %unique_accessions;

    open(my $F_gen, ">", $effects_original_line_chart_tempfile) || die "Can't open file ".$effects_original_line_chart_tempfile;
        print $F_gen "germplasmName,time,value\n";
        foreach my $p (@sorted_germplasm_names) {
            foreach my $t (@sorted_trait_names) {
                my $val = $result_blup_data_original{$p}->{$seen_times{$t}}->[0];
                my @row = ($p, $t, $val);
                my $line = join ',', @row;
                print $F_gen "$line\n";
            }
        }
    close($F_gen);

    my @set = ('0' ..'9', 'A' .. 'F');
    my @colors;
    for (1..scalar(@sorted_germplasm_names)) {
        my $str = join '' => map $set[rand @set], 1 .. 6;
        push @colors, '#'.$str;
    }
    my $color_string = join '\',\'', @colors;

    my $genetic_effects_figure_tempfile_string = $c->tempfile( TEMPLATE => 'tmp_trial_2dspl/figureXXXX');
    $genetic_effects_figure_tempfile_string .= '.png';
    my $genetic_effects_figure_tempfile = $c->config->{basepath}."/".$genetic_effects_figure_tempfile_string;

    my $cmd_gen_plot = 'R -e "library(data.table); library(ggplot2); library(GGally); library(gridExtra);
    mat <- fread(\''.$effects_original_line_chart_tempfile.'\', header=TRUE, sep=\',\');
    mat\$time <- as.numeric(as.character(mat\$time));
    options(device=\'png\');
    par();
    sp <- ggplot(mat, aes(x = time, y = value)) +
        geom_line(aes(color = germplasmName), size = 1) +
        scale_fill_manual(values = c(\''.$color_string.'\')) +
        theme_minimal();
    sp <- sp + guides(shape = guide_legend(override.aes = list(size = 0.5)));
    sp <- sp + guides(color = guide_legend(override.aes = list(size = 0.5)));
    sp <- sp + theme(legend.title = element_text(size = 3), legend.text = element_text(size = 3));
    sp <- sp + labs(title = \'Genetic Effects\');';
    if (scalar(@sorted_germplasm_names) > 100) {
        $cmd_gen_plot .= 'sp <- sp + theme(legend.position = \'none\');';
    }
    $cmd_gen_plot .= 'ggsave(\''.$genetic_effects_figure_tempfile.'\', sp, device=\'png\', width=12, height=6, units=\'in\');
    "';
    # print STDERR Dumper $cmd_gen_plot;
    my $status_gen_plot = system($cmd_gen_plot);

    my @response_trait_ids;
    my %postcomposing_info;
    my $statistics_cvterm_id = SGN::Model::Cvterm->get_cvterm_row_from_trait_name($schema, $statistics_cvterm_name)->cvterm_id();
    foreach my $time (@sorted_trait_names) {
        my $trait_name = $seen_times{$time};
        my $trait_id = $trait_id_map{$trait_name};
        push @response_trait_ids, $trait_id;

        my @comp;
        push @comp, {
            category_name => 'attribute',
            cvterm_id => $statistics_cvterm_id
        };

        my $time_cvterm_name = $trait_time_map{$trait_name};
        if ($time_cvterm_name) {
            my $time_cvterm_id = SGN::Model::Cvterm->get_cvterm_row_from_trait_name($schema, $time_cvterm_name)->cvterm_id();
            push @comp, {
                category_name => 'toy',
                cvterm_id => $time_cvterm_id
            };
        }

        $postcomposing_info{$trait_id} = \@comp;
    }

    $c->stash->{rest} = {
        success => 1,
        result_blup_data_original => \%result_blup_data_original,
        genetic_effect_min_original => $genetic_effect_min_original,
        genetic_effect_max_original => $genetic_effect_max_original,
        genetic_effect_sum_original => $genetic_effect_sum_original,
        genetic_effect_sum_square_original => $genetic_effect_sum_square_original,
        result_blup_spatial_data_original => \%result_blup_spatial_data_original,
        env_effect_min_original => $env_effect_min_original,
        env_effect_max_original => $env_effect_max_original,
        env_effect_sum_original => $env_effect_sum_original,
        env_effect_sum_square_original => $env_effect_sum_square_original,
        result_residual_data_original => \%result_residual_data_original,
        residual_sum_original => $residual_sum_original,
        residual_sum_square_original => $residual_sum_square_original,
        result_fitted_data_original => \%result_fitted_data_original,
        model_sum_square_residual_original => $model_sum_square_residual_original,
        varcomp_original => \@varcomp_original,
        varcomp_herit => \@varcomp_herit,
        heatmaps_plot => $stats_out_tempfile_spatial_heatmaps_plot_string,
        gen_effects_line_plot => $genetic_effects_figure_tempfile_string,
        model_rds_files => \@model_rds_files,
        postcomposing_info => \%postcomposing_info,
        trait_ids => \@response_trait_ids
    };
}

sub trial_plot_time_series_accessions : Chained('trial') PathPart('plot_time_series_accessions') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $schema = $c->stash->{schema};
    my $trait_ids = decode_json $c->req->param('trait_ids');
    my $accession_ids = $c->req->param('accession_ids') ne 'null' ? decode_json $c->req->param('accession_ids') : [];
    my $trait_format = $c->req->param('trait_format');
    my $data_level = $c->req->param('data_level');
    my $draw_error_bars = $c->req->param('draw_error_bars');
    my $use_cumulative_phenotype = $c->req->param('use_cumulative_phenotype');

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$schema,
            data_level=>$data_level,
            trait_list=>$trait_ids,
            trial_list=>[$c->stash->{trial_id}],
            accession_list=>$accession_ids,
            include_timestamp=>0,
            exclude_phenotype_outlier=>0
        }
    );
    my ($data, $unique_traits) = $phenotypes_search->search();
    my @sorted_trait_names = sort keys %$unique_traits;

    if (scalar(@$data) == 0) {
        $c->stash->{rest} = { error => "There are no phenotypes for the trials and traits you have selected!"};
        return;
    }

    my %trait_ids_hash = map {$_ => 1} @$trait_ids;

    my $trial = CXGN::Trial->new({bcs_schema=>$schema, trial_id=>$c->stash->{trial_id}});
    my $traits_assayed = $trial->get_traits_assayed($data_level, $trait_format, 'time_ontology');
    my %unique_traits_ids;
    foreach (@$traits_assayed) {
        if (exists($trait_ids_hash{$_->[0]})) {
            $unique_traits_ids{$_->[0]} = $_;
        }
    }
    my %unique_components;
    foreach (values %unique_traits_ids) {
        foreach my $component (@{$_->[2]}) {
            if ($component->{cv_type} && $component->{cv_type} eq 'time_ontology') {
                $unique_components{$_->[0]} = $component->{name};
            }
        }
    }

    my @sorted_times;
    my %sorted_time_hash;
    while( my($trait_id, $time_name) = each %unique_components) {
        my @time_split = split ' ', $time_name;
        my $time_val = $time_split[1] + 0;
        push @sorted_times, $time_val;
        $sorted_time_hash{$time_val} = $trait_id;
    }
    @sorted_times = sort @sorted_times;

    my %cumulative_time_hash;
    while( my($trait_id, $time_name) = each %unique_components) {
        my @time_split = split ' ', $time_name;
        my $time_val = $time_split[1] + 0;
        foreach my $t (@sorted_times) {
            if ($t < $time_val) {
                push @{$cumulative_time_hash{$time_val}}, $sorted_time_hash{$t};
            }
        }
    }

    my %phenotype_data;
    my %trait_hash;
    my %seen_germplasm_names;
    foreach my $obs_unit (@$data){
        my $obsunit_id = $obs_unit->{observationunit_stock_id};
        my $observations = $obs_unit->{observations};
        my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
        my $germplasm_uniquename = $obs_unit->{germplasm_uniquename};
        foreach (@$observations){
            push @{$phenotype_data{$germplasm_uniquename}->{$_->{trait_id}}}, $_->{value};
            $trait_hash{$_->{trait_id}} = $_->{trait_name};
        }
        $seen_germplasm_names{$germplasm_uniquename}++;
    }
    my @sorted_germplasm_names = sort keys %seen_germplasm_names;

    my $header_string = 'germplasmName,time,value,sd';

    my $dir = $c->tempfiles_subdir('/trial_analysis_accession_time_series_plot_dir');
    my $pheno_data_tempfile_string = $c->tempfile( TEMPLATE => 'trial_analysis_accession_time_series_plot_dir/datafileXXXX');
    $pheno_data_tempfile_string .= '.csv';
    my $stats_tempfile = $c->config->{basepath}."/".$pheno_data_tempfile_string;

    open(my $F, ">", $stats_tempfile) || die "Can't open file ".$stats_tempfile;
        print $F $header_string."\n";
        foreach my $s (@sorted_germplasm_names) {
            foreach my $t (@$trait_ids) {
                my $time = $unique_components{$t};
                my @time_split = split ' ', $time;
                my $time_val = $time_split[1];
                my $vals = $phenotype_data{$s}->{$t};
                my $val;
                my $sd;
                if (!$vals || scalar(@$vals) == 0) {
                    $val = 'NA';
                    $sd = 0;
                }
                else {
                    my $stat = Statistics::Descriptive::Full->new();
                    $stat->add_data(@$vals);
                    $sd = $stat->standard_deviation();
                    $val = $stat->mean();
                    if ($use_cumulative_phenotype eq 'Yes') {
                        my $previous_time_trait_ids = $cumulative_time_hash{$time_val};
                        my @previous_vals_avgs = ($val);
                        foreach my $pt (@$previous_time_trait_ids) {
                            my $previous_vals = $phenotype_data{$s}->{$pt};
                            my $previous_stat = Statistics::Descriptive::Full->new();
                            $previous_stat->add_data(@$previous_vals);
                            my $previous_val_avg = $previous_stat->mean();
                            push @previous_vals_avgs, $previous_val_avg;
                        }
                        my $stat_cumulative = Statistics::Descriptive::Full->new();
                        $stat_cumulative->add_data(@previous_vals_avgs);
                        $sd = $stat_cumulative->standard_deviation();
                        $val = sum(@previous_vals_avgs);
                    }
                }
                print $F "$s,$time_val,$val,$sd\n";
            }
        }
    close($F);

    my @set = ('0' ..'9', 'A' .. 'F');
    my @colors;
    for (1..scalar(@sorted_germplasm_names)) {
        my $str = join '' => map $set[rand @set], 1 .. 6;
        push @colors, '#'.$str;
    }
    my $color_string = join '\',\'', @colors;

    my $pheno_figure_tempfile_string = $c->tempfile( TEMPLATE => 'trial_analysis_accession_time_series_plot_dir/figureXXXX');
    $pheno_figure_tempfile_string .= '.png';
    my $pheno_figure_tempfile = $c->config->{basepath}."/".$pheno_figure_tempfile_string;

    my $cmd = 'R -e "library(data.table); library(ggplot2);
    mat <- fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\');
    mat\$time <- as.numeric(as.character(mat\$time));
    options(device=\'png\');
    par();
    sp <- ggplot(mat, aes(x = time, y = value)) +
        geom_line(aes(color = germplasmName), size = 1) +
        scale_fill_manual(values = c(\''.$color_string.'\')) +
        theme_minimal()';
    if ($draw_error_bars eq "Yes") {
        $cmd .= '+ geom_errorbar(aes(ymin=value-sd, ymax=value+sd, color=germplasmName), width=.2, position=position_dodge(0.05));
        ';
    }
    else {
        $cmd .= ';
        ';
    }
    $cmd .= 'sp <- sp + guides(shape = guide_legend(override.aes = list(size = 0.5)));
    sp <- sp + guides(color = guide_legend(override.aes = list(size = 0.5)));
    sp <- sp + theme(legend.title = element_text(size = 3), legend.text = element_text(size = 3));';
    if (scalar(@sorted_germplasm_names) > 100) {
        $cmd .= 'sp <- sp + theme(legend.position = \'none\');';
    }
    $cmd .= 'ggsave(\''.$pheno_figure_tempfile.'\', sp, device=\'png\', width=12, height=6, units=\'in\');
    dev.off();"';
    print STDERR Dumper $cmd;
    my $status = system($cmd);

    $c->stash->{rest} = {success => 1, figure => $pheno_figure_tempfile_string, data_file => $pheno_data_tempfile_string, cmd => $cmd};
}

sub trial_accessions_rank : Chained('trial') PathPart('accessions_rank') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $schema = $c->stash->{schema};
    my $trait_ids = decode_json $c->req->param('trait_ids');
    my $trait_weights = decode_json $c->req->param('trait_weights');
    my $accession_ids = $c->req->param('accession_ids') ne 'null' ? decode_json $c->req->param('accession_ids') : [];
    my $trait_format = $c->req->param('trait_format');
    my $data_level = $c->req->param('data_level');

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$schema,
            data_level=>$data_level,
            trait_list=>$trait_ids,
            trial_list=>[$c->stash->{trial_id}],
            accession_list=>$accession_ids,
            include_timestamp=>0,
            exclude_phenotype_outlier=>0
        }
    );
    my ($data, $unique_traits) = $phenotypes_search->search();
    my @sorted_trait_names = sort keys %$unique_traits;

    if (scalar(@$data) == 0) {
        $c->stash->{rest} = { error => "There are no phenotypes for the trials and traits you have selected!"};
        return;
    }

    my %trait_weight_map;
    foreach (@$trait_weights) {
        $trait_weight_map{$_->[0]} = $_->[1];
    }
    print STDERR Dumper \%trait_weight_map;

    my %phenotype_data;
    my %trait_hash;
    my %seen_germplasm_names;
    foreach my $obs_unit (@$data){
        my $obsunit_id = $obs_unit->{observationunit_stock_id};
        my $observations = $obs_unit->{observations};
        my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
        my $germplasm_uniquename = $obs_unit->{germplasm_uniquename};
        foreach (@$observations){
            push @{$phenotype_data{$germplasm_uniquename}->{$_->{trait_id}}}, $_->{value};
            $trait_hash{$_->{trait_id}} = $_->{trait_name};
        }
        $seen_germplasm_names{$germplasm_uniquename}++;
    }
    my @sorted_germplasm_names = sort keys %seen_germplasm_names;

    my %accession_sum;
    foreach my $s (@sorted_germplasm_names) {
        foreach my $t (@$trait_ids) {
            my $vals = $phenotype_data{$s}->{$t};
            my $average_val = sum(@$vals)/scalar(@$vals);
            my $average_val_weighted = $average_val*$trait_weight_map{$t};
            $accession_sum{$s} += $average_val_weighted;
        }
    }

    my @sorted_accessions = sort { $accession_sum{$b} <=> $accession_sum{$a} } keys(%accession_sum);
    my @sorted_values = @accession_sum{@sorted_accessions};
    my @sorted_rank = (1..scalar(@sorted_accessions));

    $c->stash->{rest} = {success => 1, results => \%accession_sum, sorted_accessions => \@sorted_accessions, sorted_values => \@sorted_values, sorted_ranks => \@sorted_rank};
}

sub trial_genotype_comparison : Chained('trial') PathPart('genotype_comparison') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    print STDERR Dumper $c->req->params();
    my $schema = $c->stash->{schema};
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $trait_ids = decode_json $c->req->param('trait_ids');
    my $trait_weights = decode_json $c->req->param('trait_weights');
    my $accession_ids = $c->req->param('accession_ids') ne 'null' ? decode_json $c->req->param('accession_ids') : [];
    my $trait_format = $c->req->param('trait_format');
    my $nd_protocol_id = $c->req->param('nd_protocol_id');
    my $data_level = $c->req->param('data_level');
    my $genotype_filter_string = $c->req->param('genotype_filter');
    my $compute_from_parents = $c->req->param('compute_from_parents') eq 'yes' ? 1 : 0;

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$schema,
            data_level=>$data_level,
            trait_list=>$trait_ids,
            trial_list=>[$c->stash->{trial_id}],
            accession_list=>$accession_ids,
            include_timestamp=>0,
            exclude_phenotype_outlier=>0
        }
    );
    my ($data, $unique_traits) = $phenotypes_search->search();
    my @sorted_trait_names = sort keys %$unique_traits;

    if (scalar(@$data) == 0) {
        $c->stash->{rest} = { error => "There are no phenotypes for the trials and traits you have selected!"};
        return;
    }

    my %trait_weight_map;
    foreach (@$trait_weights) {
        $trait_weight_map{$_->[0]} = $_->[1];
    }
    # print STDERR Dumper \%trait_weight_map;

    my %phenotype_data;
    my %trait_hash;
    my %seen_germplasm_names;
    my %seen_germplasm_ids;
    foreach my $obs_unit (@$data){
        my $obsunit_id = $obs_unit->{observationunit_stock_id};
        my $observations = $obs_unit->{observations};
        my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
        my $germplasm_uniquename = $obs_unit->{germplasm_uniquename};
        foreach (@$observations){
            push @{$phenotype_data{$germplasm_uniquename}->{$_->{trait_id}}}, $_->{value};
            $trait_hash{$_->{trait_id}} = $_->{trait_name};
        }
        $seen_germplasm_names{$germplasm_uniquename} = $germplasm_stock_id;
        $seen_germplasm_ids{$germplasm_stock_id}++;
    }
    my @sorted_germplasm_names = sort keys %seen_germplasm_names;
    my @sorted_germplasm_ids = sort keys %seen_germplasm_ids;

    my %accession_sum;
    foreach my $s (@sorted_germplasm_names) {
        foreach my $t (@$trait_ids) {
            my $vals = $phenotype_data{$s}->{$t};
            my $average_val = sum(@$vals)/scalar(@$vals);
            my $average_val_weighted = $average_val*$trait_weight_map{$t};
            $accession_sum{$s} += $average_val_weighted;
        }
    }

    my @sorted_accessions = sort { $accession_sum{$b} <=> $accession_sum{$a} } keys(%accession_sum);
    my @sorted_values = @accession_sum{@sorted_accessions};
    my $sort_increment = ceil(scalar(@sorted_accessions)/10)+0;
    # print STDERR Dumper $sort_increment;

    my $percentile_inc = $sort_increment/scalar(@sorted_accessions);

    my $acc_counter = 1;
    my $rank_counter = 1;
    my %rank_hash;
    my %rank_lookup;
    my %rank_percentile;
    foreach (@sorted_accessions) {
        print STDERR Dumper $acc_counter;
        if ($acc_counter >= $sort_increment) {
            $rank_counter++;
            $acc_counter = 0;
        }
        my $stock_id = $seen_germplasm_names{$_};
        push @{$rank_hash{$rank_counter}}, $stock_id;
        $rank_lookup{$stock_id} = $rank_counter;
        my $percentile = $rank_counter*$percentile_inc;
        $rank_percentile{$rank_counter} = "Rank ".$rank_counter;
        $acc_counter++;
    }

    my @sorted_rank_groups;
    foreach (@sorted_accessions) {
        my $stock_id = $seen_germplasm_names{$_};
        push @sorted_rank_groups, $rank_lookup{$stock_id};
    }
    my @sorted_ranks = (1..scalar(@sorted_accessions));
    # print STDERR Dumper \%rank_hash;
    # print STDERR Dumper \%rank_lookup;

    my $geno = CXGN::Genotype::DownloadFactory->instantiate(
        'DosageMatrix',    #can be either 'VCF' or 'DosageMatrix'
        {
            bcs_schema=>$schema,
            people_schema=>$people_schema,
            cache_root_dir=>$c->config->{cache_file_path},
            accession_list=>\@sorted_germplasm_ids,
            trial_list=>[$c->stash->{trial_id}],
            protocol_id_list=>[$nd_protocol_id],
            compute_from_parents=>$compute_from_parents,
        }
    );
    my $file_handle = $geno->download(
        $c->config->{cluster_shared_tempdir},
        $c->config->{backend},
        $c->config->{cluster_host},
        $c->config->{'web_cluster_queue'},
        $c->config->{basepath}
    );

    my %genotype_filter;
    if ($genotype_filter_string) {
        my @genos = split ',', $genotype_filter_string;
        %genotype_filter = map {$_ => 1} @genos;
    }

    my %geno_rank_counter;
    my %geno_rank_seen_scores;
    my @marker_names;
    open my $geno_fh, "<&", $file_handle or die "Can't open output file: $!";
        my $header = <$geno_fh>;
        chomp($header);
        # print STDERR Dumper $header;
        my @header = split "\t", $header;
        my $header_dummy = shift @header;

        my $position = 0;
        while (my $row = <$geno_fh>) {
            chomp($row);
            if ($row) {
                # print STDERR Dumper $row;
                my @line = split "\t", $row;
                my $marker_name = shift @line;
                push @marker_names, $marker_name;
                my $counter = 0;
                foreach (@line) {
                    if ( defined $_ && $_ ne '' && $_ ne 'NA') {
                        my $rank = $rank_lookup{$header[$counter]};
                        if (!$genotype_filter_string || exists($genotype_filter{$_})) {
                            $geno_rank_counter{$rank}->{$position}->{$_}++;
                            $geno_rank_seen_scores{$_}++;
                        }
                    }
                    $counter++;
                }
                $position++;
            }
        }
    close($geno_fh);
    # print STDERR Dumper \%geno_rank_counter;
    my @sorted_seen_scores = sort keys %geno_rank_seen_scores;

    my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
    my $tmp_stats_dir = $shared_cluster_dir_config."/tmp_trial_genotype_comparision";
    mkdir $tmp_stats_dir if ! -d $tmp_stats_dir;
    my ($stats_tempfile_fh, $stats_tempfile) = tempfile("drone_stats_XXXXX", DIR=> $tmp_stats_dir);

    my $header_string = 'Rank,Genotype,Marker,Count';

    open(my $F, ">", $stats_tempfile) || die "Can't open file ".$stats_tempfile;
        print $F $header_string."\n";
        while (my ($rank, $pos_o) = each %geno_rank_counter) {
            while (my ($position, $score_o) = each %$pos_o) {
                while (my ($score, $count) = each %$score_o) {
                    print $F $rank_percentile{$rank}.",$score,$position,$count\n";
                }
            }
        }
    close($F);

    my @set = ('0' ..'9', 'A' .. 'F');
    my @colors;
    for (1..scalar(@sorted_seen_scores)) {
        my $str = join '' => map $set[rand @set], 1 .. 6;
        push @colors, '#'.$str;
    }
    my $color_string = join '\',\'', @colors;

    my $dir = $c->tempfiles_subdir('/trial_analysis_genotype_comparision_plot_dir');
    my $pheno_figure_tempfile_string = $c->tempfile( TEMPLATE => 'trial_analysis_genotype_comparision_plot_dir/figureXXXX');
    $pheno_figure_tempfile_string .= '.png';
    my $pheno_figure_tempfile = $c->config->{basepath}."/".$pheno_figure_tempfile_string;

    my $cmd = 'R -e "library(data.table); library(ggplot2);
    mat <- fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\');
    mat\$Marker <- as.numeric(as.character(mat\$Marker));
    mat\$Genotype <- as.character(mat\$Genotype);
    options(device=\'png\');
    par();
    sp <- ggplot(mat, aes(x = Marker, y = Count)) +
        geom_line(aes(color = Genotype), size=0.2) +
        scale_fill_manual(values = c(\''.$color_string.'\')) +
        theme_minimal();
    sp <- sp + facet_grid(Rank ~ .);';
    $cmd .= 'ggsave(\''.$pheno_figure_tempfile.'\', sp, device=\'png\', width=12, height=12, units=\'in\');
    dev.off();"';
    print STDERR Dumper $cmd;
    my $status = system($cmd);

    $c->stash->{rest} = {success => 1, results => \%accession_sum, sorted_accessions => \@sorted_accessions, sorted_values => \@sorted_values, sorted_ranks => \@sorted_ranks, sorted_rank_groups => \@sorted_rank_groups, figure => $pheno_figure_tempfile_string};
}

sub trial_calculate_numerical_derivative : Chained('trial') PathPart('calculate_numerical_derivative') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $metadata_schema = $c->stash->{metadata_schema};
    my $phenome_schema = $c->stash->{phenome_schema};
    my $trait_ids = decode_json $c->req->param('trait_ids');
    my $derivative = $c->req->param('derivative');
    my $data_level = $c->req->param('data_level');

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$schema,
            data_level=>$data_level,
            trait_list=>$trait_ids,
            trial_list=>[$c->stash->{trial_id}],
            include_timestamp=>0,
            exclude_phenotype_outlier=>0
        }
    );
    my ($data, $unique_traits) = $phenotypes_search->search();
    my @sorted_trait_names = sort keys %$unique_traits;

    if (scalar(@$data) == 0) {
        $c->stash->{rest} = { error => "There are no phenotypes for the trials and traits you have selected!"};
        return;
    }

    my %phenotype_data;
    my %seen_plot_names;
    my %seen_rows;
    my %seen_cols;
    my %row_col_hash;
    my %rev_row;
    my %rev_col;
    foreach my $obs_unit (@$data){
        my $obsunit_id = $obs_unit->{observationunit_stock_id};
        my $obsunit_name = $obs_unit->{observationunit_uniquename};
        my $observations = $obs_unit->{observations};
        my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
        my $germplasm_uniquename = $obs_unit->{germplasm_uniquename};
        my $row = $obs_unit->{obsunit_row_number};
        my $col = $obs_unit->{obsunit_col_number};
        foreach (@$observations){
            $phenotype_data{$obsunit_name}->{$_->{trait_name}} = $_->{value};
        }
        $rev_row{$obsunit_name} = $row;
        $rev_col{$obsunit_name} = $col;
        $row_col_hash{$row}->{$col} = $obsunit_name;
        $seen_plot_names{$obsunit_name}++;
        $seen_rows{$row}++;
        $seen_cols{$col}++;
    }
    my @sorted_plot_names = sort keys %seen_plot_names;
    my @sorted_rows = sort { $a <=> $b } keys %seen_rows;
    my @sorted_cols = sort { $a <=> $b } keys %seen_cols;

    my @allowed_composed_cvs = split ',', $c->config->{composable_cvs};
    my $composable_cvterm_delimiter = $c->config->{composable_cvterm_delimiter};
    my $composable_cvterm_format = $c->config->{composable_cvterm_format};

    my %trait_id_map;
    foreach my $trait_name (@sorted_trait_names) {
        my $trait_cvterm_id = SGN::Model::Cvterm->get_cvterm_row_from_trait_name($schema, $trait_name)->cvterm_id();
        $trait_id_map{$trait_name} = $trait_cvterm_id;
    }
    my @trait_ids = values %trait_id_map;

    my $analysis_statistical_ontology_term = 'Two-dimension numerical first derivative across rows and columns|SGNSTAT:0000022';
    # my $analysis_statistical_ontology_term = 'Two-dimension numerical second derivative across rows and columns|SGNSTAT:0000023';
    my $stat_cvterm_id = SGN::Model::Cvterm->get_cvterm_row_from_trait_name($schema, $analysis_statistical_ontology_term)->cvterm_id();

    my $categories = {
        object => [],
        attribute => [$stat_cvterm_id],
        method => [],
        unit => [],
        trait => \@trait_ids,
        tod => [],
        toy => [],
        gen => [],
    };

    my %time_term_map;

    my $traits = SGN::Model::Cvterm->get_traits_from_component_categories($schema, \@allowed_composed_cvs, $composable_cvterm_delimiter, $composable_cvterm_format, $categories);
    my $existing_traits = $traits->{existing_traits};
    my $new_traits = $traits->{new_traits};
    # print STDERR Dumper $new_traits;
    # print STDERR Dumper $existing_traits;
    my %new_trait_names;
    foreach (@$new_traits) {
        my $components = $_->[0];
        $new_trait_names{$_->[1]} = join ',', @$components;
    }

    my $onto = CXGN::Onto->new( { schema => $schema } );
    my $new_terms = $onto->store_composed_term(\%new_trait_names);

    my %composed_trait_map;
    while (my($trait_name, $trait_id) = each %trait_id_map) {
        my $components = [$trait_id, $stat_cvterm_id];
        my $composed_cvterm_id = SGN::Model::Cvterm->get_trait_from_exact_components($schema, $components);
        my $composed_trait_name = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $composed_cvterm_id, 'extended');
        $composed_trait_map{$trait_name} = $composed_trait_name;
    }
    my @composed_trait_names = values %composed_trait_map;

    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();

    my %derivative_results;
    no warnings 'uninitialized';
    foreach my $s (@sorted_plot_names) {
        foreach my $t (@sorted_trait_names) {
            my $trait = $composed_trait_map{$t};
            my @derivs;
            my $val = $phenotype_data{$s}->{$t};
            my $row = $rev_row{$s};
            my $col = $rev_col{$s};
            my @values = (
                $phenotype_data{$row_col_hash{$row-1}->{$col}}->{$t},
                $phenotype_data{$row_col_hash{$row+1}->{$col}}->{$t},
                $phenotype_data{$row_col_hash{$row}->{$col-1}}->{$t},
                $phenotype_data{$row_col_hash{$row}->{$col+1}}->{$t},

                $phenotype_data{$row_col_hash{$row-1}->{$col-1}}->{$t},
                $phenotype_data{$row_col_hash{$row+1}->{$col-1}}->{$t},
                $phenotype_data{$row_col_hash{$row-1}->{$col+1}}->{$t},
                $phenotype_data{$row_col_hash{$row+1}->{$col+1}}->{$t},

                $phenotype_data{$row_col_hash{$row-2}->{$col}}->{$t},
                $phenotype_data{$row_col_hash{$row+2}->{$col}}->{$t},
                $phenotype_data{$row_col_hash{$row}->{$col-2}}->{$t},
                $phenotype_data{$row_col_hash{$row}->{$col+2}}->{$t},

                $phenotype_data{$row_col_hash{$row-2}->{$col-2}}->{$t},
                $phenotype_data{$row_col_hash{$row+2}->{$col-2}}->{$t},
                $phenotype_data{$row_col_hash{$row-2}->{$col+2}}->{$t},
                $phenotype_data{$row_col_hash{$row+2}->{$col+2}}->{$t},

                $phenotype_data{$row_col_hash{$row-2}->{$col-1}}->{$t},
                $phenotype_data{$row_col_hash{$row+2}->{$col-1}}->{$t},
                $phenotype_data{$row_col_hash{$row-2}->{$col+1}}->{$t},
                $phenotype_data{$row_col_hash{$row+2}->{$col+1}}->{$t},

                $phenotype_data{$row_col_hash{$row-1}->{$col-2}}->{$t},
                $phenotype_data{$row_col_hash{$row+1}->{$col-2}}->{$t},
                $phenotype_data{$row_col_hash{$row-1}->{$col+2}}->{$t},
                $phenotype_data{$row_col_hash{$row+1}->{$col+2}}->{$t},

                $phenotype_data{$row_col_hash{$row-3}->{$col}}->{$t},
                $phenotype_data{$row_col_hash{$row+3}->{$col}}->{$t},
                $phenotype_data{$row_col_hash{$row}->{$col-3}}->{$t},
                $phenotype_data{$row_col_hash{$row}->{$col+3}}->{$t},

                $phenotype_data{$row_col_hash{$row-3}->{$col-3}}->{$t},
                $phenotype_data{$row_col_hash{$row+3}->{$col-3}}->{$t},
                $phenotype_data{$row_col_hash{$row-3}->{$col+3}}->{$t},
                $phenotype_data{$row_col_hash{$row+3}->{$col+3}}->{$t},

                $phenotype_data{$row_col_hash{$row-3}->{$col-1}}->{$t},
                $phenotype_data{$row_col_hash{$row+3}->{$col-1}}->{$t},
                $phenotype_data{$row_col_hash{$row-3}->{$col+1}}->{$t},
                $phenotype_data{$row_col_hash{$row+3}->{$col+1}}->{$t},

                $phenotype_data{$row_col_hash{$row-3}->{$col-2}}->{$t},
                $phenotype_data{$row_col_hash{$row+3}->{$col-2}}->{$t},
                $phenotype_data{$row_col_hash{$row-3}->{$col+2}}->{$t},
                $phenotype_data{$row_col_hash{$row+3}->{$col+2}}->{$t},

                $phenotype_data{$row_col_hash{$row-1}->{$col-3}}->{$t},
                $phenotype_data{$row_col_hash{$row+1}->{$col-3}}->{$t},
                $phenotype_data{$row_col_hash{$row-1}->{$col+3}}->{$t},
                $phenotype_data{$row_col_hash{$row+1}->{$col+3}}->{$t},

                $phenotype_data{$row_col_hash{$row-2}->{$col-3}}->{$t},
                $phenotype_data{$row_col_hash{$row+2}->{$col-3}}->{$t},
                $phenotype_data{$row_col_hash{$row-2}->{$col+3}}->{$t},
                $phenotype_data{$row_col_hash{$row+2}->{$col+3}}->{$t}
            );

            foreach (@values) {
                if (defined($_)) {
                    push @derivs, ($val - $_);
                    push @derivs, ( (($val + $_)/8) - $_);
                    push @derivs, ( (($val + $_)/4) - $_);
                    push @derivs, ( (($val + $_)*3/8) - $_);
                    push @derivs, ( (($val + $_)/2) - $_);
                    push @derivs, ( (($val + $_)*5/8) - $_);
                    push @derivs, ( (($val + $_)*3/4) - $_);
                    push @derivs, ( (($val + $_)*7/8) - $_);
                }
            }
            # print STDERR Dumper \@derivs;
            if (scalar(@derivs) > 0) {
                my $d = sum(@derivs)/scalar(@derivs);
                $derivative_results{$s}->{$trait} = [$d, $timestamp, $user_name, '', ''];
            }
        }
    }
    # print STDERR Dumper \%derivative_results;

    if (scalar(keys %derivative_results) != scalar(@sorted_plot_names)) {
        $c->stash->{rest} = { error => "Not all plots have rows and columns defined! Please make sure row and columns are saved for this field trial!"};
        return;
    }

    my %phenotype_metadata = (
        'archived_file' => 'none',
        'archived_file_type' => 'numerical_derivative_row_and_column_computation',
        'operator' => $user_name,
        'date' => $timestamp
    );

    my $store_phenotypes = CXGN::Phenotypes::StorePhenotypes->new(
        basepath=>$c->config->{basepath},
        dbhost=>$c->config->{dbhost},
        dbname=>$c->config->{dbname},
        dbuser=>$c->config->{dbuser},
        dbpass=>$c->config->{dbpass},
        bcs_schema=>$schema,
        metadata_schema=>$metadata_schema,
        phenome_schema=>$phenome_schema,
        user_id=>$user_id,
        stock_list=>\@sorted_plot_names,
        trait_list=>\@composed_trait_names,
        values_hash=>\%derivative_results,
        has_timestamps=>0,
        overwrite_values=>1,
        ignore_new_values=>0,
        metadata_hash=>\%phenotype_metadata,
    );
    my ($verified_warning, $verified_error) = $store_phenotypes->verify();
    my ($stored_phenotype_error, $stored_Phenotype_success) = $store_phenotypes->store();

    my $bs = CXGN::BreederSearch->new( { dbh=>$c->dbc->dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = {success => 1};
}

sub trial_upload_phenotypes : Chained('trial') PathPart('upload_phenotypes') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $metadata_schema = $c->stash->{metadata_schema};
    my $phenome_schema = $c->stash->{phenome_schema};
    my $trait_ids = decode_json $c->req->param('trait_ids');
    my $postcomposing_info = $c->req->param('postcomposing_info') ? decode_json $c->req->param('postcomposing_info') : []; # { 453 => [ {category_name=>'toy', cvterm_id=>123}, {category_name=>'attribute', cvterm_id=>431} ] }
    my $data = decode_json $c->req->param('pheno_data');
    # print STDERR Dumper $c->req->params();

    my @allowed_composed_cvs = split ',', $c->config->{composable_cvs};
    my $composable_cvterm_delimiter = $c->config->{composable_cvterm_delimiter};
    my $composable_cvterm_format = $c->config->{composable_cvterm_format};

    my %trait_id_map;
    my @sorted_trait_names;
    foreach my $trait_cvterm_id (@$trait_ids) {
        my $trait_name = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $trait_cvterm_id, 'extended');
        $trait_id_map{$trait_name} = $trait_cvterm_id;
        push @sorted_trait_names, $trait_name;
    }
    my @trait_ids = values %trait_id_map;
    # print STDERR Dumper \%trait_id_map;

    my $categories = {
        object => [],
        attribute => [],
        method => [],
        unit => [],
        trait => \@trait_ids,
        tod => [],
        toy => [],
        gen => [],
    };

    while (my($trait_id, $cats) = each %$postcomposing_info) {
        foreach my $o (@$cats) {
            my $category_name = $o->{category_name};
            my $cvterm_id = $o->{cvterm_id};
            push @{$categories->{$category_name}}, $cvterm_id;
        }
    }

    my %time_term_map;

    my $traits = SGN::Model::Cvterm->get_traits_from_component_categories($schema, \@allowed_composed_cvs, $composable_cvterm_delimiter, $composable_cvterm_format, $categories);
    my $existing_traits = $traits->{existing_traits};
    my $new_traits = $traits->{new_traits};
    # print STDERR Dumper $new_traits;
    # print STDERR Dumper $existing_traits;
    my %new_trait_names;
    foreach (@$new_traits) {
        my $components = $_->[0];
        $new_trait_names{$_->[1]} = join ',', @$components;
    }

    my $onto = CXGN::Onto->new( { schema => $schema } );
    my $new_terms = $onto->store_composed_term(\%new_trait_names);

    my %composed_trait_map;
    while (my($trait_name, $trait_id) = each %trait_id_map) {
        my @components = ($trait_id);
        foreach my $o (@{$postcomposing_info->{$trait_id}}) {
            my $category_name = $o->{category_name};
            my $cvterm_id = $o->{cvterm_id};
            push @components, $cvterm_id;
        }
        my $composed_cvterm_id = SGN::Model::Cvterm->get_trait_from_exact_components($schema, \@components);
        my $composed_trait_name = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $composed_cvterm_id, 'extended');
        $composed_trait_map{$trait_name} = $composed_trait_name;
    }
    my @composed_trait_names = values %composed_trait_map;
    # print STDERR Dumper \%composed_trait_map;

    my %store_data;
    my @stock_names;
    while (my($stock_name, $val) = each %$data) {
        while (my($trait_name, $pheno_val) = each %$val) {
            my $comp_trait_name = $composed_trait_map{$trait_name};
            if ($comp_trait_name) {
                $store_data{$stock_name}->{$comp_trait_name} = $pheno_val;
            }
            else {
                # print STDERR Dumper \%composed_trait_map;
                # die "ERROR: $trait_name not in composed trait map\n";
            }
        }
        push @stock_names, $stock_name;
    }

    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();

    my %phenotype_metadata = (
        'archived_file' => 'none',
        'archived_file_type' => 'trial_metadata_upload_phenotypes',
        'operator' => $user_name,
        'date' => $timestamp
    );

    my $store_phenotypes = CXGN::Phenotypes::StorePhenotypes->new(
        basepath=>$c->config->{basepath},
        dbhost=>$c->config->{dbhost},
        dbname=>$c->config->{dbname},
        dbuser=>$c->config->{dbuser},
        dbpass=>$c->config->{dbpass},
        bcs_schema=>$schema,
        metadata_schema=>$metadata_schema,
        phenome_schema=>$phenome_schema,
        user_id=>$user_id,
        stock_list=>\@stock_names,
        trait_list=>\@composed_trait_names,
        values_hash=>\%store_data,
        has_timestamps=>0,
        overwrite_values=>1,
        ignore_new_values=>0,
        metadata_hash=>\%phenotype_metadata,
    );
    my ($verified_warning, $verified_error) = $store_phenotypes->verify();
    my ($stored_phenotype_error, $stored_Phenotype_success) = $store_phenotypes->store();

    my $bs = CXGN::BreederSearch->new( { dbh=>$c->dbc->dbh, dbname=>$c->config->{dbname}, } );
    my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

    $c->stash->{rest} = {success => 1};
}

sub trial_genotyping_protocol_grm_link : Chained('trial') PathPart('genotyping_protocol_grm_link') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $schema = $c->stash->{schema};
    my $metadata_schema = $c->stash->{metadata_schema};
    my $phenome_schema = $c->stash->{phenome_schema};
    my $grm_genotyping_protocol_id = $c->req->param('grm_genotyping_protocol_id');

    my $trial = $c->stash->{trial};
    my $return = $trial->set_grm_genotyping_protocols($grm_genotyping_protocol_id);

    $c->stash->{rest} = {success => 1, return => $return};
}


#
# TRIAL ENTRY NUMBERS
#

#
# Get an array of entry numbers for the specified trial
# path param: trial id
# return: an array of objects, with the following keys:
#   stock_id = id of the stock
#   stock_name = uniquename of the stock
#   entry_number = entry number for the stock in this trial
#
sub get_entry_numbers : Chained('trial') PathPart('entry_numbers') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->stash->{schema};
    my $trial = $c->stash->{trial};
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    # Get Entry Number map (stock_id -> entry number)
    my $entry_number_map = $trial->get_entry_numbers();
    my @entry_numbers;
    if ( $entry_number_map ) {

        # Parse each stock - get its name
        foreach my $stock_id (keys %$entry_number_map) {
            my $row = $schema->resultset("Stock::Stock")->find({ stock_id => int($stock_id) });
            my $stock_name = $row ? $row->uniquename() : 'STOCK NO LONGER EXISTS!';
            my $entry_number = $entry_number_map->{$stock_id};
            push(@entry_numbers, { stock_id => int($stock_id), stock_name => $stock_name, entry_number => $entry_number });
        }

    }

    # Return the array of entry number info
    $c->stash->{rest} = { entry_numbers => \@entry_numbers };
}

#
# Create an entry number template for the specified trials
# query param: 'trial_ids' = comma separated list of trial ids
# return: 'file' = path to tempfile of excel template
#
sub create_entry_number_template : Path('/ajax/breeders/trial_entry_numbers/create') Args(0) {
    my $self = shift;
    my $c = shift;
    my @trial_ids = split(',', $c->req->param('trial_ids'));
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $dir = $c->tempfiles_subdir('download');
    my $temp_file_name = "entry_numbers_XXXX";
    my $rel_file = $c->tempfile( TEMPLATE => "download/$temp_file_name");
    $rel_file = $rel_file . ".xlsx";
    my $tempfile = $c->config->{basepath}."/".$rel_file;

    my $download = CXGN::Trial::Download->new({
        bcs_schema => $schema,
        trial_list => \@trial_ids,
        filename => $tempfile,
        format => 'TrialEntryNumbers'
    });
    my $error = $download->download();

    $c->stash->{rest} = { file => $tempfile };
}

#
# Download an entry number template
# query param: 'file' = path of entry number template tempfile to download
# return: contents of excel file
#
sub download_entry_number_template : Path('/ajax/breeders/trial_entry_numbers/download') Args(0) {
    my $self = shift;
    my $c = shift;
    my $tempfile = $c->req->param('file');
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    $c->res->content_type('application/vnd.ms-excel');
    $c->res->header('Content-Disposition', qq[attachment; filename="entry_number_template.xls"]);
    my $output = read_file($tempfile);
    $c->res->body($output);
}

#
# Upload an entry number template
# upload params:
#   upload_entry_numbers_file: Excel file to validate and parse
#   ignore_warnings: true to add processed data if warnings exist
# return: validation errors and warnings or success = 1 if entry numbers sucessfully stored
#   filename: original upload file name
#   error: array of error messages
#   warning: array of warning messages
#   missing_accessions: array of stock names not found in the database
#   missing_trials: array of trial names not found in database
#   success: set to `1` if file successfully validated and stored
#
sub upload_entry_number_template : Path('/ajax/breeders/trial_entry_numbers/upload') : ActionClass('REST') { }
sub upload_entry_number_template_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $upload = $c->req->upload('upload_entry_numbers_file');
    my $ignore_warnings = $c->req->param('ignore_warnings') eq 'true';
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my (@errors, %response);

    my $subdirectory = "trial_entry_numbers";
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
    if ( !$archived_filename_with_path ) {
        push(@errors, "Could not save file $upload_original_name in archive");
        $c->stash->{rest} = { filename => $upload_original_name, error => \@errors };
        return;
    }
    unlink $upload_tempfile;

    ## Parse the uploaded file
    my $parser = CXGN::Trial::ParseUpload->new(chado_schema => $schema, filename => $archived_filename_with_path);
    $parser->load_plugin('TrialEntryNumbers');
    my $parsed_data = $parser->parse();
    my $parse_errors = $parser->get_parse_errors();
    my $parse_warnings = $parser->get_parse_warnings();

    print STDERR "IGNORE WARNINGS: $ignore_warnings\n";

    ## Return with warnings and errors
    if ( $parse_errors || (!$ignore_warnings && $parse_warnings) || !$parsed_data ) {
        if ( !$parse_errors && !$parse_warnings ) {
            push(@errors, "Data could not be parsed");
            $c->stash->{rest} = { filename => $upload_original_name, error => \@errors };
            return;
        }
        $c->stash->{rest} = {
            filename => $upload_original_name,
            error => $parse_errors->{'error_messages'},
            warning => $parse_warnings->{'warning_messages'},
            missing_accessions => $parse_errors->{'missing_accessions'},
            missing_trials => $parse_errors->{'missing_trials'}
        };
        return;
    }

    ## Process the parsed data
    foreach my $trial_id (keys %$parsed_data) {
        my $trial = CXGN::Trial->new({ bcs_schema => $schema, trial_id => $trial_id });
        $trial->set_entry_numbers($parsed_data->{$trial_id});
    }

    $c->stash->{rest} = {
        success => 1,
        filename => $upload_original_name,
        warning => $parse_warnings->{'warning_messages'}
    };
    return;
}

sub update_trial_status : Chained('trial') PathPart('update_trial_status') : ActionClass('REST'){ }

sub update_trial_status_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $trial_id = $c->stash->{trial_id};
    my $trial_status = $c->req->param("trial_status");
    my $activity_date = $c->req->param("activity_date");
    my $user_name = $c->req->param("user_name");
    my $time = DateTime->now();
    my $timestamp = $time->ymd();
    my ($user_id, $user_name_l, $user_role) = _check_user_login_trial_metadata($c, 'submitter', 'submitter_access');

    my $trial_status_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'trial_status_json', 'project_property')->cvterm_id();
    my $prop = $schema->resultset("Project::Projectprop")->find({project_id => $trial_id, type_id => $trial_status_type_id});
    my $prop_id;
    my %all_activities_hash;
    if ($prop) {
        $prop_id = $prop->projectprop_id();
        my $status_json = $prop->value();
        my $status_hash_ref = decode_json $status_json;
        my $all_activities = $status_hash_ref->{'trial_activities'};
        %all_activities_hash = %{$all_activities};
    }

    $all_activities_hash{$trial_status}{'user_id'} = $user_id;
    $all_activities_hash{$trial_status}{'activity_date'} = $activity_date;

    my $trial_status_obj = CXGN::TrialStatus->new({ bcs_schema => $schema });
    $trial_status_obj->trial_activities(\%all_activities_hash);
    $trial_status_obj->parent_id($trial_id);
    $trial_status_obj->prop_id($prop_id);
    my $project_prop_id = $trial_status_obj->store();

    $c->stash->{rest} = {success => 1 };
    return;
}

sub get_all_trial_activities :Chained('trial') PathPart('all_trial_activities') Args(0){
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $trial_id = $c->stash->{trial_id};
    my $activities = $c->config->{'trial_activities'};
    my @activity_list = split ',', $activities;

    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $trial_status_obj = CXGN::TrialStatus->new({ bcs_schema => $schema, people_schema => $people_schema, parent_id => $trial_id, activity_list => \@activity_list });
    my $activity_info = $trial_status_obj->get_trial_activities();

    $c->stash->{rest} = { data => $activity_info };
}

sub update_trial_design_type : Chained('trial') PathPart('update_trial_design_type') : ActionClass('REST'){ }

sub update_trial_design_type_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $trial_design_type = $c->req->param("trial_design_type");

    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'curator', 'curator_access');

    my $trial = $c->stash->{trial};

    $trial->set_design_type($trial_design_type);

    $c->stash->{rest} = {success => 1 };
    return;
}

sub get_all_soil_data :Chained('trial') PathPart('all_soil_data') Args(0){
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $trial_id = $c->stash->{trial_id};

    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 0, 0);

    my $soil_data_obj = CXGN::BreedersToolbox::SoilData->new({ bcs_schema => $schema, parent_id => $trial_id });
    my $soil_data = $soil_data_obj->get_all_soil_data();
    my @soil_data_list = @$soil_data;
    my @formatted_soil_data;
    foreach my $info_ref (@soil_data_list) {
        my @all_soil_data = ();
        my @info = @$info_ref;
        my $trial_id = pop @info;
        my $soil_data_details = pop @info;
        my $order_ref = pop @info;
        my @data_type_order = @$order_ref;
        foreach my $type(@data_type_order) {
            my $soil_data = $soil_data_details->{$type};
            my $soil_data_string = $type.":"." ".$soil_data;
            push @all_soil_data, $soil_data_string;
        }
        my $soil_data_details_string = join("<br>", @all_soil_data);
        push @info, ($soil_data_details_string, "<a href='/breeders/trial/$trial_id/download/soil_data?format=soil_data_xls&dataLevel=soil_data&prop_id=$info[0]'>Download</a>");
        push @formatted_soil_data, {
            trial_id => $trial_id,
            prop_id => $info[0],
            description => $info[1],
            date => $info[2],
            gps => $info[3],
            type_of_sampling => $info[4],
            soil_data => $info[5],
            download_link => $info[6]
        };
    }

    $c->stash->{rest} = { data => \@formatted_soil_data };
}

sub delete_soil_data : Chained('trial') PathPart('delete_soil_data') : ActionClass('REST'){ }

sub delete_soil_data_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $prop_id = $c->req->param("prop_id");
    my $trial_id = $c->stash->{trial_id};

    my ($user_id, $user_name, $user_role) = _check_user_login_trial_metadata($c, 'curator', 'curator_access');

    my $soil_data_obj = CXGN::BreedersToolbox::SoilData->new({ bcs_schema => $schema, parent_id => $trial_id, prop_id => $prop_id });
    my $error = $soil_data_obj->delete_soil_data();

    print STDERR "ERROR = $error\n";

    if ($error) {
	    $c->stash->{rest} = { error => "An error occurred attempting to delete soil data. ($@)"};
	    return;
    }

    $c->stash->{rest} = { success => 1 };
}

sub _check_user_login_trial_metadata {
    my $c = shift;
    my $check_priv = shift;
    my $user_access = shift;

    my $trial = $c->stash->{trial};
    my $original_private_company_id = $trial->private_company_id();

    my $login_check_return = CXGN::Login::_check_user_login($c, $check_priv, $original_private_company_id, $user_access);
    if ($login_check_return->{error}) {
        $c->stash->{rest} = $login_check_return;
        $c->detach();
    }
    my ($user_id, $user_name, $user_role) = @{$login_check_return->{info}};

    return ($user_id, $user_name, $user_role);
}

1;
