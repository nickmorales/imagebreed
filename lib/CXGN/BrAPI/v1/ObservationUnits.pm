package CXGN::BrAPI::v1::ObservationUnits;

use Moose;
use Data::Dumper;
use SGN::Model::Cvterm;
use CXGN::Trial;
use CXGN::Trait;
use CXGN::Phenotypes::SearchFactory;
use CXGN::BrAPI::Pagination;
use CXGN::BrAPI::JSONResponse;
use Try::Tiny;
use CXGN::Phenotypes::PhenotypeMatrix;
use CXGN::List::Transform;
use JSON;

extends 'CXGN::BrAPI::v1::Common';

sub search {
    my $self = shift;
    my $params = shift;
    my $page_size = $self->page_size;
    my $page = $self->page;
    my $status = $self->status;
    my @data_files;
    print STDERR Dumper $params;

    my $data_level = $params->{observationLevel} && scalar(@{$params->{observationLevel}})>0 ? $params->{observationLevel} : ['all'];
    my $years_arrayref = $params->{seasonDbId} || ($params->{seasonDbIds} || ());
    my $location_ids_arrayref = $params->{locationDbId} || ($params->{locationDbIds} || ());
    my $study_ids_arrayref = $params->{studyDbId} || ($params->{studyDbIds} || ());
    my $accession_ids_arrayref = $params->{germplasmDbId} || ($params->{germplasmDbIds} || ());
    my $trait_list_arrayref = $params->{observationVariableDbId} || ($params->{observationVariableDbIds} || ());
    my $program_ids_arrayref = $params->{programDbId} || ($params->{programDbIds} || ());
    my $folder_ids_arrayref = $params->{trialDbId} || ($params->{trialDbIds} || ());
    my $start_time = $params->{observationTimeStampRangeStart}->[0] || undef;
    my $end_time = $params->{observationTimeStampRangeEnd}->[0] || undef;
    my $level_order_arrayref = $params->{observationUnitLevelOrder} || ($params->{observationUnitLevelOrders} || ());
    my $level_code_arrayref = $params->{observationUnitLevelCode} || ($params->{observationUnitLevelCodes} || ());
    my $levels_relation_arrayref = $params->{observationLevelRelationships} || ();
    my $levels_arrayref = $params->{observationLevels} || ();
    my $include_observations = $params->{includeObservations} || "true";

    my $include_observations_bool = lc $include_observations eq 'true' ? 1 : 0;

    if ($levels_arrayref){
        $data_level = ();
        foreach ( @{$levels_arrayref} ){
            push @$level_code_arrayref, $_->{levelCode} if ($_->{levelCode});
            push @{$data_level}, $_->{levelName} if ($_->{levelName});
        }
        if (! $data_level) {
            $data_level = ['all'];
        }
    }

    # not part of brapi standard yet
    # my $phenotype_min_value = $params->{phenotype_min_value};
    # my $phenotype_max_value = $params->{phenotype_max_value};
    # my $exclude_phenotype_outlier = $params->{exclude_phenotype_outlier} || 0;
    # my $search_type = $params->{search_type}->[0] || 'MaterializedViewTable';

    my $lt = CXGN::List::Transform->new();
    my $trait_ids_arrayref = $lt->transform($self->bcs_schema, "traits_2_trait_ids", $trait_list_arrayref)->{transform};

    my $limit = $page_size*($page+1)-1;
    my $offset = $page_size*$page;

    my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
        'MaterializedViewTable',
        {
            bcs_schema=>$self->bcs_schema,
            data_level=>$data_level->[0],
            trial_list=>$study_ids_arrayref,
            trait_list=>$trait_ids_arrayref,
            include_timestamp=>1,
            year_list=>$years_arrayref,
            location_list=>$location_ids_arrayref,
            accession_list=>$accession_ids_arrayref,
            folder_list=>$folder_ids_arrayref,
            program_list=>$program_ids_arrayref,
            limit=>$limit,
            offset=>$offset,
            include_observations=>$include_observations_bool
            # phenotype_min_value=>$phenotype_min_value,
            # phenotype_max_value=>$phenotype_max_value,
            # exclude_phenotype_outlier=>$exclude_phenotype_outlier
        }
    );
    my ($data, $unique_traits) = $phenotypes_search->search();
    # print STDERR Dumper $data;

    my @plant_ids;
    my %plant_parents;
    foreach my $obs_unit (@$data){
        if ($obs_unit->{observationunit_type_name} eq 'plant') {
            push @plant_ids, $obs_unit->{observationunit_stock_id};
        }
    }
    if (@plant_ids && scalar @plant_ids > 0) {
        %plant_parents = $self->_get_plants_plot_parent(\@plant_ids);
    }

    my $plot_geojson_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'plot_geo_json', 'stock_property')->cvterm_id();
    my $additional_info_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'stock_additional_info', 'stock_property')->cvterm_id();

    my @data_window;
    my $total_count = 0;
    foreach my $obs_unit (@$data){
        my @brapi_observations;

        if ($include_observations_bool) {
            my $observations = $obs_unit->{observations};
            foreach (@$observations){
                my $obs_timestamp = $_->{collect_date} ? $_->{collect_date} : $_->{timestamp};
                if ( $start_time && $obs_timestamp < $start_time ) { next; } #skip observations before date range
                if ( $end_time && $obs_timestamp > $end_time ) { next; } #skip observations after date range

                my @season = {
                    year => $obs_unit->{year},
                    season => undef,
                    seasonDbId => undef
                };

                push @brapi_observations, {
                    observationDbId => qq|$_->{phenotype_id}|,
                    observationVariableDbId => qq|$_->{trait_id}|,
                    observationVariableName => $_->{trait_name},
                    observationTimeStamp => $obs_timestamp,
                    season => \@season,
                    collector => $_->{operator},
                    value => qq|$_->{value}|,
                };
            }
        }

        my @brapi_treatments;
        my $treatments = $obs_unit->{treatments};
        while (my ($factor, $modality) = each %$treatments){
            my $modality = $modality ? $modality : '';
            push @brapi_treatments, {
                factor => $factor,
                modality => $modality,
            };
        }

        my $sp_rs = $self->bcs_schema->resultset("Stock::Stockprop")->search({ type_id => $plot_geojson_type_id, stock_id => $obs_unit->{observationunit_stock_id} });
        my %geolocation_lookup;
        while( my $r = $sp_rs->next()){
            $geolocation_lookup{$r->stock_id} = $r->value;
        }
        my $geo_coordinates_string = $geolocation_lookup{$obs_unit->{observationunit_stock_id}} ? $geolocation_lookup{$obs_unit->{observationunit_stock_id}} : undef;
        my $geo_coordinates;

        if ($geo_coordinates_string){
            $geo_coordinates = decode_json $geo_coordinates_string;
        }

        my $additional_info;
        my $rs = $self->bcs_schema->resultset("Stock::Stockprop")->search({ type_id => $additional_info_type_id, stock_id => $obs_unit->{observationunit_stock_id} });
        if ($rs->count() > 0){
            my $additional_info_json = $rs->first()->value();
            $additional_info = $additional_info_json ? decode_json($additional_info_json) : undef;
        }

        my $entry_type = $obs_unit->{obsunit_is_a_control} ? 'check' : 'test';

        my $replicate = $obs_unit->{obsunit_rep};
        my $block = $obs_unit->{obsunit_block};

        my $plot;
        my $plant;
        if ($obs_unit->{observationunit_type_name} eq 'plant') {
            $plant = $obs_unit->{obsunit_plant_number};
            if ($plant_parents{$obs_unit->{observationunit_stock_id}}) {
                my $plot_object = $plant_parents{$obs_unit->{observationunit_stock_id}};
                $plot = $plot_object->{plot_number};
                $additional_info->{observationUnitParent} = $plot_object->{id};
            }
        } else {
            $plot = $obs_unit->{obsunit_plot_number};
        }

        my $level_name = $obs_unit->{observationunit_type_name};
        my $level_order = _order($level_name) + 0;
        my $level_code = eval "\$$level_name" || "";

        if ( $level_order_arrayref &&  ! grep { $_ eq $level_order } @{$level_order_arrayref}  ) { next; }
        if ( $level_code_arrayref &&  ! grep { $_ eq $level_code } @{$level_code_arrayref}  ) { next; }

        my @observationLevelRelationships;
        if ($replicate) {
            push @observationLevelRelationships, {
                levelCode => $replicate,
                levelName => "replicate",
                levelOrder => _order("replicate"),
            }
        }
        if ($block) {
            push @observationLevelRelationships, {
                levelCode => $block,
                levelName => "block",
                levelOrder => _order("block"),
            }
        }
        if ($plot) {
            push @observationLevelRelationships, {
                levelCode => qq|$plot|,
                levelName => "plot",
                levelOrder => _order("plot"),
            }
        }
        if ($plant) {
            push @observationLevelRelationships, {
                levelCode => $plant,
                levelName => "plant",
                levelOrder => _order("plant"),
            }
        }

        my $positionCoordinateXType = !$geo_coordinates ? "GRID_COL" : "LONGITUDE";
        my $positionCoordinateYType = !$geo_coordinates ? "GRID_ROW" : "LATITUDE";

        my %observationUnitPosition = (
            entryType => $entry_type,
            geoCoordinates => $geo_coordinates,
            positionCoordinateX => $obs_unit->{obsunit_col_number} ? $obs_unit->{obsunit_col_number} + 0 : undef,
            positionCoordinateXType => $positionCoordinateXType,
            positionCoordinateY => $obs_unit->{obsunit_row_number} ? $obs_unit->{obsunit_row_number} + 0 : undef,
            positionCoordinateYType => $positionCoordinateYType,
            # replicate => $obs_unit->{obsunit_rep}, #obsolete v2?
            observationLevel =>  {
                levelName => $level_name,
                levelOrder => $level_order,
                levelCode => $level_code,
            },
            observationLevelRelationships => \@observationLevelRelationships,
        );

        push @data_window, {
            additionalInfo => $additional_info,
            observationUnitPosition => \%observationUnitPosition,
            observationUnitDbId => qq|$obs_unit->{observationunit_stock_id}|,
            observationLevel => $obs_unit->{observationunit_type_name},
            observationLevels => $obs_unit->{observationunit_type_name},
            plotNumber => $obs_unit->{obsunit_plot_number},
            plantNumber => $obs_unit->{obsunit_plant_number},
            blockNumber => $obs_unit->{obsunit_block},
            replicate => $obs_unit->{obsunit_rep},
            observationUnitName => $obs_unit->{observationunit_uniquename},
            germplasmDbId => qq|$obs_unit->{germplasm_stock_id}|,
            germplasmName => $obs_unit->{germplasm_uniquename},
            studyDbId => qq|$obs_unit->{trial_id}|,
            studyName => $obs_unit->{trial_name},
            studyLocationDbId => qq|$obs_unit->{trial_location_id}|,
            studyLocation => $obs_unit->{trial_location_name},
            locationDbId => qq|$obs_unit->{trial_location_id}|,
            locationName => $obs_unit->{trial_location_name},
            programName => $obs_unit->{breeding_program_name},
            X => $obs_unit->{obsunit_col_number},
            Y => $obs_unit->{obsunit_row_number},
            entryType => $entry_type,
            entryNumber => '',
            treatments => \@brapi_treatments,
            observations => \@brapi_observations,
            observationUnitXref => [],
            pedigree => undef
        };
        $total_count = $obs_unit->{full_count};
    }

    my %result = (data=>\@data_window);
    my $pagination = CXGN::BrAPI::Pagination->pagination_response($total_count,$page_size,$page);
    return CXGN::BrAPI::JSONResponse->return_success(\%result, $pagination, \@data_files, $status, 'Phenotype search result constructed');
}

