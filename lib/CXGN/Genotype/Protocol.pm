package CXGN::Genotype::Protocol;

=head1 NAME

CXGN::Genotype::Protocol - an object to handle genotyping protocols (breeding data)

To get info for a specific protocol:

my $protocol = CXGN::Genotype::Protocol->new({
    bcs_schema => $schema,
    nd_protocol_id => $protocol_id
});
And then use Moose attributes to retrieve markers, refrence name, etc

----------------

To get a list of protocols and their info:
my $protocol_list = CXGN::Genotype::Protocol::list($schema); #INCLUDES MORE SEARCH PARAMS AND RETURN MARKER INFO
my $protocol_list = CXGN::Genotype::Protocol::list_simple($schema); #RETURNS ONLY MARKER COUNT
This can take search params in, like protocol_ids, accessions, etc

=head1 USAGE

=head1 DESCRIPTION


=head1 AUTHORS


=cut

use strict;
use warnings;
use Moose;
use Try::Tiny;
use Data::Dumper;
use SGN::Model::Cvterm;
use CXGN::Trial;
use JSON;
use CXGN::Tools::Run;

has 'bcs_schema' => (
    isa => 'Bio::Chado::Schema',
    is => 'rw',
    required => 1,
);

has 'nd_protocol_id' => (
    isa => 'Int',
    is => 'rw',
);

has 'protocol_name' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_id' => (
    isa => 'Int',
    is => 'rw',
);

has 'private_company_protocol_is_private' => (
    isa => 'Bool',
    is => 'rw',
);

has 'protocol_description' => (
    isa => 'Str|Undef',
    is => 'rw',
);

has 'markers' => (
    isa => 'HashRef',
    is => 'rw',
    lazy     => 1,
    builder  => '_retrieve_nd_protocolprop_markers',
);

has 'marker_names' => (
    isa => 'ArrayRef',
    is => 'rw'
);

has 'markers_array' => (
    isa => 'ArrayRef',
    is => 'rw',
    lazy     => 1,
    builder  => '_retrieve_nd_protocolprop_markers_array',
);

has 'header_information_lines' => (
    isa => 'ArrayRef',
    is => 'rw'
);

has 'grm_stock_relatedness' => (
    isa => 'HashRef',
    is => 'rw',
    lazy     => 1,
    builder  => '_retrieve_stock_relatedness_grm',
);

has 'reference_genome_name' => (
    isa => 'Str',
    is => 'rw'
);

has 'species_name' => (
    isa => 'Str',
    is => "rw"
);

has 'sample_observation_unit_type_name' => (
    isa => 'Str',
    is => 'rw'
);

has 'is_grm_protocol' => (
    isa => 'Bool',
    is => 'rw'
);

has 'create_date' => (
    isa => 'Str',
    is => 'rw'
);

has 'marker_type' => (
    isa => 'Str',
    is => 'rw'
);

#Filtering KEYS

has 'chromosome_list' => (
    isa => 'ArrayRef[Int]|ArrayRef[Str]|Undef',
    is => 'ro',
);

has 'start_position' => (
    isa => 'Int|Undef',
    is => 'ro',
);

has 'end_position' => (
    isa => 'Int|Undef',
    is => 'ro',
);

has 'marker_name_list' => (
    isa => 'ArrayRef[Str]|Undef',
    is => 'ro',
);

