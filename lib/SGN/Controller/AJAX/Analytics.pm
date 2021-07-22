package SGN::Controller::AJAX::Analytics;

use Moose;

use File::Slurp;
use Data::Dumper;
use URI::FromHash 'uri';
use JSON;
use CXGN::BreederSearch;

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
