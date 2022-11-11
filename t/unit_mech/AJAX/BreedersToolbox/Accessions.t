
# Tests all functions in SGN::Controller::AJAX::Accessions. These are the functions called from Accessions.js when adding new accessions.

use strict;
use warnings;
use utf8;

use lib 't/lib';
use SGN::Test::Fixture;
use Test::More;
use Test::WWW::Mechanize;

#Needed to update IO::Socket::SSL
use Data::Dumper;
use JSON;
use URI::Encode qw(uri_encode uri_decode);
use CXGN::Chado::Stock;
use LWP::UserAgent;
use CXGN::List;
use CXGN::Stock::Accession;
use Encode;

local $Data::Dumper::Indent = 0;

my $f = SGN::Test::Fixture->new();
my $schema = $f->bcs_schema;

my $mech = Test::WWW::Mechanize->new;
my $response;
my $json = JSON->new->allow_nonref;

$mech->post_ok('http://localhost:3010/brapi/v1/token', [ "username"=> "janedoe", "password"=> "secretpw", "grant_type"=> "password" ]);
$response = decode_json $mech->content;
print STDERR Dumper $response;
is($response->{'metadata'}->{'status'}->[0]->{'message'}, 'Login Successfull');
my $sgn_session_id = $response->{access_token};

$mech->post_ok('http://localhost:3010/ajax/accession_list/verify', [ "accession_list"=> '["new_accession1", "test_accession1", "test_accessionx", "test_accessiony", "test_accessionД"]', "do_fuzzy_search"=> "true" ]);
$response = decode_json $mech->content;
print STDERR Dumper $response->{'fuzzy'};
print STDERR Dumper $response->{'found'};
print STDERR Dumper $response->{'absent'};

is(scalar @{$response->{'fuzzy'}}, 3, 'check verify fuzzy match response content');
is_deeply($response->{'found'}, [{'matched_string' => 'test_accession1','unique_name' => 'test_accession1'}], 'check verify fuzzy match response content');
is_deeply($response->{'absent'}, ['new_accession1'], 'check verify fuzzy match response content');

my $fuzzy_option_data = {
    "option_form1" => { "fuzzy_name" => "test_accessionx", "fuzzy_select" => "test_accession1", "fuzzy_option" => "replace" },
    "option_form2" => { "fuzzy_name" => "test_accessiony", "fuzzy_select" => "test_accession1", "fuzzy_option" => "synonymize" },
    "option_form3" => { "fuzzy_name" => "test_accessionД", "fuzzy_select" => "test_accession1", "fuzzy_option" => "keep" }
};

$mech->post_ok('http://localhost:3010/ajax/accession_list/fuzzy_options', [ "accession_list_id"=> '3', "fuzzy_option_data"=>$json->encode($fuzzy_option_data), "names_to_add"=>$json->encode($response->{'absent'}) ]);

print STDERR $mech->content;
my $final_response = decode_json $mech->content;
print STDERR Dumper $final_response;

is_deeply($final_response, {'names_to_add' => ['new_accession1','test_accessionД'],'success' => '1'}, 'check verify fuzzy options response content');

$mech->get_ok('http://localhost:3010/organism/verify_name?species_name='.uri_encode("Manihot esculenta") );
$response = decode_json $mech->content;
print STDERR Dumper $response;

is_deeply($response, {'success' => '1'});

my @full_info;
foreach (@{$final_response->{'names_to_add'}}){
    push @full_info, {
        'species'=>'Manihot esculenta',
        'defaultDisplayName'=>$_,
        'germplasmName'=>$_,
        'organizationName'=>'test',
        'populationName'=>'population_ajax_test_1',
        'private_company_id'=>1
    };
}

$mech->post_ok('http://localhost:3010/ajax/accession_list/add', [ 'full_info'=>$json->encode(\@full_info), 'allowed_organisms'=>$json->encode(['Manihot esculenta']) ]);
$response = decode_json $mech->content;
print STDERR Dumper $response;

is_deeply($response, {'added' => [[41786,'new_accession1'],[41788,'test_accessionД']],'success' => '1'});

