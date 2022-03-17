package CXGN::Genotype::GRM;

=head1 NAME

CXGN::Genotype::GRM - an object to handle fetching a GRM for stocks

=head1 USAGE

my $geno = CXGN::Genotype::GRM->new({
    bcs_schema=>$schema,
    grm_temp_file=>$file_temp_path,
    people_schema=>$people_schema,
    accession_id_list=>\@accession_list,
    plot_id_list=>\@plot_id_list,
    protocol_id=>$protocol_id,
    get_grm_for_parental_accessions=>1,
    cache_root=>$cache_root,
    download_format=>'matrix', #either 'matrix', 'three_column', or 'heatmap'
    minor_allele_frequency=>0.01,
    marker_filter=>0.6,
    individuals_filter=>0.8,
});
RECOMMENDED
$geno->download_grm();

OR

my $grm = $geno->get_grm();

=head1 DESCRIPTION


=head1 AUTHORS

 Nicolas Morales <nm529@cornell.edu>

=cut

use strict;
use warnings;
use Moose;
use Try::Tiny;
use Data::Dumper;
use SGN::Model::Cvterm;
use CXGN::Trial;
use JSON;
use CXGN::Stock::Accession;
use CXGN::Genotype::Protocol;
use CXGN::Genotype::Search;
use CXGN::Genotype::ComputeHybridGenotype;
use R::YapRI::Base;
use R::YapRI::Data::Matrix;
use CXGN::Dataset::Cache;
use Cache::File;
use Digest::MD5 qw | md5_hex |;
use File::Slurp qw | write_file |;
use POSIX;
use File::Copy;
use CXGN::Tools::Run;
use File::Temp 'tempfile';

has 'bcs_schema' => (
    isa => 'Bio::Chado::Schema',
    is => 'rw',
    required => 1
);

has 'people_schema' => (
    isa => 'CXGN::People::Schema',
    is => 'rw',
    required => 1
);

# Uses a cached file system for getting genotype results and getting GRM
has 'cache_root' => (
    isa => 'Str',
    is => 'rw',
    required => 1
);

has 'download_format' => (
    isa => 'Str',
    is => 'rw',
    required => 1
);

has 'cache' => (
    isa => 'Cache::File',
    is => 'rw',
);

has 'cache_expiry' => (
    isa => 'Int',
    is => 'rw',
    default => 0, # never expires?
);

has '_cache_key' => (
    isa => 'Str',
    is => 'rw',
);

has 'grm_temp_file' => (
    isa => 'Str',
    is => 'rw',
    required => 1
);

has 'protocol_id' => (
    isa => 'Int|Undef',
    is => 'rw',
);

has 'minor_allele_frequency' => (
    isa => 'Num',
    is => 'rw',
    default => sub{0.05}
);

has 'marker_filter' => (
    isa => 'Num',
    is => 'rw',
    default => sub{0.60}
);

has 'individuals_filter' => (
    isa => 'Num',
    is => 'rw',
    default => sub{0.80}
);

has 'return_imputed_matrix' => (
    isa => 'Bool',
    is => 'ro',
    default => 0
);

has 'return_inverse' => (
    isa => 'Bool',
    is => 'ro',
    default => 0
);

has 'ensure_positive_definite' => (
    isa => 'Bool',
    is => 'ro',
    default => 1
);

has 'accession_id_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw'
);

has 'plot_id_list' => (
    isa => 'ArrayRef[Int]|Undef',
    is => 'rw'
);

# If the accessions in the plots you are interested have not been genotyped (as in hybrids), can get this boolean to 1 and give a list of plot_id_list and you will get back a GRM built from the parent accessions for those plots (for the plots whose parents were genotyped)
has 'get_grm_for_parental_accessions' => (
    isa => 'Bool',
    is => 'ro',
    default => 0
);

has 'genotypeprop_hash_select' => (
    isa => 'ArrayRef[Str]',
    is => 'ro',
    default => sub {['DS']} #THESE ARE THE GENERIC AND EXPECTED VCF ATRRIBUTES. For dosage matrix we only need DS
);

has 'protocolprop_top_key_select' => (
    isa => 'ArrayRef[Str]',
    is => 'ro',
    default => sub {['markers']} #THESE ARE ALL POSSIBLE TOP LEVEL KEYS IN PROTOCOLPROP BASED ON VCF LOADING. For dosage matrix we only need markers
);

has 'protocolprop_marker_hash_select' => (
    isa => 'ArrayRef[Str]',
    is => 'ro',
    default => sub {['name']} #THESE ARE ALL POSSIBLE PROTOCOLPROP MARKER HASH KEYS BASED ON VCF LOADING. For dosage matrix we only need name
);

has 'return_only_first_genotypeprop_for_stock' => (
    isa => 'Bool',
    is => 'ro',
    default => 1
);

