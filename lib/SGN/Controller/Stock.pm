package SGN::Controller::Stock;

=head1 NAME

SGN::Controller::Stock - Catalyst controller for pages dealing with
stocks (e.g. accession, population, etc.)

=cut

use Moose;
use namespace::autoclean;
use YAML::Any qw/LoadFile/;

use URI::FromHash 'uri';
use List::Compare;
use File::Temp qw / tempfile /;
use File::Slurp;
use JSON::Any;
use JSON;

use CXGN::Chado::Stock;
use SGN::View::Stock qw/stock_link stock_organisms stock_types breeding_programs /;
use Bio::Chado::NaturalDiversity::Reports;
use SGN::Model::Cvterm;
use Data::Dumper;
use CXGN::Chado::Publication;
use CXGN::Genotype::DownloadFactory;
use CXGN::Login;

BEGIN { extends 'Catalyst::Controller' }
with 'Catalyst::Component::ApplicationAttribute';

has 'schema' => (
    is       => 'rw',
    isa      => 'DBIx::Class::Schema',
    lazy_build => 1,
);
sub _build_schema {
    shift->_app->dbic_schema( 'Bio::Chado::Schema', 'sgn_chado' )
}

has 'default_page_size' => (
    is      => 'ro',
    default => 20,
);

=head1 PUBLIC ACTIONS


=head2 stock search using jQuery data tables

=cut

sub stock_search :Path('/search/stocks') Args(0) {
    my ($self, $c ) = @_;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");

    my $sgn_session_id = $c->req->param("sgn_session_id");
    my $user = $c->user();
    if (!$user && !$sgn_session_id) {
        $c->res->redirect( uri( path => '/user/login', query => { goto_url => $c->req->uri->path_query } ) );
        return;
    } elsif (!$user && $sgn_session_id) {
        my $login = CXGN::Login->new($schema->storage->dbh);
        my $logged_in = $login->query_from_cookie($sgn_session_id);
        if (!$logged_in){
            $c->res->redirect( uri( path => '/user/login', query => { goto_url => $c->req->uri->path_query } ) );
            return;
        }
    }

    my @editable_stock_props = split ',',$c->get_conf('editable_stock_props');
    $c->stash(
        template => '/search/stocks.mas',
        stock_types => stock_types($self->schema),
        organisms   => stock_organisms($self->schema) ,
        sp_person_autocomplete_uri => '/ajax/people/autocomplete',
        trait_autocomplete_uri     => '/ajax/stock/trait_autocomplete',
        onto_autocomplete_uri      => '/ajax/cvterm/autocomplete',
        trait_db_name              => $c->get_conf('trait_ontology_db_name'),
        breeding_programs          => breeding_programs($self->schema),
        editable_stock_props => \@editable_stock_props
    );
}


=head2 search DEPRECATED

Public path: /stock/search

Display a stock search form, or handle stock searching.

=cut

sub search :Path('/stock/search') Args(0) {
    my ( $self, $c ) = @_;
    $c->stash(
        template => '/search/stocks.mas',
        stock_types => stock_types($self->schema),
        organisms   => stock_organisms($self->schema) ,
        sp_person_autocomplete_uri => $c->uri_for( '/ajax/people/autocomplete' ),
        trait_autocomplete_uri     => $c->uri_for('/ajax/stock/trait_autocomplete'),
        onto_autocomplete_uri      => $c->uri_for('/ajax/cvterm/autocomplete'),
        trait_db_name              => $c->get_conf('trait_ontology_db_name'),
        breeding_programs          => breeding_programs($self->schema),
    );
    #my $form = HTML::FormFu->new(LoadFile($c->path_to(qw{forms stock stock_search.yaml})));
    #my $trait_db_name = $c->get_conf('trait_ontology_db_name');
    #$c->stash(
    #    template                   => '/search/phenotypes/stock.mas',
    #    request                    => $c->req,
    #    form                       => $form,
    #    form_opts                  => { stock_types => stock_types($self->schema), organisms => stock_organisms($self->schema)} ,
    #    results                    => $results,
    #    sp_person_autocomplete_uri => $c->uri_for( '/ajax/people/autocomplete' ),
    #    trait_autocomplete_uri     => $c->uri_for('/ajax/stock/trait_autocomplete'),
    #    onto_autocomplete_uri      => $c->uri_for('/ajax/cvterm/autocomplete'),
	#trait_db_name              => $trait_db_name,
        #pagination_link_maker      => sub {
        #    return uri( query => { %{$c->req->params} , page => shift } );
        #},
        #);
}

