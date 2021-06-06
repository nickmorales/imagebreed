
=head1 NAME

CXGN::NOAANCDC - helper class for getting weather data from NOAA NCDC weather stations

=head1 SYNOPSYS

my $noaa = CXGN::NOAANCDC->new({
    bcs_schema => $schema,
    data_types => ['TMIN', 'TMAX', 'PRCP'],
    start_date => "2019-01-13", #YYYY-MM-DD
    end_date => "2019-12-19", #YYYY-MM-DD
    noaa_station_id => "GHCND:US1NCBC0005",
    noaa_ncdc_access_token => $noaa_ncdc_access_token
});
my $temperature_averaged_growing_degree_days = $noaa->get_temperature_averaged_gdd($gdd_base_temperature);

# Musgrave stationid = GHCND:USC00300331

# Datatypes:
# PRCP Total Precipitation (+Musgrave)
# F2MN Faster 2 minute wind speed (-Musgrave)
# TMAX Maximum Temperature (+Musgrave)
# TMIN Minimum Temperature (+Musgrave)
# TOBS Temperatue at observation time (+Musgrave)
# TAVG Average Temperature (-Musgrave)
# F5SC Fastest 5 second wind speed (-Musgrave)
# AWND Average Wind Speed (-Musgrave)
# FSMI Fastest Mile (ddfff) (-Musgrave)
# FSMN Fastest One-minute Wind (ddfff) (-Musgrave)
# PRES Station Pressure (-Musgrave)
# RWND Resultant Wind Speed (-Musgrave)
# SLVP Sea Level Pressure (-Musgrave)
# TMPW Wet Bulb Temperature (-Musgrave)
# FSIN Fastest Instantaneous Wind (ddfff) (-Musgrave)
# WDMV 24_hour Wind Movement (-Musgrave)
# MNTP Average Temperature (-Musgrave)
# DPTP Dew Point Temperature (-Musgrave)

=head1 AUTHOR

Nicolas Morales <nm529@cornell.edu>

=head1 METHODS

=cut

package CXGN::NOAANCDC;

use Moose;
use Data::Dumper;
use Try::Tiny;
use SGN::Model::Cvterm;
use LWP::UserAgent;
use JSON;
use Math::Round;
use Time::Piece;
use Time::Seconds;

has 'bcs_schema' => (
    isa => 'Bio::Chado::Schema',
    is => 'rw',
    required => 1
);

has 'data_types' => (
    isa => 'ArrayRef',
    is => 'rw',
);

has 'start_date' => (
    isa => 'Str',
    is => 'rw',
    required => 1
);

has 'end_date' => (
	isa => 'Str',
	is => 'rw',
    required => 1
);

has 'noaa_station_id' => (
    isa => 'Str',
	is => 'rw',
    required => 1
);

has 'noaa_ncdc_access_token' => (
    isa => 'Str',
	is => 'rw',
    required => 1
);

sub get_noaa_data {
    my $self = shift;
    my $start_date = $self->start_date;
    my $end_date = $self->end_date;

    my $data_types_string = '&datatypeid=';
    $data_types_string .= join '&datatypeid=', @{$self->data_types};

    my $ua = LWP::UserAgent->new(
        ssl_opts => { verify_hostname => 0 }
    );
    my $server_endpoint = "https://www.ncdc.noaa.gov/cdo-web/api/v2/data?stationid=".$self->noaa_station_id."&limit=1000&datasetid=GHCND".$data_types_string."&startdate=".$start_date."&enddate=".$end_date;

    print STDERR $server_endpoint."\n";
    my $resp = $ua->get($server_endpoint, "token"=>$self->noaa_ncdc_access_token);

    my $message_hash = {};
    if ($resp->is_success) {
        my $message = $resp->decoded_content;
        $message_hash = decode_json $message;
        # print STDERR Dumper $message_hash;
    }
    else {
        my $message = $resp->decoded_content;
        print STDERR Dumper $message;
        $message_hash = decode_json $message;
    }
    return $message_hash;
}