sub BUILD {
    my $self = shift;
    my $schema = $self->bcs_schema;
    my $geno_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'genotyping_experiment', 'experiment_type')->cvterm_id();
    my $protocol_vcf_details_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'vcf_map_details', 'protocol_property')->cvterm_id();
    my $pcr_marker_protocolprop_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'pcr_marker_details', 'protocol_property')->cvterm_id();
    my $pcr_marker_protocol_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'pcr_marker_protocol', 'protocol_type')->cvterm_id();

    my $q = "SELECT nd_protocol.nd_protocol_id, nd_protocol.name, nd_protocolprop.value, nd_protocol.create_date, nd_protocol.description, nd_protocol.private_company_id, nd_protocol.is_private
        FROM nd_protocol
        LEFT JOIN nd_protocolprop ON(nd_protocol.nd_protocol_id = nd_protocolprop.nd_protocol_id AND nd_protocolprop.type_id IN (?,?))
        WHERE nd_protocol.type_id IN (?,?) AND nd_protocol.nd_protocol_id=?;";
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute($protocol_vcf_details_cvterm_id, $pcr_marker_protocolprop_cvterm_id, $geno_cvterm_id, $pcr_marker_protocol_cvterm_id, $self->nd_protocol_id);
    my ($nd_protocol_id, $nd_protocol_name, $value, $create_date, $description, $private_company_id, $is_private) = $h->fetchrow_array();
    $h = undef;

    my $map_details = $value ? decode_json $value : {};
    # print STDERR Dumper $map_details;
    $self->private_company_id($private_company_id);
    $self->private_company_protocol_is_private($is_private);

    my $marker_names = $map_details->{marker_names} || [];
    my $is_grm_protocol = $map_details->{is_grm};
    $self->is_grm_protocol($is_grm_protocol);

    my $marker_type = $map_details->{marker_type};
    if (!$marker_type) {
        $marker_type = 'SNP';
    }
    my $header_information_lines = $map_details->{header_information_lines} || [];
    my $reference_genome_name;
    if ($marker_type eq 'SSR') {
        $reference_genome_name = 'NA';
    } else {
        $reference_genome_name = $map_details->{reference_genome_name} || 'Not set. Please reload these genotypes using new genotype format!';
    }

    my $species_name = $map_details->{species_name} || 'Not set. Please reload these genotypes using new genotype format!';
    my $sample_observation_unit_type_name = $map_details->{sample_observation_unit_type_name} || 'Not set. Please reload these genotypes using new genotype format!';

    if ($is_grm_protocol) {
        $header_information_lines = ["##Genotyping protocol is of genomic relationships between accessions (GRM)"];
        $sample_observation_unit_type_name = 'accession';
    }

    $self->marker_names($marker_names);
    $self->protocol_name($nd_protocol_name);
    $self->marker_type($marker_type);
    if ($header_information_lines) {
        $self->header_information_lines($header_information_lines);
    }
    if ($reference_genome_name) {
        $self->reference_genome_name($reference_genome_name);
    }
    $self->species_name($species_name);
    $self->sample_observation_unit_type_name($sample_observation_unit_type_name);
    if ($create_date) {
        $self->create_date($create_date);
    }
    if ($description) {
        $self->protocol_description($description);
    }

    return;
}

sub _retrieve_nd_protocolprop_markers {
    my $self = shift;
    my $schema = $self->bcs_schema;
    my $chromosome_list = $self->chromosome_list;
    my $start_position = $self->start_position;
    my $end_position = $self->end_position;
    my $marker_name_list = $self->marker_name_list;

    my $geno_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'genotyping_experiment', 'experiment_type')->cvterm_id();
    my $protocol_vcf_details_markers_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'vcf_map_details_markers', 'protocol_property')->cvterm_id();

    my $chromosome_where = '';
    if ($chromosome_list && scalar(@$chromosome_list)>0) {
        my $chromosome_list_sql = '\'' . join('\', \'', @$chromosome_list) . '\'';
        $chromosome_where = " AND (s.value->>'chrom')::text IN ($chromosome_list_sql)";
    }
    my $start_position_where = '';
    if (defined($start_position)) {
        $start_position_where = " AND (s.value->>'pos')::int >= $start_position";
    }
    my $end_position_where = '';
    if (defined($end_position)) {
        $end_position_where = " AND (s.value->>'pos')::int <= $end_position";
    }
    my $marker_name_list_where = '';
    if ($marker_name_list && scalar(@$marker_name_list)>0) {
        my $search_vals_sql = '\''.join ('\', \'' , @$marker_name_list).'\'';
        $marker_name_list_where = "AND (s.value->>'name')::text IN ($search_vals_sql)";
    }

    my $protocolprop_q = "SELECT nd_protocol_id, s.key, s.value
        FROM nd_protocolprop, jsonb_each(nd_protocolprop.value) as s
        WHERE nd_protocol_id = ? and type_id = $protocol_vcf_details_markers_cvterm_id $chromosome_where $start_position_where $end_position_where $marker_name_list_where;";

    my $h = $schema->storage->dbh()->prepare($protocolprop_q);
    $h->execute($self->nd_protocol_id);
    my %markers;
    while (my ($nd_protocol_id, $marker_name, $value) = $h->fetchrow_array()) {
        $markers{$marker_name} = decode_json $value;
    }
    $h = undef;

    $self->markers(\%markers);
}