=head2 new_stock

Public path: /stock/0/new

Create a new stock.

Chained off of L</get_stock> below.

=cut

sub new_stock : Chained('get_stock') PathPart('new') Args(0) {
    my ( $self, $c ) = @_;
    $c->stash(
        template => '/stock/new_stock.mas',

        stockref => {
            action    => "new",
            stock_id  => 0 ,
            stock     => $c->stash->{stock},
            schema    => $self->schema,
        },
        );
}

=head2 view_stock

Public path: /stock/<stock_id>/view

View a stock's detail page.

Chained off of L</get_stock> below.

=cut

our $time;

sub view_stock : Chained('get_stock') PathPart('view') Args(0) {
    my ( $self, $c, $action) = @_;

    if (!$c->user()) {
        my $url = '/' . $c->req->path;
        $c->res->redirect("/user/login?goto_url=$url");
        $c->detach();
    }

    $time = time();

    if( $c->stash->{stock_row} ) {
        $c->forward('get_stock_extended_info');
    }

    my $logged_user = $c->user;
    my $person_id = $logged_user->get_object->get_sp_person_id if $logged_user;
    my $user_role = 1 if $logged_user;
    my $curator   = $logged_user->check_roles('curator') if $logged_user;
    my $submitter = $logged_user->check_roles('submitter') if $logged_user;
    my $sequencer = $logged_user->check_roles('sequencer') if $logged_user;

    my $dbh = $c->dbc->dbh;

    ##################

    ###Check if a stock page can be printed###

    my $stock = $c->stash->{stock};
    my $stock_row = $c->stash->{stock_row};
    my $stock_id = $stock ? $stock->stock_id : undef ;
    my $stock_type = $stock_row ? $stock_row->type->name : undef ;
    my $type = 1 if $stock_type && !$stock_type=~ m/population/;
    # print message if stock_id is not valid
    unless ( ( $stock_id =~ m /^\d+$/ ) || ($action eq 'new' && !$stock_id) ) {
        $c->throw_404( "No stock/accession exists for that identifier." );
    }
    unless ( $stock_row || !$stock_id && $action && $action eq 'new' ) {
        $c->throw_404( "No stock/accession exists for that identifier." );
    }

    print STDERR "Checkpoint 2: Elapsed ".(time() - $time)."\n";

    my $props = $self->_stockprops($stock_row);
    # print message if the stock is visible only to certain user roles
    my @logged_user_roles = $logged_user->roles if $logged_user;
    my @prop_roles = @{ $props->{visible_to_role} } if  ref($props->{visible_to_role} );
    my $lc = List::Compare->new( {
        lists    => [\@logged_user_roles, \@prop_roles],
        unsorted => 1,
                              } );
    my @intersection = $lc->get_intersection;
    if ( !$curator && @prop_roles  && !@intersection) { # if there is no match between user roles and stock visible_to_role props
       # $c->throw(is_client_error => 0,
       #           title             => 'Restricted page',
       #           message           => "Stock $stock_id is not visible to your user!",
       #           developer_message => 'only logged in users of certain roles can see this stock' . join(',' , @prop_roles),
       #           notify            => 0,   #< does not send an error email
       #     );

	$c->stash->{template} = "generic_message.mas";
	$c->stash->{message}  = "You do not have sufficient privileges to view the page of stock with database id $stock_id. You may need to log in to view this page.";
	return;
    }

    print STDERR "Checkpoint 3: Elapsed ".(time() - $time)."\n";

    # print message if the stock is obsolete
    my $obsolete = $stock->is_obsolete();
    if ( $obsolete  && !$curator ) {
        #$c->throw(is_client_error => 0,
        #          title             => 'Obsolete stock',
        #          message           => "Stock $stock_id is obsolete!",
        #          developer_message => 'only curators can see obsolete stock',
        #          notify            => 0,   #< does not send an error email
        #    );

	$c->stash->{template} = "generic_message.mas";
	$c->stash->{message}  = "The stock with database id $stock_id has been deleted. It can no longer be viewed.";
	return;
    }
    # print message if stock_id does not exist
    if ( !$stock && $action ne 'new' && $action ne 'store' ) {
        $c->throw_404('No stock exists for this identifier');
    }

    ####################
    my $is_owner;
    my $owner_ids = $c->stash->{owner_ids} || [] ;
    my $editor_info = $self->_stock_editor_info($stock);
    if ( $stock && ($curator || $person_id && ( grep /^$person_id$/, @$owner_ids ) ) ) {
        $is_owner = 1;
    }
    my $image_ids = $self->_stock_images($stock, $type);
    my $related_image_ids = $self->_related_stock_images($stock, $type);
    my $cview_tmp_dir = $c->tempfiles_subdir('cview');

    my $editable_stockprops = $c->get_conf('editable_stock_props');
    $editable_stockprops .= ",PUI,organization";
    if ($c->stash->{stock_row} && $c->stash->{stock_row}->type && $c->stash->{stock_row}->type->name() ne 'accession') {
        $editable_stockprops .= ",row_number,col_number,plot number,block,replicate,range,is a control,plant_index_number,subplot_index_number,tissue_sample_index_number,tissue_type";
    }

    print STDERR "Checkpoint 4: Elapsed ".(time() - $time)."\n";
################
    $c->stash(
        template => '/stock/index.mas',
        stockref => {
            stock_id  => $stock_id ,
            user      => $user_role,
            curator   => $curator,
            submitter => $submitter,
            sequencer => $sequencer,
            person_id => $person_id,
            stock     => $stock,
            schema    => $self->schema,
            dbh       => $dbh,
            is_owner  => $is_owner,
            owners    => $owner_ids,
            editor_info => $editor_info,
            props     => $props,
            members_phenotypes => $c->stash->{members_phenotypes},
            direct_phenotypes  => $c->stash->{direct_phenotypes},
            has_qtl_data   => $c->stash->{has_qtl_data},
            cview_tmp_dir  => $cview_tmp_dir,
            cview_basepath => $c->get_conf('basepath'),
            image_ids      => $image_ids,
            related_image_ids => $related_image_ids,
            allele_count   => $c->stash->{allele_count},
            has_pedigree => $c->stash->{has_pedigree},
            editable_stock_props   => $editable_stockprops,
        },
        identifier_prefix => $c->config->{identifier_prefix},
    );
}


