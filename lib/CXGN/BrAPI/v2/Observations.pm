package CXGN::BrAPI::v2::Observations;

use Moose;
use Data::Dumper;
use SGN::Model::Cvterm;
use CXGN::Stock::Search;
use CXGN::Stock;
use CXGN::Chado::Organism;
use CXGN::BrAPI::Pagination;
use CXGN::BrAPI::FileRequest;
use CXGN::Phenotypes::StorePhenotypes;
use CXGN::TimeUtils;
use utf8;
use JSON;

extends 'CXGN::BrAPI::v2::Common';

sub search {
    my $self = shift;
    my $params = shift;
    my $page_size = $self->page_size;
    my $page = $self->page;
    my $status = $self->status;

    my $observation_level = $params->{observationLevel}->[0] || 'all'; # need to be changed in v2
    my $seasons = $params->{seasonDbId} || ($params->{seasonDbIds} || [] );
    my $location_ids = $params->{locationDbId} || ($params->{locationDbIds} || [] );
    my $study_ids = $params->{studyDbId} || ($params->{studyDbIds} || [] );
    my $trial_ids = $params->{trialDbId} || ($params->{trialDbIds} || [] );
    my $accession_ids = $params->{germplasmDbId} || ($params->{germplasmDbIds} || [] );
    my $program_ids = $params->{programDbId} || ($params->{programDbIds} || [] );
    my $start_time = $params->{observationTimeStampRangeStart}->[0] || undef;
    my $end_time = $params->{observationTimeStampRangeEnd}->[0] || undef;
    my $observation_unit_ids = $params->{observationUnitDbId} || ($params->{observationUnitDbIds} || [] );
    my $phenotype_ids = $params->{observationDbId} || ($params->{observationDbIds} || [] );
    my $trait_ids = $params->{observationVariableDbId} || ($params->{observationVariableDbIds} || [] );
    # externalReferenceID
    # externalReferenceSource
    # observationUnitLevelName
    # observationUnitLevelOrder
    # observationUnitLevelCode
    my @trial_ids_combined;
    if ($study_ids){
        push @trial_ids_combined, @$study_ids;
    }
    if ($trial_ids){
        push @trial_ids_combined, @$trial_ids;
    }

    my $limit = $page_size;
    my $offset = $page_size*$page;

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$self->bcs_schema,
            data_level=>$observation_level,
            trial_list=>\@trial_ids_combined,
            trait_list=>$trait_ids,
            include_timestamp=>1,
            year_list=>$seasons,
            location_list=>$location_ids,
            accession_list=>$accession_ids,
            folder_list=>$trial_ids,
            program_list=>$program_ids,
            plot_list=>$observation_unit_ids,
            phenotype_id_list=>$phenotype_ids,
            #limit=>$limit,
            #offset=>$offset,
            # phenotype_min_value=>$phenotype_min_value,
            # phenotype_max_value=>$phenotype_max_value,
            # exclude_phenotype_outlier=>$exclude_phenotype_outlier
        }
    );
    my ($data, $unique_traits) = $phenotypes_search->search();
    #print STDERR Dumper $data;

    my $start_index = $page*$page_size;
    my $end_index = $page*$page_size + $page_size - 1;

    my @data_window;
    my $counter = 0;
    foreach my $obs_unit (@$data){
        my @brapi_observations;
        my $observations = $obs_unit->{observations};
        foreach (@$observations){
            my $observation_id = "$_->{phenotype_id}";
            my @season = {
                year => $obs_unit->{year},
                season => $obs_unit->{year},
                seasonDbId => $obs_unit->{year}
            };

            my $obs_timestamp = $_->{collect_date} ? $_->{collect_date} : $_->{timestamp};
            if ( $start_time && $obs_timestamp < $start_time ) { next; } #skip observations before date range
            if ( $end_time && $obs_timestamp > $end_time ) { next; } #skip observations after date range

            if ($counter >= $start_index && $counter <= $end_index) {
                push @data_window, {
                    additionalInfo=>$_->{additional_info},
                    externalReferences=>undef,
                    germplasmDbId => qq|$obs_unit->{germplasm_stock_id}|,
                    germplasmName => $obs_unit->{germplasm_uniquename},
                    observationUnitDbId => qq|$obs_unit->{observationunit_stock_id}|,
                    observationUnitName => $obs_unit->{observationunit_uniquename},
                    observationDbId => $observation_id,
                    observationVariableDbId => qq|$_->{trait_id}|,
                    observationVariableName => $_->{trait_name},
                    observationTimeStamp => CXGN::TimeUtils::db_time_to_iso($obs_timestamp),
                    season => \@season,
                    collector => $_->{operator},
                    studyDbId => qq|$obs_unit->{trial_id}|,
                    uploadedBy=> $_->{operator},
                    value => qq|$_->{value}|,
                };
            }
            $counter++;
        }
    }

    my %result = (data=>\@data_window);
    my @data_files;
    my $pagination = CXGN::BrAPI::Pagination->pagination_response($counter,$page_size,$page);
    return CXGN::BrAPI::JSONResponse->return_success(\%result, $pagination, \@data_files, $status, 'Observations result constructed');
}