sub _retrieve_nd_protocolprop_markers_array {
    my $self = shift;
    my $schema = $self->bcs_schema;
    my $geno_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'genotyping_experiment', 'experiment_type')->cvterm_id();
    my $protocol_vcf_details_markers_array_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'vcf_map_details_markers_array', 'protocol_property')->cvterm_id();

    my $q = "SELECT nd_protocol_id, value
        FROM nd_protocolprop
        WHERE type_id = $protocol_vcf_details_markers_array_cvterm_id AND nd_protocol_id =?;";
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute($self->nd_protocol_id);
    my ($nd_protocol_id, $value) = $h->fetchrow_array();
    $h = undef;

    my $markers_array = $value ? decode_json $value : [];
    $self->markers_array($markers_array);
}

sub _retrieve_stock_relatedness_grm {
    my $self = shift;
    my $schema = $self->bcs_schema;

    my $q = "SELECT a_stock_id, a.uniquename, b_stock_id, b.uniquename, value
        FROM stock_relatedness
        JOIN stock AS a ON(stock_relatedness.a_stock_id = a.stock_id)
        JOIN stock AS b ON(stock_relatedness.b_stock_id = b.stock_id)
        WHERE nd_protocol_id =?;";
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute($self->nd_protocol_id);
    my %grm_data;
    my %all_a_stock_ids;
    my %all_b_stock_ids;
    my $minimum_value = 100000;
    my $maximum_value = -100000;
    while(my ($a_stock_id, $a_uniquename, $b_stock_id, $b_uniquename, $value) = $h->fetchrow_array()) {
        $grm_data{$a_stock_id}->{$b_stock_id} = $value;
        $all_a_stock_ids{$a_stock_id} = $a_uniquename;
        $all_b_stock_ids{$b_stock_id} = $b_uniquename;

        if ($value < $minimum_value) {
            $minimum_value = $value;
        }
        if ($value > $maximum_value) {
            $maximum_value = $value;
        }
    }
    $h = undef;

    $self->grm_stock_relatedness({
        a_stock_id_map => \%all_a_stock_ids,
        b_stock_id_map => \%all_b_stock_ids,
        data => \%grm_data,
        max => $maximum_value,
        min => $minimum_value
    });
}