=head2 view_by_organism_name

Public Path: /stock/view_by_organism/$organism/$name
Path Params:
    organism = organism name (abbreviation, genus, species, common name)
    name = stock unique name

Search for stock(s) matching the organism query and the stock unique name.
If 1 match is found, display the stock detail page.  Display an error for
0 matches and a list of matches when multiple stocks are found.

=cut

sub view_by_organism_name : Path('/stock/view_by_organism') Args(2) {
    my ($self, $c, $organism_query, $stock_query) = @_;
    $self->search_stock($c, $organism_query, $stock_query);
}


=head2 view_by_name

Public Path: /stock/view_by_name/$name
Path Params:
    name = stock unique name

Search for stock(s) matching the stock unique name.
If 1 match is found, display the stock detail page.  Display an error for
0 matches and a list of matches when multiple stocks are found.

=cut

sub view_by_name : Path('/stock/view_by_name') Args(1) {
    my ($self, $c, $stock_query) = @_;
    $self->search_stock($c, undef, $stock_query);
}


=head1 PRIVATE ACTIONS

=head2 download_phenotypes

=cut


sub download_phenotypes : Chained('get_stock') PathPart('phenotypes') Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");

    my $sgn_session_id = $c->req->param("sgn_session_id");
    my $user = $c->user();
    if (!$user && !$sgn_session_id) {
        $c->res->redirect( uri( path => '/user/login', query => { goto_url => $c->req->uri->path_query } ) );
        return;
    } elsif (!$user && $sgn_session_id) {
        my $login = CXGN::Login->new($schema->storage->dbh);
        my $logged_in = $login->query_from_cookie($sgn_session_id);
        if (!$logged_in){
            $c->res->redirect( uri( path => '/user/login', query => { goto_url => $c->req->uri->path_query } ) );
            return;
        }
    }

    my $stock = $c->stash->{stock_row};
    my $stock_id = $stock->stock_id;
    if ($stock_id) {
        #my $tmp_dir = $c->get_conf('basepath') . "/" . $c->get_conf('stock_tempfiles');
        #my $file_cache = Cache::File->new( cache_root => $tmp_dir  );
        #$file_cache->purge();
        #my $key = "stock_" . $stock_id . "_phenotype_data";
        #my $phen_file = $file_cache->get($key);
        #my $filename = $tmp_dir . "/stock_" . $stock_id . "_phenotypes.csv";

	my $results = [];# listref for recursive subject stock_phenotypes resultsets
	#recursively get the stock_id and the ids of its subjects from stock_relationship
	my $stock_rs = $self->schema->resultset("Stock::Stock")->search( { stock_id => $stock_id } );
	$results =  $self->schema->resultset("Stock::Stock")->recursive_phenotypes_rs($stock_rs, $results);
	my $report = Bio::Chado::NaturalDiversity::Reports->new;
	my $d = $report->phenotypes_by_trait($results);

	my @info  = split(/\n/ , $d);
	my @data;
	foreach (@info) {
	    push @data, [ split(/\t/) ] ;
	}
        $c->stash->{'csv'}={ data => \@data};
        $c->forward("View::Download::CSV");
        #stock    repeat	experiment	year	SP:0001	SP:0002
    }
}