sub detail {
    my $self = shift;
    my $params = shift;

    my $page_size = $self->page_size;
    my $page = $self->page;
    my $status = $self->status;

    my $observation_level = $params->{observationLevel}->[0] || 'all'; # need to be changed in v2
    my $seasons = $params->{seasonDbId} || ($params->{seasonDbIds} || [] );
    my $location_ids = $params->{locationDbId} || ($params->{locationDbIds} || [] );
    my $study_ids = $params->{studyDbId} || ($params->{studyDbIds} || [] );
    my $trial_ids = $params->{trialDbId} || ($params->{trialDbIds} || [] );
    my $accession_ids = $params->{germplasmDbId} || ($params->{germplasmDbIds} || [] );
    my $program_ids = $params->{programDbId} || ($params->{programDbIds} || [] );
    my $start_time = $params->{observationTimeStampRangeStart}->[0] || undef;
    my $end_time = $params->{observationTimeStampRangeEnd}->[0] || undef;
    my $observation_unit_ids = $params->{observationUnitDbId} || ($params->{observationUnitDbIds} || [] );
    my $phenotype_ids = $params->{observationDbId} || ($params->{observationDbIds} || [] );
    my $trait_ids = $params->{observationVariableDbId} || ($params->{observationVariableDbIds} || [] );
    # externalReferenceID
    # externalReferenceSource
    # observationUnitLevelName
    # observationUnitLevelOrder
    # observationUnitLevelCode
    my @trial_ids_combined;
    if ($study_ids){
        push @trial_ids_combined, @$study_ids;
    }
    if ($trial_ids){
        push @trial_ids_combined, @$trial_ids;
    }

    my $limit = $page_size;
    my $offset = $page_size*$page;
    print STDERR Dumper $phenotype_ids;

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$self->bcs_schema,
            data_level=>$observation_level,
            trial_list=>\@trial_ids_combined,
            trait_list=>$trait_ids,
            include_timestamp=>1,
            year_list=>$seasons,
            location_list=>$location_ids,
            accession_list=>$accession_ids,
            folder_list=>$trial_ids,
            program_list=>$program_ids,
            plot_list=>$observation_unit_ids,
            phenotype_id_list=>$phenotype_ids
            #limit=>$limit,
            #offset=>$offset,
            # phenotype_min_value=>$phenotype_min_value,
            # phenotype_max_value=>$phenotype_max_value,
            # exclude_phenotype_outlier=>$exclude_phenotype_outlier
        }
    );
    my ($data, $unique_traits) = $phenotypes_search->search();
    #print STDERR Dumper $data;

    my $start_index = $page*$page_size;
    my $end_index = $page*$page_size + $page_size - 1;

    my @data_window;
    my $counter = 0;
    foreach my $obs_unit (@$data){
        my @brapi_observations;
        my $observations = $obs_unit->{observations};
        foreach (@$observations){
            my @season = {
                year => $obs_unit->{year},
                season => $obs_unit->{year},
                seasonDbId => $obs_unit->{year}
            };

            my $obs_timestamp = $_->{collect_date} ? $_->{collect_date} : $_->{timestamp};
            if ( $start_time && $obs_timestamp < $start_time ) { next; } #skip observations before date range
            if ( $end_time && $obs_timestamp > $end_time ) { next; } #skip observations after date range

            if ($counter >= $start_index && $counter <= $end_index) {
                push @data_window, {
                    additionalInfo=>$_->{additional_info},,
                    externalReferences=>undef,
                    germplasmDbId => qq|$obs_unit->{germplasm_stock_id}|,
                    germplasmName => $obs_unit->{germplasm_uniquename},
                    observationUnitDbId => qq|$obs_unit->{observationunit_stock_id}|,
                    observationUnitName => $obs_unit->{observationunit_uniquename},
                    observationDbId => qq|$_->{phenotype_id}|,
                    observationVariableDbId => qq|$_->{trait_id}|,
                    observationVariableName => $_->{trait_name},
                    observationTimeStamp => CXGN::TimeUtils::db_time_to_iso($obs_timestamp),
                    season => \@season,
                    collector => $_->{operator},
                    studyDbId => qq|$obs_unit->{trial_id}|,
                    uploadedBy=> $_->{operator},
                    value => qq|$_->{value}|,
                };
            }
            $counter++;
        }
    }

    my @data_files;
    my $pagination = CXGN::BrAPI::Pagination->pagination_response($counter,$page_size,$page);
    return CXGN::BrAPI::JSONResponse->return_success(@data_window, $pagination, \@data_files, $status, 'Observations result constructed');
}