#class method
sub list {
    print STDERR "Protocol list search\n";
    my $schema = shift;
    my $protocol_list = shift;
    my $accession_list = shift;
    my $tissue_sample_list = shift;
    my $limit = shift;
    my $offset = shift;
    my $genotyping_data_project_list = shift;
    my @where_clause;

    my $vcf_map_details_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'vcf_map_details', 'protocol_property')->cvterm_id();
    my $vcf_map_details_markers_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'vcf_map_details_markers', 'protocol_property')->cvterm_id();
    my $vcf_map_details_markers_array_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'vcf_map_details_markers_array', 'protocol_property')->cvterm_id();
    my $accession_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'accession', 'stock_type')->cvterm_id();
    my $tissue_sample_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'tissue_sample', 'stock_type')->cvterm_id();
    my $nd_protocol_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'genotyping_experiment', 'experiment_type')->cvterm_id();
    my $grm_protocol_experiment_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'grm_genotyping_protocol_experiment', 'experiment_type')->cvterm_id();
    my $pcr_marker_details_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'pcr_marker_details', 'protocol_property')->cvterm_id();
    my $pcr_marker_protocol_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'pcr_marker_protocol', 'protocol_type')->cvterm_id();

    #push @where_clause, "nd_protocolprop.type_id = $vcf_map_details_cvterm_id";
    push @where_clause, "nd_protocol.type_id IN ($nd_protocol_type_id, $pcr_marker_protocol_cvterm_id)";
    if ($protocol_list && scalar(@$protocol_list)>0) {
        my $protocol_sql = join ("," , @$protocol_list);
        push @where_clause, "nd_protocol.nd_protocol_id in ($protocol_sql)";
    }
    if ($genotyping_data_project_list && scalar(@$genotyping_data_project_list)>0) {
        my $sql = join ("," , @$genotyping_data_project_list);
        push @where_clause, "project.project_id in ($sql)";
    }
    if ($accession_list && scalar(@$accession_list)>0) {
        my $accession_sql = join ("," , @$accession_list);
        push @where_clause, "stock.stock_id in ($accession_sql)";
        push @where_clause, "stock.type_id = $accession_cvterm_id";
    }
    if ($tissue_sample_list && scalar(@$tissue_sample_list)>0) {
        my $stock_sql = join ("," , @$tissue_sample_list);
        push @where_clause, "stock.stock_id in ($stock_sql)";
        push @where_clause, "stock.type_id = $tissue_sample_cvterm_id";
    }

    my $offset_clause = '';
    my $limit_clause = '';
    if ($limit){
        $limit_clause = " LIMIT $limit ";
    }
    if ($offset){
        $offset_clause = " OFFSET $offset ";
    }
    my $where_clause = scalar(@where_clause) > 0 ? " WHERE " . (join (" AND " , @where_clause)) : '';

    my $q = "SELECT nd_protocol.nd_protocol_id, nd_protocol.name, nd_protocol.description, nd_protocol.create_date, nd_protocolprop.value, project.project_id, project.name, count(nd_protocol.nd_protocol_id) OVER() AS full_count, nd_protocolprop.value->>'marker_type', nd_protocolprop.value->>'is_grm'
        FROM stock
        JOIN cvterm AS stock_cvterm ON(stock.type_id = stock_cvterm.cvterm_id)
        JOIN nd_experiment_stock USING(stock_id)
        JOIN nd_experiment USING(nd_experiment_id)
        JOIN nd_experiment_protocol USING(nd_experiment_id)
        JOIN nd_experiment_project USING(nd_experiment_id)
        JOIN nd_protocol USING(nd_protocol_id)
        LEFT JOIN nd_protocolprop ON(nd_protocolprop.nd_protocol_id = nd_protocol.nd_protocol_id AND nd_protocolprop.type_id IN (?,?))
        JOIN project USING(project_id)
        $where_clause
        GROUP BY (nd_protocol.nd_protocol_id, nd_protocol.name, nd_protocol.description, nd_protocol.create_date, nd_protocolprop.value, project.project_id, project.name)
        ORDER BY nd_protocol.nd_protocol_id ASC
        $limit_clause
        $offset_clause;";

    # print STDERR Dumper $q;
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute($vcf_map_details_cvterm_id, $pcr_marker_details_cvterm_id);

    my @results;
    while (my ($protocol_id, $protocol_name, $protocol_description, $create_date, $protocolprop_json, $project_id, $project_name, $sample_count, $marker_type, $is_grm) = $h->fetchrow_array()) {
        my $protocol = $protocolprop_json ? decode_json $protocolprop_json : {};
        my $marker_names = $protocol->{marker_names} || [];
        my $header_information_lines = $protocol->{header_information_lines} || [];
        my $species_name = $protocol->{species_name} || 'Not set. Please reload these genotypes using new genotype format!';
        my $sample_observation_unit_type_name = $protocol->{sample_observation_unit_type_name} || 'Not set. Please reload these genotypes using new genotype format!';

        if ($is_grm) {
            $header_information_lines = ["##Genotyping protocol is of genomic relationships between accessions (GRM)"];
            $sample_observation_unit_type_name = 'accession';
        }

        my $reference_genome_name = $protocol->{reference_genome_name};
        $create_date = $create_date || 'Not set. Please reload these genotypes using new genotype format!';
        if (!$marker_type) {
            $marker_type = 'SNP';
            if (!$reference_genome_name) {
                $reference_genome_name = 'Not set. Please reload these genotypes using new genotype format!';
            }
        }
        push @results, {
            protocol_id => $protocol_id,
            protocol_name => $protocol_name,
            protocol_description => $protocol_description,
            marker_names => $marker_names,
            header_information_lines => $header_information_lines,
            reference_genome_name => $reference_genome_name,
            species_name => $species_name,
            sample_observation_unit_type_name => $sample_observation_unit_type_name,
            project_name => $project_name,
            project_id => $project_id,
            create_date => $create_date,
            observation_unit_count => $sample_count,
            marker_count => scalar(@$marker_names),
            marker_type => $marker_type,
            is_grm_protocol => $is_grm
        };
    }
    $h = undef;
    # print STDERR "PROTOCOL LIST =".Dumper(\@results);
    return \@results;
}