=head2 download_genotypes

=cut


sub download_genotypes : Chained('get_stock') PathPart('genotypes') Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");

    my $sgn_session_id = $c->req->param("sgn_session_id");
    my $user = $c->user();
    if (!$user && !$sgn_session_id) {
        $c->res->redirect( uri( path => '/user/login', query => { goto_url => $c->req->uri->path_query } ) );
        return;
    } elsif (!$user && $sgn_session_id) {
        my $login = CXGN::Login->new($schema->storage->dbh);
        my $logged_in = $login->query_from_cookie($sgn_session_id);
        if (!$logged_in){
            $c->res->redirect( uri( path => '/user/login', query => { goto_url => $c->req->uri->path_query } ) );
            return;
        }
    }

    my $stock_row = $c->stash->{stock_row};
    my $stock_id = $stock_row->stock_id;
    my $stock_name = $stock_row->uniquename;
    my $genotype_id = $c->req->param('genotype_id') ? [$c->req->param('genotype_id')] : undef;
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $dl_token = $c->req->param("gbs_download_token") || "no_token";
    my $dl_cookie = "download".$dl_token;

    my $stock = CXGN::Stock->new({schema => $schema, stock_id => $stock_id});
    my $stock_type = $stock->type();

    if ($stock_id) {
        my %genotype_download_factory = (
            bcs_schema=>$schema,
            people_schema=>$people_schema,
            cache_root_dir=>$c->config->{cache_file_path},
            markerprofile_id_list=>$genotype_id,
            #genotype_data_project_list=>$genotype_data_project_list,
            #marker_name_list=>['S80_265728', 'S80_265723'],
            #limit=>$limit,
            #offset=>$offset
        );

        if ($stock_type eq 'accession') {
            $genotype_download_factory{accession_list} = [$stock_id];
        }
        elsif ($stock_type eq 'tissue_sample') {
            $genotype_download_factory{tissue_sample_list} = [$stock_id];
        }

        my $geno = CXGN::Genotype::DownloadFactory->instantiate(
            'VCF',    #can be either 'VCF' or 'GenotypeMatrix'
            \%genotype_download_factory
        );
        my $file_handle = $geno->download(
            $c->config->{cluster_shared_tempdir},
            $c->config->{backend},
            $c->config->{cluster_host},
            $c->config->{'web_cluster_queue'},
            $c->config->{basepath}
        );

        $c->res->content_type("application/text");
        $c->res->cookies->{$dl_cookie} = {
            value => $dl_token,
            expires => '+1m',
        };
        $c->res->header('Content-Disposition', qq[attachment; filename="BreedBaseGenotypesDownload.vcf"]);
        $c->res->body($file_handle);
    }
}