sub _get_grm {
    my $self = shift;
    my $shared_cluster_dir_config = shift;
    my $backend_config = shift;
    my $cluster_host_config = shift;
    my $web_cluster_queue_config = shift;
    my $basepath_config = shift;
    my $schema = $self->bcs_schema();
    my $people_schema = $self->people_schema();
    my $cache_root_dir = $self->cache_root();
    my $accession_list = $self->accession_id_list();
    my $plot_list = $self->plot_id_list();
    my $protocol_id = $self->protocol_id();
    my $get_grm_for_parental_accessions = $self->get_grm_for_parental_accessions();
    my $grm_tempfile = $self->grm_temp_file();
    my $return_inverse = $self->return_inverse();
    my $ensure_positive_definite = $self->ensure_positive_definite();
    my $return_imputed_matrix = $self->return_imputed_matrix();

    my $accession_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'accession', 'stock_type')->cvterm_id();
    my $plot_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot', 'stock_type')->cvterm_id();
    my $plot_of_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot_of', 'stock_relationship')->cvterm_id();
    my $female_parent_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'female_parent', 'stock_relationship')->cvterm_id();
    my $male_parent_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'male_parent', 'stock_relationship')->cvterm_id();
    my $genomic_relatedness_dosage_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'genomic_relatedness_dosage', 'stock_relatedness')->cvterm_id();

    my $number_system_cores = `getconf _NPROCESSORS_ONLN` or die "Could not get number of system cores!\n";
    chomp($number_system_cores);
    print STDERR "NUMCORES $number_system_cores\n";

    my $tmp_output_dir = $shared_cluster_dir_config."/tmp_genotype_download_grm";
    mkdir $tmp_output_dir if ! -d $tmp_output_dir;
    my ($grm_tempfile_out_fh, $grm_tempfile_out) = tempfile("download_grm_out_XXXXX", DIR=> $tmp_output_dir);
    my ($grm_imputed_tempfile_out_fh, $grm_imputed_tempfile_out) = tempfile("download_grm_out_XXXXX", DIR=> $tmp_output_dir);
    my ($temp_out_file_fh, $temp_out_file) = tempfile("download_grm_tmp_XXXXX", DIR=> $tmp_output_dir);

    my @individuals_stock_ids;
    my @all_individual_accessions_stock_ids;
    my %seen_accession_stock_ids_relatedness;
    my %missing_stock_ids_relatedness;
    my %missing_stock_ids_all_relatedness;

    my $genomic_relatedness_dosage_q = "SELECT value FROM stock_relatedness WHERE a_stock_id=? AND b_stock_id=? AND type_id=? AND nd_protocol_id=?;";
    my $genomic_relatedness_dosage_h = $schema->storage->dbh->prepare($genomic_relatedness_dosage_q);

    if ($protocol_id) {
        my $protocol = CXGN::Genotype::Protocol->new({
            bcs_schema => $schema,
            nd_protocol_id => $protocol_id
        });
        my $markers = $protocol->markers;
        my @all_marker_objects = values %$markers;

        no warnings 'uninitialized';
        @all_marker_objects = sort { $a->{chrom} <=> $b->{chrom} || $a->{pos} <=> $b->{pos} || $a->{name} cmp $b->{name} } @all_marker_objects;

        # In this case a list of accessions is given, so get a GRM between these accessions
        if ($accession_list && scalar(@$accession_list)>0 && !$get_grm_for_parental_accessions){
            print STDERR "COMPUTING GENOTYPE FOR ACCESSIONS\n";

            @all_individual_accessions_stock_ids = sort {$a <=> $b} @$accession_list;

            #stock_relatedness is stored in both a,b directions, so only need to query this combo one way
            foreach my $a (@all_individual_accessions_stock_ids) {
                foreach my $b (@all_individual_accessions_stock_ids) {
                    $genomic_relatedness_dosage_h->execute($a, $b, $genomic_relatedness_dosage_cvterm_id, $protocol_id);
                    my ($value) = $genomic_relatedness_dosage_h->fetchrow_array();
                    if (defined($value)) {
                        $seen_accession_stock_ids_relatedness{$a}->{$b} = $value;
                    }
                    else {
                        $missing_stock_ids_relatedness{$a}->{$b}++;
                        $missing_stock_ids_all_relatedness{$a}++;
                        $missing_stock_ids_all_relatedness{$b}++;
                    }
                }
            }

            my @missing_accession_ids = sort keys %missing_stock_ids_all_relatedness;
            my $genotypes_search = CXGN::Genotype::Search->new(
                bcs_schema => $schema,
                people_schema=> $people_schema,
                accession_list => \@missing_accession_ids,
                protocol_id_list => [$protocol_id],
            );
            my ($geno_info, $seen_protocol_hash) = $genotypes_search->check_which_have_genotypes();
            # print STDERR Dumper $geno_info;

            my %missing_have_genotypes_accession_ids;
            foreach (@$geno_info) {
                my $accession_id = $_->{germplasmDbId};
                $missing_have_genotypes_accession_ids{$accession_id}++;
            }

            my %missing_no_genotypes_accession_ids;
            foreach (@missing_accession_ids) {
                if (!exists($missing_have_genotypes_accession_ids{$_})) {
                    $missing_no_genotypes_accession_ids{$_}++;
                }
            }

            my %accessions_get_genotypes;
            foreach my $a (sort keys %missing_stock_ids_relatedness) {
                foreach my $b (sort keys %{$missing_stock_ids_relatedness{$a}}) {
                    if (exists($missing_have_genotypes_accession_ids{$a}) && exists($missing_have_genotypes_accession_ids{$b})) {
                        $accessions_get_genotypes{$a}++;
                        $accessions_get_genotypes{$b}++;
                    }
                }
            }

            foreach (@all_individual_accessions_stock_ids) {
                if (exists($accessions_get_genotypes{$_})) {

                    my $dataset = CXGN::Dataset::Cache->new({
                        people_schema=>$people_schema,
                        schema=>$schema,
                        cache_root=>$cache_root_dir,
                        accessions=>[$_]
                    });
                    my $genotypes = $dataset->retrieve_genotypes($protocol_id, ['DS'], ['markers'], ['name'], 1, [], undef, undef, []);

                    if (scalar(@$genotypes)>0) {
                        my $p1_markers = $genotypes->[0]->{selected_protocol_hash}->{markers};

                        # For old genotyping protocols without nd_protocolprop info...
                        if (scalar(@all_marker_objects) == 0) {
                            foreach my $o (sort genosort keys %{$genotypes->[0]->{selected_genotype_hash}}) {
                                push @all_marker_objects, {name => $o};
                            }
                        }

                        foreach my $p (0..scalar(@$genotypes)-1) {
                            my $stock_id = $genotypes->[$p]->{stock_id};
                            my $genotype_string = "";
                            my @row;
                            foreach my $m (@all_marker_objects) {
                                push @row, $genotypes->[$p]->{selected_genotype_hash}->{$m->{name}}->{DS};
                            }
                            my $genotype_string_scores = join "\t", @row;
                            $genotype_string .= $genotype_string_scores . "\n";
                            push @individuals_stock_ids, $stock_id;
                            write_file($grm_tempfile, {append => 1}, $genotype_string);
                            undef $genotypes->[$p];
                        }
                        undef $genotypes;
                    }
                }
            }
        }
        # IN this case of a hybrid evaluation where the parents of the accessions planted in a plot are genotyped
        elsif ($get_grm_for_parental_accessions && $plot_list && scalar(@$plot_list)>0) {
            print STDERR "COMPUTING GENOTYPE FROM PARENTS FOR PLOTS\n";

            my $plot_list_string = join ',', @$plot_list;
            my $q = "SELECT plot.stock_id, accession.stock_id, female_parent.stock_id, male_parent.stock_id
                FROM stock AS plot
                JOIN stock_relationship AS plot_acc_rel ON(plot_acc_rel.subject_id=plot.stock_id AND plot_acc_rel.type_id=$plot_of_cvterm_id)
                JOIN stock AS accession ON(plot_acc_rel.object_id=accession.stock_id AND accession.type_id=$accession_cvterm_id)
                JOIN stock_relationship AS female_parent_rel ON(accession.stock_id=female_parent_rel.object_id AND female_parent_rel.type_id=$female_parent_cvterm_id)
                JOIN stock AS female_parent ON(female_parent_rel.subject_id = female_parent.stock_id AND female_parent.type_id=$accession_cvterm_id)
                JOIN stock_relationship AS male_parent_rel ON(accession.stock_id=male_parent_rel.object_id AND male_parent_rel.type_id=$male_parent_cvterm_id)
                JOIN stock AS male_parent ON(male_parent_rel.subject_id = male_parent.stock_id AND male_parent.type_id=$accession_cvterm_id)
                WHERE plot.type_id=$plot_cvterm_id AND plot.stock_id IN ($plot_list_string)
                ORDER BY accession.stock_id ASC;";
            my $h = $schema->storage->dbh()->prepare($q);
            $h->execute();
            my @plot_stock_ids_found = ();
            my @plot_accession_stock_ids_found = ();
            my @plot_female_stock_ids_found = ();
            my @plot_male_stock_ids_found = ();
            while (my ($plot_stock_id, $accession_stock_id, $female_parent_stock_id, $male_parent_stock_id) = $h->fetchrow_array()) {
                push @plot_stock_ids_found, $plot_stock_id;
                push @plot_accession_stock_ids_found, $accession_stock_id;
                push @plot_female_stock_ids_found, $female_parent_stock_id;
                push @plot_male_stock_ids_found, $male_parent_stock_id;
            }

            my %unique_accession_ids;
            my $q1 = "SELECT plot.stock_id, accession.stock_id
                FROM stock AS plot
                JOIN stock_relationship AS plot_acc_rel ON(plot_acc_rel.subject_id=plot.stock_id AND plot_acc_rel.type_id=$plot_of_cvterm_id)
                JOIN stock AS accession ON(plot_acc_rel.object_id=accession.stock_id AND accession.type_id=$accession_cvterm_id)
                WHERE plot.type_id=$plot_cvterm_id AND plot.stock_id IN ($plot_list_string);";
            my $h1 = $schema->storage->dbh()->prepare($q1);
            $h1->execute();
            while (my ($plot_stock_id, $accession_stock_id) = $h1->fetchrow_array()) {
                $unique_accession_ids{$accession_stock_id}++;
            }

            @all_individual_accessions_stock_ids = sort {$a <=> $b} keys %unique_accession_ids;

            #stock_relatedness is stored in both a,b directions, so only need to query this combo one way
            foreach my $a (@all_individual_accessions_stock_ids) {
                foreach my $b (@all_individual_accessions_stock_ids) {
                    $genomic_relatedness_dosage_h->execute($a, $b, $genomic_relatedness_dosage_cvterm_id, $protocol_id);
                    my ($value) = $genomic_relatedness_dosage_h->fetchrow_array();
                    if (defined($value)) {
                        $seen_accession_stock_ids_relatedness{$a}->{$b} = $value;
                    }
                    else {
                        $missing_stock_ids_relatedness{$a}->{$b}++;
                        $missing_stock_ids_all_relatedness{$a}++;
                        $missing_stock_ids_all_relatedness{$b}++;
                    }
                }
            }

            my @missing_accession_ids = sort keys %missing_stock_ids_all_relatedness;
            my $genotypes_search = CXGN::Genotype::Search->new(
                bcs_schema => $schema,
                people_schema=> $people_schema,
                accession_list => \@missing_accession_ids,
                protocol_id_list => [$protocol_id],
            );
            my ($geno_info, $seen_protocol_hash) = $genotypes_search->check_which_have_genotypes();
            # print STDERR Dumper $geno_info;

            my %missing_have_genotypes_accession_ids;
            foreach (@$geno_info) {
                my $accession_id = $_->{germplasmDbId};
                $missing_have_genotypes_accession_ids{$accession_id}++;
            }

            my %missing_no_genotypes_accession_ids;
            foreach (@missing_accession_ids) {
                if (!exists($missing_have_genotypes_accession_ids{$_})) {
                    $missing_no_genotypes_accession_ids{$_}++;
                }
            }

            my %accessions_get_genotypes;
            foreach my $a (sort keys %missing_stock_ids_relatedness) {
                foreach my $b (sort keys %{$missing_stock_ids_relatedness{$a}}) {
                    if (exists($missing_have_genotypes_accession_ids{$a}) && exists($missing_have_genotypes_accession_ids{$b})) {
                        $accessions_get_genotypes{$a}++;
                        $accessions_get_genotypes{$b}++;
                    }
                }
            }

            my %already_included_accession_ids;
            for my $i (0..scalar(@plot_stock_ids_found)-1) {
                my $female_stock_id = $plot_female_stock_ids_found[$i];
                my $male_stock_id = $plot_male_stock_ids_found[$i];
                my $plot_stock_id = $plot_stock_ids_found[$i];
                my $accession_id = $plot_accession_stock_ids_found[$i];

                if (!exists($already_included_accession_ids{$accession_id}) && exists($accessions_get_genotypes{$accession_id}) ) {

                    my $dataset = CXGN::Dataset::Cache->new({
                        people_schema=>$people_schema,
                        schema=>$schema,
                        cache_root=>$cache_root_dir,
                        accessions=>[$female_stock_id, $male_stock_id]
                    });
                    my $genotypes = $dataset->retrieve_genotypes($protocol_id, ['DS'], ['markers'], ['name'], 1, [], undef, undef, []);

                    if (scalar(@$genotypes) > 0) {
                        # For old genotyping protocols without nd_protocolprop info...
                        if (scalar(@all_marker_objects) == 0) {
                            foreach my $o (sort genosort keys %{$genotypes->[0]->{selected_genotype_hash}}) {
                                push @all_marker_objects, {name => $o};
                            }
                        }

                        my $genotype_string = "";
                        my $geno = CXGN::Genotype::ComputeHybridGenotype->new({
                            parental_genotypes=>$genotypes,
                            marker_objects=>\@all_marker_objects
                        });
                        my $progeny_genotype = $geno->get_hybrid_genotype();

                        push @individuals_stock_ids, $accession_id;
                        my $genotype_string_scores = join "\t", @$progeny_genotype;
                        $genotype_string .= $genotype_string_scores . "\n";
                        write_file($grm_tempfile, {append => 1}, $genotype_string);
                        undef $progeny_genotype;
                    }

                    $already_included_accession_ids{$accession_id}++;
                }
            }

        }
        # IN this case of a hybrid evaluation where the parents of the accessions planted in a plot are genotyped
        elsif ($get_grm_for_parental_accessions && $accession_list && scalar(@$accession_list)>0) {
            print STDERR "COMPUTING GENOTYPE FROM PARENTS FOR ACCESSIONS\n";

            @all_individual_accessions_stock_ids = sort {$a <=> $b} @$accession_list;

            my $accession_list_string = join ',', @$accession_list;
            my $q = "SELECT accession.stock_id, female_parent.stock_id, male_parent.stock_id
                FROM stock AS accession
                JOIN stock_relationship AS female_parent_rel ON(accession.stock_id=female_parent_rel.object_id AND female_parent_rel.type_id=$female_parent_cvterm_id)
                JOIN stock AS female_parent ON(female_parent_rel.subject_id = female_parent.stock_id AND female_parent.type_id=$accession_cvterm_id)
                JOIN stock_relationship AS male_parent_rel ON(accession.stock_id=male_parent_rel.object_id AND male_parent_rel.type_id=$male_parent_cvterm_id)
                JOIN stock AS male_parent ON(male_parent_rel.subject_id = male_parent.stock_id AND male_parent.type_id=$accession_cvterm_id)
                WHERE accession.type_id=$accession_cvterm_id AND accession.stock_id IN ($accession_list_string)
                ORDER BY accession.stock_id ASC;";
            my $h = $schema->storage->dbh()->prepare($q);
            $h->execute();
            my @accession_stock_ids_found = ();
            my @female_stock_ids_found = ();
            my @male_stock_ids_found = ();
            my %accession_pedigree_hash;
            while (my ($accession_stock_id, $female_parent_stock_id, $male_parent_stock_id) = $h->fetchrow_array()) {
                push @accession_stock_ids_found, $accession_stock_id;
                push @female_stock_ids_found, $female_parent_stock_id;
                push @male_stock_ids_found, $male_parent_stock_id;

                $accession_pedigree_hash{$accession_stock_id} = {
                    female_id => $female_parent_stock_id,
                    male_id => $male_parent_stock_id
                };
            }

            #stock_relatedness is stored in both a,b directions, so only need to query this combo one way
            my %missing_all_parents_hash;
            foreach my $a (@all_individual_accessions_stock_ids) {
                foreach my $b (@all_individual_accessions_stock_ids) {
                    $genomic_relatedness_dosage_h->execute($a, $b, $genomic_relatedness_dosage_cvterm_id, $protocol_id);
                    my ($value) = $genomic_relatedness_dosage_h->fetchrow_array();
                    if (defined($value)) {
                        $seen_accession_stock_ids_relatedness{$a}->{$b} = $value;
                    }
                    else {
                        $missing_stock_ids_relatedness{$a}->{$b}++;
                        $missing_stock_ids_all_relatedness{$a}++;
                        $missing_stock_ids_all_relatedness{$b}++;
                        $missing_all_parents_hash{$accession_pedigree_hash{$a}->{female_id}}++;
                        $missing_all_parents_hash{$accession_pedigree_hash{$b}->{female_id}}++;
                        $missing_all_parents_hash{$accession_pedigree_hash{$a}->{male_id}}++;
                        $missing_all_parents_hash{$accession_pedigree_hash{$b}->{male_id}}++;
                    }
                }
            }

            my @all_missing_parents_ids = sort keys %missing_all_parents_hash;
            my $genotypes_search = CXGN::Genotype::Search->new(
                bcs_schema => $schema,
                people_schema=> $people_schema,
                accession_list => \@all_missing_parents_ids,
                protocol_id_list => [$protocol_id],
            );
            my ($geno_info, $seen_protocol_hash) = $genotypes_search->check_which_have_genotypes();
            # print STDERR Dumper $geno_info;

            my %missing_parents_have_genotypes_accession_ids;
            foreach (@$geno_info) {
                my $accession_id = $_->{germplasmDbId};
                $missing_parents_have_genotypes_accession_ids{$accession_id}++;
            }

            my @missing_accession_ids = sort keys %missing_stock_ids_all_relatedness;
            my %missing_no_genotypes_accession_ids;
            my %missing_have_genotypes_accession_ids;
            foreach (@missing_accession_ids) {
                my $female_id = $accession_pedigree_hash{$_}->{female_id};
                my $male_id = $accession_pedigree_hash{$_}->{male_id};
                if (!exists($missing_parents_have_genotypes_accession_ids{$female_id}) && !exists($missing_parents_have_genotypes_accession_ids{$male_id})) {
                    $missing_no_genotypes_accession_ids{$_}++;
                }
                else {
                    $missing_have_genotypes_accession_ids{$_}++;
                }
            }

            my %accessions_get_genotypes;
            foreach my $a (sort keys %missing_stock_ids_relatedness) {
                foreach my $b (sort keys %{$missing_stock_ids_relatedness{$a}}) {
                    if (exists($missing_have_genotypes_accession_ids{$a}) && exists($missing_have_genotypes_accession_ids{$b})) {
                        $accessions_get_genotypes{$a}++;
                        $accessions_get_genotypes{$b}++;
                    }
                }
            }

            for my $i (0..scalar(@accession_stock_ids_found)-1) {
                my $female_stock_id = $female_stock_ids_found[$i];
                my $male_stock_id = $male_stock_ids_found[$i];
                my $accession_stock_id = $accession_stock_ids_found[$i];

                if (exists($accessions_get_genotypes{$accession_stock_id})) {

                    my $dataset = CXGN::Dataset::Cache->new({
                        people_schema=>$people_schema,
                        schema=>$schema,
                        cache_root=>$cache_root_dir,
                        accessions=>[$female_stock_id, $male_stock_id]
                    });
                    my $genotypes = $dataset->retrieve_genotypes($protocol_id, ['DS'], ['markers'], ['name'], 1, [], undef, undef, []);

                    if (scalar(@$genotypes) > 0) {
                        # For old genotyping protocols without nd_protocolprop info...
                        if (scalar(@all_marker_objects) == 0) {
                            foreach my $o (sort genosort keys %{$genotypes->[0]->{selected_genotype_hash}}) {
                                push @all_marker_objects, {name => $o};
                            }
                        }

                        my $genotype_string = "";
                        my $geno = CXGN::Genotype::ComputeHybridGenotype->new({
                            parental_genotypes=>$genotypes,
                            marker_objects=>\@all_marker_objects
                        });
                        my $progeny_genotype = $geno->get_hybrid_genotype();

                        push @individuals_stock_ids, $accession_stock_id;
                        my $genotype_string_scores = join "\t", @$progeny_genotype;
                        $genotype_string .= $genotype_string_scores . "\n";
                        write_file($grm_tempfile, {append => 1}, $genotype_string);
                        undef $progeny_genotype;
                    }

                }
            }
        }

        # print STDERR Dumper \@all_marker_names;
        # print STDERR Dumper \@individuals_stock_ids;
        # print STDERR Dumper \@dosage_matrix;

        my $maf = $self->minor_allele_frequency();
        my $marker_filter = $self->marker_filter();
        my $individuals_filter = $self->individuals_filter();

        if (scalar(@individuals_stock_ids)>0) {
            my $cmd = 'R -e "library(genoDataFilter); library(rrBLUP); library(data.table); library(scales);
            mat <- fread(\''.$grm_tempfile.'\', header=FALSE, sep=\'\t\');
            range_check <- range(as.matrix(mat)[1,]);
            if (length(table(as.matrix(mat)[1,])) < 2 || (!is.na(range_check[1]) && !is.na(range_check[2]) && range_check[2] - range_check[1] <= 1 )) {
                mat <- as.data.frame(rescale(as.matrix(mat), to = c(-1,1), from = c(0,2) ));
            } else {
                mat <- as.data.frame(rescale(as.matrix(mat), to = c(-1,1) ));
            }
            ';
            #if (!$get_grm_for_parental_accessions) {
                #strange behavior in filterGenoData during testing... will use A.mat filters instead in this case...
            #    $cmd .= 'mat_clean <- filterGenoData(gData=mat, maf='.$maf.', markerFilter='.$marker_filter.', indFilter='.$individuals_filter.');
            #    A_matrix <- A.mat(mat_clean, impute.method=\'EM\', n.core='.$number_system_cores.', return.imputed=FALSE);
            #    ';
            #}
            #else {
            if (!$return_imputed_matrix) {
                $cmd .= 'A <- A.mat(mat, min.MAF='.$maf.', max.missing='.$marker_filter.', impute.method=\'mean\', n.core='.$number_system_cores.', return.imputed=FALSE);
                ';
            }
            else {
                $cmd .= 'A_list <- A.mat(mat, min.MAF='.$maf.', max.missing='.$marker_filter.', impute.method=\'mean\', n.core='.$number_system_cores.', return.imputed=TRUE);
                A <- A_list\$A;
                imputed <- A_list\$imputed;
                write.table(imputed, file=\''.$grm_imputed_tempfile_out.'\', row.names=TRUE, col.names=TRUE, sep=\'\t\');
                ';
            }
            #}
            if ($ensure_positive_definite) {
                # Ensure positive definite matrix. Taken from Schaeffer
                $cmd .= 'E = eigen(A);
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
                ';
            }
            if ($return_inverse) {
                $cmd .= 'A <- solve(A);';
            }
            $cmd .= 'write.table(A, file=\''.$grm_tempfile_out.'\', row.names=FALSE, col.names=FALSE, sep=\'\t\');"';
            print STDERR Dumper $cmd;

            # Do the GRM on the cluster
            my $grm_cmd = CXGN::Tools::Run->new(
                {
                    backend => $backend_config,
                    submit_host => $cluster_host_config,
                    temp_base => $tmp_output_dir,
                    queue => $web_cluster_queue_config,
                    do_cleanup => 0,
                    out_file => $temp_out_file,
                    # don't block and wait if the cluster looks full
                    max_cluster_jobs => 1_000_000_000,
                }
            );

            $grm_cmd->run_cluster($cmd);
            $grm_cmd->is_cluster(1);
            $grm_cmd->wait;
        }
    }
    else {
        print STDERR "No protocol, so giving equal relationship of all stocks!!\n";
        my $number_of_stocks = 0;
        if ($accession_list && scalar(@$accession_list)) {
            @$accession_list = sort {$a <=> $b} @$accession_list;
            $number_of_stocks = scalar(@$accession_list);
            @individuals_stock_ids = @$accession_list;
            @all_individual_accessions_stock_ids = @$accession_list;
        }
        elsif ($plot_list && scalar(@$plot_list)) {
            my $plot_list_string = join ',', @$plot_list;
            my $q = "SELECT plot.stock_id, accession.stock_id
                FROM stock AS plot
                JOIN stock_relationship AS plot_acc_rel ON(plot_acc_rel.subject_id=plot.stock_id AND plot_acc_rel.type_id=$plot_of_cvterm_id)
                JOIN stock AS accession ON(plot_acc_rel.object_id=accession.stock_id AND accession.type_id=$accession_cvterm_id)
                WHERE plot.type_id=$plot_cvterm_id AND plot.stock_id IN ($plot_list_string);";
            my $h = $schema->storage->dbh()->prepare($q);
            $h->execute();
            my %plot_accession_ids;
            while (my ($plot_stock_id, $accession_stock_id) = $h->fetchrow_array()) {
                $plot_accession_ids{$accession_stock_id}++;
            }
            my @seen_accession_ids = sort {$a <=> $b} keys %plot_accession_ids;
            $number_of_stocks = scalar(@seen_accession_ids);
            @individuals_stock_ids = @seen_accession_ids;
            @all_individual_accessions_stock_ids = @seen_accession_ids;
        }
        my $cmd .= 'R -e "
            A <- as.data.frame(diag('.$number_of_stocks.'));
            write.table(A, file=\''.$grm_tempfile_out.'\', row.names=FALSE, col.names=FALSE, sep=\'\t\');
        "';
        print STDERR Dumper $cmd;
        my $status = system($cmd);
    }

    return ($grm_tempfile_out, \@individuals_stock_ids, \@all_individual_accessions_stock_ids, \%seen_accession_stock_ids_relatedness);
}

sub grm_cache_key {
    my $self = shift;
    my $datatype = shift;

    #print STDERR Dumper($self->_get_dataref());
    my $json = JSON->new();
    #preserve order of hash keys to get same text
    $json = $json->canonical();
    my $sorted_accession_list = $self->accession_id_list() || [];
    my @sorted_accession_list = sort @$sorted_accession_list;
    my $accessions = $json->encode( \@sorted_accession_list );
    my $plots = $json->encode( $self->plot_id_list() || [] );
    my $protocol = $self->protocol_id() || '';
    my $genotypeprophash = $json->encode( $self->genotypeprop_hash_select() || [] );
    my $protocolprophash = $json->encode( $self->protocolprop_top_key_select() || [] );
    my $protocolpropmarkerhash = $json->encode( $self->protocolprop_marker_hash_select() || [] );
    my $maf = $self->minor_allele_frequency();
    my $marker_filter = $self->marker_filter();
    my $individuals_filter = $self->individuals_filter();
    my $q_params = $accessions.$plots.$protocol.$genotypeprophash.$protocolprophash.$protocolpropmarkerhash.$self->get_grm_for_parental_accessions().$self->return_only_first_genotypeprop_for_stock()."_MAF$maf"."_mfilter$marker_filter"."_ifilter$individuals_filter"."_$datatype";
    if ($self->return_inverse()) {
        $q_params .= $self->return_inverse();
    }
    if (!$self->ensure_positive_definite()) {
        $q_params .= $self->ensure_positive_definite();
    }
    my $key = md5_hex($q_params);
    return $key;
}

sub download_grm {
    my $self = shift;
    my $return_type = shift || 'filehandle';
    my $shared_cluster_dir_config = shift;
    my $backend_config = shift;
    my $cluster_host_config = shift;
    my $web_cluster_queue_config = shift;
    my $basepath_config = shift;
    my $schema = $self->bcs_schema();
    my $download_format = $self->download_format();
    my $return_imputed_matrix = $self->return_imputed_matrix();
    my $grm_tempfile = $self->grm_temp_file();
    my $protocol_id = $self->protocol_id();

    my $return_imputed_matrix_key = $return_imputed_matrix ? '_returnimputed' : '';

    my $key = $self->grm_cache_key("download_grm_v04".$download_format.$return_imputed_matrix_key);
    $self->_cache_key($key);
    $self->cache( Cache::File->new( cache_root => $self->cache_root() ));

    my $return;
    if ($self->cache()->exists($key)) {
        print STDERR "DOWNLOAD GRM CACHED\n";
        if ($return_type eq 'filehandle') {
            $return = $self->cache()->handle($key);
        }
        elsif ($return_type eq 'data') {
            $return = $self->cache()->get($key);
        }
    }
    else {
        print STDERR "DOWNLOAD GRM\n";
        my ($grm_tempfile_out, $stock_ids, $all_accession_stock_ids, $seen_accession_stock_ids_relatedness) = $self->_get_grm($shared_cluster_dir_config, $backend_config, $cluster_host_config, $web_cluster_queue_config, $basepath_config);
        # print STDERR Dumper $stock_ids;
        # print STDERR Dumper $all_accession_stock_ids;
        # print STDERR Dumper $seen_accession_stock_ids_relatedness;

        my $genomic_relatedness_dosage_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'genomic_relatedness_dosage', 'stock_relatedness')->cvterm_id();

        my $relatedness_fill_q = "INSERT INTO stock_relatedness (type_id, nd_protocol_id, a_stock_id, b_stock_id, value) VALUES ($genomic_relatedness_dosage_cvterm_id,$protocol_id,?,?,?);";
        my $relatedness_fill_h = $schema->storage->dbh->prepare($relatedness_fill_q);

        my %grm_hash;
        open(my $fh, "<", $grm_tempfile_out) or die "Can't open < $grm_tempfile_out: $!";
        my $row_num = 0;
        while (my $row = <$fh>) {
            chomp($row);
            my @vals = split "\t", $row;

            my $a_stock_id = $stock_ids->[$row_num];
            my $col_num = 0;
            foreach my $val (@vals) {
                my $b_stock_id = $stock_ids->[$col_num];
                $grm_hash{$a_stock_id}->{$b_stock_id} = $val;
                $grm_hash{$b_stock_id}->{$a_stock_id} = $val;
                $col_num++;
            }
            $row_num++;
        }

        foreach my $s (@$all_accession_stock_ids) {
            foreach my $c (@$all_accession_stock_ids) {
                if (!defined($seen_accession_stock_ids_relatedness->{$s}->{$c}) && $row_num>1 && defined($grm_hash{$s}->{$c})) {
                    my $val = $grm_hash{$s}->{$c};

                    if ($protocol_id) {
                        $relatedness_fill_h->execute($s, $c, $val);
                        $relatedness_fill_h->execute($c, $s, $val);
                    }
                }
            }
        }

        my $data = '';
        if ($download_format eq 'matrix') {
            my @header = ("stock_id");
            foreach (@$all_accession_stock_ids) {
                push @header, "S".$_;
            }

            my $header_line = join "\t", @header;
            $data = "$header_line\n";

            foreach my $s (@$all_accession_stock_ids) {
                my @row = ("S".$s);
                foreach my $c (@$all_accession_stock_ids) {
                    my $val;
                    if (defined($seen_accession_stock_ids_relatedness->{$s}->{$c})) {
                        $val = $seen_accession_stock_ids_relatedness->{$s}->{$c};
                    }
                    elsif ($row_num>1 && defined($grm_hash{$s}->{$c})) {
                        $val = $grm_hash{$s}->{$c};
                    }
                    elsif ($s == $c) {
                        $val = 1;
                    }
                    else {
                        $val = 0;
                    }

                    push @row, $val;
                }
                my $line = join "\t", @row;
                $data .= "$line\n";
            }

            $self->cache()->set($key, $data);
            if ($return_type eq 'filehandle') {
                $return = $self->cache()->handle($key);
            }
            elsif ($return_type eq 'data') {
                $return = $data;
            }
        }
        elsif ($download_format eq 'three_column') {
            my %result_hash;
            foreach my $s (@$all_accession_stock_ids) {
                foreach my $c (@$all_accession_stock_ids) {
                    if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                        my $val;
                        if (defined($seen_accession_stock_ids_relatedness->{$s}->{$c})) {
                            $val = $seen_accession_stock_ids_relatedness->{$s}->{$c};
                        }
                        elsif ($row_num>1 && defined($grm_hash{$s}->{$c})) {
                            $val = $grm_hash{$s}->{$c};
                        }
                        elsif ($s == $c) {
                            $val = 1;
                        }
                        else {
                            $val = 0;
                        }

                        $data .= "S$s\tS$c\t$val\n";
                        $result_hash{$s}->{$c} = $val;
                    }
                }
            }

            $self->cache()->set($key, $data);
            if ($return_type eq 'filehandle') {
                $return = $self->cache()->handle($key);
            }
            elsif ($return_type eq 'data') {
                $return = $data;
            }
        }
        elsif ($download_format eq 'three_column_stock_id_integer') {
            my %result_hash;
            foreach my $s (@$all_accession_stock_ids) {
                foreach my $c (@$all_accession_stock_ids) {
                    if (!exists($result_hash{$s}->{$c}) && !exists($result_hash{$c}->{$s})) {
                        my $val;
                        if (defined($seen_accession_stock_ids_relatedness->{$s}->{$c})) {
                            $val = $seen_accession_stock_ids_relatedness->{$s}->{$c};
                        }
                        elsif ($row_num>1 && defined($grm_hash{$s}->{$c})) {
                            $val = $grm_hash{$s}->{$c};
                        }
                        elsif ($s == $c) {
                            $val = 1;
                        }
                        else {
                            $val = 0;
                        }

                        $data .= "$s\t$c\t$val\n";
                        $result_hash{$s}->{$c} = $val;
                    }
                }
            }

            $self->cache()->set($key, $data);
            if ($return_type eq 'filehandle') {
                $return = $self->cache()->handle($key);
            }
            elsif ($return_type eq 'data') {
                $return = $data;
            }
        }
        elsif ($download_format eq 'three_column_reciprocal') {

            foreach my $s (@$all_accession_stock_ids) {
                foreach my $c (@$all_accession_stock_ids) {
                    my $val;
                    if (defined($seen_accession_stock_ids_relatedness->{$s}->{$c})) {
                        $val = $seen_accession_stock_ids_relatedness->{$s}->{$c};
                    }
                    elsif ($row_num>1 && defined($grm_hash{$s}->{$c})) {
                        $val = $grm_hash{$s}->{$c};
                    }
                    elsif ($s == $c) {
                        $val = 1;
                    }
                    else {
                        $val = 0;
                    }

                    $data .= "S$s\tS$c\t$val\n";
                }
            }

            $self->cache()->set($key, $data);
            if ($return_type eq 'filehandle') {
                $return = $self->cache()->handle($key);
            }
            elsif ($return_type eq 'data') {
                $return = $data;
            }
        }
        elsif ($download_format eq 'three_column_reciprocal_stock_id_integer') {
            foreach my $s (@$all_accession_stock_ids) {
                foreach my $c (@$all_accession_stock_ids) {
                    my $val;
                    if (defined($seen_accession_stock_ids_relatedness->{$s}->{$c})) {
                        $val = $seen_accession_stock_ids_relatedness->{$s}->{$c};
                    }
                    elsif ($row_num>1 && defined($grm_hash{$s}->{$c})) {
                        $val = $grm_hash{$s}->{$c};
                    }
                    elsif ($s == $c) {
                        $val = 1;
                    }
                    else {
                        $val = 0;
                    }

                    $data .= "$s\t$c\t$val\n";
                }
            }

            $self->cache()->set($key, $data);
            if ($return_type eq 'filehandle') {
                $return = $self->cache()->handle($key);
            }
            elsif ($return_type eq 'data') {
                $return = $data;
            }
        }
        elsif ($download_format eq 'heatmap') {
            foreach my $s (@$all_accession_stock_ids) {
                foreach my $c (@$all_accession_stock_ids) {
                    my $val;
                    if (defined($seen_accession_stock_ids_relatedness->{$s}->{$c})) {
                        $val = $seen_accession_stock_ids_relatedness->{$s}->{$c};
                    }
                    elsif ($row_num>1 && defined($grm_hash{$s}->{$c})) {
                        $val = $grm_hash{$s}->{$c};
                    }
                    elsif ($s == $c) {
                        $val = 1;
                    }
                    else {
                        $val = 0;
                    }

                    $data .= "S$s\tS$c\t$val\n";
                }
            }

            open(my $heatmap_fh, '>', $grm_tempfile) or die $!;
                print $heatmap_fh $data;
            close($heatmap_fh);

            my $grm_tempfile_out = $grm_tempfile . "_plot_out";
            my $heatmap_cmd = 'R -e "library(ggplot2); library(data.table); library(viridis); library(GGally); library(gridExtra);
            mat <- fread(\''.$grm_tempfile.'\', header=FALSE, sep=\'\t\', stringsAsFactors=FALSE);
            gg <- ggplot(mat, aes(V1, V2, fill=V3)) +
                geom_tile() +
                scale_fill_viridis(discrete=FALSE);
            ggsave(\''.$grm_tempfile_out.'\', gg, device=\'pdf\', width=8.5, height=11, units=\'in\');
            "';
            print STDERR Dumper $heatmap_cmd;
            my $status_heatmap = system($heatmap_cmd);

            # my $tmp_output_dir = $shared_cluster_dir_config."/tmp_genotype_download_grm_heatmap";
            # mkdir $tmp_output_dir if ! -d $tmp_output_dir;
            #
            # # Do the GRM on the cluster
            # my $plot_cmd = CXGN::Tools::Run->new(
            #     {
            #         backend => $backend_config,
            #         submit_host => $cluster_host_config,
            #         temp_base => $tmp_output_dir,
            #         queue => $web_cluster_queue_config,
            #         do_cleanup => 0,
            #         out_file => $grm_tempfile_out,
            #         # don't block and wait if the cluster looks full
            #         max_cluster_jobs => 1_000_000_000,
            #     }
            # );
            #
            # $plot_cmd->run_cluster($heatmap_cmd);
            # $plot_cmd->is_cluster(1);
            # $plot_cmd->wait;

            if ($return_type eq 'filehandle') {
                open my $out_copy, '<', $grm_tempfile_out or die "Can't open output file: $!";

                $self->cache()->set($key, '');
                my $file_handle = $self->cache()->handle($key);
                copy($out_copy, $file_handle);

                close $out_copy;
                $return = $self->cache()->handle($key);
            }
            elsif ($return_type eq 'data') {
                die "Can only return the filehandle for GRM heatmap!\n";
            }
        }
    }
    return $return;
}

sub genosort {
    my ($a_chr, $a_pos, $b_chr, $b_pos);
    if ($a =~ m/S(\d+)\_(.*)/) {
        $a_chr = $1;
        $a_pos = $2;
    }
    if ($b =~ m/S(\d+)\_(.*)/) {
        $b_chr = $1;
        $b_pos = $2;
    }

    if ($a_chr && $b_chr) {
        if ($a_chr == $b_chr) {
            return $a_pos <=> $b_pos;
        }
        return $a_chr <=> $b_chr;
    } else {
        return -1;
    }
}

1;