#Remove added synonym so tests downstream do not fail.
my $stock_id = $schema->resultset('Stock::Stock')->find({uniquename=>'test_accession1'})->stock_id();
my $stock = CXGN::Chado::Stock->new($schema,$stock_id);
$stock->remove_synonym('test_accessiony');

#Remove added stocks so tests downstream do not fail
$stock_id = $schema->resultset('Stock::Stock')->find({uniquename=>'test_accessionД'})->stock_id();
$stock = CXGN::Chado::Stock->new($schema,$stock_id);
$stock->set_is_obsolete(1) ;
$stock->store();
$stock_id = $schema->resultset('Stock::Stock')->find({uniquename=>'new_accession1'})->stock_id();
$stock = CXGN::Chado::Stock->new($schema,$stock_id);
$stock->set_is_obsolete(1) ;
$stock->store();

#remove added population so tets downstreadm do not fail
my $population = $schema->resultset("Stock::Stock")->find({uniquename => 'population_ajax_test_1'});
$population->delete();

# Test uploading accession file
my $file = $f->config->{basepath}."/t/data/stock/test_accession_upload.xls";
my $ua = LWP::UserAgent->new;
$response = $ua->post(
        'http://localhost:3010/ajax/accessions/verify_accessions_file',
        Content_Type => 'form-data',
        Content => [
            new_accessions_upload_file => [ $file, 'test_accession_upload.xls', Content_Type => 'application/vnd.ms-excel', ],
            "sgn_session_id"=>$sgn_session_id,
            "fuzzy_check_upload_accessions"=>1,
            "add_accessions_file_private_company_select"=>1
        ]
    );

#print STDERR Dumper $response;
ok($response->is_success);
my $message = $response->decoded_content;
my $message_hash = decode_json $message;
print STDERR Dumper $message_hash;

is_deeply($message_hash->{'full_data'}, {'new_test_accession01' => {'private_company_id' => 1,'locationCode' => 'ITH','countryOfOriginCode' => 'Nigeria','defaultDisplayName' => 'new_test_accession01','accessionNumber' => 'ITC00001','species' => 'Manihot esculenta','organizationName' => 'test_organization','germplasmName' => 'new_test_accession01','populationName' => 'test_population','ploidyLevel' => '2','synonyms' => ['new_test_accession_synonym1','new_test_accession_synonym2','new_test_accession_synonym3']},'new_test_accession04' => {'organizationName' => 'test_organization','species' => 'Manihot esculenta','accessionNumber' => 'ITC00004','countryOfOriginCode' => 'Nigeria','defaultDisplayName' => 'new_test_accession04','private_company_id' => 1,'synonyms' => [],'populationName' => 'test_population','germplasmName' => 'new_test_accession04'},'new_test_accession03' => {'countryOfOriginCode' => 'Nigeria','defaultDisplayName' => 'new_test_accession03','accessionNumber' => 'ITC00003','species' => 'Manihot esculenta','organizationName' => 'test_organization','private_company_id' => 1,'synonyms' => ['new_test_accession3_synonym1'],'germplasmName' => 'new_test_accession03','populationName' => 'test_population'},'IITA-TMS-IBA010749' => {'synonyms' => ['IITA-TMS-IBA010746_synonym1','IITA-TMS-IBA010746_synonym2'],'germplasmName' => 'IITA-TMS-IBA010749','populationName' => 'test_population','organizationName' => undef,'species' => 'Manihot esculenta','defaultDisplayName' => 'IITA-TMS-IBA010749','private_company_id' => 1},'new_test_accession02' => {'germplasmName' => 'new_test_accession02','populationName' => 'test_population','synonyms' => [],'private_company_id' => 1,'countryOfOriginCode' => 'Nigeria','defaultDisplayName' => 'new_test_accession02','accessionNumber' => 'ITC00002','species' => 'Manihot esculenta','organizationName' => 'test_organization'}}, 'check parse accession file');
is(scalar @{$message_hash->{'fuzzy'}}, 1, 'check verify fuzzy match response content');
is_deeply($message_hash->{'found'}, [], 'check verify fuzzy match response content');
is(scalar @{$message_hash->{'absent'}}, 4, 'check verify fuzzy match response content');
is_deeply($message_hash->{'found_organisms'}, [{'unique_name' => 'Manihot esculenta','matched_string' => 'Manihot esculenta'}], 'check verify fuzzy match response content');