#class method
sub list_simple {
    print STDERR "Protocol list simple search\n";
    my $schema = shift;
    my $only_grm_protocols = shift;
    my $field_trial_ids = shift;
    my $only_geno_protocols = shift;
    my @where_clause;

    my $vcf_map_details_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'vcf_map_details', 'protocol_property')->cvterm_id();
    my $vcf_map_details_markers_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'vcf_map_details_markers', 'protocol_property')->cvterm_id();
    my $vcf_map_details_markers_array_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'vcf_map_details_markers_array', 'protocol_property')->cvterm_id();
    my $nd_protocol_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'genotyping_experiment', 'experiment_type')->cvterm_id();
    my $grm_protocol_experiment_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'grm_genotyping_protocol_experiment', 'experiment_type')->cvterm_id();
    my $pcr_marker_protocol_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'pcr_marker_protocol', 'protocol_type')->cvterm_id();
    my $pcr_marker_details_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'pcr_marker_details', 'protocol_property')->cvterm_id();

    my $field_trial_join = '';
    my $field_trial_where = '';
    if ($field_trial_ids) {
        $field_trial_join = ' JOIN nd_experiment_protocol ON(nd_protocol.nd_protocol_id=nd_experiment_protocol.nd_protocol_id)
            JOIN nd_experiment ON(nd_experiment.nd_experiment_id=nd_experiment_protocol.nd_experiment_id AND nd_experiment.type_id IN('.$grm_protocol_experiment_type_id.','.$nd_protocol_type_id.') )
            JOIN nd_experiment_project ON(nd_experiment.nd_experiment_id=nd_experiment_project.nd_experiment_id) ';
        $field_trial_where = ' AND project_id IN('.$field_trial_ids.') ';
    }

    my $q = "SELECT nd_protocol.nd_protocol_id, nd_protocol.name, nd_protocol.description, nd_protocol.create_date, nd_protocolprop.value->>'header_information_lines', nd_protocolprop.value->>'reference_genome_name', nd_protocolprop.value->>'species_name', nd_protocolprop.value->>'sample_observation_unit_type_name', jsonb_array_length(nd_protocolprop.value->'marker_names'), nd_protocolprop.value->>'marker_type', nd_protocolprop.value->>'is_grm'
        FROM nd_protocol
        LEFT JOIN nd_protocolprop ON(nd_protocolprop.nd_protocol_id = nd_protocol.nd_protocol_id AND nd_protocolprop.type_id IN (?,?))
        $field_trial_join
        WHERE nd_protocol.type_id IN (?,?) $field_trial_where
        GROUP BY (nd_protocol.nd_protocol_id, nd_protocol.name, nd_protocol.description, nd_protocol.create_date, nd_protocolprop.value)
        ORDER BY nd_protocol.nd_protocol_id ASC;";

    # print STDERR Dumper $q;
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute($vcf_map_details_cvterm_id, $pcr_marker_details_type_id, $nd_protocol_type_id, $pcr_marker_protocol_type_id);

    my @results;
    while (my ($protocol_id, $protocol_name, $protocol_description, $create_date, $header_information_lines, $reference_genome_name, $species_name, $sample_type_name, $marker_count, $marker_type, $is_grm) = $h->fetchrow_array()) {
        my $header_information_lines = $header_information_lines ? decode_json $header_information_lines : [];
        my $species_name = $species_name || 'Not set. Please reload these genotypes using new genotype format!';
        my $sample_observation_unit_type_name = $sample_type_name || 'Not set. Please reload these genotypes using new genotype format!';
        my $protocol_description = $protocol_description || 'Not set. Please reload these genotypes using new genotype format!';
        $create_date = $create_date || 'Not set. Please reload these genotypes using new genotype format!';
        if (!$marker_type) {
            $marker_type = 'SNP';
            $reference_genome_name = $reference_genome_name || 'Not set. Please reload these genotypes using new genotype format!';
        }

        if ($is_grm) {
            $header_information_lines = ["##Genotyping protocol is of genomic relationships between accessions (GRM)"];
            $sample_observation_unit_type_name = 'accession';
        }

        if ( (!$only_grm_protocols && !$only_geno_protocols) || ($only_grm_protocols && $is_grm) || ($only_geno_protocols && !$is_grm) ) {
            push @results, {
                protocol_id => $protocol_id,
                protocol_name => $protocol_name,
                protocol_description => $protocol_description,
                marker_count => $marker_count,
                header_information_lines => $header_information_lines,
                reference_genome_name => $reference_genome_name,
                species_name => $species_name,
                sample_observation_unit_type_name => $sample_observation_unit_type_name,
                create_date => $create_date,
                marker_type => $marker_type,
                is_grm_protocol => $is_grm
            };
        }
    }
    $h = undef;

    #print STDERR "SIMPLE LIST =".Dumper \@results."\n";
    return \@results;
}

