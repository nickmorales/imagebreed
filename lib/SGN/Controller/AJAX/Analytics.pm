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

BEGIN { extends 'Catalyst::Controller::REST' };

__PACKAGE__->config(
    default => 'application/json',
    stash_key => 'rest',
    map => { 'application/json' => 'JSON', 'text/html' => 'JSON'  },
);

sub list_analytics_protocols_by_user_table :Path('/ajax/analytics_protocols/by_user') Args(0) {
    my $self = shift;
    my $c = shift;

    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my ($user_id, $user_name, $user_role) = _check_user_login($c);
    my $protocol_type = $c->req->param('analytics_protocol_type');

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

    #print STDERR Dumper(\@table);
    $c->stash->{rest} = { data => \@table };
}

sub list_analytics_protocols_result_files :Path('/ajax/analytics_protocols/result_files') Args(0) {
    my $self = shift;
    my $c = shift;

    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my ($user_id, $user_name, $user_role) = _check_user_login($c);
    my $analytics_protocol_id = $c->req->param('analytics_protocol_id');

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

    $c->stash->{rest} = { data => \@table };
}

sub analytics_protocols_merge_results :Path('/ajax/analytics_protocols_merge_results') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my ($user_id, $user_name, $user_role) = _check_user_login($c, 'curator');
    my @protocol_ids = split ',', $c->req->param('protocol_ids');
    my $analysis_type = $c->req->param('analysis_type');

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
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my ($user_id, $user_name, $user_role) = _check_user_login($c, 'curator');
    print STDERR Dumper $c->req->params();
    my $protocol_id = $c->req->param('protocol_id');
    my $trait_id = $c->req->param('trait_id');
    my $trial_id = $c->req->param('trial_id');

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
    my %seen_accession_stock_ids;
    my %seen_days_after_plantings;
    my %stock_name_row_col;
    my %plot_row_col_hash;
    my %stock_info;
    my %plot_id_map;
    my %plot_germplasm_map;
    my $min_phenotype = 1000000000000000;
    my $max_phenotype = -1000000000000000;
    my $min_col = 100000000000000;
    my $max_col = -100000000000000;
    my $min_row = 100000000000000;
    my $max_row = -100000000000000;
    foreach my $obs_unit (@$data){
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
    my @seen_plots = sort keys %plot_phenotypes;
    my @accession_ids = sort keys %seen_accession_stock_ids;

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
                    download_format=>'three_column_reciprocal'
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
                    download_format=>'three_column_reciprocal'
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
                    download_format=>'three_column_reciprocal'
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
                    download_format=>'three_column_reciprocal'
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

        print STDERR Dumper \@seen_rows_numbers_sorted;
        print STDERR Dumper scalar(@seen_rows_numbers_sorted);

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
                        print STDERR "C $solution_file_counter_ar1wRowColOnly\n";
                    }
                    elsif ($solution_file_counter_ar1wRowColOnly < scalar(@seen_rows_numbers_sorted) + scalar(@seen_cols_numbers_sorted) ) {
                        my @level_split = split '_', $level;
                        $result_blup_row_spatial_data_ar1wRowColOnly{$level_split[1]} = $value;
                        print STDERR "R $solution_file_counter_ar1wRowColOnly\n";
                    }
                    elsif ($solution_file_counter_ar1wRowColOnly < $number_accessions + scalar(@seen_cols_numbers_sorted) + scalar(@seen_rows_numbers_sorted) ) {
                        my $germplasm_counter = $solution_file_counter_ar1wRowColOnly - scalar(@seen_cols_numbers_sorted) - scalar(@seen_rows_numbers_sorted) + 1;
                        print STDERR "G $germplasm_counter\n";
                        my $stock_name = $accession_id_factor_map_reverse{$germplasm_counter};
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
        print STDERR Dumper \%result_blup_col_spatial_data_ar1wRowColOnly;
        print STDERR Dumper \%result_blup_row_spatial_data_ar1wRowColOnly;

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
        print STDERR Dumper $result_blup_spatial_data_ar1wRowColOnly;
    };
    die;

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
                    elsif ($solution_file_counter_ar1wRowPlusCol < scalar(@seen_rows_numbers_sorted)) {
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
        # print STDERR Dumper $result_blup_spatial_data_ar1wRowPlusCol;

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
                    elsif ($solution_file_counter_ar1wColPlusRow < scalar(@seen_rows_numbers_sorted)) {
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
        # print STDERR Dumper $result_blup_spatial_data_ar1wColPlusRow;

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
    };
}