sub observations_store {
    my $self = shift;
    my $params = shift;
    my $c = shift;

    my $schema = $self->bcs_schema;
    my $metadata_schema = $self->metadata_schema;
    my $phenome_schema = $self->phenome_schema;
    my $dbh = $self->bcs_schema()->storage()->dbh();

    my $observations = $params->{observations};
    my $overwrite_values = $params->{overwrite} ? $params->{overwrite} : 0;
    my $user_id = $params->{user_id};
    my $user_type = $params->{user_type};
    my $archive_path = $c->config->{archive_path};
    my $tempfiles_subdir = $c->config->{basepath}."/".$c->config->{tempfiles_subdir};

    my $page_size = $self->page_size;
    my $page = $self->page;
    my $status = $self->status;
    my %result;

    #print STDERR "OBSERVATIONS_MODULE: User id is $user_id and type is $user_type\n";
    if (!$user_id) {
        print STDERR 'Must provide user_id to upload phenotypes! Please contact us!';
        push @$status, {'403' => 'Permission Denied. Must provide user_id.'};
        return CXGN::BrAPI::JSONResponse->return_error($status, 'Must provide user_id to upload phenotypes! Please contact us!', 403);
    }

    if ($user_type ne 'submitter' && $user_type ne 'sequencer' && $user_type ne 'curator') {
        print STDERR 'Must have submitter privileges to upload phenotypes! Please contact us!';
        push @$status, {'403' => 'Permission Denied. Must have correct privilege.'};
        return CXGN::BrAPI::JSONResponse->return_error($status, 'Must have submitter privileges to upload phenotypes! Please contact us!', 403);
    }

    my $p = $c->dbic_schema("CXGN::People::Schema")->resultset("SpPerson")->find({sp_person_id=>$user_id});
    my $user_name = $p->username;

    ## Validate request structure and parse data
    my $timestamp_included = 1;
    my $data_level = 'stocks';

    my $parser = CXGN::Phenotypes::ParseUpload->new();
    my $validated_request = $parser->validate('brapi observations', $observations, $timestamp_included, $data_level, $schema, undef, undef);

    if (!$validated_request || $validated_request->{'error'}) {
        my $parse_error = $validated_request ? $validated_request->{'error'} : "Error parsing request structure";
        print STDERR $parse_error;
        return CXGN::BrAPI::JSONResponse->return_error($status, $parse_error, 400);
    } elsif ($validated_request->{'success'}) {
        push @$status, {'info' => $validated_request->{'success'} };
    }


    my $parsed_request = $parser->parse('brapi observations', $observations, $timestamp_included, $data_level, $schema, undef, $user_name, undef, undef);
    my %parsed_data;
    my @units;
    my @variables;

    if (!$parsed_request || $parsed_request->{'error'}) {
        my $parse_error = $parsed_request ? $parsed_request->{'error'} : "Error parsing request data";
        print STDERR $parse_error;
        return CXGN::BrAPI::JSONResponse->return_error($status, $parse_error, 400);
    } elsif ($parsed_request->{'success'}) {
        push @$status, {'info' => $parsed_request->{'success'} };
        #define units (observationUnits) and variables (observationVariables) from parsed request
        @units = @{$parsed_request->{'units'}};
        @variables = @{$parsed_request->{'variables'}};
        %parsed_data = %{$parsed_request->{'data'}};
    }

    ## Archive in file
    my $archived_request = CXGN::BrAPI::FileRequest->new({
        schema=>$schema,
        user_id => $user_id,
        user_type => $user_type,
        tempfiles_subdir => $tempfiles_subdir,
        archive_path => $archive_path,
        format => 'observations',
        data => $observations
    });

    my $response = $archived_request->get_path();
    my $file = $response->{archived_filename_with_path};
    my $archive_error_message = $response->{error_message};
    my $archive_success_message = $response->{success_message};
    if ($archive_error_message){
        return CXGN::BrAPI::JSONResponse->return_error($status, $archive_error_message, 500);
    }
    if ($archive_success_message){
        push @$status, {'info' => $archive_success_message };
    }

    print STDERR "Archived Request is in $file\n";

    ## Set metadata
    my %phenotype_metadata;
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();
    $phenotype_metadata{'archived_file'} = $file;
    $phenotype_metadata{'archived_file_type'} = 'brapi observations';
    $phenotype_metadata{'operator'} = $user_name;
    $phenotype_metadata{'date'} = $timestamp;

    ## Store observations and return details for response
    my $store_observations = CXGN::Phenotypes::StorePhenotypes->new(
        basepath=>$c->config->{basepath},
        dbhost=>$c->config->{dbhost},
        dbname=>$c->config->{dbname},
        dbuser=>$c->config->{dbuser},
        dbpass=>$c->config->{dbpass},
        bcs_schema=>$schema,
        metadata_schema=>$metadata_schema,
        phenome_schema=>$phenome_schema,
        user_id=>$user_id,
        stock_list=>\@units,
        trait_list=>\@variables,
        values_hash=>\%parsed_data,
        has_timestamps=>1,
        metadata_hash=>\%phenotype_metadata,
        overwrite_values=>$overwrite_values,
        #image_zipfile_path=>$image_zip,
    );
    my ($verified_warning, $verified_error) = $store_observations->verify();

    if ($verified_error) {
        print STDERR "Error: $verified_error\n";
        return CXGN::BrAPI::JSONResponse->return_error($status, "Error: Your request did not pass the checks.", 500);
    }
    if ($verified_warning) {
        print STDERR "\nWarning: $verified_warning\n";
    }

    my ($stored_observation_error, $stored_observation_success, $stored_observation_details) = $store_observations->store();

    if ($stored_observation_error) {
        print STDERR "Error: $stored_observation_error\n";
        return CXGN::BrAPI::JSONResponse->return_error($status, "Error: Your request could not be processed correctly.", 500);
    }
    if ($stored_observation_success) {
        #if no error refresh matviews
        my $bs = CXGN::BreederSearch->new( { dbh=>$dbh, dbname=>$c->config->{dbname}, } );
        my $refresh = $bs->refresh_matviews($c->config->{dbhost}, $c->config->{dbname}, $c->config->{dbuser}, $c->config->{dbpass}, 'fullview', 'nonconcurrent', $c->config->{basepath});

        print STDERR "Success: $stored_observation_success\n";
        # result need to be updated with v2 format
        $result{data} = $stored_observation_details;

    }
    # result need to be updated with v2 format, StorePhenotypes needs to be modified as v2
    my @data_files = ();
    my $total_count = scalar @{$observations};
    my $pagination = CXGN::BrAPI::Pagination->pagination_response($total_count,$page_size,$page);
    return CXGN::BrAPI::JSONResponse->return_success(\%result, $pagination, \@data_files, $status, $stored_observation_success);

}

1;
