
=head1 NAME

SGN::Controller::AJAX::Search::GenotypingDataProject - a REST controller class to provide genotyping data project

=head1 DESCRIPTION


=head1 AUTHOR

=cut

package SGN::Controller::AJAX::Search::GenotypingDataProject;

use Moose;
use Data::Dumper;
use JSON;
use CXGN::People::Login;
use CXGN::Trial::Search;
use CXGN::Genotype::GenotypingProject;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON' },
   );

sub genotyping_data_project_search : Path('/ajax/genotyping_data_project/search') : ActionClass('REST') { }

sub genotyping_data_project_search_GET : Args(0) {
    my $self = shift;
    my $c = shift;
    my $bcs_schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my ($user_id, $user_name, $user_role) = _check_user_login_genotyping_data_project($c, 0, 0, 0);

    my $trial_search = CXGN::Trial::Search->new({
        bcs_schema=>$bcs_schema,
        trial_design_list=>['genotype_data_project', 'pcr_genotype_data_project'],
        sp_person_id => $user_id,
        subscription_model => $c->config->{subscription_model}
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
            $_->{genotyping_facility}
          ];
    }
    #print STDERR Dumper \@result;

    $c->stash->{rest} = { data => \@result };
}

sub genotyping_project_plates : Path('/ajax/genotyping_project/genotyping_plates') : ActionClass('REST') { }

sub genotyping_project_plates_GET : Args(0) {
    my $self = shift;
    my $c = shift;
    my $bcs_schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $genotyping_project_id = $c->req->param('genotyping_project_id');

    my ($user_id, $user_name, $user_role) = _check_user_login_genotyping_data_project($c, 0, 0, 0);

    my $plate_info = CXGN::Genotype::GenotypingProject->new({
        bcs_schema => $bcs_schema,
        project_id => $genotyping_project_id
    });
    my ($data, $total_count) = $plate_info->get_plate_info();
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
            $folder_string,
            $_->{genotyping_plate_format},
            $_->{genotyping_plate_sample_type},
            "<a class='btn btn-sm btn-default' href='/breeders/trial/$_->{trial_id}/download/layout?format=csv&dataLevel=plate'>Download Layout</a>"
        ];
    }

    $c->stash->{rest} = { data => \@result };

}

sub _check_user_login_genotyping_data_project {
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