sub do_query_max_one_year {
    my $self = shift;
    my $start_date = $self->start_date;
    my $end_date = $self->end_date;

    my $start_date_object = Time::Piece->strptime($start_date, "%Y-%m-%d");
    my $end_date_object = Time::Piece->strptime($end_date, "%Y-%m-%d");
    my $time_diff = $end_date_object - $start_date_object;
    my $time_diff_days = $time_diff->days;
    print STDERR Dumper $time_diff_days;
    my $end_date_epoch = $end_date_object->epoch;

    my @time_ranges;
    if ($time_diff_days > 365) {
        my $day_start = Time::Piece->strptime($start_date, "%Y-%m-%d") + 12 * ONE_HOUR;
        my $year_counter = 0;
        my $day_end_year = $day_start + ONE_DAY * ( 365 - $day_start->day_of_year );
        my $day_end_year_start_original = $day_end_year;
        while (1) {
            $day_end_year = $day_start + ONE_DAY * ( 365 - $day_start->day_of_year );

            if ( $day_end_year > $end_date_object ) {
                push @time_ranges, [$day_start->strftime("%Y-%m-%d"), $end_date_object->strftime("%Y-%m-%d")];
                last;
            }
            else {
                if ($year_counter == 0) {
                    push @time_ranges, [$day_start->strftime("%Y-%m-%d"), $day_end_year->strftime("%Y-%m-%d")];
                }
                else {
                    push @time_ranges, [$day_start->strftime("%Y-01-01"), $day_start->strftime("%Y-12-31")];
                }
                $day_start = $day_end_year_start_original + ONE_YEAR * $year_counter;
            }
            $year_counter++;
        }
    }
    else {
        push @time_ranges, [$start_date, $end_date];
    }
    print STDERR Dumper \@time_ranges;

    my %weather_hash;
    foreach (@time_ranges) {
        sleep(1);
        $self->start_date($_->[0]);
        $self->end_date($_->[1]);
        my $message_hash = $self->get_noaa_data();
        # print STDERR Dumper $message_hash;
        if ($message_hash->{status} eq '400') {
            return {error => $message_hash->{message}};
        }

        foreach (@{$message_hash->{results}}) {
            $weather_hash{$_->{date}}->{$_->{datatype}} = $_->{value};
        }
    }
    return \%weather_hash;
}

sub get_temperature_averaged_gdd {
    my $self = shift;
    my $gdd_base_temperature = shift || '50'; #For Maize use 50
    my $result = 0;

    $self->data_types(['TMIN','TMAX']);

    my $weather_hash = $self->do_query_max_one_year();

    foreach (values %$weather_hash) {
        if (defined($_->{TMIN}) && defined($_->{TMAX})) {
            #TMAX and TMIN are in tenths of C
            my $tmax_f = (9/5)*($_->{TMAX}/10) + 32;
            my $tmin_f = (9/5)*($_->{TMIN}/10) + 32;
            my $gdd_accumulation = (($tmax_f + $tmin_f)/2) - $gdd_base_temperature;
            if ($gdd_accumulation > 0) {
                $result = $result + $gdd_accumulation;
            }
        }
    }

    return {gdd => round($result) };
}

sub get_averaged_precipitation {
    my $self = shift;
    my $result = 0;

    $self->data_types(['PRCP']);

    my $weather_hash = $self->do_query_max_one_year();

    foreach (values %$weather_hash) {
        if (defined($_->{PRCP})) {
            $result = $result + $_->{PRCP};
        }
    }

    return $result;
}

sub get_daily_values {
    my $self = shift;
    my $result;

    my $weather_hash = $self->do_query_max_one_year();

    while (my ($date, $do) = each %$weather_hash) {
        while (my ($data_type, $value) = each %$do) {
            $result->{$date}->{$data_type} = $value;
        }
    }
    my @sorted_dates = sort keys %$result;

    return ($result, \@sorted_dates);
}

1;
