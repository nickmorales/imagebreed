package CXGN::BrAPI::v2::Events;

use Moose;
use Data::Dumper;
use SGN::Model::Cvterm;
use CXGN::Trial;
use CXGN::Calendar;
use CXGN::BrAPI::Pagination;
use CXGN::BrAPI::JSONResponse;
use Time::Piece;

extends 'CXGN::BrAPI::v2::Common';

sub search {
    my $self = shift;
    my $params = shift;
    my $page_size = $self->page_size;
    my $page = $self->page;
    my $status = $self->status;
    my $schema = $self->bcs_schema;
    my $calendar_funcs = CXGN::Calendar->new({});

    my $studydbid_arrayref = $params->{studyDbId} || ($params->{studyDbIds} || ());
    my $obsunitdbid_arrayref = $params->{observationUnitDbId} || ($params->{observationUnitDbIds} || ());
    my $eventdbid_arrayref = $params->{eventDbId} || ($params->{eventDbIds} || ());
    my $eventtypedbid_arrayref = $params->{eventType} || ($params->{eventTypes} || ());
    my $dateRangeStart = $params->{dateRangeStart}->[0] || undef;
    my $dateRangeEnd = $params->{dateRangeEnd}->[0] || undef;

    my $treatment_experiment_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'treatment_experiment', 'experiment_type')->cvterm_id();
    my $field_layout_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'field_layout', 'experiment_type')->cvterm_id();
    my $treatment_on_trial_rel_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'trial_treatment_relationship', 'project_relationship')->cvterm_id();
    my $treatment_type_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'management_factor_type', 'project_property')->cvterm_id();
    my $treatment_year_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'project year', 'project_property')->cvterm_id();
    my $treatment_date_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'management_factor_date', 'project_property')->cvterm_id();

    if ($obsunitdbid_arrayref && scalar(@$obsunitdbid_arrayref)>0) {
        my $stock_string = join ',', @$obsunitdbid_arrayref;
        my $q0 = "SELECT project.project_id
            FROM project
            JOIN nd_experiment_project ON(nd_experiment_project.project_id=project.project_id)
            JOIN nd_experiment ON(nd_experiment.nd_experiment_id=nd_experiment_project.nd_experiment_id AND nd_experiment.type_id=$field_layout_type_cvterm_id)
            JOIN nd_experiment_stock ON(nd_experiment.nd_experiment_id=nd_experiment_stock.nd_experiment_id)
            WHERE nd_experiment_stock.stock_id IN ($stock_string);";
        my $h0 = $schema->storage->dbh()->prepare($q0);
        $h0->execute();
        while (my($trial_id) = $h0->fetchrow_array()) {
            push @$studydbid_arrayref, $trial_id;
        }
        $h0 = undef;
    }

    my @where_clause;
    if ($studydbid_arrayref && scalar(@$studydbid_arrayref)>0) {
        my $string = join ',', @$studydbid_arrayref;
        push @where_clause, "trial.project_id IN ($string)";
    }
    if ($eventdbid_arrayref && scalar(@$eventdbid_arrayref)>0) {
        my $string = join ',', @$eventdbid_arrayref;
        push @where_clause, "treatment.project_id IN ($string)";
    }

    #Others are everything besides fertilizer, fungicide, irrigation, herbicide, weeding
    if ($eventtypedbid_arrayref && scalar(@$eventtypedbid_arrayref)>0) {
        my %eventtypedbid_arrayref_map = map {$_ => 1} @$eventtypedbid_arrayref;
        if (exists($eventtypedbid_arrayref_map{"chemicals"})) {
            my $string = join '","', @$eventtypedbid_arrayref;
            push @where_clause, "lower(treatment_type.value) IN ('fungicide', 'herbicide' )";

        } elsif (exists($eventtypedbid_arrayref_map{"other"})) {
            my $string = join '","', @$eventtypedbid_arrayref;
            push @where_clause, "lower(treatment_type.value) NOT IN ('fertilizer', 'fungicide', 'irrigation', 'herbicide', 'weeding' )";

        } else {
            my $string = join '","', @$eventtypedbid_arrayref;
            push @where_clause, "lower(treatment_type.value) IN ('". lc $string."')";
        }
    }

    my $where_clause_string = scalar(@where_clause) ? " WHERE ".join(' AND ', @where_clause) : '';

    my $start_index = $page*$page_size;
    my $end_index = $page*$page_size + $page_size;

    my $limit = $end_index-$start_index;
    my $offset = $start_index;

    my $q = "SELECT treatment.project_id, treatment.name, treatment.description, treatment.create_date, trial.project_id, trial.name, trial.description, trial.create_date, nd_experiment_project.nd_experiment_id, treatment_type.value, treatment_year.value, treatment_date.value, count(treatment.project_id) OVER() AS full_count
        FROM project AS trial
        JOIN project_relationship ON(trial.project_id=project_relationship.object_project_id AND project_relationship.type_id=$treatment_on_trial_rel_cvterm_id)
        JOIN project AS treatment ON(project_relationship.subject_project_id=treatment.project_id)
        JOIN nd_experiment_project ON(treatment.project_id=nd_experiment_project.project_id)
        JOIN nd_experiment ON(nd_experiment.nd_experiment_id=nd_experiment_project.nd_experiment_id AND nd_experiment.type_id=$treatment_experiment_type_cvterm_id)
        JOIN projectprop AS treatment_type ON(treatment.project_id=treatment_type.project_id AND treatment_type.type_id=$treatment_type_cvterm_id)
        JOIN projectprop AS treatment_year ON(treatment.project_id=treatment_year.project_id AND treatment_year.type_id=$treatment_year_cvterm_id)
        JOIN projectprop AS treatment_date ON(treatment.project_id=treatment_date.project_id AND treatment_date.type_id=$treatment_date_cvterm_id)
        $where_clause_string
        ORDER BY trial.project_id, treatment.project_id
        LIMIT $limit
        OFFSET $offset
        ;";

    my $q2 = "SELECT stock_id
        FROM stock
        JOIN nd_experiment_stock USING(stock_id)
        WHERE nd_experiment_id=?;";

    my $h = $schema->storage->dbh()->prepare($q);
    my $h2 = $schema->storage->dbh()->prepare($q2);
    $h->execute();

    my @data;
    my $total_count = 0;
    while (my ($treatment_id, $treatment_name, $treatment_desc, $treatment_create_date, $trial_id, $trial_name, $trial_desc, $trial_create_date, $trial_nd_experiment_id, $treatment_type_raw, $treatment_year, $treatment_date, $full_count) = $h->fetchrow_array()) {
        $total_count = $full_count;
        my $treatment_date_display = $treatment_date ? $calendar_funcs->display_start_date($treatment_date) : '';
        my $treatment_date_timestamp = '';
        if ($treatment_date_display) {
            my $formatted_time = Time::Piece->strptime($treatment_date_display, '%Y-%B-%d');
            $treatment_date_timestamp =  $formatted_time->strftime("%Y-%m-%dT%H%M%S");
        }

        $h2->execute($trial_nd_experiment_id);
        my @stock_ids;
        while (my($stock_id) = $h2->fetchrow_array()) {
            push @stock_ids, qq|$stock_id|;
        }

        if (!$treatment_desc || $treatment_desc eq 'No description'){
            $treatment_desc = $treatment_name;
        }

        my $treatment_type = _get_event_type($treatment_type_raw);

        push @data, {
            additionalInfo => {
                year => $treatment_year,
                studyDescription => $trial_desc,
                eventCreateDate => $treatment_create_date,
                studyCreateDate => $trial_create_date
            },
            date => {
                discreteDates => [ _format_date($treatment_date_timestamp) ],
                endDate => undef,
                startDate => undef
            },
            eventDbId => qq|$treatment_id|,
            eventDescription => $treatment_type_raw . ": " .  $treatment_desc,
            eventParameters => [],
            eventType => $treatment_type,
            eventTypeDbId => $treatment_type,
            observationUnitDbIds => \@stock_ids,
            studyDbId => qq|$trial_id|,
            studyName => $trial_name,
        };
    }
    $h = undef;
    $h2 = undef;

    my %result = (data => \@data);
    my @data_files = ();
    my $pagination = CXGN::BrAPI::Pagination->pagination_response($total_count,$page_size,$page);
    return CXGN::BrAPI::JSONResponse->return_success(\%result, $pagination, \@data_files, $status, 'Event search result constructed');
}


#These types comes from Brapi compaitble with ICASA format
sub _get_event_type {
    my $value = shift;

    my %types = (
        fertilizer => 'fertilizer',
        fungicide => 'chemicals',
        irrigation => 'irrigation',
        drought => 'other',
        herbicide => 'chemicals',
        weeding => 'weeding',
        pruning => 'other',
        'hormone treatment' => 'other',
        'light treatment' => 'other',

    );
    return $types{lc $value} ;

}



sub _format_date {

    my $str_date = shift; #It gets 2022-04-19T000000
    my $date;

    if ($str_date ) {
        my  $formatted_time = Time::Piece->strptime($str_date, '%Y-%m-%d');
        #Desired output format: 2017-06-01T00:00:00Z
        $date =  $formatted_time->strftime("%Y-%m-%dT%H:%M:%SZ");
    }
    else { $date = $str_date;}

    return $date;
}


1;
