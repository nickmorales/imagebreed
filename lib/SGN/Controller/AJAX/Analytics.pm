package SGN::Controller::AJAX::Analytics;

use Moose;

use File::Slurp;
use Data::Dumper;
use URI::FromHash 'uri';
use JSON;
use CXGN::BreederSearch;
use CXGN::Phenotypes::SearchFactory;
use Text::CSV;
use Statistics::Descriptive::Full;
use Scalar::Util qw(looks_like_number);
use CXGN::Pedigree::ARM;
use CXGN::Genotype::GRM;
use File::Temp 'tempfile';
use Math::Round qw | :all |;
use List::Util qw/sum/;
use Statistics::Descriptive;

BEGIN { extends 'Catalyst::Controller::REST' };

__PACKAGE__->config(
    default => 'application/json',
    stash_key => 'rest',
    map => { 'application/json' => 'JSON', 'text/html' => 'JSON'  },
);

sub list_analytics_protocols_by_user_table :Path('/ajax/analytics_protocols/by_user') Args(0) {
    my $self = shift;
    my $c = shift;

    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my $protocol_type = $c->req->param('analytics_protocol_type');
    my ($user_id, $user_name, $user_role) = _check_user_login_analytics($c, 0, 0, 0);

    my $protocol_type_where = '';
    if ($protocol_type) {
        my $protocol_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, $protocol_type, 'protocol_type')->cvterm_id();
        $protocol_type_where = "nd_protocol.type_id = $protocol_type_cvterm_id AND ";
    }

    my $protocolprop_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analytics_protocol_properties', 'protocol_property')->cvterm_id();

    my %available_types = (
        SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_imagery_analytics_env_simulation_protocol', 'protocol_type')->cvterm_id() => 'Drone Imagery Environment Simulation'
    );

    my $q = "SELECT nd_protocol.nd_protocol_id, nd_protocol.name, nd_protocol.type_id, nd_protocol.description, nd_protocol.create_date, nd_protocolprop.value
        FROM nd_protocol
        JOIN nd_protocolprop USING(nd_protocol_id)
        WHERE $protocol_type_where nd_protocolprop.type_id=$protocolprop_type_cvterm_id;";
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute();

    my @table;
    while (my ($nd_protocol_id, $name, $type_id, $description, $create_date, $props_json) = $h->fetchrow_array()) {
        push @table, [
            '<a href="/analytics_protocols/'.$nd_protocol_id.'">'.$name."</a>",
            $description,
            $available_types{$type_id},
            $create_date
        ];
    }
    $h = undef;

    #print STDERR Dumper(\@table);
    $c->stash->{rest} = { data => \@table };
}

sub list_analytics_protocols_result_files :Path('/ajax/analytics_protocols/result_files') Args(0) {
    my $self = shift;
    my $c = shift;

    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my $analytics_protocol_id = $c->req->param('analytics_protocol_id');
    my ($user_id, $user_name, $user_role) = _check_user_login_analytics($c, 0, 0, 0);

    if (!$analytics_protocol_id) {
        $c->stash->{rest} = { error => "No ID given!" };
        $c->detach();
    }

    my $analytics_experiment_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analytics_protocol_experiment', 'experiment_type')->cvterm_id();

    my $q = "SELECT nd_protocol.nd_protocol_id, nd_protocol.name, nd_protocol.description, basename, dirname, md.file_id, md.filetype, nd_protocol.type_id, nd_experiment.type_id
        FROM metadata.md_files AS md
        JOIN metadata.md_metadata AS meta ON (md.metadata_id=meta.metadata_id)
        JOIN phenome.nd_experiment_md_files using(file_id)
        JOIN nd_experiment using(nd_experiment_id)
        JOIN nd_experiment_protocol using(nd_experiment_id)
        JOIN nd_protocol using(nd_protocol_id)
        WHERE nd_protocol.nd_protocol_id=$analytics_protocol_id AND nd_experiment.type_id=$analytics_experiment_type_cvterm_id;";
    print STDERR $q."\n";
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute();
    my @table;
    while (my ($model_id, $model_name, $model_description, $basename, $filename, $file_id, $filetype, $model_type_id, $experiment_type_id, $property_type_id, $property_value) = $h->fetchrow_array()) {
        # $result{$model_id}->{model_id} = $model_id;
        # $result{$model_id}->{model_name} = $model_name;
        # $result{$model_id}->{model_description} = $model_description;
        # $result{$model_id}->{model_type_id} = $model_type_id;
        # $result{$model_id}->{model_type_name} = $schema->resultset("Cv::Cvterm")->find({cvterm_id => $model_type_id })->name();
        # $result{$model_id}->{model_experiment_type_id} = $experiment_type_id;
        # $result{$model_id}->{model_files}->{$filetype} = $filename."/".$basename;
        # $result{$model_id}->{model_file_ids}->{$file_id} = $basename;
        push @table, [$basename, $filetype, "<a href='/breeders/phenotyping/download/$file_id'>Download</a>"];
    }
    $h = undef;

    $c->stash->{rest} = { data => \@table };
}

sub analytics_protocols_merge_results :Path('/ajax/analytics_protocols_merge_results') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my @protocol_ids = split ',', $c->req->param('protocol_ids');
    my $analysis_type = $c->req->param('analysis_type');
    my ($user_id, $user_name, $user_role) = _check_user_login_analytics($c, 'curator', 0, 0);

    my $protocolprop_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analytics_protocol_properties', 'protocol_property')->cvterm_id();
    my $protocolprop_results_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analytics_protocol_result_summary', 'protocol_property')->cvterm_id();

    my @env_corr_results_array = (["id", "Time", "Models", "Accuracy", "Simulation", "SimulationVariance", "FixedEffect", "Parameters"]);

    my $q = "SELECT value FROM nd_protocolprop WHERE type_id=$protocolprop_results_type_cvterm_id AND nd_protocol_id = ?;";
    my $h = $schema->storage->dbh()->prepare($q);


    my $result_props_json_array_total_counter = 1;
    my $result_props_json_array_counter = 1;
    my %seen_unique_model_names;
    foreach my $analytics_protocol_id (@protocol_ids) {
        $h->execute($analytics_protocol_id);
        my ($result_props_json) = $h->fetchrow_array();

        my $result_props_json_array = $result_props_json ? decode_json $result_props_json : [];
        # print STDERR Dumper $result_props_json_array;

        foreach my $a (@$result_props_json_array) {
            my $analytics_result_type = $a->{statistics_select_original};

            my $env_correlation_results = $a->{env_correlation_results};
            foreach my $env_type (sort keys %$env_correlation_results) {
                my $values = $env_correlation_results->{$env_type}->{values};
                my $mean = $env_correlation_results->{$env_type}->{mean};
                my $std = $env_correlation_results->{$env_type}->{std};

                my $parameter = '';
                my $sim_var = '';
                if (index($env_type, '0.1') != -1) {
                    $parameter = "Simulation Variance = 0.1";
                    $sim_var = 0.1;
                }
                elsif (index($env_type, '0.2') != -1) {
                    $parameter = "Simulation Variance = 0.2";
                    $sim_var = 0.2;
                }
                elsif (index($env_type, '0.3') != -1) {
                    $parameter = "Simulation Variance = 0.3";
                    $sim_var = 0.3;
                }

                my $time_change = 'Constant';
                if (index($env_type, 'changing_gradual') != -1) {
                    if (index($env_type, '0.75') != -1) {
                        $time_change = "Correlated 0.75";
                    }
                    elsif (index($env_type, '0.9') != -1) {
                        $time_change = "Correlated 0.9";
                    }
                }

                my $sim_name = '';
                if (index($env_type, 'linear') != -1) {
                    $sim_name = "Linear";
                }
                elsif (index($env_type, '1DN') != -1) {
                    $sim_name = "1D-N";
                }
                elsif (index($env_type, '2DN') != -1) {
                    $sim_name = "2D-N";
                }
                elsif (index($env_type, 'ar1xar1') != -1) {
                    $sim_name = "AR1xAR1";
                }
                elsif (index($env_type, 'random') != -1) {
                    $sim_name = "Random";
                }
                elsif (index($env_type, 'realdata') != -1) {
                    $sim_name = "Trait";
                }

                my $model_name = '';
                if (index($env_type, 'airemlf90_') != -1) {
                    if (index($env_type, 'identity') != -1) {
                        $model_name = "RR_IDPE";
                    }
                    elsif (index($env_type, 'euclidean_rows_and_columns') != -1) {
                        $model_name = "RR_EucPE";
                    }
                    elsif (index($env_type, 'phenotype_2dspline_effect') != -1) {
                        $model_name = "RR_2DsplTraitPE";
                    }
                    elsif (index($env_type, 'phenotype_ar1xar1_effect') != -1) {
                        $model_name = "RR_AR1xAR1TraitPE";
                    }
                    elsif (index($env_type, 'phenotype_correlation') != -1) {
                        $model_name = "RR_CorrTraitPE";
                    }
                }
                elsif ($analytics_result_type eq 'sommer_grm_spatial_pure_2dspl_genetic_blups') {
                    $model_name = '2Dspl_Multi';
                }
                elsif ($analytics_result_type eq 'sommer_grm_univariate_spatial_pure_2dspl_genetic_blups') {
                    $model_name = '2Dspl_Uni';
                }
                elsif ($analytics_result_type eq 'asreml_grm_multivariate_spatial_genetic_blups') {
                    $model_name = 'AR1_Multi';
                }
                elsif ($analytics_result_type eq 'asreml_grm_univariate_pure_spatial_genetic_blups') {
                    $model_name = 'AR1_Uni';
                }
                # $model_name .= "_$result_props_json_array_counter";
                $seen_unique_model_names{$model_name}++;

                my $fixed_effect = 'Replicate';

                foreach my $v (@$values) {
                    push @env_corr_results_array, [$result_props_json_array_total_counter, $time_change, $model_name, $v, $sim_name, $sim_var, $fixed_effect, $parameter];
                    $result_props_json_array_total_counter++
                }
            }

            $result_props_json_array_counter++;
        }
    }
    $h = undef;

    my @analytics_protocol_charts;
    if (scalar(@env_corr_results_array) > 1) {
        my $dir = $c->tempfiles_subdir('/analytics_protocol_figure');
        my $analytics_protocol_tempfile_string = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string .= '.png';
        my $analytics_protocol_figure_tempfile = $c->config->{basepath}."/".$analytics_protocol_tempfile_string;
        my $analytics_protocol_data_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

        open(my $F, ">", $analytics_protocol_data_tempfile) || die "Can't open file ".$analytics_protocol_data_tempfile;
            foreach (@env_corr_results_array) {
                my $string = join ',', @$_;
                print $F "$string\n";
            }
        close($F);

        my @model_names = keys %seen_unique_model_names;
        my $model_names_string = join '\',\'', @model_names;

        my $r_cmd = 'R -e "library(ggplot2); library(data.table);
        data <- data.frame(fread(\''.$analytics_protocol_data_tempfile.'\', header=TRUE, sep=\',\'));
        data\$Models <- factor(data\$Models, levels = c(\''.$model_names_string.'\'));
        data\$Time <- factor(data\$Time, levels = c(\'Constant\', \'Correlated 0.9\', \'Correlated 0.75\'));
        data\$Simulation <- factor(data\$Simulation, levels = c(\'Linear\', \'1D-N\', \'2D-N\', \'AR1xAR1\', \'Trait\', \'Random\'));
        data\$Parameters <- factor(data\$Parameters, levels = c(\'Simulation Variance = 0.2\', \'Simulation Variance = 0.1\', \'Simulation Variance = 0.3\'));
        p <- ggplot(data, aes(x=Models, y=Accuracy, fill=Time)) + geom_boxplot(position=position_dodge(1), outlier.shape = NA) +theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust=1));
        p <- p + coord_cartesian(ylim=c(0,1));
        p <- p + facet_grid(Simulation~Parameters, scales=\'free\', space=\'free_x\');
        p <- p + ggtitle(\'Environment Simulation Prediction Accuracy\');
        ggsave(\''.$analytics_protocol_figure_tempfile.'\', p, device=\'png\', width=10, height=12, limitsize = FALSE, units=\'in\');
        "';
        print STDERR Dumper $r_cmd;
        my $status = system($r_cmd);

        push @analytics_protocol_charts, $analytics_protocol_tempfile_string;
    }

    $c->stash->{rest} = { charts => \@analytics_protocol_charts };
}

sub analytics_protocols_compare_to_trait_test_ar1_models :Path('/ajax/analytics_protocols_compare_to_trait_test_ar1_models') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    print STDERR Dumper $c->req->params();
    my $protocol_id = $c->req->param('protocol_id');
    my $trait_id = $c->req->param('trait_id');
    my $trial_id = $c->req->param('trial_id');
    my $default_tol = $c->req->param('default_tol');
    my ($user_id, $user_name, $user_role) = _check_user_login_analytics($c, 'submitter', 0, 0);

    my $csv = Text::CSV->new({ sep_char => "," });
    my $dir = $c->tempfiles_subdir('/analytics_protocol_figure');

    my $protocolprop_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analytics_protocol_properties', 'protocol_property')->cvterm_id();
    my $protocolprop_results_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analytics_protocol_result_summary', 'protocol_property')->cvterm_id();
    my $analytics_experiment_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analytics_protocol_experiment', 'experiment_type')->cvterm_id();

    my $q0 = "SELECT nd_protocol.nd_protocol_id, nd_protocol.name, nd_protocol.type_id, nd_protocol.description, nd_protocol.create_date, properties.value, results.value
        FROM nd_protocol
        JOIN nd_protocolprop AS properties ON(properties.nd_protocol_id=nd_protocol.nd_protocol_id AND properties.type_id=$protocolprop_type_cvterm_id)
        JOIN nd_protocolprop AS results ON(results.nd_protocol_id=nd_protocol.nd_protocol_id AND results.type_id=$protocolprop_results_type_cvterm_id)
        WHERE nd_protocol.nd_protocol_id = ?;";
    my $h0 = $schema->storage->dbh()->prepare($q0);
    $h0->execute($protocol_id);
    my ($nd_protocol_id, $name, $type_id, $description, $create_date, $props_json, $result_props_json) = $h0->fetchrow_array();
    $h0 = undef;

    if (!$name) {
        $c->stash->{rest} = { error => "There is no protocol with that ID!"};
        return;
    }

    my $protocol_properties = decode_json $props_json;
    my $observation_variable_id_list = $protocol_properties->{observation_variable_id_list};
    my $observation_variable_number = scalar(@$observation_variable_id_list);
    my $legendre_poly_number = $protocol_properties->{legendre_order_number} || 3;
    my $analytics_select = $protocol_properties->{analytics_select};
    my $compute_relationship_matrix_from_htp_phenotypes = $protocol_properties->{relationship_matrix_type};
    my $compute_relationship_matrix_from_htp_phenotypes_type = $protocol_properties->{htp_pheno_rel_matrix_type};
    my $compute_relationship_matrix_from_htp_phenotypes_time_points = $protocol_properties->{htp_pheno_rel_matrix_time_points};
    my $compute_relationship_matrix_from_htp_phenotypes_blues_inversion = $protocol_properties->{htp_pheno_rel_matrix_blues_inversion};
    my $compute_from_parents = $protocol_properties->{genotype_compute_from_parents};
    my $include_pedgiree_info_if_compute_from_parents = $protocol_properties->{include_pedgiree_info_if_compute_from_parents};
    my $use_parental_grms_if_compute_from_parents = $protocol_properties->{use_parental_grms_if_compute_from_parents};
    my $use_area_under_curve = $protocol_properties->{use_area_under_curve};
    my $genotyping_protocol_id = $protocol_properties->{genotyping_protocol_id};
    my $tolparinv = $protocol_properties->{tolparinv};
    my $permanent_environment_structure = $protocol_properties->{permanent_environment_structure};
    my $permanent_environment_structure_phenotype_correlation_traits = $protocol_properties->{permanent_environment_structure_phenotype_correlation_traits};
    my $permanent_environment_structure_phenotype_trait_ids = $protocol_properties->{permanent_environment_structure_phenotype_trait_ids};
    my @env_variance_percents = split ',', $protocol_properties->{env_variance_percent};
    my $number_iterations = $protocol_properties->{number_iterations};
    my $simulated_environment_real_data_trait_id = $protocol_properties->{simulated_environment_real_data_trait_id};
    my $correlation_between_times = $protocol_properties->{sim_env_change_over_time_correlation} || 0.9;
    my $fixed_effect_type = $protocol_properties->{fixed_effect_type} || 'replicate';
    my $fixed_effect_trait_id = $protocol_properties->{fixed_effect_trait_id};
    my $fixed_effect_quantiles = $protocol_properties->{fixed_effect_quantiles};
    my $env_iterations = $protocol_properties->{env_iterations};
    my $perform_cv = $protocol_properties->{perform_cv} || 0;
    my $tolparinv_10 = $tolparinv*10;

    my $field_trial_id_list = [$trial_id];
    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$schema,
            data_level=>'plot',
            trait_list=>[$trait_id],
            trial_list=>$field_trial_id_list,
            include_timestamp=>0,
            exclude_phenotype_outlier=>0
        }
    );
    my ($data, $unique_traits) = $phenotypes_search->search();
    my @sorted_trait_names = sort keys %$unique_traits;

    if (scalar(@$data) == 0) {
        $c->stash->{rest} = { error => "There are no phenotypes for the trials and trait you have selected!"};
        return;
    }

    my %germplasm_phenotypes;
    my %plot_phenotypes;
    my $min_phenotype = 1000000000000000;
    my $max_phenotype = -1000000000000000;
    foreach my $obs_unit (@$data){
        my $germplasm_name = $obs_unit->{germplasm_uniquename};
        my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
        my $replicate_number = $obs_unit->{obsunit_rep} || '';
        my $block_number = $obs_unit->{obsunit_block} || '';
        my $obsunit_stock_id = $obs_unit->{observationunit_stock_id};
        my $obsunit_stock_uniquename = $obs_unit->{observationunit_uniquename};
        my $row_number = $obs_unit->{obsunit_row_number} || '';
        my $col_number = $obs_unit->{obsunit_col_number} || '';

        my $observations = $obs_unit->{observations};
        foreach (@$observations){
            my $value = $_->{value};
            my $trait_name = $_->{trait_name};

            if ($value < $min_phenotype) {
                $min_phenotype = $value;
            }
            if ($value > $max_phenotype) {
                $max_phenotype = $value;
            }

            push @{$germplasm_phenotypes{$germplasm_name}->{$trait_name}}, $value;
            $plot_phenotypes{$obsunit_stock_uniquename}->{$trait_name} = $value;
        }
    }

    my $phenotypes_search_htp = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$schema,
            data_level=>'plot',
            trait_list=>$observation_variable_id_list,
            trial_list=>$field_trial_id_list,
            include_timestamp=>0,
            exclude_phenotype_outlier=>0
        }
    );
    my ($data_htp, $unique_traits_htp) = $phenotypes_search_htp->search();
    my @sorted_trait_names_htp = sort keys %$unique_traits_htp;

    if (scalar(@$data_htp) == 0) {
        $c->stash->{rest} = { error => "There are no phenotypes for the trials and trait you have selected!"};
        return;
    }

    my %germplasm_phenotypes_htp;
    my %plot_phenotypes_htp;
    my %seen_accession_stock_ids;
    my %seen_accession_stock_names;
    my %seen_days_after_plantings;
    my %stock_name_row_col;
    my %plot_row_col_hash;
    my %stock_info;
    my %plot_id_map;
    my %plot_germplasm_map;
    my $min_col = 100000000000000;
    my $max_col = -100000000000000;
    my $min_row = 100000000000000;
    my $max_row = -100000000000000;
    foreach my $obs_unit (@$data_htp){
        my $germplasm_name = $obs_unit->{germplasm_uniquename};
        my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
        my $replicate_number = $obs_unit->{obsunit_rep} || '';
        my $block_number = $obs_unit->{obsunit_block} || '';
        my $obsunit_stock_id = $obs_unit->{observationunit_stock_id};
        my $obsunit_stock_uniquename = $obs_unit->{observationunit_uniquename};
        my $row_number = $obs_unit->{obsunit_row_number} || '';
        my $col_number = $obs_unit->{obsunit_col_number} || '';

        if ($row_number > $max_row) {
            $max_row = $row_number;
        }
        if ($row_number < $min_row) {
            $min_row = $row_number;
        }
        if ($col_number > $max_col) {
            $max_col = $col_number;
        }
        if ($col_number < $min_col) {
            $min_col = $col_number;
        }

        $seen_accession_stock_ids{$germplasm_stock_id}++;
        $seen_accession_stock_names{$germplasm_name}++;
        $plot_id_map{$obsunit_stock_id} = $obsunit_stock_uniquename;
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
        $plot_germplasm_map{$obsunit_stock_uniquename} = $germplasm_name;

        $stock_info{"S".$germplasm_stock_id} = {
            uniquename => $germplasm_name
        };

        $plot_row_col_hash{$row_number}->{$col_number} = {
            obsunit_stock_id => $obsunit_stock_id,
            obsunit_name => $obsunit_stock_uniquename
        };

        my $observations = $obs_unit->{observations};
        foreach (@$observations){
            my $value = $_->{value};
            my $trait_name = $_->{trait_name};

            push @{$germplasm_phenotypes_htp{$germplasm_name}->{$trait_name}}, $value;
            $plot_phenotypes_htp{$obsunit_stock_uniquename}->{$trait_name} = $value;

            if ($_->{associated_image_project_time_json}) {
                my $related_time_terms_json = decode_json $_->{associated_image_project_time_json};
                my $time_days_cvterm = $related_time_terms_json->{day};
                my $time_term_string = $time_days_cvterm;
                my $time_days = (split '\|', $time_days_cvterm)[0];
                my $time_value = (split ' ', $time_days)[1];
                $seen_days_after_plantings{$time_value}++;
            }
        }
    }

    my @seen_plots = sort keys %plot_phenotypes_htp;
    my @accession_ids = sort keys %seen_accession_stock_ids;
    my @accession_names = sort keys %seen_accession_stock_names;

    my $trait_name_encoded_s = 1;
    my %trait_name_encoder_s;
    my %trait_name_encoder_rev_s;
    foreach my $trait_name (@sorted_trait_names) {
        if (!exists($trait_name_encoder_s{$trait_name})) {
            my $trait_name_e = 't'.$trait_name_encoded_s;
            $trait_name_encoder_s{$trait_name} = $trait_name_e;
            $trait_name_encoder_rev_s{$trait_name_e} = $trait_name;
            $trait_name_encoded_s++;
        }
    }

    # Prepare phenotype file for Trait Spatial Correction
    my $stats_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_factors = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $grm_rename_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
    my $stats_out_tempfile_ar1_indata = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_2dspl = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_residual = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

    my @data_matrix_original;
    foreach my $p (@seen_plots) {
        my $obsunit_stock_id = $stock_name_row_col{$p}->{obsunit_stock_id};
        my $row_number = $stock_name_row_col{$p}->{row_number};
        my $col_number = $stock_name_row_col{$p}->{col_number};
        my $replicate = $stock_name_row_col{$p}->{rep};
        my $block = $stock_name_row_col{$p}->{block};
        my $germplasm_stock_id = $stock_name_row_col{$p}->{germplasm_stock_id};
        my $germplasm_name = $stock_name_row_col{$p}->{germplasm_name};

        my @row = ($replicate, $block, "S".$germplasm_stock_id, $obsunit_stock_id, $row_number, $col_number, $row_number, $col_number, '', '');

        foreach my $t (@sorted_trait_names) {
            if (defined($plot_phenotypes{$p}->{$t})) {
                push @row, $plot_phenotypes{$p}->{$t};
            } else {
                print STDERR $p." : $t : $germplasm_name : NA \n";
                push @row, 'NA';
            }
        }
        push @data_matrix_original, \@row;
    }

    my @phenotype_header = ("replicate", "block", "id", "plot_id", "rowNumber", "colNumber", "rowNumberFactor", "colNumberFactor", "accession_id_factor", "plot_id_factor");
    foreach (@sorted_trait_names) {
        push @phenotype_header, $trait_name_encoder_s{$_};
    }
    my $header_string = join ',', @phenotype_header;

    open(my $Fs, ">", $stats_tempfile) || die "Can't open file ".$stats_tempfile;
        print $Fs $header_string."\n";
        foreach (@data_matrix_original) {
            my $line = join ',', @$_;
            print $Fs "$line\n";
        }
    close($Fs);

    my $trait_name_string = join ',', @sorted_trait_names;
    my $trait_name_encoded_string = $trait_name_encoder_s{$trait_name_string};

    my $grm_file_ar1;
    # Prepare GRM for AR1 Trait Spatial Correction
    eval {
        print STDERR Dumper [$compute_relationship_matrix_from_htp_phenotypes, $include_pedgiree_info_if_compute_from_parents, $use_parental_grms_if_compute_from_parents, $compute_from_parents];
        if ($compute_relationship_matrix_from_htp_phenotypes eq 'genotypes') {

            if ($include_pedgiree_info_if_compute_from_parents) {
                my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
                my $tmp_arm_dir = $shared_cluster_dir_config."/tmp_download_arm";
                mkdir $tmp_arm_dir if ! -d $tmp_arm_dir;
                my ($arm_tempfile_fh, $arm_tempfile) = tempfile("drone_stats_download_arm_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm1_tempfile_fh, $grm1_tempfile) = tempfile("drone_stats_download_grm1_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_temp_tempfile_fh, $grm_out_temp_tempfile) = tempfile("drone_stats_download_grm_temp_out_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_posdef_tempfile_fh, $grm_out_posdef_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);

                if (!$genotyping_protocol_id) {
                    $genotyping_protocol_id = undef;
                }

                my $pedigree_arm = CXGN::Pedigree::ARM->new({
                    bcs_schema=>$schema,
                    arm_temp_file=>$arm_tempfile,
                    people_schema=>$people_schema,
                    accession_id_list=>\@accession_ids,
                    # plot_id_list=>\@plot_id_list,
                    cache_root=>$c->config->{cache_file_path},
                    download_format=>'matrix', #either 'matrix', 'three_column', or 'heatmap'
                });
                my ($parent_hash, $stock_ids, $all_accession_stock_ids, $female_stock_ids, $male_stock_ids) = $pedigree_arm->get_arm(
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                # print STDERR Dumper $parent_hash;

                my $female_geno = CXGN::Genotype::GRM->new({
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm1_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>$female_stock_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>0,
                    download_format=>'three_column_reciprocal',
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                });
                my $female_grm_data = $female_geno->download_grm(
                    'data',
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                my @fl = split '\n', $female_grm_data;
                my %female_parent_grm;
                foreach (@fl) {
                    my @l = split '\t', $_;
                    $female_parent_grm{$l[0]}->{$l[1]} = $l[2];
                }
                # print STDERR Dumper \%female_parent_grm;

                my $male_geno = CXGN::Genotype::GRM->new({
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm1_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>$male_stock_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>0,
                    download_format=>'three_column_reciprocal',
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                });
                my $male_grm_data = $male_geno->download_grm(
                    'data',
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                my @ml = split '\n', $male_grm_data;
                my %male_parent_grm;
                foreach (@ml) {
                    my @l = split '\t', $_;
                    $male_parent_grm{$l[0]}->{$l[1]} = $l[2];
                }
                # print STDERR Dumper \%male_parent_grm;

                my %rel_result_hash;
                foreach my $a1 (@accession_ids) {
                    foreach my $a2 (@accession_ids) {
                        my $female_parent1 = $parent_hash->{$a1}->{female_stock_id};
                        my $male_parent1 = $parent_hash->{$a1}->{male_stock_id};
                        my $female_parent2 = $parent_hash->{$a2}->{female_stock_id};
                        my $male_parent2 = $parent_hash->{$a2}->{male_stock_id};

                        my $female_rel = 0;
                        if ($female_parent1 && $female_parent2 && $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2}) {
                            $female_rel = $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2};
                        }
                        elsif ($female_parent1 && $female_parent2 && $female_parent1 == $female_parent2) {
                            $female_rel = 1;
                        }
                        elsif ($a1 == $a2) {
                            $female_rel = 1;
                        }

                        my $male_rel = 0;
                        if ($male_parent1 && $male_parent2 && $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2}) {
                            $male_rel = $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2};
                        }
                        elsif ($male_parent1 && $male_parent2 && $male_parent1 == $male_parent2) {
                            $male_rel = 1;
                        }
                        elsif ($a1 == $a2) {
                            $male_rel = 1;
                        }
                        # print STDERR "$a1 $a2 $female_rel $male_rel\n";

                        my $rel = 0.5*($female_rel + $male_rel);
                        $rel_result_hash{$a1}->{$a2} = $rel;
                    }
                }
                # print STDERR Dumper \%rel_result_hash;

                my $data = '';
                my %result_hash;
                foreach my $s (sort @accession_ids) {
                    foreach my $c (sort @accession_ids) {
                        if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                            my $val = $rel_result_hash{$s}->{$c};
                            if (defined $val and length $val) {
                                $result_hash{$s}->{$c} = $val;
                                $data .= "S$s\tS$c\t$val\n";
                            }
                        }
                    }
                }

                # print STDERR Dumper $data;
                open(my $F2, ">", $grm_out_temp_tempfile) || die "Can't open file ".$grm_out_temp_tempfile;
                    print $F2 $data;
                close($F2);

                my $cmd = 'R -e "library(data.table); library(scales); library(tidyr); library(reshape2);
                three_col <- fread(\''.$grm_out_temp_tempfile.'\', header=FALSE, sep=\'\t\');
                A_wide <- dcast(three_col, V1~V2, value.var=\'V3\');
                A_1 <- A_wide[,-1];
                A_1[is.na(A_1)] <- 0;
                A <- A_1 + t(A_1);
                diag(A) <- diag(as.matrix(A_1));
                E = eigen(A);
                ev = E\$values;
                U = E\$vectors;
                no = dim(A)[1];
                nev = which(ev < 0);
                wr = 0;
                k=length(nev);
                if(k > 0){
                    p = ev[no - k];
                    B = sum(ev[nev])*2.0;
                    wr = (B*B*100.0)+1;
                    val = ev[nev];
                    ev[nev] = p*(B-val)*(B-val)/wr;
                    A = U%*%diag(ev)%*%t(U);
                }
                A <- as.data.frame(A);
                colnames(A) <- A_wide[,1];
                A\$stock_id <- A_wide[,1];
                A_threecol <- melt(A, id.vars = c(\'stock_id\'), measure.vars = A_wide[,1]);
                A_threecol\$stock_id <- substring(A_threecol\$stock_id, 2);
                A_threecol\$variable <- substring(A_threecol\$variable, 2);
                write.table(data.frame(variable = A_threecol\$variable, stock_id = A_threecol\$stock_id, value = A_threecol\$value), file=\''.$grm_out_tempfile.'\', row.names=FALSE, col.names=FALSE, sep=\'\t\');"';
                print STDERR $cmd."\n";
                my $status = system($cmd);

                my %rel_pos_def_result_hash;
                open(my $F3, '<', $grm_out_tempfile)
                    or die "Could not open file '$grm_out_tempfile' $!";

                    print STDERR "Opened $grm_out_tempfile\n";

                    while (my $row = <$F3>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        my $stock_id1 = $columns[0];
                        my $stock_id2 = $columns[1];
                        my $val = $columns[2];
                        $rel_pos_def_result_hash{$stock_id1}->{$stock_id2} = $val;
                    }
                close($F3);

                my $data_pos_def = '';
                %result_hash = ();
                foreach my $s (sort @accession_ids) {
                    foreach my $c (sort @accession_ids) {
                        if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                            my $val = $rel_pos_def_result_hash{$s}->{$c};
                            if (defined $val and length $val) {
                                $result_hash{$s}->{$c} = $val;
                                $data_pos_def .= "$s\t$c\t$val\n";
                            }
                        }
                    }
                }

                open(my $F4, ">", $grm_out_posdef_tempfile) || die "Can't open file ".$grm_out_posdef_tempfile;
                    print $F4 $data_pos_def;
                close($F4);

                $grm_file_ar1 = $grm_out_posdef_tempfile;
            }
            elsif ($use_parental_grms_if_compute_from_parents) {
                my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
                my $tmp_arm_dir = $shared_cluster_dir_config."/tmp_download_arm";
                mkdir $tmp_arm_dir if ! -d $tmp_arm_dir;
                my ($arm_tempfile_fh, $arm_tempfile) = tempfile("drone_stats_download_arm_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm1_tempfile_fh, $grm1_tempfile) = tempfile("drone_stats_download_grm1_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_temp_tempfile_fh, $grm_out_temp_tempfile) = tempfile("drone_stats_download_grm_temp_out_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_posdef_tempfile_fh, $grm_out_posdef_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);

                if (!$genotyping_protocol_id) {
                    $genotyping_protocol_id = undef;
                }

                my $pedigree_arm = CXGN::Pedigree::ARM->new({
                    bcs_schema=>$schema,
                    arm_temp_file=>$arm_tempfile,
                    people_schema=>$people_schema,
                    accession_id_list=>\@accession_ids,
                    # plot_id_list=>\@plot_id_list,
                    cache_root=>$c->config->{cache_file_path},
                    download_format=>'matrix', #either 'matrix', 'three_column', or 'heatmap'
                });
                my ($parent_hash, $stock_ids, $all_accession_stock_ids, $female_stock_ids, $male_stock_ids) = $pedigree_arm->get_arm(
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                # print STDERR Dumper $parent_hash;

                my $female_geno = CXGN::Genotype::GRM->new({
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm1_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>$female_stock_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>0,
                    download_format=>'three_column_reciprocal',
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                });
                my $female_grm_data = $female_geno->download_grm(
                    'data',
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                my @fl = split '\n', $female_grm_data;
                my %female_parent_grm;
                foreach (@fl) {
                    my @l = split '\t', $_;
                    $female_parent_grm{$l[0]}->{$l[1]} = $l[2];
                }
                # print STDERR Dumper \%female_parent_grm;

                my $male_geno = CXGN::Genotype::GRM->new({
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm1_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>$male_stock_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>0,
                    download_format=>'three_column_reciprocal',
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                });
                my $male_grm_data = $male_geno->download_grm(
                    'data',
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                my @ml = split '\n', $male_grm_data;
                my %male_parent_grm;
                foreach (@ml) {
                    my @l = split '\t', $_;
                    $male_parent_grm{$l[0]}->{$l[1]} = $l[2];
                }
                # print STDERR Dumper \%male_parent_grm;

                my %rel_result_hash;
                foreach my $a1 (@accession_ids) {
                    foreach my $a2 (@accession_ids) {
                        my $female_parent1 = $parent_hash->{$a1}->{female_stock_id};
                        my $male_parent1 = $parent_hash->{$a1}->{male_stock_id};
                        my $female_parent2 = $parent_hash->{$a2}->{female_stock_id};
                        my $male_parent2 = $parent_hash->{$a2}->{male_stock_id};

                        my $female_rel = 0;
                        if ($female_parent1 && $female_parent2 && $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2}) {
                            $female_rel = $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2};
                        }
                        elsif ($a1 == $a2) {
                            $female_rel = 1;
                        }

                        my $male_rel = 0;
                        if ($male_parent1 && $male_parent2 && $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2}) {
                            $male_rel = $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2};
                        }
                        elsif ($a1 == $a2) {
                            $male_rel = 1;
                        }
                        # print STDERR "$a1 $a2 $female_rel $male_rel\n";

                        my $rel = 0.5*($female_rel + $male_rel);
                        $rel_result_hash{$a1}->{$a2} = $rel;
                    }
                }
                # print STDERR Dumper \%rel_result_hash;

                my $data = '';
                my %result_hash;
                foreach my $s (sort @accession_ids) {
                    foreach my $c (sort @accession_ids) {
                        if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                            my $val = $rel_result_hash{$s}->{$c};
                            if (defined $val and length $val) {
                                $result_hash{$s}->{$c} = $val;
                                $data .= "S$s\tS$c\t$val\n";
                            }
                        }
                    }
                }

                # print STDERR Dumper $data;
                open(my $F2, ">", $grm_out_temp_tempfile) || die "Can't open file ".$grm_out_temp_tempfile;
                    print $F2 $data;
                close($F2);

                my $cmd = 'R -e "library(data.table); library(scales); library(tidyr); library(reshape2);
                three_col <- fread(\''.$grm_out_temp_tempfile.'\', header=FALSE, sep=\'\t\');
                A_wide <- dcast(three_col, V1~V2, value.var=\'V3\');
                A_1 <- A_wide[,-1];
                A_1[is.na(A_1)] <- 0;
                A <- A_1 + t(A_1);
                diag(A) <- diag(as.matrix(A_1));
                E = eigen(A);
                ev = E\$values;
                U = E\$vectors;
                no = dim(A)[1];
                nev = which(ev < 0);
                wr = 0;
                k=length(nev);
                if(k > 0){
                    p = ev[no - k];
                    B = sum(ev[nev])*2.0;
                    wr = (B*B*100.0)+1;
                    val = ev[nev];
                    ev[nev] = p*(B-val)*(B-val)/wr;
                    A = U%*%diag(ev)%*%t(U);
                }
                A <- as.data.frame(A);
                colnames(A) <- A_wide[,1];
                A\$stock_id <- A_wide[,1];
                A_threecol <- melt(A, id.vars = c(\'stock_id\'), measure.vars = A_wide[,1]);
                A_threecol\$stock_id <- substring(A_threecol\$stock_id, 2);
                A_threecol\$variable <- substring(A_threecol\$variable, 2);
                write.table(data.frame(variable = A_threecol\$variable, stock_id = A_threecol\$stock_id, value = A_threecol\$value), file=\''.$grm_out_tempfile.'\', row.names=FALSE, col.names=FALSE, sep=\'\t\');"';
                print STDERR $cmd."\n";
                my $status = system($cmd);

                my %rel_pos_def_result_hash;
                open(my $F3, '<', $grm_out_tempfile) or die "Could not open file '$grm_out_tempfile' $!";
                    print STDERR "Opened $grm_out_tempfile\n";

                    while (my $row = <$F3>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        my $stock_id1 = $columns[0];
                        my $stock_id2 = $columns[1];
                        my $val = $columns[2];
                        $rel_pos_def_result_hash{$stock_id1}->{$stock_id2} = $val;
                    }
                close($F3);

                my $data_pos_def = '';
                %result_hash = ();
                foreach my $s (sort @accession_ids) {
                    foreach my $c (sort @accession_ids) {
                        if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                            my $val = $rel_pos_def_result_hash{$s}->{$c};
                            if (defined $val and length $val) {
                                $result_hash{$s}->{$c} = $val;
                                $data_pos_def .= "$s\t$c\t$val\n";
                            }
                        }
                    }
                }

                open(my $F4, ">", $grm_out_posdef_tempfile) || die "Can't open file ".$grm_out_posdef_tempfile;
                    print $F4 $data_pos_def;
                close($F4);

                $grm_file_ar1 = $grm_out_posdef_tempfile;
            }
            else {
                my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
                my $tmp_grm_dir = $shared_cluster_dir_config."/tmp_genotype_download_grm";
                mkdir $tmp_grm_dir if ! -d $tmp_grm_dir;
                my ($grm_tempfile_fh, $grm_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
                my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);

                if (!$genotyping_protocol_id) {
                    $genotyping_protocol_id = undef;
                }

                my $grm_search_params = {
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>\@accession_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>$compute_from_parents,
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                };
                $grm_search_params->{download_format} = 'three_column_stock_id_integer';

                my $geno = CXGN::Genotype::GRM->new($grm_search_params);
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
                $grm_file_ar1 = $grm_out_tempfile;
            }

        }
        elsif ($compute_relationship_matrix_from_htp_phenotypes eq 'htp_phenotypes') {
            my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
            my $tmp_grm_dir = $shared_cluster_dir_config."/tmp_genotype_download_grm";
            mkdir $tmp_grm_dir if ! -d $tmp_grm_dir;
            my ($stats_out_htp_rel_tempfile_input_fh, $stats_out_htp_rel_tempfile_input) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
            my ($stats_out_htp_rel_tempfile_fh, $stats_out_htp_rel_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
            my ($stats_out_htp_rel_tempfile_out_fh, $stats_out_htp_rel_tempfile_out) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);

            my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
                'MaterializedViewTable',
                {
                    bcs_schema=>$schema,
                    data_level=>'plot',
                    trial_list=>$field_trial_id_list,
                    include_timestamp=>0,
                    exclude_phenotype_outlier=>0
                }
            );
            my ($data, $unique_traits) = $phenotypes_search->search();

            if (scalar(@$data) == 0) {
                $c->stash->{rest} = { error => "There are no phenotypes for the trial you have selected!"};
                return;
            }

            my $q_time = "SELECT t.cvterm_id FROM cvterm as t JOIN cv ON(t.cv_id=cv.cv_id) WHERE t.name=? and cv.name=?;";
            my $h_time = $schema->storage->dbh()->prepare($q_time);

            my %seen_plot_names_htp_rel;
            my %phenotype_data_htp_rel;
            my %seen_times_htp_rel;
            foreach my $obs_unit (@$data){
                my $germplasm_name = $obs_unit->{germplasm_uniquename};
                my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
                my $row_number = $obs_unit->{obsunit_row_number} || '';
                my $col_number = $obs_unit->{obsunit_col_number} || '';
                my $rep = $obs_unit->{obsunit_rep};
                my $block = $obs_unit->{obsunit_block};
                $seen_plot_names_htp_rel{$obs_unit->{observationunit_uniquename}} = $obs_unit;
                my $observations = $obs_unit->{observations};
                foreach (@$observations){
                    if ($_->{associated_image_project_time_json}) {
                        my $related_time_terms_json = decode_json $_->{associated_image_project_time_json};

                        my $time_days_cvterm = $related_time_terms_json->{day};
                        my $time_days_term_string = $time_days_cvterm;
                        my $time_days = (split '\|', $time_days_cvterm)[0];
                        my $time_days_value = (split ' ', $time_days)[1];

                        my $time_gdd_value = $related_time_terms_json->{gdd_average_temp} + 0;
                        my $gdd_term_string = "GDD $time_gdd_value";
                        $h_time->execute($gdd_term_string, 'cxgn_time_ontology');
                        my ($gdd_cvterm_id) = $h_time->fetchrow_array();
                        if (!$gdd_cvterm_id) {
                            my $new_gdd_term = $schema->resultset("Cv::Cvterm")->create_with({
                               name => $gdd_term_string,
                               cv => 'cxgn_time_ontology'
                            });
                            $gdd_cvterm_id = $new_gdd_term->cvterm_id();
                        }
                        my $time_gdd_term_string = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $gdd_cvterm_id, 'extended');

                        $phenotype_data_htp_rel{$obs_unit->{observationunit_uniquename}}->{$_->{trait_name}} = $_->{value};
                        $seen_times_htp_rel{$_->{trait_name}} = [$time_days_value, $time_days_term_string, $time_gdd_value, $time_gdd_term_string];
                    }
                }
            }
            $h_time = undef;

            my @allowed_standard_htp_values = ('Nonzero Pixel Count', 'Total Pixel Sum', 'Mean Pixel Value', 'Harmonic Mean Pixel Value', 'Median Pixel Value', 'Pixel Variance', 'Pixel Standard Deviation', 'Pixel Population Standard Deviation', 'Minimum Pixel Value', 'Maximum Pixel Value', 'Minority Pixel Value', 'Minority Pixel Count', 'Majority Pixel Value', 'Majority Pixel Count', 'Pixel Group Count');
            my %filtered_seen_times_htp_rel;
            while (my ($t, $time) = each %seen_times_htp_rel) {
                my $allowed = 0;
                foreach (@allowed_standard_htp_values) {
                    if (index($t, $_) != -1) {
                        $allowed = 1;
                        last;
                    }
                }
                if ($allowed) {
                    $filtered_seen_times_htp_rel{$t} = $time;
                }
            }

            my @seen_plot_names_htp_rel_sorted = sort keys %seen_plot_names_htp_rel;
            my @filtered_seen_times_htp_rel_sorted = sort keys %filtered_seen_times_htp_rel;

            my @header_htp = ('plot_id', 'plot_name', 'accession_id', 'accession_name', 'rep', 'block');

            my %trait_name_encoder_htp;
            my %trait_name_encoder_rev_htp;
            my $trait_name_encoded_htp = 1;
            my @header_traits_htp;
            foreach my $trait_name (@filtered_seen_times_htp_rel_sorted) {
                if (!exists($trait_name_encoder_htp{$trait_name})) {
                    my $trait_name_e = 't'.$trait_name_encoded_htp;
                    $trait_name_encoder_htp{$trait_name} = $trait_name_e;
                    $trait_name_encoder_rev_htp{$trait_name_e} = $trait_name;
                    push @header_traits_htp, $trait_name_e;
                    $trait_name_encoded_htp++;
                }
            }

            my @htp_pheno_matrix;
            if ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'all') {
                push @header_htp, @header_traits_htp;
                push @htp_pheno_matrix, \@header_htp;

                foreach my $p (@seen_plot_names_htp_rel_sorted) {
                    my $obj = $seen_plot_names_htp_rel{$p};
                    my @row = ($obj->{observationunit_stock_id}, $obj->{observationunit_uniquename}, $obj->{germplasm_stock_id}, $obj->{germplasm_uniquename}, $obj->{obsunit_rep}, $obj->{obsunit_block});
                    foreach my $t (@filtered_seen_times_htp_rel_sorted) {
                        my $val = $phenotype_data_htp_rel{$p}->{$t} + 0;
                        push @row, $val;
                    }
                    push @htp_pheno_matrix, \@row;
                }
            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'latest_trait') {
                my $max_day = 0;
                foreach (keys %seen_days_after_plantings) {
                    if ($_ + 0 > $max_day) {
                        $max_day = $_;
                    }
                }

                foreach my $t (@filtered_seen_times_htp_rel_sorted) {
                    my $day = $filtered_seen_times_htp_rel{$t}->[0];
                    if ($day <= $max_day) {
                        push @header_htp, $t;
                    }
                }
                push @htp_pheno_matrix, \@header_htp;

                foreach my $p (@seen_plot_names_htp_rel_sorted) {
                    my $obj = $seen_plot_names_htp_rel{$p};
                    my @row = ($obj->{observationunit_stock_id}, $obj->{observationunit_uniquename}, $obj->{germplasm_stock_id}, $obj->{germplasm_uniquename}, $obj->{obsunit_rep}, $obj->{obsunit_block});
                    foreach my $t (@filtered_seen_times_htp_rel_sorted) {
                        my $day = $filtered_seen_times_htp_rel{$t}->[0];
                        if ($day <= $max_day) {
                            my $val = $phenotype_data_htp_rel{$p}->{$t} + 0;
                            push @row, $val;
                        }
                    }
                    push @htp_pheno_matrix, \@row;
                }
            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'vegetative') {

            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'reproductive') {

            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'mature') {

            }
            else {
                $c->stash->{rest} = { error => "The value of $compute_relationship_matrix_from_htp_phenotypes_time_points htp_pheno_rel_matrix_time_points is not valid!" };
                return;
            }

            open(my $htp_pheno_f, ">", $stats_out_htp_rel_tempfile_input) || die "Can't open file ".$stats_out_htp_rel_tempfile_input;
                foreach (@htp_pheno_matrix) {
                    my $line = join "\t", @$_;
                    print $htp_pheno_f $line."\n";
                }
            close($htp_pheno_f);

            my %rel_htp_result_hash;
            if ($compute_relationship_matrix_from_htp_phenotypes_type eq 'correlations') {
                my $htp_cmd = 'R -e "library(lme4); library(data.table);
                mat <- fread(\''.$stats_out_htp_rel_tempfile_input.'\', header=TRUE, sep=\'\t\');
                mat_agg <- aggregate(mat[, 7:ncol(mat)], list(mat\$accession_id), mean);
                mat_pheno <- mat_agg[,2:ncol(mat_agg)];
                cor_mat <- cor(t(mat_pheno));
                rownames(cor_mat) <- mat_agg[,1];
                colnames(cor_mat) <- mat_agg[,1];
                range01 <- function(x){(x-min(x))/(max(x)-min(x))};
                cor_mat <- range01(cor_mat);
                write.table(cor_mat, file=\''.$stats_out_htp_rel_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');"';
                print STDERR Dumper $htp_cmd;
                my $status = system($htp_cmd);
            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_type eq 'blues') {
                my $htp_cmd = 'R -e "library(lme4); library(data.table);
                mat <- fread(\''.$stats_out_htp_rel_tempfile_input.'\', header=TRUE, sep=\'\t\');
                blues <- data.frame(id = seq(1,length(unique(mat\$accession_id))));
                varlist <- names(mat)[7:ncol(mat)];
                blues.models <- lapply(varlist, function(x) {
                    tryCatch(
                        lmer(substitute(i ~ 1 + (1|accession_id), list(i = as.name(x))), data = mat, REML = FALSE, control = lmerControl(optimizer =\'Nelder_Mead\', boundary.tol='.$compute_relationship_matrix_from_htp_phenotypes_blues_inversion.' ) ), error=function(e) {}
                    )
                });
                counter = 1;
                for (m in blues.models) {
                    if (!is.null(m)) {
                        blues\$accession_id <- row.names(ranef(m)\$accession_id);
                        blues[,ncol(blues) + 1] <- ranef(m)\$accession_id\$\`(Intercept)\`;
                        colnames(blues)[ncol(blues)] <- varlist[counter];
                    }
                    counter = counter + 1;
                }
                blues_vals <- as.matrix(blues[,3:ncol(blues)]);
                blues_vals <- apply(blues_vals, 2, function(y) (y - mean(y)) / sd(y) ^ as.logical(sd(y)));
                rel <- (1/ncol(blues_vals)) * (blues_vals %*% t(blues_vals));
                rownames(rel) <- blues[,2];
                colnames(rel) <- blues[,2];
                write.table(rel, file=\''.$stats_out_htp_rel_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');"';
                print STDERR Dumper $htp_cmd;
                my $status = system($htp_cmd);
            }
            else {
                $c->stash->{rest} = { error => "The value of $compute_relationship_matrix_from_htp_phenotypes_type htp_pheno_rel_matrix_type is not valid!" };
                return;
            }

            open(my $htp_rel_res, '<', $stats_out_htp_rel_tempfile) or die "Could not open file '$stats_out_htp_rel_tempfile' $!";
                print STDERR "Opened $stats_out_htp_rel_tempfile\n";
                my $header_row = <$htp_rel_res>;
                my @header;
                if ($csv->parse($header_row)) {
                    @header = $csv->fields();
                }

                while (my $row = <$htp_rel_res>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    my $stock_id1 = $columns[0];
                    my $counter = 1;
                    foreach my $stock_id2 (@header) {
                        my $val = $columns[$counter];
                        $rel_htp_result_hash{$stock_id1}->{$stock_id2} = $val;
                        $counter++;
                    }
                }
            close($htp_rel_res);

            my $data_rel_htp = '';
            my %result_hash;
            foreach my $s (sort @accession_ids) {
                foreach my $c (sort @accession_ids) {
                    if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                        my $val = $rel_htp_result_hash{$s}->{$c};
                        if (defined $val and length $val) {
                            $result_hash{$s}->{$c} = $val;
                            $data_rel_htp .= "$s\t$c\t$val\n";
                        }
                    }
                }
            }

            open(my $htp_rel_out, ">", $stats_out_htp_rel_tempfile_out) || die "Can't open file ".$stats_out_htp_rel_tempfile_out;
                print $htp_rel_out $data_rel_htp;
            close($htp_rel_out);

            $grm_file_ar1 = $stats_out_htp_rel_tempfile_out;
        }
        else {
            $c->stash->{rest} = { error => "The value of $compute_relationship_matrix_from_htp_phenotypes is not valid!" };
            return;
        }
    };

    my %accession_id_factor_map;
    my %accession_id_factor_map_reverse;
    my %stock_row_col;

    my $cmd_factor = 'R -e "library(data.table); library(dplyr);
    mat <- fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\');
    mat\$accession_id_factor <- as.numeric(as.factor(mat\$id));
    mat\$plot_id_factor <- as.numeric(as.factor(mat\$plot_id));
    write.table(mat, file=\''.$stats_out_tempfile_factors.'\', row.names=FALSE, col.names=TRUE, sep=\',\');"';
    print STDERR Dumper $cmd_factor;
    my $status_factor = system($cmd_factor);

    open(my $fh_factor, '<', $stats_out_tempfile_factors) or die "Could not open file '$stats_out_tempfile_factors' $!";
        print STDERR "Opened $stats_out_tempfile_factors\n";
        my $header = <$fh_factor>;
        my @header_cols;
        if ($csv->parse($header)) {
            @header_cols = $csv->fields();
        }

        my $line_factor_count = 0;
        while (my $row = <$fh_factor>) {
            my @columns;
            if ($csv->parse($row)) {
                @columns = $csv->fields();
            }
            # my @phenotype_header = ("replicate", "block", "id", "plot_id", "rowNumber", "colNumber", "rowNumberFactor", "colNumberFactor", "accession_id_factor", "plot_id_factor");
            my $rep = $columns[0];
            my $block = $columns[1];
            my $accession_id = $columns[2];
            my $plot_id = $columns[3];
            my $accession_id_factor = $columns[8];
            my $plot_id_factor = $columns[9];
            $stock_row_col{$plot_id}->{plot_id_factor} = $plot_id_factor;
            $accession_id_factor_map{$accession_id} = $accession_id_factor;
            $accession_id_factor_map_reverse{$accession_id_factor} = $stock_info{$accession_id}->{uniquename};
            $line_factor_count++;
        }
    close($fh_factor);

    my @data_matrix_original_ar1;
    my %seen_col_numbers;
    my %seen_row_numbers;
    foreach my $p (@seen_plots) {
        my $obsunit_stock_id = $stock_name_row_col{$p}->{obsunit_stock_id};
        my $row_number = $stock_name_row_col{$p}->{row_number};
        my $col_number = $stock_name_row_col{$p}->{col_number};
        my $replicate = $stock_name_row_col{$p}->{rep};
        my $block = $stock_name_row_col{$p}->{block};
        my $germplasm_stock_id = $stock_name_row_col{$p}->{germplasm_stock_id};
        my $germplasm_name = $stock_name_row_col{$p}->{germplasm_name};
        $seen_col_numbers{$col_number}++;
        $seen_row_numbers{$row_number}++;

        my @row = (
            $germplasm_stock_id,
            $obsunit_stock_id,
            $replicate,
            $row_number,
            $col_number,
            $accession_id_factor_map{'S'.$germplasm_stock_id},
            $stock_row_col{$obsunit_stock_id}->{plot_id_factor}
        );

        foreach my $t (@sorted_trait_names) {
            if (defined($plot_phenotypes{$p}->{$t})) {
                push @row, $plot_phenotypes{$p}->{$t};
            } else {
                print STDERR $p." : $t : $germplasm_name : NA \n";
                push @row, 'NA';
            }
        }
        push @data_matrix_original_ar1, \@row;
    }
    # print STDERR Dumper \@data_matrix_original_ar1;
    my @seen_cols_numbers_sorted = sort keys %seen_col_numbers;
    my @seen_rows_numbers_sorted = sort keys %seen_row_numbers;

    my @phenotype_header_ar1 = ("id", "plot_id", "replicate", "rowNumber", "colNumber", "id_factor", "plot_id_factor");
    foreach (@sorted_trait_names) {
        push @phenotype_header_ar1, $trait_name_encoder_s{$_};
    }
    my $header_string_ar1 = join ',', @phenotype_header_ar1;

    open(my $Fs_ar1, ">", $stats_out_tempfile_ar1_indata) || die "Can't open file ".$stats_out_tempfile_ar1_indata;
        print $Fs_ar1 $header_string_ar1."\n";
        foreach (@data_matrix_original_ar1) {
            my $line = join ',', @$_;
            print $Fs_ar1 "$line\n";
        }
    close($Fs_ar1);

    my $csv_tsv = Text::CSV->new({ sep_char => "\t" });

    my @grm_old;
    open(my $fh_grm_old, '<', $grm_file_ar1) or die "Could not open file '$grm_file_ar1' $!";
        print STDERR "Opened $grm_file_ar1\n";

        while (my $row = <$fh_grm_old>) {
            my @columns;
            if ($csv_tsv->parse($row)) {
                @columns = $csv_tsv->fields();
            }
            push @grm_old, \@columns;
        }
    close($fh_grm_old);

    my %grm_hash_ordered;
    foreach (@grm_old) {
        my $l1 = $accession_id_factor_map{"S".$_->[0]};
        my $l2 = $accession_id_factor_map{"S".$_->[1]};
        my $val = sprintf("%.8f", $_->[2]);
        if ($l1 > $l2) {
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

    my $tol_asr = 'c(-8,-10)';
    if ($tolparinv eq '0.000001') {
        $tol_asr = 'c(-6,-8)';
    }
    if ($tolparinv eq '0.00001') {
        $tol_asr = 'c(-5,-7)';
    }
    if ($tolparinv eq '0.0001') {
        $tol_asr = 'c(-4,-6)';
    }
    if ($tolparinv eq '0.001') {
        $tol_asr = 'c(-3,-5)';
    }
    if ($tolparinv eq '0.01') {
        $tol_asr = 'c(-2,-4)';
    }
    if ($tolparinv eq '0.05') {
        $tol_asr = 'c(-2,-3)';
    }
    if ($tolparinv eq '0.08') {
        $tol_asr = 'c(-1,-2)';
    }
    if ($tolparinv eq '0.1' || $tolparinv eq '0.2' || $tolparinv eq '0.5') {
        $tol_asr = 'c(-1,-2)';
    }

    if ($default_tol eq 'default_both' || $default_tol eq 'pre_2dspl_def_ar1') {
        $tol_asr = 'c(-8,-10)';
    }
    elsif ($default_tol eq 'large_tol') {
        $tol_asr = 'c(-1,-2)';
    }

    my $number_traits = scalar(@sorted_trait_names);
    my $number_accessions = scalar(@accession_ids);

    my $current_gen_row_count_ar1 = 0;
    my $current_env_row_count_ar1 = 0;
    my $genetic_effect_min_ar1 = 1000000000;
    my $genetic_effect_max_ar1 = -1000000000;
    my $env_effect_min_ar1 = 1000000000;
    my $env_effect_max_ar1 = -1000000000;
    my $genetic_effect_sum_square_ar1 = 0;
    my $genetic_effect_sum_ar1 = 0;
    my $env_effect_sum_square_ar1 = 0;
    my $env_effect_sum_ar1 = 0;
    my $residual_sum_square_ar1 = 0;
    my $residual_sum_ar1 = 0;
    my @row_col_ordered_plots_names_ar1;
    my $result_blup_data_ar1;
    my $result_blup_spatial_data_ar1;

    eval {
        my $stats_out_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_residual = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_varcomp = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

        my $spatial_correct_ar1_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_out_tempfile_ar1_indata.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumber);
        mat\$colNumberFactor <- as.factor(mat\$colNumber);
        mat\$rowNumberFactorSep <- mat\$rowNumberFactor;
        mat\$colNumberFactorSep <- mat\$colNumberFactor;
        mat\$id_factor <- as.factor(mat\$id_factor);
        mat <- mat[order(mat\$rowNumber, mat\$colNumber),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml('.$trait_name_encoded_string.'~1 + replicate, random=~vm(id_factor, geno_mat_3col) + ar1v(rowNumberFactor):ar1(colNumberFactor), residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        summary(mix);
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        }
        "';
        print STDERR Dumper $spatial_correct_ar1_cmd;
        my $spatial_correct_ar1_status = system($spatial_correct_ar1_cmd);

        open(my $fh_residual_ar1, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual_ar1 = <$fh_residual_ar1>;
            my @header_cols_residual_ar1;
            if ($csv->parse($header_residual_ar1)) {
                @header_cols_residual_ar1 = $csv->fields();
            }
            while (my $row = <$fh_residual_ar1>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                push @row_col_ordered_plots_names_ar1, $stock_name;
                if (defined $residual && $residual ne '') {
                    $residual_sum_ar1 += abs($residual);
                    $residual_sum_square_ar1 = $residual_sum_square_ar1 + $residual*$residual;
                }
            }
        close($fh_residual_ar1);

        open(my $fh_ar1, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header_ar1 = <$fh_ar1>;

            my $solution_file_counter_ar1 = 0;
            while (defined(my $row = <$fh_ar1>)) {
                # print STDERR $row;
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $level = $columns[0];
                my $value = $columns[1];
                my $std = $columns[2];
                my $z_ratio = $columns[3];
                if (defined $value && $value ne '') {
                    if ($solution_file_counter_ar1 < $number_accessions) {
                        my $stock_name = $accession_id_factor_map_reverse{$solution_file_counter_ar1 + 1};
                        $result_blup_data_ar1->{$stock_name}->{$trait_name_string} = $value;

                        if ($value < $genetic_effect_min_ar1) {
                            $genetic_effect_min_ar1 = $value;
                        }
                        elsif ($value >= $genetic_effect_max_ar1) {
                            $genetic_effect_max_ar1 = $value;
                        }

                        $genetic_effect_sum_ar1 += abs($value);
                        $genetic_effect_sum_square_ar1 = $genetic_effect_sum_square_ar1 + $value*$value;

                        $current_gen_row_count_ar1++;
                    }
                    else {
                        my $plot_name = $row_col_ordered_plots_names_ar1[$current_env_row_count_ar1];
                        $result_blup_spatial_data_ar1->{$plot_name}->{$trait_name_string} = $value;

                        if ($value < $env_effect_min_ar1) {
                            $env_effect_min_ar1 = $value;
                        }
                        elsif ($value >= $env_effect_max_ar1) {
                            $env_effect_max_ar1 = $value;
                        }

                        $env_effect_sum_ar1 += abs($value);
                        $env_effect_sum_square_ar1 = $env_effect_sum_square_ar1 + $value*$value;

                        $current_env_row_count_ar1++;
                    }
                }
                $solution_file_counter_ar1++;
            }
        close($fh_ar1);
        # print STDERR Dumper $result_blup_spatial_data_ar1;
    };

    my $current_gen_row_count_ar1wCol = 0;
    my $current_env_row_count_ar1wCol = 0;
    my $genetic_effect_min_ar1wCol = 1000000000;
    my $genetic_effect_max_ar1wCol = -1000000000;
    my $env_effect_min_ar1wCol = 1000000000;
    my $env_effect_max_ar1wCol = -1000000000;
    my $genetic_effect_sum_square_ar1wCol = 0;
    my $genetic_effect_sum_ar1wCol = 0;
    my $env_effect_sum_square_ar1wCol = 0;
    my $env_effect_sum_ar1wCol = 0;
    my $residual_sum_square_ar1wCol = 0;
    my $residual_sum_ar1wCol = 0;
    my @row_col_ordered_plots_names_ar1wCol;
    my $result_blup_data_ar1wCol;
    my $result_blup_spatial_data_ar1wCol;

    eval {
        my $stats_out_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_residual = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_varcomp = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

        my $spatial_correct_ar1wCol_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_out_tempfile_ar1_indata.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumber);
        mat\$colNumberFactor <- as.factor(mat\$colNumber);
        mat\$rowNumberFactorSep <- mat\$rowNumberFactor;
        mat\$colNumberFactorSep <- mat\$colNumberFactor;
        mat\$id_factor <- as.factor(mat\$id_factor);
        mat <- mat[order(mat\$rowNumber, mat\$colNumber),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml('.$trait_name_encoded_string.'~1 + replicate, random=~vm(id_factor, geno_mat_3col) + ar1v(rowNumberFactor):ar1(colNumberFactor) + colNumberFactor, residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        summary(mix);
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        }
        "';
        print STDERR Dumper $spatial_correct_ar1wCol_cmd;
        my $spatial_correct_ar1wCol_status = system($spatial_correct_ar1wCol_cmd);

        open(my $fh_residual_ar1wCol, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual_ar1wCol = <$fh_residual_ar1wCol>;
            my @header_cols_residual_ar1wCol = ();
            if ($csv->parse($header_residual_ar1wCol)) {
                @header_cols_residual_ar1wCol = $csv->fields();
            }
            while (my $row = <$fh_residual_ar1wCol>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                push @row_col_ordered_plots_names_ar1wCol, $stock_name;
                if (defined $residual && $residual ne '') {
                    $residual_sum_ar1wCol += abs($residual);
                    $residual_sum_square_ar1wCol = $residual_sum_square_ar1wCol + $residual*$residual;
                }
            }
        close($fh_residual_ar1wCol);

        open(my $fh_ar1wCol, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header_ar1wCol = <$fh_ar1wCol>;

            my $solution_file_counter_ar1wCol_skipping = 0;
            my $solution_file_counter_ar1wCol = 0;
            while (defined(my $row = <$fh_ar1wCol>)) {
                # print STDERR $row;
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $level = $columns[0];
                my $value = $columns[1];
                my $std = $columns[2];
                my $z_ratio = $columns[3];
                if (defined $value && $value ne '') {
                    if ($solution_file_counter_ar1wCol_skipping < scalar(@seen_cols_numbers_sorted)) {
                        $solution_file_counter_ar1wCol_skipping++;
                        next;
                    }
                    elsif ($solution_file_counter_ar1wCol < $number_accessions) {
                        my $stock_name = $accession_id_factor_map_reverse{$solution_file_counter_ar1wCol + 1};
                        $result_blup_data_ar1wCol->{$stock_name}->{$trait_name_string} = $value;

                        if ($value < $genetic_effect_min_ar1wCol) {
                            $genetic_effect_min_ar1wCol = $value;
                        }
                        elsif ($value >= $genetic_effect_max_ar1wCol) {
                            $genetic_effect_max_ar1wCol = $value;
                        }

                        $genetic_effect_sum_ar1wCol += abs($value);
                        $genetic_effect_sum_square_ar1wCol = $genetic_effect_sum_square_ar1wCol + $value*$value;

                        $current_gen_row_count_ar1wCol++;
                    }
                    else {
                        my $plot_name = $row_col_ordered_plots_names_ar1wCol[$current_env_row_count_ar1wCol];
                        $result_blup_spatial_data_ar1wCol->{$plot_name}->{$trait_name_string} = $value;

                        if ($value < $env_effect_min_ar1wCol) {
                            $env_effect_min_ar1wCol = $value;
                        }
                        elsif ($value >= $env_effect_max_ar1wCol) {
                            $env_effect_max_ar1wCol = $value;
                        }

                        $env_effect_sum_ar1wCol += abs($value);
                        $env_effect_sum_square_ar1wCol = $env_effect_sum_square_ar1wCol + $value*$value;

                        $current_env_row_count_ar1wCol++;
                    }
                }
                $solution_file_counter_ar1wCol++;
            }
        close($fh_ar1wCol);
        # print STDERR Dumper $result_blup_spatial_data_ar1wCol;
    };

    my $current_gen_row_count_ar1wRow = 0;
    my $current_env_row_count_ar1wRow = 0;
    my $genetic_effect_min_ar1wRow = 1000000000;
    my $genetic_effect_max_ar1wRow = -1000000000;
    my $env_effect_min_ar1wRow = 1000000000;
    my $env_effect_max_ar1wRow = -1000000000;
    my $genetic_effect_sum_square_ar1wRow = 0;
    my $genetic_effect_sum_ar1wRow = 0;
    my $env_effect_sum_square_ar1wRow = 0;
    my $env_effect_sum_ar1wRow = 0;
    my $residual_sum_square_ar1wRow = 0;
    my $residual_sum_ar1wRow = 0;
    my @row_col_ordered_plots_names_ar1wRow;
    my $result_blup_data_ar1wRow;
    my $result_blup_spatial_data_ar1wRow;

    eval {
        my $stats_out_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_residual = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_varcomp = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

        my $spatial_correct_ar1wRow_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_out_tempfile_ar1_indata.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumber);
        mat\$colNumberFactor <- as.factor(mat\$colNumber);
        mat\$rowNumberFactorSep <- mat\$rowNumberFactor;
        mat\$colNumberFactorSep <- mat\$colNumberFactor;
        mat\$id_factor <- as.factor(mat\$id_factor);
        mat <- mat[order(mat\$rowNumber, mat\$colNumber),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml('.$trait_name_encoded_string.'~1 + replicate, random=~vm(id_factor, geno_mat_3col) + ar1v(rowNumberFactor):ar1(colNumberFactor) + rowNumberFactor, residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        summary(mix);
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        }
        "';
        print STDERR Dumper $spatial_correct_ar1wRow_cmd;
        my $spatial_correct_ar1wRow_status = system($spatial_correct_ar1wRow_cmd);

        open(my $fh_residual_ar1wRow, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual_ar1wRow = <$fh_residual_ar1wRow>;
            my @header_cols_residual_ar1wRow = ();
            if ($csv->parse($header_residual_ar1wRow)) {
                @header_cols_residual_ar1wRow = $csv->fields();
            }
            while (my $row = <$fh_residual_ar1wRow>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                push @row_col_ordered_plots_names_ar1wRow, $stock_name;
                if (defined $residual && $residual ne '') {
                    $residual_sum_ar1wRow += abs($residual);
                    $residual_sum_square_ar1wRow = $residual_sum_square_ar1wRow + $residual*$residual;
                }
            }
        close($fh_residual_ar1wRow);

        open(my $fh_ar1wRow, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header_ar1wRow = <$fh_ar1wRow>;

            my $solution_file_counter_ar1wRow_skipping = 0;
            my $solution_file_counter_ar1wRow = 0;
            while (defined(my $row = <$fh_ar1wRow>)) {
                # print STDERR $row;
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $level = $columns[0];
                my $value = $columns[1];
                my $std = $columns[2];
                my $z_ratio = $columns[3];
                if (defined $value && $value ne '') {
                    if ($solution_file_counter_ar1wRow_skipping < scalar(@seen_rows_numbers_sorted)) {
                        $solution_file_counter_ar1wRow_skipping++;
                        next;
                    }
                    elsif ($solution_file_counter_ar1wRow < $number_accessions) {
                        my $stock_name = $accession_id_factor_map_reverse{$solution_file_counter_ar1wRow + 1};
                        $result_blup_data_ar1wRow->{$stock_name}->{$trait_name_string} = $value;

                        if ($value < $genetic_effect_min_ar1wRow) {
                            $genetic_effect_min_ar1wRow = $value;
                        }
                        elsif ($value >= $genetic_effect_max_ar1wRow) {
                            $genetic_effect_max_ar1wRow = $value;
                        }

                        $genetic_effect_sum_ar1wRow += abs($value);
                        $genetic_effect_sum_square_ar1wRow = $genetic_effect_sum_square_ar1wRow + $value*$value;

                        $current_gen_row_count_ar1wRow++;
                    }
                    else {
                        my $plot_name = $row_col_ordered_plots_names_ar1wRow[$current_env_row_count_ar1wRow];
                        $result_blup_spatial_data_ar1wRow->{$plot_name}->{$trait_name_string} = $value;

                        if ($value < $env_effect_min_ar1wRow) {
                            $env_effect_min_ar1wRow = $value;
                        }
                        elsif ($value >= $env_effect_max_ar1wRow) {
                            $env_effect_max_ar1wRow = $value;
                        }

                        $env_effect_sum_ar1wRow += abs($value);
                        $env_effect_sum_square_ar1wRow = $env_effect_sum_square_ar1wRow + $value*$value;

                        $current_env_row_count_ar1wRow++;
                    }
                }
                $solution_file_counter_ar1wRow++;
            }
        close($fh_ar1wRow);
        # print STDERR Dumper $result_blup_spatial_data_ar1wRow;
    };

    my $current_gen_row_count_ar1wRowCol = 0;
    my $current_env_row_count_ar1wRowCol = 0;
    my $genetic_effect_min_ar1wRowCol = 1000000000;
    my $genetic_effect_max_ar1wRowCol = -1000000000;
    my $env_effect_min_ar1wRowCol = 1000000000;
    my $env_effect_max_ar1wRowCol = -1000000000;
    my $genetic_effect_sum_square_ar1wRowCol = 0;
    my $genetic_effect_sum_ar1wRowCol = 0;
    my $env_effect_sum_square_ar1wRowCol = 0;
    my $env_effect_sum_ar1wRowCol = 0;
    my $residual_sum_square_ar1wRowCol = 0;
    my $residual_sum_ar1wRowCol = 0;
    my @row_col_ordered_plots_names_ar1wRowCol;
    my $result_blup_data_ar1wRowCol;
    my $result_blup_spatial_data_ar1wRowCol;

    eval {
        my $stats_out_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_residual = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_varcomp = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

        my $spatial_correct_ar1wRowCol_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_out_tempfile_ar1_indata.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumber);
        mat\$colNumberFactor <- as.factor(mat\$colNumber);
        mat\$rowNumberFactorSep <- mat\$rowNumberFactor;
        mat\$colNumberFactorSep <- mat\$colNumberFactor;
        mat\$id_factor <- as.factor(mat\$id_factor);
        mat <- mat[order(mat\$rowNumber, mat\$colNumber),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml('.$trait_name_encoded_string.'~1 + replicate, random=~vm(id_factor, geno_mat_3col) + ar1v(rowNumberFactor):ar1(colNumberFactor) + rowNumberFactor + colNumberFactor, residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        summary(mix);
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        }
        "';
        print STDERR Dumper $spatial_correct_ar1wRowCol_cmd;
        my $spatial_correct_ar1wRowCol_status = system($spatial_correct_ar1wRowCol_cmd);

        open(my $fh_residual_ar1wRowCol, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual_ar1wRowCol = <$fh_residual_ar1wRowCol>;
            my @header_cols_residual_ar1wRowCol = ();
            if ($csv->parse($header_residual_ar1wRowCol)) {
                @header_cols_residual_ar1wRowCol = $csv->fields();
            }
            while (my $row = <$fh_residual_ar1wRowCol>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                push @row_col_ordered_plots_names_ar1wRowCol, $stock_name;
                if (defined $residual && $residual ne '') {
                    $residual_sum_ar1wRowCol += abs($residual);
                    $residual_sum_square_ar1wRowCol = $residual_sum_square_ar1wRowCol + $residual*$residual;
                }
            }
        close($fh_residual_ar1wRowCol);

        open(my $fh_ar1wRowCol, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header_ar1wRowCol = <$fh_ar1wRowCol>;

            my $solution_file_counter_ar1wRowCol_skipping = 0;
            my $solution_file_counter_ar1wRowCol = 0;
            while (defined(my $row = <$fh_ar1wRowCol>)) {
                # print STDERR $row;
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $level = $columns[0];
                my $value = $columns[1];
                my $std = $columns[2];
                my $z_ratio = $columns[3];
                if (defined $value && $value ne '') {
                    if ($solution_file_counter_ar1wRowCol_skipping < scalar(@seen_rows_numbers_sorted) + scalar(@seen_cols_numbers_sorted)) {
                        $solution_file_counter_ar1wRowCol_skipping++;
                        next;
                    }
                    elsif ($solution_file_counter_ar1wRowCol < $number_accessions) {
                        my $stock_name = $accession_id_factor_map_reverse{$solution_file_counter_ar1wRowCol + 1};
                        $result_blup_data_ar1wRowCol->{$stock_name}->{$trait_name_string} = $value;

                        if ($value < $genetic_effect_min_ar1wRowCol) {
                            $genetic_effect_min_ar1wRowCol = $value;
                        }
                        elsif ($value >= $genetic_effect_max_ar1wRowCol) {
                            $genetic_effect_max_ar1wRowCol = $value;
                        }

                        $genetic_effect_sum_ar1wRowCol += abs($value);
                        $genetic_effect_sum_square_ar1wRowCol = $genetic_effect_sum_square_ar1wRowCol + $value*$value;

                        $current_gen_row_count_ar1wRowCol++;
                    }
                    else {
                        my $plot_name = $row_col_ordered_plots_names_ar1wRowCol[$current_env_row_count_ar1wRowCol];
                        $result_blup_spatial_data_ar1wRowCol->{$plot_name}->{$trait_name_string} = $value;

                        if ($value < $env_effect_min_ar1wRowCol) {
                            $env_effect_min_ar1wRowCol = $value;
                        }
                        elsif ($value >= $env_effect_max_ar1wRowCol) {
                            $env_effect_max_ar1wRowCol = $value;
                        }

                        $env_effect_sum_ar1wRowCol += abs($value);
                        $env_effect_sum_square_ar1wRowCol = $env_effect_sum_square_ar1wRowCol + $value*$value;

                        $current_env_row_count_ar1wRowCol++;
                    }
                }
                $solution_file_counter_ar1wRowCol++;
            }
        close($fh_ar1wRowCol);
        # print STDERR Dumper $result_blup_spatial_data_ar1wRowCol;
    };

    my $current_gen_row_count_ar1wRowColOnly = 0;
    my $genetic_effect_min_ar1wRowColOnly = 1000000000;
    my $genetic_effect_max_ar1wRowColOnly = -1000000000;
    my $env_effect_min_ar1wRowColOnly = 1000000000;
    my $env_effect_max_ar1wRowColOnly = -1000000000;
    my $genetic_effect_sum_square_ar1wRowColOnly = 0;
    my $genetic_effect_sum_ar1wRowColOnly = 0;
    my $env_effect_sum_square_ar1wRowColOnly = 0;
    my $env_effect_sum_ar1wRowColOnly = 0;
    my $residual_sum_square_ar1wRowColOnly = 0;
    my $residual_sum_ar1wRowColOnly = 0;
    my @row_col_ordered_plots_names_ar1wRowColOnly;
    my $result_blup_data_ar1wRowColOnly;
    my $result_blup_spatial_data_ar1wRowColOnly;

    eval {
        my $stats_out_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_residual = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_varcomp = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

        my $spatial_correct_ar1wRowColOnly_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_out_tempfile_ar1_indata.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumber);
        mat\$colNumberFactor <- as.factor(mat\$colNumber);
        mat\$rowNumberFactorSep <- mat\$rowNumberFactor;
        mat\$colNumberFactorSep <- mat\$colNumberFactor;
        mat\$id_factor <- as.factor(mat\$id_factor);
        mat <- mat[order(mat\$rowNumber, mat\$colNumber),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml('.$trait_name_encoded_string.'~1 + replicate, random=~vm(id_factor, geno_mat_3col) + rowNumberFactor + colNumberFactor, residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        summary(mix);
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        }
        "';
        print STDERR Dumper $spatial_correct_ar1wRowColOnly_cmd;
        my $spatial_correct_ar1wRowColOnly_status = system($spatial_correct_ar1wRowColOnly_cmd);

        open(my $fh_residual_ar1wRowColOnly, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual_ar1wRowColOnly = <$fh_residual_ar1wRowColOnly>;
            my @header_cols_residual_ar1wRowColOnly = ();
            if ($csv->parse($header_residual_ar1wRowColOnly)) {
                @header_cols_residual_ar1wRowColOnly = $csv->fields();
            }
            while (my $row = <$fh_residual_ar1wRowColOnly>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                push @row_col_ordered_plots_names_ar1wRowColOnly, $stock_name;
                if (defined $residual && $residual ne '') {
                    $residual_sum_ar1wRowColOnly += abs($residual);
                    $residual_sum_square_ar1wRowColOnly = $residual_sum_square_ar1wRowColOnly + $residual*$residual;
                }
            }
        close($fh_residual_ar1wRowColOnly);

        my %result_blup_row_spatial_data_ar1wRowColOnly;
        my %result_blup_col_spatial_data_ar1wRowColOnly;

        open(my $fh_ar1wRowColOnly, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header_ar1wRowColOnly = <$fh_ar1wRowColOnly>;

            my $solution_file_counter_ar1wRowColOnly = 0;
            while (defined(my $row = <$fh_ar1wRowColOnly>)) {
                # print STDERR $row;
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $level = $columns[0];
                my $value = $columns[1];
                my $std = $columns[2];
                my $z_ratio = $columns[3];
                if (defined $value && $value ne '') {
                    if ($solution_file_counter_ar1wRowColOnly < scalar(@seen_cols_numbers_sorted)) {
                        my @level_split = split '_', $level;
                        $result_blup_col_spatial_data_ar1wRowColOnly{$level_split[1]} = $value;
                    }
                    elsif ($solution_file_counter_ar1wRowColOnly < scalar(@seen_rows_numbers_sorted) + scalar(@seen_cols_numbers_sorted) ) {
                        my @level_split = split '_', $level;
                        $result_blup_row_spatial_data_ar1wRowColOnly{$level_split[1]} = $value;
                    }
                    elsif ($solution_file_counter_ar1wRowColOnly < $number_accessions + scalar(@seen_cols_numbers_sorted) + scalar(@seen_rows_numbers_sorted) ) {
                        my $stock_name = $accession_id_factor_map_reverse{$solution_file_counter_ar1wRowColOnly - scalar(@seen_cols_numbers_sorted) - scalar(@seen_rows_numbers_sorted) + 1};
                        $result_blup_data_ar1wRowColOnly->{$stock_name}->{$trait_name_string} = $value;

                        if ($value < $genetic_effect_min_ar1wRowColOnly) {
                            $genetic_effect_min_ar1wRowColOnly = $value;
                        }
                        elsif ($value >= $genetic_effect_max_ar1wRowColOnly) {
                            $genetic_effect_max_ar1wRowColOnly = $value;
                        }

                        $genetic_effect_sum_ar1wRowColOnly += abs($value);
                        $genetic_effect_sum_square_ar1wRowColOnly = $genetic_effect_sum_square_ar1wRowColOnly + $value*$value;

                        $current_gen_row_count_ar1wRowColOnly++;
                    }
                }
                $solution_file_counter_ar1wRowColOnly++;
            }
        close($fh_ar1wRowColOnly);
        # print STDERR Dumper \%result_blup_col_spatial_data_ar1wRowColOnly;
        # print STDERR Dumper \%result_blup_row_spatial_data_ar1wRowColOnly;

        while (my($row_level, $row_val) = each %result_blup_row_spatial_data_ar1wRowColOnly) {
            while (my($col_level, $col_val) = each %result_blup_col_spatial_data_ar1wRowColOnly) {
                my $plot_name = $plot_row_col_hash{$row_level}->{$col_level}->{obsunit_name};

                my $value = $row_val + $col_val;
                $result_blup_spatial_data_ar1wRowColOnly->{$plot_name}->{$trait_name_string} = $value;

                if ($value < $env_effect_min_ar1wRowColOnly) {
                    $env_effect_min_ar1wRowColOnly = $value;
                }
                elsif ($value >= $env_effect_max_ar1wRowColOnly) {
                    $env_effect_max_ar1wRowColOnly = $value;
                }

                $env_effect_sum_ar1wRowColOnly += abs($value);
                $env_effect_sum_square_ar1wRowColOnly = $env_effect_sum_square_ar1wRowColOnly + $value*$value;
            }
        }
        # print STDERR Dumper $result_blup_spatial_data_ar1wRowColOnly;
    };

    my $current_gen_row_count_ar1wRowPlusCol = 0;
    my $genetic_effect_min_ar1wRowPlusCol = 1000000000;
    my $genetic_effect_max_ar1wRowPlusCol = -1000000000;
    my $env_effect_min_ar1wRowPlusCol = 1000000000;
    my $env_effect_max_ar1wRowPlusCol = -1000000000;
    my $genetic_effect_sum_square_ar1wRowPlusCol = 0;
    my $genetic_effect_sum_ar1wRowPlusCol = 0;
    my $env_effect_sum_square_ar1wRowPlusCol = 0;
    my $env_effect_sum_ar1wRowPlusCol = 0;
    my $residual_sum_square_ar1wRowPlusCol = 0;
    my $residual_sum_ar1wRowPlusCol = 0;
    my @row_col_ordered_plots_names_ar1wRowPlusCol;
    my $result_blup_data_ar1wRowPlusCol;
    my $result_blup_spatial_data_ar1wRowPlusCol;

    eval {
        my $stats_out_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_residual = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_varcomp = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

        my $spatial_correct_ar1wRowPlusCol_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_out_tempfile_ar1_indata.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumber);
        mat\$colNumberFactor <- as.factor(mat\$colNumber);
        mat\$rowNumberFactorSep <- mat\$rowNumberFactor;
        mat\$colNumberFactorSep <- mat\$colNumberFactor;
        mat\$id_factor <- as.factor(mat\$id_factor);
        mat <- mat[order(mat\$rowNumber, mat\$colNumber),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml('.$trait_name_encoded_string.'~1 + replicate, random=~vm(id_factor, geno_mat_3col) + ar1v(rowNumberFactor) + colNumberFactor, residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        summary(mix);
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        }
        "';
        print STDERR Dumper $spatial_correct_ar1wRowPlusCol_cmd;
        my $spatial_correct_ar1wRowPlusCol_status = system($spatial_correct_ar1wRowPlusCol_cmd);

        open(my $fh_residual_ar1wRowPlusCol, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual_ar1wRowPlusCol = <$fh_residual_ar1wRowPlusCol>;
            my @header_cols_residual_ar1wRowPlusCol = ();
            if ($csv->parse($header_residual_ar1wRowPlusCol)) {
                @header_cols_residual_ar1wRowPlusCol = $csv->fields();
            }
            while (my $row = <$fh_residual_ar1wRowPlusCol>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                push @row_col_ordered_plots_names_ar1wRowPlusCol, $stock_name;
                if (defined $residual && $residual ne '') {
                    $residual_sum_ar1wRowPlusCol += abs($residual);
                    $residual_sum_square_ar1wRowPlusCol = $residual_sum_square_ar1wRowPlusCol + $residual*$residual;
                }
            }
        close($fh_residual_ar1wRowPlusCol);

        my %result_blup_row_spatial_data_ar1wRowPlusCol;
        my %result_blup_col_spatial_data_ar1wRowPlusCol;

        open(my $fh_ar1wRowPlusCol, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header_ar1wRowPlusCol = <$fh_ar1wRowPlusCol>;

            my $solution_file_counter_ar1wRowPlusCol_skipping = 0;
            my $solution_file_counter_ar1wRowPlusCol = 0;
            while (defined(my $row = <$fh_ar1wRowPlusCol>)) {
                # print STDERR $row;
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $level = $columns[0];
                my $value = $columns[1];
                my $std = $columns[2];
                my $z_ratio = $columns[3];
                if (defined $value && $value ne '') {
                    if ($solution_file_counter_ar1wRowPlusCol < scalar(@seen_cols_numbers_sorted)) {
                        my @level_split = split '_', $level;
                        $result_blup_col_spatial_data_ar1wRowPlusCol{$level_split[1]} = $value;
                    }
                    elsif ($solution_file_counter_ar1wRowPlusCol < scalar(@seen_cols_numbers_sorted) + scalar(@seen_rows_numbers_sorted)) {
                        my @level_split = split '_', $level;
                        $result_blup_row_spatial_data_ar1wRowPlusCol{$level_split[1]} = $value;
                    }
                    elsif ($solution_file_counter_ar1wRowPlusCol < $number_accessions + scalar(@seen_cols_numbers_sorted) + scalar(@seen_rows_numbers_sorted)) {
                        my $stock_name = $accession_id_factor_map_reverse{$solution_file_counter_ar1wRowPlusCol - scalar(@seen_cols_numbers_sorted) - scalar(@seen_rows_numbers_sorted) + 1};
                        $result_blup_data_ar1wRowPlusCol->{$stock_name}->{$trait_name_string} = $value;

                        if ($value < $genetic_effect_min_ar1wRowPlusCol) {
                            $genetic_effect_min_ar1wRowPlusCol = $value;
                        }
                        elsif ($value >= $genetic_effect_max_ar1wRowPlusCol) {
                            $genetic_effect_max_ar1wRowPlusCol = $value;
                        }

                        $genetic_effect_sum_ar1wRowPlusCol += abs($value);
                        $genetic_effect_sum_square_ar1wRowPlusCol = $genetic_effect_sum_square_ar1wRowPlusCol + $value*$value;

                        $current_gen_row_count_ar1wRowPlusCol++;
                    }
                }
                $solution_file_counter_ar1wRowPlusCol++;
            }
        close($fh_ar1wRowPlusCol);

        while (my($row_level, $row_val) = each %result_blup_row_spatial_data_ar1wRowPlusCol) {
            while (my($col_level, $col_val) = each %result_blup_col_spatial_data_ar1wRowPlusCol) {
                my $plot_name = $plot_row_col_hash{$row_level}->{$col_level}->{obsunit_name};

                my $value = $row_val + $col_val;
                $result_blup_spatial_data_ar1wRowPlusCol->{$plot_name}->{$trait_name_string} = $value;

                if ($value < $env_effect_min_ar1wRowPlusCol) {
                    $env_effect_min_ar1wRowPlusCol = $value;
                }
                elsif ($value >= $env_effect_max_ar1wRowPlusCol) {
                    $env_effect_max_ar1wRowPlusCol = $value;
                }

                $env_effect_sum_ar1wRowPlusCol += abs($value);
                $env_effect_sum_square_ar1wRowPlusCol = $env_effect_sum_square_ar1wRowPlusCol + $value*$value;
            }
        }
        # print STDERR Dumper $result_blup_spatial_data_ar1wRowPlusCol;
    };

    my $current_gen_row_count_ar1wColPlusRow = 0;
    my $genetic_effect_min_ar1wColPlusRow = 1000000000;
    my $genetic_effect_max_ar1wColPlusRow = -1000000000;
    my $env_effect_min_ar1wColPlusRow = 1000000000;
    my $env_effect_max_ar1wColPlusRow = -1000000000;
    my $genetic_effect_sum_square_ar1wColPlusRow = 0;
    my $genetic_effect_sum_ar1wColPlusRow = 0;
    my $env_effect_sum_square_ar1wColPlusRow = 0;
    my $env_effect_sum_ar1wColPlusRow = 0;
    my $residual_sum_square_ar1wColPlusRow = 0;
    my $residual_sum_ar1wColPlusRow = 0;
    my @row_col_ordered_plots_names_ar1wColPlusRow;
    my $result_blup_data_ar1wColPlusRow;
    my $result_blup_spatial_data_ar1wColPlusRow;

    eval {
        my $stats_out_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_residual = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $stats_out_tempfile_varcomp = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

        my $spatial_correct_ar1wColPlusRow_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_out_tempfile_ar1_indata.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumber);
        mat\$colNumberFactor <- as.factor(mat\$colNumber);
        mat\$rowNumberFactorSep <- mat\$rowNumberFactor;
        mat\$colNumberFactorSep <- mat\$colNumberFactor;
        mat\$id_factor <- as.factor(mat\$id_factor);
        mat <- mat[order(mat\$rowNumber, mat\$colNumber),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml('.$trait_name_encoded_string.'~1 + replicate, random=~vm(id_factor, geno_mat_3col) + ar1v(colNumberFactor) + rowNumberFactor, residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        summary(mix);
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        }
        "';
        print STDERR Dumper $spatial_correct_ar1wColPlusRow_cmd;
        my $spatial_correct_ar1wColPlusRow_status = system($spatial_correct_ar1wColPlusRow_cmd);

        open(my $fh_residual_ar1wColPlusRow, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual_ar1wColPlusRow = <$fh_residual_ar1wColPlusRow>;
            my @header_cols_residual_ar1wColPlusRow = ();
            if ($csv->parse($header_residual_ar1wColPlusRow)) {
                @header_cols_residual_ar1wColPlusRow = $csv->fields();
            }
            while (my $row = <$fh_residual_ar1wColPlusRow>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                push @row_col_ordered_plots_names_ar1wColPlusRow, $stock_name;
                if (defined $residual && $residual ne '') {
                    $residual_sum_ar1wColPlusRow += abs($residual);
                    $residual_sum_square_ar1wColPlusRow = $residual_sum_square_ar1wColPlusRow + $residual*$residual;
                }
            }
        close($fh_residual_ar1wColPlusRow);

        my %result_blup_row_spatial_data_ar1wColPlusRow;
        my %result_blup_col_spatial_data_ar1wColPlusRow;

        open(my $fh_ar1wColPlusRow, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header_ar1wColPlusRow = <$fh_ar1wColPlusRow>;

            my $solution_file_counter_ar1wColPlusRow_skipping = 0;
            my $solution_file_counter_ar1wColPlusRow = 0;
            while (defined(my $row = <$fh_ar1wColPlusRow>)) {
                # print STDERR $row;
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $level = $columns[0];
                my $value = $columns[1];
                my $std = $columns[2];
                my $z_ratio = $columns[3];
                if (defined $value && $value ne '') {
                    if ($solution_file_counter_ar1wColPlusRow < scalar(@seen_cols_numbers_sorted)) {
                        my @level_split = split '_', $level;
                        $result_blup_col_spatial_data_ar1wColPlusRow{$level_split[1]} = $value;
                    }
                    elsif ($solution_file_counter_ar1wColPlusRow < scalar(@seen_cols_numbers_sorted) + scalar(@seen_rows_numbers_sorted)) {
                        my @level_split = split '_', $level;
                        $result_blup_row_spatial_data_ar1wColPlusRow{$level_split[1]} = $value;
                    }
                    elsif ($solution_file_counter_ar1wColPlusRow < $number_accessions + scalar(@seen_cols_numbers_sorted) + scalar(@seen_rows_numbers_sorted) ) {
                        my $stock_name = $accession_id_factor_map_reverse{$solution_file_counter_ar1wColPlusRow - scalar(@seen_cols_numbers_sorted) - scalar(@seen_rows_numbers_sorted) + 1};
                        $result_blup_data_ar1wColPlusRow->{$stock_name}->{$trait_name_string} = $value;

                        if ($value < $genetic_effect_min_ar1wColPlusRow) {
                            $genetic_effect_min_ar1wColPlusRow = $value;
                        }
                        elsif ($value >= $genetic_effect_max_ar1wColPlusRow) {
                            $genetic_effect_max_ar1wColPlusRow = $value;
                        }

                        $genetic_effect_sum_ar1wColPlusRow += abs($value);
                        $genetic_effect_sum_square_ar1wColPlusRow = $genetic_effect_sum_square_ar1wColPlusRow + $value*$value;

                        $current_gen_row_count_ar1wColPlusRow++;
                    }
                }
                $solution_file_counter_ar1wColPlusRow++;
            }
        close($fh_ar1wColPlusRow);

        while (my($row_level, $row_val) = each %result_blup_row_spatial_data_ar1wColPlusRow) {
            while (my($col_level, $col_val) = each %result_blup_col_spatial_data_ar1wColPlusRow) {
                my $plot_name = $plot_row_col_hash{$row_level}->{$col_level}->{obsunit_name};

                my $value = $row_val + $col_val;
                $result_blup_spatial_data_ar1wColPlusRow->{$plot_name}->{$trait_name_string} = $value;

                if ($value < $env_effect_min_ar1wColPlusRow) {
                    $env_effect_min_ar1wColPlusRow = $value;
                }
                elsif ($value >= $env_effect_max_ar1wColPlusRow) {
                    $env_effect_max_ar1wColPlusRow = $value;
                }

                $env_effect_sum_ar1wColPlusRow += abs($value);
                $env_effect_sum_square_ar1wColPlusRow = $env_effect_sum_square_ar1wColPlusRow + $value*$value;
            }
        }
        # print STDERR Dumper $result_blup_spatial_data_ar1wColPlusRow;
    };

    my $grm_file;
    # Prepare GRM for 2Dspl Trait Spatial Correction
    eval {
        print STDERR Dumper [$compute_relationship_matrix_from_htp_phenotypes, $include_pedgiree_info_if_compute_from_parents, $use_parental_grms_if_compute_from_parents, $compute_from_parents];
        if ($compute_relationship_matrix_from_htp_phenotypes eq 'genotypes') {

            if ($include_pedgiree_info_if_compute_from_parents) {
                my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
                my $tmp_arm_dir = $shared_cluster_dir_config."/tmp_download_arm";
                mkdir $tmp_arm_dir if ! -d $tmp_arm_dir;
                my ($arm_tempfile_fh, $arm_tempfile) = tempfile("drone_stats_download_arm_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm1_tempfile_fh, $grm1_tempfile) = tempfile("drone_stats_download_grm1_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_temp_tempfile_fh, $grm_out_temp_tempfile) = tempfile("drone_stats_download_grm_temp_out_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_posdef_tempfile_fh, $grm_out_posdef_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);

                if (!$genotyping_protocol_id) {
                    $genotyping_protocol_id = undef;
                }

                my $pedigree_arm = CXGN::Pedigree::ARM->new({
                    bcs_schema=>$schema,
                    arm_temp_file=>$arm_tempfile,
                    people_schema=>$people_schema,
                    accession_id_list=>\@accession_ids,
                    # plot_id_list=>\@plot_id_list,
                    cache_root=>$c->config->{cache_file_path},
                    download_format=>'matrix', #either 'matrix', 'three_column', or 'heatmap'
                });
                my ($parent_hash, $stock_ids, $all_accession_stock_ids, $female_stock_ids, $male_stock_ids) = $pedigree_arm->get_arm(
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                # print STDERR Dumper $parent_hash;

                my $female_geno = CXGN::Genotype::GRM->new({
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm1_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>$female_stock_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>0,
                    download_format=>'three_column_reciprocal',
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                });
                my $female_grm_data = $female_geno->download_grm(
                    'data',
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                my @fl = split '\n', $female_grm_data;
                my %female_parent_grm;
                foreach (@fl) {
                    my @l = split '\t', $_;
                    $female_parent_grm{$l[0]}->{$l[1]} = $l[2];
                }
                # print STDERR Dumper \%female_parent_grm;

                my $male_geno = CXGN::Genotype::GRM->new({
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm1_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>$male_stock_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>0,
                    download_format=>'three_column_reciprocal',
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                });
                my $male_grm_data = $male_geno->download_grm(
                    'data',
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                my @ml = split '\n', $male_grm_data;
                my %male_parent_grm;
                foreach (@ml) {
                    my @l = split '\t', $_;
                    $male_parent_grm{$l[0]}->{$l[1]} = $l[2];
                }
                # print STDERR Dumper \%male_parent_grm;

                my %rel_result_hash;
                foreach my $a1 (@accession_ids) {
                    foreach my $a2 (@accession_ids) {
                        my $female_parent1 = $parent_hash->{$a1}->{female_stock_id};
                        my $male_parent1 = $parent_hash->{$a1}->{male_stock_id};
                        my $female_parent2 = $parent_hash->{$a2}->{female_stock_id};
                        my $male_parent2 = $parent_hash->{$a2}->{male_stock_id};

                        my $female_rel = 0;
                        if ($female_parent1 && $female_parent2 && $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2}) {
                            $female_rel = $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2};
                        }
                        elsif ($female_parent1 && $female_parent2 && $female_parent1 == $female_parent2) {
                            $female_rel = 1;
                        }
                        elsif ($a1 == $a2) {
                            $female_rel = 1;
                        }

                        my $male_rel = 0;
                        if ($male_parent1 && $male_parent2 && $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2}) {
                            $male_rel = $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2};
                        }
                        elsif ($male_parent1 && $male_parent2 && $male_parent1 == $male_parent2) {
                            $male_rel = 1;
                        }
                        elsif ($a1 == $a2) {
                            $male_rel = 1;
                        }
                        # print STDERR "$a1 $a2 $female_rel $male_rel\n";

                        my $rel = 0.5*($female_rel + $male_rel);
                        $rel_result_hash{$a1}->{$a2} = $rel;
                    }
                }
                # print STDERR Dumper \%rel_result_hash;

                my $data = '';
                my %result_hash;
                foreach my $s (sort @accession_ids) {
                    foreach my $c (sort @accession_ids) {
                        if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                            my $val = $rel_result_hash{$s}->{$c};
                            if (defined $val and length $val) {
                                $result_hash{$s}->{$c} = $val;
                                $data .= "S$s\tS$c\t$val\n";
                            }
                        }
                    }
                }

                # print STDERR Dumper $data;
                open(my $F2, ">", $grm_out_temp_tempfile) || die "Can't open file ".$grm_out_temp_tempfile;
                    print $F2 $data;
                close($F2);

                my $cmd = 'R -e "library(data.table); library(scales); library(tidyr); library(reshape2);
                three_col <- fread(\''.$grm_out_temp_tempfile.'\', header=FALSE, sep=\'\t\');
                A_wide <- dcast(three_col, V1~V2, value.var=\'V3\');
                A_1 <- A_wide[,-1];
                A_1[is.na(A_1)] <- 0;
                A <- A_1 + t(A_1);
                diag(A) <- diag(as.matrix(A_1));
                E = eigen(A);
                ev = E\$values;
                U = E\$vectors;
                no = dim(A)[1];
                nev = which(ev < 0);
                wr = 0;
                k=length(nev);
                if(k > 0){
                    p = ev[no - k];
                    B = sum(ev[nev])*2.0;
                    wr = (B*B*100.0)+1;
                    val = ev[nev];
                    ev[nev] = p*(B-val)*(B-val)/wr;
                    A = U%*%diag(ev)%*%t(U);
                }
                A <- as.data.frame(A);
                colnames(A) <- A_wide[,1];
                A\$stock_id <- A_wide[,1];
                A_threecol <- melt(A, id.vars = c(\'stock_id\'), measure.vars = A_wide[,1]);
                A_threecol\$stock_id <- substring(A_threecol\$stock_id, 2);
                A_threecol\$variable <- substring(A_threecol\$variable, 2);
                write.table(data.frame(variable = A_threecol\$variable, stock_id = A_threecol\$stock_id, value = A_threecol\$value), file=\''.$grm_out_tempfile.'\', row.names=FALSE, col.names=FALSE, sep=\'\t\');"';
                print STDERR $cmd."\n";
                my $status = system($cmd);

                my %rel_pos_def_result_hash;
                open(my $F3, '<', $grm_out_tempfile)
                    or die "Could not open file '$grm_out_tempfile' $!";

                    print STDERR "Opened $grm_out_tempfile\n";

                    while (my $row = <$F3>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        my $stock_id1 = $columns[0];
                        my $stock_id2 = $columns[1];
                        my $val = $columns[2];
                        $rel_pos_def_result_hash{$stock_id1}->{$stock_id2} = $val;
                    }
                close($F3);

                my $data_pos_def = '';
                %result_hash = ();
                foreach my $s (sort @accession_ids) {
                    foreach my $c (sort @accession_ids) {
                        if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                            my $val = $rel_pos_def_result_hash{$s}->{$c};
                            if (defined $val and length $val) {
                                $result_hash{$s}->{$c} = $val;
                                $result_hash{$c}->{$s} = $val;
                                $data_pos_def .= "S$s\tS$c\t$val\n";
                                if ($s != $c) {
                                    $data_pos_def .= "S$c\tS$s\t$val\n";
                                }
                            }
                        }
                    }
                }

                open(my $F4, ">", $grm_out_posdef_tempfile) || die "Can't open file ".$grm_out_posdef_tempfile;
                    print $F4 $data_pos_def;
                close($F4);

                $grm_file = $grm_out_posdef_tempfile;
            }
            elsif ($use_parental_grms_if_compute_from_parents) {
                my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
                my $tmp_arm_dir = $shared_cluster_dir_config."/tmp_download_arm";
                mkdir $tmp_arm_dir if ! -d $tmp_arm_dir;
                my ($arm_tempfile_fh, $arm_tempfile) = tempfile("drone_stats_download_arm_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm1_tempfile_fh, $grm1_tempfile) = tempfile("drone_stats_download_grm1_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_temp_tempfile_fh, $grm_out_temp_tempfile) = tempfile("drone_stats_download_grm_temp_out_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_posdef_tempfile_fh, $grm_out_posdef_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);

                if (!$genotyping_protocol_id) {
                    $genotyping_protocol_id = undef;
                }

                my $pedigree_arm = CXGN::Pedigree::ARM->new({
                    bcs_schema=>$schema,
                    arm_temp_file=>$arm_tempfile,
                    people_schema=>$people_schema,
                    accession_id_list=>\@accession_ids,
                    # plot_id_list=>\@plot_id_list,
                    cache_root=>$c->config->{cache_file_path},
                    download_format=>'matrix', #either 'matrix', 'three_column', or 'heatmap'
                });
                my ($parent_hash, $stock_ids, $all_accession_stock_ids, $female_stock_ids, $male_stock_ids) = $pedigree_arm->get_arm(
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                # print STDERR Dumper $parent_hash;

                my $female_geno = CXGN::Genotype::GRM->new({
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm1_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>$female_stock_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>0,
                    download_format=>'three_column_reciprocal',
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                });
                my $female_grm_data = $female_geno->download_grm(
                    'data',
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                my @fl = split '\n', $female_grm_data;
                my %female_parent_grm;
                foreach (@fl) {
                    my @l = split '\t', $_;
                    $female_parent_grm{$l[0]}->{$l[1]} = $l[2];
                }
                # print STDERR Dumper \%female_parent_grm;

                my $male_geno = CXGN::Genotype::GRM->new({
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm1_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>$male_stock_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>0,
                    download_format=>'three_column_reciprocal',
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                });
                my $male_grm_data = $male_geno->download_grm(
                    'data',
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                my @ml = split '\n', $male_grm_data;
                my %male_parent_grm;
                foreach (@ml) {
                    my @l = split '\t', $_;
                    $male_parent_grm{$l[0]}->{$l[1]} = $l[2];
                }
                # print STDERR Dumper \%male_parent_grm;

                my %rel_result_hash;
                foreach my $a1 (@accession_ids) {
                    foreach my $a2 (@accession_ids) {
                        my $female_parent1 = $parent_hash->{$a1}->{female_stock_id};
                        my $male_parent1 = $parent_hash->{$a1}->{male_stock_id};
                        my $female_parent2 = $parent_hash->{$a2}->{female_stock_id};
                        my $male_parent2 = $parent_hash->{$a2}->{male_stock_id};

                        my $female_rel = 0;
                        if ($female_parent1 && $female_parent2 && $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2}) {
                            $female_rel = $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2};
                        }
                        elsif ($a1 == $a2) {
                            $female_rel = 1;
                        }

                        my $male_rel = 0;
                        if ($male_parent1 && $male_parent2 && $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2}) {
                            $male_rel = $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2};
                        }
                        elsif ($a1 == $a2) {
                            $male_rel = 1;
                        }
                        # print STDERR "$a1 $a2 $female_rel $male_rel\n";

                        my $rel = 0.5*($female_rel + $male_rel);
                        $rel_result_hash{$a1}->{$a2} = $rel;
                    }
                }
                # print STDERR Dumper \%rel_result_hash;

                my $data = '';
                my %result_hash;
                foreach my $s (sort @accession_ids) {
                    foreach my $c (sort @accession_ids) {
                        if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                            my $val = $rel_result_hash{$s}->{$c};
                            if (defined $val and length $val) {
                                $result_hash{$s}->{$c} = $val;
                                $data .= "S$s\tS$c\t$val\n";
                            }
                        }
                    }
                }

                # print STDERR Dumper $data;
                open(my $F2, ">", $grm_out_temp_tempfile) || die "Can't open file ".$grm_out_temp_tempfile;
                    print $F2 $data;
                close($F2);

                my $cmd = 'R -e "library(data.table); library(scales); library(tidyr); library(reshape2);
                three_col <- fread(\''.$grm_out_temp_tempfile.'\', header=FALSE, sep=\'\t\');
                A_wide <- dcast(three_col, V1~V2, value.var=\'V3\');
                A_1 <- A_wide[,-1];
                A_1[is.na(A_1)] <- 0;
                A <- A_1 + t(A_1);
                diag(A) <- diag(as.matrix(A_1));
                E = eigen(A);
                ev = E\$values;
                U = E\$vectors;
                no = dim(A)[1];
                nev = which(ev < 0);
                wr = 0;
                k=length(nev);
                if(k > 0){
                    p = ev[no - k];
                    B = sum(ev[nev])*2.0;
                    wr = (B*B*100.0)+1;
                    val = ev[nev];
                    ev[nev] = p*(B-val)*(B-val)/wr;
                    A = U%*%diag(ev)%*%t(U);
                }
                A <- as.data.frame(A);
                colnames(A) <- A_wide[,1];
                A\$stock_id <- A_wide[,1];
                A_threecol <- melt(A, id.vars = c(\'stock_id\'), measure.vars = A_wide[,1]);
                A_threecol\$stock_id <- substring(A_threecol\$stock_id, 2);
                A_threecol\$variable <- substring(A_threecol\$variable, 2);
                write.table(data.frame(variable = A_threecol\$variable, stock_id = A_threecol\$stock_id, value = A_threecol\$value), file=\''.$grm_out_tempfile.'\', row.names=FALSE, col.names=FALSE, sep=\'\t\');"';
                print STDERR $cmd."\n";
                my $status = system($cmd);

                my %rel_pos_def_result_hash;
                open(my $F3, '<', $grm_out_tempfile) or die "Could not open file '$grm_out_tempfile' $!";
                    print STDERR "Opened $grm_out_tempfile\n";

                    while (my $row = <$F3>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        my $stock_id1 = $columns[0];
                        my $stock_id2 = $columns[1];
                        my $val = $columns[2];
                        $rel_pos_def_result_hash{$stock_id1}->{$stock_id2} = $val;
                    }
                close($F3);

                my $data_pos_def = '';
                %result_hash = ();
                foreach my $s (sort @accession_ids) {
                    foreach my $c (sort @accession_ids) {
                        if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                            my $val = $rel_pos_def_result_hash{$s}->{$c};
                            if (defined $val and length $val) {
                                $result_hash{$s}->{$c} = $val;
                                $result_hash{$c}->{$s} = $val;
                                $data_pos_def .= "S$s\tS$c\t$val\n";
                                if ($s != $c) {
                                    $data_pos_def .= "S$c\tS$s\t$val\n";
                                }
                            }
                        }
                    }
                }

                open(my $F4, ">", $grm_out_posdef_tempfile) || die "Can't open file ".$grm_out_posdef_tempfile;
                    print $F4 $data_pos_def;
                close($F4);

                $grm_file = $grm_out_posdef_tempfile;
            }
            else {
                my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
                my $tmp_grm_dir = $shared_cluster_dir_config."/tmp_genotype_download_grm";
                mkdir $tmp_grm_dir if ! -d $tmp_grm_dir;
                my ($grm_tempfile_fh, $grm_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
                my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);

                if (!$genotyping_protocol_id) {
                    $genotyping_protocol_id = undef;
                }

                my $grm_search_params = {
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>\@accession_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>$compute_from_parents,
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                };
                $grm_search_params->{download_format} = 'three_column_reciprocal';

                my $geno = CXGN::Genotype::GRM->new($grm_search_params);
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
                $grm_file = $grm_out_tempfile;
            }

        }
        elsif ($compute_relationship_matrix_from_htp_phenotypes eq 'htp_phenotypes') {
            my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
            my $tmp_grm_dir = $shared_cluster_dir_config."/tmp_genotype_download_grm";
            mkdir $tmp_grm_dir if ! -d $tmp_grm_dir;
            my ($stats_out_htp_rel_tempfile_input_fh, $stats_out_htp_rel_tempfile_input) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
            my ($stats_out_htp_rel_tempfile_fh, $stats_out_htp_rel_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
            my ($stats_out_htp_rel_tempfile_out_fh, $stats_out_htp_rel_tempfile_out) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);

            my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
                'MaterializedViewTable',
                {
                    bcs_schema=>$schema,
                    data_level=>'plot',
                    trial_list=>$field_trial_id_list,
                    include_timestamp=>0,
                    exclude_phenotype_outlier=>0
                }
            );
            my ($data, $unique_traits) = $phenotypes_search->search();

            if (scalar(@$data) == 0) {
                $c->stash->{rest} = { error => "There are no phenotypes for the trial you have selected!"};
                return;
            }

            my $q_time = "SELECT t.cvterm_id FROM cvterm as t JOIN cv ON(t.cv_id=cv.cv_id) WHERE t.name=? and cv.name=?;";
            my $h_time = $schema->storage->dbh()->prepare($q_time);

            my %seen_plot_names_htp_rel;
            my %phenotype_data_htp_rel;
            my %seen_times_htp_rel;
            foreach my $obs_unit (@$data){
                my $germplasm_name = $obs_unit->{germplasm_uniquename};
                my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
                my $row_number = $obs_unit->{obsunit_row_number} || '';
                my $col_number = $obs_unit->{obsunit_col_number} || '';
                my $rep = $obs_unit->{obsunit_rep};
                my $block = $obs_unit->{obsunit_block};
                $seen_plot_names_htp_rel{$obs_unit->{observationunit_uniquename}} = $obs_unit;
                my $observations = $obs_unit->{observations};
                foreach (@$observations){
                    if ($_->{associated_image_project_time_json}) {
                        my $related_time_terms_json = decode_json $_->{associated_image_project_time_json};

                        my $time_days_cvterm = $related_time_terms_json->{day};
                        my $time_days_term_string = $time_days_cvterm;
                        my $time_days = (split '\|', $time_days_cvterm)[0];
                        my $time_days_value = (split ' ', $time_days)[1];

                        my $time_gdd_value = $related_time_terms_json->{gdd_average_temp} + 0;
                        my $gdd_term_string = "GDD $time_gdd_value";
                        $h_time->execute($gdd_term_string, 'cxgn_time_ontology');
                        my ($gdd_cvterm_id) = $h_time->fetchrow_array();
                        if (!$gdd_cvterm_id) {
                            my $new_gdd_term = $schema->resultset("Cv::Cvterm")->create_with({
                               name => $gdd_term_string,
                               cv => 'cxgn_time_ontology'
                            });
                            $gdd_cvterm_id = $new_gdd_term->cvterm_id();
                        }
                        my $time_gdd_term_string = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $gdd_cvterm_id, 'extended');

                        $phenotype_data_htp_rel{$obs_unit->{observationunit_uniquename}}->{$_->{trait_name}} = $_->{value};
                        $seen_times_htp_rel{$_->{trait_name}} = [$time_days_value, $time_days_term_string, $time_gdd_value, $time_gdd_term_string];
                    }
                }
            }
            $h_time = undef;

            my @allowed_standard_htp_values = ('Nonzero Pixel Count', 'Total Pixel Sum', 'Mean Pixel Value', 'Harmonic Mean Pixel Value', 'Median Pixel Value', 'Pixel Variance', 'Pixel Standard Deviation', 'Pixel Population Standard Deviation', 'Minimum Pixel Value', 'Maximum Pixel Value', 'Minority Pixel Value', 'Minority Pixel Count', 'Majority Pixel Value', 'Majority Pixel Count', 'Pixel Group Count');
            my %filtered_seen_times_htp_rel;
            while (my ($t, $time) = each %seen_times_htp_rel) {
                my $allowed = 0;
                foreach (@allowed_standard_htp_values) {
                    if (index($t, $_) != -1) {
                        $allowed = 1;
                        last;
                    }
                }
                if ($allowed) {
                    $filtered_seen_times_htp_rel{$t} = $time;
                }
            }

            my @seen_plot_names_htp_rel_sorted = sort keys %seen_plot_names_htp_rel;
            my @filtered_seen_times_htp_rel_sorted = sort keys %filtered_seen_times_htp_rel;

            my @header_htp = ('plot_id', 'plot_name', 'accession_id', 'accession_name', 'rep', 'block');

            my %trait_name_encoder_htp;
            my %trait_name_encoder_rev_htp;
            my $trait_name_encoded_htp = 1;
            my @header_traits_htp;
            foreach my $trait_name (@filtered_seen_times_htp_rel_sorted) {
                if (!exists($trait_name_encoder_htp{$trait_name})) {
                    my $trait_name_e = 't'.$trait_name_encoded_htp;
                    $trait_name_encoder_htp{$trait_name} = $trait_name_e;
                    $trait_name_encoder_rev_htp{$trait_name_e} = $trait_name;
                    push @header_traits_htp, $trait_name_e;
                    $trait_name_encoded_htp++;
                }
            }

            my @htp_pheno_matrix;
            if ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'all') {
                push @header_htp, @header_traits_htp;
                push @htp_pheno_matrix, \@header_htp;

                foreach my $p (@seen_plot_names_htp_rel_sorted) {
                    my $obj = $seen_plot_names_htp_rel{$p};
                    my @row = ($obj->{observationunit_stock_id}, $obj->{observationunit_uniquename}, $obj->{germplasm_stock_id}, $obj->{germplasm_uniquename}, $obj->{obsunit_rep}, $obj->{obsunit_block});
                    foreach my $t (@filtered_seen_times_htp_rel_sorted) {
                        my $val = $phenotype_data_htp_rel{$p}->{$t} + 0;
                        push @row, $val;
                    }
                    push @htp_pheno_matrix, \@row;
                }
            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'latest_trait') {
                my $max_day = 0;
                foreach (keys %seen_days_after_plantings) {
                    if ($_ + 0 > $max_day) {
                        $max_day = $_;
                    }
                }

                foreach my $t (@filtered_seen_times_htp_rel_sorted) {
                    my $day = $filtered_seen_times_htp_rel{$t}->[0];
                    if ($day <= $max_day) {
                        push @header_htp, $t;
                    }
                }
                push @htp_pheno_matrix, \@header_htp;

                foreach my $p (@seen_plot_names_htp_rel_sorted) {
                    my $obj = $seen_plot_names_htp_rel{$p};
                    my @row = ($obj->{observationunit_stock_id}, $obj->{observationunit_uniquename}, $obj->{germplasm_stock_id}, $obj->{germplasm_uniquename}, $obj->{obsunit_rep}, $obj->{obsunit_block});
                    foreach my $t (@filtered_seen_times_htp_rel_sorted) {
                        my $day = $filtered_seen_times_htp_rel{$t}->[0];
                        if ($day <= $max_day) {
                            my $val = $phenotype_data_htp_rel{$p}->{$t} + 0;
                            push @row, $val;
                        }
                    }
                    push @htp_pheno_matrix, \@row;
                }
            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'vegetative') {

            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'reproductive') {

            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'mature') {

            }
            else {
                $c->stash->{rest} = { error => "The value of $compute_relationship_matrix_from_htp_phenotypes_time_points htp_pheno_rel_matrix_time_points is not valid!" };
                return;
            }

            open(my $htp_pheno_f, ">", $stats_out_htp_rel_tempfile_input) || die "Can't open file ".$stats_out_htp_rel_tempfile_input;
                foreach (@htp_pheno_matrix) {
                    my $line = join "\t", @$_;
                    print $htp_pheno_f $line."\n";
                }
            close($htp_pheno_f);

            my %rel_htp_result_hash;
            if ($compute_relationship_matrix_from_htp_phenotypes_type eq 'correlations') {
                my $htp_cmd = 'R -e "library(lme4); library(data.table);
                mat <- fread(\''.$stats_out_htp_rel_tempfile_input.'\', header=TRUE, sep=\'\t\');
                mat_agg <- aggregate(mat[, 7:ncol(mat)], list(mat\$accession_id), mean);
                mat_pheno <- mat_agg[,2:ncol(mat_agg)];
                cor_mat <- cor(t(mat_pheno));
                rownames(cor_mat) <- mat_agg[,1];
                colnames(cor_mat) <- mat_agg[,1];
                range01 <- function(x){(x-min(x))/(max(x)-min(x))};
                cor_mat <- range01(cor_mat);
                write.table(cor_mat, file=\''.$stats_out_htp_rel_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');"';
                print STDERR Dumper $htp_cmd;
                my $status = system($htp_cmd);
            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_type eq 'blues') {
                my $htp_cmd = 'R -e "library(lme4); library(data.table);
                mat <- fread(\''.$stats_out_htp_rel_tempfile_input.'\', header=TRUE, sep=\'\t\');
                blues <- data.frame(id = seq(1,length(unique(mat\$accession_id))));
                varlist <- names(mat)[7:ncol(mat)];
                blues.models <- lapply(varlist, function(x) {
                    tryCatch(
                        lmer(substitute(i ~ 1 + (1|accession_id), list(i = as.name(x))), data = mat, REML = FALSE, control = lmerControl(optimizer =\'Nelder_Mead\', boundary.tol='.$compute_relationship_matrix_from_htp_phenotypes_blues_inversion.' ) ), error=function(e) {}
                    )
                });
                counter = 1;
                for (m in blues.models) {
                    if (!is.null(m)) {
                        blues\$accession_id <- row.names(ranef(m)\$accession_id);
                        blues[,ncol(blues) + 1] <- ranef(m)\$accession_id\$\`(Intercept)\`;
                        colnames(blues)[ncol(blues)] <- varlist[counter];
                    }
                    counter = counter + 1;
                }
                blues_vals <- as.matrix(blues[,3:ncol(blues)]);
                blues_vals <- apply(blues_vals, 2, function(y) (y - mean(y)) / sd(y) ^ as.logical(sd(y)));
                rel <- (1/ncol(blues_vals)) * (blues_vals %*% t(blues_vals));
                rownames(rel) <- blues[,2];
                colnames(rel) <- blues[,2];
                write.table(rel, file=\''.$stats_out_htp_rel_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');"';
                print STDERR Dumper $htp_cmd;
                my $status = system($htp_cmd);
            }
            else {
                $c->stash->{rest} = { error => "The value of $compute_relationship_matrix_from_htp_phenotypes_type htp_pheno_rel_matrix_type is not valid!" };
                return;
            }

            open(my $htp_rel_res, '<', $stats_out_htp_rel_tempfile) or die "Could not open file '$stats_out_htp_rel_tempfile' $!";
                print STDERR "Opened $stats_out_htp_rel_tempfile\n";
                my $header_row = <$htp_rel_res>;
                my @header;
                if ($csv->parse($header_row)) {
                    @header = $csv->fields();
                }

                while (my $row = <$htp_rel_res>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    my $stock_id1 = $columns[0];
                    my $counter = 1;
                    foreach my $stock_id2 (@header) {
                        my $val = $columns[$counter];
                        $rel_htp_result_hash{$stock_id1}->{$stock_id2} = $val;
                        $counter++;
                    }
                }
            close($htp_rel_res);

            my $data_rel_htp = '';
            my %result_hash;
            foreach my $s (sort @accession_ids) {
                foreach my $c (sort @accession_ids) {
                    if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                        my $val = $rel_htp_result_hash{$s}->{$c};
                        if (defined $val and length $val) {
                            $result_hash{$s}->{$c} = $val;
                            $result_hash{$c}->{$s} = $val;
                            $data_rel_htp .= "S$s\tS$c\t$val\n";
                            if ($s != $c) {
                                $data_rel_htp .= "S$c\tS$s\t$val\n";
                            }
                        }
                    }
                }
            }

            open(my $htp_rel_out, ">", $stats_out_htp_rel_tempfile_out) || die "Can't open file ".$stats_out_htp_rel_tempfile_out;
                print $htp_rel_out $data_rel_htp;
            close($htp_rel_out);

            $grm_file = $stats_out_htp_rel_tempfile_out;
        }
        else {
            $c->stash->{rest} = { error => "The value of $compute_relationship_matrix_from_htp_phenotypes is not valid!" };
            return;
        }
    };

    if ($default_tol eq 'default_both' || $default_tol eq 'pre_ar1_def_2dspl') {
        $tolparinv = 0.000001;
        $tolparinv_10 = $tolparinv*10;
    }
    elsif ($default_tol eq 'large_tol') {
        $tolparinv = 10;
        $tolparinv_10 = 10;
    }

    my @data_matrix_original_sp;
    foreach my $p (@seen_plots) {
        my $obsunit_stock_id = $stock_name_row_col{$p}->{obsunit_stock_id};
        my $row_number = $stock_name_row_col{$p}->{row_number};
        my $col_number = $stock_name_row_col{$p}->{col_number};
        my $replicate = $stock_name_row_col{$p}->{rep};
        my $block = $stock_name_row_col{$p}->{block};
        my $germplasm_stock_id = $stock_name_row_col{$p}->{germplasm_stock_id};
        my $germplasm_name = $stock_name_row_col{$p}->{germplasm_name};

        my @row = ($replicate, $block, "S".$germplasm_stock_id, $obsunit_stock_id, $row_number, $col_number, $row_number, $col_number, '', '');

        foreach my $t (@sorted_trait_names) {
            if (defined($plot_phenotypes{$p}->{$t})) {
                push @row, $plot_phenotypes{$p}->{$t};
            } else {
                print STDERR $p." : $t : $germplasm_name : NA \n";
                push @row, 'NA';
            }
        }
        push @data_matrix_original_sp, \@row;
    }

    my @phenotype_header_sp = ("replicate", "block", "id", "plot_id", "rowNumber", "colNumber", "rowNumberFactor", "colNumberFactor", "accession_id_factor", "plot_id_factor");
    foreach (@sorted_trait_names) {
        push @phenotype_header_sp, $trait_name_encoder_s{$_};
    }
    my $header_string_sp = join ',', @phenotype_header_sp;

    open($Fs, ">", $stats_tempfile) || die "Can't open file ".$stats_tempfile;
        print $Fs $header_string_sp."\n";
        foreach (@data_matrix_original_sp) {
            my $line = join ',', @$_;
            print $Fs "$line\n";
        }
    close($Fs);

    my $result_blup_data_s;
    my $genetic_effect_max_s = -1000000000;
    my $genetic_effect_min_s = 10000000000;
    my $genetic_effect_sum_square_s = 0;
    my $genetic_effect_sum_s = 0;
    my $result_blup_spatial_data_s;
    my $env_effect_min_s = 100000000;
    my $env_effect_max_s = -100000000;
    my $env_effect_sum_s = 0;
    my $env_effect_sum_square_s = 0;
    my $result_residual_data_s;
    my $result_fitted_data_s;
    my $residual_sum_s = 0;
    my $residual_sum_square_s = 0;
    my $model_sum_square_residual_s = 0;

    my $spatial_correct_2dspl_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
    mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
    geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
    geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
    geno_mat[is.na(geno_mat)] <- 0;
    mat\$rowNumber <- as.numeric(mat\$rowNumber);
    mat\$colNumber <- as.numeric(mat\$colNumber);
    mat\$rowNumberFactor <- as.factor(mat\$rowNumberFactor);
    mat\$colNumberFactor <- as.factor(mat\$colNumberFactor);
    mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + spl2Da(rowNumber, colNumber), rcov=~vs(units), data=mat, tolparinv='.$tolparinv_10.');
    if (!is.null(mix\$U)) {
    #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
    write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
    write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
    spatial_blup_results <- data.frame(plot_id = mat\$plot_id);
    W <- with(mat, spl2Da(rowNumber, colNumber));
    X <- W\$Z\$\`A:all\`;
    blups1 <- mix\$U\$\`A:all\`\$'.$trait_name_encoded_string.';
    spatial_blup_results\$'.$trait_name_encoded_string.' <- X %*% blups1;
    write.table(spatial_blup_results, file=\''.$stats_out_tempfile_2dspl.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
    }
    "';
    print STDERR Dumper $spatial_correct_2dspl_cmd;
    my $spatial_correct_2dspl_status = system($spatial_correct_2dspl_cmd);

    open(my $fh_sp, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
        print STDERR "Opened $stats_out_tempfile\n";
        my $header_sp = <$fh_sp>;
        my @header_cols_sp;
        if ($csv->parse($header_sp)) {
            @header_cols_sp = $csv->fields();
        }

        while (my $row = <$fh_sp>) {
            my @columns;
            if ($csv->parse($row)) {
                @columns = $csv->fields();
            }
            my $col_counter = 0;
            foreach my $encoded_trait (@header_cols_sp) {
                if ($encoded_trait eq $trait_name_encoded_string) {
                    my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                    my $stock_id = $columns[0];

                    my $stock_name = $stock_info{$stock_id}->{uniquename};
                    my $value = $columns[$col_counter+1];
                    if (defined $value && $value ne '') {
                        $result_blup_data_s->{$stock_name}->{$trait} = $value;

                        if ($value < $genetic_effect_min_s) {
                            $genetic_effect_min_s = $value;
                        }
                        elsif ($value >= $genetic_effect_max_s) {
                            $genetic_effect_max_s = $value;
                        }

                        $genetic_effect_sum_s += abs($value);
                        $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                    }
                }
                $col_counter++;
            }
        }
    close($fh_sp);

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
                if ($encoded_trait eq $trait_name_encoded_string) {
                    my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                    my $plot_id = $columns[0];

                    my $plot_name = $plot_id_map{$plot_id};
                    my $value = $columns[$col_counter+1];
                    if (defined $value && $value ne '') {
                        $result_blup_spatial_data_s->{$plot_name}->{$trait} = $value;

                        if ($value < $env_effect_min_s) {
                            $env_effect_min_s = $value;
                        }
                        elsif ($value >= $env_effect_max_s) {
                            $env_effect_max_s = $value;
                        }

                        $env_effect_sum_s += abs($value);
                        $env_effect_sum_square_s = $env_effect_sum_square_s + $value*$value;
                    }
                }
                $col_counter++;
            }
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

            my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
            my $stock_id = $columns[0];
            my $residual = $columns[1];
            my $fitted = $columns[2];
            my $stock_name = $plot_id_map{$stock_id};
            if (defined $residual && $residual ne '') {
                $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                $residual_sum_s += abs($residual);
                $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
            }
            if (defined $fitted && $fitted ne '') {
                $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
            }
            $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
        }
    close($fh_residual);

    my @plots_avg_data_heatmap_values_header = ("trait_type", "row", "col", "value");
    my @plots_avg_data_heatmap_values = ();
    my @plots_avg_data_ggcor_values = ();
    my @type_names_plot = ('2DSpline', 'AR(1)xAR(1)', 'AR(1)xAR(1)+Col', 'AR(1)xAR(1)+Row', 'AR(1)xAR(1)+Row+Col', 'Row+Col', 'AR(1)Row+Col', 'AR(1)Col+Row', 'AVG');

    foreach my $p (@seen_plots) {
        my $row = $stock_name_row_col{$p}->{row_number};
        my $col = $stock_name_row_col{$p}->{col_number};

        my $val0 = $result_blup_spatial_data_s->{$p}->{$trait_name_string} || 0;
        my $val1 = $result_blup_spatial_data_ar1->{$p}->{$trait_name_string} || 0;
        my $val2 = $result_blup_spatial_data_ar1wCol->{$p}->{$trait_name_string} || 0;
        my $val3 = $result_blup_spatial_data_ar1wRow->{$p}->{$trait_name_string} || 0;
        my $val4 = $result_blup_spatial_data_ar1wRowCol->{$p}->{$trait_name_string} || 0;
        my $val5 = $result_blup_spatial_data_ar1wRowColOnly->{$p}->{$trait_name_string} || 0;
        my $val6 = $result_blup_spatial_data_ar1wRowPlusCol->{$p}->{$trait_name_string} || 0;
        my $val7 = $result_blup_spatial_data_ar1wColPlusRow->{$p}->{$trait_name_string} || 0;
        my $val8 = ($val0 + $val1 + $val2 + $val3 + $val4 + $val5 + $val6 + $val7)/8;
        push @plots_avg_data_heatmap_values, [$type_names_plot[0], $row, $col, $val0 || 'NA'];
        push @plots_avg_data_heatmap_values, [$type_names_plot[1], $row, $col, $val1 || 'NA'];
        push @plots_avg_data_heatmap_values, [$type_names_plot[2], $row, $col, $val2 || 'NA'];
        push @plots_avg_data_heatmap_values, [$type_names_plot[3], $row, $col, $val3 || 'NA'];
        push @plots_avg_data_heatmap_values, [$type_names_plot[4], $row, $col, $val4 || 'NA'];
        push @plots_avg_data_heatmap_values, [$type_names_plot[5], $row, $col, $val5 || 'NA'];
        push @plots_avg_data_heatmap_values, [$type_names_plot[6], $row, $col, $val6 || 'NA'];
        push @plots_avg_data_heatmap_values, [$type_names_plot[7], $row, $col, $val7 || 'NA'];
        push @plots_avg_data_heatmap_values, [$type_names_plot[8], $row, $col, $val8 || 'NA'];

        push @plots_avg_data_ggcor_values, [$val0 || 'NA', $val1 || 'NA', $val2 || 'NA', $val3 || 'NA', $val4 || 'NA', $val5 || 'NA', $val6 || 'NA', $val7 || 'NA', $val8 || 'NA'];
    }

    my @germplasm_data_header = ('germplasmName', '2Dspline', 'AR(1)xAR(1)', 'AR(1)xAR(1)+Col', 'AR(1)xAR(1)+Row', 'AR(1)xAR(1)+Row+Col', 'Row+Col', 'AR(1)Row+Col', 'AR(1)Col+Row');
    my @germplasm_data;
    my @germplasm_data_ggcorr_header = ('2Dspline', 'AR(1)xAR(1)', 'AR(1)xAR(1)+Col', 'AR(1)xAR(1)+Row', 'AR(1)xAR(1)+Row+Col', 'Row+Col', 'AR(1)Row+Col', 'AR(1)Col+Row');
    my @germplasm_data_ggcorr;
    foreach my $a (@accession_names) {
        my $val0 = $result_blup_data_s->{$a}->{$trait_name_string} || 'NA';
        my $val1 = $result_blup_data_ar1->{$a}->{$trait_name_string} || 'NA';
        my $val2 = $result_blup_data_ar1wCol->{$a}->{$trait_name_string} || 'NA';
        my $val3 = $result_blup_data_ar1wRow->{$a}->{$trait_name_string} || 'NA';
        my $val4 = $result_blup_data_ar1wRowCol->{$a}->{$trait_name_string} || 'NA';
        my $val5 = $result_blup_data_ar1wRowColOnly->{$a}->{$trait_name_string} || 'NA';
        my $val6 = $result_blup_data_ar1wRowPlusCol->{$a}->{$trait_name_string} || 'NA';
        my $val7 = $result_blup_data_ar1wColPlusRow->{$a}->{$trait_name_string} || 'NA';
        push @germplasm_data, [$a, $val0, $val1, $val2, $val3, $val4, $val5, $val6, $val7];
        push @germplasm_data_ggcorr, [$val0, $val1, $val2, $val3, $val4, $val5, $val6, $val7];
    }

    my $analytics_protocol_data_tempfile1 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $analytics_protocol_data_tempfile2 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $analytics_protocol_data_tempfile3 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

    my $analytics_protocol_tempfile_string_1 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
    $analytics_protocol_tempfile_string_1 .= '.png';
    my $analytics_protocol_figure_tempfile_1 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_1;

    my $analytics_protocol_tempfile_string_2 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
    $analytics_protocol_tempfile_string_2 .= '.png';
    my $analytics_protocol_figure_tempfile_2 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_2;

    my $analytics_protocol_tempfile_string_3 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
    $analytics_protocol_tempfile_string_3 .= '.png';
    my $analytics_protocol_figure_tempfile_3 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_3;

    open(my $F1, ">", $analytics_protocol_data_tempfile1) || die "Can't open file ".$analytics_protocol_data_tempfile1;
        my $header_string1 = join ',', @plots_avg_data_heatmap_values_header;
        print $F1 "$header_string1\n";

        foreach (@plots_avg_data_heatmap_values) {
            my $string = join ',', @$_;
            print $F1 "$string\n";
        }
    close($F1);

    open(my $F2, ">", $analytics_protocol_data_tempfile2) || die "Can't open file ".$analytics_protocol_data_tempfile2;
        my $header_string2 = join ',', @type_names_plot;
        print $F2 "$header_string2\n";

        foreach (@plots_avg_data_ggcor_values) {
            my $string = join ',', @$_;
            print $F2 "$string\n";
        }
    close($F2);

    open(my $F3, ">", $analytics_protocol_data_tempfile3) || die "Can't open file ".$analytics_protocol_data_tempfile3;
        my $header_string3 = join ',', @germplasm_data_ggcorr_header;
        print $F3 "$header_string3\n";

        foreach (@germplasm_data_ggcorr) {
            my $string = join ',', @$_;
            print $F3 "$string\n";
        }
    close($F3);

    my $output_plot_row = 'row';
    my $output_plot_col = 'col';
    if ($max_col > $max_row) {
        $output_plot_row = 'col';
        $output_plot_col = 'row';
    }

    my $type_list_string = join '\',\'', @type_names_plot;
    my $number_types = scalar(@type_names_plot);
    my $r_cmd_i1 = 'R -e "library(data.table); library(ggplot2); library(dplyr); library(viridis); library(GGally); library(gridExtra);
    pheno_mat <- data.frame(fread(\''.$analytics_protocol_data_tempfile1.'\', header=TRUE, sep=\',\'));
    type_list <- c(\''.$type_list_string.'\');
    pheno_mat\$trait_type <- factor(pheno_mat\$trait_type, levels = type_list);
    lapply(type_list, function(cc) { gg <- ggplot(filter(pheno_mat, trait_type==cc), aes('.$output_plot_col.', '.$output_plot_row.', fill=value, frame=trait_type)) + geom_tile() + scale_fill_viridis(discrete=FALSE) + coord_equal() + labs(x=NULL, y=NULL, title=sprintf(\'%s\', cc)); }) -> cclist;
    cclist[[\'ncol\']] <- '.$number_types.';
    gg <- do.call(grid.arrange, cclist);
    ggsave(\''.$analytics_protocol_figure_tempfile_1.'\', gg, device=\'png\', width=30, height=30, units=\'in\');
    "';
    print STDERR Dumper $r_cmd_i1;
    my $status_i1 = system($r_cmd_i1);

    my $r_cmd_ic2 = 'R -e "library(ggplot2); library(data.table); library(GGally);
    data <- data.frame(fread(\''.$analytics_protocol_data_tempfile2.'\', header=TRUE, sep=\',\'));
    plot <- ggcorr(data, hjust = 1, size = 3, color = \'grey50\', label = TRUE, label_size = 3, label_round = 2, layout.exp = 1);
    ggsave(\''.$analytics_protocol_figure_tempfile_2.'\', plot, device=\'png\', width=10, height=10, units=\'in\');
    "';
    print STDERR Dumper $r_cmd_ic2;
    my $status_ic2 = system($r_cmd_ic2);

    my $r_cmd_ic3 = 'R -e "library(ggplot2); library(data.table); library(GGally);
    data <- data.frame(fread(\''.$analytics_protocol_data_tempfile3.'\', header=TRUE, sep=\',\'));
    plot <- ggcorr(data, hjust = 1, size = 3, color = \'grey50\', label = TRUE, label_size = 3, label_round = 2, layout.exp = 1);
    ggsave(\''.$analytics_protocol_figure_tempfile_3.'\', plot, device=\'png\', width=10, height=10, units=\'in\');
    "';
    print STDERR Dumper $r_cmd_ic3;
    my $status_ic3 = system($r_cmd_ic3);

    $c->stash->{rest} = {
        heatmap_plot => $analytics_protocol_tempfile_string_1,
        ggcorr_plot => $analytics_protocol_tempfile_string_2,
        germplasm_data_header => \@germplasm_data_header,
        germplasm_data => \@germplasm_data,
        germplasm_ggcorr_plot => $analytics_protocol_tempfile_string_3
    };
}

sub analytics_protocols_compare_to_trait :Path('/ajax/analytics_protocols_compare_to_trait') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    print STDERR Dumper $c->req->params();
    my $protocol_id = $c->req->param('protocol_id');
    my $trait_id = $c->req->param('trait_id');
    my @traits_secondary_id = $c->req->param('traits_secondary') ? split(',', $c->req->param('traits_secondary')) : ();
    my $trial_id = $c->req->param('trial_id');
    my $analysis_run_type = $c->req->param('analysis');
    my $default_tol = $c->req->param('default_tol');
    my $cor_label_size = $c->req->param('cor_label_size');
    my $cor_label_digits = $c->req->param('cor_label_digits');
    my ($user_id, $user_name, $user_role) = _check_user_login_analytics($c, 'submitter', 0, 0);

    my $csv = Text::CSV->new({ sep_char => "," });
    my $dir = $c->tempfiles_subdir('/analytics_protocol_figure');

    my $protocolprop_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analytics_protocol_properties', 'protocol_property')->cvterm_id();
    my $protocolprop_results_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analytics_protocol_result_summary', 'protocol_property')->cvterm_id();
    my $analytics_experiment_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analytics_protocol_experiment', 'experiment_type')->cvterm_id();

    my $q0 = "SELECT nd_protocol.nd_protocol_id, nd_protocol.name, nd_protocol.type_id, nd_protocol.description, nd_protocol.create_date, properties.value, results.value
        FROM nd_protocol
        JOIN nd_protocolprop AS properties ON(properties.nd_protocol_id=nd_protocol.nd_protocol_id AND properties.type_id=$protocolprop_type_cvterm_id)
        JOIN nd_protocolprop AS results ON(results.nd_protocol_id=nd_protocol.nd_protocol_id AND results.type_id=$protocolprop_results_type_cvterm_id)
        WHERE nd_protocol.nd_protocol_id = ?;";
    my $h0 = $schema->storage->dbh()->prepare($q0);
    $h0->execute($protocol_id);
    my ($nd_protocol_id, $name, $type_id, $description, $create_date, $props_json, $result_props_json) = $h0->fetchrow_array();
    $h0 = undef;

    if (!$name) {
        $c->stash->{rest} = { error => "There is no protocol with that ID!"};
        return;
    }

    my $result_props_json_array = $result_props_json ? decode_json $result_props_json : [];
    # print STDERR Dumper $result_props_json_array;
    my %trait_name_map;
    my %trait_name_map_reverse;
    foreach my $a (@$result_props_json_array) {
        my $trait_name_encoder = $a->{trait_name_map};
        print STDERR Dumper $trait_name_encoder;
        while (my ($k,$v) = each %$trait_name_encoder) {
            if (looks_like_number($k)) {
                #'181' => 't3',
                $trait_name_map{$v} = $k;
                $trait_name_map_reverse{$k} = $v;
            }
            else {
                #'Mean Pixel Value|Merged 3 Bands NRN|NDVI Vegetative Index Image|day 181|COMP:0000618' => 't3',
                my @t_comps = split '\|', $k;
                my $time_term = $t_comps[3];
                my ($day, $time) = split ' ', $time_term;
                $trait_name_map{$v} = $time;
                $trait_name_map_reverse{$time} = $v;
            }
        }
    }
    print STDERR Dumper \%trait_name_map;

    my $protocol_properties = decode_json $props_json;
    my $observation_variable_id_list = $protocol_properties->{observation_variable_id_list};
    my $observation_variable_number = scalar(@$observation_variable_id_list);
    my $legendre_poly_number = $protocol_properties->{legendre_order_number} || 3;
    my $analytics_select = $protocol_properties->{analytics_select};
    my $compute_relationship_matrix_from_htp_phenotypes = $protocol_properties->{relationship_matrix_type};
    my $compute_relationship_matrix_from_htp_phenotypes_type = $protocol_properties->{htp_pheno_rel_matrix_type};
    my $compute_relationship_matrix_from_htp_phenotypes_time_points = $protocol_properties->{htp_pheno_rel_matrix_time_points};
    my $compute_relationship_matrix_from_htp_phenotypes_blues_inversion = $protocol_properties->{htp_pheno_rel_matrix_blues_inversion};
    my $compute_from_parents = $protocol_properties->{genotype_compute_from_parents};
    my $include_pedgiree_info_if_compute_from_parents = $protocol_properties->{include_pedgiree_info_if_compute_from_parents};
    my $use_parental_grms_if_compute_from_parents = $protocol_properties->{use_parental_grms_if_compute_from_parents};
    my $use_area_under_curve = $protocol_properties->{use_area_under_curve};
    my $genotyping_protocol_id = $protocol_properties->{genotyping_protocol_id};
    my $tolparinv = $protocol_properties->{tolparinv};
    my $permanent_environment_structure = $protocol_properties->{permanent_environment_structure};
    my $permanent_environment_structure_phenotype_correlation_traits = $protocol_properties->{permanent_environment_structure_phenotype_correlation_traits};
    my $permanent_environment_structure_phenotype_trait_ids = $protocol_properties->{permanent_environment_structure_phenotype_trait_ids};
    my @env_variance_percents = split ',', $protocol_properties->{env_variance_percent};
    my $number_iterations = $protocol_properties->{number_iterations};
    my $simulated_environment_real_data_trait_id = $protocol_properties->{simulated_environment_real_data_trait_id};
    my $correlation_between_times = $protocol_properties->{sim_env_change_over_time_correlation} || 0.9;
    my $fixed_effect_type = $protocol_properties->{fixed_effect_type} || 'replicate';
    my $fixed_effect_trait_id = $protocol_properties->{fixed_effect_trait_id};
    my $fixed_effect_quantiles = $protocol_properties->{fixed_effect_quantiles};
    my $env_iterations = $protocol_properties->{env_iterations};
    my $perform_cv = $protocol_properties->{perform_cv} || 0;

    if ($default_tol eq 'default_both' || $default_tol eq 'pre_ar1_def_2dspl') {
        $tolparinv = 0.000001;
    }
    my $tolparinv_10 = $tolparinv*10;

    if ($default_tol eq 'large_tol') {
        $tolparinv = 10;
        $tolparinv_10 = 10;
    }

    my @legendre_coeff_exec = (
        '1 * $b',
        '($time**1)*$b',
        '($time**2)*$b',
        '($time**3)*$b',
        '($time**4)*$b',
        '($time**5)*$b',
        '($time**6)*$b'
    );

    my $r0_gdd = 1225;
    my $r1_gdd = 1800;
    my $r2_gdd = 3000;

    my $field_trial_id_list = [$trial_id];
    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$schema,
            data_level=>'plot',
            trait_list=>[$trait_id],
            trial_list=>$field_trial_id_list,
            include_timestamp=>0,
            exclude_phenotype_outlier=>0
        }
    );
    my ($data, $unique_traits) = $phenotypes_search->search();
    my @sorted_trait_names = sort keys %$unique_traits;

    if (scalar(@$data) == 0) {
        $c->stash->{rest} = { error => "There are no phenotypes for the trials and trait you have selected!"};
        return;
    }

    my %germplasm_phenotypes;
    my %plot_phenotypes;
    my %seen_accession_stock_ids;
    my %seen_days_after_plantings;
    my %stock_name_row_col;
    my %stock_info;
    my %plot_id_map;
    my %plot_germplasm_map;
    my $min_phenotype = 1000000000000000;
    my $max_phenotype = -1000000000000000;
    my $min_col = 100000000000000;
    my $max_col = -100000000000000;
    my $min_row = 100000000000000;
    my $max_row = -100000000000000;
    my $min_rep = 100000000000000;
    my $max_rep = -100000000000000;
    foreach my $obs_unit (@$data){
        my $germplasm_name = $obs_unit->{germplasm_uniquename};
        my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
        my $replicate_number = $obs_unit->{obsunit_rep} || '';
        my $block_number = $obs_unit->{obsunit_block} || '';
        my $obsunit_stock_id = $obs_unit->{observationunit_stock_id};
        my $obsunit_stock_uniquename = $obs_unit->{observationunit_uniquename};
        my $row_number = $obs_unit->{obsunit_row_number} || '';
        my $col_number = $obs_unit->{obsunit_col_number} || '';

        my $observations = $obs_unit->{observations};
        foreach (@$observations){
            my $value = $_->{value};
            my $trait_name = $_->{trait_name};

            if ($value < $min_phenotype) {
                $min_phenotype = $value;
            }
            if ($value > $max_phenotype) {
                $max_phenotype = $value;
            }

            push @{$germplasm_phenotypes{$germplasm_name}->{$trait_name}}, $value;
            $plot_phenotypes{$obsunit_stock_uniquename}->{$trait_name} = $value;

            if ($_->{associated_image_project_time_json}) {
                my $related_time_terms_json = decode_json $_->{associated_image_project_time_json};
                my $time_days_cvterm = $related_time_terms_json->{day};
                my $time_term_string = $time_days_cvterm;
                my $time_days = (split '\|', $time_days_cvterm)[0];
                my $time_value = (split ' ', $time_days)[1];
                $seen_days_after_plantings{$time_value}++;
            }
        }
    }

    my %germplasm_phenotypes_secondary;
    my %plot_phenotypes_secondary;
    my %plot_phenotypes_secondary_cutoff_data;
    my $min_phenotype_secondary = 1000000000000000;
    my $max_phenotype_secondary = -1000000000000000;
    my @sorted_trait_names_secondary;
    my $number_secondary_traits = scalar(@traits_secondary_id);
    if (scalar(@traits_secondary_id)>0) {
        my $phenotypes_search_secondary = CXGN::Phenotypes::SearchFactory->instantiate(
            'MaterializedViewTable',
            {
                bcs_schema=>$schema,
                data_level=>'plot',
                trait_list=>\@traits_secondary_id,
                trial_list=>$field_trial_id_list,
                include_timestamp=>0,
                exclude_phenotype_outlier=>0
            }
        );
        my ($data_secondary, $unique_traits_secondary) = $phenotypes_search_secondary->search();
        @sorted_trait_names_secondary = sort keys %$unique_traits_secondary;

        if (scalar(@$data_secondary) == 0) {
            $c->stash->{rest} = { error => "There are no phenotypes for the trials and secondary trait you have selected!"};
            return;
        }

        foreach my $obs_unit (@$data_secondary){
            my $germplasm_name = $obs_unit->{germplasm_uniquename};
            my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
            my $replicate_number = $obs_unit->{obsunit_rep} || '';
            my $block_number = $obs_unit->{obsunit_block} || '';
            my $obsunit_stock_id = $obs_unit->{observationunit_stock_id};
            my $obsunit_stock_uniquename = $obs_unit->{observationunit_uniquename};
            my $row_number = $obs_unit->{obsunit_row_number} || '';
            my $col_number = $obs_unit->{obsunit_col_number} || '';

            my $observations = $obs_unit->{observations};
            foreach (@$observations){
                my $value = $_->{value};
                my $trait_name = $_->{trait_name};

                if ($value < $min_phenotype_secondary) {
                    $min_phenotype_secondary = $value;
                }
                if ($value > $max_phenotype_secondary) {
                    $max_phenotype_secondary = $value;
                }

                push @{$germplasm_phenotypes_secondary{$germplasm_name}->{$trait_name}}, $value;
                $plot_phenotypes_secondary{$obsunit_stock_uniquename}->{$trait_name} = $value;
                push @{$plot_phenotypes_secondary_cutoff_data{$trait_name}->{data}}, $value;
            }
        }
    }

    while (my($t,$vals) = each %plot_phenotypes_secondary_cutoff_data) {
        my $stat = Statistics::Descriptive::Full->new();
        $stat->add_data(@{$vals->{data}});
        my $cutoff_25 = $stat->quantile(1);
        my $cutoff_50 = $stat->quantile(2);
        my $cutoff_75 = $stat->quantile(3);
        $plot_phenotypes_secondary_cutoff_data{$t}->{cutoffs} = [$cutoff_25, $cutoff_50, $cutoff_75];
    }

    my $phenotypes_search_htp = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$schema,
            data_level=>'plot',
            trait_list=>$observation_variable_id_list,
            trial_list=>$field_trial_id_list,
            include_timestamp=>0,
            exclude_phenotype_outlier=>0
        }
    );
    my ($data_htp, $unique_traits_htp) = $phenotypes_search_htp->search();
    my @sorted_trait_names_htp = sort keys %$unique_traits_htp;

    if (scalar(@$data_htp) == 0) {
        $c->stash->{rest} = { error => "There are no htp phenotypes for the trials and traits you have selected!"};
        return;
    }

    my $min_phenotype_htp = 1000000000000000;
    my $max_phenotype_htp = -1000000000000000;
    my $min_time_htp = 1000000000000000;
    my $max_time_htp = -1000000000000000;
    my %plot_phenotypes_htp;
    my %dap_to_gdd_hash;
    my %seen_days_after_plantings_htp;
    my %plot_row_col_hash;
    my %seen_reps_hash;
    foreach my $obs_unit (@$data_htp){
        my $germplasm_name = $obs_unit->{germplasm_uniquename};
        my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
        my $replicate_number = $obs_unit->{obsunit_rep} || '';
        my $block_number = $obs_unit->{obsunit_block} || '';
        my $obsunit_stock_id = $obs_unit->{observationunit_stock_id};
        my $obsunit_stock_uniquename = $obs_unit->{observationunit_uniquename};
        my $row_number = $obs_unit->{obsunit_row_number} || '';
        my $col_number = $obs_unit->{obsunit_col_number} || '';

        $seen_accession_stock_ids{$germplasm_stock_id}++;
        $plot_id_map{$obsunit_stock_id} = $obsunit_stock_uniquename;
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
        $plot_germplasm_map{$obsunit_stock_uniquename} = $germplasm_name;

        $stock_info{"S".$germplasm_stock_id} = {
            uniquename => $germplasm_name
        };

        $plot_row_col_hash{$row_number}->{$col_number} = {
            obsunit_stock_id => $obsunit_stock_id,
            obsunit_name => $obsunit_stock_uniquename
        };

        if ($replicate_number < $min_rep) {
            $min_rep = $replicate_number;
        }
        if ($replicate_number > $max_rep) {
            $max_rep = $replicate_number;
        }
        $seen_reps_hash{$replicate_number}++;

        if ($row_number < $min_row) {
            $min_row = $row_number;
        }
        if ($row_number > $max_row) {
            $max_row = $row_number;
        }
        if ($col_number < $min_col) {
            $min_col = $col_number;
        }
        if ($col_number > $max_col) {
            $max_col = $col_number;
        }

        my $observations = $obs_unit->{observations};
        foreach (@$observations){
            my $value = $_->{value};
            my $trait_name = $_->{trait_name};

            if ($value < $min_phenotype_htp) {
                $min_phenotype_htp = $value;
            }
            if ($value > $max_phenotype_htp) {
                $max_phenotype_htp = $value;
            }

            $plot_phenotypes_htp{$obsunit_stock_uniquename}->{$trait_name} = $value;

            if ($_->{associated_image_project_time_json}) {
                my $related_time_terms_json = decode_json $_->{associated_image_project_time_json};
                my $time_days_cvterm = $related_time_terms_json->{day};
                my $time_term_string = $time_days_cvterm;
                my $time_days = (split '\|', $time_days_cvterm)[0];
                my $time_value = (split ' ', $time_days)[1];
                $seen_days_after_plantings_htp{$time_value}++;

                if ($time_value < $min_time_htp) {
                    $min_time_htp = $time_value;
                }
                if ($time_value > $max_time_htp) {
                    $max_time_htp = $time_value;
                }

                my $gdd_value = $related_time_terms_json->{gdd_average_temp} + 0;
                $dap_to_gdd_hash{$time_value} = $gdd_value;
            }
        }
    }
    my @seen_plots = sort keys %plot_phenotypes_htp;
    my @seen_germplasm = sort keys %germplasm_phenotypes;
    my @accession_ids = sort keys %seen_accession_stock_ids;

    my $max_row_half = round($max_row/2);
    my $max_col_half = round($max_col/2);
    print STDERR Dumper [$max_row_half, $max_col_half];

    my $grm_file;
    # Prepare GRM for 2Dspl Trait Spatial Correction
    eval {
        print STDERR Dumper [$compute_relationship_matrix_from_htp_phenotypes, $include_pedgiree_info_if_compute_from_parents, $use_parental_grms_if_compute_from_parents, $compute_from_parents];
        if ($compute_relationship_matrix_from_htp_phenotypes eq 'genotypes') {

            if ($include_pedgiree_info_if_compute_from_parents) {
                my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
                my $tmp_arm_dir = $shared_cluster_dir_config."/tmp_download_arm";
                mkdir $tmp_arm_dir if ! -d $tmp_arm_dir;
                my ($arm_tempfile_fh, $arm_tempfile) = tempfile("drone_stats_download_arm_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm1_tempfile_fh, $grm1_tempfile) = tempfile("drone_stats_download_grm1_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_temp_tempfile_fh, $grm_out_temp_tempfile) = tempfile("drone_stats_download_grm_temp_out_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_posdef_tempfile_fh, $grm_out_posdef_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);

                if (!$genotyping_protocol_id) {
                    $genotyping_protocol_id = undef;
                }

                my $pedigree_arm = CXGN::Pedigree::ARM->new({
                    bcs_schema=>$schema,
                    arm_temp_file=>$arm_tempfile,
                    people_schema=>$people_schema,
                    accession_id_list=>\@accession_ids,
                    # plot_id_list=>\@plot_id_list,
                    cache_root=>$c->config->{cache_file_path},
                    download_format=>'matrix', #either 'matrix', 'three_column', or 'heatmap'
                });
                my ($parent_hash, $stock_ids, $all_accession_stock_ids, $female_stock_ids, $male_stock_ids) = $pedigree_arm->get_arm(
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                # print STDERR Dumper $parent_hash;

                my $female_geno = CXGN::Genotype::GRM->new({
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm1_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>$female_stock_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>0,
                    download_format=>'three_column_reciprocal',
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                });
                my $female_grm_data = $female_geno->download_grm(
                    'data',
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                my @fl = split '\n', $female_grm_data;
                my %female_parent_grm;
                foreach (@fl) {
                    my @l = split '\t', $_;
                    $female_parent_grm{$l[0]}->{$l[1]} = $l[2];
                }
                # print STDERR Dumper \%female_parent_grm;

                my $male_geno = CXGN::Genotype::GRM->new({
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm1_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>$male_stock_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>0,
                    download_format=>'three_column_reciprocal',
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                });
                my $male_grm_data = $male_geno->download_grm(
                    'data',
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                my @ml = split '\n', $male_grm_data;
                my %male_parent_grm;
                foreach (@ml) {
                    my @l = split '\t', $_;
                    $male_parent_grm{$l[0]}->{$l[1]} = $l[2];
                }
                # print STDERR Dumper \%male_parent_grm;

                my %rel_result_hash;
                foreach my $a1 (@accession_ids) {
                    foreach my $a2 (@accession_ids) {
                        my $female_parent1 = $parent_hash->{$a1}->{female_stock_id};
                        my $male_parent1 = $parent_hash->{$a1}->{male_stock_id};
                        my $female_parent2 = $parent_hash->{$a2}->{female_stock_id};
                        my $male_parent2 = $parent_hash->{$a2}->{male_stock_id};

                        my $female_rel = 0;
                        if ($female_parent1 && $female_parent2 && $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2}) {
                            $female_rel = $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2};
                        }
                        elsif ($female_parent1 && $female_parent2 && $female_parent1 == $female_parent2) {
                            $female_rel = 1;
                        }
                        elsif ($a1 == $a2) {
                            $female_rel = 1;
                        }

                        my $male_rel = 0;
                        if ($male_parent1 && $male_parent2 && $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2}) {
                            $male_rel = $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2};
                        }
                        elsif ($male_parent1 && $male_parent2 && $male_parent1 == $male_parent2) {
                            $male_rel = 1;
                        }
                        elsif ($a1 == $a2) {
                            $male_rel = 1;
                        }
                        # print STDERR "$a1 $a2 $female_rel $male_rel\n";

                        my $rel = 0.5*($female_rel + $male_rel);
                        $rel_result_hash{$a1}->{$a2} = $rel;
                    }
                }
                # print STDERR Dumper \%rel_result_hash;

                my $data = '';
                my %result_hash;
                foreach my $s (sort @accession_ids) {
                    foreach my $c (sort @accession_ids) {
                        if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                            my $val = $rel_result_hash{$s}->{$c};
                            if (defined $val and length $val) {
                                $result_hash{$s}->{$c} = $val;
                                $data .= "S$s\tS$c\t$val\n";
                            }
                        }
                    }
                }

                # print STDERR Dumper $data;
                open(my $F2, ">", $grm_out_temp_tempfile) || die "Can't open file ".$grm_out_temp_tempfile;
                    print $F2 $data;
                close($F2);

                my $cmd = 'R -e "library(data.table); library(scales); library(tidyr); library(reshape2);
                three_col <- fread(\''.$grm_out_temp_tempfile.'\', header=FALSE, sep=\'\t\');
                A_wide <- dcast(three_col, V1~V2, value.var=\'V3\');
                A_1 <- A_wide[,-1];
                A_1[is.na(A_1)] <- 0;
                A <- A_1 + t(A_1);
                diag(A) <- diag(as.matrix(A_1));
                E = eigen(A);
                ev = E\$values;
                U = E\$vectors;
                no = dim(A)[1];
                nev = which(ev < 0);
                wr = 0;
                k=length(nev);
                if(k > 0){
                    p = ev[no - k];
                    B = sum(ev[nev])*2.0;
                    wr = (B*B*100.0)+1;
                    val = ev[nev];
                    ev[nev] = p*(B-val)*(B-val)/wr;
                    A = U%*%diag(ev)%*%t(U);
                }
                A <- as.data.frame(A);
                colnames(A) <- A_wide[,1];
                A\$stock_id <- A_wide[,1];
                A_threecol <- melt(A, id.vars = c(\'stock_id\'), measure.vars = A_wide[,1]);
                A_threecol\$stock_id <- substring(A_threecol\$stock_id, 2);
                A_threecol\$variable <- substring(A_threecol\$variable, 2);
                write.table(data.frame(variable = A_threecol\$variable, stock_id = A_threecol\$stock_id, value = A_threecol\$value), file=\''.$grm_out_tempfile.'\', row.names=FALSE, col.names=FALSE, sep=\'\t\');"';
                print STDERR $cmd."\n";
                my $status = system($cmd);

                my %rel_pos_def_result_hash;
                open(my $F3, '<', $grm_out_tempfile)
                    or die "Could not open file '$grm_out_tempfile' $!";

                    print STDERR "Opened $grm_out_tempfile\n";

                    while (my $row = <$F3>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        my $stock_id1 = $columns[0];
                        my $stock_id2 = $columns[1];
                        my $val = $columns[2];
                        $rel_pos_def_result_hash{$stock_id1}->{$stock_id2} = $val;
                    }
                close($F3);

                my $data_pos_def = '';
                %result_hash = ();
                foreach my $s (sort @accession_ids) {
                    foreach my $c (sort @accession_ids) {
                        if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                            my $val = $rel_pos_def_result_hash{$s}->{$c};
                            if (defined $val and length $val) {
                                $result_hash{$s}->{$c} = $val;
                                $result_hash{$c}->{$s} = $val;
                                $data_pos_def .= "S$s\tS$c\t$val\n";
                                if ($s != $c) {
                                    $data_pos_def .= "S$c\tS$s\t$val\n";
                                }
                            }
                        }
                    }
                }

                open(my $F4, ">", $grm_out_posdef_tempfile) || die "Can't open file ".$grm_out_posdef_tempfile;
                    print $F4 $data_pos_def;
                close($F4);

                $grm_file = $grm_out_posdef_tempfile;
            }
            elsif ($use_parental_grms_if_compute_from_parents) {
                my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
                my $tmp_arm_dir = $shared_cluster_dir_config."/tmp_download_arm";
                mkdir $tmp_arm_dir if ! -d $tmp_arm_dir;
                my ($arm_tempfile_fh, $arm_tempfile) = tempfile("drone_stats_download_arm_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm1_tempfile_fh, $grm1_tempfile) = tempfile("drone_stats_download_grm1_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_temp_tempfile_fh, $grm_out_temp_tempfile) = tempfile("drone_stats_download_grm_temp_out_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);
                my ($grm_out_posdef_tempfile_fh, $grm_out_posdef_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);

                if (!$genotyping_protocol_id) {
                    $genotyping_protocol_id = undef;
                }

                my $pedigree_arm = CXGN::Pedigree::ARM->new({
                    bcs_schema=>$schema,
                    arm_temp_file=>$arm_tempfile,
                    people_schema=>$people_schema,
                    accession_id_list=>\@accession_ids,
                    # plot_id_list=>\@plot_id_list,
                    cache_root=>$c->config->{cache_file_path},
                    download_format=>'matrix', #either 'matrix', 'three_column', or 'heatmap'
                });
                my ($parent_hash, $stock_ids, $all_accession_stock_ids, $female_stock_ids, $male_stock_ids) = $pedigree_arm->get_arm(
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                # print STDERR Dumper $parent_hash;

                my $female_geno = CXGN::Genotype::GRM->new({
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm1_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>$female_stock_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>0,
                    download_format=>'three_column_reciprocal',
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                });
                my $female_grm_data = $female_geno->download_grm(
                    'data',
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                my @fl = split '\n', $female_grm_data;
                my %female_parent_grm;
                foreach (@fl) {
                    my @l = split '\t', $_;
                    $female_parent_grm{$l[0]}->{$l[1]} = $l[2];
                }
                # print STDERR Dumper \%female_parent_grm;

                my $male_geno = CXGN::Genotype::GRM->new({
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm1_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>$male_stock_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>0,
                    download_format=>'three_column_reciprocal',
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                });
                my $male_grm_data = $male_geno->download_grm(
                    'data',
                    $shared_cluster_dir_config,
                    $c->config->{backend},
                    $c->config->{cluster_host},
                    $c->config->{'web_cluster_queue'},
                    $c->config->{basepath}
                );
                my @ml = split '\n', $male_grm_data;
                my %male_parent_grm;
                foreach (@ml) {
                    my @l = split '\t', $_;
                    $male_parent_grm{$l[0]}->{$l[1]} = $l[2];
                }
                # print STDERR Dumper \%male_parent_grm;

                my %rel_result_hash;
                foreach my $a1 (@accession_ids) {
                    foreach my $a2 (@accession_ids) {
                        my $female_parent1 = $parent_hash->{$a1}->{female_stock_id};
                        my $male_parent1 = $parent_hash->{$a1}->{male_stock_id};
                        my $female_parent2 = $parent_hash->{$a2}->{female_stock_id};
                        my $male_parent2 = $parent_hash->{$a2}->{male_stock_id};

                        my $female_rel = 0;
                        if ($female_parent1 && $female_parent2 && $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2}) {
                            $female_rel = $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2};
                        }
                        elsif ($a1 == $a2) {
                            $female_rel = 1;
                        }

                        my $male_rel = 0;
                        if ($male_parent1 && $male_parent2 && $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2}) {
                            $male_rel = $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2};
                        }
                        elsif ($a1 == $a2) {
                            $male_rel = 1;
                        }
                        # print STDERR "$a1 $a2 $female_rel $male_rel\n";

                        my $rel = 0.5*($female_rel + $male_rel);
                        $rel_result_hash{$a1}->{$a2} = $rel;
                    }
                }
                # print STDERR Dumper \%rel_result_hash;

                my $data = '';
                my %result_hash;
                foreach my $s (sort @accession_ids) {
                    foreach my $c (sort @accession_ids) {
                        if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                            my $val = $rel_result_hash{$s}->{$c};
                            if (defined $val and length $val) {
                                $result_hash{$s}->{$c} = $val;
                                $data .= "S$s\tS$c\t$val\n";
                            }
                        }
                    }
                }

                # print STDERR Dumper $data;
                open(my $F2, ">", $grm_out_temp_tempfile) || die "Can't open file ".$grm_out_temp_tempfile;
                    print $F2 $data;
                close($F2);

                my $cmd = 'R -e "library(data.table); library(scales); library(tidyr); library(reshape2);
                three_col <- fread(\''.$grm_out_temp_tempfile.'\', header=FALSE, sep=\'\t\');
                A_wide <- dcast(three_col, V1~V2, value.var=\'V3\');
                A_1 <- A_wide[,-1];
                A_1[is.na(A_1)] <- 0;
                A <- A_1 + t(A_1);
                diag(A) <- diag(as.matrix(A_1));
                E = eigen(A);
                ev = E\$values;
                U = E\$vectors;
                no = dim(A)[1];
                nev = which(ev < 0);
                wr = 0;
                k=length(nev);
                if(k > 0){
                    p = ev[no - k];
                    B = sum(ev[nev])*2.0;
                    wr = (B*B*100.0)+1;
                    val = ev[nev];
                    ev[nev] = p*(B-val)*(B-val)/wr;
                    A = U%*%diag(ev)%*%t(U);
                }
                A <- as.data.frame(A);
                colnames(A) <- A_wide[,1];
                A\$stock_id <- A_wide[,1];
                A_threecol <- melt(A, id.vars = c(\'stock_id\'), measure.vars = A_wide[,1]);
                A_threecol\$stock_id <- substring(A_threecol\$stock_id, 2);
                A_threecol\$variable <- substring(A_threecol\$variable, 2);
                write.table(data.frame(variable = A_threecol\$variable, stock_id = A_threecol\$stock_id, value = A_threecol\$value), file=\''.$grm_out_tempfile.'\', row.names=FALSE, col.names=FALSE, sep=\'\t\');"';
                print STDERR $cmd."\n";
                my $status = system($cmd);

                my %rel_pos_def_result_hash;
                open(my $F3, '<', $grm_out_tempfile) or die "Could not open file '$grm_out_tempfile' $!";
                    print STDERR "Opened $grm_out_tempfile\n";

                    while (my $row = <$F3>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        my $stock_id1 = $columns[0];
                        my $stock_id2 = $columns[1];
                        my $val = $columns[2];
                        $rel_pos_def_result_hash{$stock_id1}->{$stock_id2} = $val;
                    }
                close($F3);

                my $data_pos_def = '';
                %result_hash = ();
                foreach my $s (sort @accession_ids) {
                    foreach my $c (sort @accession_ids) {
                        if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                            my $val = $rel_pos_def_result_hash{$s}->{$c};
                            if (defined $val and length $val) {
                                $result_hash{$s}->{$c} = $val;
                                $result_hash{$c}->{$s} = $val;
                                $data_pos_def .= "S$s\tS$c\t$val\n";
                                if ($s != $c) {
                                    $data_pos_def .= "S$c\tS$s\t$val\n";
                                }
                            }
                        }
                    }
                }

                open(my $F4, ">", $grm_out_posdef_tempfile) || die "Can't open file ".$grm_out_posdef_tempfile;
                    print $F4 $data_pos_def;
                close($F4);

                $grm_file = $grm_out_posdef_tempfile;
            }
            else {
                my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
                my $tmp_grm_dir = $shared_cluster_dir_config."/tmp_genotype_download_grm";
                mkdir $tmp_grm_dir if ! -d $tmp_grm_dir;
                my ($grm_tempfile_fh, $grm_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
                my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);

                if (!$genotyping_protocol_id) {
                    $genotyping_protocol_id = undef;
                }

                my $grm_search_params = {
                    bcs_schema=>$schema,
                    grm_temp_file=>$grm_tempfile,
                    people_schema=>$people_schema,
                    cache_root=>$c->config->{cache_file_path},
                    accession_id_list=>\@accession_ids,
                    protocol_id=>$genotyping_protocol_id,
                    get_grm_for_parental_accessions=>$compute_from_parents,
                    genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                    # minor_allele_frequency=>$minor_allele_frequency,
                    # marker_filter=>$marker_filter,
                    # individuals_filter=>$individuals_filter
                };
                $grm_search_params->{download_format} = 'three_column_reciprocal';

                my $geno = CXGN::Genotype::GRM->new($grm_search_params);
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
                $grm_file = $grm_out_tempfile;
            }

        }
        elsif ($compute_relationship_matrix_from_htp_phenotypes eq 'htp_phenotypes') {
            my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
            my $tmp_grm_dir = $shared_cluster_dir_config."/tmp_genotype_download_grm";
            mkdir $tmp_grm_dir if ! -d $tmp_grm_dir;
            my ($stats_out_htp_rel_tempfile_input_fh, $stats_out_htp_rel_tempfile_input) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
            my ($stats_out_htp_rel_tempfile_fh, $stats_out_htp_rel_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
            my ($stats_out_htp_rel_tempfile_out_fh, $stats_out_htp_rel_tempfile_out) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);

            my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
                'MaterializedViewTable',
                {
                    bcs_schema=>$schema,
                    data_level=>'plot',
                    trial_list=>$field_trial_id_list,
                    include_timestamp=>0,
                    exclude_phenotype_outlier=>0
                }
            );
            my ($data, $unique_traits) = $phenotypes_search->search();

            if (scalar(@$data) == 0) {
                $c->stash->{rest} = { error => "There are no phenotypes for the trial you have selected!"};
                return;
            }

            my $q_time = "SELECT t.cvterm_id FROM cvterm as t JOIN cv ON(t.cv_id=cv.cv_id) WHERE t.name=? and cv.name=?;";
            my $h_time = $schema->storage->dbh()->prepare($q_time);

            my %seen_plot_names_htp_rel;
            my %phenotype_data_htp_rel;
            my %seen_times_htp_rel;
            foreach my $obs_unit (@$data){
                my $germplasm_name = $obs_unit->{germplasm_uniquename};
                my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
                my $row_number = $obs_unit->{obsunit_row_number} || '';
                my $col_number = $obs_unit->{obsunit_col_number} || '';
                my $rep = $obs_unit->{obsunit_rep};
                my $block = $obs_unit->{obsunit_block};
                $seen_plot_names_htp_rel{$obs_unit->{observationunit_uniquename}} = $obs_unit;
                my $observations = $obs_unit->{observations};
                foreach (@$observations){
                    if ($_->{associated_image_project_time_json}) {
                        my $related_time_terms_json = decode_json $_->{associated_image_project_time_json};

                        my $time_days_cvterm = $related_time_terms_json->{day};
                        my $time_days_term_string = $time_days_cvterm;
                        my $time_days = (split '\|', $time_days_cvterm)[0];
                        my $time_days_value = (split ' ', $time_days)[1];

                        my $time_gdd_value = $related_time_terms_json->{gdd_average_temp} + 0;
                        my $gdd_term_string = "GDD $time_gdd_value";
                        $h_time->execute($gdd_term_string, 'cxgn_time_ontology');
                        my ($gdd_cvterm_id) = $h_time->fetchrow_array();
                        if (!$gdd_cvterm_id) {
                            my $new_gdd_term = $schema->resultset("Cv::Cvterm")->create_with({
                               name => $gdd_term_string,
                               cv => 'cxgn_time_ontology'
                            });
                            $gdd_cvterm_id = $new_gdd_term->cvterm_id();
                        }
                        my $time_gdd_term_string = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $gdd_cvterm_id, 'extended');

                        $phenotype_data_htp_rel{$obs_unit->{observationunit_uniquename}}->{$_->{trait_name}} = $_->{value};
                        $seen_times_htp_rel{$_->{trait_name}} = [$time_days_value, $time_days_term_string, $time_gdd_value, $time_gdd_term_string];
                    }
                }
            }
            $h_time = undef;

            my @allowed_standard_htp_values = ('Nonzero Pixel Count', 'Total Pixel Sum', 'Mean Pixel Value', 'Harmonic Mean Pixel Value', 'Median Pixel Value', 'Pixel Variance', 'Pixel Standard Deviation', 'Pixel Population Standard Deviation', 'Minimum Pixel Value', 'Maximum Pixel Value', 'Minority Pixel Value', 'Minority Pixel Count', 'Majority Pixel Value', 'Majority Pixel Count', 'Pixel Group Count');
            my %filtered_seen_times_htp_rel;
            while (my ($t, $time) = each %seen_times_htp_rel) {
                my $allowed = 0;
                foreach (@allowed_standard_htp_values) {
                    if (index($t, $_) != -1) {
                        $allowed = 1;
                        last;
                    }
                }
                if ($allowed) {
                    $filtered_seen_times_htp_rel{$t} = $time;
                }
            }

            my @seen_plot_names_htp_rel_sorted = sort keys %seen_plot_names_htp_rel;
            my @filtered_seen_times_htp_rel_sorted = sort keys %filtered_seen_times_htp_rel;

            my @header_htp = ('plot_id', 'plot_name', 'accession_id', 'accession_name', 'rep', 'block');

            my %trait_name_encoder_htp;
            my %trait_name_encoder_rev_htp;
            my $trait_name_encoded_htp = 1;
            my @header_traits_htp;
            foreach my $trait_name (@filtered_seen_times_htp_rel_sorted) {
                if (!exists($trait_name_encoder_htp{$trait_name})) {
                    my $trait_name_e = 't'.$trait_name_encoded_htp;
                    $trait_name_encoder_htp{$trait_name} = $trait_name_e;
                    $trait_name_encoder_rev_htp{$trait_name_e} = $trait_name;
                    push @header_traits_htp, $trait_name_e;
                    $trait_name_encoded_htp++;
                }
            }

            my @htp_pheno_matrix;
            if ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'all') {
                push @header_htp, @header_traits_htp;
                push @htp_pheno_matrix, \@header_htp;

                foreach my $p (@seen_plot_names_htp_rel_sorted) {
                    my $obj = $seen_plot_names_htp_rel{$p};
                    my @row = ($obj->{observationunit_stock_id}, $obj->{observationunit_uniquename}, $obj->{germplasm_stock_id}, $obj->{germplasm_uniquename}, $obj->{obsunit_rep}, $obj->{obsunit_block});
                    foreach my $t (@filtered_seen_times_htp_rel_sorted) {
                        my $val = $phenotype_data_htp_rel{$p}->{$t} + 0;
                        push @row, $val;
                    }
                    push @htp_pheno_matrix, \@row;
                }
            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'latest_trait') {
                my $max_day = 0;
                foreach (keys %seen_days_after_plantings) {
                    if ($_ + 0 > $max_day) {
                        $max_day = $_;
                    }
                }

                foreach my $t (@filtered_seen_times_htp_rel_sorted) {
                    my $day = $filtered_seen_times_htp_rel{$t}->[0];
                    if ($day <= $max_day) {
                        push @header_htp, $t;
                    }
                }
                push @htp_pheno_matrix, \@header_htp;

                foreach my $p (@seen_plot_names_htp_rel_sorted) {
                    my $obj = $seen_plot_names_htp_rel{$p};
                    my @row = ($obj->{observationunit_stock_id}, $obj->{observationunit_uniquename}, $obj->{germplasm_stock_id}, $obj->{germplasm_uniquename}, $obj->{obsunit_rep}, $obj->{obsunit_block});
                    foreach my $t (@filtered_seen_times_htp_rel_sorted) {
                        my $day = $filtered_seen_times_htp_rel{$t}->[0];
                        if ($day <= $max_day) {
                            my $val = $phenotype_data_htp_rel{$p}->{$t} + 0;
                            push @row, $val;
                        }
                    }
                    push @htp_pheno_matrix, \@row;
                }
            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'vegetative') {

            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'reproductive') {

            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'mature') {

            }
            else {
                $c->stash->{rest} = { error => "The value of $compute_relationship_matrix_from_htp_phenotypes_time_points htp_pheno_rel_matrix_time_points is not valid!" };
                return;
            }

            open(my $htp_pheno_f, ">", $stats_out_htp_rel_tempfile_input) || die "Can't open file ".$stats_out_htp_rel_tempfile_input;
                foreach (@htp_pheno_matrix) {
                    my $line = join "\t", @$_;
                    print $htp_pheno_f $line."\n";
                }
            close($htp_pheno_f);

            my %rel_htp_result_hash;
            if ($compute_relationship_matrix_from_htp_phenotypes_type eq 'correlations') {
                my $htp_cmd = 'R -e "library(lme4); library(data.table);
                mat <- fread(\''.$stats_out_htp_rel_tempfile_input.'\', header=TRUE, sep=\'\t\');
                mat_agg <- aggregate(mat[, 7:ncol(mat)], list(mat\$accession_id), mean);
                mat_pheno <- mat_agg[,2:ncol(mat_agg)];
                cor_mat <- cor(t(mat_pheno));
                rownames(cor_mat) <- mat_agg[,1];
                colnames(cor_mat) <- mat_agg[,1];
                range01 <- function(x){(x-min(x))/(max(x)-min(x))};
                cor_mat <- range01(cor_mat);
                write.table(cor_mat, file=\''.$stats_out_htp_rel_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');"';
                print STDERR Dumper $htp_cmd;
                my $status = system($htp_cmd);
            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes_type eq 'blues') {
                my $htp_cmd = 'R -e "library(lme4); library(data.table);
                mat <- fread(\''.$stats_out_htp_rel_tempfile_input.'\', header=TRUE, sep=\'\t\');
                blues <- data.frame(id = seq(1,length(unique(mat\$accession_id))));
                varlist <- names(mat)[7:ncol(mat)];
                blues.models <- lapply(varlist, function(x) {
                    tryCatch(
                        lmer(substitute(i ~ 1 + (1|accession_id), list(i = as.name(x))), data = mat, REML = FALSE, control = lmerControl(optimizer =\'Nelder_Mead\', boundary.tol='.$compute_relationship_matrix_from_htp_phenotypes_blues_inversion.' ) ), error=function(e) {}
                    )
                });
                counter = 1;
                for (m in blues.models) {
                    if (!is.null(m)) {
                        blues\$accession_id <- row.names(ranef(m)\$accession_id);
                        blues[,ncol(blues) + 1] <- ranef(m)\$accession_id\$\`(Intercept)\`;
                        colnames(blues)[ncol(blues)] <- varlist[counter];
                    }
                    counter = counter + 1;
                }
                blues_vals <- as.matrix(blues[,3:ncol(blues)]);
                blues_vals <- apply(blues_vals, 2, function(y) (y - mean(y)) / sd(y) ^ as.logical(sd(y)));
                rel <- (1/ncol(blues_vals)) * (blues_vals %*% t(blues_vals));
                rownames(rel) <- blues[,2];
                colnames(rel) <- blues[,2];
                write.table(rel, file=\''.$stats_out_htp_rel_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');"';
                print STDERR Dumper $htp_cmd;
                my $status = system($htp_cmd);
            }
            else {
                $c->stash->{rest} = { error => "The value of $compute_relationship_matrix_from_htp_phenotypes_type htp_pheno_rel_matrix_type is not valid!" };
                return;
            }

            open(my $htp_rel_res, '<', $stats_out_htp_rel_tempfile) or die "Could not open file '$stats_out_htp_rel_tempfile' $!";
                print STDERR "Opened $stats_out_htp_rel_tempfile\n";
                my $header_row = <$htp_rel_res>;
                my @header;
                if ($csv->parse($header_row)) {
                    @header = $csv->fields();
                }

                while (my $row = <$htp_rel_res>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    my $stock_id1 = $columns[0];
                    my $counter = 1;
                    foreach my $stock_id2 (@header) {
                        my $val = $columns[$counter];
                        $rel_htp_result_hash{$stock_id1}->{$stock_id2} = $val;
                        $counter++;
                    }
                }
            close($htp_rel_res);

            my $data_rel_htp = '';
            my %result_hash;
            foreach my $s (sort @accession_ids) {
                foreach my $c (sort @accession_ids) {
                    if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                        my $val = $rel_htp_result_hash{$s}->{$c};
                        if (defined $val and length $val) {
                            $result_hash{$s}->{$c} = $val;
                            $result_hash{$c}->{$s} = $val;
                            $data_rel_htp .= "S$s\tS$c\t$val\n";
                            if ($s != $c) {
                                $data_rel_htp .= "S$c\tS$s\t$val\n";
                            }
                        }
                    }
                }
            }

            open(my $htp_rel_out, ">", $stats_out_htp_rel_tempfile_out) || die "Can't open file ".$stats_out_htp_rel_tempfile_out;
                print $htp_rel_out $data_rel_htp;
            close($htp_rel_out);

            $grm_file = $stats_out_htp_rel_tempfile_out;
        }
        else {
            $c->stash->{rest} = { error => "The value of $compute_relationship_matrix_from_htp_phenotypes is not valid!" };
            return;
        }
    };

    my $trait_name_encoded_s = 1;
    my %trait_name_encoder_s;
    my %trait_name_encoder_rev_s;
    foreach my $trait_name (@sorted_trait_names) {
        if (!exists($trait_name_encoder_s{$trait_name})) {
            my $trait_name_e = 't'.$trait_name_encoded_s;
            $trait_name_encoder_s{$trait_name} = $trait_name_e;
            $trait_name_encoder_rev_s{$trait_name_e} = $trait_name;
            $trait_name_encoded_s++;
        }
    }

    my $trait_name_encoded_input_htp = 1;
    my %trait_name_encoder_input_htp;
    my %trait_name_encoder_rev_input_htp;
    foreach my $trait_name (@sorted_trait_names_htp) {
        if (!exists($trait_name_encoder_input_htp{$trait_name})) {
            my $trait_name_e = 'it'.$trait_name_encoded_input_htp;
            $trait_name_encoder_input_htp{$trait_name} = $trait_name_e;
            $trait_name_encoder_rev_input_htp{$trait_name_e} = $trait_name;
            $trait_name_encoded_input_htp++;
        }
    }

    # Prepare phenotype file for Trait Spatial Correction
    my $stats_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_tempfile_q1 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_tempfile_q2 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_tempfile_q3 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_tempfile_q4 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_ar1_indata = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_2dspl = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_residual = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_varcomp = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_vpredict = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_fits = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_gcor = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_factors = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $grm_rename_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
    my $ggcorr_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $fixed_eff_anova_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

    my $analytics_protocol_genfile_tempfile_string_1 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
    $analytics_protocol_genfile_tempfile_string_1 .= '.csv';
    my $analytics_protocol_genfile_tempfile_1 = $c->config->{basepath}."/".$analytics_protocol_genfile_tempfile_string_1;

    my @data_matrix_original;
    my @data_matrix_original_q1;
    my @data_matrix_original_q2;
    my @data_matrix_original_q3;
    my @data_matrix_original_q4;
    foreach my $p (@seen_plots) {
        my $obsunit_stock_id = $stock_name_row_col{$p}->{obsunit_stock_id};
        my $row_number = $stock_name_row_col{$p}->{row_number};
        my $col_number = $stock_name_row_col{$p}->{col_number};
        my $replicate = $stock_name_row_col{$p}->{rep};
        my $block = $stock_name_row_col{$p}->{block};
        my $germplasm_stock_id = $stock_name_row_col{$p}->{germplasm_stock_id};
        my $germplasm_name = $stock_name_row_col{$p}->{germplasm_name};

        my @row = ($replicate, $block, "S".$germplasm_stock_id, $obsunit_stock_id, $row_number, $col_number, $row_number, $col_number, '', '', "S".$obsunit_stock_id);

        foreach my $t (@sorted_trait_names) {
            if (defined($plot_phenotypes{$p}->{$t})) {
                push @row, $plot_phenotypes{$p}->{$t};
            } else {
                print STDERR $p." : $t : $germplasm_name : NA \n";
                push @row, 'NA';
            }
        }

        if ($row_number <= $max_row_half) {
            if ($col_number <= $max_col_half) {
                push @data_matrix_original_q1, \@row;
            }
            else {
                push @data_matrix_original_q2, \@row;
            }
        }
        else {
            if ($col_number <= $max_col_half) {
                push @data_matrix_original_q3, \@row;
            }
            else {
                push @data_matrix_original_q4, \@row;
            }
        }

        push @data_matrix_original, \@row;
    }
    # print STDERR Dumper \@data_matrix_original;
    # print STDERR Dumper \@data_matrix_original_q1;
    # print STDERR Dumper \@data_matrix_original_q2;
    # print STDERR Dumper \@data_matrix_original_q3;
    # print STDERR Dumper \@data_matrix_original_q4;

    my @phenotype_header = ("replicate", "block", "id", "plot_id", "rowNumber", "colNumber", "rowNumberFactor", "colNumberFactor", "accession_id_factor", "plot_id_factor", "plot_id_s");
    foreach (@sorted_trait_names) {
        push @phenotype_header, $trait_name_encoder_s{$_};
    }
    my $header_string = join ',', @phenotype_header;

    open(my $Fs, ">", $stats_tempfile) || die "Can't open file ".$stats_tempfile;
        print $Fs $header_string."\n";
        foreach (@data_matrix_original) {
            my $line = join ',', @$_;
            print $Fs "$line\n";
        }
    close($Fs);

    open(my $Fsq1, ">", $stats_tempfile_q1) || die "Can't open file ".$stats_tempfile_q1;
        print $Fsq1 $header_string."\n";
        foreach (@data_matrix_original_q1) {
            my $line = join ',', @$_;
            print $Fsq1 "$line\n";
        }
    close($Fsq1);

    open(my $Fsq2, ">", $stats_tempfile_q2) || die "Can't open file ".$stats_tempfile_q2;
        print $Fsq2 $header_string."\n";
        foreach (@data_matrix_original_q2) {
            my $line = join ',', @$_;
            print $Fsq2 "$line\n";
        }
    close($Fsq2);

    open(my $Fsq3, ">", $stats_tempfile_q3) || die "Can't open file ".$stats_tempfile_q3;
        print $Fsq3 $header_string."\n";
        foreach (@data_matrix_original_q3) {
            my $line = join ',', @$_;
            print $Fsq3 "$line\n";
        }
    close($Fsq3);

    open(my $Fsq4, ">", $stats_tempfile_q4) || die "Can't open file ".$stats_tempfile_q4;
        print $Fsq4 $header_string."\n";
        foreach (@data_matrix_original_q4) {
            my $line = join ',', @$_;
            print $Fsq4 "$line\n";
        }
    close($Fsq4);

    my $trait_name_string = join ',', @sorted_trait_names;
    my $trait_name_encoded_string = $trait_name_encoder_s{$trait_name_string};

    my $result_blup_data_s;
    my $genetic_effect_max_s = -1000000000;
    my $genetic_effect_min_s = 10000000000;
    my $genetic_effect_sum_square_s = 0;
    my $genetic_effect_sum_s = 0;
    my $result_blup_spatial_data_s;
    my $env_effect_min_s = 100000000;
    my $env_effect_max_s = -100000000;
    my $env_effect_sum_s = 0;
    my $env_effect_sum_square_s = 0;
    my $result_residual_data_s;
    my $result_fitted_data_s;
    my $residual_sum_s = 0;
    my $residual_sum_square_s = 0;
    my $model_sum_square_residual_s = 0;
    my @varcomp_original_grm_trait_2dspl;
    my @varcomp_h_grm_trait_2dspl;
    my @fits_grm_trait_2dspl;

    my $spatial_correct_2dspl_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
    mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
    geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
    geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
    geno_mat[is.na(geno_mat)] <- 0;
    mat\$rowNumber <- as.numeric(mat\$rowNumber);
    mat\$colNumber <- as.numeric(mat\$colNumber);
    mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + spl2Da(rowNumber, colNumber), rcov=~vs(units), data=mat, tolparinv='.$tolparinv_10.');
    if (!is.null(mix\$U)) {
    #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
    write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
    write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
    spatial_blup_results <- data.frame(plot_id = mat\$plot_id);
    W <- with(mat, spl2Da(rowNumber, colNumber));
    X <- W\$Z\$\`A:all\`;
    blups1 <- mix\$U\$\`A:all\`\$'.$trait_name_encoded_string.';
    spatial_blup_results\$'.$trait_name_encoded_string.' <- X %*% blups1;
    write.table(spatial_blup_results, file=\''.$stats_out_tempfile_2dspl.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
    write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
    h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V3) );
    e2 <- vpredict(mix, h2 ~ (V2) / ( V2+V3) );
    write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE, env=e2\$Estimate, ese=e2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
    ff <- fitted(mix, tolparinv='.$tolparinv_10.');
    r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
    SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
    write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
    }
    "';
    print STDERR Dumper $spatial_correct_2dspl_cmd;
    my $spatial_correct_2dspl_status = system($spatial_correct_2dspl_cmd);

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
                if ($encoded_trait eq $trait_name_encoded_string) {
                    my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                    my $stock_id = $columns[0];

                    my $stock_name = $stock_info{$stock_id}->{uniquename};
                    my $value = $columns[$col_counter+1];
                    if (defined $value && $value ne '') {
                        $result_blup_data_s->{$stock_name}->{$trait} = $value;

                        if ($value < $genetic_effect_min_s) {
                            $genetic_effect_min_s = $value;
                        }
                        elsif ($value >= $genetic_effect_max_s) {
                            $genetic_effect_max_s = $value;
                        }

                        $genetic_effect_sum_s += abs($value);
                        $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                    }
                }
                $col_counter++;
            }
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
                if ($encoded_trait eq $trait_name_encoded_string) {
                    my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                    my $plot_id = $columns[0];

                    my $plot_name = $plot_id_map{$plot_id};
                    my $value = $columns[$col_counter+1];
                    if (defined $value && $value ne '') {
                        $result_blup_spatial_data_s->{$plot_name}->{$trait} = $value;

                        if ($value < $env_effect_min_s) {
                            $env_effect_min_s = $value;
                        }
                        elsif ($value >= $env_effect_max_s) {
                            $env_effect_max_s = $value;
                        }

                        $env_effect_sum_s += abs($value);
                        $env_effect_sum_square_s = $env_effect_sum_square_s + $value*$value;
                    }
                }
                $col_counter++;
            }
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

            my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
            my $stock_id = $columns[0];
            my $residual = $columns[1];
            my $fitted = $columns[2];
            my $stock_name = $plot_id_map{$stock_id};
            if (defined $residual && $residual ne '') {
                $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                $residual_sum_s += abs($residual);
                $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
            }
            if (defined $fitted && $fitted ne '') {
                $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
            }
            $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
        }
    close($fh_residual);

    open(my $fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
        print STDERR "Opened $stats_out_tempfile_varcomp\n";
        my $header_varcomp = <$fh_varcomp>;
        print STDERR Dumper $header_varcomp;
        my @header_cols_varcomp;
        if ($csv->parse($header_varcomp)) {
            @header_cols_varcomp = $csv->fields();
        }
        while (my $row = <$fh_varcomp>) {
            my @columns;
            if ($csv->parse($row)) {
                @columns = $csv->fields();
            }
            push @varcomp_original_grm_trait_2dspl, \@columns;
        }
    close($fh_varcomp);
    print STDERR Dumper \@varcomp_original_grm_trait_2dspl;

    open(my $fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
        print STDERR "Opened $stats_out_tempfile_vpredict\n";
        my $header_varcomp_h = <$fh_varcomp_h>;
        print STDERR Dumper $header_varcomp_h;
        my @header_cols_varcomp_h;
        if ($csv->parse($header_varcomp_h)) {
            @header_cols_varcomp_h = $csv->fields();
        }
        while (my $row = <$fh_varcomp_h>) {
            my @columns;
            if ($csv->parse($row)) {
                @columns = $csv->fields();
            }
            push @varcomp_h_grm_trait_2dspl, \@columns;
        }
    close($fh_varcomp_h);
    print STDERR Dumper \@varcomp_h_grm_trait_2dspl;

    open(my $fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
        print STDERR "Opened $stats_out_tempfile_fits\n";
        my $header_fits = <$fh_fits>;
        print STDERR Dumper $header_fits;
        my @header_cols_fits;
        if ($csv->parse($header_fits)) {
            @header_cols_fits = $csv->fields();
        }
        while (my $row = <$fh_fits>) {
            my @columns;
            if ($csv->parse($row)) {
                @columns = $csv->fields();
            }
            push @fits_grm_trait_2dspl, \@columns;
        }
    close($fh_fits);
    print STDERR Dumper \@fits_grm_trait_2dspl;

    my $result_blup_data_g;
    my $genetic_effect_max_g = -1000000000;
    my $genetic_effect_min_g = 10000000000;
    my $genetic_effect_sum_square_g = 0;
    my $genetic_effect_sum_g = 0;
    my $env_effect_sum_square_g = 0;
    my $result_residual_data_g;
    my $result_fitted_data_g;
    my $residual_sum_g = 0;
    my $residual_sum_square_g = 0;
    my $model_sum_square_residual_g = 0;
    my @varcomp_original_grm_trait_g;
    my @varcomp_h_grm_trait_g;
    my @fits_grm_trait_g;

    my $spatial_correct_g_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
    mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
    geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
    geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
    geno_mat[is.na(geno_mat)] <- 0;
    mat\$rowNumber <- as.numeric(mat\$rowNumber);
    mat\$colNumber <- as.numeric(mat\$colNumber);
    mat\$rowNumberFactor <- as.factor(mat\$rowNumberFactor);
    mat\$colNumberFactor <- as.factor(mat\$colNumberFactor);
    mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat, tolparinv='.$tolparinv_10.');
    if (!is.null(mix\$U)) {
    #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
    write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
    write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
    write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
    h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
    write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
    ff <- fitted(mix, tolparinv='.$tolparinv_10.');
    r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
    SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
    write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
    }
    "';
    print STDERR Dumper $spatial_correct_g_cmd;
    my $spatial_correct_g_status = system($spatial_correct_g_cmd);

    open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
        print STDERR "Opened $stats_out_tempfile\n";
        $header = <$fh>;
        @header_cols = ();
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
                if ($encoded_trait eq $trait_name_encoded_string) {
                    my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                    my $stock_id = $columns[0];

                    my $stock_name = $stock_info{$stock_id}->{uniquename};
                    my $value = $columns[$col_counter+1];
                    if (defined $value && $value ne '') {
                        $result_blup_data_g->{$stock_name}->{$trait} = $value;

                        if ($value < $genetic_effect_min_g) {
                            $genetic_effect_min_g = $value;
                        }
                        elsif ($value >= $genetic_effect_max_g) {
                            $genetic_effect_max_g = $value;
                        }

                        $genetic_effect_sum_g += abs($value);
                        $genetic_effect_sum_square_g = $genetic_effect_sum_square_g + $value*$value;
                    }
                }
                $col_counter++;
            }
        }
    close($fh);

    open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
        print STDERR "Opened $stats_out_tempfile_residual\n";
        $header_residual = <$fh_residual>;
        @header_cols_residual = ();
        if ($csv->parse($header_residual)) {
            @header_cols_residual = $csv->fields();
        }
        while (my $row = <$fh_residual>) {
            my @columns;
            if ($csv->parse($row)) {
                @columns = $csv->fields();
            }

            my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
            my $stock_id = $columns[0];
            my $residual = $columns[1];
            my $fitted = $columns[2];
            my $stock_name = $plot_id_map{$stock_id};
            if (defined $residual && $residual ne '') {
                $result_residual_data_g->{$stock_name}->{$trait_name} = $residual;
                $residual_sum_g += abs($residual);
                $residual_sum_square_g = $residual_sum_square_g + $residual*$residual;
            }
            if (defined $fitted && $fitted ne '') {
                $result_fitted_data_g->{$stock_name}->{$trait_name} = $fitted;
            }
            $model_sum_square_residual_g = $model_sum_square_residual_g + $residual*$residual;
        }
    close($fh_residual);

    open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
        print STDERR "Opened $stats_out_tempfile_varcomp\n";
        $header_varcomp = <$fh_varcomp>;
        print STDERR Dumper $header_varcomp;
        @header_cols_varcomp = ();
        if ($csv->parse($header_varcomp)) {
            @header_cols_varcomp = $csv->fields();
        }
        while (my $row = <$fh_varcomp>) {
            my @columns;
            if ($csv->parse($row)) {
                @columns = $csv->fields();
            }
            push @varcomp_original_grm_trait_g, \@columns;
        }
    close($fh_varcomp);
    print STDERR Dumper \@varcomp_original_grm_trait_g;

    open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
        print STDERR "Opened $stats_out_tempfile_vpredict\n";
        $header_varcomp_h = <$fh_varcomp_h>;
        print STDERR Dumper $header_varcomp_h;
        @header_cols_varcomp_h = ();
        if ($csv->parse($header_varcomp_h)) {
            @header_cols_varcomp_h = $csv->fields();
        }
        while (my $row = <$fh_varcomp_h>) {
            my @columns;
            if ($csv->parse($row)) {
                @columns = $csv->fields();
            }
            push @varcomp_h_grm_trait_g, \@columns;
        }
    close($fh_varcomp_h);
    print STDERR Dumper \@varcomp_h_grm_trait_g;

    open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
        print STDERR "Opened $stats_out_tempfile_fits\n";
        $header_fits = <$fh_fits>;
        print STDERR Dumper $header_fits;
        @header_cols_fits = ();
        if ($csv->parse($header_fits)) {
            @header_cols_fits = $csv->fields();
        }
        while (my $row = <$fh_fits>) {
            my @columns;
            if ($csv->parse($row)) {
                @columns = $csv->fields();
            }
            push @fits_grm_trait_g, \@columns;
        }
    close($fh_fits);
    print STDERR Dumper \@fits_grm_trait_g;

    my $gcorr_grm_trait_2dspl = 0;
    eval {
        my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
        geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
        geno_mat[is.na(geno_mat)] <- 0;
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + spl2Da(rowNumber, colNumber), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ], tolparinv='.$tolparinv_10.');
        if (!is.null(mix1\$U)) {
        mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + spl2Da(rowNumber, colNumber), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ], tolparinv='.$tolparinv_10.');
        if (!is.null(mix2\$U)) {
        mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
        g_corr <- 0;
        try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
        write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        }
        }
        "';
        print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
        my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

        open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
            print STDERR "Opened $stats_out_tempfile_gcor\n";
            $header_fits = <$F_gcorr_f>;
            while (my $row = <$F_gcorr_f>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                $gcorr_grm_trait_2dspl = $columns[0];
            }
        close($F_gcorr_f);
    };

    my $gcorr_grm_trait_2dspl_q_mean = 0;
    my @gcorr_grm_trait_2dspl_q_array;
    eval {
        my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
        mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\'));
        mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\'));
        mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\'));
        mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
        geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
        geno_mat[is.na(geno_mat)] <- 0;
        mat_q1\$rowNumber <- as.numeric(mat_q1\$rowNumber); mat_q1\$colNumber <- as.numeric(mat_q1\$colNumber); mat_q2\$rowNumber <- as.numeric(mat_q2\$rowNumber); mat_q2\$colNumber <- as.numeric(mat_q2\$colNumber); mat_q3\$rowNumber <- as.numeric(mat_q3\$rowNumber); mat_q3\$colNumber <- as.numeric(mat_q3\$colNumber); mat_q4\$rowNumber <- as.numeric(mat_q4\$rowNumber); mat_q4\$colNumber <- as.numeric(mat_q4\$colNumber);
        mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + spl2Da(rowNumber, colNumber), rcov=~vs(units), data=mat_q1, tolparinv='.$tolparinv_10.');
        if (!is.null(mix1\$U)) {
        mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + spl2Da(rowNumber, colNumber), rcov=~vs(units), data=mat_q2, tolparinv='.$tolparinv_10.');
        if (!is.null(mix2\$U)) {
        mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + spl2Da(rowNumber, colNumber), rcov=~vs(units), data=mat_q3, tolparinv='.$tolparinv_10.');
        if (!is.null(mix3\$U)) {
        mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + spl2Da(rowNumber, colNumber), rcov=~vs(units), data=mat_q4, tolparinv='.$tolparinv_10.');
        if (!is.null(mix4\$U)) {
        m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
        m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
        m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
        m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
        m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
        m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
        g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0;
        try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\'));
        try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\'));
        try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\'));
        try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\'));
        try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\'));
        try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\'));
        g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
        write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        }}}}
        "';
        print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
        my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

        open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
            print STDERR "Opened $stats_out_tempfile_gcor\n";
            $header_fits = <$F_gcorr_f>;
            while (my $row = <$F_gcorr_f>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                $gcorr_grm_trait_2dspl_q_mean = $columns[0];
                @gcorr_grm_trait_2dspl_q_array = split ',', $columns[1];
            }
        close($F_gcorr_f);
    };

    print STDERR Dumper {
        type => 'trait spatial genetic effect 2dspl',
        genetic_effect_sum => $genetic_effect_sum_s,
        genetic_effect_min => $genetic_effect_min_s,
        genetic_effect_max => $genetic_effect_max_s,
        gcorr_mean => $gcorr_grm_trait_2dspl_q_mean,
        gcorr_arr => \@gcorr_grm_trait_2dspl_q_array
    };

    my %accession_id_factor_map;
    my %accession_id_factor_map_reverse;
    my %stock_row_col;

    my $cmd_factor = 'R -e "library(data.table); library(dplyr);
    mat <- fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\');
    mat\$accession_id_factor <- as.numeric(as.factor(mat\$id));
    mat\$plot_id_factor <- as.numeric(as.factor(mat\$plot_id));
    write.table(mat, file=\''.$stats_out_tempfile_factors.'\', row.names=FALSE, col.names=TRUE, sep=\',\');"';
    print STDERR Dumper $cmd_factor;
    my $status_factor = system($cmd_factor);

    open(my $fh_factor, '<', $stats_out_tempfile_factors) or die "Could not open file '$stats_out_tempfile_factors' $!";
        print STDERR "Opened $stats_out_tempfile_factors\n";
        my $header_factor = <$fh_factor>;
        my @header_cols_factor;
        if ($csv->parse($header_factor)) {
            @header_cols_factor = $csv->fields();
        }

        my $line_factor_count = 0;
        while (my $row = <$fh_factor>) {
            my @columns;
            if ($csv->parse($row)) {
                @columns = $csv->fields();
            }
            # my @phenotype_header = ("replicate", "block", "id", "plot_id", "rowNumber", "colNumber", "rowNumberFactor", "colNumberFactor", "accession_id_factor", "plot_id_factor");
            my $rep = $columns[0];
            my $block = $columns[1];
            my $accession_id = $columns[2];
            my $plot_id = $columns[3];
            my $accession_id_factor = $columns[8];
            my $plot_id_factor = $columns[9];
            $stock_row_col{$plot_id}->{plot_id_factor} = $plot_id_factor;
            $accession_id_factor_map{$accession_id} = $accession_id_factor;
            $accession_id_factor_map_reverse{$accession_id_factor} = $stock_info{$accession_id}->{uniquename};
            $line_factor_count++;
        }
    close($fh_factor);

    my @data_matrix_original_ar1;
    my %seen_col_numbers;
    my %seen_row_numbers;
    foreach my $p (@seen_plots) {
        my $obsunit_stock_id = $stock_name_row_col{$p}->{obsunit_stock_id};
        my $row_number = $stock_name_row_col{$p}->{row_number};
        my $col_number = $stock_name_row_col{$p}->{col_number};
        my $replicate = $stock_name_row_col{$p}->{rep};
        my $block = $stock_name_row_col{$p}->{block};
        my $germplasm_stock_id = $stock_name_row_col{$p}->{germplasm_stock_id};
        my $germplasm_name = $stock_name_row_col{$p}->{germplasm_name};
        $seen_col_numbers{$col_number}++;
        $seen_row_numbers{$row_number}++;

        my @row = (
            $germplasm_stock_id,
            $obsunit_stock_id,
            $replicate,
            $row_number,
            $col_number,
            $accession_id_factor_map{'S'.$germplasm_stock_id},
            $stock_row_col{$obsunit_stock_id}->{plot_id_factor}
        );

        foreach my $t (@sorted_trait_names) {
            if (defined($plot_phenotypes{$p}->{$t})) {
                push @row, $plot_phenotypes{$p}->{$t};
            } else {
                print STDERR $p." : $t : $germplasm_name : NA \n";
                push @row, 'NA';
            }
        }
        push @data_matrix_original_ar1, \@row;
    }
    # print STDERR Dumper \@data_matrix_original_ar1;
    my @seen_cols_numbers_sorted = sort keys %seen_col_numbers;
    my @seen_rows_numbers_sorted = sort keys %seen_row_numbers;

    my @phenotype_header_ar1 = ("id", "plot_id", "replicate", "rowNumber", "colNumber", "id_factor", "plot_id_factor");
    foreach (@sorted_trait_names) {
        push @phenotype_header_ar1, $trait_name_encoder_s{$_};
    }
    my $header_string_ar1 = join ',', @phenotype_header_ar1;

    open(my $Fs_ar1, ">", $stats_out_tempfile_ar1_indata) || die "Can't open file ".$stats_out_tempfile_ar1_indata;
        print $Fs_ar1 $header_string_ar1."\n";
        foreach (@data_matrix_original_ar1) {
            my $line = join ',', @$_;
            print $Fs_ar1 "$line\n";
        }
    close($Fs_ar1);

    my $grm_file_ar1;
    # if ($analysis_run_type eq 'ar1' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq 'ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq 'ar1_wRow' || $analysis_run_type eq '2dspl_ar1_wRow' || $analysis_run_type eq '2dspl_ar1_wRowCol' || $analysis_run_type eq '2dspl_ar1_wRowPlusCol' || $analysis_run_type eq '2dspl_ar1_wColPlusRow') {
        # Prepare GRM for AR1 Trait Spatial Correction
        eval {
            print STDERR Dumper [$compute_relationship_matrix_from_htp_phenotypes, $include_pedgiree_info_if_compute_from_parents, $use_parental_grms_if_compute_from_parents, $compute_from_parents];
            if ($compute_relationship_matrix_from_htp_phenotypes eq 'genotypes') {

                if ($include_pedgiree_info_if_compute_from_parents) {
                    my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
                    my $tmp_arm_dir = $shared_cluster_dir_config."/tmp_download_arm";
                    mkdir $tmp_arm_dir if ! -d $tmp_arm_dir;
                    my ($arm_tempfile_fh, $arm_tempfile) = tempfile("drone_stats_download_arm_XXXXX", DIR=> $tmp_arm_dir);
                    my ($grm1_tempfile_fh, $grm1_tempfile) = tempfile("drone_stats_download_grm1_XXXXX", DIR=> $tmp_arm_dir);
                    my ($grm_out_temp_tempfile_fh, $grm_out_temp_tempfile) = tempfile("drone_stats_download_grm_temp_out_XXXXX", DIR=> $tmp_arm_dir);
                    my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);
                    my ($grm_out_posdef_tempfile_fh, $grm_out_posdef_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);

                    if (!$genotyping_protocol_id) {
                        $genotyping_protocol_id = undef;
                    }

                    my $pedigree_arm = CXGN::Pedigree::ARM->new({
                        bcs_schema=>$schema,
                        arm_temp_file=>$arm_tempfile,
                        people_schema=>$people_schema,
                        accession_id_list=>\@accession_ids,
                        # plot_id_list=>\@plot_id_list,
                        cache_root=>$c->config->{cache_file_path},
                        download_format=>'matrix', #either 'matrix', 'three_column', or 'heatmap'
                    });
                    my ($parent_hash, $stock_ids, $all_accession_stock_ids, $female_stock_ids, $male_stock_ids) = $pedigree_arm->get_arm(
                        $shared_cluster_dir_config,
                        $c->config->{backend},
                        $c->config->{cluster_host},
                        $c->config->{'web_cluster_queue'},
                        $c->config->{basepath}
                    );
                    # print STDERR Dumper $parent_hash;

                    my $female_geno = CXGN::Genotype::GRM->new({
                        bcs_schema=>$schema,
                        grm_temp_file=>$grm1_tempfile,
                        people_schema=>$people_schema,
                        cache_root=>$c->config->{cache_file_path},
                        accession_id_list=>$female_stock_ids,
                        protocol_id=>$genotyping_protocol_id,
                        get_grm_for_parental_accessions=>0,
                        download_format=>'three_column_reciprocal',
                        genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                        # minor_allele_frequency=>$minor_allele_frequency,
                        # marker_filter=>$marker_filter,
                        # individuals_filter=>$individuals_filter
                    });
                    my $female_grm_data = $female_geno->download_grm(
                        'data',
                        $shared_cluster_dir_config,
                        $c->config->{backend},
                        $c->config->{cluster_host},
                        $c->config->{'web_cluster_queue'},
                        $c->config->{basepath}
                    );
                    my @fl = split '\n', $female_grm_data;
                    my %female_parent_grm;
                    foreach (@fl) {
                        my @l = split '\t', $_;
                        $female_parent_grm{$l[0]}->{$l[1]} = $l[2];
                    }
                    # print STDERR Dumper \%female_parent_grm;

                    my $male_geno = CXGN::Genotype::GRM->new({
                        bcs_schema=>$schema,
                        grm_temp_file=>$grm1_tempfile,
                        people_schema=>$people_schema,
                        cache_root=>$c->config->{cache_file_path},
                        accession_id_list=>$male_stock_ids,
                        protocol_id=>$genotyping_protocol_id,
                        get_grm_for_parental_accessions=>0,
                        download_format=>'three_column_reciprocal',
                        genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                        # minor_allele_frequency=>$minor_allele_frequency,
                        # marker_filter=>$marker_filter,
                        # individuals_filter=>$individuals_filter
                    });
                    my $male_grm_data = $male_geno->download_grm(
                        'data',
                        $shared_cluster_dir_config,
                        $c->config->{backend},
                        $c->config->{cluster_host},
                        $c->config->{'web_cluster_queue'},
                        $c->config->{basepath}
                    );
                    my @ml = split '\n', $male_grm_data;
                    my %male_parent_grm;
                    foreach (@ml) {
                        my @l = split '\t', $_;
                        $male_parent_grm{$l[0]}->{$l[1]} = $l[2];
                    }
                    # print STDERR Dumper \%male_parent_grm;

                    my %rel_result_hash;
                    foreach my $a1 (@accession_ids) {
                        foreach my $a2 (@accession_ids) {
                            my $female_parent1 = $parent_hash->{$a1}->{female_stock_id};
                            my $male_parent1 = $parent_hash->{$a1}->{male_stock_id};
                            my $female_parent2 = $parent_hash->{$a2}->{female_stock_id};
                            my $male_parent2 = $parent_hash->{$a2}->{male_stock_id};

                            my $female_rel = 0;
                            if ($female_parent1 && $female_parent2 && $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2}) {
                                $female_rel = $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2};
                            }
                            elsif ($female_parent1 && $female_parent2 && $female_parent1 == $female_parent2) {
                                $female_rel = 1;
                            }
                            elsif ($a1 == $a2) {
                                $female_rel = 1;
                            }

                            my $male_rel = 0;
                            if ($male_parent1 && $male_parent2 && $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2}) {
                                $male_rel = $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2};
                            }
                            elsif ($male_parent1 && $male_parent2 && $male_parent1 == $male_parent2) {
                                $male_rel = 1;
                            }
                            elsif ($a1 == $a2) {
                                $male_rel = 1;
                            }
                            # print STDERR "$a1 $a2 $female_rel $male_rel\n";

                            my $rel = 0.5*($female_rel + $male_rel);
                            $rel_result_hash{$a1}->{$a2} = $rel;
                        }
                    }
                    # print STDERR Dumper \%rel_result_hash;

                    my $data = '';
                    my %result_hash;
                    foreach my $s (sort @accession_ids) {
                        foreach my $c (sort @accession_ids) {
                            if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                                my $val = $rel_result_hash{$s}->{$c};
                                if (defined $val and length $val) {
                                    $result_hash{$s}->{$c} = $val;
                                    $data .= "S$s\tS$c\t$val\n";
                                }
                            }
                        }
                    }

                    # print STDERR Dumper $data;
                    open(my $F2, ">", $grm_out_temp_tempfile) || die "Can't open file ".$grm_out_temp_tempfile;
                        print $F2 $data;
                    close($F2);

                    my $cmd = 'R -e "library(data.table); library(scales); library(tidyr); library(reshape2);
                    three_col <- fread(\''.$grm_out_temp_tempfile.'\', header=FALSE, sep=\'\t\');
                    A_wide <- dcast(three_col, V1~V2, value.var=\'V3\');
                    A_1 <- A_wide[,-1];
                    A_1[is.na(A_1)] <- 0;
                    A <- A_1 + t(A_1);
                    diag(A) <- diag(as.matrix(A_1));
                    E = eigen(A);
                    ev = E\$values;
                    U = E\$vectors;
                    no = dim(A)[1];
                    nev = which(ev < 0);
                    wr = 0;
                    k=length(nev);
                    if(k > 0){
                        p = ev[no - k];
                        B = sum(ev[nev])*2.0;
                        wr = (B*B*100.0)+1;
                        val = ev[nev];
                        ev[nev] = p*(B-val)*(B-val)/wr;
                        A = U%*%diag(ev)%*%t(U);
                    }
                    A <- as.data.frame(A);
                    colnames(A) <- A_wide[,1];
                    A\$stock_id <- A_wide[,1];
                    A_threecol <- melt(A, id.vars = c(\'stock_id\'), measure.vars = A_wide[,1]);
                    A_threecol\$stock_id <- substring(A_threecol\$stock_id, 2);
                    A_threecol\$variable <- substring(A_threecol\$variable, 2);
                    write.table(data.frame(variable = A_threecol\$variable, stock_id = A_threecol\$stock_id, value = A_threecol\$value), file=\''.$grm_out_tempfile.'\', row.names=FALSE, col.names=FALSE, sep=\'\t\');"';
                    print STDERR $cmd."\n";
                    my $status = system($cmd);

                    my %rel_pos_def_result_hash;
                    open(my $F3, '<', $grm_out_tempfile)
                        or die "Could not open file '$grm_out_tempfile' $!";

                        print STDERR "Opened $grm_out_tempfile\n";

                        while (my $row = <$F3>) {
                            my @columns;
                            if ($csv->parse($row)) {
                                @columns = $csv->fields();
                            }
                            my $stock_id1 = $columns[0];
                            my $stock_id2 = $columns[1];
                            my $val = $columns[2];
                            $rel_pos_def_result_hash{$stock_id1}->{$stock_id2} = $val;
                        }
                    close($F3);

                    my $data_pos_def = '';
                    %result_hash = ();
                    foreach my $s (sort @accession_ids) {
                        foreach my $c (sort @accession_ids) {
                            if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                                my $val = $rel_pos_def_result_hash{$s}->{$c};
                                if (defined $val and length $val) {
                                    $result_hash{$s}->{$c} = $val;
                                    $data_pos_def .= "$s\t$c\t$val\n";
                                }
                            }
                        }
                    }

                    open(my $F4, ">", $grm_out_posdef_tempfile) || die "Can't open file ".$grm_out_posdef_tempfile;
                        print $F4 $data_pos_def;
                    close($F4);

                    $grm_file_ar1 = $grm_out_posdef_tempfile;
                }
                elsif ($use_parental_grms_if_compute_from_parents) {
                    my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
                    my $tmp_arm_dir = $shared_cluster_dir_config."/tmp_download_arm";
                    mkdir $tmp_arm_dir if ! -d $tmp_arm_dir;
                    my ($arm_tempfile_fh, $arm_tempfile) = tempfile("drone_stats_download_arm_XXXXX", DIR=> $tmp_arm_dir);
                    my ($grm1_tempfile_fh, $grm1_tempfile) = tempfile("drone_stats_download_grm1_XXXXX", DIR=> $tmp_arm_dir);
                    my ($grm_out_temp_tempfile_fh, $grm_out_temp_tempfile) = tempfile("drone_stats_download_grm_temp_out_XXXXX", DIR=> $tmp_arm_dir);
                    my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);
                    my ($grm_out_posdef_tempfile_fh, $grm_out_posdef_tempfile) = tempfile("drone_stats_download_grm_out_XXXXX", DIR=> $tmp_arm_dir);

                    if (!$genotyping_protocol_id) {
                        $genotyping_protocol_id = undef;
                    }

                    my $pedigree_arm = CXGN::Pedigree::ARM->new({
                        bcs_schema=>$schema,
                        arm_temp_file=>$arm_tempfile,
                        people_schema=>$people_schema,
                        accession_id_list=>\@accession_ids,
                        # plot_id_list=>\@plot_id_list,
                        cache_root=>$c->config->{cache_file_path},
                        download_format=>'matrix', #either 'matrix', 'three_column', or 'heatmap'
                    });
                    my ($parent_hash, $stock_ids, $all_accession_stock_ids, $female_stock_ids, $male_stock_ids) = $pedigree_arm->get_arm(
                        $shared_cluster_dir_config,
                        $c->config->{backend},
                        $c->config->{cluster_host},
                        $c->config->{'web_cluster_queue'},
                        $c->config->{basepath}
                    );
                    # print STDERR Dumper $parent_hash;

                    my $female_geno = CXGN::Genotype::GRM->new({
                        bcs_schema=>$schema,
                        grm_temp_file=>$grm1_tempfile,
                        people_schema=>$people_schema,
                        cache_root=>$c->config->{cache_file_path},
                        accession_id_list=>$female_stock_ids,
                        protocol_id=>$genotyping_protocol_id,
                        get_grm_for_parental_accessions=>0,
                        download_format=>'three_column_reciprocal',
                        genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                        # minor_allele_frequency=>$minor_allele_frequency,
                        # marker_filter=>$marker_filter,
                        # individuals_filter=>$individuals_filter
                    });
                    my $female_grm_data = $female_geno->download_grm(
                        'data',
                        $shared_cluster_dir_config,
                        $c->config->{backend},
                        $c->config->{cluster_host},
                        $c->config->{'web_cluster_queue'},
                        $c->config->{basepath}
                    );
                    my @fl = split '\n', $female_grm_data;
                    my %female_parent_grm;
                    foreach (@fl) {
                        my @l = split '\t', $_;
                        $female_parent_grm{$l[0]}->{$l[1]} = $l[2];
                    }
                    # print STDERR Dumper \%female_parent_grm;

                    my $male_geno = CXGN::Genotype::GRM->new({
                        bcs_schema=>$schema,
                        grm_temp_file=>$grm1_tempfile,
                        people_schema=>$people_schema,
                        cache_root=>$c->config->{cache_file_path},
                        accession_id_list=>$male_stock_ids,
                        protocol_id=>$genotyping_protocol_id,
                        get_grm_for_parental_accessions=>0,
                        download_format=>'three_column_reciprocal',
                        genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                        # minor_allele_frequency=>$minor_allele_frequency,
                        # marker_filter=>$marker_filter,
                        # individuals_filter=>$individuals_filter
                    });
                    my $male_grm_data = $male_geno->download_grm(
                        'data',
                        $shared_cluster_dir_config,
                        $c->config->{backend},
                        $c->config->{cluster_host},
                        $c->config->{'web_cluster_queue'},
                        $c->config->{basepath}
                    );
                    my @ml = split '\n', $male_grm_data;
                    my %male_parent_grm;
                    foreach (@ml) {
                        my @l = split '\t', $_;
                        $male_parent_grm{$l[0]}->{$l[1]} = $l[2];
                    }
                    # print STDERR Dumper \%male_parent_grm;

                    my %rel_result_hash;
                    foreach my $a1 (@accession_ids) {
                        foreach my $a2 (@accession_ids) {
                            my $female_parent1 = $parent_hash->{$a1}->{female_stock_id};
                            my $male_parent1 = $parent_hash->{$a1}->{male_stock_id};
                            my $female_parent2 = $parent_hash->{$a2}->{female_stock_id};
                            my $male_parent2 = $parent_hash->{$a2}->{male_stock_id};

                            my $female_rel = 0;
                            if ($female_parent1 && $female_parent2 && $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2}) {
                                $female_rel = $female_parent_grm{'S'.$female_parent1}->{'S'.$female_parent2};
                            }
                            elsif ($a1 == $a2) {
                                $female_rel = 1;
                            }

                            my $male_rel = 0;
                            if ($male_parent1 && $male_parent2 && $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2}) {
                                $male_rel = $male_parent_grm{'S'.$male_parent1}->{'S'.$male_parent2};
                            }
                            elsif ($a1 == $a2) {
                                $male_rel = 1;
                            }
                            # print STDERR "$a1 $a2 $female_rel $male_rel\n";

                            my $rel = 0.5*($female_rel + $male_rel);
                            $rel_result_hash{$a1}->{$a2} = $rel;
                        }
                    }
                    # print STDERR Dumper \%rel_result_hash;

                    my $data = '';
                    my %result_hash;
                    foreach my $s (sort @accession_ids) {
                        foreach my $c (sort @accession_ids) {
                            if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                                my $val = $rel_result_hash{$s}->{$c};
                                if (defined $val and length $val) {
                                    $result_hash{$s}->{$c} = $val;
                                    $data .= "S$s\tS$c\t$val\n";
                                }
                            }
                        }
                    }

                    # print STDERR Dumper $data;
                    open(my $F2, ">", $grm_out_temp_tempfile) || die "Can't open file ".$grm_out_temp_tempfile;
                        print $F2 $data;
                    close($F2);

                    my $cmd = 'R -e "library(data.table); library(scales); library(tidyr); library(reshape2);
                    three_col <- fread(\''.$grm_out_temp_tempfile.'\', header=FALSE, sep=\'\t\');
                    A_wide <- dcast(three_col, V1~V2, value.var=\'V3\');
                    A_1 <- A_wide[,-1];
                    A_1[is.na(A_1)] <- 0;
                    A <- A_1 + t(A_1);
                    diag(A) <- diag(as.matrix(A_1));
                    E = eigen(A);
                    ev = E\$values;
                    U = E\$vectors;
                    no = dim(A)[1];
                    nev = which(ev < 0);
                    wr = 0;
                    k=length(nev);
                    if(k > 0){
                        p = ev[no - k];
                        B = sum(ev[nev])*2.0;
                        wr = (B*B*100.0)+1;
                        val = ev[nev];
                        ev[nev] = p*(B-val)*(B-val)/wr;
                        A = U%*%diag(ev)%*%t(U);
                    }
                    A <- as.data.frame(A);
                    colnames(A) <- A_wide[,1];
                    A\$stock_id <- A_wide[,1];
                    A_threecol <- melt(A, id.vars = c(\'stock_id\'), measure.vars = A_wide[,1]);
                    A_threecol\$stock_id <- substring(A_threecol\$stock_id, 2);
                    A_threecol\$variable <- substring(A_threecol\$variable, 2);
                    write.table(data.frame(variable = A_threecol\$variable, stock_id = A_threecol\$stock_id, value = A_threecol\$value), file=\''.$grm_out_tempfile.'\', row.names=FALSE, col.names=FALSE, sep=\'\t\');"';
                    print STDERR $cmd."\n";
                    my $status = system($cmd);

                    my %rel_pos_def_result_hash;
                    open(my $F3, '<', $grm_out_tempfile) or die "Could not open file '$grm_out_tempfile' $!";
                        print STDERR "Opened $grm_out_tempfile\n";

                        while (my $row = <$F3>) {
                            my @columns;
                            if ($csv->parse($row)) {
                                @columns = $csv->fields();
                            }
                            my $stock_id1 = $columns[0];
                            my $stock_id2 = $columns[1];
                            my $val = $columns[2];
                            $rel_pos_def_result_hash{$stock_id1}->{$stock_id2} = $val;
                        }
                    close($F3);

                    my $data_pos_def = '';
                    %result_hash = ();
                    foreach my $s (sort @accession_ids) {
                        foreach my $c (sort @accession_ids) {
                            if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                                my $val = $rel_pos_def_result_hash{$s}->{$c};
                                if (defined $val and length $val) {
                                    $result_hash{$s}->{$c} = $val;
                                    $data_pos_def .= "$s\t$c\t$val\n";
                                }
                            }
                        }
                    }

                    open(my $F4, ">", $grm_out_posdef_tempfile) || die "Can't open file ".$grm_out_posdef_tempfile;
                        print $F4 $data_pos_def;
                    close($F4);

                    $grm_file_ar1 = $grm_out_posdef_tempfile;
                }
                else {
                    my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
                    my $tmp_grm_dir = $shared_cluster_dir_config."/tmp_genotype_download_grm";
                    mkdir $tmp_grm_dir if ! -d $tmp_grm_dir;
                    my ($grm_tempfile_fh, $grm_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
                    my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);

                    if (!$genotyping_protocol_id) {
                        $genotyping_protocol_id = undef;
                    }

                    my $grm_search_params = {
                        bcs_schema=>$schema,
                        grm_temp_file=>$grm_tempfile,
                        people_schema=>$people_schema,
                        cache_root=>$c->config->{cache_file_path},
                        accession_id_list=>\@accession_ids,
                        protocol_id=>$genotyping_protocol_id,
                        get_grm_for_parental_accessions=>$compute_from_parents,
                        genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
                        # minor_allele_frequency=>$minor_allele_frequency,
                        # marker_filter=>$marker_filter,
                        # individuals_filter=>$individuals_filter
                    };
                    $grm_search_params->{download_format} = 'three_column_stock_id_integer';

                    my $geno = CXGN::Genotype::GRM->new($grm_search_params);
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
                    $grm_file_ar1 = $grm_out_tempfile;
                }

            }
            elsif ($compute_relationship_matrix_from_htp_phenotypes eq 'htp_phenotypes') {
                my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
                my $tmp_grm_dir = $shared_cluster_dir_config."/tmp_genotype_download_grm";
                mkdir $tmp_grm_dir if ! -d $tmp_grm_dir;
                my ($stats_out_htp_rel_tempfile_input_fh, $stats_out_htp_rel_tempfile_input) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
                my ($stats_out_htp_rel_tempfile_fh, $stats_out_htp_rel_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
                my ($stats_out_htp_rel_tempfile_out_fh, $stats_out_htp_rel_tempfile_out) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);

                my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
                    'MaterializedViewTable',
                    {
                        bcs_schema=>$schema,
                        data_level=>'plot',
                        trial_list=>$field_trial_id_list,
                        include_timestamp=>0,
                        exclude_phenotype_outlier=>0
                    }
                );
                my ($data, $unique_traits) = $phenotypes_search->search();

                if (scalar(@$data) == 0) {
                    $c->stash->{rest} = { error => "There are no phenotypes for the trial you have selected!"};
                    return;
                }

                my $q_time = "SELECT t.cvterm_id FROM cvterm as t JOIN cv ON(t.cv_id=cv.cv_id) WHERE t.name=? and cv.name=?;";
                my $h_time = $schema->storage->dbh()->prepare($q_time);

                my %seen_plot_names_htp_rel;
                my %phenotype_data_htp_rel;
                my %seen_times_htp_rel;
                foreach my $obs_unit (@$data){
                    my $germplasm_name = $obs_unit->{germplasm_uniquename};
                    my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
                    my $row_number = $obs_unit->{obsunit_row_number} || '';
                    my $col_number = $obs_unit->{obsunit_col_number} || '';
                    my $rep = $obs_unit->{obsunit_rep};
                    my $block = $obs_unit->{obsunit_block};
                    $seen_plot_names_htp_rel{$obs_unit->{observationunit_uniquename}} = $obs_unit;
                    my $observations = $obs_unit->{observations};
                    foreach (@$observations){
                        if ($_->{associated_image_project_time_json}) {
                            my $related_time_terms_json = decode_json $_->{associated_image_project_time_json};

                            my $time_days_cvterm = $related_time_terms_json->{day};
                            my $time_days_term_string = $time_days_cvterm;
                            my $time_days = (split '\|', $time_days_cvterm)[0];
                            my $time_days_value = (split ' ', $time_days)[1];

                            my $time_gdd_value = $related_time_terms_json->{gdd_average_temp} + 0;
                            my $gdd_term_string = "GDD $time_gdd_value";
                            $h_time->execute($gdd_term_string, 'cxgn_time_ontology');
                            my ($gdd_cvterm_id) = $h_time->fetchrow_array();
                            if (!$gdd_cvterm_id) {
                                my $new_gdd_term = $schema->resultset("Cv::Cvterm")->create_with({
                                   name => $gdd_term_string,
                                   cv => 'cxgn_time_ontology'
                                });
                                $gdd_cvterm_id = $new_gdd_term->cvterm_id();
                            }
                            my $time_gdd_term_string = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $gdd_cvterm_id, 'extended');

                            $phenotype_data_htp_rel{$obs_unit->{observationunit_uniquename}}->{$_->{trait_name}} = $_->{value};
                            $seen_times_htp_rel{$_->{trait_name}} = [$time_days_value, $time_days_term_string, $time_gdd_value, $time_gdd_term_string];
                        }
                    }
                }
                $h_time = undef;

                my @allowed_standard_htp_values = ('Nonzero Pixel Count', 'Total Pixel Sum', 'Mean Pixel Value', 'Harmonic Mean Pixel Value', 'Median Pixel Value', 'Pixel Variance', 'Pixel Standard Deviation', 'Pixel Population Standard Deviation', 'Minimum Pixel Value', 'Maximum Pixel Value', 'Minority Pixel Value', 'Minority Pixel Count', 'Majority Pixel Value', 'Majority Pixel Count', 'Pixel Group Count');
                my %filtered_seen_times_htp_rel;
                while (my ($t, $time) = each %seen_times_htp_rel) {
                    my $allowed = 0;
                    foreach (@allowed_standard_htp_values) {
                        if (index($t, $_) != -1) {
                            $allowed = 1;
                            last;
                        }
                    }
                    if ($allowed) {
                        $filtered_seen_times_htp_rel{$t} = $time;
                    }
                }

                my @seen_plot_names_htp_rel_sorted = sort keys %seen_plot_names_htp_rel;
                my @filtered_seen_times_htp_rel_sorted = sort keys %filtered_seen_times_htp_rel;

                my @header_htp = ('plot_id', 'plot_name', 'accession_id', 'accession_name', 'rep', 'block');

                my %trait_name_encoder_htp;
                my %trait_name_encoder_rev_htp;
                my $trait_name_encoded_htp = 1;
                my @header_traits_htp;
                foreach my $trait_name (@filtered_seen_times_htp_rel_sorted) {
                    if (!exists($trait_name_encoder_htp{$trait_name})) {
                        my $trait_name_e = 't'.$trait_name_encoded_htp;
                        $trait_name_encoder_htp{$trait_name} = $trait_name_e;
                        $trait_name_encoder_rev_htp{$trait_name_e} = $trait_name;
                        push @header_traits_htp, $trait_name_e;
                        $trait_name_encoded_htp++;
                    }
                }

                my @htp_pheno_matrix;
                if ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'all') {
                    push @header_htp, @header_traits_htp;
                    push @htp_pheno_matrix, \@header_htp;

                    foreach my $p (@seen_plot_names_htp_rel_sorted) {
                        my $obj = $seen_plot_names_htp_rel{$p};
                        my @row = ($obj->{observationunit_stock_id}, $obj->{observationunit_uniquename}, $obj->{germplasm_stock_id}, $obj->{germplasm_uniquename}, $obj->{obsunit_rep}, $obj->{obsunit_block});
                        foreach my $t (@filtered_seen_times_htp_rel_sorted) {
                            my $val = $phenotype_data_htp_rel{$p}->{$t} + 0;
                            push @row, $val;
                        }
                        push @htp_pheno_matrix, \@row;
                    }
                }
                elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'latest_trait') {
                    my $max_day = 0;
                    foreach (keys %seen_days_after_plantings) {
                        if ($_ + 0 > $max_day) {
                            $max_day = $_;
                        }
                    }

                    foreach my $t (@filtered_seen_times_htp_rel_sorted) {
                        my $day = $filtered_seen_times_htp_rel{$t}->[0];
                        if ($day <= $max_day) {
                            push @header_htp, $t;
                        }
                    }
                    push @htp_pheno_matrix, \@header_htp;

                    foreach my $p (@seen_plot_names_htp_rel_sorted) {
                        my $obj = $seen_plot_names_htp_rel{$p};
                        my @row = ($obj->{observationunit_stock_id}, $obj->{observationunit_uniquename}, $obj->{germplasm_stock_id}, $obj->{germplasm_uniquename}, $obj->{obsunit_rep}, $obj->{obsunit_block});
                        foreach my $t (@filtered_seen_times_htp_rel_sorted) {
                            my $day = $filtered_seen_times_htp_rel{$t}->[0];
                            if ($day <= $max_day) {
                                my $val = $phenotype_data_htp_rel{$p}->{$t} + 0;
                                push @row, $val;
                            }
                        }
                        push @htp_pheno_matrix, \@row;
                    }
                }
                elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'vegetative') {

                }
                elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'reproductive') {

                }
                elsif ($compute_relationship_matrix_from_htp_phenotypes_time_points eq 'mature') {

                }
                else {
                    $c->stash->{rest} = { error => "The value of $compute_relationship_matrix_from_htp_phenotypes_time_points htp_pheno_rel_matrix_time_points is not valid!" };
                    return;
                }

                open(my $htp_pheno_f, ">", $stats_out_htp_rel_tempfile_input) || die "Can't open file ".$stats_out_htp_rel_tempfile_input;
                    foreach (@htp_pheno_matrix) {
                        my $line = join "\t", @$_;
                        print $htp_pheno_f $line."\n";
                    }
                close($htp_pheno_f);

                my %rel_htp_result_hash;
                if ($compute_relationship_matrix_from_htp_phenotypes_type eq 'correlations') {
                    my $htp_cmd = 'R -e "library(lme4); library(data.table);
                    mat <- fread(\''.$stats_out_htp_rel_tempfile_input.'\', header=TRUE, sep=\'\t\');
                    mat_agg <- aggregate(mat[, 7:ncol(mat)], list(mat\$accession_id), mean);
                    mat_pheno <- mat_agg[,2:ncol(mat_agg)];
                    cor_mat <- cor(t(mat_pheno));
                    rownames(cor_mat) <- mat_agg[,1];
                    colnames(cor_mat) <- mat_agg[,1];
                    range01 <- function(x){(x-min(x))/(max(x)-min(x))};
                    cor_mat <- range01(cor_mat);
                    write.table(cor_mat, file=\''.$stats_out_htp_rel_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');"';
                    print STDERR Dumper $htp_cmd;
                    my $status = system($htp_cmd);
                }
                elsif ($compute_relationship_matrix_from_htp_phenotypes_type eq 'blues') {
                    my $htp_cmd = 'R -e "library(lme4); library(data.table);
                    mat <- fread(\''.$stats_out_htp_rel_tempfile_input.'\', header=TRUE, sep=\'\t\');
                    blues <- data.frame(id = seq(1,length(unique(mat\$accession_id))));
                    varlist <- names(mat)[7:ncol(mat)];
                    blues.models <- lapply(varlist, function(x) {
                        tryCatch(
                            lmer(substitute(i ~ 1 + (1|accession_id), list(i = as.name(x))), data = mat, REML = FALSE, control = lmerControl(optimizer =\'Nelder_Mead\', boundary.tol='.$compute_relationship_matrix_from_htp_phenotypes_blues_inversion.' ) ), error=function(e) {}
                        )
                    });
                    counter = 1;
                    for (m in blues.models) {
                        if (!is.null(m)) {
                            blues\$accession_id <- row.names(ranef(m)\$accession_id);
                            blues[,ncol(blues) + 1] <- ranef(m)\$accession_id\$\`(Intercept)\`;
                            colnames(blues)[ncol(blues)] <- varlist[counter];
                        }
                        counter = counter + 1;
                    }
                    blues_vals <- as.matrix(blues[,3:ncol(blues)]);
                    blues_vals <- apply(blues_vals, 2, function(y) (y - mean(y)) / sd(y) ^ as.logical(sd(y)));
                    rel <- (1/ncol(blues_vals)) * (blues_vals %*% t(blues_vals));
                    rownames(rel) <- blues[,2];
                    colnames(rel) <- blues[,2];
                    write.table(rel, file=\''.$stats_out_htp_rel_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');"';
                    print STDERR Dumper $htp_cmd;
                    my $status = system($htp_cmd);
                }
                else {
                    $c->stash->{rest} = { error => "The value of $compute_relationship_matrix_from_htp_phenotypes_type htp_pheno_rel_matrix_type is not valid!" };
                    return;
                }

                open(my $htp_rel_res, '<', $stats_out_htp_rel_tempfile) or die "Could not open file '$stats_out_htp_rel_tempfile' $!";
                    print STDERR "Opened $stats_out_htp_rel_tempfile\n";
                    my $header_row = <$htp_rel_res>;
                    my @header;
                    if ($csv->parse($header_row)) {
                        @header = $csv->fields();
                    }

                    while (my $row = <$htp_rel_res>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        my $stock_id1 = $columns[0];
                        my $counter = 1;
                        foreach my $stock_id2 (@header) {
                            my $val = $columns[$counter];
                            $rel_htp_result_hash{$stock_id1}->{$stock_id2} = $val;
                            $counter++;
                        }
                    }
                close($htp_rel_res);

                my $data_rel_htp = '';
                my %result_hash;
                foreach my $s (sort @accession_ids) {
                    foreach my $c (sort @accession_ids) {
                        if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                            my $val = $rel_htp_result_hash{$s}->{$c};
                            if (defined $val and length $val) {
                                $result_hash{$s}->{$c} = $val;
                                $data_rel_htp .= "$s\t$c\t$val\n";
                            }
                        }
                    }
                }

                open(my $htp_rel_out, ">", $stats_out_htp_rel_tempfile_out) || die "Can't open file ".$stats_out_htp_rel_tempfile_out;
                    print $htp_rel_out $data_rel_htp;
                close($htp_rel_out);

                $grm_file_ar1 = $stats_out_htp_rel_tempfile_out;
            }
            else {
                $c->stash->{rest} = { error => "The value of $compute_relationship_matrix_from_htp_phenotypes is not valid!" };
                return;
            }
        };

        my $csv_tsv = Text::CSV->new({ sep_char => "\t" });

        my @grm_old;
        open(my $fh_grm_old, '<', $grm_file_ar1) or die "Could not open file '$grm_file_ar1' $!";
            print STDERR "Opened $grm_file_ar1\n";

            while (my $row = <$fh_grm_old>) {
                my @columns;
                if ($csv_tsv->parse($row)) {
                    @columns = $csv_tsv->fields();
                }
                push @grm_old, \@columns;
            }
        close($fh_grm_old);

        my %grm_hash_ordered;
        foreach (@grm_old) {
            my $l1 = $accession_id_factor_map{"S".$_->[0]};
            my $l2 = $accession_id_factor_map{"S".$_->[1]};
            my $val = sprintf("%.8f", $_->[2]);
            if ($l1 > $l2) {
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
    # }

    my $tol_asr = 'c(-8,-10)';
    if ($tolparinv eq '0.000001') {
        $tol_asr = 'c(-6,-8)';
    }
    if ($tolparinv eq '0.00001') {
        $tol_asr = 'c(-5,-7)';
    }
    if ($tolparinv eq '0.0001') {
        $tol_asr = 'c(-4,-6)';
    }
    if ($tolparinv eq '0.001') {
        $tol_asr = 'c(-3,-5)';
    }
    if ($tolparinv eq '0.01') {
        $tol_asr = 'c(-2,-4)';
    }
    if ($tolparinv eq '0.05') {
        $tol_asr = 'c(-2,-3)';
    }
    if ($tolparinv eq '0.08') {
        $tol_asr = 'c(-1,-2)';
    }
    if ($tolparinv eq '0.1' || $tolparinv eq '0.2' || $tolparinv eq '0.5') {
        $tol_asr = 'c(-1,-2)';
    }

    if ($default_tol eq 'default_both' || $default_tol eq 'pre_2dspl_def_ar1') {
        $tol_asr = 'c(-8,-10)';
    }
    elsif ($default_tol eq 'large_tol') {
        $tol_asr = 'c(-1,-2)';
    }

    my $number_traits = scalar(@sorted_trait_names);
    my $number_accessions = scalar(@accession_ids);

    my $current_gen_row_count_ar1 = 0;
    my $current_env_row_count_ar1 = 0;
    my $genetic_effect_min_ar1 = 1000000000;
    my $genetic_effect_max_ar1 = -1000000000;
    my $env_effect_min_ar1 = 1000000000;
    my $env_effect_max_ar1 = -1000000000;
    my $genetic_effect_sum_square_ar1 = 0;
    my $genetic_effect_sum_ar1 = 0;
    my $env_effect_sum_square_ar1 = 0;
    my $env_effect_sum_ar1 = 0;
    my $residual_sum_square_ar1 = 0;
    my $residual_sum_ar1 = 0;
    my @row_col_ordered_plots_names_ar1;
    my $result_blup_data_ar1;
    my $result_blup_spatial_data_ar1;
    my @varcomp_original_grm_trait_ar1;
    my @varcomp_h_grm_trait_ar1;
    my @fits_grm_trait_ar1;

    if ($analysis_run_type eq 'ar1' || $analysis_run_type eq '2dspl_ar1') {
        my $spatial_correct_ar1_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_out_tempfile_ar1_indata.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumber);
        mat\$colNumberFactor <- as.factor(mat\$colNumber);
        mat\$rowNumberFactorSep <- mat\$rowNumberFactor;
        mat\$colNumberFactorSep <- mat\$colNumberFactor;
        mat\$id_factor <- as.factor(mat\$id_factor);
        mat <- mat[order(mat\$rowNumber, mat\$colNumber),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml('.$trait_name_encoded_string.'~1 + replicate, random=~vm(id_factor, geno_mat_3col) + ar1v(rowNumberFactor):ar1(colNumberFactor), residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V3) );
        e2 <- vpredict(mix, h2 ~ (V2) / ( V2+V3) );
        write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE, env=e2\$Estimate, ese=e2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        ff <- fitted(mix);
        r2 <- cor(ff, mix\$mf\$'.$trait_name_encoded_string.', use = \'complete.obs\');
        SSE <- sum( abs(ff - mix\$mf\$'.$trait_name_encoded_string.'),na.rm=TRUE );
        write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        }
        "';
        print STDERR Dumper $spatial_correct_ar1_cmd;
        my $spatial_correct_ar1_status = system($spatial_correct_ar1_cmd);

        open(my $fh_residual_ar1, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual_ar1 = <$fh_residual_ar1>;
            my @header_cols_residual_ar1;
            if ($csv->parse($header_residual_ar1)) {
                @header_cols_residual_ar1 = $csv->fields();
            }
            while (my $row = <$fh_residual_ar1>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                push @row_col_ordered_plots_names_ar1, $stock_name;
                if (defined $residual && $residual ne '') {
                    $residual_sum_ar1 += abs($residual);
                    $residual_sum_square_ar1 = $residual_sum_square_ar1 + $residual*$residual;
                }
            }
        close($fh_residual_ar1);

        open(my $fh_ar1, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header_ar1 = <$fh_ar1>;

            my $solution_file_counter_ar1 = 0;
            while (defined(my $row = <$fh_ar1>)) {
                # print STDERR $row;
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $level = $columns[0];
                my $value = $columns[1];
                my $std = $columns[2];
                my $z_ratio = $columns[3];
                if (defined $value && $value ne '') {
                    if ($solution_file_counter_ar1 < $number_accessions) {
                        my $stock_name = $accession_id_factor_map_reverse{$solution_file_counter_ar1 + 1};
                        $result_blup_data_ar1->{$stock_name}->{$trait_name_string} = $value;

                        if ($value < $genetic_effect_min_ar1) {
                            $genetic_effect_min_ar1 = $value;
                        }
                        elsif ($value >= $genetic_effect_max_ar1) {
                            $genetic_effect_max_ar1 = $value;
                        }

                        $genetic_effect_sum_ar1 += abs($value);
                        $genetic_effect_sum_square_ar1 = $genetic_effect_sum_square_ar1 + $value*$value;

                        $current_gen_row_count_ar1++;
                    }
                    else {
                        my $plot_name = $row_col_ordered_plots_names_ar1[$current_env_row_count_ar1];
                        $result_blup_spatial_data_ar1->{$plot_name}->{$trait_name_string} = $value;

                        if ($value < $env_effect_min_ar1) {
                            $env_effect_min_ar1 = $value;
                        }
                        elsif ($value >= $env_effect_max_ar1) {
                            $env_effect_max_ar1 = $value;
                        }

                        $env_effect_sum_ar1 += abs($value);
                        $env_effect_sum_square_ar1 = $env_effect_sum_square_ar1 + $value*$value;

                        $current_env_row_count_ar1++;
                    }
                }
                $solution_file_counter_ar1++;
            }
        close($fh_ar1);
        # print STDERR Dumper $result_blup_spatial_data_ar1;

        open(my $fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
            print STDERR "Opened $stats_out_tempfile_varcomp\n";
            my $header_varcomp = <$fh_varcomp>;
            print STDERR Dumper $header_varcomp;
            my @header_cols_varcomp;
            if ($csv->parse($header_varcomp)) {
                @header_cols_varcomp = $csv->fields();
            }
            while (my $row = <$fh_varcomp>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_original_grm_trait_ar1, \@columns;
            }
        close($fh_varcomp);
        print STDERR Dumper \@varcomp_original_grm_trait_ar1;

        open(my $fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
            print STDERR "Opened $stats_out_tempfile_vpredict\n";
            my $header_varcomp_h = <$fh_varcomp_h>;
            print STDERR Dumper $header_varcomp_h;
            my @header_cols_varcomp_h;
            if ($csv->parse($header_varcomp_h)) {
                @header_cols_varcomp_h = $csv->fields();
            }
            while (my $row = <$fh_varcomp_h>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_h_grm_trait_ar1, \@columns;
            }
        close($fh_varcomp_h);
        print STDERR Dumper \@varcomp_h_grm_trait_ar1;

        open(my $fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
            print STDERR "Opened $stats_out_tempfile_fits\n";
            my $header_fits = <$fh_fits>;
            print STDERR Dumper $header_fits;
            my @header_cols_fits;
            if ($csv->parse($header_fits)) {
                @header_cols_fits = $csv->fields();
            }
            while (my $row = <$fh_fits>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @fits_grm_trait_ar1, \@columns;
            }
        close($fh_fits);
        print STDERR Dumper \@fits_grm_trait_ar1;
    }

    if ($analysis_run_type eq 'ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wCol') {
        my $spatial_correct_ar1wCol_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_out_tempfile_ar1_indata.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumber);
        mat\$colNumberFactor <- as.factor(mat\$colNumber);
        mat\$rowNumberFactorSep <- mat\$rowNumberFactor;
        mat\$colNumberFactorSep <- mat\$colNumberFactor;
        mat\$id_factor <- as.factor(mat\$id_factor);
        mat <- mat[order(mat\$rowNumber, mat\$colNumber),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml('.$trait_name_encoded_string.'~1 + replicate, random=~vm(id_factor, geno_mat_3col) + ar1v(rowNumberFactor):ar1(colNumberFactor) + colNumberFactor, residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V3) );
        e2 <- vpredict(mix, h2 ~ (V2) / ( V2+V3) );
        write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE, env=e2\$Estimate, ese=e2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        ff <- fitted(mix);
        r2 <- cor(ff, mix\$mf\$'.$trait_name_encoded_string.', use = \'complete.obs\');
        SSE <- sum( abs(ff - mix\$mf\$'.$trait_name_encoded_string.'),na.rm=TRUE );
        write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        }
        "';
        print STDERR Dumper $spatial_correct_ar1wCol_cmd;
        my $spatial_correct_ar1_status = system($spatial_correct_ar1wCol_cmd);

        open(my $fh_residual_ar1, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual_ar1 = <$fh_residual_ar1>;
            my @header_cols_residual_ar1;
            if ($csv->parse($header_residual_ar1)) {
                @header_cols_residual_ar1 = $csv->fields();
            }
            while (my $row = <$fh_residual_ar1>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                push @row_col_ordered_plots_names_ar1, $stock_name;
                if (defined $residual && $residual ne '') {
                    $residual_sum_ar1 += abs($residual);
                    $residual_sum_square_ar1 = $residual_sum_square_ar1 + $residual*$residual;
                }
            }
        close($fh_residual_ar1);

        open(my $fh_ar1, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header_ar1 = <$fh_ar1>;

            my $solution_file_counter_ar1_skipping = 0;
            my $solution_file_counter_ar1 = 0;
            while (defined(my $row = <$fh_ar1>)) {
                # print STDERR $row;
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $level = $columns[0];
                my $value = $columns[1];
                my $std = $columns[2];
                my $z_ratio = $columns[3];
                if (defined $value && $value ne '') {
                    if ($solution_file_counter_ar1_skipping < scalar(@seen_cols_numbers_sorted)) {
                        $solution_file_counter_ar1_skipping++;
                        next;
                    }
                    elsif ($solution_file_counter_ar1 < $number_accessions) {
                        my $stock_name = $accession_id_factor_map_reverse{$solution_file_counter_ar1 + 1};
                        $result_blup_data_ar1->{$stock_name}->{$trait_name_string} = $value;

                        if ($value < $genetic_effect_min_ar1) {
                            $genetic_effect_min_ar1 = $value;
                        }
                        elsif ($value >= $genetic_effect_max_ar1) {
                            $genetic_effect_max_ar1 = $value;
                        }

                        $genetic_effect_sum_ar1 += abs($value);
                        $genetic_effect_sum_square_ar1 = $genetic_effect_sum_square_ar1 + $value*$value;

                        $current_gen_row_count_ar1++;
                    }
                    else {
                        my $plot_name = $row_col_ordered_plots_names_ar1[$current_env_row_count_ar1];
                        $result_blup_spatial_data_ar1->{$plot_name}->{$trait_name_string} = $value;

                        if ($value < $env_effect_min_ar1) {
                            $env_effect_min_ar1 = $value;
                        }
                        elsif ($value >= $env_effect_max_ar1) {
                            $env_effect_max_ar1 = $value;
                        }

                        $env_effect_sum_ar1 += abs($value);
                        $env_effect_sum_square_ar1 = $env_effect_sum_square_ar1 + $value*$value;

                        $current_env_row_count_ar1++;
                    }
                }
                $solution_file_counter_ar1++;
            }
        close($fh_ar1);
        # print STDERR Dumper $result_blup_spatial_data_ar1;

        open(my $fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
            print STDERR "Opened $stats_out_tempfile_varcomp\n";
            my $header_varcomp = <$fh_varcomp>;
            print STDERR Dumper $header_varcomp;
            my @header_cols_varcomp;
            if ($csv->parse($header_varcomp)) {
                @header_cols_varcomp = $csv->fields();
            }
            while (my $row = <$fh_varcomp>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_original_grm_trait_ar1, \@columns;
            }
        close($fh_varcomp);
        print STDERR Dumper \@varcomp_original_grm_trait_ar1;

        open(my $fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
            print STDERR "Opened $stats_out_tempfile_vpredict\n";
            my $header_varcomp_h = <$fh_varcomp_h>;
            print STDERR Dumper $header_varcomp_h;
            my @header_cols_varcomp_h;
            if ($csv->parse($header_varcomp_h)) {
                @header_cols_varcomp_h = $csv->fields();
            }
            while (my $row = <$fh_varcomp_h>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_h_grm_trait_ar1, \@columns;
            }
        close($fh_varcomp_h);
        print STDERR Dumper \@varcomp_h_grm_trait_ar1;

        open(my $fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
            print STDERR "Opened $stats_out_tempfile_fits\n";
            my $header_fits = <$fh_fits>;
            print STDERR Dumper $header_fits;
            my @header_cols_fits;
            if ($csv->parse($header_fits)) {
                @header_cols_fits = $csv->fields();
            }
            while (my $row = <$fh_fits>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @fits_grm_trait_ar1, \@columns;
            }
        close($fh_fits);
        print STDERR Dumper \@fits_grm_trait_ar1;
    }

    if ($analysis_run_type eq 'ar1_wRow' || $analysis_run_type eq '2dspl_ar1_wRow') {
        my $spatial_correct_ar1wCol_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_out_tempfile_ar1_indata.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumber);
        mat\$colNumberFactor <- as.factor(mat\$colNumber);
        mat\$rowNumberFactorSep <- mat\$rowNumberFactor;
        mat\$colNumberFactorSep <- mat\$colNumberFactor;
        mat\$id_factor <- as.factor(mat\$id_factor);
        mat <- mat[order(mat\$rowNumber, mat\$colNumber),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml('.$trait_name_encoded_string.'~1 + replicate, random=~vm(id_factor, geno_mat_3col) + ar1v(rowNumberFactor):ar1(colNumberFactor) + rowNumberFactor, residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V3) );
        e2 <- vpredict(mix, h2 ~ (V2) / ( V2+V3) );
        write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE, env=e2\$Estimate, ese=e2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        ff <- fitted(mix);
        r2 <- cor(ff, mix\$mf\$'.$trait_name_encoded_string.', use = \'complete.obs\');
        SSE <- sum( abs(ff - mix\$mf\$'.$trait_name_encoded_string.'),na.rm=TRUE );
        write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        }
        "';
        print STDERR Dumper $spatial_correct_ar1wCol_cmd;
        my $spatial_correct_ar1_status = system($spatial_correct_ar1wCol_cmd);

        open(my $fh_residual_ar1, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual_ar1 = <$fh_residual_ar1>;
            my @header_cols_residual_ar1;
            if ($csv->parse($header_residual_ar1)) {
                @header_cols_residual_ar1 = $csv->fields();
            }
            while (my $row = <$fh_residual_ar1>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                push @row_col_ordered_plots_names_ar1, $stock_name;
                if (defined $residual && $residual ne '') {
                    $residual_sum_ar1 += abs($residual);
                    $residual_sum_square_ar1 = $residual_sum_square_ar1 + $residual*$residual;
                }
            }
        close($fh_residual_ar1);

        open(my $fh_ar1, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header_ar1 = <$fh_ar1>;

            my $solution_file_counter_ar1_skipping = 0;
            my $solution_file_counter_ar1 = 0;
            while (defined(my $row = <$fh_ar1>)) {
                # print STDERR $row;
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $level = $columns[0];
                my $value = $columns[1];
                my $std = $columns[2];
                my $z_ratio = $columns[3];
                if (defined $value && $value ne '') {
                    if ($solution_file_counter_ar1_skipping < scalar(@seen_rows_numbers_sorted)) {
                        $solution_file_counter_ar1_skipping++;
                        next;
                    }
                    elsif ($solution_file_counter_ar1 < $number_accessions) {
                        my $stock_name = $accession_id_factor_map_reverse{$solution_file_counter_ar1 + 1};
                        $result_blup_data_ar1->{$stock_name}->{$trait_name_string} = $value;

                        if ($value < $genetic_effect_min_ar1) {
                            $genetic_effect_min_ar1 = $value;
                        }
                        elsif ($value >= $genetic_effect_max_ar1) {
                            $genetic_effect_max_ar1 = $value;
                        }

                        $genetic_effect_sum_ar1 += abs($value);
                        $genetic_effect_sum_square_ar1 = $genetic_effect_sum_square_ar1 + $value*$value;

                        $current_gen_row_count_ar1++;
                    }
                    else {
                        my $plot_name = $row_col_ordered_plots_names_ar1[$current_env_row_count_ar1];
                        $result_blup_spatial_data_ar1->{$plot_name}->{$trait_name_string} = $value;

                        if ($value < $env_effect_min_ar1) {
                            $env_effect_min_ar1 = $value;
                        }
                        elsif ($value >= $env_effect_max_ar1) {
                            $env_effect_max_ar1 = $value;
                        }

                        $env_effect_sum_ar1 += abs($value);
                        $env_effect_sum_square_ar1 = $env_effect_sum_square_ar1 + $value*$value;

                        $current_env_row_count_ar1++;
                    }
                }
                $solution_file_counter_ar1++;
            }
        close($fh_ar1);
        # print STDERR Dumper $result_blup_spatial_data_ar1;

        open(my $fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
            print STDERR "Opened $stats_out_tempfile_varcomp\n";
            my $header_varcomp = <$fh_varcomp>;
            print STDERR Dumper $header_varcomp;
            my @header_cols_varcomp;
            if ($csv->parse($header_varcomp)) {
                @header_cols_varcomp = $csv->fields();
            }
            while (my $row = <$fh_varcomp>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_original_grm_trait_ar1, \@columns;
            }
        close($fh_varcomp);
        print STDERR Dumper \@varcomp_original_grm_trait_ar1;

        open(my $fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
            print STDERR "Opened $stats_out_tempfile_vpredict\n";
            my $header_varcomp_h = <$fh_varcomp_h>;
            print STDERR Dumper $header_varcomp_h;
            my @header_cols_varcomp_h;
            if ($csv->parse($header_varcomp_h)) {
                @header_cols_varcomp_h = $csv->fields();
            }
            while (my $row = <$fh_varcomp_h>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_h_grm_trait_ar1, \@columns;
            }
        close($fh_varcomp_h);
        print STDERR Dumper \@varcomp_h_grm_trait_ar1;

        open(my $fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
            print STDERR "Opened $stats_out_tempfile_fits\n";
            my $header_fits = <$fh_fits>;
            print STDERR Dumper $header_fits;
            my @header_cols_fits;
            if ($csv->parse($header_fits)) {
                @header_cols_fits = $csv->fields();
            }
            while (my $row = <$fh_fits>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @fits_grm_trait_ar1, \@columns;
            }
        close($fh_fits);
        print STDERR Dumper \@fits_grm_trait_ar1;
    }

    if ($analysis_run_type eq '2dspl_ar1_wRowCol') {
        my $spatial_correct_ar1wCol_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_out_tempfile_ar1_indata.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumber);
        mat\$colNumberFactor <- as.factor(mat\$colNumber);
        mat\$rowNumberFactorSep <- mat\$rowNumberFactor;
        mat\$colNumberFactorSep <- mat\$colNumberFactor;
        mat\$id_factor <- as.factor(mat\$id_factor);
        mat <- mat[order(mat\$rowNumber, mat\$colNumber),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml('.$trait_name_encoded_string.'~1 + replicate, random=~vm(id_factor, geno_mat_3col) + ar1v(rowNumberFactor):ar1(colNumberFactor) + rowNumberFactor + colNumberFactor, residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V3) );
        e2 <- vpredict(mix, h2 ~ (V2) / ( V2+V3) );
        write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE, env=e2\$Estimate, ese=e2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        ff <- fitted(mix);
        r2 <- cor(ff, mix\$mf\$'.$trait_name_encoded_string.', use = \'complete.obs\');
        SSE <- sum( abs(ff - mix\$mf\$'.$trait_name_encoded_string.'),na.rm=TRUE );
        write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        }
        "';
        print STDERR Dumper $spatial_correct_ar1wCol_cmd;
        my $spatial_correct_ar1_status = system($spatial_correct_ar1wCol_cmd);

        open(my $fh_residual_ar1, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual_ar1 = <$fh_residual_ar1>;
            my @header_cols_residual_ar1;
            if ($csv->parse($header_residual_ar1)) {
                @header_cols_residual_ar1 = $csv->fields();
            }
            while (my $row = <$fh_residual_ar1>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                push @row_col_ordered_plots_names_ar1, $stock_name;
                if (defined $residual && $residual ne '') {
                    $residual_sum_ar1 += abs($residual);
                    $residual_sum_square_ar1 = $residual_sum_square_ar1 + $residual*$residual;
                }
            }
        close($fh_residual_ar1);

        open(my $fh_ar1, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header_ar1 = <$fh_ar1>;

            my $solution_file_counter_ar1_skipping = 0;
            my $solution_file_counter_ar1 = 0;
            while (defined(my $row = <$fh_ar1>)) {
                # print STDERR $row;
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $level = $columns[0];
                my $value = $columns[1];
                my $std = $columns[2];
                my $z_ratio = $columns[3];
                if (defined $value && $value ne '') {
                    if ($solution_file_counter_ar1_skipping < scalar(@seen_rows_numbers_sorted) + scalar(@seen_cols_numbers_sorted)) {
                        $solution_file_counter_ar1_skipping++;
                        next;
                    }
                    elsif ($solution_file_counter_ar1 < $number_accessions) {
                        my $stock_name = $accession_id_factor_map_reverse{$solution_file_counter_ar1 + 1};
                        $result_blup_data_ar1->{$stock_name}->{$trait_name_string} = $value;

                        if ($value < $genetic_effect_min_ar1) {
                            $genetic_effect_min_ar1 = $value;
                        }
                        elsif ($value >= $genetic_effect_max_ar1) {
                            $genetic_effect_max_ar1 = $value;
                        }

                        $genetic_effect_sum_ar1 += abs($value);
                        $genetic_effect_sum_square_ar1 = $genetic_effect_sum_square_ar1 + $value*$value;

                        $current_gen_row_count_ar1++;
                    }
                    else {
                        my $plot_name = $row_col_ordered_plots_names_ar1[$current_env_row_count_ar1];
                        $result_blup_spatial_data_ar1->{$plot_name}->{$trait_name_string} = $value;

                        if ($value < $env_effect_min_ar1) {
                            $env_effect_min_ar1 = $value;
                        }
                        elsif ($value >= $env_effect_max_ar1) {
                            $env_effect_max_ar1 = $value;
                        }

                        $env_effect_sum_ar1 += abs($value);
                        $env_effect_sum_square_ar1 = $env_effect_sum_square_ar1 + $value*$value;

                        $current_env_row_count_ar1++;
                    }
                }
                $solution_file_counter_ar1++;
            }
        close($fh_ar1);
        # print STDERR Dumper $result_blup_spatial_data_ar1;

        open(my $fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
            print STDERR "Opened $stats_out_tempfile_varcomp\n";
            my $header_varcomp = <$fh_varcomp>;
            print STDERR Dumper $header_varcomp;
            my @header_cols_varcomp;
            if ($csv->parse($header_varcomp)) {
                @header_cols_varcomp = $csv->fields();
            }
            while (my $row = <$fh_varcomp>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_original_grm_trait_ar1, \@columns;
            }
        close($fh_varcomp);
        print STDERR Dumper \@varcomp_original_grm_trait_ar1;

        open(my $fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
            print STDERR "Opened $stats_out_tempfile_vpredict\n";
            my $header_varcomp_h = <$fh_varcomp_h>;
            print STDERR Dumper $header_varcomp_h;
            my @header_cols_varcomp_h;
            if ($csv->parse($header_varcomp_h)) {
                @header_cols_varcomp_h = $csv->fields();
            }
            while (my $row = <$fh_varcomp_h>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_h_grm_trait_ar1, \@columns;
            }
        close($fh_varcomp_h);
        print STDERR Dumper \@varcomp_h_grm_trait_ar1;

        open(my $fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
            print STDERR "Opened $stats_out_tempfile_fits\n";
            my $header_fits = <$fh_fits>;
            print STDERR Dumper $header_fits;
            my @header_cols_fits;
            if ($csv->parse($header_fits)) {
                @header_cols_fits = $csv->fields();
            }
            while (my $row = <$fh_fits>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @fits_grm_trait_ar1, \@columns;
            }
        close($fh_fits);
        print STDERR Dumper \@fits_grm_trait_ar1;
    }

    if ($analysis_run_type eq '2dspl_ar1_wRowPlusCol') {
        my $spatial_correct_ar1wCol_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_out_tempfile_ar1_indata.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumber);
        mat\$colNumberFactor <- as.factor(mat\$colNumber);
        mat\$rowNumberFactorSep <- mat\$rowNumberFactor;
        mat\$colNumberFactorSep <- mat\$colNumberFactor;
        mat\$id_factor <- as.factor(mat\$id_factor);
        mat <- mat[order(mat\$rowNumber, mat\$colNumber),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml('.$trait_name_encoded_string.'~1 + replicate, random=~vm(id_factor, geno_mat_3col) + ar1v(rowNumberFactor) + colNumberFactor, residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V3) );
        e2 <- vpredict(mix, h2 ~ (V2) / ( V2+V3) );
        write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE, env=e2\$Estimate, ese=e2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        ff <- fitted(mix);
        r2 <- cor(ff, mix\$mf\$'.$trait_name_encoded_string.', use = \'complete.obs\');
        SSE <- sum( abs(ff - mix\$mf\$'.$trait_name_encoded_string.'),na.rm=TRUE );
        write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        }
        "';
        print STDERR Dumper $spatial_correct_ar1wCol_cmd;
        my $spatial_correct_ar1_status = system($spatial_correct_ar1wCol_cmd);

        open(my $fh_residual_ar1, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual_ar1 = <$fh_residual_ar1>;
            my @header_cols_residual_ar1;
            if ($csv->parse($header_residual_ar1)) {
                @header_cols_residual_ar1 = $csv->fields();
            }
            while (my $row = <$fh_residual_ar1>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                push @row_col_ordered_plots_names_ar1, $stock_name;
                if (defined $residual && $residual ne '') {
                    $residual_sum_ar1 += abs($residual);
                    $residual_sum_square_ar1 = $residual_sum_square_ar1 + $residual*$residual;
                }
            }
        close($fh_residual_ar1);

        my %result_blup_row_spatial_data_ar1;
        my %result_blup_col_spatial_data_ar1;

        open(my $fh_ar1, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header_ar1 = <$fh_ar1>;

            my $solution_file_counter_ar1_skipping = 0;
            my $solution_file_counter_ar1 = 0;
            while (defined(my $row = <$fh_ar1>)) {
                # print STDERR $row;
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $level = $columns[0];
                my $value = $columns[1];
                my $std = $columns[2];
                my $z_ratio = $columns[3];
                if (defined $value && $value ne '') {
                    if ($solution_file_counter_ar1 < scalar(@seen_cols_numbers_sorted)) {
                        my @level_split = split '_', $level;
                        $result_blup_col_spatial_data_ar1{$level_split[1]} = $value;
                    }
                    elsif ($solution_file_counter_ar1 < scalar(@seen_cols_numbers_sorted) + scalar(@seen_rows_numbers_sorted)) {
                        my @level_split = split '_', $level;
                        $result_blup_row_spatial_data_ar1{$level_split[1]} = $value;
                    }
                    elsif ($solution_file_counter_ar1 < $number_accessions + scalar(@seen_cols_numbers_sorted) + scalar(@seen_rows_numbers_sorted)) {
                        my $stock_name = $accession_id_factor_map_reverse{$solution_file_counter_ar1 - scalar(@seen_cols_numbers_sorted) - scalar(@seen_rows_numbers_sorted) + 1};
                        $result_blup_data_ar1->{$stock_name}->{$trait_name_string} = $value;

                        if ($value < $genetic_effect_min_ar1) {
                            $genetic_effect_min_ar1 = $value;
                        }
                        elsif ($value >= $genetic_effect_max_ar1) {
                            $genetic_effect_max_ar1 = $value;
                        }

                        $genetic_effect_sum_ar1 += abs($value);
                        $genetic_effect_sum_square_ar1 = $genetic_effect_sum_square_ar1 + $value*$value;

                        $current_gen_row_count_ar1++;
                    }
                }
                $solution_file_counter_ar1++;
            }
        close($fh_ar1);

        while (my($row_level, $row_val) = each %result_blup_row_spatial_data_ar1) {
            while (my($col_level, $col_val) = each %result_blup_col_spatial_data_ar1) {
                my $plot_name = $plot_row_col_hash{$row_level}->{$col_level}->{obsunit_name};

                my $value = $row_val + $col_val;
                $result_blup_spatial_data_ar1->{$plot_name}->{$trait_name_string} = $value;

                if ($value < $env_effect_min_ar1) {
                    $env_effect_min_ar1 = $value;
                }
                elsif ($value >= $env_effect_max_ar1) {
                    $env_effect_max_ar1 = $value;
                }

                $env_effect_sum_ar1 += abs($value);
                $env_effect_sum_square_ar1 = $env_effect_sum_square_ar1 + $value*$value;
            }
        }
        # print STDERR Dumper $result_blup_spatial_data_ar1;

        open(my $fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
            print STDERR "Opened $stats_out_tempfile_varcomp\n";
            my $header_varcomp = <$fh_varcomp>;
            print STDERR Dumper $header_varcomp;
            my @header_cols_varcomp;
            if ($csv->parse($header_varcomp)) {
                @header_cols_varcomp = $csv->fields();
            }
            while (my $row = <$fh_varcomp>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_original_grm_trait_ar1, \@columns;
            }
        close($fh_varcomp);
        print STDERR Dumper \@varcomp_original_grm_trait_ar1;

        open(my $fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
            print STDERR "Opened $stats_out_tempfile_vpredict\n";
            my $header_varcomp_h = <$fh_varcomp_h>;
            print STDERR Dumper $header_varcomp_h;
            my @header_cols_varcomp_h;
            if ($csv->parse($header_varcomp_h)) {
                @header_cols_varcomp_h = $csv->fields();
            }
            while (my $row = <$fh_varcomp_h>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @varcomp_h_grm_trait_ar1, \@columns;
            }
        close($fh_varcomp_h);
        print STDERR Dumper \@varcomp_h_grm_trait_ar1;

        open(my $fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
            print STDERR "Opened $stats_out_tempfile_fits\n";
            my $header_fits = <$fh_fits>;
            print STDERR Dumper $header_fits;
            my @header_cols_fits;
            if ($csv->parse($header_fits)) {
                @header_cols_fits = $csv->fields();
            }
            while (my $row = <$fh_fits>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                push @fits_grm_trait_ar1, \@columns;
            }
        close($fh_fits);
        print STDERR Dumper \@fits_grm_trait_ar1;
    }

    if ($analysis_run_type eq '2dspl_ar1_wColPlusRow') {
        my $spatial_correct_ar1wCol_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_out_tempfile_ar1_indata.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumber);
        mat\$colNumberFactor <- as.factor(mat\$colNumber);
        mat\$rowNumberFactorSep <- mat\$rowNumberFactor;
        mat\$colNumberFactorSep <- mat\$colNumberFactor;
        mat\$id_factor <- as.factor(mat\$id_factor);
        mat <- mat[order(mat\$rowNumber, mat\$colNumber),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml('.$trait_name_encoded_string.'~1 + replicate, random=~vm(id_factor, geno_mat_3col) + ar1v(colNumberFactor) + rowNumberFactor, residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V3) );
        e2 <- vpredict(mix, h2 ~ (V2) / ( V2+V3) );
        write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE, env=e2\$Estimate, ese=e2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        ff <- fitted(mix);
        r2 <- cor(ff, mix\$mf\$'.$trait_name_encoded_string.', use = \'complete.obs\');
        SSE <- sum( abs(ff - mix\$mf\$'.$trait_name_encoded_string.'),na.rm=TRUE );
        write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        }
        "';
        print STDERR Dumper $spatial_correct_ar1wCol_cmd;
        my $spatial_correct_ar1_status = system($spatial_correct_ar1wCol_cmd);

        open(my $fh_residual_ar1, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
            print STDERR "Opened $stats_out_tempfile_residual\n";
            my $header_residual_ar1 = <$fh_residual_ar1>;
            my @header_cols_residual_ar1;
            if ($csv->parse($header_residual_ar1)) {
                @header_cols_residual_ar1 = $csv->fields();
            }
            while (my $row = <$fh_residual_ar1>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                my $stock_id = $columns[0];
                my $residual = $columns[1];
                my $fitted = $columns[2];
                my $stock_name = $plot_id_map{$stock_id};
                push @row_col_ordered_plots_names_ar1, $stock_name;
                if (defined $residual && $residual ne '') {
                    $residual_sum_ar1 += abs($residual);
                    $residual_sum_square_ar1 = $residual_sum_square_ar1 + $residual*$residual;
                }
            }
        close($fh_residual_ar1);

        my %result_blup_row_spatial_data_ar1;
        my %result_blup_col_spatial_data_ar1;

        open(my $fh_ar1, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
            print STDERR "Opened $stats_out_tempfile\n";
            my $header_ar1 = <$fh_ar1>;

            my $solution_file_counter_ar1_skipping = 0;
            my $solution_file_counter_ar1 = 0;
            while (defined(my $row = <$fh_ar1>)) {
                # print STDERR $row;
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                my $level = $columns[0];
                my $value = $columns[1];
                my $std = $columns[2];
                my $z_ratio = $columns[3];
                if (defined $value && $value ne '') {
                    if ($solution_file_counter_ar1 < scalar(@seen_cols_numbers_sorted)) {
                        my @level_split = split '_', $level;
                        $result_blup_col_spatial_data_ar1{$level_split[1]} = $value;
                    }
                    elsif ($solution_file_counter_ar1 < scalar(@seen_cols_numbers_sorted) + scalar(@seen_rows_numbers_sorted)) {
                        my @level_split = split '_', $level;
                        $result_blup_row_spatial_data_ar1{$level_split[1]} = $value;
                    }
                    elsif ($solution_file_counter_ar1 < $number_accessions + scalar(@seen_cols_numbers_sorted) + scalar(@seen_rows_numbers_sorted)) {
                        my $stock_name = $accession_id_factor_map_reverse{$solution_file_counter_ar1 - scalar(@seen_cols_numbers_sorted) - scalar(@seen_rows_numbers_sorted) + 1};
                        $result_blup_data_ar1->{$stock_name}->{$trait_name_string} = $value;

                        if ($value < $genetic_effect_min_ar1) {
                            $genetic_effect_min_ar1 = $value;
                        }
                        elsif ($value >= $genetic_effect_max_ar1) {
                            $genetic_effect_max_ar1 = $value;
                        }

                        $genetic_effect_sum_ar1 += abs($value);
                        $genetic_effect_sum_square_ar1 = $genetic_effect_sum_square_ar1 + $value*$value;

                        $current_gen_row_count_ar1++;
                    }
                }
                $solution_file_counter_ar1++;
            }
        close($fh_ar1);

        while (my($row_level, $row_val) = each %result_blup_row_spatial_data_ar1) {
            while (my($col_level, $col_val) = each %result_blup_col_spatial_data_ar1) {
                my $plot_name = $plot_row_col_hash{$row_level}->{$col_level}->{obsunit_name};

                my $value = $row_val + $col_val;
                $result_blup_spatial_data_ar1->{$plot_name}->{$trait_name_string} = $value;

                if ($value < $env_effect_min_ar1) {
                    $env_effect_min_ar1 = $value;
                }
                elsif ($value >= $env_effect_max_ar1) {
                    $env_effect_max_ar1 = $value;
                }

                $env_effect_sum_ar1 += abs($value);
                $env_effect_sum_square_ar1 = $env_effect_sum_square_ar1 + $value*$value;
            }
        }
        # print STDERR Dumper $result_blup_spatial_data_ar1;
    }

    # Factor Analytic on HTP and agronomic trait

    my @trait_list_all_long = ($trait_id, @$observation_variable_id_list);
    my $phenotypes_search_long = CXGN::Phenotypes::PhenotypeMatrixLong->new(
        bcs_schema=>$schema,
        search_type=>'MaterializedViewTable',
        data_level=>'plot',
        trait_list=>\@trait_list_all_long,
        trial_list=>$field_trial_id_list
    );
    my @data_long = $phenotypes_search_long->get_phenotype_matrix();
    # print STDERR Dumper \@data_long;

    my $stats_tempfile_long = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

    open(my $fh_factor_long, '>', $stats_tempfile_long) or die "Could not open file '$stats_tempfile_long' $!";

        print $fh_factor_long join (',', ('accession_id','accession_id_factor','plot_id','plot_id_factor','replicate','block','row_number','col_number','trait','value'))."\n";

        # my @phenotype_header = ('studyYear', 'programDbId', 'programName', 'programDescription', 'studyDbId', 'studyName', 'studyDescription', 'studyDesign', 'plotWidth', 'plotLength', 'fieldSize', 'fieldTrialIsPlannedToBeGenotyped', 'fieldTrialIsPlannedToCross', 'plantingDate', 'harvestDate', 'locationDbId', 'locationName', 'germplasmDbId', 'germplasmName', 'germplasmSynonyms', 'observationLevel', 'observationUnitDbId', 'observationUnitName', 'replicate', 'blockNumber', 'plotNumber', 'rowNumber', 'colNumber', 'entryType', 'plantNumber', 'plantedSeedlotStockDbId', 'plantedSeedlotStockUniquename', 'plantedSeedlotCurrentCount', 'plantedSeedlotCurrentWeightGram', 'plantedSeedlotBoxName', 'plantedSeedlotTransactionCount', 'plantedSeedlotTransactionWeight', 'plantedSeedlotTransactionDescription', 'availableGermplasmSeedlotUniquenames', 'notes', 'createDate', 'collectDate', 'timestamp', 'observationVariableName', 'value');
        for (my $line = 1; $line < scalar(@data_long); $line++) {
            my $columns = $data_long[$line];

            my $accession_id = $columns->[17];
            my $plot_id = $columns->[21];
            my $replicate = $columns->[23];
            my $block = $columns->[24];
            my $row_number = $columns->[26];
            my $col_number = $columns->[27];
            my $trait = $columns->[43];
            my $value = $columns->[44];

            my $plot_id_factor = $stock_row_col{$plot_id}->{plot_id_factor};
            my $accession_id_factor = $accession_id_factor_map{"S".$accession_id};

            print $fh_factor_long join (',', ($accession_id, $accession_id_factor, $plot_id, $plot_id_factor, $replicate, $block, $row_number, $col_number, $trait, $value))."\n";
        }

    close($fh_factor_long);

    if ($analysis_run_type eq '2dspl_asremlFA') {
        my $factor_analytic_cmd = 'R -e "library(asreml); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_tempfile_long.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_rename_tempfile.'\', header=FALSE, sep=\' \'));
        mat\$row_number <- as.numeric(mat\$row_number);
        mat\$col_number <- as.numeric(mat\$col_number);
        mat\$accession_id_factor <- as.factor(as.numeric(as.factor(mat\$accession_id)));
        mat\$plot_id_factor <- as.numeric(as.factor(mat\$plot_id));
        mat\$rep_trait <- as.factor(paste(mat\$replicate, mat\$trait));
        mat\$trait <- as.factor(mat\$trait);
        mat <- mat[order(mat\$row_number, mat\$col_number),];
        attr(geno_mat_3col,\'rowNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'colNames\') <- as.character(seq(1,'.$number_accessions.'));
        attr(geno_mat_3col,\'INVERSE\') <- TRUE;
        mix <- asreml(value~1 + rep_trait, random=~fa(trait):vm(accession_id_factor, geno_mat_3col), residual=~idv(units), data=mat, tol='.$tol_asr.');
        if (!is.null(summary(mix,coef=TRUE)\$coef.random)) {
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$row_number, colNumber = mat\$col_number), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        count <- nrow(summary(mix)\$varcomp);
        h2s <- c(); h2ses <- c(); ';
        for (my $fa_trait = scalar(@trait_list_all_long); $fa_trait >= 1; $fa_trait--) {
            $factor_analytic_cmd .= 'h2 <- vpredict(mix, as.formula(paste(\"h2 ~ (V\", count-1-'.$fa_trait.', \") / ( V\", count-1-'.$fa_trait.' , \"+V\", count-1, \")\", sep=\"\")) );
            h2s <- append(h2s, h2\$Estimate); h2ses <- append(h2ses, h2\$SE);';
        }
        $factor_analytic_cmd .= 'write.table(data.frame(h2s=h2s, h2ses=h2ses), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        ff <- fitted(mix);
        r2 <- cor(ff, mix\$mf\$value, use = \'complete.obs\');
        SSE <- sum( abs(ff - mix\$mf\$value),na.rm=TRUE );
        write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        }
        mix1 <- asreml(value~1 + rep_trait, random=~fa(trait):vm(accession_id_factor, geno_mat_3col), residual=~idv(units), data=mat[mat\$replicate == \'1\', ], tol='.$tol_asr.');
        if (!is.null(summary(mix_g1,coef=TRUE)\$coef.random)) {
        mix2 <- asreml(value~1 + rep_trait, random=~fa(trait):vm(accession_id_factor, geno_mat_3col), residual=~idv(units), data=mat[mat\$replicate == \'2\', ], tol='.$tol_asr.');
        if (!is.null(summary(mix_g1,coef=TRUE)\$coef.random)) {
        mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$coefficients\$random), data.frame(g_rep2=mix2\$coefficients\$random), by=\'row.names\', all=TRUE);
        g_corr <- 0;
        try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
        write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        }
        }
        "';
        print STDERR Dumper $factor_analytic_cmd;
        my $asreml_fa_status = system($factor_analytic_cmd);

        open(my $F_fa_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
            print STDERR "Opened $stats_out_tempfile_gcor\n";
            $header_fits = <$F_fa_f>;
            while (my $row = <$F_fa_f>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }
                print STDERR Dumper $columns[0];
            }
        close($F_fa_f);

    }
    die;

    open(my $F_genfile, ">", $analytics_protocol_genfile_tempfile_1) || die "Can't open file ".$analytics_protocol_genfile_tempfile_1;
        print $F_genfile "trait,accession_name,genetic_effect_g,genetic_effect_2dspl,genetic_effect_ar1\n";
        foreach my $accession_name (sort keys %$result_blup_data_g) {
            my $g_g = $result_blup_data_g->{$accession_name}->{$trait_name_string} || '';
            my $g_s = $result_blup_data_s->{$accession_name}->{$trait_name_string} || '';
            my $g_ar1 = $result_blup_data_ar1->{$accession_name}->{$trait_name_string} || '';

            my $line = join ',', ($trait_name_string, $accession_name, $g_g, $g_s, $g_ar1);
            print $F_genfile "$line\n";
        }
    close($F_genfile);

    # my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
    # my $tmp_grm_dir = $shared_cluster_dir_config."/tmp_genotype_download_grm";
    # mkdir $tmp_grm_dir if ! -d $tmp_grm_dir;
    # my ($stats_out_htp_rel_tempfile_input_fh, $stats_out_htp_rel_tempfile_input) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
    #
    # eval {
    #     my $phenotypes_search_htp_cor = CXGN::Phenotypes::SearchFactory->instantiate(
    #         'MaterializedViewTable',
    #         {
    #             bcs_schema=>$schema,
    #             data_level=>'plot',
    #             trial_list=>$field_trial_id_list,
    #             include_timestamp=>0,
    #             exclude_phenotype_outlier=>0
    #         }
    #     );
    #     my ($data_htp_cor, $unique_traits_htp_cor) = $phenotypes_search_htp_cor->search();
    #
    #     if (scalar(@$data_htp_cor) == 0) {
    #         $c->stash->{rest} = { error => "There are no phenotypes for the trial you have selected!"};
    #         return;
    #     }
    #
    #     my $q_time = "SELECT t.cvterm_id FROM cvterm as t JOIN cv ON(t.cv_id=cv.cv_id) WHERE t.name=? and cv.name=?;";
    #     my $h_time = $schema->storage->dbh()->prepare($q_time);
    #
    #     my %seen_plot_names_htp_rel;
    #     my %phenotype_data_htp_rel;
    #     my %seen_times_htp_rel;
    #     foreach my $obs_unit (@$data_htp_cor){
    #         my $germplasm_name = $obs_unit->{germplasm_uniquename};
    #         my $germplasm_stock_id = $obs_unit->{germplasm_stock_id};
    #         my $row_number = $obs_unit->{obsunit_row_number} || '';
    #         my $col_number = $obs_unit->{obsunit_col_number} || '';
    #         my $rep = $obs_unit->{obsunit_rep};
    #         my $block = $obs_unit->{obsunit_block};
    #         $seen_plot_names_htp_rel{$obs_unit->{observationunit_uniquename}} = $obs_unit;
    #         my $observations = $obs_unit->{observations};
    #         foreach (@$observations){
    #             if ($_->{associated_image_project_time_json}) {
    #                 my $related_time_terms_json = decode_json $_->{associated_image_project_time_json};
    #
    #                 my $time_days_cvterm = $related_time_terms_json->{day};
    #                 my $time_days_term_string = $time_days_cvterm;
    #                 my $time_days = (split '\|', $time_days_cvterm)[0];
    #                 my $time_days_value = (split ' ', $time_days)[1];
    #
    #                 my $time_gdd_value = $related_time_terms_json->{gdd_average_temp} + 0;
    #                 my $gdd_term_string = "GDD $time_gdd_value";
    #                 $h_time->execute($gdd_term_string, 'cxgn_time_ontology');
    #                 my ($gdd_cvterm_id) = $h_time->fetchrow_array();
    #                 if (!$gdd_cvterm_id) {
    #                     my $new_gdd_term = $schema->resultset("Cv::Cvterm")->create_with({
    #                        name => $gdd_term_string,
    #                        cv => 'cxgn_time_ontology'
    #                     });
    #                     $gdd_cvterm_id = $new_gdd_term->cvterm_id();
    #                 }
    #                 my $time_gdd_term_string = SGN::Model::Cvterm::get_trait_from_cvterm_id($schema, $gdd_cvterm_id, 'extended');
    #
    #                 $phenotype_data_htp_rel{$obs_unit->{observationunit_uniquename}}->{$_->{trait_name}} = $_->{value};
    #                 $seen_times_htp_rel{$_->{trait_name}} = [$time_days_value, $time_days_term_string, $time_gdd_value, $time_gdd_term_string];
    #             }
    #         }
    #     }
    #     $h_time = undef;
    #
    #     #my @allowed_standard_htp_values = ('Nonzero Pixel Count', 'Total Pixel Sum', 'Mean Pixel Value', 'Harmonic Mean Pixel Value', 'Median Pixel Value', 'Pixel Variance', 'Pixel Standard Deviation', 'Pixel Population Standard Deviation', 'Minimum Pixel Value', 'Maximum Pixel Value', 'Minority Pixel Value', 'Minority Pixel Count', 'Majority Pixel Value', 'Majority Pixel Count', 'Pixel Group Count');
    #     my @allowed_standard_htp_values = ('Mean Pixel Value');
    #     my %filtered_seen_times_htp_rel;
    #     while (my ($t, $time) = each %seen_times_htp_rel) {
    #         my $allowed = 0;
    #         foreach (@allowed_standard_htp_values) {
    #             if (index($t, $_) != -1) {
    #                 $allowed = 1;
    #                 last;
    #             }
    #         }
    #         if ($allowed) {
    #             $filtered_seen_times_htp_rel{$t} = $time;
    #         }
    #     }
    #
    #     my @filtered_seen_times_htp_rel_sorted = sort keys %filtered_seen_times_htp_rel;
    #
    #     my @header_htp = ('plot_id', 'plot_name', 'accession_id', 'accession_name', 'rep', 'block');
    #
    #     my %trait_name_encoder_htp;
    #     my %trait_name_encoder_rev_htp;
    #     my $trait_name_encoded_htp = 1;
    #     my @header_traits_htp;
    #     foreach my $trait_name (@filtered_seen_times_htp_rel_sorted) {
    #         if (!exists($trait_name_encoder_htp{$trait_name})) {
    #             my $trait_name_e = 't'.$trait_name_encoded_htp;
    #             $trait_name_encoder_htp{$trait_name} = $trait_name_e;
    #             $trait_name_encoder_rev_htp{$trait_name_e} = $trait_name;
    #             push @header_traits_htp, $trait_name_e;
    #             $trait_name_encoded_htp++;
    #         }
    #     }
    #
    #     my @htp_pheno_matrix;
    #     push @header_htp, @header_traits_htp;
    #     push @htp_pheno_matrix, \@header_htp;
    #
    #     foreach my $p (@seen_plots) {
    #         my $obj = $seen_plot_names_htp_rel{$p};
    #         my @row = ($obj->{observationunit_stock_id}, $obj->{observationunit_uniquename}, $obj->{germplasm_stock_id}, $obj->{germplasm_uniquename}, $obj->{obsunit_rep}, $obj->{obsunit_block});
    #         foreach my $t (@filtered_seen_times_htp_rel_sorted) {
    #             my $val = $phenotype_data_htp_rel{$p}->{$t} + 0;
    #             push @row, $val;
    #         }
    #         push @htp_pheno_matrix, \@row;
    #     }
    #
    #     open(my $htp_pheno_f, ">", $stats_out_htp_rel_tempfile_input) || die "Can't open file ".$stats_out_htp_rel_tempfile_input;
    #         foreach (@htp_pheno_matrix) {
    #             my $line = join "\t", @$_;
    #             print $htp_pheno_f $line."\n";
    #         }
    #     close($htp_pheno_f);
    # };

    my @result_blups_all;
    my $q = 'SELECT nd_protocol.nd_protocol_id, nd_protocol.name, nd_protocol.description, basename, dirname, md.file_id, md.filetype, nd_protocol.type_id, nd_experiment.type_id
        FROM metadata.md_files AS md
        JOIN metadata.md_metadata AS meta ON (md.metadata_id=meta.metadata_id)
        JOIN phenome.nd_experiment_md_files using(file_id)
        JOIN nd_experiment using(nd_experiment_id)
        JOIN nd_experiment_protocol using(nd_experiment_id)
        JOIN nd_protocol using(nd_protocol_id)
        WHERE nd_protocol.nd_protocol_id=? AND nd_experiment.type_id=?
        AND md.filetype like \'%nicksmixedmodelsanalytics_v1%\' AND md.filetype like \'%datafile%\' AND (md.filetype like \'%originalgenoeff%\' OR md.filetype like \'%fullcorr%\')
        ORDER BY md.file_id ASC
        LIMIT 2;';
    print STDERR $q."\n";
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute($protocol_id, $analytics_experiment_type_cvterm_id);
    while (my ($model_id, $model_name, $model_description, $basename, $filename, $file_id, $filetype, $model_type_id, $experiment_type_id, $property_type_id, $property_value) = $h->fetchrow_array()) {
        my $result_type;
        if (index($filetype, 'originalgenoeff') != -1) {
            $result_type = 'originalgenoeff';
        }
        elsif (index($filetype, 'fullcorr') != -1) {
            $result_type = 'fullcorr';
        }
        else {
            next;
        }

        my $parameter = '';
        my $sim_var = '';
        if (index($filetype, '0.1') != -1) {
            $parameter = "Simulation Variance = 0.1";
            $sim_var = 0.1;
        }
        elsif (index($filetype, '0.2') != -1) {
            $parameter = "Simulation Variance = 0.2";
            $sim_var = 0.2;
        }
        elsif (index($filetype, '0.3') != -1) {
            $parameter = "Simulation Variance = 0.3";
            $sim_var = 0.3;
        }

        my $time_change = 'Constant';
        if (index($filetype, 'changing_gradual') != -1) {
            if (index($filetype, '0.75') != -1) {
                $time_change = "Correlated 0.75";
            }
            elsif (index($filetype, '0.9') != -1) {
                $time_change = "Correlated 0.9";
            }
        }

        my $model_name = '';
        my $is_random_regression;
        if (index($filetype, 'airemlf90_grm_random_regression') != -1) {
            $is_random_regression = 1;
            if (index($filetype, 'identity') != -1) {
                $model_name = "RR_IDPE";
            }
            elsif (index($filetype, 'euclidean_rows_and_columns') != -1) {
                $model_name = "RR_EucPE";
            }
            elsif (index($filetype, 'phenotype_2dspline_effect') != -1) {
                $model_name = "RR_2DsplTraitPE";
            }
            elsif (index($filetype, 'phenotype_ar1xar1_effect') != -1) {
                $model_name = "RR_AR1xAR1TraitPE";
            }
            elsif (index($filetype, 'phenotype_correlation') != -1) {
                $model_name = "RR_CorrTraitPE";
            }
        }
        elsif (index($filetype, 'asreml_grm_univariate_pure') != -1) {
            $model_name = 'AR1_Uni';
        }
        elsif (index($filetype, 'sommer_grm_spatial_pure') != -1) {
            $model_name = '2Dspl_Multi';
        }
        elsif (index($filetype, 'sommer_grm_univariate_spatial_pure') != -1) {
            $model_name = '2Dspl_Uni';
        }
        elsif (index($filetype, 'asreml_grm_multivariate') != -1) {
            $model_name = 'AR1_Multi';
        }
        else {
            $c->stash->{rest} = { error => "The model was not recognized for $filetype!"};
            return;
        }

        my @all_local_env_vals;
        my %germplasm_result_blups;
        my %germplasm_result_time_blups;
        my %plot_result_blups;
        my %plot_result_time_blups;
        my %seen_times_g;
        my %seen_times_p;
        my $file_destination = File::Spec->catfile($filename, $basename);
        open(my $fh, '<', $file_destination) or die "Could not open file '$file_destination' $!";
            print STDERR "Opened $file_destination\n";

            my $header = <$fh>;
            my @header_columns;
            if ($csv->parse($header)) {
                @header_columns = $csv->fields();
            }

            while (my $row = <$fh>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                if ($result_type eq 'originalgenoeff') {
                    my $germplasm_name = $columns[0];
                    my $time = $columns[1];
                    my $value = $columns[2];
                    push @{$germplasm_result_blups{$germplasm_name}}, $value;
                    $germplasm_result_time_blups{$germplasm_name}->{$time} = $value;
                    $seen_times_g{$time}++;
                }
                elsif ($result_type eq 'fullcorr') {
                    my $plot_name = $columns[0];
                    my $plot_id = $columns[1];

                    my $total_num_t;
                    # if (!$is_random_regression) {
                        $total_num_t = $observation_variable_number;
                    # }
                    # else {
                    #     $total_num_t = $legendre_poly_number;
                    # }

                    # if (!$is_random_regression) {
                        for my $iter (0..$total_num_t-1) {
                            my $step = 10+($iter*22);

                            my $col_name = $header_columns[$step];
                            my ($eff, $mod, $time) = split '_', $col_name;
                            my $time_val = $trait_name_map{$time};
                            my $value = $columns[$step];
                            push @{$plot_result_blups{$plot_name}}, $value;
                            $plot_result_time_blups{$plot_name}->{$time_val} = $value;
                            $seen_times_p{$time_val}++;
                            push @all_local_env_vals, $value;
                        }
                    # }
                    # else {
                    #     my @coeffs;
                    #     for my $iter (0..$total_num_t-1) {
                    #         my $step = 10+($iter*22);
                    #
                    #         my $col_name = $header_columns[$step];
                    #         my ($eff, $mod, $time) = split '_', $col_name;
                    #         my $time_val = $trait_name_map{$time};
                    #         my $value = $columns[$step];
                    #         push @coeffs, $value;
                    #     }
                    #     foreach my $t_i (0..20) {
                    #         my $time = $t_i*5/100;
                    #         my $time_rescaled = sprintf("%.2f", $time*($max_time_htp - $min_time_htp) + $min_time_htp);
                    #
                    #         my $value = 0;
                    #         my $coeff_counter = 0;
                    #         foreach my $b (@coeffs) {
                    #             my $eval_string = $legendre_coeff_exec[$coeff_counter];
                    #             # print STDERR Dumper [$eval_string, $b, $time];
                    #             $value += eval $eval_string;
                    #             $coeff_counter++;
                    #         }
                    #         push @{$plot_result_blups{$plot_name}}, $value;
                    #         $plot_result_time_blups{$plot_name}->{$time_rescaled} = $value;
                    #         $seen_times_p{$time_rescaled}++;
                    #     }
                    # }
                }
            }
        close($fh);
        # print STDERR Dumper \%plot_result_time_blups;
        # print STDERR Dumper \%germplasm_result_time_blups;

        my @sorted_seen_times_g = sort { $a <=> $b } keys %seen_times_g;
        my @sorted_seen_times_p = sort { $a <=> $b } keys %seen_times_p;
        my $number_time_points = scalar(@sorted_seen_times_p);
        my $number_time_points_half = round($number_time_points/2);
        my $number_time_points_1third = round($number_time_points/3);

        my $stat = Statistics::Descriptive::Full->new();
        $stat->add_data(@all_local_env_vals);
        my $cutoff_25 = $stat->quantile(1);
        my $cutoff_50 = $stat->quantile(2);
        my $cutoff_75 = $stat->quantile(3);

        my $analytics_protocol_data_tempfile10 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile11 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile12 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile13 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile14 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile15 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile16 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile17 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile18 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile19 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile20 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile21= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile22= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile23= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile24= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile25= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile26= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile27= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile28= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile29= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile30= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_favg_gcorr= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_f2_gcorr= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_f3_gcorr= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_havg_gcorr= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_fmax_gcorr= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_fmin_gcorr= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_grm_gcorr= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_prm_gcorr= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_grm_id_gcorr= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_grm_prm_gcorr= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_grm_id_prm_gcorr= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_grm_id_prm_id_gcorr= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_grm_prm_secondary_gcorr= $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_fixed_q1 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_fixed_q2 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_fixed_q3 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_fixed_q4 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_prm_q1 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_prm_q2 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_prm_q3 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_prm_q4 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_prm_sec_q1 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_prm_sec_q2 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_prm_sec_q3 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_prm_sec_q4 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_prm_sec_fix_q1 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_prm_sec_fix_q2 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_prm_sec_fix_q3 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile_prm_sec_fix_q4 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

        my $analytics_protocol_tempfile_string_1 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string_1 .= '.png';
        my $analytics_protocol_figure_tempfile_1 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_1;

        my $analytics_protocol_tempfile_string_2 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string_2 .= '.png';
        my $analytics_protocol_figure_tempfile_2 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_2;

        my $analytics_protocol_tempfile_string_3 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string_3 .= '.png';
        my $analytics_protocol_figure_tempfile_3 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_3;

        my $analytics_protocol_tempfile_string_4 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string_4 .= '.png';
        my $analytics_protocol_figure_tempfile_4 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_4;

        my $analytics_protocol_tempfile_string_5 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string_5 .= '.png';
        my $analytics_protocol_figure_tempfile_5 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_5;

        my $analytics_protocol_tempfile_string_6 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string_6 .= '.png';
        my $analytics_protocol_figure_tempfile_6 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_6;

        my $analytics_protocol_tempfile_string_7 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string_7 .= '.png';
        my $analytics_protocol_figure_tempfile_7 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_7;

        my $analytics_protocol_tempfile_string_8 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string_8 .= '.png';
        my $analytics_protocol_figure_tempfile_8 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_8;

        my $analytics_protocol_tempfile_string_9 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string_9 .= '.png';
        my $analytics_protocol_figure_tempfile_9 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_9;

        my $analytics_protocol_tempfile_string_10 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string_10 .= '.png';
        my $analytics_protocol_figure_tempfile_10 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_10;

        my %plot_fixed_effects;
        my %plot_fixed_effects_cont;
        my %plot_fixed_effects_3;
        my %plot_fixed_effects_3_cont;
        my %plot_averaged_fixed_effect_cont;
        my %plot_averaged_fixed_effect_maximum;
        my %plot_averaged_fixed_effect_minimum;
        my %plot_averaged_fixed_effect;
        my %plot_averaged_fixed_effects;
        my %plot_averaged_fixed_effects_3;
        my %plot_averaged_fixed_effects_3_cont;

        my @germplasm_results;
        my @germplasm_data = ();
        my @germplasm_data_header = ("germplasmName");
        my @germplasm_data_values = ();
        my @germplasm_data_values_header = ();
        my @plots_avg_results;
        my @plots_avg_data = ();
        my @plots_avg_data_header = ("plotName", "germplasmName");
        my @plots_avg_data_values = ();
        my @plots_avg_data_values_header = ();
        my @plots_avg_data_heatmap_values_header = ("trait_type", "row", "col", "value");
        my @plots_avg_data_heatmap_values = ();
        my @plots_avg_data_heatmap_values_traits_header = ("trait_type", "row", "col", "value");
        my @plots_avg_data_heatmap_values_traits = ();
        my @plots_avg_data_heatmap_values_traits_corrected_header = ("trait_type", "row", "col", "value");
        my @plots_avg_data_heatmap_values_traits_corrected = ();
        my @plots_avg_data_heatmap_values_traits_secondary_header = ("trait_type", "row", "col", "value");
        my @plots_avg_data_heatmap_values_traits_secondary = ();
        my @plots_h_results;
        my @germplasm_data_iteration_header = ("germplasmName", "tmean", "time", "value");
        my @germplasm_data_iteration_data_values = ();
        my @plots_data_iteration_header = ("plotName", "tvalue", "time", "value");
        my @plots_data_iteration_data_values = ();

        my @plots_data_grm_prm_data_values = ();
        my @plots_data_grm_prm_data_values_q1 = ();
        my @plots_data_grm_prm_data_values_q2 = ();
        my @plots_data_grm_prm_data_values_q3 = ();
        my @plots_data_grm_prm_data_values_q4 = ();
        my @plots_data_grm_prm_secondary_traits_data_values = ();
        my @plots_data_grm_prm_secondary_traits_data_values_q1 = ();
        my @plots_data_grm_prm_secondary_traits_data_values_q2 = ();
        my @plots_data_grm_prm_secondary_traits_data_values_q3 = ();
        my @plots_data_grm_prm_secondary_traits_data_values_q4 = ();
        my @plots_data_grm_prm_secondary_traits_fixed_data_values = ();
        my @plots_data_grm_prm_secondary_traits_fixed_data_values_q1 = ();
        my @plots_data_grm_prm_secondary_traits_fixed_data_values_q2 = ();
        my @plots_data_grm_prm_secondary_traits_fixed_data_values_q3 = ();
        my @plots_data_grm_prm_secondary_traits_fixed_data_values_q4 = ();
        my @varcomp_original_grm;
        my @varcomp_original_grm_fixed_effect;
        my @varcomp_original_grm_fixed_effects;
        my @varcomp_original_grm_fixed_effects_3;
        my @varcomp_original_grm_fixed_effects_cont;
        my @varcomp_original_grm_fixed_effects_min;
        my @varcomp_original_grm_fixed_effects_max;
        my @varcomp_original_grm_fixed_effects_all;
        my @varcomp_original_grm_fixed_effects_f3_cont;
        my @varcomp_original_grm_id;
        my @varcomp_original_grm_prm;
        my @varcomp_original_grm_prm_secondary_traits;
        my @varcomp_original_grm_id_prm;
        my @varcomp_original_grm_id_prm_id;
        my @varcomp_original_prm;
        my @varcomp_original_grm_prm_secondary_traits_favg;
        my @varcomp_original_grm_prm_secondary_traits_havg;
        my @varcomp_h_grm;
        my @varcomp_h_grm_fixed_effect;
        my @varcomp_h_grm_fixed_effects;
        my @varcomp_h_grm_fixed_effects_3;
        my @varcomp_h_grm_fixed_effects_cont;
        my @varcomp_h_grm_fixed_effects_min;
        my @varcomp_h_grm_fixed_effects_max;
        my @varcomp_h_grm_fixed_effects_all;
        my @varcomp_h_grm_fixed_effects_f3_cont;
        my @varcomp_h_grm_id;
        my @varcomp_h_grm_id_prm;
        my @varcomp_h_grm_id_prm_id;
        my @varcomp_h_grm_prm;
        my @varcomp_h_grm_prm_secondary_traits;
        my @varcomp_h_prm;
        my @varcomp_h_grm_prm_secondary_traits_favg;
        my @varcomp_h_grm_prm_secondary_traits_havg;
        my @fits_grm;
        my @fits_grm_fixed_effect;
        my @fits_grm_fixed_effects;
        my @fits_grm_fixed_effects_3;
        my @fits_grm_fixed_effects_cont;
        my @fits_grm_fixed_effects_min;
        my @fits_grm_fixed_effects_max;
        my @fits_grm_fixed_effects_all;
        my @fits_grm_fixed_effects_f3_cont;
        my @fits_grm_id;
        my @fits_grm_id_prm;
        my @fits_grm_id_prm_id;
        my @fits_grm_prm;
        my @fits_grm_prm_secondary_traits;
        my @fits_prm;
        my @fits_grm_prm_secondary_traits_favg;
        my @fits_grm_prm_secondary_traits_havg;
        my $gcorr_favg;
        my $gcorr_f2;
        my $gcorr_f3;
        my $gcorr_havg;
        my $gcorr_fmax;
        my $gcorr_fmin;
        my $gcorr_fall;
        my $gcorr_f3_cont;
        my $gcorr_grm;
        my $gcorr_grm_id;
        my $gcorr_prm;
        my $gcorr_grm_prm;
        my $gcorr_grm_id_prm;
        my $gcorr_grm_id_prm_id;
        my $gcorr_grm_prm_secondary_traits;
        my @gcorr_grm_prm_secondary_traits_favg;
        my @gcorr_grm_prm_secondary_traits_havg;
        my $gcorr_q_favg;
        my $gcorr_q_f2;
        my $gcorr_q_f3;
        my $gcorr_q_havg;
        my $gcorr_q_fmax;
        my $gcorr_q_fmin;
        my $gcorr_q_fall;
        my $gcorr_q_f3_cont;
        my $gcorr_q_grm;
        my $gcorr_q_grm_id;
        my $gcorr_q_prm;
        my $gcorr_q_grm_prm;
        my $gcorr_q_grm_id_prm;
        my $gcorr_q_grm_id_prm_id;
        my $gcorr_q_grm_prm_secondary_traits;
        my @gcorr_q_grm_prm_secondary_traits_favg;
        my @gcorr_q_grm_prm_secondary_traits_havg;
        my @gcorr_qarr_favg;
        my @gcorr_qarr_f2;
        my @gcorr_qarr_f3;
        my @gcorr_qarr_havg;
        my @gcorr_qarr_fmax;
        my @gcorr_qarr_fmin;
        my @gcorr_qarr_fall;
        my @gcorr_qarr_f3_cont;
        my @gcorr_qarr_grm;
        my @gcorr_qarr_grm_id;
        my @gcorr_qarr_prm;
        my @gcorr_qarr_grm_prm;
        my @gcorr_qarr_grm_id_prm;
        my @gcorr_qarr_grm_id_prm_id;
        my @gcorr_qarr_grm_prm_secondary_traits;
        my @gcorr_qarr_grm_prm_secondary_traits_favg;
        my @gcorr_qarr_grm_prm_secondary_traits_havg;
        my @f_anova_grm_fixed_effect;
        my @f_anova_grm_fixed_effects;
        my @f_anova_grm_fixed_effects_3;
        my @f_anova_grm_fixed_effects_cont;
        my @f_anova_grm_fixed_effects_max;
        my @f_anova_grm_fixed_effects_min;
        my @f_anova_grm_fixed_effects_all;
        my @f_anova_grm_fixed_effects_f3_cont;
        my @f_anova_grm_prm_secondary_traits_havg;
        my @f_anova_grm_prm_secondary_traits_favg;
        my $reps_acc_havg;
        my $reps_acc_f3_cont;
        my $reps_acc_grm_prm;
        my $reps_test_acc_havg;
        my $reps_test_acc_f3_cont;
        my $reps_test_acc_grm_prm;
        my @reps_acc_cross_val;
        my @reps_acc_cross_val_havg;
        my @reps_acc_cross_val_traits;
        my @reps_acc_cross_val_havg_and_traits;

        foreach my $t (@sorted_trait_names) {
            push @germplasm_data_header, ($t."mean", $t."sd", $t."spatialcorrected2Dsplgenoeffect");
            push @germplasm_data_values_header, ($t."mean", $t."spatialcorrected2Dsplgenoeffect");
        }

        if ($result_type eq 'originalgenoeff') {
            push @germplasm_data_header, ("htpspatialcorrectedgenoeffectmean", "htpspatialcorrectedgenoeffectsd");
            push @germplasm_data_values_header, "htpspatialcorrectedgenoeffectmean";

            foreach my $time (@sorted_seen_times_g) {
                push @germplasm_data_header, "htpspatialcorrectedgenoeffect$time";
                push @germplasm_data_values_header, "htpspatialcorrectedgenoeffect$time";
            }
        }
        elsif ($result_type eq 'fullcorr') {
            push @plots_avg_data_header, ("htpspatialeffectsd","htpspatialeffectmean");
            push @plots_avg_data_values_header, "htpspatialeffectmean";

            foreach my $t (@sorted_trait_names) {

                push @plots_avg_data_header, $t;
                push @plots_avg_data_values_header, $t;
                if ($analysis_run_type eq '2dspl' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wRow' || $analysis_run_type eq '2dspl_ar1_wRowCol' || $analysis_run_type eq '2dspl_ar1_wRowPlusCol' || $analysis_run_type eq '2dspl_ar1_wColPlusRow' ) {
                    push @plots_avg_data_header, ($t."spatial2Dspl", $t."2Dsplcorrected");
                    # push @plots_avg_data_values_header, ($t."spatial2Dspl", $t."2Dsplcorrected");
                    push @plots_avg_data_values_header, $t."spatial2Dspl";
                }
                if ($analysis_run_type eq 'ar1' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq 'ar1_wCol' || $analysis_run_type eq 'ar1_wRow' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wRow' || $analysis_run_type eq '2dspl_ar1_wRowCol' || $analysis_run_type eq '2dspl_ar1_wRowPlusCol' || $analysis_run_type eq '2dspl_ar1_wColPlusRow' ) {
                    push @plots_avg_data_header, ($t."spatialAR1", $t."AR1corrected");
                    # push @plots_avg_data_values_header, ($t."spatialAR1", $t."AR1corrected");
                    push @plots_avg_data_values_header, $t."spatialAR1";
                }
                push @plots_avg_data_header, $t."spatialcorrecthtpmean";
                # push @plots_avg_data_values_header, $t."spatialcorrecthtpmean";

                foreach my $time (@sorted_seen_times_p) {
                    push @plots_avg_data_header, ("htpspatialeffect$time", "traithtpspatialcorrected$time");
                    # push @plots_avg_data_values_header, ("htpspatialeffect$time", "traithtpspatialcorrected$time");
                    push @plots_avg_data_values_header, "htpspatialeffect$time";
                }
            }
            foreach my $t (@sorted_trait_names_secondary) {
                push @plots_avg_data_header, $t;
                push @plots_avg_data_values_header, $t;
            }
        }

        foreach my $g (@seen_germplasm) {
            my @line = ($g); #germplasmName
            my @values;

            foreach my $t (@sorted_trait_names) {
                my $trait_phenos = $germplasm_phenotypes{$g}->{$t};
                my $trait_pheno_stat = Statistics::Descriptive::Full->new();
                $trait_pheno_stat->add_data(@$trait_phenos);
                my $sd = $trait_pheno_stat->standard_deviation();
                my $mean = $trait_pheno_stat->mean();

                my $geno_trait_spatial_val = $result_blup_data_s->{$g}->{$t};
                push @line, ($mean, $sd, $geno_trait_spatial_val); #$t."mean", $t."sd", $t."spatialcorrected2Dsplgenoeffect"
                push @values, ($mean, $geno_trait_spatial_val); #$t."mean", $t."spatialcorrected2Dsplgenoeffect"

                foreach my $time (@sorted_seen_times_g) {
                    my $val = $germplasm_result_time_blups{$g}->{$time};
                    push @germplasm_data_iteration_data_values, [$g, $mean, $time, $val]; #"germplasmName", "tmean", "time", "value"
                }
            }

            if ($result_type eq 'originalgenoeff') {
                my $geno_blups = $germplasm_result_blups{$g};
                my $geno_blups_stat = Statistics::Descriptive::Full->new();
                $geno_blups_stat->add_data(@$geno_blups);
                my $geno_sd = $geno_blups_stat->standard_deviation();
                my $geno_mean = $geno_blups_stat->mean();

                push @line, ($geno_mean, $geno_sd); #"htpspatialcorrectedgenoeffectmean", "htpspatialcorrectedgenoeffectsd"
                push @values, $geno_mean; #"htpspatialcorrectedgenoeffectmean"

                foreach my $time (@sorted_seen_times_g) {
                    my $val = $germplasm_result_time_blups{$g}->{$time};
                    push @line, $val; #"htpspatialcorrectedgenoeffect$time"
                    push @values, $val; #"htpspatialcorrectedgenoeffect$time"
                }
            }
            push @germplasm_data, \@line;
            push @germplasm_data_values, \@values;
        }

        my @type_names_first_line;
        my @type_names_first_line_traits;
        my @type_names_first_line_traits_corrected;
        my @type_names_first_line_secondary;
        my $is_first_plot = 1;
        foreach my $p (@seen_plots) {
            my $germplasm_name = $plot_germplasm_map{$p};
            my @line = ($p, $germplasm_name); #"plotName", "germplasmName"
            my @values;
            my @plots_grm_prm_values;
            my @plots_grm_prm_secondary_traits_values;
            my @plots_grm_prm_secondary_traits_fixed_values;

            my $row_number = $stock_name_row_col{$p}->{row_number};
            my $col_number = $stock_name_row_col{$p}->{col_number};

            foreach my $t (@sorted_trait_names) {
                my $val = $plot_phenotypes{$p}->{$t} || '';
                foreach my $time (@sorted_seen_times_p) {
                    my $sval = $plot_result_time_blups{$p}->{$time};
                    push @plots_data_iteration_data_values, [$p, $val, $time, $sval]; #"plotName", "tvalue", "time", "value"
                }

                my $time_point_counter = 1;
                my $fixed_eff_counter = 1;
                foreach my $time (@sorted_seen_times_p) {
                    my $sval = $plot_result_time_blups{$p}->{$time};

                    my $fixed_val;
                    if ($sval <= $cutoff_25) {
                        $fixed_val = 0;
                    }
                    elsif ($sval <= $cutoff_50) {
                        $fixed_val = 1;
                    }
                    elsif ($sval <= $cutoff_75) {
                        $fixed_val = 2;
                    }
                    else {
                        $fixed_val = 3;
                    }

                    push @{$plot_fixed_effects{$p}->{$fixed_eff_counter}}, $fixed_val;
                    push @{$plot_fixed_effects_cont{$p}}, $sval;

                    if ($time_point_counter >= $number_time_points_half) {
                        $fixed_eff_counter++;
                        $time_point_counter = 0;
                    }

                    $time_point_counter++;
                }
                foreach my $time (@sorted_seen_times_p) {
                    my $sval = $plot_result_time_blups{$p}->{$time};

                    my $fixed_val;
                    if ($sval <= $cutoff_25) {
                        $fixed_val = 0;
                    }
                    elsif ($sval <= $cutoff_50) {
                        $fixed_val = 1;
                    }
                    elsif ($sval <= $cutoff_75) {
                        $fixed_val = 2;
                    }
                    else {
                        $fixed_val = 3;
                    }

                    my $gdd_val = $dap_to_gdd_hash{$time};
                    my $rep_growth_fixed;
                    if ($gdd_val <= $r0_gdd) {
                        $rep_growth_fixed = 1;
                    }
                    elsif ($gdd_val <= $r1_gdd) {
                        $rep_growth_fixed = 2;
                    }
                    elsif ($gdd_val <= $r2_gdd) {
                        $rep_growth_fixed = 3;
                    }

                    push @{$plot_fixed_effects_3{$p}->{$rep_growth_fixed}}, $fixed_val;
                    push @{$plot_fixed_effects_3_cont{$p}->{$rep_growth_fixed}}, $sval;
                }
            }

            if ($result_type eq 'fullcorr') {
                my $plot_blups = $plot_result_blups{$p};
                my $plot_blups_stat = Statistics::Descriptive::Full->new();
                $plot_blups_stat->add_data(@$plot_blups);
                my $plot_sd = $plot_blups_stat->standard_deviation();
                my $plot_mean = $plot_blups_stat->mean();
                my $plot_mean_scaled = $plot_mean*($max_phenotype/$max_phenotype_htp);

                push @line, ($plot_sd, $plot_mean_scaled); #"htpspatialeffectsd","htpspatialeffectmean"
                push @values, $plot_mean_scaled; #"htpspatialeffectmean"
                push @plots_avg_data_heatmap_values, ["HTPspatialmean", $row_number, $col_number, $plot_mean]; #"trait_type", "row", "col", "value"

                if ($is_first_plot) {
                    push @type_names_first_line, "HTPspatialmean";
                }

                foreach my $t (@sorted_trait_names) {
                    my $trait_val = $plot_phenotypes{$p}->{$t} || 0;
                    my $val = $trait_val - $plot_mean_scaled;

                    push @plots_avg_data_heatmap_values_traits, ["TraitPhenotype", $row_number, $col_number, $trait_val]; #"trait_type", "row", "col", "value"
                    push @plots_avg_data_heatmap_values_traits, ["TraitHTPspatialMeanCorrected", $row_number, $col_number, $val]; #"trait_type", "row", "col", "value"
                    if ($is_first_plot) {
                        push @type_names_first_line_traits, ("TraitPhenotype", "TraitHTPspatialMeanCorrected");
                    }

                    push @line, $trait_val;
                    push @values, $trait_val;
                    if ($analysis_run_type eq '2dspl' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wRow' || $analysis_run_type eq '2dspl_ar1_wRowCol' || $analysis_run_type eq '2dspl_ar1_wRowPlusCol' || $analysis_run_type eq '2dspl_ar1_wColPlusRow') {
                        my $env_trait_spatial_val = $result_blup_spatial_data_s->{$p}->{$t};
                        my $trait_val_2dspl_corrected = $trait_val - $env_trait_spatial_val;
                        push @line, ($env_trait_spatial_val, $trait_val_2dspl_corrected);
                        # push @values, ($env_trait_spatial_val, $trait_val_2dspl_corrected);
                        push @values, $env_trait_spatial_val;
                        push @plots_avg_data_heatmap_values_traits_corrected, ["TraitSpatial2Dspl", $row_number, $col_number, $env_trait_spatial_val]; #"trait_type", "row", "col", "value"
                        push @plots_avg_data_heatmap_values_traits, ["Trait2DsplCorrected", $row_number, $col_number, $trait_val_2dspl_corrected]; #"trait_type", "row", "col", "value"

                        if ($is_first_plot) {
                            push @type_names_first_line_traits_corrected, "TraitSpatial2Dspl";
                            push @type_names_first_line_traits, "Trait2DsplCorrected";
                        }
                    }
                    if ($analysis_run_type eq 'ar1' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq 'ar1_wCol' || $analysis_run_type eq 'ar1_wRow' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wRow' || $analysis_run_type eq '2dspl_ar1_wRowCol' || $analysis_run_type eq '2dspl_ar1_wRowPlusCol' || $analysis_run_type eq '2dspl_ar1_wColPlusRow') {
                        my $env_trait_spatial_ar1_val = $result_blup_spatial_data_ar1->{$p}->{$t};
                        my $trait_val_ar1_corrected = $trait_val - $env_trait_spatial_ar1_val;
                        push @line, ($env_trait_spatial_ar1_val, $trait_val_ar1_corrected);
                        # push @values, ($env_trait_spatial_ar1_val, $trait_val_ar1_corrected);
                        push @values, $env_trait_spatial_ar1_val;
                        push @plots_avg_data_heatmap_values_traits_corrected, ["TraitSpatialAR1", $row_number, $col_number, $env_trait_spatial_ar1_val]; #"trait_type", "row", "col", "value"
                        push @plots_avg_data_heatmap_values_traits, ["TraitAR1Corrected", $row_number, $col_number, $trait_val_ar1_corrected]; #"trait_type", "row", "col", "value"

                        if ($is_first_plot) {
                            push @type_names_first_line_traits_corrected, "TraitSpatialAR1";
                            push @type_names_first_line_traits, "TraitAR1Corrected";
                        }
                    }
                    push @line, $val; #$t, $t."spatial2Dspl", $t."2Dsplcorrected", $t."spatialAR1", $t."AR1corrected", $t."spatialcorrecthtpmean"
                    # push @values, $val; #$t, $t."spatial2Dspl", $t."2Dsplcorrected", $t."spatialAR1", $t."AR1corrected", $t."spatialcorrecthtpmean"

                    foreach my $time (@sorted_seen_times_p) {
                        my $time_val = $plot_result_time_blups{$p}->{$time};
                        my $time_val_scaled = $time_val*($max_phenotype/$max_phenotype_htp);
                        my $val = $trait_val - $time_val_scaled;
                        push @line, ($time_val, $val); #"htpspatialeffect$time", "traithtpspatialcorrected$time"
                        # push @values, ($time_val, $val); #"htpspatialeffect$time", "traithtpspatialcorrected$time"
                        push @values, $time_val; #"htpspatialeffect$time"
                        push @plots_avg_data_heatmap_values, ["HTPspatial$time", $row_number, $col_number, $time_val]; #"trait_type", "row", "col", "value"
                        push @plots_avg_data_heatmap_values_traits, ["TraitHTPspatialCorrected$time", $row_number, $col_number, $val]; #"trait_type", "row", "col", "value"

                        push @plots_grm_prm_values, $time_val;

                        if ($is_first_plot) {
                            push @type_names_first_line, "HTPspatial$time";
                            push @type_names_first_line_traits, "TraitHTPspatialCorrected$time";
                        }
                    }
                }
                foreach my $t (@sorted_trait_names_secondary) {
                    my $trait_secondary_val = $plot_phenotypes_secondary{$p}->{$t} || 0;
                    push @line, $trait_secondary_val;
                    push @values, $trait_secondary_val;
                    push @plots_avg_data_heatmap_values_traits_secondary, [$t, $row_number, $col_number, $trait_secondary_val]; #"trait_type", "row", "col", "value"

                    push @plots_grm_prm_secondary_traits_values, $trait_secondary_val;

                    my ($cutoff_25, $cutoff_50, $cutoff_75) = @{$plot_phenotypes_secondary_cutoff_data{$t}->{cutoffs}};
                    my $fixed_val;
                    if ($trait_secondary_val <= $cutoff_25) {
                        $fixed_val = 0;
                    }
                    elsif ($trait_secondary_val <= $cutoff_50) {
                        $fixed_val = 1;
                    }
                    elsif ($trait_secondary_val <= $cutoff_75) {
                        $fixed_val = 2;
                    }
                    else {
                        $fixed_val = 3;
                    }

                    if ($is_first_plot) {
                        push @type_names_first_line_secondary, $t;
                    }
                    push @plots_grm_prm_secondary_traits_fixed_values, $fixed_val;
                }
            }
            push @plots_avg_data, \@line;
            push @plots_avg_data_values, \@values;
            push @plots_data_grm_prm_data_values, \@plots_grm_prm_values;
            push @plots_data_grm_prm_secondary_traits_data_values, \@plots_grm_prm_secondary_traits_values;
            push @plots_data_grm_prm_secondary_traits_fixed_data_values, \@plots_grm_prm_secondary_traits_fixed_values;

            if ($row_number <= $max_row_half) {
                if ($col_number <= $max_col_half) {
                    push @plots_data_grm_prm_data_values_q1, \@plots_grm_prm_values;
                    push @plots_data_grm_prm_secondary_traits_data_values_q1, \@plots_grm_prm_secondary_traits_values;
                    push @plots_data_grm_prm_secondary_traits_fixed_data_values_q1, \@plots_grm_prm_secondary_traits_fixed_values;
                }
                else {
                    push @plots_data_grm_prm_data_values_q2, \@plots_grm_prm_values;
                    push @plots_data_grm_prm_secondary_traits_data_values_q2, \@plots_grm_prm_secondary_traits_values;
                    push @plots_data_grm_prm_secondary_traits_fixed_data_values_q2, \@plots_grm_prm_secondary_traits_fixed_values;
                }
            }
            else {
                if ($col_number <= $max_col_half) {
                    push @plots_data_grm_prm_data_values_q3, \@plots_grm_prm_values;
                    push @plots_data_grm_prm_secondary_traits_data_values_q3, \@plots_grm_prm_secondary_traits_values;
                    push @plots_data_grm_prm_secondary_traits_fixed_data_values_q3, \@plots_grm_prm_secondary_traits_fixed_values;
                }
                else {
                    push @plots_data_grm_prm_data_values_q4, \@plots_grm_prm_values;
                    push @plots_data_grm_prm_secondary_traits_data_values_q4, \@plots_grm_prm_secondary_traits_values;
                    push @plots_data_grm_prm_secondary_traits_fixed_data_values_q4, \@plots_grm_prm_secondary_traits_fixed_values;
                }
            }

            $is_first_plot = 0;
        }

        if ($analysis_run_type eq '2dspl' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wRow' || $analysis_run_type eq '2dspl_ar1_wRowCol' || $analysis_run_type eq '2dspl_ar1_wRowPlusCol' || $analysis_run_type eq '2dspl_ar1_wColPlusRow') {
            open(my $F10, ">", $analytics_protocol_data_tempfile10) || die "Can't open file ".$analytics_protocol_data_tempfile10;
                my $header_string10 = join ',', @germplasm_data_header;
                print $F10 "$header_string10\n";

                foreach (@germplasm_data) {
                    my $string = join ',', @$_;
                    print $F10 "$string\n";
                }
            close($F10);

            open(my $F11, ">", $analytics_protocol_data_tempfile11) || die "Can't open file ".$analytics_protocol_data_tempfile11;
                my $header_string11 = join ',', @germplasm_data_values_header;
                print $F11 "$header_string11\n";

                foreach (@germplasm_data_values) {
                    my $string = join ',', @$_;
                    print $F11 "$string\n";
                }
            close($F11);
        }

        open(my $F12, ">", $analytics_protocol_data_tempfile12) || die "Can't open file ".$analytics_protocol_data_tempfile12;
            my $header_string12 = join ',', @plots_avg_data_header;
            print $F12 "$header_string12\n";

            foreach (@plots_avg_data) {
                my $string = join ',', @$_;
                print $F12 "$string\n";
            }
        close($F12);

        open(my $F13, ">", $analytics_protocol_data_tempfile13) || die "Can't open file ".$analytics_protocol_data_tempfile13;
            my $header_string13 = join ',', @plots_avg_data_values_header;
            print $F13 "$header_string13\n";

            foreach (@plots_avg_data_values) {
                my $string = join ',', @$_;
                print $F13 "$string\n";
            }
        close($F13);

        open(my $F19, ">", $analytics_protocol_data_tempfile19) || die "Can't open file ".$analytics_protocol_data_tempfile19;
            my $header_string19 = join ',', @germplasm_data_iteration_header;
            print $F19 "$header_string19\n";

            foreach (@germplasm_data_iteration_data_values) {
                my $string = join ',', @$_;
                print $F19 "$string\n";
            }
        close($F19);

        open(my $F20, ">", $analytics_protocol_data_tempfile20) || die "Can't open file ".$analytics_protocol_data_tempfile20;
            my $header_string20 = join ',', @plots_data_iteration_header;
            print $F20 "$header_string20\n";

            foreach (@plots_data_iteration_data_values) {
                my $string = join ',', @$_;
                print $F20 "$string\n";
            }
        close($F20);

        open(my $F22, ">", $analytics_protocol_data_tempfile22) || die "Can't open file ".$analytics_protocol_data_tempfile22;
            my $header_string22 = join ',', @plots_avg_data_heatmap_values_header;
            print $F22 "$header_string22\n";

            foreach (@plots_avg_data_heatmap_values) {
                my $string = join ',', @$_;
                print $F22 "$string\n";
            }
        close($F22);

        open(my $F23, ">", $analytics_protocol_data_tempfile23) || die "Can't open file ".$analytics_protocol_data_tempfile23;
            my $header_string23 = join ',', @plots_avg_data_heatmap_values_traits_header;
            print $F23 "$header_string23\n";

            foreach (@plots_avg_data_heatmap_values_traits) {
                my $string = join ',', @$_;
                print $F23 "$string\n";
            }
        close($F23);

        open(my $F25, ">", $analytics_protocol_data_tempfile25) || die "Can't open file ".$analytics_protocol_data_tempfile25;
            my $header_string25 = join ',', @plots_avg_data_heatmap_values_traits_secondary_header;
            print $F25 "$header_string25\n";

            foreach (@plots_avg_data_heatmap_values_traits_secondary) {
                my $string = join ',', @$_;
                print $F25 "$string\n";
            }
        close($F25);

        open(my $F26, ">", $analytics_protocol_data_tempfile26) || die "Can't open file ".$analytics_protocol_data_tempfile26;
            my $header_string26 = join ',', @plots_avg_data_heatmap_values_traits_corrected_header;
            print $F26 "$header_string26\n";

            foreach (@plots_avg_data_heatmap_values_traits_corrected) {
                my $string = join ',', @$_;
                print $F26 "$string\n";
            }
        close($F26);

        open(my $F27, ">", $analytics_protocol_data_tempfile27) || die "Can't open file ".$analytics_protocol_data_tempfile27;
            foreach (@plots_data_grm_prm_data_values) {
                my $string = join ',', @$_;
                print $F27 "$string\n";
            }
        close($F27);

        open(my $F27_q1, ">", $analytics_protocol_data_tempfile_prm_q1) || die "Can't open file ".$analytics_protocol_data_tempfile_prm_q1;
            foreach (@plots_data_grm_prm_data_values_q1) {
                my $string = join ',', @$_;
                print $F27_q1 "$string\n";
            }
        close($F27_q1);

        open(my $F27_q2, ">", $analytics_protocol_data_tempfile_prm_q2) || die "Can't open file ".$analytics_protocol_data_tempfile_prm_q2;
            foreach (@plots_data_grm_prm_data_values_q2) {
                my $string = join ',', @$_;
                print $F27_q2 "$string\n";
            }
        close($F27_q2);

        open(my $F27_q3, ">", $analytics_protocol_data_tempfile_prm_q3) || die "Can't open file ".$analytics_protocol_data_tempfile_prm_q3;
            foreach (@plots_data_grm_prm_data_values_q3) {
                my $string = join ',', @$_;
                print $F27_q3 "$string\n";
            }
        close($F27_q3);

        open(my $F27_q4, ">", $analytics_protocol_data_tempfile_prm_q4) || die "Can't open file ".$analytics_protocol_data_tempfile_prm_q4;
            foreach (@plots_data_grm_prm_data_values_q4) {
                my $string = join ',', @$_;
                print $F27_q4 "$string\n";
            }
        close($F27_q4);

        open(my $F28, ">", $analytics_protocol_data_tempfile28) || die "Can't open file ".$analytics_protocol_data_tempfile28;
            foreach (@plots_data_grm_prm_secondary_traits_data_values) {
                my $string = join ',', @$_;
                print $F28 "$string\n";
            }
        close($F28);

        open(my $F28_q1, ">", $analytics_protocol_data_tempfile_prm_sec_q1) || die "Can't open file ".$analytics_protocol_data_tempfile_prm_sec_q1;
            foreach (@plots_data_grm_prm_secondary_traits_data_values_q1) {
                my $string = join ',', @$_;
                print $F28_q1 "$string\n";
            }
        close($F28_q1);

        open(my $F28_q2, ">", $analytics_protocol_data_tempfile_prm_sec_q2) || die "Can't open file ".$analytics_protocol_data_tempfile_prm_sec_q2;
            foreach (@plots_data_grm_prm_secondary_traits_data_values_q2) {
                my $string = join ',', @$_;
                print $F28_q2 "$string\n";
            }
        close($F28_q2);

        open(my $F28_q3, ">", $analytics_protocol_data_tempfile_prm_sec_q3) || die "Can't open file ".$analytics_protocol_data_tempfile_prm_sec_q3;
            foreach (@plots_data_grm_prm_secondary_traits_data_values_q3) {
                my $string = join ',', @$_;
                print $F28_q3 "$string\n";
            }
        close($F28_q3);

        open(my $F28_q4, ">", $analytics_protocol_data_tempfile_prm_sec_q4) || die "Can't open file ".$analytics_protocol_data_tempfile_prm_sec_q4;
            foreach (@plots_data_grm_prm_secondary_traits_data_values_q4) {
                my $string = join ',', @$_;
                print $F28_q4 "$string\n";
            }
        close($F28_q4);

        open(my $F30, ">", $analytics_protocol_data_tempfile30) || die "Can't open file ".$analytics_protocol_data_tempfile30;
            foreach (@plots_data_grm_prm_secondary_traits_fixed_data_values) {
                my $string = join ',', @$_;
                print $F30 "$string\n";
            }
        close($F30);

        open(my $F30_q1, ">", $analytics_protocol_data_tempfile_prm_sec_fix_q1) || die "Can't open file ".$analytics_protocol_data_tempfile_prm_sec_fix_q1;
            foreach (@plots_data_grm_prm_secondary_traits_fixed_data_values_q1) {
                my $string = join ',', @$_;
                print $F30_q1 "$string\n";
            }
        close($F30_q1);

        open(my $F30_q2, ">", $analytics_protocol_data_tempfile_prm_sec_fix_q2) || die "Can't open file ".$analytics_protocol_data_tempfile_prm_sec_fix_q2;
            foreach (@plots_data_grm_prm_secondary_traits_fixed_data_values_q2) {
                my $string = join ',', @$_;
                print $F30_q2 "$string\n";
            }
        close($F30_q2);

        open(my $F30_q3, ">", $analytics_protocol_data_tempfile_prm_sec_fix_q3) || die "Can't open file ".$analytics_protocol_data_tempfile_prm_sec_fix_q3;
            foreach (@plots_data_grm_prm_secondary_traits_fixed_data_values_q3) {
                my $string = join ',', @$_;
                print $F30_q3 "$string\n";
            }
        close($F30_q3);

        open(my $F30_q4, ">", $analytics_protocol_data_tempfile_prm_sec_fix_q4) || die "Can't open file ".$analytics_protocol_data_tempfile_prm_sec_fix_q4;
            foreach (@plots_data_grm_prm_secondary_traits_fixed_data_values_q4) {
                my $string = join ',', @$_;
                print $F30_q4 "$string\n";
            }
        close($F30_q4);

        if ($result_type eq 'originalgenoeff') {

            if ($analysis_run_type eq '2dspl' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wRow' || $analysis_run_type eq '2dspl_ar1_wRowCol' || $analysis_run_type eq '2dspl_ar1_wRowPlusCol' || $analysis_run_type eq '2dspl_ar1_wColPlusRow') {
                my $r_cmd_i1 = 'R -e "library(ggplot2); library(data.table);
                data <- data.frame(fread(\''.$analytics_protocol_data_tempfile11.'\', header=TRUE, sep=\',\'));
                res <- cor(data, use = \'complete.obs\');
                res_rounded <- round(res, 2);
                write.table(res_rounded, file=\''.$analytics_protocol_data_tempfile16.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
                "';
                print STDERR Dumper $r_cmd_i1;
                my $status_i1 = system($r_cmd_i1);

                open(my $fh_i1, '<', $analytics_protocol_data_tempfile16) or die "Could not open file '$analytics_protocol_data_tempfile16' $!";
                    print STDERR "Opened $analytics_protocol_data_tempfile16\n";
                    my $header = <$fh_i1>;
                    my @header_cols;
                    if ($csv->parse($header)) {
                        @header_cols = $csv->fields();
                    }

                    my @header_trait_names = ("Trait", @header_cols);
                    push @germplasm_results, \@header_trait_names;

                    while (my $row = <$fh_i1>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }

                        push @germplasm_results, \@columns;
                    }
                close($fh_i1);
            }

            my $r_cmd_p1 = 'R -e "library(data.table); library(ggplot2); library(GGally);
            data <- data.frame(fread(\''.$analytics_protocol_data_tempfile19.'\', header=TRUE, sep=\',\'));
            data\$time <- as.factor(data\$time);
            gg <- ggplot(data, aes(x=value, y=tmean, color=time)) +
            geom_point() +
            geom_smooth(method=lm, aes(fill=time), se=FALSE, fullrange=TRUE);
            ggsave(\''.$analytics_protocol_figure_tempfile_1.'\', gg, device=\'png\', width=8, height=8, units=\'in\');
            "';
            print STDERR Dumper $r_cmd_p1;
            my $status_p1 = system($r_cmd_p1);
        }

        if ($result_type eq 'fullcorr') {
            # print STDERR Dumper \%plot_fixed_effects;
            while (my($p, $o) = each %plot_fixed_effects) {
                my @all_vals;
                while (my($fixed_eff, $vals) = each %$o) {
                    push @all_vals, @$vals;

                    my $avg_val = round(sum(@$vals)/scalar(@$vals));
                    $plot_averaged_fixed_effects{$p}->{$fixed_eff} = $avg_val;
                }

                my $avg_val_all = round(sum(@all_vals)/scalar(@all_vals));
                $plot_averaged_fixed_effect{$p} = $avg_val_all;

                my $max_val = 0;
                foreach (@all_vals) {
                    if ($_ > $max_val) {
                        $max_val = $_;
                    }
                }
                $plot_averaged_fixed_effect_maximum{$p} = $max_val;

                my $min_val = 100000000;
                foreach (@all_vals) {
                    if ($_ < $min_val) {
                        $min_val = $_;
                    }
                }
                $plot_averaged_fixed_effect_minimum{$p} = $min_val;
            }

            while (my($p, $o) = each %plot_fixed_effects_cont) {
                my $avg_val_all = sum(@$o)/scalar(@$o);
                $plot_averaged_fixed_effect_cont{$p} = $avg_val_all;
            }

            # print STDERR Dumper \%plot_fixed_effects_3;
            while (my($p, $o) = each %plot_fixed_effects_3) {
                while (my($fixed_eff, $vals) = each %$o) {
                    my $avg_val = round(sum(@$vals)/scalar(@$vals));
                    $plot_averaged_fixed_effects_3{$p}->{$fixed_eff} = $avg_val;
                }
            }

            # print STDERR Dumper \%plot_fixed_effects_3_cont;
            while (my($p, $o) = each %plot_fixed_effects_3_cont) {
                while (my($fixed_eff, $vals) = each %$o) {
                    my $avg_val = sum(@$vals)/scalar(@$vals);
                    $plot_averaged_fixed_effects_3_cont{$p}->{$fixed_eff} = $avg_val;
                }
            }

            # print STDERR Dumper \%plot_averaged_fixed_effect_minimum;
            # print STDERR Dumper \%plot_averaged_fixed_effect_maximum;
            # print STDERR Dumper \%plot_averaged_fixed_effect;
            # print STDERR Dumper \%plot_averaged_fixed_effects;
            # print STDERR Dumper \%plot_averaged_fixed_effects_3;
            # print STDERR Dumper \%plot_averaged_fixed_effects_3_cont;

            my @fixed_effect_header_traits;
            print STDERR "$analytics_protocol_data_tempfile29\n";
            open(my $F29, ">", $analytics_protocol_data_tempfile29) || die "Can't open file ".$analytics_protocol_data_tempfile29;
            open(my $F29_q1, ">", $analytics_protocol_data_tempfile_fixed_q1) || die "Can't open file ".$analytics_protocol_data_tempfile_fixed_q1;
            open(my $F29_q2, ">", $analytics_protocol_data_tempfile_fixed_q2) || die "Can't open file ".$analytics_protocol_data_tempfile_fixed_q2;
            open(my $F29_q3, ">", $analytics_protocol_data_tempfile_fixed_q3) || die "Can't open file ".$analytics_protocol_data_tempfile_fixed_q3;
            open(my $F29_q4, ">", $analytics_protocol_data_tempfile_fixed_q4) || die "Can't open file ".$analytics_protocol_data_tempfile_fixed_q4;
                my @fixed_factor_header = ('plot_name','fixed_effect_all_cont','fixed_effect_all','fixed_effect_1','fixed_effect_2','fixed_effect_3_1','fixed_effect_3_2','fixed_effect_3_3','fixed_effect_max','fixed_effect_min','fixed_effect_1_cont','fixed_effect_2_cont','fixed_effect_3_cont');
                foreach my $time (@sorted_seen_times_p) {
                    my $time_enc = $trait_name_map_reverse{$time};
                    push @fixed_factor_header, $time_enc;
                    push @fixed_effect_header_traits, $time_enc;
                }
                foreach my $trait_htp (@sorted_trait_names_htp) {
                    my $trait_enc = $trait_name_encoder_input_htp{$trait_htp};
                    push @fixed_factor_header, $trait_enc;
                }
                my $fixed_factor_header_string = join ',', @fixed_factor_header;
                print $F29 "$fixed_factor_header_string\n";
                print $F29_q1 "$fixed_factor_header_string\n";
                print $F29_q2 "$fixed_factor_header_string\n";
                print $F29_q3 "$fixed_factor_header_string\n";
                print $F29_q4 "$fixed_factor_header_string\n";
                foreach my $p (@seen_plots) {
                    my $row_number = $stock_name_row_col{$p}->{row_number};
                    my $col_number = $stock_name_row_col{$p}->{col_number};
                    my $fixed_effect_cont = $plot_averaged_fixed_effect_cont{$p};
                    my $fixed_effect_all = $plot_averaged_fixed_effect{$p};
                    my $fixed_effect_min = $plot_averaged_fixed_effect_minimum{$p};
                    my $fixed_effect_max = $plot_averaged_fixed_effect_maximum{$p};
                    my $fixed_effect_1 = $plot_averaged_fixed_effects{$p}->{'1'};
                    my $fixed_effect_2 = $plot_averaged_fixed_effects{$p}->{'2'};
                    my $fixed_effect_3_1 = $plot_averaged_fixed_effects_3{$p}->{'1'} || 0;
                    my $fixed_effect_3_2 = $plot_averaged_fixed_effects_3{$p}->{'2'} || 0;
                    my $fixed_effect_3_3 = $plot_averaged_fixed_effects_3{$p}->{'3'} || 0;
                    my $fixed_effect_3_cont_1 = $plot_averaged_fixed_effects_3_cont{$p}->{'1'} || 0;
                    my $fixed_effect_3_cont_2 = $plot_averaged_fixed_effects_3_cont{$p}->{'2'} || 0;
                    my $fixed_effect_3_cont_3 = $plot_averaged_fixed_effects_3_cont{$p}->{'3'} || 0;

                    my @fixed_effect_row = ($p,$fixed_effect_cont,$fixed_effect_all,$fixed_effect_1,$fixed_effect_2,$fixed_effect_3_1,$fixed_effect_3_2,$fixed_effect_3_3,$fixed_effect_max,$fixed_effect_min,$fixed_effect_3_cont_1,$fixed_effect_3_cont_2,$fixed_effect_3_cont_3);
                    foreach my $time (@sorted_seen_times_p) {
                        my $time_val = $plot_result_time_blups{$p}->{$time} || 'NA';
                        push @fixed_effect_row, $time_val;
                    }
                    foreach my $trait (@sorted_trait_names_htp) {
                        my $trait_val = $plot_phenotypes_htp{$p}->{$trait} || 'NA';
                        push @fixed_effect_row, $trait_val;
                    }

                    my $fixed_effect_row_string = join ',', @fixed_effect_row;
                    print $F29 "$fixed_effect_row_string\n";

                    if ($row_number <= $max_row_half) {
                        if ($col_number <= $max_col_half) {
                            print $F29_q1 "$fixed_effect_row_string\n";
                        }
                        else {
                            print $F29_q2 "$fixed_effect_row_string\n";
                        }
                    }
                    else {
                        if ($col_number <= $max_col_half) {
                            print $F29_q3 "$fixed_effect_row_string\n";
                        }
                        else {
                            print $F29_q4 "$fixed_effect_row_string\n";
                        }
                    }
                }
            close($F29);
            close($F29_q1);
            close($F29_q2);
            close($F29_q3);
            close($F29_q4);
            my $fixed_effect_header_traits_string = join ' + ', @fixed_effect_header_traits;

            my $r_cmd_i2 = 'R -e "library(ggplot2); library(data.table);
            data <- data.frame(fread(\''.$analytics_protocol_data_tempfile13.'\', header=TRUE, sep=\',\'));
            res <- cor(data, use = \'complete.obs\');
            res_rounded <- round(res, 2);
            write.table(res_rounded, file=\''.$analytics_protocol_data_tempfile17.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            "';
            print STDERR Dumper $r_cmd_i2;
            my $status_i2 = system($r_cmd_i2);

            open(my $fh_i2, '<', $analytics_protocol_data_tempfile17) or die "Could not open file '$analytics_protocol_data_tempfile17' $!";
                print STDERR "Opened $analytics_protocol_data_tempfile17\n";
                my $header2 = <$fh_i2>;
                my @header_cols2;
                if ($csv->parse($header2)) {
                    @header_cols2 = $csv->fields();
                }

                my @header_trait_names2 = ("Trait", @header_cols2);
                push @plots_avg_results, \@header_trait_names2;

                while (my $row = <$fh_i2>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    push @plots_avg_results, \@columns;
                }
            close($fh_i2);

            my $r_cmd_p2 = 'R -e "library(data.table); library(ggplot2); library(GGally);
            data <- data.frame(fread(\''.$analytics_protocol_data_tempfile20.'\', header=TRUE, sep=\',\'));
            data\$time <- as.factor(data\$time);
            gg <- ggplot(data, aes(x=value, y=tvalue, color=time)) +
            geom_point() +
            geom_smooth(method=lm, aes(fill=time), se=FALSE, fullrange=TRUE);
            ggsave(\''.$analytics_protocol_figure_tempfile_2.'\', gg, device=\'png\', width=8, height=8, units=\'in\');
            "';
            print STDERR Dumper $r_cmd_p2;
            my $status_p2 = system($r_cmd_p2);

            my $r_cmd_i3 = 'R -e "library(data.table); library(lme4);
            data <- data.frame(fread(\''.$analytics_protocol_data_tempfile12.'\', header=TRUE, sep=\',\'));
            num_columns <- ncol(data);
            col_names_results <- c();
            results <- c();
            for (i in seq(4,num_columns)){
                t <- names(data)[i];
                print(t);
                myformula <- as.formula(paste0(t, \' ~ (1|germplasmName)\'));
                m <- NULL;
                m.summary <- NULL;
                try (m <- lmer(myformula, data=data));
                if (!is.null(m)) {
                    try (m.summary <- summary(m));
                    if (!is.null(m.summary)) {
                        if (!is.null(m.summary\$varcor)) {
                            h <- m.summary\$varcor\$germplasmName[1,1]/(m.summary\$varcor\$germplasmName[1,1] + (m.summary\$sigma)^2);
                            col_names_results <- append(col_names_results, t);
                            results <- append(results, h);
                        }
                    }
                }
            }
            write.table(data.frame(names = col_names_results, results = results), file=\''.$analytics_protocol_data_tempfile21.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            "';
            print STDERR Dumper $r_cmd_i3;
            my $status_i3 = system($r_cmd_i3);

            open(my $fh_i3, '<', $analytics_protocol_data_tempfile21) or die "Could not open file '$analytics_protocol_data_tempfile21' $!";
                print STDERR "Opened $analytics_protocol_data_tempfile21\n";
                my $header3 = <$fh_i3>;

                while (my $row = <$fh_i3>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    push @plots_h_results, \@columns;
                }
            close($fh_i3);

            my $output_plot_row = 'row';
            my $output_plot_col = 'col';
            if ($max_col > $max_row) {
                $output_plot_row = 'col';
                $output_plot_col = 'row';
            }

            my $type_list_string = join '\',\'', @type_names_first_line;
            my $type_list_string_number = scalar(@type_names_first_line);
            my $r_cmd_i4 = 'R -e "library(data.table); library(ggplot2); library(dplyr); library(viridis); library(GGally); library(gridExtra);
            pheno_mat <- data.frame(fread(\''.$analytics_protocol_data_tempfile22.'\', header=TRUE, sep=\',\'));
            pheno_mat\$trait_type <- factor(pheno_mat\$trait_type, levels = c(\''.$type_list_string.'\'));
            gg <- ggplot(pheno_mat, aes('.$output_plot_col.', '.$output_plot_row.', fill=value)) +
                geom_tile() +
                scale_fill_viridis(discrete=FALSE) +
                coord_equal() +
                facet_wrap(~trait_type, ncol='.$type_list_string_number.');
            ggsave(\''.$analytics_protocol_figure_tempfile_3.'\', gg, device=\'png\', width=30, height=30, units=\'in\');
            "';
            print STDERR Dumper $r_cmd_i4;
            my $status_i4 = system($r_cmd_i4);

            my $type_list_traits_string = join '\',\'', @type_names_first_line_traits;
            my $type_list_traits_string_number = scalar(@type_names_first_line_traits);
            my $r_cmd_i5 = 'R -e "library(data.table); library(ggplot2); library(dplyr); library(viridis); library(GGally); library(gridExtra);
            pheno_mat <- data.frame(fread(\''.$analytics_protocol_data_tempfile23.'\', header=TRUE, sep=\',\'));
            pheno_mat\$trait_type <- factor(pheno_mat\$trait_type, levels = c(\''.$type_list_traits_string.'\'));
            gg <- ggplot(pheno_mat, aes('.$output_plot_col.', '.$output_plot_row.', fill=value)) +
                geom_tile() +
                scale_fill_viridis(discrete=FALSE) +
                coord_equal() +
                facet_wrap(~trait_type, ncol='.$type_list_traits_string_number.');
            ggsave(\''.$analytics_protocol_figure_tempfile_4.'\', gg, device=\'png\', width=30, height=30, units=\'in\');
            "';
            print STDERR Dumper $r_cmd_i5;
            my $status_i5 = system($r_cmd_i5);

            my $r_cmd_ic6 = 'R -e "library(ggplot2); library(data.table); library(GGally);
            data <- data.frame(fread(\''.$analytics_protocol_data_tempfile13.'\', header=TRUE, sep=\',\'));
            plot <- ggcorr(data, hjust = 1, size = 3, color = \'grey50\', label = TRUE, label_size = '.$cor_label_size.', label_round = '.$cor_label_digits.', layout.exp = 1);
            ggsave(\''.$analytics_protocol_figure_tempfile_5.'\', plot, device=\'png\', width=10, height=10, units=\'in\');
            "';
            print STDERR Dumper $r_cmd_ic6;
            my $status_ic6 = system($r_cmd_ic6);

            if (scalar(@type_names_first_line_secondary)>0) {
                my $secondary_type_list_string = join '\',\'', @type_names_first_line_secondary;
                my $r_cmd_i7 = 'R -e "library(data.table); library(ggplot2); library(dplyr); library(viridis); library(GGally); library(gridExtra);
                pheno_mat <- data.frame(fread(\''.$analytics_protocol_data_tempfile25.'\', header=TRUE, sep=\',\'));
                type_list <- c(\''.$secondary_type_list_string.'\');
                pheno_mat\$trait_type <- factor(pheno_mat\$trait_type, levels = type_list);
                lapply(type_list, function(cc) { gg <- ggplot(filter(pheno_mat, trait_type==cc), aes('.$output_plot_col.', '.$output_plot_row.', fill=value, frame=trait_type)) + geom_tile() + scale_fill_viridis(discrete=FALSE) + coord_equal() + labs(x=NULL, y=NULL, title=sprintf(\'%s\', cc)); }) -> cclist;
                cclist[[\'ncol\']] <- '.$number_secondary_traits.';
                gg <- do.call(grid.arrange, cclist);
                ggsave(\''.$analytics_protocol_figure_tempfile_6.'\', gg, device=\'png\', width=30, height=30, units=\'in\');
                "';
                print STDERR Dumper $r_cmd_i7;
                my $status_i7 = system($r_cmd_i7);
            }

            my $type_list_traits_corrected_string = join '\',\'', @type_names_first_line_traits_corrected;
            my $type_list_traits_corrected_string_number = scalar(@type_names_first_line_traits_corrected);
            my $r_cmd_i8 = 'R -e "library(data.table); library(ggplot2); library(dplyr); library(viridis); library(GGally); library(gridExtra);
            pheno_mat <- data.frame(fread(\''.$analytics_protocol_data_tempfile26.'\', header=TRUE, sep=\',\'));
            type_list <- c(\''.$type_list_traits_corrected_string.'\');
            pheno_mat\$trait_type <- factor(pheno_mat\$trait_type, levels = type_list);
            lapply(type_list, function(cc) { gg <- ggplot(filter(pheno_mat, trait_type==cc), aes('.$output_plot_col.', '.$output_plot_row.', fill=value, frame=trait_type)) + geom_tile() + scale_fill_viridis(discrete=FALSE) + coord_equal() + labs(x=NULL, y=NULL, title=sprintf(\'%s\', cc)); }) -> cclist;
            cclist[[\'ncol\']] <- '.$type_list_traits_corrected_string_number.';
            gg <- do.call(grid.arrange, cclist);
            ggsave(\''.$analytics_protocol_figure_tempfile_7.'\', gg, device=\'png\', width=10, height=10, units=\'in\');
            "';
            print STDERR Dumper $r_cmd_i8;
            my $status_i8 = system($r_cmd_i8);

            my $grm_no_prm_fixed_effect_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_all <- mat_fixed\$fixed_effect_all;
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
            write.table(data.frame(value=h2\$Estimate, se=h2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            fixed_r <- anova(mix);
            write.table(data.frame(i=rownames(fixed_r), model=c(fixed_r\$Models), f=c(fixed_r\$F.value), p=c(fixed_r\$\`Pr(>F)\`) ), file=\''.$fixed_eff_anova_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effect_cmd;
            my $grm_no_prm_fixed_effect_cmd_status = system($grm_no_prm_fixed_effect_cmd);

            open(my $fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                my $header_no_prm = <$fh>;
                my @header_cols_no_prm;
                if ($csv->parse($header_no_prm)) {
                    @header_cols_no_prm = $csv->fields();
                }

                while (my $row = <$fh>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    my $col_counter = 0;
                    foreach my $encoded_trait (@header_cols_no_prm) {
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

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

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open(my $fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                my $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                my @header_cols_varcomp;
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm_fixed_effect, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_grm_fixed_effect;

            open(my $fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                my $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                my @header_cols_varcomp_h;
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm_fixed_effect, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_grm_fixed_effect;

            open(my $fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                my $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                my @header_cols_fits;
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm_fixed_effect, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_grm_fixed_effect;

            open(my $fh_f_anova, '<', $fixed_eff_anova_tempfile) or die "Could not open file '$fixed_eff_anova_tempfile' $!";
                print STDERR "Opened $fixed_eff_anova_tempfile\n";
                my $header_f_anova = <$fh_f_anova>;
                print STDERR Dumper $header_f_anova;
                my @header_cols_f_anova;
                if ($csv->parse($header_f_anova)) {
                    @header_cols_f_anova = $csv->fields();
                }
                while (my $row = <$fh_f_anova>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @f_anova_grm_fixed_effect, \@columns;
                }
            close($fh_f_anova);
            print STDERR Dumper \@f_anova_grm_fixed_effect;

            my $grm_no_prm_fixed_effect_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_all <- mat_fixed\$fixed_effect_all;
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effect_rep_gcorr_cmd;
            my $grm_no_prm_fixed_effect_rep_gcorr_cmd_status = system($grm_no_prm_fixed_effect_rep_gcorr_cmd);

            open(my $F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_favg = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                mat_fq1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q1.'\', header=TRUE, sep=\',\')); mat_fq2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q2.'\', header=TRUE, sep=\',\')); mat_fq3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q3.'\', header=TRUE, sep=\',\')); mat_fq4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                mat_q1\$fixed_effect_all <- mat_fq1\$fixed_effect_all; mat_q2\$fixed_effect_all <- mat_fq2\$fixed_effect_all; mat_q3\$fixed_effect_all <- mat_fq3\$fixed_effect_all; mat_q4\$fixed_effect_all <- mat_fq4\$fixed_effect_all;
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_favg = $columns[0];
                        @gcorr_qarr_favg = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $grm_no_prm_fixed_effects_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_1 <- mat_fixed\$fixed_effect_1;
            mat\$fixed_effect_2 <- mat_fixed\$fixed_effect_2;
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1 + fixed_effect_2, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
            write.table(data.frame(value=h2\$Estimate, se=h2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            fixed_r <- anova(mix);
            write.table(data.frame(i=rownames(fixed_r), model=c(fixed_r\$Models), f=c(fixed_r\$F.value), p=c(fixed_r\$\`Pr(>F)\`) ), file=\''.$fixed_eff_anova_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_cmd;
            my $grm_no_prm_fixed_effects_cmd_status = system($grm_no_prm_fixed_effects_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                $header_no_prm = <$fh>;
                @header_cols_no_prm = ();
                if ($csv->parse($header_no_prm)) {
                    @header_cols_no_prm = $csv->fields();
                }

                while (my $row = <$fh>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    my $col_counter = 0;
                    foreach my $encoded_trait (@header_cols_no_prm) {
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm_fixed_effects, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_grm_fixed_effects;

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm_fixed_effects, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_grm_fixed_effects;

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm_fixed_effects, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_grm_fixed_effects;

            open($fh_f_anova, '<', $fixed_eff_anova_tempfile) or die "Could not open file '$fixed_eff_anova_tempfile' $!";
                print STDERR "Opened $fixed_eff_anova_tempfile\n";
                $header_f_anova = <$fh_f_anova>;
                print STDERR Dumper $header_f_anova;
                @header_cols_f_anova = ();
                if ($csv->parse($header_f_anova)) {
                    @header_cols_f_anova = $csv->fields();
                }
                while (my $row = <$fh_f_anova>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @f_anova_grm_fixed_effects, \@columns;
                }
            close($fh_f_anova);
            print STDERR Dumper \@f_anova_grm_fixed_effects;

            my $grm_no_prm_fixed_effects_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_1 <- mat_fixed\$fixed_effect_1;
            mat\$fixed_effect_2 <- mat_fixed\$fixed_effect_2;
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1 + fixed_effect_2, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1 + fixed_effect_2, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_rep_gcorr_cmd;
            my $grm_no_prm_fixed_effects_rep_gcorr_cmd_status = system($grm_no_prm_fixed_effects_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_f2 = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                mat_fq1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q1.'\', header=TRUE, sep=\',\')); mat_fq2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q2.'\', header=TRUE, sep=\',\')); mat_fq3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q3.'\', header=TRUE, sep=\',\')); mat_fq4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                mat_q1\$fixed_effect_1 <- mat_fq1\$fixed_effect_1; mat_q2\$fixed_effect_1 <- mat_fq2\$fixed_effect_1; mat_q3\$fixed_effect_1 <- mat_fq3\$fixed_effect_1; mat_q4\$fixed_effect_1 <- mat_fq4\$fixed_effect_1; mat_q1\$fixed_effect_2 <- mat_fq1\$fixed_effect_2; mat_q2\$fixed_effect_2 <- mat_fq2\$fixed_effect_2; mat_q3\$fixed_effect_2 <- mat_fq3\$fixed_effect_2; mat_q4\$fixed_effect_2 <- mat_fq4\$fixed_effect_2;
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1 + fixed_effect_2, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1 + fixed_effect_2, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1 + fixed_effect_2, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1 + fixed_effect_2, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_f2 = $columns[0];
                        @gcorr_qarr_f2 = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $grm_no_prm_fixed_effects_all_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0; ';
            foreach my $fixed_eff_t_col (@fixed_effect_header_traits) {
                $grm_no_prm_fixed_effects_all_cmd .= '
                mat\$'.$fixed_eff_t_col.' <- mat_fixed\$'.$fixed_eff_t_col.';';
            }
            $grm_no_prm_fixed_effects_all_cmd .= '
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + '.$fixed_effect_header_traits_string.', random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
            write.table(data.frame(value=h2\$Estimate, se=h2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            fixed_r <- anova(mix);
            write.table(data.frame(i=rownames(fixed_r), model=c(fixed_r\$Models), f=c(fixed_r\$F.value), p=c(fixed_r\$\`Pr(>F)\`) ), file=\''.$fixed_eff_anova_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_all_cmd;
            my $grm_no_prm_fixed_effects_all_cmd_status = system($grm_no_prm_fixed_effects_all_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                $header_no_prm = <$fh>;
                @header_cols_no_prm = ();
                if ($csv->parse($header_no_prm)) {
                    @header_cols_no_prm = $csv->fields();
                }

                while (my $row = <$fh>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    my $col_counter = 0;
                    foreach my $encoded_trait (@header_cols_no_prm) {
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm_fixed_effects_all, \@columns;
                }
            close($fh_varcomp);

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm_fixed_effects_all, \@columns;
                }
            close($fh_varcomp_h);

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm_fixed_effects_all, \@columns;
                }
            close($fh_fits);

            open($fh_f_anova, '<', $fixed_eff_anova_tempfile) or die "Could not open file '$fixed_eff_anova_tempfile' $!";
                print STDERR "Opened $fixed_eff_anova_tempfile\n";
                $header_f_anova = <$fh_f_anova>;
                print STDERR Dumper $header_f_anova;
                @header_cols_f_anova = ();
                if ($csv->parse($header_f_anova)) {
                    @header_cols_f_anova = $csv->fields();
                }
                while (my $row = <$fh_f_anova>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @f_anova_grm_fixed_effects_all, \@columns;
                }
            close($fh_f_anova);

            my $grm_no_prm_fixed_effects_all_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0; ';
            foreach my $fixed_eff_t_col (@fixed_effect_header_traits) {
                $grm_no_prm_fixed_effects_all_rep_gcorr_cmd .= '
                mat\$'.$fixed_eff_t_col.' <- mat_fixed\$'.$fixed_eff_t_col.';';
            }
            $grm_no_prm_fixed_effects_all_rep_gcorr_cmd .= '
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + '.$fixed_effect_header_traits_string.', random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + '.$fixed_effect_header_traits_string.', random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_all_rep_gcorr_cmd;
            my $grm_no_prm_fixed_effects_all_rep_gcorr_cmd_status = system($grm_no_prm_fixed_effects_all_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_fall = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                mat_fq1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q1.'\', header=TRUE, sep=\',\')); mat_fq2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q2.'\', header=TRUE, sep=\',\')); mat_fq3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q3.'\', header=TRUE, sep=\',\')); mat_fq4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0; ';
                foreach my $fixed_eff_t_col (@fixed_effect_header_traits) {
                    $spatial_correct_2dspl_rep_gcorr_cmd .= '
                    mat_q1\$'.$fixed_eff_t_col.' <- mat_fq1\$'.$fixed_eff_t_col.'; mat_q2\$'.$fixed_eff_t_col.' <- mat_fq2\$'.$fixed_eff_t_col.'; mat_q3\$'.$fixed_eff_t_col.' <- mat_fq3\$'.$fixed_eff_t_col.'; mat_q4\$'.$fixed_eff_t_col.' <- mat_fq4\$'.$fixed_eff_t_col.'; ';
                }
                $spatial_correct_2dspl_rep_gcorr_cmd .= '
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + '.$fixed_effect_header_traits_string.', random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + '.$fixed_effect_header_traits_string.', random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate + '.$fixed_effect_header_traits_string.', random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate + '.$fixed_effect_header_traits_string.', random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_fall = $columns[0];
                        @gcorr_qarr_fall = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $grm_no_prm_fixed_effects_3_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_3_1 <- mat_fixed\$fixed_effect_3_1;
            mat\$fixed_effect_3_2 <- mat_fixed\$fixed_effect_3_2;
            mat\$fixed_effect_3_3 <- mat_fixed\$fixed_effect_3_3;
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_3_1 + fixed_effect_3_2 + fixed_effect_3_3, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
            write.table(data.frame(value=h2\$Estimate, se=h2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            fixed_r <- anova(mix);
            write.table(data.frame(i=rownames(fixed_r), model=c(fixed_r\$Models), f=c(fixed_r\$F.value), p=c(fixed_r\$\`Pr(>F)\`) ), file=\''.$fixed_eff_anova_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_3_cmd;
            my $grm_no_prm_fixed_effects_3_cmd_status = system($grm_no_prm_fixed_effects_3_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                $header_no_prm = <$fh>;
                @header_cols_no_prm = ();
                if ($csv->parse($header_no_prm)) {
                    @header_cols_no_prm = $csv->fields();
                }

                while (my $row = <$fh>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    my $col_counter = 0;
                    foreach my $encoded_trait (@header_cols_no_prm) {
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm_fixed_effects_3, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_grm_fixed_effects_3;

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm_fixed_effects_3, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_grm_fixed_effects_3;

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm_fixed_effects_3, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_grm_fixed_effects_3;

            open($fh_f_anova, '<', $fixed_eff_anova_tempfile) or die "Could not open file '$fixed_eff_anova_tempfile' $!";
                print STDERR "Opened $fixed_eff_anova_tempfile\n";
                $header_f_anova = <$fh_f_anova>;
                print STDERR Dumper $header_f_anova;
                @header_cols_f_anova = ();
                if ($csv->parse($header_f_anova)) {
                    @header_cols_f_anova = $csv->fields();
                }
                while (my $row = <$fh_f_anova>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @f_anova_grm_fixed_effects_3, \@columns;
                }
            close($fh_f_anova);
            print STDERR Dumper \@f_anova_grm_fixed_effects_3;

            my $grm_no_prm_fixed_effects_3_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_3_1 <- mat_fixed\$fixed_effect_3_1;
            mat\$fixed_effect_3_2 <- mat_fixed\$fixed_effect_3_2;
            mat\$fixed_effect_3_3 <- mat_fixed\$fixed_effect_3_3;
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_3_1 + fixed_effect_3_2 + fixed_effect_3_3, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_3_1 + fixed_effect_3_2 + fixed_effect_3_3, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_3_rep_gcorr_cmd;
            my $grm_no_prm_fixed_effects_3_rep_gcorr_cmd_status = system($grm_no_prm_fixed_effects_3_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_f3 = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                mat_fq1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q1.'\', header=TRUE, sep=\',\')); mat_fq2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q2.'\', header=TRUE, sep=\',\')); mat_fq3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q3.'\', header=TRUE, sep=\',\')); mat_fq4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                mat_q1\$fixed_effect_3_1 <- mat_fq1\$fixed_effect_3_1; mat_q2\$fixed_effect_3_1 <- mat_fq2\$fixed_effect_3_1; mat_q3\$fixed_effect_3_1 <- mat_fq3\$fixed_effect_3_1; mat_q4\$fixed_effect_3_1 <- mat_fq4\$fixed_effect_3_1; mat_q1\$fixed_effect_3_2 <- mat_fq1\$fixed_effect_3_2; mat_q2\$fixed_effect_3_2 <- mat_fq2\$fixed_effect_3_2; mat_q3\$fixed_effect_3_2 <- mat_fq3\$fixed_effect_3_2; mat_q4\$fixed_effect_3_2 <- mat_fq4\$fixed_effect_3_2; mat_q1\$fixed_effect_3_3 <- mat_fq1\$fixed_effect_3_3; mat_q2\$fixed_effect_3_3 <- mat_fq2\$fixed_effect_3_3; mat_q3\$fixed_effect_3_3 <- mat_fq3\$fixed_effect_3_3; mat_q4\$fixed_effect_3_3 <- mat_fq4\$fixed_effect_3_3;
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_3_1 + fixed_effect_3_2 + fixed_effect_3_3, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_3_1 + fixed_effect_3_2 + fixed_effect_3_3, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_3_1 + fixed_effect_3_2 + fixed_effect_3_3, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_3_1 + fixed_effect_3_2 + fixed_effect_3_3, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_f3 = $columns[0];
                        @gcorr_qarr_f3 = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $grm_no_prm_fixed_effects_cont_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_all_cont <- mat_fixed\$fixed_effect_all_cont;
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
            write.table(data.frame(value=h2\$Estimate, se=h2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            fixed_r <- anova(mix);
            write.table(data.frame(i=rownames(fixed_r), model=c(fixed_r\$Models), f=c(fixed_r\$F.value), p=c(fixed_r\$\`Pr(>F)\`) ), file=\''.$fixed_eff_anova_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_cont_cmd;
            my $grm_no_prm_fixed_effects_cont_cmd_status = system($grm_no_prm_fixed_effects_cont_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                $header_no_prm = <$fh>;
                @header_cols_no_prm = ();
                if ($csv->parse($header_no_prm)) {
                    @header_cols_no_prm = $csv->fields();
                }

                while (my $row = <$fh>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    my $col_counter = 0;
                    foreach my $encoded_trait (@header_cols_no_prm) {
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm_fixed_effects_cont, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_grm_fixed_effects_cont;

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm_fixed_effects_cont, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_grm_fixed_effects_cont;

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm_fixed_effects_cont, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_grm_fixed_effects_cont;

            open($fh_f_anova, '<', $fixed_eff_anova_tempfile) or die "Could not open file '$fixed_eff_anova_tempfile' $!";
                print STDERR "Opened $fixed_eff_anova_tempfile\n";
                $header_f_anova = <$fh_f_anova>;
                print STDERR Dumper $header_f_anova;
                @header_cols_f_anova = ();
                if ($csv->parse($header_f_anova)) {
                    @header_cols_f_anova = $csv->fields();
                }
                while (my $row = <$fh_f_anova>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @f_anova_grm_fixed_effects_cont, \@columns;
                }
            close($fh_f_anova);
            print STDERR Dumper \@f_anova_grm_fixed_effects_cont;

            my $grm_no_prm_fixed_effects_havg_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_all_cont <- mat_fixed\$fixed_effect_all_cont;
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_havg_rep_gcorr_cmd;
            my $grm_no_prm_fixed_effects_havg_rep_gcorr_cmd_status = system($grm_no_prm_fixed_effects_havg_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_havg = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                mat_fq1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q1.'\', header=TRUE, sep=\',\')); mat_fq2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q2.'\', header=TRUE, sep=\',\')); mat_fq3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q3.'\', header=TRUE, sep=\',\')); mat_fq4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                mat_q1\$fixed_effect_all_cont <- mat_fq1\$fixed_effect_all_cont; mat_q2\$fixed_effect_all_cont <- mat_fq2\$fixed_effect_all_cont; mat_q3\$fixed_effect_all_cont <- mat_fq3\$fixed_effect_all_cont; mat_q4\$fixed_effect_all_cont <- mat_fq4\$fixed_effect_all_cont;
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_havg = $columns[0];
                        @gcorr_qarr_havg = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $grm_no_prm_fixed_effects_havg_reps_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_all_cont <- mat_fixed\$fixed_effect_all_cont;
            h2s <- c(); h2ses <- c(); r2s <- c(); sses <- c(); ';
            foreach my $r (sort keys %seen_reps_hash) {
                $grm_no_prm_fixed_effects_havg_reps_gcorr_cmd .= '
                mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \''.$r.'\', ]);
                if (!is.null(mix\$U)) {
                h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) ); ff <- fitted(mix);
                r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
                SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
                h2s <- append(h2s, h2\$Estimate); h2ses <- append(h2ses, h2\$SE); r2s <- append(r2s, r2); sses <- append(sses, SSE);
                } ';
            }
            $grm_no_prm_fixed_effects_havg_reps_gcorr_cmd .= '
            write.table(data.frame(h2s_vals=c(paste(h2s,collapse=\',\')), h2s_mean=c(mean(h2s,na.rm=TRUE)), h2ses_vals=c(paste(h2ses,collapse=\',\')), h2ses_mean=c(mean(h2ses,na.rm=TRUE)), r2s_vals=c(paste(r2s,collapse=\',\')), r2s_mean=c(mean(r2s,na.rm=TRUE)), sses_vals=c(paste(sses,collapse=\',\')), sses_mean = c(mean(sses,na.rm=TRUE)) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_havg_reps_gcorr_cmd;
            my $grm_no_prm_fixed_effects_havg_reps_gcorr_cmd_status = system($grm_no_prm_fixed_effects_havg_reps_gcorr_cmd);

            open(my $F_avg_rep_acc_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_rep_acc_f>;
                while (my $row = <$F_avg_rep_acc_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $reps_acc_havg = \@columns;
                }
            close($F_avg_rep_acc_f);

            my $grm_no_prm_fixed_effects_cross_val_reps_gcorr_cmd = 'R -e "library(caret); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            res <- data.frame();
            #train.control <- trainControl(method = \'repeatedcv\', number = 5, repeats = 10);
            train.control <- trainControl(method = \'LOOCV\');
            mix <- train('.$trait_name_encoded_string.' ~ replicate + id, data = mat, method = \'lm\', trControl = train.control);
            res <- rbind(res, mix\$results); ';
            my @grm_no_prm_fixed_effects_cross_val_reps_tests;
            foreach my $r (sort keys %seen_reps_hash) {
                push @grm_no_prm_fixed_effects_cross_val_reps_tests, $r;
                my $grm_no_prm_fixed_effects_cross_val_reps_test = join '\',\'', @grm_no_prm_fixed_effects_cross_val_reps_tests;

                $grm_no_prm_fixed_effects_cross_val_reps_gcorr_cmd .= '
                mat_f <- mat[!mat\$replicate %in% c(\''.$grm_no_prm_fixed_effects_cross_val_reps_test.'\'), ];
                if (nrow(mat_f)>0) {
                mix <- train('.$trait_name_encoded_string.' ~ replicate + id, data = mat_f, method = \'lm\', trControl = train.control);
                res <- rbind(res, mix\$results);
                } ';
            }
            $grm_no_prm_fixed_effects_cross_val_reps_gcorr_cmd .= '
            write.table(res, file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_cross_val_reps_gcorr_cmd;
            my $grm_no_prm_fixed_effects_cross_val_reps_gcorr_cmd_status = system($grm_no_prm_fixed_effects_cross_val_reps_gcorr_cmd);

            open(my $F_avg_rep_acc_cross_val, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                # $header_fits = <$F_avg_rep_acc_cross_val>;
                while (my $row = <$F_avg_rep_acc_cross_val>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @reps_acc_cross_val, \@columns;
                }
            close($F_avg_rep_acc_cross_val);

            my $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd = 'R -e "library(caret); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            mat\$fixed_effect_all_cont <- mat_fixed\$fixed_effect_all_cont;
            res <- data.frame();
            #train.control <- trainControl(method = \'repeatedcv\', number = 5, repeats = 10);
            train.control <- trainControl(method = \'LOOCV\');
            mix <- train('.$trait_name_encoded_string.' ~ replicate + id + fixed_effect_all_cont, data = mat, method = \'lm\', trControl = train.control);
            res <- rbind(res, mix\$results); ';
            my @grm_no_prm_fixed_effects_havg_cross_val_reps_tests;
            foreach my $r (sort keys %seen_reps_hash) {
                push @grm_no_prm_fixed_effects_havg_cross_val_reps_tests, $r;
                my $grm_no_prm_fixed_effects_havg_cross_val_reps_test = join '\',\'', @grm_no_prm_fixed_effects_havg_cross_val_reps_tests;

                $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd .= '
                mat_f <- mat[!mat\$replicate %in% c(\''.$grm_no_prm_fixed_effects_havg_cross_val_reps_test.'\'), ];
                if (nrow(mat_f)>0) {
                mix <- train('.$trait_name_encoded_string.' ~ replicate + id + fixed_effect_all_cont, data = mat_f, method = \'lm\', trControl = train.control);
                res <- rbind(res, mix\$results);
                } ';
            }
            $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd .= '
            write.table(res, file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd;
            my $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd_status = system($grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd);

            open(my $F_avg_rep_acc_f_cross_val, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                # $header_fits = <$F_avg_rep_acc_f_cross_val>;
                while (my $row = <$F_avg_rep_acc_f_cross_val>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @reps_acc_cross_val_havg, \@columns;
                }
            close($F_avg_rep_acc_f_cross_val);

            foreach my $trait_name (@sorted_trait_names_htp) {
                my $enc_trait = $trait_name_encoder_input_htp{$trait_name};
                my $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd = 'R -e "library(caret); library(data.table); library(reshape2); library(ggplot2); library(GGally);
                mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
                mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
                mat\$'.$enc_trait.' <- mat_fixed\$'.$enc_trait.';
                res <- data.frame();
                #train.control <- trainControl(method = \'repeatedcv\', number = 5, repeats = 10);
                train.control <- trainControl(method = \'LOOCV\');
                mix <- train('.$trait_name_encoded_string.' ~ replicate + id + '.$enc_trait.', data = mat, method = \'lm\', trControl = train.control);
                res <- rbind(res, mix\$results); ';
                my @grm_no_prm_fixed_effects_havg_cross_val_reps_tests;
                foreach my $r (sort keys %seen_reps_hash) {
                    push @grm_no_prm_fixed_effects_havg_cross_val_reps_tests, $r;
                    my $grm_no_prm_fixed_effects_havg_cross_val_reps_test = join '\',\'', @grm_no_prm_fixed_effects_havg_cross_val_reps_tests;

                    $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd .= '
                    mat_f <- mat[!mat\$replicate %in% c(\''.$grm_no_prm_fixed_effects_havg_cross_val_reps_test.'\'), ];
                    if (nrow(mat_f)>0) {
                    mix <- train('.$trait_name_encoded_string.' ~ replicate + id + '.$enc_trait.', data = mat_f, method = \'lm\', trControl = train.control);
                    res <- rbind(res, mix\$results);
                    } ';
                }
                $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd .= '
                write.table(res, file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                "';
                print STDERR Dumper $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd;
                my $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd_status = system($grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd);

                open(my $F_avg_rep_acc_f_cross_val, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    # $header_fits = <$F_avg_rep_acc_f_cross_val>;
                    while (my $row = <$F_avg_rep_acc_f_cross_val>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        push @columns, $trait_name;
                        push @reps_acc_cross_val_traits, \@columns;
                    }
                close($F_avg_rep_acc_f_cross_val);
            }

            foreach my $trait_name (@sorted_trait_names_htp) {
                my $enc_trait = $trait_name_encoder_input_htp{$trait_name};
                my $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd = 'R -e "library(caret); library(data.table); library(reshape2); library(ggplot2); library(GGally);
                mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
                mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
                mat\$fixed_effect_all_cont <- mat_fixed\$fixed_effect_all_cont;
                mat\$'.$enc_trait.' <- mat_fixed\$'.$enc_trait.';
                res <- data.frame();
                #train.control <- trainControl(method = \'repeatedcv\', number = 5, repeats = 10);
                train.control <- trainControl(method = \'LOOCV\');
                mix <- train('.$trait_name_encoded_string.' ~ replicate + id + '.$enc_trait.' + fixed_effect_all_cont, data = mat, method = \'lm\', trControl = train.control);
                res <- rbind(res, mix\$results); ';
                my @grm_no_prm_fixed_effects_havg_cross_val_reps_tests;
                foreach my $r (sort keys %seen_reps_hash) {
                    push @grm_no_prm_fixed_effects_havg_cross_val_reps_tests, $r;
                    my $grm_no_prm_fixed_effects_havg_cross_val_reps_test = join '\',\'', @grm_no_prm_fixed_effects_havg_cross_val_reps_tests;

                    $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd .= '
                    mat_f <- mat[!mat\$replicate %in% c(\''.$grm_no_prm_fixed_effects_havg_cross_val_reps_test.'\'), ];
                    if (nrow(mat_f)>0) {
                    mix <- train('.$trait_name_encoded_string.' ~ replicate + id + '.$enc_trait.' + fixed_effect_all_cont, data = mat_f, method = \'lm\', trControl = train.control);
                    res <- rbind(res, mix\$results);
                    } ';
                }
                $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd .= '
                write.table(res, file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                "';
                print STDERR Dumper $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd;
                my $grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd_status = system($grm_no_prm_fixed_effects_havg_cross_val_reps_gcorr_cmd);

                open(my $F_avg_rep_acc_f_cross_val, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    # $header_fits = <$F_avg_rep_acc_f_cross_val>;
                    while (my $row = <$F_avg_rep_acc_f_cross_val>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        push @columns, $trait_name;
                        push @reps_acc_cross_val_havg_and_traits, \@columns;
                    }
                close($F_avg_rep_acc_f_cross_val);
            }

            my $grm_no_prm_fixed_effects_havg_reps_test_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_all_cont <- mat_fixed\$fixed_effect_all_cont;
            h2s <- c(); h2ses <- c(); r2s <- c(); sses <- c();
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) ); ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            h2s <- append(h2s, h2\$Estimate); h2ses <- append(h2ses, h2\$SE); r2s <- append(r2s, r2); sses <- append(sses, SSE);
            }
            ';
            my @grm_no_prm_fixed_effects_havg_reps_tests;
            foreach my $r (sort keys %seen_reps_hash) {
                push @grm_no_prm_fixed_effects_havg_reps_tests, $r;
                my $grm_no_prm_fixed_effects_havg_reps_test = join '\',\'', @grm_no_prm_fixed_effects_havg_reps_tests;

                $grm_no_prm_fixed_effects_havg_reps_test_gcorr_cmd .= '
                mat_f <- mat[!mat\$replicate %in% c(\''.$grm_no_prm_fixed_effects_havg_reps_test.'\'), ];
                if (nrow(mat_f)>0) {
                mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_all_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_f);
                if (!is.null(mix\$U)) {
                h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) ); ff <- fitted(mix);
                r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
                SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
                h2s <- append(h2s, h2\$Estimate); h2ses <- append(h2ses, h2\$SE); r2s <- append(r2s, r2); sses <- append(sses, SSE);
                }} ';
            }
            $grm_no_prm_fixed_effects_havg_reps_test_gcorr_cmd .= '
            write.table(data.frame(h2s_vals=c(paste(h2s,collapse=\',\')), h2s_mean=c(mean(h2s,na.rm=TRUE)), h2ses_vals=c(paste(h2ses,collapse=\',\')), h2ses_mean=c(mean(h2ses,na.rm=TRUE)), r2s_vals=c(paste(r2s,collapse=\',\')), r2s_mean=c(mean(r2s,na.rm=TRUE)), sses_vals=c(paste(sses,collapse=\',\')), sses_mean = c(mean(sses,na.rm=TRUE)) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_havg_reps_test_gcorr_cmd;
            my $grm_no_prm_fixed_effects_havg_reps_test_gcorr_cmd_status = system($grm_no_prm_fixed_effects_havg_reps_test_gcorr_cmd);

            open($F_avg_rep_acc_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_rep_acc_f>;
                while (my $row = <$F_avg_rep_acc_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $reps_test_acc_havg = \@columns;
                }
            close($F_avg_rep_acc_f);

            my $grm_no_prm_fixed_effects_max_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_max <- mat_fixed\$fixed_effect_max;
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_max, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
            write.table(data.frame(value=h2\$Estimate, se=h2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            fixed_r <- anova(mix);
            write.table(data.frame(i=rownames(fixed_r), model=c(fixed_r\$Models), f=c(fixed_r\$F.value), p=c(fixed_r\$\`Pr(>F)\`) ), file=\''.$fixed_eff_anova_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_max_cmd;
            my $grm_no_prm_fixed_effects_max_cmd_status = system($grm_no_prm_fixed_effects_max_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                $header_no_prm = <$fh>;
                @header_cols_no_prm = ();
                if ($csv->parse($header_no_prm)) {
                    @header_cols_no_prm = $csv->fields();
                }

                while (my $row = <$fh>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    my $col_counter = 0;
                    foreach my $encoded_trait (@header_cols_no_prm) {
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm_fixed_effects_max, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_grm_fixed_effects_max;

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm_fixed_effects_max, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_grm_fixed_effects_max;

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm_fixed_effects_max, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_grm_fixed_effects_max;

            open($fh_f_anova, '<', $fixed_eff_anova_tempfile) or die "Could not open file '$fixed_eff_anova_tempfile' $!";
                print STDERR "Opened $fixed_eff_anova_tempfile\n";
                $header_f_anova = <$fh_f_anova>;
                print STDERR Dumper $header_f_anova;
                @header_cols_f_anova = ();
                if ($csv->parse($header_f_anova)) {
                    @header_cols_f_anova = $csv->fields();
                }
                while (my $row = <$fh_f_anova>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @f_anova_grm_fixed_effects_max, \@columns;
                }
            close($fh_f_anova);
            print STDERR Dumper \@f_anova_grm_fixed_effects_max;

            my $grm_no_prm_fixed_effects_fmax_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_max <- mat_fixed\$fixed_effect_max;
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_max, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_max, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_fmax_rep_gcorr_cmd;
            my $grm_no_prm_fixed_effects_fmax_rep_gcorr_cmd_status = system($grm_no_prm_fixed_effects_fmax_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_fmax = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                mat_fq1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q1.'\', header=TRUE, sep=\',\')); mat_fq2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q2.'\', header=TRUE, sep=\',\')); mat_fq3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q3.'\', header=TRUE, sep=\',\')); mat_fq4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                mat_q1\$fixed_effect_max <- mat_fq1\$fixed_effect_max; mat_q2\$fixed_effect_max <- mat_fq2\$fixed_effect_max; mat_q3\$fixed_effect_max <- mat_fq3\$fixed_effect_max; mat_q4\$fixed_effect_max <- mat_fq4\$fixed_effect_max;
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_max, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_max, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_max, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_max, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_fmax = $columns[0];
                        @gcorr_qarr_fmax = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $grm_no_prm_fixed_effects_min_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_min <- mat_fixed\$fixed_effect_min;
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_min, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
            write.table(data.frame(value=h2\$Estimate, se=h2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            fixed_r <- anova(mix);
            write.table(data.frame(i=rownames(fixed_r), model=c(fixed_r\$Models), f=c(fixed_r\$F.value), p=c(fixed_r\$\`Pr(>F)\`) ), file=\''.$fixed_eff_anova_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_min_cmd;
            my $grm_no_prm_fixed_effects_min_cmd_status = system($grm_no_prm_fixed_effects_min_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                $header_no_prm = <$fh>;
                @header_cols_no_prm = ();
                if ($csv->parse($header_no_prm)) {
                    @header_cols_no_prm = $csv->fields();
                }

                while (my $row = <$fh>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    my $col_counter = 0;
                    foreach my $encoded_trait (@header_cols_no_prm) {
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm_fixed_effects_min, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_grm_fixed_effects_min;

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm_fixed_effects_min, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_grm_fixed_effects_min;

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm_fixed_effects_min, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_grm_fixed_effects_min;

            open($fh_f_anova, '<', $fixed_eff_anova_tempfile) or die "Could not open file '$fixed_eff_anova_tempfile' $!";
                print STDERR "Opened $fixed_eff_anova_tempfile\n";
                $header_f_anova = <$fh_f_anova>;
                print STDERR Dumper $header_f_anova;
                @header_cols_f_anova = ();
                if ($csv->parse($header_f_anova)) {
                    @header_cols_f_anova = $csv->fields();
                }
                while (my $row = <$fh_f_anova>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @f_anova_grm_fixed_effects_min, \@columns;
                }
            close($fh_f_anova);
            print STDERR Dumper \@f_anova_grm_fixed_effects_min;

            my $grm_no_prm_fixed_effects_fmin_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_min <- mat_fixed\$fixed_effect_min;
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_min, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_min, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_fmin_rep_gcorr_cmd;
            my $grm_no_prm_fixed_effects_fmin_rep_gcorr_cmd_status = system($grm_no_prm_fixed_effects_fmin_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_fmin = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                mat_fq1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q1.'\', header=TRUE, sep=\',\')); mat_fq2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q2.'\', header=TRUE, sep=\',\')); mat_fq3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q3.'\', header=TRUE, sep=\',\')); mat_fq4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                mat_q1\$fixed_effect_min <- mat_fq1\$fixed_effect_min; mat_q2\$fixed_effect_min <- mat_fq2\$fixed_effect_min; mat_q3\$fixed_effect_min <- mat_fq3\$fixed_effect_min; mat_q4\$fixed_effect_min <- mat_fq4\$fixed_effect_min;
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_min, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_min, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_min, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_min, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_fmin = $columns[0];
                        @gcorr_qarr_fmin = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $grm_no_prm_fixed_effects_3_cont_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_1_cont <- mat_fixed\$fixed_effect_1_cont;
            mat\$fixed_effect_2_cont <- mat_fixed\$fixed_effect_2_cont;
            mat\$fixed_effect_3_cont <- mat_fixed\$fixed_effect_3_cont;
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1_cont + fixed_effect_2_cont + fixed_effect_3_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
            write.table(data.frame(value=h2\$Estimate, se=h2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            fixed_r <- anova(mix);
            write.table(data.frame(i=rownames(fixed_r), model=c(fixed_r\$Models), f=c(fixed_r\$F.value), p=c(fixed_r\$\`Pr(>F)\`) ), file=\''.$fixed_eff_anova_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_3_cont_cmd;
            my $grm_no_prm_fixed_effects_2_cont_cmd_status = system($grm_no_prm_fixed_effects_3_cont_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                $header_no_prm = <$fh>;
                @header_cols_no_prm = ();
                if ($csv->parse($header_no_prm)) {
                    @header_cols_no_prm = $csv->fields();
                }

                while (my $row = <$fh>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    my $col_counter = 0;
                    foreach my $encoded_trait (@header_cols_no_prm) {
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm_fixed_effects_f3_cont, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_grm_fixed_effects_f3_cont;

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm_fixed_effects_f3_cont, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_grm_fixed_effects_f3_cont;

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm_fixed_effects_f3_cont, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_grm_fixed_effects_f3_cont;

            open($fh_f_anova, '<', $fixed_eff_anova_tempfile) or die "Could not open file '$fixed_eff_anova_tempfile' $!";
                print STDERR "Opened $fixed_eff_anova_tempfile\n";
                $header_f_anova = <$fh_f_anova>;
                print STDERR Dumper $header_f_anova;
                @header_cols_f_anova = ();
                if ($csv->parse($header_f_anova)) {
                    @header_cols_f_anova = $csv->fields();
                }
                while (my $row = <$fh_f_anova>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @f_anova_grm_fixed_effects_f3_cont, \@columns;
                }
            close($fh_f_anova);
            print STDERR Dumper \@f_anova_grm_fixed_effects_f3_cont;

            my $grm_no_prm_fixed_effects_f3_cont_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_1_cont <- mat_fixed\$fixed_effect_1_cont;
            mat\$fixed_effect_2_cont <- mat_fixed\$fixed_effect_2_cont;
            mat\$fixed_effect_3_cont <- mat_fixed\$fixed_effect_3_cont;
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1_cont + fixed_effect_2_cont + fixed_effect_3_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1_cont + fixed_effect_2_cont + fixed_effect_3_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_f3_cont_rep_gcorr_cmd;
            my $grm_no_prm_fixed_effects_f3_cont_rep_gcorr_cmd_status = system($grm_no_prm_fixed_effects_f3_cont_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_f3_cont = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                mat_fq1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q1.'\', header=TRUE, sep=\',\')); mat_fq2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q2.'\', header=TRUE, sep=\',\')); mat_fq3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q3.'\', header=TRUE, sep=\',\')); mat_fq4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_fixed_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                mat_q1\$fixed_effect_1_cont <- mat_fq1\$fixed_effect_1_cont; mat_q2\$fixed_effect_1_cont <- mat_fq2\$fixed_effect_1_cont; mat_q3\$fixed_effect_1_cont <- mat_fq3\$fixed_effect_1_cont; mat_q4\$fixed_effect_1_cont <- mat_fq4\$fixed_effect_1_cont; mat_q1\$fixed_effect_2_cont <- mat_fq1\$fixed_effect_2_cont; mat_q2\$fixed_effect_2_cont <- mat_fq2\$fixed_effect_2_cont; mat_q3\$fixed_effect_2_cont <- mat_fq3\$fixed_effect_2_cont; mat_q4\$fixed_effect_2_cont <- mat_fq4\$fixed_effect_2_cont; mat_q1\$fixed_effect_3_cont <- mat_fq1\$fixed_effect_3_cont; mat_q2\$fixed_effect_3_cont <- mat_fq2\$fixed_effect_3_cont; mat_q3\$fixed_effect_3_cont <- mat_fq3\$fixed_effect_3_cont; mat_q4\$fixed_effect_3_cont <- mat_fq4\$fixed_effect_3_cont;
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1_cont + fixed_effect_2_cont + fixed_effect_3_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1_cont + fixed_effect_2_cont + fixed_effect_3_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1_cont + fixed_effect_2_cont + fixed_effect_3_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1_cont + fixed_effect_2_cont + fixed_effect_3_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_f3_cont = $columns[0];
                        @gcorr_qarr_f3_cont = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $grm_no_prm_fixed_effects_f3_cont_reps_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_1_cont <- mat_fixed\$fixed_effect_1_cont;
            mat\$fixed_effect_2_cont <- mat_fixed\$fixed_effect_2_cont;
            mat\$fixed_effect_3_cont <- mat_fixed\$fixed_effect_3_cont;
            h2s <- c(); h2ses <- c(); r2s <- c(); sses <- c(); ';
            foreach my $r (sort keys %seen_reps_hash) {
                $grm_no_prm_fixed_effects_f3_cont_reps_gcorr_cmd .= '
                mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1_cont + fixed_effect_2_cont + fixed_effect_3_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \''.$r.'\', ]);
                if (!is.null(mix\$U)) {
                h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) ); ff <- fitted(mix);
                r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
                SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
                h2s <- append(h2s, h2\$Estimate); h2ses <- append(h2ses, h2\$SE); r2s <- append(r2s, r2); sses <- append(sses, SSE);
                } ';
            }
            $grm_no_prm_fixed_effects_f3_cont_reps_gcorr_cmd .= '
            write.table(data.frame(h2s_vals=c(paste(h2s,collapse=\',\')), h2s_mean=c(mean(h2s,na.rm=TRUE)), h2ses_vals=c(paste(h2ses,collapse=\',\')), h2ses_mean=c(mean(h2ses,na.rm=TRUE)), r2s_vals=c(paste(r2s,collapse=\',\')), r2s_mean=c(mean(r2s,na.rm=TRUE)), sses_vals=c(paste(sses,collapse=\',\')), sses_mean = c(mean(sses,na.rm=TRUE)) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_f3_cont_reps_gcorr_cmd;
            my $grm_no_prm_fixed_effects_f3_cont_reps_gcorr_cmd_status = system($grm_no_prm_fixed_effects_f3_cont_reps_gcorr_cmd);

            open($F_avg_rep_acc_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_rep_acc_f>;
                while (my $row = <$F_avg_rep_acc_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $reps_acc_f3_cont = \@columns;
                }
            close($F_avg_rep_acc_f);

            my $grm_no_prm_fixed_effects_f3_cont_reps_test_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            mat_fixed <- data.frame(fread(\''.$analytics_protocol_data_tempfile29.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mat\$fixed_effect_1_cont <- mat_fixed\$fixed_effect_1_cont;
            mat\$fixed_effect_2_cont <- mat_fixed\$fixed_effect_2_cont;
            mat\$fixed_effect_3_cont <- mat_fixed\$fixed_effect_3_cont;
            h2s <- c(); h2ses <- c(); r2s <- c(); sses <- c();
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1_cont + fixed_effect_2_cont + fixed_effect_3_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) ); ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            h2s <- append(h2s, h2\$Estimate); h2ses <- append(h2ses, h2\$SE); r2s <- append(r2s, r2); sses <- append(sses, SSE);
            }
            ';
            my @grm_no_prm_fixed_effects_f3_cont_reps_tests;
            foreach my $r (sort keys %seen_reps_hash) {
                push @grm_no_prm_fixed_effects_f3_cont_reps_tests, $r;
                my $grm_no_prm_fixed_effects_f3_cont_reps_test = join '\',\'', @grm_no_prm_fixed_effects_f3_cont_reps_tests;

                $grm_no_prm_fixed_effects_f3_cont_reps_test_gcorr_cmd .= '
                mat_f <- mat[!mat\$replicate %in% c(\''.$grm_no_prm_fixed_effects_f3_cont_reps_test.'\'), ];
                if (nrow(mat_f)>0) {
                mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_effect_1_cont + fixed_effect_2_cont + fixed_effect_3_cont, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_f);
                if (!is.null(mix\$U)) {
                h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) ); ff <- fitted(mix);
                r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
                SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
                h2s <- append(h2s, h2\$Estimate); h2ses <- append(h2ses, h2\$SE); r2s <- append(r2s, r2); sses <- append(sses, SSE);
                }} ';
            }
            $grm_no_prm_fixed_effects_f3_cont_reps_test_gcorr_cmd .= '
            write.table(data.frame(h2s_vals=c(paste(h2s,collapse=\',\')), h2s_mean=c(mean(h2s,na.rm=TRUE)), h2ses_vals=c(paste(h2ses,collapse=\',\')), h2ses_mean=c(mean(h2ses,na.rm=TRUE)), r2s_vals=c(paste(r2s,collapse=\',\')), r2s_mean=c(mean(r2s,na.rm=TRUE)), sses_vals=c(paste(sses,collapse=\',\')), sses_mean = c(mean(sses,na.rm=TRUE)) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_f3_cont_reps_test_gcorr_cmd;
            my $grm_no_prm_fixed_effects_f3_cont_reps_test_gcorr_cmd_status = system($grm_no_prm_fixed_effects_f3_cont_reps_test_gcorr_cmd);

            open($F_avg_rep_acc_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_rep_acc_f>;
                while (my $row = <$F_avg_rep_acc_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $reps_test_acc_f3_cont = \@columns;
                }
            close($F_avg_rep_acc_f);

            my $grm_no_prm_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
            write.table(data.frame(value=h2\$Estimate, se=h2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_no_prm_cmd;
            my $grm_no_prm_cmd_status = system($grm_no_prm_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                $header_no_prm = <$fh>;
                @header_cols_no_prm = ();
                if ($csv->parse($header_no_prm)) {
                    @header_cols_no_prm = $csv->fields();
                }

                while (my $row = <$fh>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    my $col_counter = 0;
                    foreach my $encoded_trait (@header_cols_no_prm) {
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_grm;

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_grm;

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_grm;

            my $grm_no_prm_fixed_effects_grm_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_grm_rep_gcorr_cmd;
            my $grm_no_prm_fixed_effects_grm_rep_gcorr_cmd_status = system($grm_no_prm_fixed_effects_grm_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_grm = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_grm = $columns[0];
                        @gcorr_qarr_grm = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $grm_prm_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile27.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            #prm_mat <- as.matrix(prm_mat_cols) %*% t(as.matrix(prm_mat_cols));
            prm_mat[is.na(prm_mat)] <- 0;
            prm_mat <- prm_mat/ncol(prm_mat_cols);
            cor_plot <- ggcorr(data = NULL, cor_matrix = prm_mat, hjust = 1, size = 3, color = \'grey50\', label = FALSE, layout.exp = 1);
            ggsave(\''.$analytics_protocol_figure_tempfile_8.'\', cor_plot, device=\'png\', width=50, height=50, units=\'in\', limitsize = FALSE);
            colnames(prm_mat) <- mat\$plot_id_s;
            rownames(prm_mat) <- mat\$plot_id_s;
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
            write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE, env=0, ese=0), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_prm_cmd;
            my $grm_prm_cmd_status = system($grm_prm_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
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
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm_prm, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_grm_prm;

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm_prm, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_grm_prm;

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm_prm, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_grm_prm;

            my $prm_fixed_effects_prm_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile27.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            #prm_mat <- as.matrix(prm_mat_cols) %*% t(as.matrix(prm_mat_cols));
            prm_mat[is.na(prm_mat)] <- 0;
            prm_mat <- prm_mat/ncol(prm_mat_cols);
            colnames(prm_mat) <- mat\$plot_id_s;
            rownames(prm_mat) <- mat\$plot_id_s;
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $prm_fixed_effects_prm_rep_gcorr_cmd;
            my $prm_fixed_effects_prm_rep_gcorr_cmd_status = system($prm_fixed_effects_prm_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_grm_prm = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                prm_mat_cols_q1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q1.'\', header=FALSE, sep=\',\')); prm_mat_q1 <- cor(t(prm_mat_cols_q1)); prm_mat_q1[is.na(prm_mat_q1)] <- 0; prm_mat_q1 <- prm_mat_q1/ncol(prm_mat_cols_q1); colnames(prm_mat_q1) <- mat_q1\$plot_id_s; rownames(prm_mat_q1) <- mat_q1\$plot_id_s;
                prm_mat_cols_q2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q2.'\', header=FALSE, sep=\',\')); prm_mat_q2 <- cor(t(prm_mat_cols_q2)); prm_mat_q2[is.na(prm_mat_q2)] <- 0; prm_mat_q2 <- prm_mat_q2/ncol(prm_mat_cols_q2); colnames(prm_mat_q2) <- mat_q2\$plot_id_s; rownames(prm_mat_q2) <- mat_q2\$plot_id_s;
                prm_mat_cols_q3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q3.'\', header=FALSE, sep=\',\')); prm_mat_q3 <- cor(t(prm_mat_cols_q3)); prm_mat_q3[is.na(prm_mat_q3)] <- 0; prm_mat_q3 <- prm_mat_q3/ncol(prm_mat_cols_q3); colnames(prm_mat_q3) <- mat_q3\$plot_id_s; rownames(prm_mat_q3) <- mat_q3\$plot_id_s;
                prm_mat_cols_q4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q4.'\', header=FALSE, sep=\',\')); prm_mat_q4 <- cor(t(prm_mat_cols_q4)); prm_mat_q4[is.na(prm_mat_q4)] <- 0; prm_mat_q4 <- prm_mat_q4/ncol(prm_mat_cols_q4); colnames(prm_mat_q4) <- mat_q4\$plot_id_s; rownames(prm_mat_q4) <- mat_q4\$plot_id_s;
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat_q1), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat_q2), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat_q3), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat_q4), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_grm_prm = $columns[0];
                        @gcorr_qarr_grm_prm = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $grm_no_prm_fixed_effects_prm_reps_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile27.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            #prm_mat <- as.matrix(prm_mat_cols) %*% t(as.matrix(prm_mat_cols));
            prm_mat[is.na(prm_mat)] <- 0;
            prm_mat <- prm_mat/ncol(prm_mat_cols);
            colnames(prm_mat) <- mat\$plot_id_s;
            rownames(prm_mat) <- mat\$plot_id_s;
            h2s <- c(); h2ses <- c(); r2s <- c(); sses <- c(); ';
            foreach my $r (sort keys %seen_reps_hash) {
                $grm_no_prm_fixed_effects_prm_reps_gcorr_cmd .= '
                mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat), rcov=~vs(units), data=mat[mat\$replicate == \''.$r.'\', ]);
                if (!is.null(mix\$U)) {
                h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) ); ff <- fitted(mix);
                r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
                SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
                h2s <- append(h2s, h2\$Estimate); h2ses <- append(h2ses, h2\$SE); r2s <- append(r2s, r2); sses <- append(sses, SSE);
                } ';
            }
            $grm_no_prm_fixed_effects_prm_reps_gcorr_cmd .= '
            write.table(data.frame(h2s_vals=c(paste(h2s,collapse=\',\')), h2s_mean=c(mean(h2s,na.rm=TRUE)), h2ses_vals=c(paste(h2ses,collapse=\',\')), h2ses_mean=c(mean(h2ses,na.rm=TRUE)), r2s_vals=c(paste(r2s,collapse=\',\')), r2s_mean=c(mean(r2s,na.rm=TRUE)), sses_vals=c(paste(sses,collapse=\',\')), sses_mean = c(mean(sses,na.rm=TRUE)) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_prm_reps_gcorr_cmd;
            my $grm_no_prm_fixed_effects_prm_reps_gcorr_cmd_status = system($grm_no_prm_fixed_effects_prm_reps_gcorr_cmd);

            open($F_avg_rep_acc_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_rep_acc_f>;
                while (my $row = <$F_avg_rep_acc_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $reps_acc_grm_prm = \@columns;
                }
            close($F_avg_rep_acc_f);

            my $grm_no_prm_fixed_effects_prm_reps_test_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile27.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            #prm_mat <- as.matrix(prm_mat_cols) %*% t(as.matrix(prm_mat_cols));
            prm_mat[is.na(prm_mat)] <- 0;
            prm_mat <- prm_mat/ncol(prm_mat_cols);
            colnames(prm_mat) <- mat\$plot_id_s;
            rownames(prm_mat) <- mat\$plot_id_s;
            h2s <- c(); h2ses <- c(); r2s <- c(); sses <- c();
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) ); ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            h2s <- append(h2s, h2\$Estimate); h2ses <- append(h2ses, h2\$SE); r2s <- append(r2s, r2); sses <- append(sses, SSE);
            }
            ';
            my @grm_no_prm_fixed_effects_prm_reps_tests;
            foreach my $r (sort keys %seen_reps_hash) {
                push @grm_no_prm_fixed_effects_prm_reps_tests, $r;
                my $grm_no_prm_fixed_effects_prm_reps_test = join '\',\'', @grm_no_prm_fixed_effects_prm_reps_tests;

                $grm_no_prm_fixed_effects_prm_reps_test_gcorr_cmd .= '
                mat_f <- mat[!mat\$replicate %in% c(\''.$grm_no_prm_fixed_effects_prm_reps_test.'\'), ];
                if (nrow(mat_f)>0) {
                mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat), rcov=~vs(units), data=mat_f);
                if (!is.null(mix\$U)) {
                h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) ); ff <- fitted(mix);
                r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
                SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
                h2s <- append(h2s, h2\$Estimate); h2ses <- append(h2ses, h2\$SE); r2s <- append(r2s, r2); sses <- append(sses, SSE);
                }} ';
            }
            $grm_no_prm_fixed_effects_prm_reps_test_gcorr_cmd .= '
            write.table(data.frame(h2s_vals=c(paste(h2s,collapse=\',\')), h2s_mean=c(mean(h2s,na.rm=TRUE)), h2ses_vals=c(paste(h2ses,collapse=\',\')), h2ses_mean=c(mean(h2ses,na.rm=TRUE)), r2s_vals=c(paste(r2s,collapse=\',\')), r2s_mean=c(mean(r2s,na.rm=TRUE)), sses_vals=c(paste(sses,collapse=\',\')), sses_mean = c(mean(sses,na.rm=TRUE)) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            "';
            print STDERR Dumper $grm_no_prm_fixed_effects_prm_reps_test_gcorr_cmd;
            my $grm_no_prm_fixed_effects_prm_reps_test_gcorr_cmd_status = system($grm_no_prm_fixed_effects_prm_reps_test_gcorr_cmd);

            open($F_avg_rep_acc_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_rep_acc_f>;
                while (my $row = <$F_avg_rep_acc_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $reps_test_acc_grm_prm = \@columns;
                }
            close($F_avg_rep_acc_f);

            my $grm_prm_secondary_traits_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile28.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            #prm_mat <- as.matrix(prm_mat_cols) %*% t(as.matrix(prm_mat_cols));
            prm_mat[is.na(prm_mat)] <- 0;
            prm_mat <- prm_mat/ncol(prm_mat_cols);
            cor_plot <- ggcorr(data = NULL, cor_matrix = prm_mat, hjust = 1, size = 3, color = \'grey50\', label = FALSE, layout.exp = 1);
            ggsave(\''.$analytics_protocol_figure_tempfile_10.'\', cor_plot, device=\'png\', width=50, height=50, units=\'in\', limitsize = FALSE);
            colnames(prm_mat) <- mat\$plot_id_s;
            rownames(prm_mat) <- mat\$plot_id_s;
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat) , rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V3) );
            e2 <- vpredict(mix, h2 ~ (V2) / ( V2+V3) );
            write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE, env=e2\$Estimate, ese=e2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_prm_secondary_traits_cmd;
            my $grm_prm_secondary_traits_cmd_status = system($grm_prm_secondary_traits_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                $header = <$fh>;
                @header_cols = ();
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
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm_prm_secondary_traits, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_grm_prm_secondary_traits;

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm_prm_secondary_traits, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_grm_prm_secondary_traits;

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm_prm_secondary_traits, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_grm_prm_secondary_traits;

            my $prm_fixed_effects_grm_prm_sec_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile28.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            #prm_mat <- as.matrix(prm_mat_cols) %*% t(as.matrix(prm_mat_cols));
            prm_mat[is.na(prm_mat)] <- 0;
            prm_mat <- prm_mat/ncol(prm_mat_cols);
            colnames(prm_mat) <- mat\$plot_id_s;
            rownames(prm_mat) <- mat\$plot_id_s;
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat) , rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat) , rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $prm_fixed_effects_grm_prm_sec_rep_gcorr_cmd;
            my $prm_fixed_effects_grm_prm_sec_rep_gcorr_cmd_status = system($prm_fixed_effects_grm_prm_sec_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_grm_prm_secondary_traits = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                prm_mat_cols_q1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_sec_q1.'\', header=FALSE, sep=\',\')); prm_mat_q1 <- cor(t(prm_mat_cols_q1)); prm_mat_q1[is.na(prm_mat_q1)] <- 0; prm_mat_q1 <- prm_mat_q1/ncol(prm_mat_cols_q1); colnames(prm_mat_q1) <- mat_q1\$plot_id_s; rownames(prm_mat_q1) <- mat_q1\$plot_id_s;
                prm_mat_cols_q2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_sec_q2.'\', header=FALSE, sep=\',\')); prm_mat_q2 <- cor(t(prm_mat_cols_q2)); prm_mat_q2[is.na(prm_mat_q2)] <- 0; prm_mat_q2 <- prm_mat_q2/ncol(prm_mat_cols_q2); colnames(prm_mat_q2) <- mat_q2\$plot_id_s; rownames(prm_mat_q2) <- mat_q2\$plot_id_s;
                prm_mat_cols_q3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_sec_q3.'\', header=FALSE, sep=\',\')); prm_mat_q3 <- cor(t(prm_mat_cols_q3)); prm_mat_q3[is.na(prm_mat_q3)] <- 0; prm_mat_q3 <- prm_mat_q3/ncol(prm_mat_cols_q3); colnames(prm_mat_q3) <- mat_q3\$plot_id_s; rownames(prm_mat_q3) <- mat_q3\$plot_id_s;
                prm_mat_cols_q4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_sec_q4.'\', header=FALSE, sep=\',\')); prm_mat_q4 <- cor(t(prm_mat_cols_q4)); prm_mat_q4[is.na(prm_mat_q4)] <- 0; prm_mat_q4 <- prm_mat_q4/ncol(prm_mat_cols_q4); colnames(prm_mat_q4) <- mat_q4\$plot_id_s; rownames(prm_mat_q4) <- mat_q4\$plot_id_s;
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat_q1), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat_q2), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat_q3), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) + vs(plot_id_s, Gu=prm_mat_q4), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_grm_prm_secondary_traits = $columns[0];
                        @gcorr_qarr_grm_prm_secondary_traits = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $prm_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile27.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            #prm_mat <- as.matrix(prm_mat_cols) %*% t(as.matrix(prm_mat_cols));
            prm_mat[is.na(prm_mat)] <- 0;
            prm_mat <- prm_mat/ncol(prm_mat_cols);
            colnames(prm_mat) <- mat\$plot_id_s;
            rownames(prm_mat) <- mat\$plot_id_s;
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(plot_id_s, Gu=prm_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            e2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
            write.table(data.frame(env=e2\$Estimate, ese=e2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $prm_cmd;
            my $prm_cmd_status = system($prm_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                $header = <$fh>;
                @header_cols = ();
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
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_prm, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_prm;

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_prm, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_prm;

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_prm, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_prm;

            my $prm_fixed_effects_grm_prm_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile27.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            #prm_mat <- as.matrix(prm_mat_cols) %*% t(as.matrix(prm_mat_cols));
            prm_mat[is.na(prm_mat)] <- 0;
            prm_mat <- prm_mat/ncol(prm_mat_cols);
            colnames(prm_mat) <- mat\$plot_id_s;
            rownames(prm_mat) <- mat\$plot_id_s;
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(plot_id_s, Gu=prm_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(plot_id_s, Gu=prm_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $prm_fixed_effects_grm_prm_rep_gcorr_cmd;
            my $prm_fixed_effects_grm_prm_rep_gcorr_cmd_status = system($prm_fixed_effects_grm_prm_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_prm = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                prm_mat_cols_q1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q1.'\', header=FALSE, sep=\',\')); prm_mat_q1 <- cor(t(prm_mat_cols_q1)); prm_mat_q1[is.na(prm_mat_q1)] <- 0; prm_mat_q1 <- prm_mat_q1/ncol(prm_mat_cols_q1); colnames(prm_mat_q1) <- mat_q1\$plot_id_s; rownames(prm_mat_q1) <- mat_q1\$plot_id_s;
                prm_mat_cols_q2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q2.'\', header=FALSE, sep=\',\')); prm_mat_q2 <- cor(t(prm_mat_cols_q2)); prm_mat_q2[is.na(prm_mat_q2)] <- 0; prm_mat_q2 <- prm_mat_q2/ncol(prm_mat_cols_q2); colnames(prm_mat_q2) <- mat_q2\$plot_id_s; rownames(prm_mat_q2) <- mat_q2\$plot_id_s;
                prm_mat_cols_q3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q3.'\', header=FALSE, sep=\',\')); prm_mat_q3 <- cor(t(prm_mat_cols_q3)); prm_mat_q3[is.na(prm_mat_q3)] <- 0; prm_mat_q3 <- prm_mat_q3/ncol(prm_mat_cols_q3); colnames(prm_mat_q3) <- mat_q3\$plot_id_s; rownames(prm_mat_q3) <- mat_q3\$plot_id_s;
                prm_mat_cols_q4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q4.'\', header=FALSE, sep=\',\')); prm_mat_q4 <- cor(t(prm_mat_cols_q4)); prm_mat_q4[is.na(prm_mat_q4)] <- 0; prm_mat_q4 <- prm_mat_q4/ncol(prm_mat_cols_q4); colnames(prm_mat_q4) <- mat_q4\$plot_id_s; rownames(prm_mat_q4) <- mat_q4\$plot_id_s;
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(plot_id_s, Gu=prm_mat_q1), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(plot_id_s, Gu=prm_mat_q2), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(plot_id_s, Gu=prm_mat_q3), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(plot_id_s, Gu=prm_mat_q4), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_prm = $columns[0];
                        @gcorr_qarr_prm = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $grm_id_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile27.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            #prm_mat <- as.matrix(prm_mat_cols) %*% t(as.matrix(prm_mat_cols));
            prm_mat[is.na(prm_mat)] <- 0;
            prm_mat <- prm_mat/ncol(prm_mat_cols);
            colnames(prm_mat) <- mat\$plot_id_s;
            rownames(prm_mat) <- mat\$plot_id_s;
            diag_geno <- diag(nrow(geno_mat));
            colnames(diag_geno) <- colnames(geno_mat);
            rownames(diag_geno) <- rownames(geno_mat);
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
            write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_id_cmd;
            my $grm_id_cmd_status = system($grm_id_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                $header = <$fh>;
                @header_cols = ();
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
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm_id, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_grm_id;

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm_id, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_grm_id;

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm_id, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_grm_id;

            my $prm_fixed_effects_grm_id_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile27.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            #prm_mat <- as.matrix(prm_mat_cols) %*% t(as.matrix(prm_mat_cols));
            prm_mat[is.na(prm_mat)] <- 0;
            prm_mat <- prm_mat/ncol(prm_mat_cols);
            colnames(prm_mat) <- mat\$plot_id_s;
            rownames(prm_mat) <- mat\$plot_id_s;
            diag_geno <- diag(nrow(geno_mat));
            colnames(diag_geno) <- colnames(geno_mat);
            rownames(diag_geno) <- rownames(geno_mat);
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $prm_fixed_effects_grm_id_rep_gcorr_cmd;
            my $prm_fixed_effects_grm_id_rep_gcorr_cmd_status = system($prm_fixed_effects_grm_id_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_grm_id = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
                geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
                geno_mat[is.na(geno_mat)] <- 0;
                diag_geno <- diag(nrow(geno_mat));
                colnames(diag_geno) <- colnames(geno_mat);
                rownames(diag_geno) <- rownames(geno_mat);
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_grm_id = $columns[0];
                        @gcorr_qarr_grm_id = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $grm_id_prm_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile27.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            #prm_mat <- as.matrix(prm_mat_cols) %*% t(as.matrix(prm_mat_cols));
            prm_mat[is.na(prm_mat)] <- 0;
            prm_mat <- prm_mat/ncol(prm_mat_cols);
            colnames(prm_mat) <- mat\$plot_id_s;
            rownames(prm_mat) <- mat\$plot_id_s;
            diag_geno <- diag(nrow(geno_mat));
            colnames(diag_geno) <- colnames(geno_mat);
            rownames(diag_geno) <- rownames(geno_mat);
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=prm_mat), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V3) );
            e2 <- vpredict(mix, h2 ~ (V2) / ( V2+V3) );
            write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE, env=e2\$Estimate, ese=e2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_id_prm_cmd;
            my $grm_id_prm_cmd_status = system($grm_id_prm_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                $header = <$fh>;
                @header_cols = ();
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
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm_id_prm, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_grm_id_prm;

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm_id_prm, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_grm_id_prm;

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm_id_prm, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_grm_id_prm;

            my $prm_fixed_effects_grm_id_prm_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile27.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            #prm_mat <- as.matrix(prm_mat_cols) %*% t(as.matrix(prm_mat_cols));
            prm_mat[is.na(prm_mat)] <- 0;
            prm_mat <- prm_mat/ncol(prm_mat_cols);
            colnames(prm_mat) <- mat\$plot_id_s;
            rownames(prm_mat) <- mat\$plot_id_s;
            diag_geno <- diag(nrow(geno_mat));
            colnames(diag_geno) <- colnames(geno_mat);
            rownames(diag_geno) <- rownames(geno_mat);
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=prm_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=prm_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $prm_fixed_effects_grm_id_prm_rep_gcorr_cmd;
            my $prm_fixed_effects_grm_id_prm_rep_gcorr_cmd_status = system($prm_fixed_effects_grm_id_prm_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_grm_id_prm = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                prm_mat_cols_q1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q1.'\', header=FALSE, sep=\',\')); prm_mat_q1 <- cor(t(prm_mat_cols_q1)); prm_mat_q1[is.na(prm_mat_q1)] <- 0; prm_mat_q1 <- prm_mat_q1/ncol(prm_mat_cols_q1); colnames(prm_mat_q1) <- mat_q1\$plot_id_s; rownames(prm_mat_q1) <- mat_q1\$plot_id_s;
                prm_mat_cols_q2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q2.'\', header=FALSE, sep=\',\')); prm_mat_q2 <- cor(t(prm_mat_cols_q2)); prm_mat_q2[is.na(prm_mat_q2)] <- 0; prm_mat_q2 <- prm_mat_q2/ncol(prm_mat_cols_q2); colnames(prm_mat_q2) <- mat_q2\$plot_id_s; rownames(prm_mat_q2) <- mat_q2\$plot_id_s;
                prm_mat_cols_q3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q3.'\', header=FALSE, sep=\',\')); prm_mat_q3 <- cor(t(prm_mat_cols_q3)); prm_mat_q3[is.na(prm_mat_q3)] <- 0; prm_mat_q3 <- prm_mat_q3/ncol(prm_mat_cols_q3); colnames(prm_mat_q3) <- mat_q3\$plot_id_s; rownames(prm_mat_q3) <- mat_q3\$plot_id_s;
                prm_mat_cols_q4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q4.'\', header=FALSE, sep=\',\')); prm_mat_q4 <- cor(t(prm_mat_cols_q4)); prm_mat_q4[is.na(prm_mat_q4)] <- 0; prm_mat_q4 <- prm_mat_q4/ncol(prm_mat_cols_q4); colnames(prm_mat_q4) <- mat_q4\$plot_id_s; rownames(prm_mat_q4) <- mat_q4\$plot_id_s;
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=prm_mat_q1), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=prm_mat_q2), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=prm_mat_q3), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=prm_mat_q4), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_grm_id_prm = $columns[0];
                        @gcorr_qarr_grm_id_prm = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $grm_id_prm_id_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile27.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            diag_geno <- diag(nrow(geno_mat));
            colnames(diag_geno) <- colnames(geno_mat);
            rownames(diag_geno) <- rownames(geno_mat);
            diag_prm <- diag(nrow(prm_mat));
            colnames(diag_prm) <- mat\$plot_id_s;
            rownames(diag_prm) <- mat\$plot_id_s;
            mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=diag_prm), rcov=~vs(units), data=mat);
            if (!is.null(mix\$U)) {
            #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
            write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V3) );
            e2 <- vpredict(mix, h2 ~ (V2) / ( V2+V3) );
            write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE, env=e2\$Estimate, ese=e2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            ff <- fitted(mix);
            r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
            SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
            write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            }
            "';
            print STDERR Dumper $grm_id_prm_id_cmd;
            my $grm_id_prm_id_cmd_status = system($grm_id_prm_id_cmd);

            open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                print STDERR "Opened $stats_out_tempfile\n";
                $header = <$fh>;
                @header_cols = ();
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
                        if ($encoded_trait eq $trait_name_encoded_string) {
                            my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                            my $stock_id = $columns[0];

                            my $stock_name = $stock_info{$stock_id}->{uniquename};
                            my $value = $columns[$col_counter+1];
                            if (defined $value && $value ne '') {
                                $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                if ($value < $genetic_effect_min_s) {
                                    $genetic_effect_min_s = $value;
                                }
                                elsif ($value >= $genetic_effect_max_s) {
                                    $genetic_effect_max_s = $value;
                                }

                                $genetic_effect_sum_s += abs($value);
                                $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                            }
                        }
                        $col_counter++;
                    }
                }
            close($fh);

            open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                print STDERR "Opened $stats_out_tempfile_residual\n";
                $header_residual = <$fh_residual>;
                @header_cols_residual = ();
                if ($csv->parse($header_residual)) {
                    @header_cols_residual = $csv->fields();
                }
                while (my $row = <$fh_residual>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                    my $stock_id = $columns[0];
                    my $residual = $columns[1];
                    my $fitted = $columns[2];
                    my $stock_name = $plot_id_map{$stock_id};
                    if (defined $residual && $residual ne '') {
                        $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                        $residual_sum_s += abs($residual);
                        $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                    }
                    if (defined $fitted && $fitted ne '') {
                        $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                    }
                    $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                }
            close($fh_residual);

            open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                print STDERR "Opened $stats_out_tempfile_varcomp\n";
                $header_varcomp = <$fh_varcomp>;
                print STDERR Dumper $header_varcomp;
                @header_cols_varcomp = ();
                if ($csv->parse($header_varcomp)) {
                    @header_cols_varcomp = $csv->fields();
                }
                while (my $row = <$fh_varcomp>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_original_grm_id_prm_id, \@columns;
                }
            close($fh_varcomp);
            print STDERR Dumper \@varcomp_original_grm_id_prm_id;

            open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                print STDERR "Opened $stats_out_tempfile_vpredict\n";
                $header_varcomp_h = <$fh_varcomp_h>;
                print STDERR Dumper $header_varcomp_h;
                @header_cols_varcomp_h = ();
                if ($csv->parse($header_varcomp_h)) {
                    @header_cols_varcomp_h = $csv->fields();
                }
                while (my $row = <$fh_varcomp_h>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @varcomp_h_grm_id_prm_id, \@columns;
                }
            close($fh_varcomp_h);
            print STDERR Dumper \@varcomp_h_grm_id_prm_id;

            open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                print STDERR "Opened $stats_out_tempfile_fits\n";
                $header_fits = <$fh_fits>;
                print STDERR Dumper $header_fits;
                @header_cols_fits = ();
                if ($csv->parse($header_fits)) {
                    @header_cols_fits = $csv->fields();
                }
                while (my $row = <$fh_fits>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    push @fits_grm_id_prm_id, \@columns;
                }
            close($fh_fits);
            print STDERR Dumper \@fits_grm_id_prm_id;

            my $prm_fixed_effects_grm_id_prm_id_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
            mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
            geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
            prm_mat_cols <- data.frame(fread(\''.$analytics_protocol_data_tempfile27.'\', header=FALSE, sep=\',\'));
            geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
            geno_mat[is.na(geno_mat)] <- 0;
            prm_mat <- cor(t(prm_mat_cols));
            diag_geno <- diag(nrow(geno_mat));
            colnames(diag_geno) <- colnames(geno_mat);
            rownames(diag_geno) <- rownames(geno_mat);
            diag_prm <- diag(nrow(prm_mat));
            colnames(diag_prm) <- mat\$plot_id_s;
            rownames(diag_prm) <- mat\$plot_id_s;
            mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=diag_prm), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
            if (!is.null(mix1\$U)) {
            mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=diag_prm), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
            if (!is.null(mix2\$U)) {
            mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
            g_corr <- 0;
            try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
            write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
            }
            }
            "';
            print STDERR Dumper $prm_fixed_effects_grm_id_prm_id_rep_gcorr_cmd;
            my $prm_fixed_effects_grm_id_prm_id_rep_gcorr_cmd_status = system($prm_fixed_effects_grm_id_prm_id_rep_gcorr_cmd);

            open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                print STDERR "Opened $stats_out_tempfile_gcor\n";
                $header_fits = <$F_avg_gcorr_f>;
                while (my $row = <$F_avg_gcorr_f>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }
                    $gcorr_grm_id_prm_id = $columns[0];
                }
            close($F_avg_gcorr_f);

            eval {
                my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0; diag_geno <- diag(nrow(geno_mat)); colnames(diag_geno) <- colnames(geno_mat); rownames(diag_geno) <- rownames(geno_mat);
                prm_mat_cols_q1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q1.'\', header=FALSE, sep=\',\')); prm_mat_q1 <- cor(t(prm_mat_cols_q1)); diag_prm_q1 <- diag(nrow(prm_mat_q1)); colnames(diag_prm_q1) <- mat_q1\$plot_id_s; rownames(diag_prm_q1) <- mat_q1\$plot_id_s;
                prm_mat_cols_q2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q2.'\', header=FALSE, sep=\',\')); prm_mat_q2 <- cor(t(prm_mat_cols_q2)); diag_prm_q2 <- diag(nrow(prm_mat_q2)); colnames(diag_prm_q2) <- mat_q2\$plot_id_s; rownames(diag_prm_q2) <- mat_q2\$plot_id_s;
                prm_mat_cols_q3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q3.'\', header=FALSE, sep=\',\')); prm_mat_q3 <- cor(t(prm_mat_cols_q3)); diag_prm_q3 <- diag(nrow(prm_mat_q3)); colnames(diag_prm_q3) <- mat_q3\$plot_id_s; rownames(diag_prm_q3) <- mat_q3\$plot_id_s;
                prm_mat_cols_q4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_q4.'\', header=FALSE, sep=\',\')); prm_mat_q4 <- cor(t(prm_mat_cols_q4)); diag_prm_q4 <- diag(nrow(prm_mat_q4)); colnames(diag_prm_q4) <- mat_q4\$plot_id_s; rownames(diag_prm_q4) <- mat_q4\$plot_id_s;
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=diag_prm_q1), rcov=~vs(units), data=mat_q1);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=diag_prm_q2), rcov=~vs(units), data=mat_q2);
                if (!is.null(mix2\$U)) {
                mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=diag_prm_q3), rcov=~vs(units), data=mat_q3);
                if (!is.null(mix3\$U)) {
                mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=diag_geno) + vs(plot_id_s, Gu=diag_prm_q4), rcov=~vs(units), data=mat_q4);
                if (!is.null(mix4\$U)) {
                m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }}}}
                "';
                print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_gcorr_f>;
                    while (my $row = <$F_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_q_grm_id_prm_id = $columns[0];
                        @gcorr_qarr_grm_id_prm_id = split ',', $columns[1];
                    }
                close($F_gcorr_f);
            };

            my $trait_name_secondary_counter = 1;
            foreach my $t_sec (@sorted_trait_names_secondary) {
                my $grm_prm_secondary_traits_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
                mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
                sec_cont <- data.frame(fread(\''.$analytics_protocol_data_tempfile28.'\', header=FALSE, sep=\',\'));
                sec_binned <- data.frame(fread(\''.$analytics_protocol_data_tempfile30.'\', header=FALSE, sep=\',\'));
                geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
                geno_mat[is.na(geno_mat)] <- 0;
                mat\$fixed_eff <- sec_cont[ ,'.$trait_name_secondary_counter.'];
                mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat);
                if (!is.null(mix\$U)) {
                #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
                write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
                write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
                h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
                write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
                ff <- fitted(mix);
                r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
                SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
                write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
                fixed_r <- anova(mix);
                write.table(data.frame(i=rownames(fixed_r), model=c(fixed_r\$Models), f=c(fixed_r\$F.value), p=c(fixed_r\$\`Pr(>F)\`) ), file=\''.$fixed_eff_anova_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
                }
                "';
                print STDERR Dumper $grm_prm_secondary_traits_cmd;
                my $grm_prm_secondary_traits_cmd_status = system($grm_prm_secondary_traits_cmd);

                open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                    print STDERR "Opened $stats_out_tempfile\n";
                    $header = <$fh>;
                    @header_cols = ();
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
                            if ($encoded_trait eq $trait_name_encoded_string) {
                                my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                                my $stock_id = $columns[0];

                                my $stock_name = $stock_info{$stock_id}->{uniquename};
                                my $value = $columns[$col_counter+1];
                                if (defined $value && $value ne '') {
                                    $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                    if ($value < $genetic_effect_min_s) {
                                        $genetic_effect_min_s = $value;
                                    }
                                    elsif ($value >= $genetic_effect_max_s) {
                                        $genetic_effect_max_s = $value;
                                    }

                                    $genetic_effect_sum_s += abs($value);
                                    $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                                }
                            }
                            $col_counter++;
                        }
                    }
                close($fh);

                open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                    print STDERR "Opened $stats_out_tempfile_residual\n";
                    $header_residual = <$fh_residual>;
                    @header_cols_residual = ();
                    if ($csv->parse($header_residual)) {
                        @header_cols_residual = $csv->fields();
                    }
                    while (my $row = <$fh_residual>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }

                        my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                        my $stock_id = $columns[0];
                        my $residual = $columns[1];
                        my $fitted = $columns[2];
                        my $stock_name = $plot_id_map{$stock_id};
                        if (defined $residual && $residual ne '') {
                            $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                            $residual_sum_s += abs($residual);
                            $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                        }
                        if (defined $fitted && $fitted ne '') {
                            $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                        }
                        $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                    }
                close($fh_residual);

                my @varcomp_original_grm_prm_secondary_traits_havg_vals;
                open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                    print STDERR "Opened $stats_out_tempfile_varcomp\n";
                    $header_varcomp = <$fh_varcomp>;
                    print STDERR Dumper $header_varcomp;
                    @header_cols_varcomp = ();
                    if ($csv->parse($header_varcomp)) {
                        @header_cols_varcomp = $csv->fields();
                    }
                    while (my $row = <$fh_varcomp>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        push @varcomp_original_grm_prm_secondary_traits_havg_vals, \@columns;
                    }
                close($fh_varcomp);
                push @varcomp_original_grm_prm_secondary_traits_havg, \@varcomp_original_grm_prm_secondary_traits_havg_vals;

                my @varcomp_h_grm_prm_secondary_traits_vals;
                open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                    print STDERR "Opened $stats_out_tempfile_vpredict\n";
                    $header_varcomp_h = <$fh_varcomp_h>;
                    print STDERR Dumper $header_varcomp_h;
                    @header_cols_varcomp_h = ();
                    if ($csv->parse($header_varcomp_h)) {
                        @header_cols_varcomp_h = $csv->fields();
                    }
                    while (my $row = <$fh_varcomp_h>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        push @varcomp_h_grm_prm_secondary_traits_vals, \@columns;
                    }
                close($fh_varcomp_h);
                push @varcomp_h_grm_prm_secondary_traits_havg, \@varcomp_h_grm_prm_secondary_traits_vals;

                my @fits_grm_prm_secondary_traits_vals;
                open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                    print STDERR "Opened $stats_out_tempfile_fits\n";
                    $header_fits = <$fh_fits>;
                    print STDERR Dumper $header_fits;
                    @header_cols_fits = ();
                    if ($csv->parse($header_fits)) {
                        @header_cols_fits = $csv->fields();
                    }
                    while (my $row = <$fh_fits>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        push @fits_grm_prm_secondary_traits_vals, \@columns;
                    }
                close($fh_fits);
                push @fits_grm_prm_secondary_traits_havg, \@fits_grm_prm_secondary_traits_vals;

                my @f_anova_grm_fixed_effects_secondary_traits_havg_vals;
                open($fh_f_anova, '<', $fixed_eff_anova_tempfile) or die "Could not open file '$fixed_eff_anova_tempfile' $!";
                    print STDERR "Opened $fixed_eff_anova_tempfile\n";
                    my $header_f_anova = <$fh_f_anova>;
                    print STDERR Dumper $header_f_anova;
                    my @header_cols_f_anova;
                    if ($csv->parse($header_f_anova)) {
                        @header_cols_f_anova = $csv->fields();
                    }
                    while (my $row = <$fh_f_anova>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        push @f_anova_grm_fixed_effects_secondary_traits_havg_vals, \@columns;
                    }
                close($fh_f_anova);
                push @f_anova_grm_prm_secondary_traits_havg, \@f_anova_grm_fixed_effects_secondary_traits_havg_vals;

                my $prm_fixed_effects_grm_prm_sec_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
                mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
                sec_cont <- data.frame(fread(\''.$analytics_protocol_data_tempfile28.'\', header=FALSE, sep=\',\'));
                sec_binned <- data.frame(fread(\''.$analytics_protocol_data_tempfile30.'\', header=FALSE, sep=\',\'));
                geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
                geno_mat[is.na(geno_mat)] <- 0;
                mat\$fixed_eff <- sec_cont[ ,'.$trait_name_secondary_counter.'];
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
                if (!is.null(mix2\$U)) {
                mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr <- 0;
                try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
                write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }
                }
                "';
                print STDERR Dumper $prm_fixed_effects_grm_prm_sec_rep_gcorr_cmd;
                my $prm_fixed_effects_grm_prm_sec_rep_gcorr_cmd_status = system($prm_fixed_effects_grm_prm_sec_rep_gcorr_cmd);

                open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_avg_gcorr_f>;
                    while (my $row = <$F_avg_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_grm_prm_secondary_traits = $columns[0];
                    }
                close($F_avg_gcorr_f);
                push @gcorr_grm_prm_secondary_traits_havg, $gcorr_grm_prm_secondary_traits;

                eval {
                    my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                    mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                    geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                    mat_fq1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_sec_q1.'\', header=FALSE, sep=\',\')); mat_fq2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_sec_q2.'\', header=FALSE, sep=\',\')); mat_fq3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_sec_q3.'\', header=FALSE, sep=\',\')); mat_fq4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_sec_q4.'\', header=FALSE, sep=\',\'));
                    mat_q1\$fixed_eff <- mat_fq1[ ,'.$trait_name_secondary_counter.']; mat_q2\$fixed_eff <- mat_fq2[ ,'.$trait_name_secondary_counter.']; mat_q3\$fixed_eff <- mat_fq3[ ,'.$trait_name_secondary_counter.']; mat_q4\$fixed_eff <- mat_fq4[ ,'.$trait_name_secondary_counter.'];
                    mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q1);
                    if (!is.null(mix1\$U)) {
                    mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q2);
                    if (!is.null(mix2\$U)) {
                    mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q3);
                    if (!is.null(mix3\$U)) {
                    mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q4);
                    if (!is.null(mix4\$U)) {
                    m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                    g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                    write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                    }}}}
                    "';
                    print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                    my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                    open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                        print STDERR "Opened $stats_out_tempfile_gcor\n";
                        $header_fits = <$F_gcorr_f>;
                        while (my $row = <$F_gcorr_f>) {
                            my @columns;
                            if ($csv->parse($row)) {
                                @columns = $csv->fields();
                            }
                            push @gcorr_q_grm_prm_secondary_traits_havg, $columns[0];
                            my @gcorr_qarr = split ',', $columns[1];
                            push @gcorr_qarr_grm_prm_secondary_traits_havg, \@gcorr_qarr;
                        }
                    close($F_gcorr_f);
                };

                my $grm_prm_secondary_favg_traits_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
                mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
                sec_cont <- data.frame(fread(\''.$analytics_protocol_data_tempfile28.'\', header=FALSE, sep=\',\'));
                sec_binned <- data.frame(fread(\''.$analytics_protocol_data_tempfile30.'\', header=FALSE, sep=\',\'));
                geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
                geno_mat[is.na(geno_mat)] <- 0;
                mat\$fixed_eff <- sec_binned[ ,'.$trait_name_secondary_counter.'];
                mix <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat);
                if (!is.null(mix\$U)) {
                #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
                write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
                write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
                h2 <- vpredict(mix, h2 ~ (V1) / ( V1+V2) );
                write.table(data.frame(heritability=h2\$Estimate, hse=h2\$SE), file=\''.$stats_out_tempfile_vpredict.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
                ff <- fitted(mix);
                r2 <- cor(ff\$dataWithFitted\$'.$trait_name_encoded_string.', ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted);
                SSE <- sum( abs(ff\$dataWithFitted\$'.$trait_name_encoded_string.'- ff\$dataWithFitted\$'.$trait_name_encoded_string.'.fitted) );
                write.table(data.frame(sse=c(SSE), r2=c(r2)), file=\''.$stats_out_tempfile_fits.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
                fixed_r <- anova(mix);
                write.table(data.frame(i=rownames(fixed_r), model=c(fixed_r\$Models), f=c(fixed_r\$F.value), p=c(fixed_r\$\`Pr(>F)\`) ), file=\''.$fixed_eff_anova_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
                }
                "';
                print STDERR Dumper $grm_prm_secondary_favg_traits_cmd;
                my $grm_prm_secondary_favg_traits_cmd_status = system($grm_prm_secondary_favg_traits_cmd);

                open($fh, '<', $stats_out_tempfile) or die "Could not open file '$stats_out_tempfile' $!";
                    print STDERR "Opened $stats_out_tempfile\n";
                    $header = <$fh>;
                    @header_cols = ();
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
                            if ($encoded_trait eq $trait_name_encoded_string) {
                                my $trait = $trait_name_encoder_rev_s{$encoded_trait};
                                my $stock_id = $columns[0];

                                my $stock_name = $stock_info{$stock_id}->{uniquename};
                                my $value = $columns[$col_counter+1];
                                if (defined $value && $value ne '') {
                                    $result_blup_data_s->{$stock_name}->{$trait} = $value;

                                    if ($value < $genetic_effect_min_s) {
                                        $genetic_effect_min_s = $value;
                                    }
                                    elsif ($value >= $genetic_effect_max_s) {
                                        $genetic_effect_max_s = $value;
                                    }

                                    $genetic_effect_sum_s += abs($value);
                                    $genetic_effect_sum_square_s = $genetic_effect_sum_square_s + $value*$value;
                                }
                            }
                            $col_counter++;
                        }
                    }
                close($fh);

                open($fh_residual, '<', $stats_out_tempfile_residual) or die "Could not open file '$stats_out_tempfile_residual' $!";
                    print STDERR "Opened $stats_out_tempfile_residual\n";
                    $header_residual = <$fh_residual>;
                    @header_cols_residual = ();
                    if ($csv->parse($header_residual)) {
                        @header_cols_residual = $csv->fields();
                    }
                    while (my $row = <$fh_residual>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }

                        my $trait_name = $trait_name_encoder_rev_s{$trait_name_encoded_string};
                        my $stock_id = $columns[0];
                        my $residual = $columns[1];
                        my $fitted = $columns[2];
                        my $stock_name = $plot_id_map{$stock_id};
                        if (defined $residual && $residual ne '') {
                            $result_residual_data_s->{$stock_name}->{$trait_name} = $residual;
                            $residual_sum_s += abs($residual);
                            $residual_sum_square_s = $residual_sum_square_s + $residual*$residual;
                        }
                        if (defined $fitted && $fitted ne '') {
                            $result_fitted_data_s->{$stock_name}->{$trait_name} = $fitted;
                        }
                        $model_sum_square_residual_s = $model_sum_square_residual_s + $residual*$residual;
                    }
                close($fh_residual);

                my @varcomp_original_grm_prm_secondary_favg_traits_havg_vals;
                open($fh_varcomp, '<', $stats_out_tempfile_varcomp) or die "Could not open file '$stats_out_tempfile_varcomp' $!";
                    print STDERR "Opened $stats_out_tempfile_varcomp\n";
                    $header_varcomp = <$fh_varcomp>;
                    print STDERR Dumper $header_varcomp;
                    @header_cols_varcomp = ();
                    if ($csv->parse($header_varcomp)) {
                        @header_cols_varcomp = $csv->fields();
                    }
                    while (my $row = <$fh_varcomp>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        push @varcomp_original_grm_prm_secondary_favg_traits_havg_vals, \@columns;
                    }
                close($fh_varcomp);
                push @varcomp_original_grm_prm_secondary_traits_favg, \@varcomp_original_grm_prm_secondary_favg_traits_havg_vals;

                my @varcomp_h_grm_prm_secondary_favg_traits_vals;
                open($fh_varcomp_h, '<', $stats_out_tempfile_vpredict) or die "Could not open file '$stats_out_tempfile_vpredict' $!";
                    print STDERR "Opened $stats_out_tempfile_vpredict\n";
                    $header_varcomp_h = <$fh_varcomp_h>;
                    print STDERR Dumper $header_varcomp_h;
                    @header_cols_varcomp_h = ();
                    if ($csv->parse($header_varcomp_h)) {
                        @header_cols_varcomp_h = $csv->fields();
                    }
                    while (my $row = <$fh_varcomp_h>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        push @varcomp_h_grm_prm_secondary_favg_traits_vals, \@columns;
                    }
                close($fh_varcomp_h);
                push @varcomp_h_grm_prm_secondary_traits_favg, \@varcomp_h_grm_prm_secondary_favg_traits_vals;

                my @fits_grm_prm_secondary_favg_traits_vals;
                open($fh_fits, '<', $stats_out_tempfile_fits) or die "Could not open file '$stats_out_tempfile_fits' $!";
                    print STDERR "Opened $stats_out_tempfile_fits\n";
                    $header_fits = <$fh_fits>;
                    print STDERR Dumper $header_fits;
                    @header_cols_fits = ();
                    if ($csv->parse($header_fits)) {
                        @header_cols_fits = $csv->fields();
                    }
                    while (my $row = <$fh_fits>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        push @fits_grm_prm_secondary_favg_traits_vals, \@columns;
                    }
                close($fh_fits);
                push @fits_grm_prm_secondary_traits_favg, \@fits_grm_prm_secondary_favg_traits_vals;

                my @f_anova_grm_fixed_effects_secondary_traits_favg_vals;
                open($fh_f_anova, '<', $fixed_eff_anova_tempfile) or die "Could not open file '$fixed_eff_anova_tempfile' $!";
                    print STDERR "Opened $fixed_eff_anova_tempfile\n";
                    $header_f_anova = <$fh_f_anova>;
                    print STDERR Dumper $header_f_anova;
                    @header_cols_f_anova = ();
                    if ($csv->parse($header_f_anova)) {
                        @header_cols_f_anova = $csv->fields();
                    }
                    while (my $row = <$fh_f_anova>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        push @f_anova_grm_fixed_effects_secondary_traits_favg_vals, \@columns;
                    }
                close($fh_f_anova);
                push @f_anova_grm_prm_secondary_traits_favg, \@f_anova_grm_fixed_effects_secondary_traits_favg_vals;

                my $prm_fixed_effects_grm_prm_sec_favg_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2); library(ggplot2); library(GGally);
                mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
                geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
                sec_cont <- data.frame(fread(\''.$analytics_protocol_data_tempfile28.'\', header=FALSE, sep=\',\'));
                sec_binned <- data.frame(fread(\''.$analytics_protocol_data_tempfile30.'\', header=FALSE, sep=\',\'));
                geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
                geno_mat[is.na(geno_mat)] <- 0;
                mat\$rowNumber <- as.numeric(mat\$rowNumber);
                mat\$colNumber <- as.numeric(mat\$colNumber);
                mat\$rowNumberFactor <- as.factor(mat\$rowNumberFactor);
                mat\$colNumberFactor <- as.factor(mat\$colNumberFactor);
                mat\$fixed_eff <- sec_binned[ ,'.$trait_name_secondary_counter.'];
                mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'1\', ]);
                if (!is.null(mix1\$U)) {
                mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat[mat\$replicate == \'2\', ]);
                if (!is.null(mix2\$U)) {
                mix_gp_g_reps <- merge(data.frame(g_rep1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_rep2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                g_corr <- 0;
                try (g_corr <- cor(mix_gp_g_reps\$g_rep1, mix_gp_g_reps\$g_rep2, use = \'complete.obs\'));
                write.table(data.frame(gcorr = c(g_corr) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                }
                }
                "';
                print STDERR Dumper $prm_fixed_effects_grm_prm_sec_favg_rep_gcorr_cmd;
                my $prm_fixed_effects_grm_prm_sec_favg_rep_gcorr_cmd_status = system($prm_fixed_effects_grm_prm_sec_favg_rep_gcorr_cmd);

                open($F_avg_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                    print STDERR "Opened $stats_out_tempfile_gcor\n";
                    $header_fits = <$F_avg_gcorr_f>;
                    while (my $row = <$F_avg_gcorr_f>) {
                        my @columns;
                        if ($csv->parse($row)) {
                            @columns = $csv->fields();
                        }
                        $gcorr_grm_prm_secondary_traits = $columns[0];
                    }
                close($F_avg_gcorr_f);
                push @gcorr_grm_prm_secondary_traits_favg, $gcorr_grm_prm_secondary_traits;

                eval {
                    my $spatial_correct_2dspl_rep_gcorr_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
                    mat_q1 <- data.frame(fread(\''.$stats_tempfile_q1.'\', header=TRUE, sep=\',\')); mat_q2 <- data.frame(fread(\''.$stats_tempfile_q2.'\', header=TRUE, sep=\',\')); mat_q3 <- data.frame(fread(\''.$stats_tempfile_q3.'\', header=TRUE, sep=\',\')); mat_q4 <- data.frame(fread(\''.$stats_tempfile_q4.'\', header=TRUE, sep=\',\'));
                    geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\')); geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\'); geno_mat[is.na(geno_mat)] <- 0;
                    mat_fq1 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_sec_fix_q1.'\', header=FALSE, sep=\',\')); mat_fq2 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_sec_fix_q2.'\', header=FALSE, sep=\',\')); mat_fq3 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_sec_fix_q3.'\', header=FALSE, sep=\',\')); mat_fq4 <- data.frame(fread(\''.$analytics_protocol_data_tempfile_prm_sec_fix_q4.'\', header=FALSE, sep=\',\'));
                    mat_q1\$fixed_eff <- mat_fq1[ ,'.$trait_name_secondary_counter.']; mat_q2\$fixed_eff <- mat_fq2[ ,'.$trait_name_secondary_counter.']; mat_q3\$fixed_eff <- mat_fq3[ ,'.$trait_name_secondary_counter.']; mat_q4\$fixed_eff <- mat_fq4[ ,'.$trait_name_secondary_counter.'];
                    mix1 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q1);
                    if (!is.null(mix1\$U)) {
                    mix2 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q2);
                    if (!is.null(mix2\$U)) {
                    mix3 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q3);
                    if (!is.null(mix3\$U)) {
                    mix4 <- mmer('.$trait_name_encoded_string.'~1 + replicate + fixed_eff, random=~vs(id, Gu=geno_mat), rcov=~vs(units), data=mat_q4);
                    if (!is.null(mix4\$U)) {
                    m_q1 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q2 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q3 <- merge(data.frame(g_q1=mix1\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q4 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q5 <- merge(data.frame(g_q2=mix2\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE); m_q6 <- merge(data.frame(g_q3=mix3\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), data.frame(g_q4=mix4\$U\$\`u:id\`\$'.$trait_name_encoded_string.'), by=\'row.names\', all=TRUE);
                    g_corr1 <- 0; g_corr2 <- 0; g_corr3 <- 0; g_corr4 <- 0; g_corr5 <- 0; g_corr6 <- 0; try (g_c1 <- cor(m_q1\$g_q1, m_q1\$g_q2, use = \'complete.obs\')); try (g_c2 <- cor(m_q2\$g_q1, m_q2\$g_q3, use = \'complete.obs\')); try (g_c3 <- cor(m_q3\$g_q1, m_q3\$g_q4, use = \'complete.obs\')); try (g_c4 <- cor(m_q4\$g_q2, m_q4\$g_q3, use = \'complete.obs\')); try (g_c5 <- cor(m_q5\$g_q2, m_q5\$g_q4, use = \'complete.obs\')); try (g_c6 <- cor(m_q6\$g_q3, m_q6\$g_q4, use = \'complete.obs\')); g_c <- c(g_c1, g_c2, g_c3, g_c4, g_c5, g_c6);
                    write.table(data.frame(gcorr = c(mean(g_c,na.rm=TRUE)), gcorra = c(paste(g_c,collapse=\',\')) ), file=\''.$stats_out_tempfile_gcor.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
                    }}}}
                    "';
                    print STDERR Dumper $spatial_correct_2dspl_rep_gcorr_cmd;
                    my $spatial_correct_2dspl_rep_gcorr_status = system($spatial_correct_2dspl_rep_gcorr_cmd);

                    open(my $F_gcorr_f, '<', $stats_out_tempfile_gcor) or die "Could not open file '$stats_out_tempfile_gcor' $!";
                        print STDERR "Opened $stats_out_tempfile_gcor\n";
                        $header_fits = <$F_gcorr_f>;
                        while (my $row = <$F_gcorr_f>) {
                            my @columns;
                            if ($csv->parse($row)) {
                                @columns = $csv->fields();
                            }
                            push @gcorr_q_grm_prm_secondary_traits_favg, $columns[0];
                            my @gcorr_qarr = split ',', $columns[1];
                            push @gcorr_qarr_grm_prm_secondary_traits_favg, \@gcorr_qarr;
                        }
                    close($F_gcorr_f);
                };

                $trait_name_secondary_counter++;
            }
        }

        push @result_blups_all, {
            result_type => $result_type,
            germplasm_result_blups => \%germplasm_result_blups,
            plot_result_blups => \%plot_result_blups,
            parameter => $parameter,
            sim_var => $sim_var,
            time_change => $time_change,
            model_name => $model_name,
            sorted_trait_names_secondary => \@sorted_trait_names_secondary,
            germplasm_data_header => \@germplasm_data_header,
            germplasm_data => \@germplasm_data,
            germplasm_results => \@germplasm_results,
            plots_avg_data_header => \@plots_avg_data_header,
            plots_avg_data => \@plots_avg_data,
            plots_avg_results => \@plots_avg_results,
            plots_h_results => \@plots_h_results,
            germplasm_geno_corr_plot => $analytics_protocol_tempfile_string_1,
            plots_spatial_corr_plot => $analytics_protocol_tempfile_string_2,
            plots_spatial_heatmap_plot => $analytics_protocol_tempfile_string_3,
            plots_spatial_heatmap_traits_plot => $analytics_protocol_tempfile_string_4,
            plots_spatial_ggcorr_plot => $analytics_protocol_tempfile_string_5,
            plots_spatial_heatmap_traits_secondary_plot => $analytics_protocol_tempfile_string_6,
            plots_spatial_heatmap_traits_effects_plot => $analytics_protocol_tempfile_string_7,
            plots_spatial_effects_corr_plot => $analytics_protocol_tempfile_string_8,
            plots_htp_corr_plot => $analytics_protocol_tempfile_string_9,
            plots_secondary_traits_corr_plot => $analytics_protocol_tempfile_string_10,
            varcomp_original_grm => \@varcomp_original_grm,
            varcomp_original_grm_trait_2dspl => \@varcomp_original_grm_trait_2dspl,
            varcomp_original_grm_trait_ar1 => \@varcomp_original_grm_trait_ar1,
            varcomp_original_grm_fixed_effect => \@varcomp_original_grm_fixed_effect,
            varcomp_original_grm_fixed_effects => \@varcomp_original_grm_fixed_effects,
            varcomp_original_grm_fixed_effects_3 => \@varcomp_original_grm_fixed_effects_3,
            varcomp_original_grm_fixed_effects_cont => \@varcomp_original_grm_fixed_effects_cont,
            varcomp_original_grm_fixed_effects_min => \@varcomp_original_grm_fixed_effects_min,
            varcomp_original_grm_fixed_effects_max => \@varcomp_original_grm_fixed_effects_max,
            varcomp_original_grm_fixed_effects_all => \@varcomp_original_grm_fixed_effects_all,
            varcomp_original_grm_fixed_effects_f3_cont => \@varcomp_original_grm_fixed_effects_f3_cont,
            varcomp_original_grm_id => \@varcomp_original_grm_id,
            varcomp_original_grm_id_prm => \@varcomp_original_grm_id_prm,
            varcomp_original_grm_id_prm_id => \@varcomp_original_grm_id_prm_id,
            varcomp_original_grm_prm => \@varcomp_original_grm_prm,
            varcomp_original_grm_prm_secondary_traits => \@varcomp_original_grm_prm_secondary_traits,
            varcomp_original_grm_prm_secondary_traits_favg => \@varcomp_original_grm_prm_secondary_traits_favg,
            varcomp_original_grm_prm_secondary_traits_havg => \@varcomp_original_grm_prm_secondary_traits_havg,
            varcomp_original_prm => \@varcomp_original_prm,
            varcomp_h_grm => \@varcomp_h_grm,
            varcomp_h_grm_trait_2dspl => \@varcomp_h_grm_trait_2dspl,
            varcomp_h_grm_trait_ar1 => \@varcomp_h_grm_trait_ar1,
            varcomp_h_grm_fixed_effect => \@varcomp_h_grm_fixed_effect,
            varcomp_h_grm_fixed_effects => \@varcomp_h_grm_fixed_effects,
            varcomp_h_grm_fixed_effects_3 => \@varcomp_h_grm_fixed_effects_3,
            varcomp_h_grm_fixed_effects_cont => \@varcomp_h_grm_fixed_effects_cont,
            varcomp_h_grm_fixed_effects_min => \@varcomp_h_grm_fixed_effects_min,
            varcomp_h_grm_fixed_effects_max => \@varcomp_h_grm_fixed_effects_max,
            varcomp_h_grm_fixed_effects_all => \@varcomp_h_grm_fixed_effects_all,
            varcomp_h_grm_fixed_effects_f3_cont => \@varcomp_h_grm_fixed_effects_f3_cont,
            varcomp_h_grm_id => \@varcomp_h_grm_id,
            varcomp_h_grm_id_prm => \@varcomp_h_grm_id_prm,
            varcomp_h_grm_id_prm_id => \@varcomp_h_grm_id_prm_id,
            varcomp_h_grm_prm => \@varcomp_h_grm_prm,
            varcomp_h_grm_prm_secondary_traits => \@varcomp_h_grm_prm_secondary_traits,
            varcomp_h_grm_prm_secondary_traits_favg => \@varcomp_h_grm_prm_secondary_traits_favg,
            varcomp_h_grm_prm_secondary_traits_havg => \@varcomp_h_grm_prm_secondary_traits_havg,
            varcomp_h_prm => \@varcomp_h_prm,
            fits_grm => \@fits_grm,
            fits_grm_trait_2dspl => \@fits_grm_trait_2dspl,
            fits_grm_trait_ar1 => \@fits_grm_trait_ar1,
            fits_grm_fixed_effect => \@fits_grm_fixed_effect,
            fits_grm_fixed_effects => \@fits_grm_fixed_effects,
            fits_grm_fixed_effects_3 => \@fits_grm_fixed_effects_3,
            fits_grm_fixed_effects_cont => \@fits_grm_fixed_effects_cont,
            fits_grm_fixed_effects_min => \@fits_grm_fixed_effects_min,
            fits_grm_fixed_effects_max => \@fits_grm_fixed_effects_max,
            fits_grm_fixed_effects_all => \@fits_grm_fixed_effects_all,
            fits_grm_fixed_effects_f3_cont => \@fits_grm_fixed_effects_f3_cont,
            fits_grm_id => \@fits_grm_id,
            fits_grm_id_prm => \@fits_grm_id_prm,
            fits_grm_id_prm_id => \@fits_grm_id_prm_id,
            fits_grm_prm => \@fits_grm_prm,
            fits_grm_prm_secondary_traits => \@fits_grm_prm_secondary_traits,
            fits_grm_prm_secondary_traits_favg => \@fits_grm_prm_secondary_traits_favg,
            fits_grm_prm_secondary_traits_havg => \@fits_grm_prm_secondary_traits_havg,
            fits_prm => \@fits_prm,
            gcorr_favg => $gcorr_favg,
            gcorr_f2 => $gcorr_f2,
            gcorr_f3 => $gcorr_f3,
            gcorr_havg => $gcorr_havg,
            gcorr_fmax => $gcorr_fmax,
            gcorr_fmin => $gcorr_fmin,
            gcorr_fall => $gcorr_fall,
            gcorr_f3_cont => $gcorr_f3_cont,
            gcorr_grm => $gcorr_grm,
            gcorr_grm_2dspl => $gcorr_grm_trait_2dspl,
            gcorr_prm => $gcorr_prm,
            gcorr_grm_id => $gcorr_grm_id,
            gcorr_grm_prm => $gcorr_grm_prm,
            gcorr_grm_id_prm => $gcorr_grm_id_prm,
            gcorr_grm_id_prm_id => $gcorr_grm_id_prm_id,
            gcorr_grm_prm_secondary_traits => $gcorr_grm_prm_secondary_traits,
            gcorr_grm_prm_secondary_traits_favg => \@gcorr_grm_prm_secondary_traits_favg,
            gcorr_grm_prm_secondary_traits_havg => \@gcorr_grm_prm_secondary_traits_havg,
            f_anova_grm_fixed_effect => \@f_anova_grm_fixed_effect,
            f_anova_grm_fixed_effects => \@f_anova_grm_fixed_effects,
            f_anova_grm_fixed_effects_3 => \@f_anova_grm_fixed_effects_3,
            f_anova_grm_fixed_effects_cont => \@f_anova_grm_fixed_effects_cont,
            f_anova_grm_fixed_effects_max => \@f_anova_grm_fixed_effects_max,
            f_anova_grm_fixed_effects_min => \@f_anova_grm_fixed_effects_min,
            f_anova_grm_fixed_effects_all => \@f_anova_grm_fixed_effects_all,
            f_anova_grm_fixed_effects_f3_cont => \@f_anova_grm_fixed_effects_f3_cont,
            f_anova_grm_prm_secondary_traits_havg => \@f_anova_grm_prm_secondary_traits_havg,
            f_anova_grm_prm_secondary_traits_favg => \@f_anova_grm_prm_secondary_traits_favg,
            gcorr_q_grm_trait_2dspl => $gcorr_grm_trait_2dspl_q_mean,
            gcorr_q_favg => $gcorr_q_favg,
            gcorr_q_f2 => $gcorr_q_f2,
            gcorr_q_f3 => $gcorr_q_f3,
            gcorr_q_fall => $gcorr_q_fall,
            gcorr_q_havg => $gcorr_q_havg,
            gcorr_q_fmax => $gcorr_q_fmax,
            gcorr_q_fmin => $gcorr_q_fmin,
            gcorr_q_f3_cont => $gcorr_q_f3_cont,
            gcorr_q_grm => $gcorr_q_grm,
            gcorr_q_prm => $gcorr_q_prm,
            gcorr_q_grm_prm_secondary_traits => $gcorr_q_grm_prm_secondary_traits,
            gcorr_q_grm_prm => $gcorr_q_grm_prm,
            gcorr_q_grm_id => $gcorr_q_grm_id,
            gcorr_q_grm_id_prm => $gcorr_q_grm_id_prm,
            gcorr_q_grm_id_prm_id => $gcorr_q_grm_id_prm_id,
            gcorr_q_grm_prm_secondary_traits_havg => \@gcorr_q_grm_prm_secondary_traits_havg,
            gcorr_q_grm_prm_secondary_traits_favg => \@gcorr_q_grm_prm_secondary_traits_favg,
            gcorr_qarr_grm_trait_2dspl => \@gcorr_grm_trait_2dspl_q_array,
            gcorr_qarr_favg => \@gcorr_qarr_favg,
            gcorr_qarr_f2 => \@gcorr_qarr_f2,
            gcorr_qarr_f3 => \@gcorr_qarr_f3,
            gcorr_qarr_fall => \@gcorr_qarr_fall,
            gcorr_qarr_havg => \@gcorr_qarr_havg,
            gcorr_qarr_fmax => \@gcorr_qarr_fmax,
            gcorr_qarr_fmin => \@gcorr_qarr_fmin,
            gcorr_qarr_f3_cont => \@gcorr_qarr_f3_cont,
            gcorr_qarr_grm => \@gcorr_qarr_grm,
            gcorr_qarr_prm => \@gcorr_qarr_prm,
            gcorr_qarr_grm_prm_secondary_traits => \@gcorr_qarr_grm_prm_secondary_traits,
            gcorr_qarr_grm_prm => \@gcorr_qarr_grm_prm,
            gcorr_qarr_grm_id => \@gcorr_qarr_grm_id,
            gcorr_qarr_grm_id_prm => \@gcorr_qarr_grm_id_prm,
            gcorr_qarr_grm_id_prm_id => \@gcorr_qarr_grm_id_prm_id,
            gcorr_qarr_grm_prm_secondary_traits_havg => \@gcorr_qarr_grm_prm_secondary_traits_havg,
            gcorr_qarr_grm_prm_secondary_traits_favg => \@gcorr_qarr_grm_prm_secondary_traits_favg,
            reps_acc_havg => $reps_acc_havg,
            reps_acc_f3_cont => $reps_acc_f3_cont,
            reps_acc_grm_prm => $reps_acc_grm_prm,
            reps_test_acc_havg => $reps_test_acc_havg,
            reps_test_acc_f3_cont => $reps_test_acc_f3_cont,
            reps_test_acc_grm_prm => $reps_test_acc_grm_prm,
            reps_acc_cross_val => \@reps_acc_cross_val,
            reps_acc_cross_val_havg => \@reps_acc_cross_val_havg,
            reps_acc_cross_val_traits => \@reps_acc_cross_val_traits,
            reps_acc_cross_val_havg_and_traits => \@reps_acc_cross_val_havg_and_traits
        }
    }
    $h = undef;

    my @analytics_protocol_charts;
    my @germplasm_results;
    my @germplasm_data = ();
    my @germplasm_data_header = ("germplasmName");
    my @germplasm_data_values = ();
    my @germplasm_data_values_header = ();
    my @plots_avg_results;
    my @plots_avg_data = ();
    my @plots_avg_data_header = ("plotName");
    my @plots_avg_data_values = ();
    my @plots_avg_data_values_header = ();
    my @plots_avg_corrected_results;
    my @plots_avg_corrected_data = ();
    my @plots_avg_corrected_data_header = ("plotName");
    my @plots_avg_corrected_data_values = ();
    my @plots_avg_corrected_data_values_header = ();

    my $show_summarized_iterations;
    if (scalar(@result_blups_all) > 1 && $show_summarized_iterations) {
        my $analytics_protocol_tempfile_string = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string .= '.png';
        my $analytics_protocol_figure_tempfile = $c->config->{basepath}."/".$analytics_protocol_tempfile_string;
        my $analytics_protocol_data_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile2 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile3 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile4 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile5 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile6 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile7 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile8 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
        my $analytics_protocol_data_tempfile9 = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";

        foreach my $t (@sorted_trait_names) {
            push @germplasm_data_header, ($t."mean", $t."sd", $t."spatialcorrectedgenoeffect");
            push @germplasm_data_values_header, ($t."mean", $t."spatialcorrectedgenoeffect");

            push @plots_avg_data_header, ($t, $t."spatialeffect", $t."spatialcorrected");
            push @plots_avg_data_values_header, ($t, $t."spatialeffect", $t."spatialcorrected");

            push @plots_avg_corrected_data_header, ($t, $t."spatialeffect", $t."spatialcorrected");
            push @plots_avg_corrected_data_values_header, ($t, $t."spatialeffect", $t."spatialcorrected");
        }
        my $result_gblup_iter = 1;
        my $result_sblup_iter = 1;
        foreach my $r (@result_blups_all) {
            if ($r->{result_type} eq 'originalgenoeff') {
                push @germplasm_data_header, ("htpspatialcorrectedgenoeffectmean$result_gblup_iter", "htpspatialcorrectedgenoeffectsd$result_gblup_iter");
                push @germplasm_data_values_header, "htpspatialcorrectedgenoeffectmean$result_gblup_iter";
                $result_gblup_iter++;
            }
            elsif ($r->{result_type} eq 'fullcorr') {
                push @plots_avg_data_header, ("htpspatialeffectmean$result_sblup_iter", "htpspatialeffectsd$result_sblup_iter");
                push @plots_avg_data_values_header, "htpspatialeffectmean$result_sblup_iter";

                push @plots_avg_corrected_data_header, ("htpspatialeffectmean$result_sblup_iter", "htpspatialeffectsd$result_sblup_iter");
                push @plots_avg_corrected_data_values_header, "htpspatialeffectmean$result_sblup_iter";

                foreach my $t (@sorted_trait_names) {
                    push @plots_avg_corrected_data_header, $t."spatialcorrecthtpmean$result_sblup_iter";
                    push @plots_avg_corrected_data_values_header, $t."spatialcorrecthtpmean$result_sblup_iter";
                }

                $result_sblup_iter++;
            }
        }

        foreach my $g (@seen_germplasm) {
            my @line = ($g); #"germplasmName"
            my @values;

            foreach my $t (@sorted_trait_names) {
                my $trait_phenos = $germplasm_phenotypes{$g}->{$t};
                my $trait_pheno_stat = Statistics::Descriptive::Full->new();
                $trait_pheno_stat->add_data(@$trait_phenos);
                my $sd = $trait_pheno_stat->standard_deviation();
                my $mean = $trait_pheno_stat->mean();

                my $geno_trait_spatial_val = $result_blup_data_s->{$g}->{$t};
                push @line, ($mean, $sd, $geno_trait_spatial_val); #$t."mean", $t."sd", $t."spatialcorrectedgenoeffect"
                push @values, ($mean, $geno_trait_spatial_val); #$t."mean", $t."spatialcorrectedgenoeffect"
            }

            foreach my $r (@result_blups_all) {
                if ($r->{result_type} eq 'originalgenoeff') {
                    my $germplasm_result_blups = $r->{germplasm_result_blups};

                    my $geno_blups = $germplasm_result_blups->{$g};
                    my $geno_blups_stat = Statistics::Descriptive::Full->new();
                    $geno_blups_stat->add_data(@$geno_blups);
                    my $geno_sd = $geno_blups_stat->standard_deviation();
                    my $geno_mean = $geno_blups_stat->mean();

                    push @line, ($geno_mean, $geno_sd); #"htpspatialcorrectedgenoeffectmean$result_gblup_iter", "htpspatialcorrectedgenoeffectsd$result_gblup_iter"
                    push @values, $geno_mean; #"htpspatialcorrectedgenoeffectmean$result_gblup_iter"
                }
            }
            push @germplasm_data, \@line;
            push @germplasm_data_values, \@values;
        }

        foreach my $p (@seen_plots) {
            my @line = ($p); #"plotName"
            my @values;

            my @line_corrected = ($p); #"plotName"
            my @values_corrected;

            foreach my $t (@sorted_trait_names) {
                my $val = $plot_phenotypes{$p}->{$t};
                my $env_trait_spatial_val = $result_blup_spatial_data_s->{$p}->{$t};
                my $env_trait_spatial_correct = $val - $env_trait_spatial_val;

                push @line, ($val, $env_trait_spatial_val, $env_trait_spatial_correct); #$t, $t."spatialeffect", $t."spatialcorrected"
                push @values, ($val, $env_trait_spatial_val, $env_trait_spatial_correct); #$t, $t."spatialeffect", $t."spatialcorrected"

                push @line_corrected, ($val, $env_trait_spatial_val, $env_trait_spatial_correct); #$t, $t."spatialeffect", $t."spatialcorrected"
                push @values_corrected, ($val, $env_trait_spatial_val, $env_trait_spatial_correct); #$t, $t."spatialeffect", $t."spatialcorrected"
            }

            foreach my $r (@result_blups_all) {
                if ($r->{result_type} eq 'fullcorr') {
                    my $plot_result_blups = $r->{plot_result_blups};

                    my $plot_blups = $plot_result_blups->{$p};
                    my $plot_blups_stat = Statistics::Descriptive::Full->new();
                    $plot_blups_stat->add_data(@$plot_blups);
                    my $plot_sd = $plot_blups_stat->standard_deviation();
                    my $plot_mean = $plot_blups_stat->mean();
                    my $plot_mean_scaled = $plot_mean*(($max_phenotype - $min_phenotype)/($max_phenotype_htp - $min_phenotype_htp));

                    push @line, ($plot_mean_scaled, $plot_sd);#"htpspatialeffectmean$result_sblup_iter", "htpspatialeffectsd$result_sblup_iter"
                    push @values, $plot_mean_scaled; #"htpspatialeffectmean$result_sblup_iter"

                    push @line_corrected, ($plot_mean_scaled, $plot_sd); #"htpspatialeffectmean$result_sblup_iter", "htpspatialeffectsd$result_sblup_iter"
                    push @values_corrected, $plot_mean_scaled; #"htpspatialeffectmean$result_sblup_iter"

                    foreach my $t (@sorted_trait_names) {
                        my $trait_val = $plot_phenotypes{$p}->{$t};
                        my $val = $trait_val - $plot_mean_scaled;

                        push @line_corrected, $val; #$t."spatialcorrecthtpmean$result_sblup_iter"
                        push @values_corrected, $val; #$t."spatialcorrecthtpmean$result_sblup_iter"
                    }
                }
            }
            push @plots_avg_data, \@line;
            push @plots_avg_data_values, \@values;

            push @plots_avg_corrected_data, \@line_corrected;
            push @plots_avg_corrected_data_values, \@values_corrected;
        }

        open(my $F, ">", $analytics_protocol_data_tempfile) || die "Can't open file ".$analytics_protocol_data_tempfile;
            my $header_string = join ',', @germplasm_data_header;
            print $F "$header_string\n";

            foreach (@germplasm_data) {
                my $string = join ',', @$_;
                print $F "$string\n";
            }
        close($F);

        open(my $F2, ">", $analytics_protocol_data_tempfile2) || die "Can't open file ".$analytics_protocol_data_tempfile2;
            my $header_string2 = join ',', @germplasm_data_values_header;
            print $F2 "$header_string2\n";

            foreach (@germplasm_data_values) {
                my $string = join ',', @$_;
                print $F2 "$string\n";
            }
        close($F2);

        open(my $F3, ">", $analytics_protocol_data_tempfile4) || die "Can't open file ".$analytics_protocol_data_tempfile4;
            my $header_string3 = join ',', @plots_avg_data_header;
            print $F3 "$header_string3\n";

            foreach (@plots_avg_data) {
                my $string = join ',', @$_;
                print $F3 "$string\n";
            }
        close($F3);

        open(my $F4, ">", $analytics_protocol_data_tempfile5) || die "Can't open file ".$analytics_protocol_data_tempfile5;
            my $header_string4 = join ',', @plots_avg_data_values_header;
            print $F4 "$header_string4\n";

            foreach (@plots_avg_data_values) {
                my $string = join ',', @$_;
                print $F4 "$string\n";
            }
        close($F4);

        open(my $F5, ">", $analytics_protocol_data_tempfile7) || die "Can't open file ".$analytics_protocol_data_tempfile7;
            my $header_string5 = join ',', @plots_avg_corrected_data_header;
            print $F5 "$header_string5\n";

            foreach (@plots_avg_corrected_data) {
                my $string = join ',', @$_;
                print $F5 "$string\n";
            }
        close($F5);

        open(my $F6, ">", $analytics_protocol_data_tempfile8) || die "Can't open file ".$analytics_protocol_data_tempfile8;
            my $header_string6 = join ',', @plots_avg_corrected_data_values_header;
            print $F6 "$header_string6\n";

            foreach (@plots_avg_corrected_data_values) {
                my $string = join ',', @$_;
                print $F6 "$string\n";
            }
        close($F6);

        my $r_cmd = 'R -e "library(ggplot2); library(data.table);
        data <- data.frame(fread(\''.$analytics_protocol_data_tempfile2.'\', header=TRUE, sep=\',\'));
        res <- cor(data, use = \'complete.obs\')
        res_rounded <- round(res, 2)
        write.table(res_rounded, file=\''.$analytics_protocol_data_tempfile3.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        "';
        print STDERR Dumper $r_cmd;
        my $status = system($r_cmd);

        open(my $fh, '<', $analytics_protocol_data_tempfile3) or die "Could not open file '$analytics_protocol_data_tempfile3' $!";
            print STDERR "Opened $analytics_protocol_data_tempfile3\n";
            my $header = <$fh>;
            my @header_cols;
            if ($csv->parse($header)) {
                @header_cols = $csv->fields();
            }

            my @header_trait_names = ("Trait", @header_cols);
            push @germplasm_results, \@header_trait_names;

            while (my $row = <$fh>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                push @germplasm_results, \@columns;
            }
        close($fh);

        my $r_cmd2 = 'R -e "library(ggplot2); library(data.table);
        data <- data.frame(fread(\''.$analytics_protocol_data_tempfile5.'\', header=TRUE, sep=\',\'));
        res <- cor(data, use = \'complete.obs\')
        res_rounded <- round(res, 2)
        write.table(res_rounded, file=\''.$analytics_protocol_data_tempfile6.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        "';
        print STDERR Dumper $r_cmd2;
        my $status2 = system($r_cmd2);

        open(my $fh2, '<', $analytics_protocol_data_tempfile6) or die "Could not open file '$analytics_protocol_data_tempfile6' $!";
            print STDERR "Opened $analytics_protocol_data_tempfile6\n";
            my $header2 = <$fh2>;
            my @header_cols2;
            if ($csv->parse($header2)) {
                @header_cols2 = $csv->fields();
            }

            my @header_trait_names2 = ("Trait", @header_cols2);
            push @plots_avg_results, \@header_trait_names2;

            while (my $row = <$fh2>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                push @plots_avg_results, \@columns;
            }
        close($fh2);

        my $r_cmd3 = 'R -e "library(ggplot2); library(data.table);
        data <- data.frame(fread(\''.$analytics_protocol_data_tempfile8.'\', header=TRUE, sep=\',\'));
        res <- cor(data, use = \'complete.obs\')
        res_rounded <- round(res, 2)
        write.table(res_rounded, file=\''.$analytics_protocol_data_tempfile9.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        "';
        print STDERR Dumper $r_cmd3;
        my $status3 = system($r_cmd3);

        open(my $fh3, '<', $analytics_protocol_data_tempfile9) or die "Could not open file '$analytics_protocol_data_tempfile9' $!";
            print STDERR "Opened $analytics_protocol_data_tempfile9\n";
            my $header3 = <$fh3>;
            my @header_cols3;
            if ($csv->parse($header3)) {
                @header_cols3 = $csv->fields();
            }

            my @header_trait_names3 = ("Trait", @header_cols3);
            push @plots_avg_corrected_results, \@header_trait_names3;

            while (my $row = <$fh3>) {
                my @columns;
                if ($csv->parse($row)) {
                    @columns = $csv->fields();
                }

                push @plots_avg_corrected_results, \@columns;
            }
        close($fh3);
    }

    $c->stash->{rest} = {
        observation_variable_id_list => $observation_variable_id_list,
        result_blups_all => \@result_blups_all,
        charts => \@analytics_protocol_charts,
        germplasm_data_header => \@germplasm_data_header,
        germplasm_data => \@germplasm_data,
        germplasm_results => \@germplasm_results,
        plots_avg_data_header => \@plots_avg_data_header,
        plots_avg_data => \@plots_avg_data,
        plots_avg_results => \@plots_avg_results,
        plots_avg_corrected_data_header => \@plots_avg_corrected_data_header,
        plots_avg_corrected_data => \@plots_avg_corrected_data,
        plots_avg_corrected_results => \@plots_avg_corrected_results,
        germplasm_trait_gen_file => $analytics_protocol_genfile_tempfile_string_1
    };
}

sub _check_user_login_analytics {
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
