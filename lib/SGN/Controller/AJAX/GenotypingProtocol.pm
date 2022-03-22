
=head1 NAME

SGN::Controller::AJAX::Search::GenotypingProtocol - a REST controller class to provide genotyping protocol search

=head1 DESCRIPTION


=head1 AUTHOR

=cut

package SGN::Controller::AJAX::GenotypingProtocol;

use Moose;
use Data::Dumper;
use JSON;
use CXGN::People::Login;
use CXGN::Genotype::Protocol;
use CXGN::Genotype::MarkersSearch;
use JSON;
use CXGN::Genotype::Protocol;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON'  },
);

sub genotyping_protocol_grm_genotype_relationships : Path('/ajax/genotyping_protocol/grm_genotype_relationships') : ActionClass('REST') { }
sub genotyping_protocol_grm_genotype_relationships_GET : Args(1) {
   my $self = shift;
   my $c = shift;
   my $protocol_id = shift;
   my $bcs_schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');

   my $protocol = CXGN::Genotype::Protocol->new({
       bcs_schema => $bcs_schema,
       nd_protocol_id => $protocol_id
   });
   my $private_company_id = $protocol->private_company_id();

   my ($user_id, $user_name, $user_role) = _check_user_login_genotyping_protocol($c, 'user', $private_company_id, 'user_access');

   my $grm = $protocol->grm_stock_relatedness();

   $c->stash->{rest} = {grm => $grm};
}

sub genotyping_protocol_delete : Path('/ajax/genotyping_protocol/delete') : ActionClass('REST') { }
sub genotyping_protocol_delete_GET : Args(1) {
    my $self = shift;
    my $c = shift;
    my $protocol_id = shift;
    my $bcs_schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');

    my $protocol = CXGN::Genotype::Protocol->new({
        bcs_schema => $bcs_schema,
        nd_protocol_id => $protocol_id
    });
    my $private_company_id = $protocol->private_company_id();

    my ($user_id, $user_name, $user_role) = _check_user_login_genotyping_protocol($c, 'curator', $private_company_id, 'curator_access');

    my $basepath = $c->config->{basepath};
    my $dbhost = $c->config->{dbhost};
    my $dbname = $c->config->{dbname};
    my $dbuser = $c->config->{dbuser};
    my $dbpass = $c->config->{dbpass};
    my $dir = $c->tempfiles_subdir('/genotype_data_delete_nd_experiment_ids');
    my $temp_file_nd_experiment_id = "$basepath/".$c->tempfile( TEMPLATE => 'genotype_data_delete_nd_experiment_ids/fileXXXX');

    my $return = $protocol->delete_protocol($basepath, $dbhost, $dbname, $dbuser, $dbpass, $temp_file_nd_experiment_id);

    $c->stash->{rest} = $return;
}

sub _check_user_login_genotyping_protocol {
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