sub delete_protocol {
    my $self = shift;
    my $basepath = shift;
    my $dbhost = shift;
    my $dbname = shift;
    my $dbuser = shift;
    my $dbpass = shift;
    my $temp_file_nd_experiment_id = shift;
    my $bcs_schema = $self->bcs_schema();
    my $protocol_id = $self->nd_protocol_id();

    my $geno_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($bcs_schema, 'genotyping_experiment', 'experiment_type')->cvterm_id();

    my $q = "SELECT nd_experiment_id, genotype_id
        FROM genotype
        JOIN nd_experiment_genotype USING(genotype_id)
        JOIN nd_experiment USING(nd_experiment_id)
        JOIN nd_experiment_protocol USING(nd_experiment_id)
        WHERE nd_protocol_id = $protocol_id AND nd_experiment.type_id = $geno_cvterm_id;
    ";
    my $h = $bcs_schema->storage->dbh()->prepare($q);
    $h->execute();
    my %genotype_ids_and_nd_experiment_ids_to_delete;
    while (my ($nd_experiment_id, $genotype_id) = $h->fetchrow_array()) {
        push @{$genotype_ids_and_nd_experiment_ids_to_delete{genotype_ids}}, $genotype_id;
        push @{$genotype_ids_and_nd_experiment_ids_to_delete{nd_experiment_ids}}, $nd_experiment_id;
    }
    $h = undef;

    my $q_grm = "SELECT stock_relatedness_id, nd_experiment_id
        FROM stock_relatedness
        WHERE nd_protocol_id = $protocol_id;
    ";
    my $h_grm = $bcs_schema->storage->dbh()->prepare($q_grm);
    $h_grm->execute();
    while (my ($stock_relatedness_id, $nd_experiment_id) = $h_grm->fetchrow_array()) {
        push @{$genotype_ids_and_nd_experiment_ids_to_delete{stock_relatedness_ids}}, $stock_relatedness_id;
        push @{$genotype_ids_and_nd_experiment_ids_to_delete{nd_experiment_ids}}, $nd_experiment_id;
    }
    $h_grm = undef;

    # Cascade will delete from genotypeprop
    if ($genotype_ids_and_nd_experiment_ids_to_delete{genotype_ids}) {
        my $genotype_id_sql = join (",", @{$genotype_ids_and_nd_experiment_ids_to_delete{genotype_ids}});
        my $del_geno_q = "DELETE from genotype WHERE genotype_id IN ($genotype_id_sql);";
        my $h_del_geno = $bcs_schema->storage->dbh()->prepare($del_geno_q);
        $h_del_geno->execute();
        $h_del_geno = undef;
    }

    # Cascade will delete from nd_protocolprop
    my $del_geno_prot_q = "DELETE from nd_protocol WHERE nd_protocol_id=?;";
    my $h_del_geno_prot = $bcs_schema->storage->dbh()->prepare($del_geno_prot_q);
    $h_del_geno_prot->execute($protocol_id);
    $h_del_geno_prot = undef;

    # Delete nd_experiment_md_files entries linking genotypes to archived genotyping upload file e.g. original VCF
    my $nd_experiment_id_sql = join (",", @{$genotype_ids_and_nd_experiment_ids_to_delete{nd_experiment_ids}});
    my $q_nd_exp_files_delete = "DELETE FROM phenome.nd_experiment_md_files WHERE nd_experiment_id IN ($nd_experiment_id_sql);";
    my $h3 = $bcs_schema->storage->dbh()->prepare($q_nd_exp_files_delete);
    $h3->execute();
    $h3 = undef;

    # Delete stock_relatedness_ids for GRM protocols
    if ($genotype_ids_and_nd_experiment_ids_to_delete{stock_relatedness_ids}) {
        my $stock_relatedness_id_sql = join (",", @{$genotype_ids_and_nd_experiment_ids_to_delete{stock_relatedness_ids}});
        my $q_stock_relatedness_delete = "DELETE FROM stock_relatedness WHERE stock_relatedness_id IN ($stock_relatedness_id_sql);";
        my $h4 = $bcs_schema->storage->dbh()->prepare($q_stock_relatedness_delete);
        $h4->execute();
        $h4 = undef;
    }

    # Delete from nd_experiment asynchronously because it takes long
    open (my $fh, "> :encoding(UTF-8)", $temp_file_nd_experiment_id ) || die ("\nERROR: the file $temp_file_nd_experiment_id could not be found\n" );
        foreach (@{$genotype_ids_and_nd_experiment_ids_to_delete{nd_experiment_ids}}) {
            print $fh "$_\n";
        }
    close($fh);
    my $async_delete = CXGN::Tools::Run->new();
    $async_delete->run_async("perl $basepath/bin/delete_nd_experiment_entries.pl -H $dbhost -D $dbname -U $dbuser -P $dbpass -i $temp_file_nd_experiment_id");

    # Rebuild and refresh the materialized_markerview table
    my $async_refresh = CXGN::Tools::Run->new();
    $async_refresh->run_async("perl $basepath/bin/refresh_materialized_markerview.pl -H $dbhost -D $dbname -U $dbuser -P $dbpass");

    return { success => 1};
}

1;