sub chr_sort {
    no warnings 'uninitialized';
    my @a = split "\t", $a;
    my @b = split "\t", $b;

    my $a_chr;
    my $a_coord;
    my $b_chr;
    my $b_coord;

    if ($a[1] =~ /^[A-Za-z]+(\d+)[_-](\d+)$/) {
	$a_chr = $1;
	$a_coord = $2;
    }

    if ($b[1] =~ /[A-Za-z]+(\d+)[_-](\d+)/) {
	$b_chr = $1;
	$b_coord = $2;
    }

    if ($a_chr eq $b_chr) {
	return $a_coord <=> $b_coord;
    }
    else {
	return $a_chr <=> $b_chr;
    }
}

=head2 get_stock

Chain root for fetching a stock object to operate on.

Path part: /stock/<stock_id>

=cut

sub get_stock : Chained('/')  PathPart('stock')  CaptureArgs(1) {
    my ($self, $c, $stock_id) = @_;

    $c->stash->{stock_id}  = $stock_id;
    $c->stash->{stock}     = CXGN::Stock->new({schema=>$self->schema, stock_id=>$stock_id});
    $c->stash->{stock_row} = $self->schema->resultset('Stock::Stock')
                                  ->find({ stock_id => $stock_id });
}

# Search for stock by organism name (optional) and uniquename
# Display stock detail page for 1 match, error messages for 0 or multiple matches
sub search_stock : Private {
    my ( $self, $c, $organism_query, $stock_query ) = @_;
    my $rs = $self->schema->resultset('Stock::Stock');

    my $matches;
    my $count = 0;

    # Search by name and organism
    if ( defined($organism_query) && defined($stock_query) ) {
        $matches = $rs->search({
                'UPPER(uniquename)' => uc($stock_query),
                -or => [
                    'UPPER(organism.abbreviation)' => uc($organism_query),
                    'UPPER(organism.genus)' => uc($organism_query),
                    'UPPER(organism.species)' => uc($organism_query),
                    'UPPER(organism.common_name)' => {'like', '%' . uc($organism_query) .'%'}
                ],
                is_obsolete => 'false'
            },
            {join => 'organism'}
        );
        $count = $matches->count;
    }

    # Search by name
    elsif ( defined($stock_query) ) {
        $matches = $rs->search({
                'UPPER(uniquename)' => uc($stock_query),
                is_obsolete => 'false'
            },
            {join => 'organism'}
        );
        $count = $matches->count;
    }


    # NO MATCH FOUND
    if ( $count == 0 ) {
        $c->stash->{template} = "generic_message.mas";
        $c->stash->{message} = "<strong>No Matching Stock Found</strong> ($stock_query $organism_query)<br />You can view and search for stocks from the <a href='/search/stocks'>Stock Search Page</a>";
    }

    # MULTIPLE MATCHES FOUND
    elsif ( $count > 1 ) {
        my $list = "<ul>";
        while (my $stock = $matches->next) {
            my $stock_id = $stock->stock_id;
            my $stock_name = $stock->uniquename;
            my $species_name = $stock->organism->species;
            my $url = "/stock/$stock_id/view";
            $list.="<li><a href='$url'>$stock_name ($species_name)</li>";
        }
        $list.="</ul>";
        $c->stash->{template} = "generic_message.mas";
        $c->stash->{message} = "<strong>Multiple Stocks Found</strong><br />" . $list;
    }

    # 1 MATCH FOUND - FORWARD TO VIEW STOCK
    else {
        my $stock_id = $matches->first->stock_id;
        $c->stash->{stock}     = CXGN::Chado::Stock->new($self->schema, $stock_id);
        $c->stash->{stock_row} = $self->schema->resultset('Stock::Stock')
                                  ->find({ stock_id => $stock_id });
        $c->forward('view_stock');
    }
}

sub get_stock_owner_ids : Private {
    my ( $self, $c ) = @_;
    my $stock = $c->stash->{stock_row};
    my $owner_ids = $stock ? $self->_stock_owner_ids($stock) : undef;
    $c->stash->{owner_ids} = $owner_ids;
}

