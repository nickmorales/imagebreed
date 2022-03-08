use strict;
use warnings;

use lib 't/lib';
use SGN::Test::Fixture;
use Test::More;
use Test::WWW::Mechanize;
use LWP::UserAgent;
use CXGN::Genotype::Protocol;
use CXGN::Genotype::Search;
use DateTime;
use CXGN::Genotype::ParseUpload;
use CXGN::Genotype::StoreVCFGenotypes;

#Needed to update IO::Socket::SSL
use Data::Dumper;
use JSON;
local $Data::Dumper::Indent = 0;

my $f = SGN::Test::Fixture->new();
my $schema = $f->bcs_schema();
my $dbh = $schema->storage->dbh();
my $people_schema = $f->people_schema();
my $metadata_schema = $f->metadata_schema();
my $phenome_schema = $f->phenome_schema();



my $mech = Test::WWW::Mechanize->new;

$mech->post_ok('http://localhost:3010/brapi/v1/token', [ "username"=> "janedoe", "password"=> "secretpw", "grant_type"=> "password" ]);
my $response = decode_json $mech->content;
print STDERR Dumper $response;
is($response->{'metadata'}->{'status'}->[0]->{'message'}, 'Login Successfull');
my $sgn_session_id = $response->{access_token};
print STDERR $sgn_session_id."\n";

my $location_rs = $schema->resultset('NaturalDiversity::NdGeolocation')->search({description => 'Cornell Biotech'});
my $location_id = $location_rs->first->nd_geolocation_id;

my $bp_rs = $schema->resultset('Project::Project')->search({name => 'test'});
my $breeding_program_id = $bp_rs->first->project_id;

#test uploading SSR marker info
my $file = $f->config->{basepath}."/t/data/genotype_data/ssr_marker_info.xls";

my $ua = LWP::UserAgent->new;
$response = $ua->post(
    'http://localhost:3010/ajax/genotype/upload_ssr_protocol',
    Content_Type => 'form-data',
    Content => [
        "xls_ssr_protocol_file" => [ $file, 'ssr_marker_info.xls', Content_Type => 'application/vnd.ms-excel', ],
        "sgn_session_id" => $sgn_session_id,
        "upload_ssr_protocol_name" => "SSR_protocol_1",
        "upload_ssr_protocol_description_input" => "test SSR marker info upload",
        "upload_ssr_species_name_input" => "Manihot esculenta",
    ]
);

ok($response->is_success);
my $message = $response->decoded_content;
my $message_hash = decode_json $message;
is($message_hash->{'success'}, '1');

my $ssr_protocol_id = $message_hash->{'protocol_id'};

#test uploading SSR data
my %upload_metadata;
my $file_name = 't/data/genotype_data/ssr_data.xls';
my $time = DateTime->now();
my $timestamp = $time->ymd()."_".$time->hms();

#Test archive upload file
my $uploader = CXGN::UploadFile->new({
  tempfile => $file_name,
  subdirectory => 'ssr_data_upload',
  archive_path => '/tmp',
  archive_filename => 'ssr_data.xls',
  timestamp => $timestamp,
  user_id => 41, #janedoe in fixture
  user_role => 'curator'
});

## Store uploaded temporary file in archive
my $archived_filename_with_path = $uploader->archive();
my $md5 = $uploader->get_md5($archived_filename_with_path);
ok($archived_filename_with_path);
ok($md5);

my $organism_q = "SELECT organism_id FROM organism WHERE species = ?";
my @found_organisms;
my $h = $schema->storage->dbh()->prepare($organism_q);
$h->execute('Manihot esculenta');
while (my ($organism_id) = $h->fetchrow_array()){
    push @found_organisms, $organism_id;
}
my $organism_id = $found_organisms[0];

my $parser = CXGN::Genotype::ParseUpload->new({
    chado_schema => $schema,
    filename => $archived_filename_with_path,
    organism_id => $organism_id,
    observation_unit_type_name => 'accession'
});
$parser->load_plugin('SSRExcel');
my $parsed_data = $parser->parse();
ok($parsed_data, "Check if parse validate excel file works");
print STDERR Dumper $parsed_data;

