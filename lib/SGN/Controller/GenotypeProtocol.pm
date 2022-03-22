package SGN::Controller::GenotypeProtocol;

use Moose;
use Data::Dumper;
use Try::Tiny;
use SGN::Model::Cvterm;
use Data::Dumper;
use CXGN::Trial::Folder;
use CXGN::Genotype::Protocol;
use File::Basename qw | basename dirname|;
use File::Spec::Functions;
use File::Slurp qw | read_file |;


BEGIN { extends 'Catalyst::Controller'; }

has 'schema' => (
    is       => 'rw',
    isa      => 'DBIx::Class::Schema',
    lazy_build => 1,
);

sub _build_schema {
    shift->_app->dbic_schema( 'Bio::Chado::Schema', 'sgn_chado' )
}

sub protocol_page :Path("/breeders_toolbox/protocol") Args(1) {
    my $self = shift;
    my $c = shift;
    my $protocol_id = shift;

    if (!$c->user()) {
        my $url = '/' . $c->req->path;
        $c->res->redirect("/user/login?goto_url=$url");
        $c->detach();
    }

    my $protocol = CXGN::Genotype::Protocol->new({
        bcs_schema => $self->schema,
        nd_protocol_id => $protocol_id
    });

    my $display_observation_unit_type;
    my $observation_unit_type = $protocol->sample_observation_unit_type_name;
    if ($observation_unit_type eq 'tissue_sample_or_accession') {
        $display_observation_unit_type = 'tissue sample or accession';
    } else {
        $display_observation_unit_type = $observation_unit_type;
    }

    $c->stash->{protocol_id} = $protocol_id;
    $c->stash->{protocol_name} = $protocol->protocol_name;
    $c->stash->{protocol_description} = $protocol->protocol_description;
    $c->stash->{protocol_is_grm} = $protocol->is_grm_protocol;
    $c->stash->{markers} = $protocol->markers || {};
    $c->stash->{marker_names} = $protocol->marker_names || [];
    $c->stash->{header_information_lines} = $protocol->header_information_lines || [];
    $c->stash->{reference_genome_name} = $protocol->reference_genome_name;
    $c->stash->{species_name} = $protocol->species_name;
    $c->stash->{create_date} = $protocol->create_date;
    $c->stash->{sample_observation_unit_type_name} = $display_observation_unit_type;
    $c->stash->{marker_type} = $protocol->marker_type;
    $c->stash->{template} = '/breeders_toolbox/genotyping_protocol/index.mas';
}


sub pcr_protocol_genotype_data_download : Path('/protocol_genotype_data/pcr_download/') Args(1) {
    my $self  =shift;
    my $c = shift;
    my $file_id = shift;
    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');
    my $file_row = $metadata_schema->resultset("MdFiles")->find({file_id => $file_id});
    my $file_destination =  catfile($file_row->dirname, $file_row->basename);
    my $contents = read_file($file_destination);
    my $file_name = $file_row->basename;

    $c->res->content_type('Application/trt');
    $c->res->header('Content-Disposition', qq[attachment; filename="$file_name"]);
    $c->res->body($contents);
}


1;