sub _get_plants_plot_parent {
    my $self = shift;
    my $plant_id_array = shift;
    my $schema = $self->bcs_schema;

    my $plant_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plant_of', 'stock_relationship')->cvterm_id();
    my $plot_number_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot number', 'stock_property')->cvterm_id();
    my $plant_ids_string = join ',', @{$plant_id_array};
    my $select = "select stock.stock_id, stock_relationship.subject_id, stockprop.value from stock join stock_relationship on stock.stock_id = stock_relationship.object_id join stockprop on stock_relationship.subject_id = stockprop.stock_id where stockprop.type_id = $plot_number_cvterm_id and stock_relationship.type_id = $plant_cvterm_id and stock.stock_id in ($plant_ids_string);";
    my $h = $schema->storage->dbh()->prepare($select);
    $h->execute();

    my %plant_hash;
    while (my ($plant_id, $plot_id, $plot_number) = $h->fetchrow_array()) {
        $plant_hash{$plant_id} = { id => $plot_id, plot_number => $plot_number };
    }
    $h = undef;

    return %plant_hash;
}

sub _order {
    my $value = shift;
    my %levels = (
        "replicate"  => 0,
        "block"  => 1,
        "plot" => 2,
        "subplot"=> 3,
        "plant"=> 4,
        "tissue_sample"=> 5,

    );
    return $levels{$value} + 0;
}

1;