sub get_stock_has_pedigree : Private {
    my ( $self, $c ) = @_;
    my $stock = $c->stash->{stock_row};
    my $has_pedigree = $stock ? $self->_stock_has_pedigree($stock) : undef;
    $c->stash->{has_pedigree} = $has_pedigree;
}

sub get_stock_extended_info : Private {
    my ( $self, $c ) = @_;
    $c->forward('get_stock_owner_ids');
    $c->forward('get_stock_has_pedigree');
}

############## HELPER METHODS ######################3

sub _stockprops {
    my ($self,$bcs_stock) = @_;

    my $properties ;
    if ($bcs_stock) {
        my $stockprops = $bcs_stock->search_related("stockprops");
        while ( my $prop =  $stockprops->next ) {
            push @{ $properties->{$prop->type->name} } ,   $prop->value ;
        }
    }
    return $properties;
}


sub _stock_images {
    my ($self, $stock) = @_;
    my @ids;
    my $q = "select distinct image_id, cvterm.name, stock_image.display_order FROM phenome.stock_image JOIN stock USING(stock_id) JOIN cvterm ON(type_id=cvterm_id) WHERE stock_id = ? ORDER BY stock_image.display_order ASC";
    my $h = $self->schema->storage->dbh()->prepare($q);
    $h->execute($stock->stock_id);
    while (my ($image_id, $stock_type) = $h->fetchrow_array()){
        push @ids, [$image_id, $stock_type];
    }
    return \@ids;
}

sub _related_stock_images {
    my ($self, $stock) = @_;
    my @ids;
    my $q = "select distinct image_id, cvterm.name FROM phenome.stock_image JOIN stock USING(stock_id) JOIN cvterm ON(type_id=cvterm_id) WHERE stock_id IN (SELECT subject_id FROM stock_relationship WHERE object_id = ? ) OR stock_id IN (SELECT object_id FROM stock_relationship WHERE subject_id = ? )";
    my $h = $self->schema->storage->dbh()->prepare($q);
    $h->execute($stock->stock_id, $stock->stock_id);
    while (my ($image_id, $stock_type) = $h->fetchrow_array()){
        push @ids, [$image_id, $stock_type];
    }
    return \@ids;
}

sub _stock_owner_ids {
    my ($self,$stock) = @_;
    my $ids = $self->schema->storage->dbh->selectcol_arrayref
        ("SELECT sp_person_id FROM phenome.stock_owner WHERE stock_id = ? ",
         undef,
         $stock->stock_id
        );
    return $ids;
}

sub _stock_editor_info {
    my ($self,$stock) = @_;
    my @owner_info;
    my $q = "SELECT sp_person_id, md_metadata.create_date, md_metadata.modification_note FROM phenome.stock_owner JOIN metadata.md_metadata USING(metadata_id) WHERE stock_id = ? ";
    my $h = $self->schema->storage->dbh()->prepare($q);
    $h->execute($stock->stock_id);
    while (my ($sp_person_id, $timestamp, $modification_note) = $h->fetchrow_array){
        push @owner_info, [$sp_person_id, $timestamp, $modification_note];
    }
    return \@owner_info;
}

sub _stock_has_pedigree {
  my ($self, $bcs_stock) = @_;
  my $cvterm_female_parent = SGN::Model::Cvterm->get_cvterm_row($self->schema, 'female_parent', 'stock_relationship');

  my $cvterm_male_parent = SGN::Model::Cvterm->get_cvterm_row($self->schema, 'male_parent', 'stock_relationship');

  my $stock_relationships = $bcs_stock->search_related("stock_relationship_objects",undef,{ prefetch => ['type','subject'] });
  my $female_parent_relationship = $stock_relationships->find({type_id => $cvterm_female_parent->cvterm_id()});
  my $male_parent_relationship = $stock_relationships->find({type_id => $cvterm_male_parent->cvterm_id()});
  if ($female_parent_relationship || $male_parent_relationship) {
    return 1;
  } else {
    return 0;
  }
}


sub _validate_pair {
    my ($self,$c,$key,$value) = @_;
    $c->throw( is_client_error => 1, public_message => "$value is not a valid value for $key" )
        if ($key =~ m/_id$/ and $value !~ m/\d+/);
}




__PACKAGE__->meta->make_immutable;
