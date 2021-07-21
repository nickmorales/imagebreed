
package SGN::Controller::Analytics;

use Moose;
use URI::FromHash 'uri';
use Data::Dumper;
use JSON::XS;
use Statistics::Descriptive::Full;
use Time::Piece;

BEGIN { extends 'Catalyst::Controller' };

sub view_analytics_protocols :Path('/analytics_protocols') Args(0) {
    my $self = shift;
    my $c = shift;

    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my $user_id;
    if ($c->user()) {
        $user_id = $c->user->get_object()->get_sp_person_id();
    }
    if (!$user_id) {
        $c->res->redirect( uri( path => '/user/login', query => { goto_url => $c->req->uri->path_query } ) );
    }

    $c->stash->{template} = '/analytics_protocols/index.mas';
}

sub analytics_protocol_detail :Path('/analytics_protocols') Args(1) {
    my $self = shift;
    my $c = shift;
    my $analytics_protocol_id = shift;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my $user = $c->user();

    my $user_id;
    if ($c->user()) {
        $user_id = $c->user->get_object()->get_sp_person_id();
    }
    if (!$user_id) {
        $c->res->redirect( uri( path => '/user/login', query => { goto_url => $c->req->uri->path_query } ) );
        $c->detach();
    }

    print STDERR "Viewing analytics protocol with id $analytics_protocol_id\n";

    my $protocolprop_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analytics_protocol_properties', 'protocol_property')->cvterm_id();
    my $protocolprop_results_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analytics_protocol_result_summary', 'protocol_property')->cvterm_id();

    my $q = "SELECT nd_protocol.nd_protocol_id, nd_protocol.name, nd_protocol.type_id, nd_protocol.description, nd_protocol.create_date, nd_protocolprop.value
        FROM nd_protocol
        JOIN nd_protocolprop USING(nd_protocol_id)
        WHERE nd_protocolprop.type_id=$protocolprop_type_cvterm_id AND nd_protocol.nd_protocol_id = ?;";
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute($analytics_protocol_id);
    my ($nd_protocol_id, $name, $type_id, $description, $create_date, $props_json) = $h->fetchrow_array();

    if (! $name) {
        $c->stash->{template} = '/generic_message.mas';
        $c->stash->{message} = 'The requested analytics protocol ID does not exist in the database.';
        return;
    }

    my $q2 = "SELECT value
        FROM nd_protocolprop
        WHERE type_id=$protocolprop_results_type_cvterm_id AND nd_protocol_id = ?;";
    my $h2 = $schema->storage->dbh()->prepare($q2);
    $h2->execute($analytics_protocol_id);
    my ($result_props_json) = $h2->fetchrow_array();

    my %available_types = (
        SGN::Model::Cvterm->get_cvterm_row($schema, 'drone_imagery_analytics_env_simulation_protocol', 'protocol_type')->cvterm_id() => 'Drone Imagery Environment Simulation'
    );

    my $result_props_json_array = $result_props_json ? decode_json $result_props_json : [];
    # print STDERR Dumper $result_props_json_array;

    my @env_corr_results_array = (["id", "Time", "Models", "Accuracy", "Simulation", "SimulationVariance", "FixedEffect", "Parameters"]);
    my $result_props_json_array_total_counter = 1;
    my $result_props_json_array_counter = 1;
    foreach my $a (@$result_props_json_array) {
        my $analytics_result_type = $a->{statistics_select_original};
        my $trait_name_encoder = $a->{trait_name_map};
        my @potential_times;
        #Sommer
        foreach (keys %$trait_name_encoder) {
            push @potential_times, "t$_";
        }
        #ASREML-R
        foreach (values %$trait_name_encoder) {
            push @potential_times, $_;
        }

        my %avg_varcomps = %{$a->{avg_varcomps}};
        my @avg_varcomps_display = @{$a->{avg_varcomps_display}};

        while (my($t, $type_obj) = each %avg_varcomps) {
            while (my($type, $level_obj) = each %$type_obj) {
                foreach my $time (@potential_times) {
                    #Sommer varcomps
                    if (exists($avg_varcomps{$t}->{$type}->{"u:id.$time-$time"}->{vals}) && exists($avg_varcomps{$t}->{$type}->{"u:units.$time-$time"}->{vals})) {
                        my $g_values = $avg_varcomps{$t}->{$type}->{"u:id.$time-$time"}->{vals};
                        my $r_values = $avg_varcomps{$t}->{$type}->{"u:units.$time-$time"}->{vals};
                        my $g_counter = 0;
                        my @h_values_type;
                        foreach my $g_i (@$g_values) {
                            my $r_i = $r_values->[$g_counter];
                            if ($g_i && $r_i) {
                                my $h_i = $g_i + $r_i == 0 ? 0 : $g_i/($g_i + $r_i);
                                push @h_values_type, $h_i;
                                $g_counter++;
                            }
                        }

                        my $stat = Statistics::Descriptive::Full->new();
                        $stat->add_data(@h_values_type);
                        my $std = $stat->standard_deviation() || 0;
                        my $mean = $stat->mean() || 0;
                        push @avg_varcomps_display, {
                            type => $t,
                            type_scenario => $type,
                            level => "h2-$time",
                            vals => \@h_values_type,
                            std => $std,
                            mean => $mean
                        };
                    }
                    #ASREML-R multivariate + univariate
                    elsif (exists($avg_varcomps{$t}->{$type}->{"trait:vm(id_factor, geno_mat_3col)!trait_$time:$time"}->{vals}) && (exists($avg_varcomps{$t}->{$type}->{"units:trait!trait_$time:$time"}->{vals}) || exists($avg_varcomps{$t}->{$type}->{"trait:units!units!trait_$time:$time"}->{vals}) ) ) {
                        my $g_values = $avg_varcomps{$t}->{$type}->{"trait:vm(id_factor, geno_mat_3col)!trait_$time:$time"}->{vals};
                        my $r_values = $avg_varcomps{$t}->{$type}->{"units:trait!trait_$time:$time"}->{vals} || $avg_varcomps{$t}->{$type}->{"trait:units!units!trait_$time:$time"}->{vals};
                        my $g_counter = 0;
                        my @h_values_type;
                        foreach my $g_i (@$g_values) {
                            my $r_i = $r_values->[$g_counter];
                            if ($g_i && $r_i) {
                                my $h_i = $g_i + $r_i == 0 ? 0 : $g_i/($g_i + $r_i);
                                push @h_values_type, $h_i;
                                $g_counter++;
                            }
                        }

                        my $stat = Statistics::Descriptive::Full->new();
                        $stat->add_data(@h_values_type);
                        my $std = $stat->standard_deviation() || 0;
                        my $mean = $stat->mean() || 0;
                        push @avg_varcomps_display, {
                            type => $t,
                            type_scenario => $type,
                            level => "h2-$time",
                            vals => \@h_values_type,
                            std => $std,
                            mean => $mean
                        };
                    }
                }

            }
        }

        $a->{avg_varcomps_display} = \@avg_varcomps_display;

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
            $model_name .= "_$result_props_json_array_counter";

            my $fixed_effect = 'Replicate';

            foreach my $v (@$values) {
                push @env_corr_results_array, [$result_props_json_array_total_counter, $time_change, $model_name, $v, $sim_name, $sim_var, $fixed_effect, $parameter];
                $result_props_json_array_total_counter++
            }
        }

        $result_props_json_array_counter++;
    }

    my @analytics_protocol_charts;
    if (scalar(@$result_props_json_array) > 0) {
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

        my $r_cmd = 'R -e "library(ggplot2); library(data.table);
        data <- data.frame(fread(\''.$analytics_protocol_data_tempfile.'\', header=TRUE, sep=\',\'));
        data\$Models <- factor(data\$Models, levels = c(\'RR_IDPE\',\'RR_EucPE\',\'RR_2DsplTraitPE\',\'RR_CorrTraitPE\',\'AR1_Uni\',\'AR1_Multi\',\'2Dspl_Uni\',\'2Dspl_Multi\'));
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

    $c->stash->{analytics_protocol_id} = $nd_protocol_id;
    $c->stash->{analytics_protocol_name} = $name;
    $c->stash->{analytics_protocol_description} = $description;
    $c->stash->{analytics_protocol_type_id} = $type_id;
    $c->stash->{analytics_protocol_type_name} = $available_types{$type_id};
    $c->stash->{analytics_protocol_create_date} = $create_date;
    $c->stash->{analytics_protocol_properties} = decode_json $props_json;
    $c->stash->{analytics_protocol_result_summary} = $result_props_json_array;
    $c->stash->{analytics_protocol_charts} = \@analytics_protocol_charts;
    $c->stash->{template} = '/analytics_protocols/detail.mas';
}

1;
