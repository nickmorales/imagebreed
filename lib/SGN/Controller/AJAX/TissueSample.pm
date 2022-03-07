
=head1 NAME

SGN::Controller::AJAX::TissueSample - a REST controller class to provide tissue sample functionality

=head1 DESCRIPTION


=head1 AUTHOR

=cut

package SGN::Controller::AJAX::TissueSample;

use Moose;
use Data::Dumper;
use JSON;
use CXGN::People::Login;
use CXGN::Trial::Search;
use JSON;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON' },
   );

sub tissue_sample_field_trials : Path('/ajax/tissue_samples/field_trials') : ActionClass('REST') { }

sub tissue_sample_field_trials_GET : Args(0) {
    my $self = shift;
    my $c = shift;
    my $bcs_schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my ($user_id, $user_name, $user_role) = _check_user_login_tissue_sample($c, 0, 0, 0);

    my $trial_search = CXGN::Trial::Search->new({
        bcs_schema=>$bcs_schema,
        trial_has_tissue_samples=>1,
        sp_person_id=>$user_id,
        subscription_model=>$c->config->{subscription_model}
    });
    my ($data, $total_count) = $trial_search->search();
    my @result;
    my %selected_columns = ('tissue_sample_name'=>1, 'tissue_sample_id'=>1, 'plant_name'=>1, 'plot_name'=>1, 'block_number'=>1, 'plant_number'=>1, 'plot_number'=>1, 'rep_number'=>1, 'row_number'=>1, 'col_number'=>1, 'accession_name'=>1, 'is_a_control'=>1);
    my $selected_columns_json = encode_json \%selected_columns;
    foreach (@$data){
        my $folder_string = '';
        if ($_->{folder_name}){
            $folder_string = "<a href=\"/folder/$_->{folder_id}\">$_->{folder_name}</a>";
        }
        push @result,
          [
            "<a href=\"/breeders_toolbox/trial/$_->{trial_id}\">$_->{trial_name}</a>",
            $_->{description},
            "<a href=\"/company/$_->{private_company_id}\">$_->{private_company_name}</a>",
            "<a href=\"/breeders/program/$_->{breeding_program_id}\">$_->{breeding_program_name}</a>",
            $folder_string,
            $_->{year},
            $_->{location_name},
            $_->{trial_type},
            $_->{design},
            $_->{project_planting_date},
            $_->{project_harvest_date},
            "<a class='btn btn-sm btn-default' href='/breeders/trial/$_->{trial_id}/download/layout?format=csv&dataLevel=field_trial_tissue_samples&selected_columns=$selected_columns_json'>Download Layout</a>"
          ];
    }
    #print STDERR Dumper \@result;

    $c->stash->{rest} = { data => \@result };
}

sub tissue_sample_genotyping_trials : Path('/ajax/tissue_samples/genotyping_trials') : ActionClass('REST') { }

sub tissue_sample_genotyping_trials_GET : Args(0) {
    my $self = shift;
    my $c = shift;
    my $bcs_schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my ($user_id, $user_name, $user_role) = _check_user_login_tissue_sample($c, 0, 0, 0);

    my $trial_search = CXGN::Trial::Search->new({
        bcs_schema=>$bcs_schema,
        trial_design_list=>['genotyping_plate'],
        sp_person_id=>$user_id,
        subscription_model=>$c->config->{subscription_model}
    });
    my ($data, $total_count) = $trial_search->search();
    my @result;
    foreach (@$data){
        my $folder_string = '';
        if ($_->{folder_name}){
            $folder_string = "<a href=\"/folder/$_->{folder_id}\">$_->{folder_name}</a>";
        }
        push @result,
          [
            "<a href=\"/breeders_toolbox/trial/$_->{trial_id}\">$_->{trial_name}</a>",
            $_->{description},
            "<a href=\"/company/$_->{private_company_id}\">$_->{private_company_name}</a>",
            "<a href=\"/breeders/program/$_->{breeding_program_id}\">$_->{breeding_program_name}</a>",
            $folder_string,
            $_->{year},
            $_->{location_name},
            $_->{genotyping_facility},
            $_->{genotyping_plate_format},
            $_->{genotyping_plate_sample_type},
            "<a class='btn btn-sm btn-default' href='/breeders/trial/$_->{trial_id}/download/layout?format=csv&dataLevel=plate'>Download Layout</a>"
          ];
    }
    #print STDERR Dumper \@result;

    $c->stash->{rest} = { data => \@result };
}

sub tissue_sample_sampling_trials : Path('/ajax/tissue_samples/sampling_trials') : ActionClass('REST') { }

sub tissue_sample_sampling_trials_GET : Args(0) {
    my $self = shift;
    my $c = shift;
    my $bcs_schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my ($user_id, $user_name, $user_role) = _check_user_login_tissue_sample($c, 0, 0, 0);

    my $trial_search = CXGN::Trial::Search->new({
        bcs_schema=>$bcs_schema,
        trial_design_list=>['sampling_trial'],
        sp_person_id=>$user_id,
        subscription_model=>$c->config->{subscription_model}
    });
    my ($data, $total_count) = $trial_search->search();
    my @result;
    foreach (@$data){
        my $folder_string = '';
        if ($_->{folder_name}){
            $folder_string = "<a href=\"/folder/$_->{folder_id}\">$_->{folder_name}</a>";
        }
        push @result,
          [
            "<a href=\"/breeders_toolbox/trial/$_->{trial_id}\">$_->{trial_name}</a>",
            $_->{description},
            "<a href=\"/company/$_->{private_company_id}\">$_->{private_company_name}</a>",
            "<a href=\"/breeders/program/$_->{breeding_program_id}\">$_->{breeding_program_name}</a>",
            $folder_string,
            $_->{year},
            $_->{location_name},
            $_->{sampling_facility},
            $_->{sampling_trial_sample_type},
            "<a class='btn btn-sm btn-default' href='/breeders/trial/$_->{trial_id}/download/layout?format=csv&dataLevel=samplingtrial'>Download Layout</a>"
          ];
    }
    #print STDERR Dumper \@result;

    $c->stash->{rest} = { data => \@result };
}

sub _check_user_login_tissue_sample {
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