my $observation_unit_uniquenames = $parsed_data->{observation_unit_uniquenames};
my $genotype_info = $parsed_data->{genotypes_info};
my $protocolprop_info = $parsed_data->{protocol_info};
$protocolprop_info->{sample_observation_unit_type_name} = 'accession';

my $temp_file_sql_copy = "/tmp/temp_file_sql_copy";

my $store_args = {
    bcs_schema=>$schema,
    metadata_schema=>$metadata_schema,
    phenome_schema=>$phenome_schema,
    observation_unit_type_name=>'accession',
    protocol_id=>$ssr_protocol_id,
    genotyping_facility=>"IGD",
    breeding_program_id=>$breeding_program_id,
    project_year=>'2021',
    project_location_id=>$location_id,
    project_name=>'ssr_project',
    project_description=>'test_ssr_upload',
    user_id=>'41',
    archived_filename=>$archived_filename_with_path,
    archived_file_type=>'ssr',
    genotyping_data_type=>'ssr',
    organism_id => $organism_id,
    temp_file_sql_copy=>$temp_file_sql_copy,
    genotype_info => $genotype_info,
    protocol_info => $protocolprop_info,
    observation_unit_uniquenames => $observation_unit_uniquenames
};
my $store_genotypes = CXGN::Genotype::StoreVCFGenotypes->new($store_args);

ok($store_genotypes->validate());
ok($store_genotypes->store_metadata());

my $stored_data = $store_genotypes->store_identifiers();
is($stored_data->{'success'}, '1');
is($stored_data->{'nd_protocol_id'}, $ssr_protocol_id);

#test retrieving data
my @protocol_id_list;
push @protocol_id_list, $ssr_protocol_id;

my $genotypes_search = CXGN::Genotype::Search->new({
	bcs_schema=>$schema,
	people_schema=>$people_schema,
	protocol_id_list=>\@protocol_id_list,
});
my $result = $genotypes_search->get_pcr_genotype_info();
my $protocol_marker_names = $result->{'marker_names'};
my $ssr_genotype_data = $result->{'protocol_genotype_data'};

my $protocol_marker_names_ref = decode_json $protocol_marker_names;
my @marker_name_arrays = sort @$protocol_marker_names_ref;

is_deeply(\@marker_name_arrays, ['m01','m02','m03','m04']);

is_deeply($ssr_genotype_data, [
    [38878,'UG120001','accession',undef,'SSR genotypes for stock (name = UG120001, id = 38878)',1064,'{"m01": {"126": "0", "184": "0"}, "m02": {"237": "1", "267": "0"}, "m03": {"157": "0"}, "m04": {"110": "0", "190": "1"}}'],
    [38879,'UG120002','accession',undef,'SSR genotypes for stock (name = UG120002, id = 38879)',1065,'{"m01": {"126": "1", "184": "1"}, "m02": {"237": "0", "267": "0"}, "m03": {"157": "0"}, "m04": {"110": "1", "190": "1"}}'],
    [38880,'UG120003','accession',undef,'SSR genotypes for stock (name = UG120003, id = 38880)',1066,'{"m01": {"126": "1", "184": "1"}, "m02": {"237": "0", "267": "0"}, "m03": {"157": "1"}, "m04": {"110": "1", "190": "1"}}'],
    [38881,'UG120004','accession',undef,'SSR genotypes for stock (name = UG120004, id = 38881)',1067,'{"m01": {"126": "0", "184": "0"}, "m02": {"237": "1", "267": "0"}, "m03": {"157": "1"}, "m04": {"110": "0", "190": "1"}}']
]);

#deleting protocol and ssr genotyping data
$ua = LWP::UserAgent->new;
$mech->get_ok("http://localhost:3010/ajax/genotyping_protocol/delete/$ssr_protocol_id?sgn_session_id=$sgn_session_id");
$response = decode_json $mech->content;
print STDERR Dumper $response;
is_deeply($response, {success=>1});

done_testing();