sub analytics_protocols_compare_to_trait :Path('/ajax/analytics_protocols_compare_to_trait') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my ($user_id, $user_name, $user_role) = _check_user_login($c, 'curator');
    print STDERR Dumper $c->req->params();
    my $protocol_id = $c->req->param('protocol_id');
    my $trait_id = $c->req->param('trait_id');
    my @traits_secondary_id = $c->req->param('traits_secondary') ? split(',', $c->req->param('traits_secondary')) : ();
    my $trial_id = $c->req->param('trial_id');
    my $analysis_run_type = $c->req->param('analysis');

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

    if (!$name) {
        $c->stash->{rest} = { error => "There is no protocol with that ID!"};
        return;
    }

    my $result_props_json_array = $result_props_json ? decode_json $result_props_json : [];
    # print STDERR Dumper $result_props_json_array;
    my %trait_name_map;
    foreach my $a (@$result_props_json_array) {
        my $trait_name_encoder = $a->{trait_name_map};
        print STDERR Dumper $trait_name_encoder;
        while (my ($k,$v) = each %$trait_name_encoder) {
            if (looks_like_number($k)) {
                #'181' => 't3',
                $trait_name_map{$v} = $k;
            }
            else {
                #'Mean Pixel Value|Merged 3 Bands NRN|NDVI Vegetative Index Image|day 181|COMP:0000618' => 't3',
                my @t_comps = split '\|', $k;
                my $time_term = $t_comps[3];
                my ($day, $time) = split ' ', $time_term;
                $trait_name_map{$v} = $time;
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
    my $tolparinv_10 = $tolparinv*10;

    my @legendre_coeff_exec = (
        '1 * $b',
        '$time * $b',
        '(1/2*(3*$time**2 - 1)*$b)',
        '1/2*(5*$time**3 - 3*$time)*$b',
        '1/8*(35*$time**4 - 30*$time**2 + 3)*$b',
        '1/16*(63*$time**5 - 70*$time**2 + 15*$time)*$b',
        '1/16*(231*$time**6 - 315*$time**4 + 105*$time**2 - 5)*$b'
    );

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
            }
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
        $c->stash->{rest} = { error => "There are no htp phenotypes for the trials and traits you have selected!"};
        return;
    }

    my $min_phenotype_htp = 1000000000000000;
    my $max_phenotype_htp = -1000000000000000;
    my $min_time_htp = 1000000000000000;
    my $max_time_htp = -1000000000000000;
    my %plot_phenotypes_htp;
    my %seen_days_after_plantings_htp;
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
            }
        }
    }
    my @seen_plots = sort keys %plot_phenotypes_htp;
    my @seen_germplasm = sort keys %germplasm_phenotypes;
    my @accession_ids = sort keys %seen_accession_stock_ids;

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
                    download_format=>'three_column_reciprocal'
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
                    download_format=>'three_column_reciprocal'
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
                    download_format=>'three_column_reciprocal'
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
                    download_format=>'three_column_reciprocal'
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

    # Prepare phenotype file for Trait Spatial Correction
    my $stats_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_ar1_indata = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_2dspl = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_residual = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_varcomp = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $stats_out_tempfile_factors = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX').".csv";
    my $grm_rename_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');

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

    if ($analysis_run_type eq '2dspl' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wRow') {
        my $spatial_correct_2dspl_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
        mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
        geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
        geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
        geno_mat[is.na(geno_mat)] <- 0;
        mat\$rowNumber <- as.numeric(mat\$rowNumber);
        mat\$colNumber <- as.numeric(mat\$colNumber);
        mat\$rowNumberFactor <- as.factor(mat\$rowNumberFactor);
        mat\$colNumberFactor <- as.factor(mat\$colNumberFactor);
        mix <- mmer('.$trait_name_encoded_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) +vs(spl2D(rowNumber, colNumber)), rcov=~vs(units), data=mat, tolparinv='.$tolparinv_10.');
        if (!is.null(mix\$U)) {
        #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
        write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
        X <- with(mat, spl2D(rowNumber, colNumber));
        spatial_blup_results <- data.frame(plot_id = mat\$plot_id);
        blups1 <- mix\$U\$\`u:rowNumber\`\$'.$trait_name_encoded_string.';
        spatial_blup_results\$'.$trait_name_encoded_string.' <- data.matrix(X) %*% data.matrix(blups1);
        write.table(spatial_blup_results, file=\''.$stats_out_tempfile_2dspl.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
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

        print STDERR Dumper {
            type => 'trait spatial genetic effect 2dspl',
            genetic_effect_sum => $genetic_effect_sum_s,
            genetic_effect_min => $genetic_effect_min_s,
            genetic_effect_max => $genetic_effect_max_s,
        };
    }

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
                    download_format=>'three_column_reciprocal'
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
                    download_format=>'three_column_reciprocal'
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
                    download_format=>'three_column_reciprocal'
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
                    download_format=>'three_column_reciprocal'
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
        summary(mix);
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
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
        summary(mix);
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
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
        summary(mix);
        write.table(summary(mix,coef=TRUE)\$coef.random, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
        write.table(data.frame(plot_id = mat\$plot_id, residuals = mix\$residuals, fitted = mix\$linear.predictors, rowNumber = mat\$rowNumber, colNumber = mat\$colNumber), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\',\');
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
    }

    my @result_blups_all;
    my $q = "SELECT nd_protocol.nd_protocol_id, nd_protocol.name, nd_protocol.description, basename, dirname, md.file_id, md.filetype, nd_protocol.type_id, nd_experiment.type_id
        FROM metadata.md_files AS md
        JOIN metadata.md_metadata AS meta ON (md.metadata_id=meta.metadata_id)
        JOIN phenome.nd_experiment_md_files using(file_id)
        JOIN nd_experiment using(nd_experiment_id)
        JOIN nd_experiment_protocol using(nd_experiment_id)
        JOIN nd_protocol using(nd_protocol_id)
        WHERE nd_protocol.nd_protocol_id=$protocol_id AND nd_experiment.type_id=$analytics_experiment_type_cvterm_id
        ORDER BY md.file_id ASC;";
    print STDERR $q."\n";
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute();
    while (my ($model_id, $model_name, $model_description, $basename, $filename, $file_id, $filetype, $model_type_id, $experiment_type_id, $property_type_id, $property_value) = $h->fetchrow_array()) {
        my $result_type;
        if (index($filetype, 'originalgenoeff') != -1 && index($filetype, 'nicksmixedmodelsanalytics_v1') != -1 && index($filetype, 'datafile') != -1) {
            $result_type = 'originalgenoeff';
        }
        elsif (index($filetype, 'fullcorr') != -1 && index($filetype, 'nicksmixedmodelsanalytics_v1') != -1 && index($filetype, 'datafile') != -1) {
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
                if ($analysis_run_type eq '2dspl' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wRow') {
                    push @plots_avg_data_header, ($t."spatial2Dspl", $t."2Dsplcorrected");
                    # push @plots_avg_data_values_header, ($t."spatial2Dspl", $t."2Dsplcorrected");
                    push @plots_avg_data_values_header, $t."spatial2Dspl";
                }
                if ($analysis_run_type eq 'ar1' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq 'ar1_wCol' || $analysis_run_type eq 'ar1_wRow' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wRow') {
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

            my $row_number = $stock_name_row_col{$p}->{row_number};
            my $col_number = $stock_name_row_col{$p}->{col_number};

            foreach my $t (@sorted_trait_names) {
                my $val = $plot_phenotypes{$p}->{$t} || '';

                foreach my $time (@sorted_seen_times_p) {
                    my $sval = $plot_result_time_blups{$p}->{$time};
                    push @plots_data_iteration_data_values, [$p, $val, $time, $sval]; #"plotName", "tvalue", "time", "value"
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
                    if ($analysis_run_type eq '2dspl' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wRow') {
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
                    if ($analysis_run_type eq 'ar1' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq 'ar1_wCol' || $analysis_run_type eq 'ar1_wRow' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wRow') {
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

                    if ($is_first_plot) {
                        push @type_names_first_line_secondary, $t;
                    }
                }
            }
            push @plots_avg_data, \@line;
            push @plots_avg_data_values, \@values;
            $is_first_plot = 0;
        }

        if ($analysis_run_type eq '2dspl' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wRow') {
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

        if ($result_type eq 'originalgenoeff') {

            if ($analysis_run_type eq '2dspl' || $analysis_run_type eq '2dspl_ar1' || $analysis_run_type eq '2dspl_ar1_wCol' || $analysis_run_type eq '2dspl_ar1_wRow') {
                my $r_cmd_i1 = 'R -e "library(ggplot2); library(data.table);
                data <- data.frame(fread(\''.$analytics_protocol_data_tempfile11.'\', header=TRUE, sep=\',\'));
                res <- cor(data, use = \'complete.obs\')
                res_rounded <- round(res, 2)
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
            my $r_cmd_i2 = 'R -e "library(ggplot2); library(data.table);
            data <- data.frame(fread(\''.$analytics_protocol_data_tempfile13.'\', header=TRUE, sep=\',\'));
            res <- cor(data, use = \'complete.obs\')
            res_rounded <- round(res, 2)
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
            options(device=\'png\');
            par();
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
            options(device=\'png\');
            par();
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
            plot <- ggcorr(data, hjust = 1, size = 3, color = \'grey50\', label = TRUE, label_size = 3, label_round = 2, layout.exp = 1);
            ggsave(\''.$analytics_protocol_figure_tempfile_5.'\', plot, device=\'png\', width=10, height=10, units=\'in\');
            "';
            print STDERR Dumper $r_cmd_ic6;
            my $status_ic6 = system($r_cmd_ic6);

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
        }

        push @result_blups_all, {
            result_type => $result_type,
            germplasm_result_blups => \%germplasm_result_blups,
            plot_result_blups => \%plot_result_blups,
            parameter => $parameter,
            sim_var => $sim_var,
            time_change => $time_change,
            model_name => $model_name,
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
        }
    }

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
    };
}

sub _check_user_login {
    my $c = shift;
    my $role_check = shift;
    my $user_id;
    my $user_name;
    my $user_role;
    my $session_id = $c->req->param("sgn_session_id");

    if ($session_id){
        my $dbh = $c->dbc->dbh;
        my @user_info = CXGN::Login->new($dbh)->query_from_cookie($session_id);
        if (!$user_info[0]){
            $c->stash->{rest} = {error=>'You must be logged in to do this!'};
            $c->detach();
        }
        $user_id = $user_info[0];
        $user_role = $user_info[1];
        my $p = CXGN::People::Person->new($dbh, $user_id);
        $user_name = $p->get_username;
    } else{
        if (!$c->user){
            $c->stash->{rest} = {error=>'You must be logged in to do this!'};
            $c->detach();
        }
        $user_id = $c->user()->get_object()->get_sp_person_id();
        $user_name = $c->user()->get_object()->get_username();
        $user_role = $c->user->get_object->get_user_type();
    }
    if ($role_check && $user_role ne $role_check) {
        $c->stash->{rest} = {error=>'You must have permission to do this! Please contact us!'};
        $c->detach();
    }
    return ($user_id, $user_name, $user_role);
}

1;
