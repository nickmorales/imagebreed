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

sub analytics_protocols_compare_to_trait :Path('/ajax/analytics_protocols_compare_to_trait') Args(0) {
    my $self = shift;
    my $c = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my ($user_id, $user_name, $user_role) = _check_user_login($c, 'curator');
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

    my $protocol_props = decode_json $props_json;
    my $observation_variable_id_list = $protocol_props->{observation_variable_id_list};
    my $observation_variable_number = scalar(@$observation_variable_id_list);
    my $legendre_poly_number = $protocol_props->{legendre_order_number} || 3;

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$schema,
            data_level=>'plot',
            trait_list=>[$trait_id],
            trial_list=>[$trial_id],
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

    my %germplasm_phenotypes;
    my %plot_phenotypes;
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

            push @{$germplasm_phenotypes{$germplasm_name}->{$trait_name}}, $value;
            $plot_phenotypes{$obsunit_stock_uniquename}->{$trait_name} = $value;
        }
    }
    my @seen_germplasm = sort keys %germplasm_phenotypes;
    my @seen_plots = sort keys %plot_phenotypes;

    my $trait_name_string = join ',', @sorted_trait_names;

    # my $spatial_correct_2dspl_cmd = 'R -e "library(sommer); library(data.table); library(reshape2);
    # mat <- data.frame(fread(\''.$stats_tempfile.'\', header=TRUE, sep=\',\'));
    # geno_mat_3col <- data.frame(fread(\''.$grm_file.'\', header=FALSE, sep=\'\t\'));
    # geno_mat <- acast(geno_mat_3col, V1~V2, value.var=\'V3\');
    # geno_mat[is.na(geno_mat)] <- 0;
    # mat\$rowNumber <- as.numeric(mat\$rowNumber);
    # mat\$colNumber <- as.numeric(mat\$colNumber);
    # mat\$rowNumberFactor <- as.factor(mat\$rowNumberFactor);
    # mat\$colNumberFactor <- as.factor(mat\$colNumberFactor);
    # mix <- mmer('.$trait_name_string.'~1 + replicate, random=~vs(id, Gu=geno_mat) +vs(spl2D(rowNumber, colNumber)), rcov=~vs(units), data=mat, tolparinv='.$tolparinv_10.');
    # if (!is.null(mix\$U)) {
    # #gen_cor <- cov2cor(mix\$sigma\$\`u:id\`);
    # write.table(mix\$U\$\`u:id\`, file=\''.$stats_out_tempfile.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');
    # write.table(mix\$U\$\`u:rowNumberFactor\`, file=\''.$stats_out_tempfile_row.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');
    # write.table(mix\$U\$\`u:colNumberFactor\`, file=\''.$stats_out_tempfile_col.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');
    # write.table(data.frame(plot_id = mix\$data\$plot_id, residuals = mix\$residuals, fitted = mix\$fitted), file=\''.$stats_out_tempfile_residual.'\', row.names=FALSE, col.names=TRUE, sep=\'\t\');
    # write.table(summary(mix)\$varcomp, file=\''.$stats_out_tempfile_varcomp.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');
    # X <- with(mat, spl2D(rowNumber, colNumber));
    # spatial_blup_results <- data.frame(plot_id = mat\$plot_id);
    # blups1 <- mix\$U\$\`u:rowNumber\`\$'.$t.';
    # spatial_blup_results\$'.$t.' <- data.matrix(X) %*% data.matrix(blups1);
    # write.table(spatial_blup_results, file=\''.$stats_out_tempfile_2dspl.'\', row.names=FALSE, col.names=TRUE, sep=\'\t\');
    # }
    # "';

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
        if (index($filetype, 'airemlf90_grm_random_regression') != -1) {
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
                    if (index($filetype, 'airemlf90_grm_random_regression') == -1) {
                        $total_num_t = $observation_variable_number;
                    }
                    else {
                        $total_num_t = $legendre_poly_number;
                    }

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
                }
            }
        close($fh);
        print STDERR Dumper \%plot_result_time_blups;
        print STDERR Dumper \%germplasm_result_time_blups;

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

        my $analytics_protocol_tempfile_string_1 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string_1 .= '.png';
        my $analytics_protocol_figure_tempfile_1 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_1;

        my $analytics_protocol_tempfile_string_2 = $c->tempfile( TEMPLATE => 'analytics_protocol_figure/figureXXXX');
        $analytics_protocol_tempfile_string_2 .= '.png';
        my $analytics_protocol_figure_tempfile_2 = $c->config->{basepath}."/".$analytics_protocol_tempfile_string_2;

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
        my @germplasm_data_iteration_header = ("germplasmName", "tmean", "time", "value");
        my @germplasm_data_iteration_data_values = ();
        my @plots_data_iteration_header = ("plotName", "tvalue", "time", "value");
        my @plots_data_iteration_data_values = ();


        foreach my $t (@sorted_trait_names) {
            push @germplasm_data_header, ($t."mean", $t."sd");
            push @germplasm_data_values_header, $t."mean";

            push @plots_avg_data_header, $t;
            push @plots_avg_data_values_header, $t;
        }

        if ($result_type eq 'originalgenoeff') {
            push @germplasm_data_header, ("gmean", "gsd");
            push @germplasm_data_values_header, "gmean";

            foreach my $time (@sorted_seen_times_g) {
                push @germplasm_data_header, "g$time";
                push @germplasm_data_values_header, "g$time";
            }
        }
        elsif ($result_type eq 'fullcorr') {
            push @plots_avg_data_header, ("smean", "ssd");
            push @plots_avg_data_values_header, "smean";

            foreach my $time (@sorted_seen_times_p) {
                push @plots_avg_data_header, "s$time";
                push @plots_avg_data_values_header, "s$time";
            }

            push @plots_avg_corrected_data_header, ("smean", "ssd");
            push @plots_avg_corrected_data_values_header, "smean";

            foreach my $t (@sorted_trait_names) {
                push @plots_avg_corrected_data_header, $t."csmean";
                push @plots_avg_corrected_data_values_header, $t."csmean";

                foreach my $time (@sorted_seen_times_p) {
                    push @plots_avg_corrected_data_header, "c$time";
                    push @plots_avg_corrected_data_values_header, "c$time";
                }
            }
        }

        foreach my $g (@seen_germplasm) {
            my @line = ($g);
            my @values;

            foreach my $t (@sorted_trait_names) {
                my $trait_phenos = $germplasm_phenotypes{$g}->{$t};
                my $trait_pheno_stat = Statistics::Descriptive::Full->new();
                $trait_pheno_stat->add_data(@$trait_phenos);
                my $sd = $trait_pheno_stat->standard_deviation();
                my $mean = $trait_pheno_stat->mean();
                push @line, ($mean, $sd);
                push @values, $mean;

                foreach my $time (@sorted_seen_times_g) {
                    my $val = $germplasm_result_time_blups{$g}->{$time};
                    push @germplasm_data_iteration_data_values, [$g, $mean, $time, $val];
                }
            }

            if ($result_type eq 'originalgenoeff') {
                my $geno_blups = $germplasm_result_blups{$g};
                my $geno_blups_stat = Statistics::Descriptive::Full->new();
                $geno_blups_stat->add_data(@$geno_blups);
                my $geno_sd = $geno_blups_stat->standard_deviation();
                my $geno_mean = $geno_blups_stat->mean();

                push @line, ($geno_mean, $geno_sd);
                push @values, $geno_mean;

                foreach my $time (@sorted_seen_times_g) {
                    my $val = $germplasm_result_time_blups{$g}->{$time};
                    push @line, $val;
                    push @values, $val;
                }
            }
            push @germplasm_data, \@line;
            push @germplasm_data_values, \@values;
        }

        foreach my $p (@seen_plots) {
            my @line = ($p);
            my @values;

            my @line_corrected = ($p);
            my @values_corrected;

            foreach my $t (@sorted_trait_names) {
                my $val = $plot_phenotypes{$p}->{$t};
                push @line, $val;
                push @values, $val;

                foreach my $time (@sorted_seen_times_p) {
                    my $sval = $plot_result_time_blups{$p}->{$time};
                    push @plots_data_iteration_data_values, [$p, $val, $time, $sval];
                }
            }

            if ($result_type eq 'fullcorr') {
                my $plot_blups = $plot_result_blups{$p};
                my $plot_blups_stat = Statistics::Descriptive::Full->new();
                $plot_blups_stat->add_data(@$plot_blups);
                my $plot_sd = $plot_blups_stat->standard_deviation();
                my $plot_mean = $plot_blups_stat->mean();

                push @line, ($plot_mean, $plot_sd);
                push @values, $plot_mean;

                foreach my $time (@sorted_seen_times_p) {
                    my $val = $plot_result_time_blups{$p}->{$time};
                    push @line, $val;
                    push @values, $val;
                }

                push @line_corrected, ($plot_mean, $plot_sd);
                push @values_corrected, $plot_mean;

                foreach my $t (@sorted_trait_names) {
                    my $val = $plot_phenotypes{$p}->{$t} - $plot_mean;
                    push @line_corrected, $val;
                    push @values_corrected, $val;

                    foreach my $time (@sorted_seen_times_p) {
                        my $val = $plot_phenotypes{$p}->{$t} - $plot_result_time_blups{$p}->{$time};
                        push @line_corrected, $val;
                        push @values_corrected, $val;
                    }
                }
            }
            push @plots_avg_data, \@line;
            push @plots_avg_data_values, \@values;

            push @plots_avg_corrected_data, \@line_corrected;
            push @plots_avg_corrected_data_values, \@values_corrected;
        }

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

        open(my $F14, ">", $analytics_protocol_data_tempfile14) || die "Can't open file ".$analytics_protocol_data_tempfile14;
            my $header_string14 = join ',', @plots_avg_corrected_data_header;
            print $F14 "$header_string14\n";

            foreach (@plots_avg_corrected_data) {
                my $string = join ',', @$_;
                print $F14 "$string\n";
            }
        close($F14);

        open(my $F15, ">", $analytics_protocol_data_tempfile15) || die "Can't open file ".$analytics_protocol_data_tempfile15;
            my $header_string15 = join ',', @plots_avg_corrected_data_values_header;
            print $F15 "$header_string15\n";

            foreach (@plots_avg_corrected_data_values) {
                my $string = join ',', @$_;
                print $F15 "$string\n";
            }
        close($F15);

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

        if ($result_type eq 'originalgenoeff') {
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

            my $r_cmd_i3 = 'R -e "library(ggplot2); library(data.table);
            data <- data.frame(fread(\''.$analytics_protocol_data_tempfile15.'\', header=TRUE, sep=\',\'));
            res <- cor(data, use = \'complete.obs\')
            res_rounded <- round(res, 2)
            write.table(res_rounded, file=\''.$analytics_protocol_data_tempfile18.'\', row.names=TRUE, col.names=TRUE, sep=\',\');
            "';
            print STDERR Dumper $r_cmd_i3;
            my $status_i3 = system($r_cmd_i3);

            open(my $fh_i3, '<', $analytics_protocol_data_tempfile18) or die "Could not open file '$analytics_protocol_data_tempfile18' $!";
                print STDERR "Opened $analytics_protocol_data_tempfile18\n";
                my $header3 = <$fh_i3>;
                my @header_cols3;
                if ($csv->parse($header3)) {
                    @header_cols3 = $csv->fields();
                }

                my @header_trait_names3 = ("Trait", @header_cols3);
                push @plots_avg_corrected_results, \@header_trait_names3;

                while (my $row = <$fh_i3>) {
                    my @columns;
                    if ($csv->parse($row)) {
                        @columns = $csv->fields();
                    }

                    push @plots_avg_corrected_results, \@columns;
                }
            close($fh_i3);

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
            plots_avg_corrected_data_header => \@plots_avg_corrected_data_header,
            plots_avg_corrected_data => \@plots_avg_corrected_data,
            plots_avg_corrected_results => \@plots_avg_corrected_results,
            germplasm_geno_corr_plot => $analytics_protocol_tempfile_string_1,
            plots_spatial_corr_plot => $analytics_protocol_tempfile_string_2
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

    if (scalar(@result_blups_all) > 1) {
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
            push @germplasm_data_header, ($t."mean", $t."sd");
            push @germplasm_data_values_header, $t."mean";

            push @plots_avg_data_header, $t;
            push @plots_avg_data_values_header, $t;
        }
        my $result_gblup_iter = 1;
        my $result_sblup_iter = 1;
        foreach my $r (@result_blups_all) {
            if ($r->{result_type} eq 'originalgenoeff') {
                push @germplasm_data_header, ("gmean$result_gblup_iter", "gsd$result_gblup_iter");
                push @germplasm_data_values_header, "gmean$result_gblup_iter";
                $result_gblup_iter++;
            }
            elsif ($r->{result_type} eq 'fullcorr') {
                push @plots_avg_data_header, ("smean$result_sblup_iter", "ssd$result_sblup_iter");
                push @plots_avg_data_values_header, "smean$result_sblup_iter";

                push @plots_avg_corrected_data_header, ("smean$result_sblup_iter", "ssd$result_sblup_iter");
                push @plots_avg_corrected_data_values_header, "smean$result_sblup_iter";

                foreach my $t (@sorted_trait_names) {
                    push @plots_avg_corrected_data_header, $t."csmean$result_sblup_iter";
                    push @plots_avg_corrected_data_values_header, $t."csmean$result_sblup_iter";
                }

                $result_sblup_iter++;
            }
        }

        foreach my $g (@seen_germplasm) {
            my @line = ($g);
            my @values;

            foreach my $t (@sorted_trait_names) {
                my $trait_phenos = $germplasm_phenotypes{$g}->{$t};
                my $trait_pheno_stat = Statistics::Descriptive::Full->new();
                $trait_pheno_stat->add_data(@$trait_phenos);
                my $sd = $trait_pheno_stat->standard_deviation();
                my $mean = $trait_pheno_stat->mean();
                push @line, ($mean, $sd);
                push @values, $mean;
            }

            foreach my $r (@result_blups_all) {
                if ($r->{result_type} eq 'originalgenoeff') {
                    my $germplasm_result_blups = $r->{germplasm_result_blups};

                    my $geno_blups = $germplasm_result_blups->{$g};
                    my $geno_blups_stat = Statistics::Descriptive::Full->new();
                    $geno_blups_stat->add_data(@$geno_blups);
                    my $geno_sd = $geno_blups_stat->standard_deviation();
                    my $geno_mean = $geno_blups_stat->mean();

                    push @line, ($geno_mean, $geno_sd);
                    push @values, $geno_mean;
                }
            }
            push @germplasm_data, \@line;
            push @germplasm_data_values, \@values;
        }

        foreach my $p (@seen_plots) {
            my @line = ($p);
            my @values;

            my @line_corrected = ($p);
            my @values_corrected;

            foreach my $t (@sorted_trait_names) {
                my $val = $plot_phenotypes{$p}->{$t};
                push @line, $val;
                push @values, $val;
            }

            foreach my $r (@result_blups_all) {
                if ($r->{result_type} eq 'fullcorr') {
                    my $plot_result_blups = $r->{plot_result_blups};

                    my $plot_blups = $plot_result_blups->{$p};
                    my $plot_blups_stat = Statistics::Descriptive::Full->new();
                    $plot_blups_stat->add_data(@$plot_blups);
                    my $plot_sd = $plot_blups_stat->standard_deviation();
                    my $plot_mean = $plot_blups_stat->mean();

                    push @line, ($plot_mean, $plot_sd);
                    push @values, $plot_mean;

                    push @line_corrected, ($plot_mean, $plot_sd);
                    push @values_corrected, $plot_mean;

                    foreach my $t (@sorted_trait_names) {
                        my $val = $plot_phenotypes{$p}->{$t} - $plot_mean;
                        push @line_corrected, $val;
                        push @values_corrected, $val;
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