my @full_info;
foreach (keys %{$message_hash->{'full_data'}}){
    push @full_info, $message_hash->{'full_data'}->{$_};
}

$mech->post_ok('http://localhost:3010/ajax/accession_list/add?sgn_session_id='.$sgn_session_id, [ 'full_info'=>$json->encode(\@full_info), 'allowed_organisms'=>$json->encode(['Manihot esculenta']) ]);
$response = decode_json $mech->content;
print STDERR Dumper $response;

is(scalar @{$response->{'added'}}, 5);

#Remove added list so tests downstream pass
my $list_id = $message_hash->{list_id};
CXGN::List::delete_list($schema->storage->dbh, $list_id);

#Remove added stocks so tests downstream do not fail, but also test if for attributes
$stock_id = $schema->resultset('Stock::Stock')->find({uniquename=>'new_test_accession01'})->stock_id();
$stock = CXGN::Stock::Accession->new(schema=>$schema,stock_id=>$stock_id);
is($stock->organization_name, 'test_organization');
is($stock->population_name, 'test_population');
is($stock->ploidyLevel, '2');
is($stock->locationCode, 'ITH');
is($stock->countryOfOriginCode, 'Nigeria');
is($stock->accessionNumber, 'ITC00001');
is($stock->private_company_id, 1);
is_deeply($stock->synonyms, ['new_test_accession_synonym1','new_test_accession_synonym2','new_test_accession_synonym3']);
$stock->is_obsolete(1) ;
$stock->store();
$stock_id = $schema->resultset('Stock::Stock')->find({uniquename=>'new_test_accession02'})->stock_id();
$stock = CXGN::Stock::Accession->new(schema=>$schema,stock_id=>$stock_id);
is($stock->organization_name, 'test_organization');
is($stock->population_name, 'test_population');
is($stock->countryOfOriginCode, 'Nigeria');
is($stock->accessionNumber, 'ITC00002');
$stock->is_obsolete(1) ;
$stock->store();
$stock_id = $schema->resultset('Stock::Stock')->find({uniquename=>'new_test_accession03'})->stock_id();
$stock = CXGN::Stock::Accession->new(schema=>$schema,stock_id=>$stock_id);
is($stock->organization_name, 'test_organization');
is($stock->population_name, 'test_population');
is_deeply($stock->synonyms, ['new_test_accession3_synonym1']);
is($stock->countryOfOriginCode, 'Nigeria');
is($stock->accessionNumber, 'ITC00003');
$stock->is_obsolete(1) ;
$stock->store();
$stock_id = $schema->resultset('Stock::Stock')->find({uniquename=>'new_test_accession04'})->stock_id();
$stock = CXGN::Stock::Accession->new(schema=>$schema,stock_id=>$stock_id);
is($stock->organization_name, 'test_organization');
is($stock->population_name, 'test_population');
is($stock->countryOfOriginCode, 'Nigeria');
is($stock->accessionNumber, 'ITC00004');
$stock->is_obsolete(1) ;
$stock->store();
$stock_id = $schema->resultset('Stock::Stock')->find({uniquename=>'IITA-TMS-IBA010749'})->stock_id();
$stock = CXGN::Stock::Accession->new(schema=>$schema,stock_id=>$stock_id);
is($stock->population_name, 'test_population');
is_deeply($stock->synonyms, ['IITA-TMS-IBA010746_synonym1','IITA-TMS-IBA010746_synonym2']);
$stock->is_obsolete(1) ;
$stock->store();

#remove added population so tets downstreadm do not fail
$population = $schema->resultset("Stock::Stock")->find({uniquename => 'test_population'});
$population->delete();

done_testing();
