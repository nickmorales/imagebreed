
=head1 NAME

SGN::Controller::AJAX::GenotypesVCFUpload - a REST controller class to provide the
backend for uploading genotype VCF files

=head1 DESCRIPTION

Uploading Genotype VCF

=head1 AUTHOR

=cut

package SGN::Controller::AJAX::GenotypesVCFUpload;

use Moose;
use Try::Tiny;
use DateTime;
use File::Slurp;
use File::Spec::Functions;
use File::Copy;
use Data::Dumper;
use List::MoreUtils qw /any /;
use CXGN::BreederSearch;
use CXGN::UploadFile;
use CXGN::Genotype::ParseUpload;
use CXGN::Genotype::StoreVCFGenotypes;
use CXGN::Login;
use CXGN::People::Person;
use CXGN::Genotype::Protocol;
use CXGN::Genotype::GRM;
use File::Basename qw | basename dirname|;
use File::Temp 'tempfile';
use JSON;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON'  },
   );


sub upload_genotype_verify :  Path('/ajax/genotype/upload') : ActionClass('REST') { }
sub upload_genotype_verify_POST : Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $transpose_vcf_for_loading = 1;
    my @error_status;
    my @success_status;

    my ($user_id, $user_name, $user_role) = _check_user_login_genotypes_vcf_upload($c, 'submitter', 0, 0);

    print STDERR Dumper $c->req->params();
    my $project_id = $c->req->param('upload_genotype_project_id') || undef;
    my $protocol_id = $c->req->param('upload_genotype_protocol_id') || undef;
    my $organism_species = $c->req->param('upload_genotypes_species_name_input');
    my $protocol_description = $c->req->param('upload_genotypes_protocol_description_input');
    my $project_name = $c->req->param('upload_genotype_vcf_project_name');
    my $location_id = $c->req->param('upload_genotype_location_select');
    my $year = $c->req->param('upload_genotype_year_select');
    my $breeding_program_id = $c->req->param('upload_genotype_breeding_program_select');
    my $obs_type = $c->req->param('upload_genotype_vcf_observation_type');
    my $genotyping_facility = $c->req->param('upload_genotype_vcf_facility_select');
    my $description = $c->req->param('upload_genotype_vcf_project_description');
    my $protocol_name = $c->req->param('upload_genotype_vcf_protocol_name');
    my $contains_igd = $c->req->param('upload_genotype_vcf_include_igd_numbers');
    my $reference_genome_name = $c->req->param('upload_genotype_vcf_reference_genome_name');
    my $add_new_accessions = $c->req->param('upload_genotype_add_new_accessions');
    my $add_accessions;
    if ($add_new_accessions){
        $add_accessions = 1;
        $obs_type = 'accession';
    }
    my $include_igd_numbers;
    if ($contains_igd){
        $include_igd_numbers = 1;
    }
    my $include_lab_numbers;
    my $accept_warnings_input = $c->req->param('upload_genotype_accept_warnings');
    my $accept_warnings;
    if ($accept_warnings_input){
        $accept_warnings = 1;
    }

    #archive uploaded file
    my $upload_vcf = $c->req->upload('upload_genotype_vcf_file_input');
    my $upload_tassel_hdf5 = $c->req->upload('upload_genotype_tassel_hdf5_file_input');
    my $upload_transposed_vcf = $c->req->upload('upload_genotype_transposed_vcf_file_input');
    my $upload_intertek_genotypes = $c->req->upload('upload_genotype_intertek_file_input');
    my $upload_inteterk_marker_info = $c->req->upload('upload_genotype_intertek_snp_file_input');
    my $upload_ssr_data = $c->req->upload('upload_genotype_ssr_file_input');
    my $upload_grm_data = $c->req->upload('upload_genotype_grm_file_input');

    my $is_from_grm = $c->req->param('upload_genotype_data_is_from_grm') eq '1' ? 1 : 0;
    my $is_from_grm_trial_ids = $c->req->param('upload_genotype_is_from_grm_field_trial_ids_json') ? decode_json $c->req->param('upload_genotype_is_from_grm_field_trial_ids_json') : [];
    my $is_from_grm_accession_list_id = $c->req->param('upload_genotype_is_from_grm_accession_list_select_div_list_select');
    my $is_from_grm_protocol_name = $c->req->param('upload_genotype_is_from_grm_protocol_name');
    my $is_from_grm_protocol_desc = $c->req->param('upload_genotype_is_from_grm_protocol_desc');
    my $is_from_grm_location_id = $c->req->param('upload_genotype_is_from_grm_location_select');
    my $is_from_grm_compute_from_parents = $c->req->param('upload_genotype_data_is_from_grm_compute_from_parents') && $c->req->param('upload_genotype_data_is_from_grm_compute_from_parents') eq 'yes' ? 1 : 0;

    if ($is_from_grm && !$is_from_grm_trial_ids && scalar(@$is_from_grm_trial_ids)==0) {
        $c->stash->{rest} = { error => 'If computing GRM please give a field trial id!' };
        $c->detach();
    }
    if ($is_from_grm && !$is_from_grm_protocol_name) {
        $c->stash->{rest} = { error => 'If computing GRM please give a GRM protocol name!' };
        $c->detach();
    }
    if ($is_from_grm && !$is_from_grm_protocol_desc) {
        $c->stash->{rest} = { error => 'If computing GRM please give a GRM protocol description!' };
        $c->detach();
    }
    if ($is_from_grm && !$is_from_grm_location_id) {
        $c->stash->{rest} = { error => 'If computing GRM please give a GRM protocol location!' };
        $c->detach();
    }
    if ($is_from_grm) {
        $accept_warnings = 1;
    }

    if (defined($upload_vcf) && defined($upload_intertek_genotypes)) {
        $c->stash->{rest} = { error => 'Do not try to upload both VCF and Intertek at the same time!' };
        $c->detach();
    }
    if (defined($upload_vcf) && defined($upload_grm_data)) {
        $c->stash->{rest} = { error => 'Do not try to upload both VCF and GRM data at the same time!' };
        $c->detach();
    }
    if (defined($upload_vcf) && defined($upload_tassel_hdf5)) {
        $c->stash->{rest} = { error => 'Do not try to upload both VCF and Tassel HDF5 at the same time!' };
        $c->detach();
    }
    if (defined($upload_intertek_genotypes) && defined($upload_tassel_hdf5)) {
        $c->stash->{rest} = { error => 'Do not try to upload both Intertek and Tassel HDF5 at the same time!' };
        $c->detach();
    }
    if (defined($upload_intertek_genotypes) && !defined($upload_inteterk_marker_info)) {
        $c->stash->{rest} = { error => 'To upload Intertek genotype data please provide both the Grid Genotypes File and the Marker Info File.' };
        $c->detach();
    }

    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();

    my $upload_original_name;
    my $upload_tempfile;
    my $subdirectory;
    my $parser_plugin = '';
    if ($upload_vcf) {
        $upload_original_name = $upload_vcf->filename();
        $upload_tempfile = $upload_vcf->tempname;
        $subdirectory = "genotype_vcf_upload";
        $parser_plugin = 'VCF';

        if ($transpose_vcf_for_loading) {
            my $dir = $c->tempfiles_subdir('/genotype_data_upload_transpose_VCF');
            my $temp_file_transposed = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'genotype_data_upload_transpose_VCF/fileXXXX');

            open (my $Fout, "> :encoding(UTF-8)", $temp_file_transposed) || die "Can't open file $temp_file_transposed\n";
            open (my $F, "< :encoding(UTF-8)", $upload_tempfile) or die "Can't open file $upload_tempfile \n";
            my @outline;
            my $lastcol;
            while (<$F>) {
                $_ =~ s/\r//g;
                if ($_ =~ m/^\##/) {
                    print $Fout $_;
                } else {
                    chomp;
                    my @line = split /\t/;
                    my $oldlastcol = $lastcol;
                    $lastcol = $#line if $#line > $lastcol;
                    for (my $i=$oldlastcol; $i < $lastcol; $i++) {
                        if ($oldlastcol) {
                            $outline[$i] = "\t" x $oldlastcol;
                        }
                    }
                    for (my $i=0; $i <=$lastcol; $i++) {
                        $outline[$i] .= "$line[$i]\t"
                    }
                }
            }
            for (my $i=0; $i <= $lastcol; $i++) {
                $outline[$i] =~ s/\s*$//g;
                print $Fout $outline[$i]."\n";
            }
            close($F);
            close($Fout);
            $upload_tempfile = $temp_file_transposed;
            $upload_original_name = basename($temp_file_transposed);
            $parser_plugin = 'transposedVCF';
        }
    }
    if ($upload_transposed_vcf) {
        $upload_original_name = $upload_transposed_vcf->filename();
        $upload_tempfile = $upload_transposed_vcf->tempname;
        $subdirectory = "genotype_transposed_vcf_upload";
        $parser_plugin = 'transposedVCF';
    }
    if ($upload_tassel_hdf5) {
        $upload_original_name = $upload_tassel_hdf5->filename();
        $upload_tempfile = $upload_tassel_hdf5->tempname;
        $subdirectory = "genotype_tassel_hdf5_upload";

        my $uploader = CXGN::UploadFile->new({
            tempfile => $upload_tempfile,
            subdirectory => $subdirectory,
            archive_path => $c->config->{archive_path},
            archive_filename => $upload_original_name,
            timestamp => $timestamp,
            user_id => $user_id,
            user_role => $user_role
        });
        my $archived_tassel_hdf5_file = $uploader->archive();
        my $md5 = $uploader->get_md5($archived_tassel_hdf5_file);
        if (!$archived_tassel_hdf5_file) {
            $c->stash->{rest} = { error => "Could not save file $upload_original_name in archive." };
            $c->detach();
        }
        unlink $upload_tempfile;

        my $output_dir = $c->tempfiles_subdir('/genotype_upload_tassel_hdf5');
        $upload_tempfile = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'genotype_upload_tassel_hdf5/temp_vcf_XXXX').".vcf";
        my $cmd = "perl ".$c->config->{rootpath}."/tassel-5-standalone/run_pipeline.pl -Xmx12g -h5 ".$archived_tassel_hdf5_file." -export ".$upload_tempfile." -exportType VCF";
        print STDERR Dumper $cmd;
        my $status = system($cmd);

        my $temp_file_transposed = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'genotype_upload_tassel_hdf5/fileXXXX');

        open (my $Fout, "> :encoding(UTF-8)", $temp_file_transposed) || die "Can't open file $temp_file_transposed\n";
        open (my $F, "< :encoding(UTF-8)", $upload_tempfile) or die "Can't open file $upload_tempfile \n";
        my @outline;
        my $lastcol;
        while (<$F>) {
	    $_ =~ s/\r//g;
            if ($_ =~ m/^\##/) {
                print $Fout $_;
            } else {
                chomp;
                my @line = split /\t/;
                my $oldlastcol = $lastcol;
                $lastcol = $#line if $#line > $lastcol;
                for (my $i=$oldlastcol; $i < $lastcol; $i++) {
                    if ($oldlastcol) {
                        $outline[$i] = "\t" x $oldlastcol;
                    }
                }
                for (my $i=0; $i <=$lastcol; $i++) {
                    $outline[$i] .= "$line[$i]\t"
                }
            }
        }
        for (my $i=0; $i <= $lastcol; $i++) {
            $outline[$i] =~ s/\s*$//g;
            print $Fout $outline[$i]."\n";
        }
        close($F);
        close($Fout);
        $upload_tempfile = $temp_file_transposed;
        $upload_original_name = basename($temp_file_transposed);

        $subdirectory = "genotype_transposed_vcf_upload";
        $parser_plugin = 'transposedVCF';
    }

    my $archived_intertek_marker_info_file;
    if ($upload_intertek_genotypes) {
        $upload_original_name = $upload_intertek_genotypes->filename();
        $upload_tempfile = $upload_intertek_genotypes->tempname;
        $subdirectory = "genotype_intertek_upload";
        $parser_plugin = 'IntertekCSV';

        if ($obs_type eq 'accession') {
            $include_lab_numbers = 1;
        }

        my $upload_inteterk_marker_info_original_name = $upload_inteterk_marker_info->filename();
        my $upload_inteterk_marker_info_tempfile = $upload_inteterk_marker_info->tempname();

        my $uploader = CXGN::UploadFile->new({
            tempfile => $upload_inteterk_marker_info_tempfile,
            subdirectory => $subdirectory,
            archive_path => $c->config->{archive_path},
            archive_filename => $upload_inteterk_marker_info_original_name,
            timestamp => $timestamp,
            user_id => $user_id,
            user_role => $user_role
        });
        $archived_intertek_marker_info_file = $uploader->archive();
        my $md5 = $uploader->get_md5($archived_intertek_marker_info_file);
        if (!$archived_intertek_marker_info_file) {
            push @error_status, "Could not save file $upload_inteterk_marker_info_original_name in archive.";
            return (\@success_status, \@error_status);
        } else {
            push @success_status, "File $upload_inteterk_marker_info_original_name saved in archive.";
        }
        unlink $upload_inteterk_marker_info_tempfile;
    }

    if ($upload_ssr_data) {
        $upload_original_name = $upload_ssr_data->filename();
        $upload_tempfile = $upload_ssr_data->tempname;
        $subdirectory = "ssr_data_upload";
        $parser_plugin = 'SSRExcel';
    }

    if ($upload_grm_data) {
        $upload_original_name = $upload_grm_data->filename();
        $upload_tempfile = $upload_grm_data->tempname;
        $subdirectory = "grm_data_upload";
        $parser_plugin = 'GRMTSV';
    }

    #if protocol_id provided, a new one will not be created
    my $protocol_is_grm;
    if ($protocol_id){
        my $protocol = CXGN::Genotype::Protocol->new({
            bcs_schema => $schema,
            nd_protocol_id => $protocol_id
        });
        $organism_species = $protocol->species_name;
        $obs_type = $protocol->sample_observation_unit_type_name;
        $reference_genome_name = $protocol->reference_genome_name;
        $protocol_is_grm = $protocol->is_grm_protocol;
    }

    my $organism_q = "SELECT organism_id FROM organism WHERE species = ?";
    my @found_organisms;
    my $h = $schema->storage->dbh()->prepare($organism_q);
    $h->execute($organism_species);
    while (my ($organism_id) = $h->fetchrow_array()){
        push @found_organisms, $organism_id;
    }
    if (scalar(@found_organisms) == 0){
        $c->stash->{rest} = { error => 'The organism species you provided is not in the database! Please contact us.' };
        $c->detach();
    }
    if (scalar(@found_organisms) > 1){
        $c->stash->{rest} = { error => 'The organism species you provided is not unique in the database! Please contact us.' };
        $c->detach();
    }
    my $organism_id = $found_organisms[0];

    my $archived_filename_with_path;
    my $parser;
    if (!$is_from_grm) {
        my $uploader = CXGN::UploadFile->new({
            tempfile => $upload_tempfile,
            subdirectory => $subdirectory,
            archive_path => $c->config->{archive_path},
            archive_filename => $upload_original_name,
            timestamp => $timestamp,
            user_id => $user_id,
            user_role => $user_role
        });
        $archived_filename_with_path = $uploader->archive();
        my $md5 = $uploader->get_md5($archived_filename_with_path);
        if (!$archived_filename_with_path) {
            $c->stash->{rest} = { error => 'Could not save file $upload_original_name in archive.' };
            $c->detach();
        }
        unlink $upload_tempfile;

        $parser = CXGN::Genotype::ParseUpload->new({
            chado_schema => $schema,
            filename => $archived_filename_with_path,
            filename_intertek_marker_info => $archived_intertek_marker_info_file,
            observation_unit_type_name => $obs_type,
            organism_id => $organism_id,
            create_missing_observation_units_as_accessions => $add_accessions,
            igd_numbers_included => $include_igd_numbers,
            # lab_numbers_included => $include_lab_numbers
        });
        $parser->load_plugin($parser_plugin);
    }

    my $dir = $c->tempfiles_subdir('/genotype_data_upload_SQL_COPY');
    my $temp_file_sql_copy = $c->config->{basepath}."/".$c->tempfile( TEMPLATE => 'genotype_data_upload_SQL_COPY/fileXXXX');

    my $store_args = {
        bcs_schema=>$schema,
        metadata_schema=>$metadata_schema,
        phenome_schema=>$phenome_schema,
        observation_unit_type_name=>$obs_type,
        project_id=>$project_id,
        protocol_id=>$protocol_id,
        genotyping_facility=>$genotyping_facility, #projectprop
        breeding_program_id=>$breeding_program_id, #project_rel
        project_year=>$year, #projectprop
        project_location_id=>$location_id, #ndexperiment and projectprop
        project_name=>$project_name, #project_attr
        project_description=>$description, #project_attr
        protocol_name=>$protocol_name,
        protocol_description=>$protocol_description,
        organism_id=>$organism_id,
        igd_numbers_included=>$include_igd_numbers,
        lab_numbers_included=>$include_lab_numbers,
        user_id=>$user_id,
        archived_filename=>$archived_filename_with_path,
        archived_file_type=>'genotype_vcf', #can be 'genotype_vcf' or 'genotype_dosage' to disntiguish genotyprop between old dosage only format and more info vcf format
        temp_file_sql_copy=>$temp_file_sql_copy
    };

    my $return;
    #For VCF files, memory was an issue so we parse them with an iterator
    if ($parser_plugin eq 'VCF' || $parser_plugin eq 'transposedVCF') {
        $store_args->{genotyping_data_type} = 'SNP';

        my $parser_return = $parser->parse_with_iterator();

        if ($parser->get_parse_errors()) {
            my $return_error = '';
            my $parse_errors = $parser->get_parse_errors();
            print STDERR Dumper $parse_errors;
            foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                $return_error=$return_error.$error_string."<br>";
            }
            $c->stash->{rest} = {error_string => $return_error, missing_stocks => $parse_errors->{'missing_stocks'}};
            $c->detach();
        }

        my $protocol = $parser->protocol_data();
        my $observation_unit_names_all = $parser->observation_unit_names();
        $store_args->{observation_unit_uniquenames} = $observation_unit_names_all;

        if ($parser_plugin eq 'VCF') {
            $store_args->{marker_by_marker_storage} = 1;
        }

        $protocol->{'reference_genome_name'} = $reference_genome_name;
        $protocol->{'species_name'} = $organism_species;
        my $store_genotypes;
        my ($observation_unit_names, $genotype_info) = $parser->next();
        if (scalar(keys %$genotype_info) > 0) {
            #print STDERR Dumper [$observation_unit_names, $genotype_info];
            print STDERR "Parsing first genotype and extracting protocol info... \n";

            $store_args->{protocol_info} = $protocol;
            $store_args->{genotype_info} = $genotype_info;

            $store_genotypes = CXGN::Genotype::StoreVCFGenotypes->new($store_args);
            my $verified_errors = $store_genotypes->validate();
            # print STDERR Dumper $verified_errors;
            if (scalar(@{$verified_errors->{error_messages}}) > 0){
                my $error_string = join ', ', @{$verified_errors->{error_messages}};
                $c->stash->{rest} = { error => "There exist errors in your file. $error_string", missing_stocks => $verified_errors->{missing_stocks} };
                $c->detach();
            }
            if (scalar(@{$verified_errors->{warning_messages}}) > 0){
                #print STDERR Dumper $verified_errors->{warning_messages};
                my $warning_string = join ', ', @{$verified_errors->{warning_messages}};
                if (!$accept_warnings){
                    $c->stash->{rest} = { warning => $warning_string, previous_genotypes_exist => $verified_errors->{previous_genotypes_exist} };
                    $c->detach();
                }
            }

            if ($protocol_id) {
                my @protocol_match_errors;
                my $stored_protocol = CXGN::Genotype::Protocol->new({
                    bcs_schema => $schema,
                    nd_protocol_id => $protocol_id
                });
                my $stored_markers = $stored_protocol->markers();

                while (my ($marker_name, $marker_obj) = each %$stored_markers) {
                    my $new_marker_obj = $protocol->{markers}->{$marker_name};
                    while (my ($key, $value) = each %$marker_obj) {
                        if ($value ne $new_marker_obj->{$key}) {
                            push @protocol_match_errors, "Marker $marker_name in the previously loaded protocol has $value for $key, but in your file now shows ".$new_marker_obj->{$key};
                        }
                    }
                }

                if (scalar(@protocol_match_errors) > 0){
                    my $warning_string = join ', ', @protocol_match_errors;
                    if (!$accept_warnings){
                        $c->stash->{rest} = { warning => $warning_string };
                        $c->detach();
                    }
                }
            }

            $store_genotypes->store_metadata();
            $store_genotypes->store_identifiers();
        }

        print STDERR "Done loading first line, moving on...\n";

        my $continue_iterate = 1;
        while ($continue_iterate == 1) {
            my ($observation_unit_names, $genotype_info) = $parser->next();
            if (scalar(keys %$genotype_info) > 0) {
                $store_genotypes->genotype_info($genotype_info);
                $store_genotypes->observation_unit_uniquenames($observation_unit_names);
                $store_genotypes->store_identifiers();
            } else {
                $continue_iterate = 0;
                last;
            }
        }
        $return = $store_genotypes->store_genotypeprop_table();
    }
    #For smaller Intertek files, memory is not usually an issue so can parse them without iterator
    elsif ($parser_plugin eq 'GridFileIntertekCSV' || $parser_plugin eq 'IntertekCSV') {
        my $parsed_data = $parser->parse();
        my $parse_errors;
        if (!$parsed_data) {
            my $return_error = '';
            if (!$parser->has_parse_errors() ){
                $return_error = "Could not get parsing errors";
                $c->stash->{rest} = {error_string => $return_error,};
            } else {
                $parse_errors = $parser->get_parse_errors();
                #print STDERR Dumper $parse_errors;
                foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                    $return_error=$return_error.$error_string."<br>";
                }
            }
            $c->stash->{rest} = {error_string => $return_error, missing_stocks => $parse_errors->{'missing_stocks'}};
            $c->detach();
        }
        #print STDERR Dumper $parsed_data;
        my $observation_unit_uniquenames = $parsed_data->{observation_unit_uniquenames};
        my $genotype_info = $parsed_data->{genotypes_info};
        my $protocol_info = $parsed_data->{protocol_info};
        $protocol_info->{'reference_genome_name'} = $reference_genome_name;
        $protocol_info->{'species_name'} = $organism_species;

        $store_args->{genotyping_data_type} = 'SNP';
        $store_args->{protocol_info} = $protocol_info;
        $store_args->{genotype_info} = $genotype_info;
        $store_args->{observation_unit_uniquenames} = $observation_unit_uniquenames;

        my $store_genotypes = CXGN::Genotype::StoreVCFGenotypes->new($store_args);
        my $verified_errors = $store_genotypes->validate();
        if (scalar(@{$verified_errors->{error_messages}}) > 0){
            my $error_string = join ', ', @{$verified_errors->{error_messages}};
            $c->stash->{rest} = { error => "There exist errors in your file. $error_string", missing_stocks => $verified_errors->{missing_stocks} };
            $c->detach();
        }
        if (scalar(@{$verified_errors->{warning_messages}}) > 0){
            #print STDERR Dumper $verified_errors->{warning_messages};
            my $warning_string = join ', ', @{$verified_errors->{warning_messages}};
            if (!$accept_warnings){
                $c->stash->{rest} = { warning => $warning_string, previous_genotypes_exist => $verified_errors->{previous_genotypes_exist} };
                $c->detach();
            }
        }

        if ($protocol_id) {
            my @protocol_match_errors;
            my $stored_protocol = CXGN::Genotype::Protocol->new({
                bcs_schema => $schema,
                nd_protocol_id => $protocol_id
            });
            my $stored_markers = $stored_protocol->markers();

            while (my ($marker_name, $marker_obj) = each %$stored_markers) {
                my $new_marker_obj = $protocol_info->{markers}->{$marker_name};
                while (my ($key, $value) = each %$marker_obj) {
                    if ($value ne $new_marker_obj->{$key}) {
                        push @protocol_match_errors, "Marker $marker_name in the previously loaded protocol has $value for $key, but in your file now shows ".$new_marker_obj->{$key};
                    }
                }
            }

            if (scalar(@protocol_match_errors) > 0){
                my $warning_string = join ', ', @protocol_match_errors;
                if (!$accept_warnings){
                    $c->stash->{rest} = { warning => $warning_string };
                    $c->detach();
                }
            }
        }

        $store_genotypes->store_metadata();
        $store_genotypes->store_identifiers();
        $return = $store_genotypes->store_genotypeprop_table();

    } elsif ($parser_plugin eq 'SSRExcel') {
        my $parsed_data = $parser->parse();
        # print STDERR "SSR PARSED DATA =".Dumper($parsed_data)."\n";
        my $parse_errors;
        if (!$parsed_data) {
            my $return_error = '';
            if (!$parser->has_parse_errors() ){
                $return_error = "Could not get parsing errors";
                $c->stash->{rest} = {error_string => $return_error,};
            } else {
                $parse_errors = $parser->get_parse_errors();
                #print STDERR Dumper $parse_errors;
                foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                    $return_error=$return_error.$error_string."<br>";
                }
            }
            $c->stash->{rest} = {error_string => $return_error, missing_stocks => $parse_errors->{'missing_stocks'}};
            $c->detach();
        }

        my $observation_unit_uniquenames = $parsed_data->{observation_unit_uniquenames};
        my $genotype_info = $parsed_data->{genotypes_info};
        my $protocolprop_info = $parsed_data->{protocol_info};
        $protocolprop_info->{sample_observation_unit_type_name} = $obs_type;

        $store_args->{genotype_info} = $genotype_info;
        $store_args->{observation_unit_uniquenames} = $observation_unit_uniquenames;
        $store_args->{protocol_info} = $protocolprop_info;
        $store_args->{observation_unit_type_name} = $obs_type;
        $store_args->{genotyping_data_type} = 'ssr';

        my $store_genotypes = CXGN::Genotype::StoreVCFGenotypes->new($store_args);
        my $verified_errors = $store_genotypes->validate();
        if (scalar(@{$verified_errors->{error_messages}}) > 0){
            my $error_string = join ', ', @{$verified_errors->{error_messages}};
            $c->stash->{rest} = { error => "There exist errors in your file. $error_string", missing_stocks => $verified_errors->{missing_stocks} };
            $c->detach();
        }
        if (scalar(@{$verified_errors->{warning_messages}}) > 0){
            #print STDERR Dumper $verified_errors->{warning_messages};
            my $warning_string = join ', ', @{$verified_errors->{warning_messages}};
            if (!$accept_warnings){
                $c->stash->{rest} = { warning => $warning_string, previous_genotypes_exist => $verified_errors->{previous_genotypes_exist} };
                $c->detach();
            }
        }

        if ($protocol_id) {
            my $genotypes_search = CXGN::Genotype::Search->new({
                bcs_schema=>$schema,
                people_schema=>$people_schema,
                protocol_id_list=>[$protocol_id],
                genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
            });
            my $result = $genotypes_search->get_pcr_genotype_info();
            my $protocol_marker_names = $result->{'marker_names'};
            my $previous_protocol_marker_names = decode_json $protocol_marker_names;
            my %previous_marker_map = map {$_ => 1} @$previous_protocol_marker_names;

            my @protocol_match_errors;
            foreach (@{$protocolprop_info->{marker_names}}) {
                if (!exists($previous_marker_map{$_})) {
                    push @protocol_match_errors, "Marker $_ does not exist in the previously loaded protocol";
                }
            }

            if (scalar(@protocol_match_errors) > 0){
                my $warning_string = join ', ', @protocol_match_errors;
                if (!$accept_warnings){
                    $c->stash->{rest} = { warning => $warning_string };
                    $c->detach();
                }
            }
        }

        $store_genotypes->store_metadata();
        $return = $store_genotypes->store_identifiers();

    } elsif ($parser_plugin eq 'GRMTSV') {
        my $parsed_data = $parser->parse();
        # print STDERR "GRM TSV PARSED DATA =".Dumper($parsed_data)."\n";
        my $parse_errors;
        if (!$parsed_data) {
            my $return_error = '';
            if (!$parser->has_parse_errors() ){
                $return_error = "Could not get parsing errors";
                $c->stash->{rest} = {error_string => $return_error,};
            } else {
                $parse_errors = $parser->get_parse_errors();
                #print STDERR Dumper $parse_errors;
                foreach my $error_string (@{$parse_errors->{'error_messages'}}){
                    $return_error=$return_error.$error_string."<br>";
                }
            }
            $c->stash->{rest} = {error_string => $return_error, missing_stocks => $parse_errors->{'missing_stocks'}};
            $c->detach();
        }

        my $grm_info = $parsed_data->{genotypes_info};
        my $observation_unit_names_all = $parsed_data->{observation_unit_uniquenames};

        my $store_args = {
            bcs_schema=>$schema,
            metadata_schema=>$metadata_schema,
            phenome_schema=>$phenome_schema,
            observation_unit_type_name=>$obs_type,
            project_id=>$project_id,
            protocol_id=>$protocol_id,
            genotyping_facility=>$genotyping_facility, #projectprop
            breeding_program_id=>$breeding_program_id, #project_rel
            project_year=>$year, #projectprop
            project_location_id=>$location_id, #ndexperiment and projectprop
            project_name=>$project_name, #project_attr
            project_description=>$description, #project_attr
            protocol_name=>$protocol_name,
            protocol_description=>$protocol_description,
            organism_id=>$organism_id,
            igd_numbers_included=>$include_igd_numbers,
            lab_numbers_included=>$include_lab_numbers,
            user_id=>$user_id,
            archived_filename=>$archived_filename_with_path,
            archived_file_type=>'genotype_vcf', #can be 'genotype_vcf' or 'genotype_dosage' to disntiguish genotyprop between old dosage only format and more info vcf format
            temp_file_sql_copy=>$temp_file_sql_copy,
            genotyping_data_type=>'GRM',
            observation_unit_uniquenames=>$observation_unit_names_all,
            protocol_info=>{
                reference_genome_name => $reference_genome_name,
                species_name => $organism_species,
                is_grm => 1
            },
            genotype_info=>$grm_info
        };

        my $store_genotypes = CXGN::Genotype::StoreVCFGenotypes->new($store_args);
        my $verified_errors = $store_genotypes->validate();
        # print STDERR Dumper $verified_errors;
        if (scalar(@{$verified_errors->{error_messages}}) > 0){
            my $error_string = join ', ', @{$verified_errors->{error_messages}};
            $c->stash->{rest} = { error => "There exist errors in your file. $error_string", missing_stocks => $verified_errors->{missing_stocks} };
            $c->detach();
        }
        if (scalar(@{$verified_errors->{warning_messages}}) > 0){
            #print STDERR Dumper $verified_errors->{warning_messages};
            my $warning_string = join ', ', @{$verified_errors->{warning_messages}};
            if (!$accept_warnings){
                $c->stash->{rest} = { warning => $warning_string, previous_genotypes_exist => $verified_errors->{previous_genotypes_exist} };
                $c->detach();
            }
        }

        $store_genotypes->store_metadata();
        $return = $store_genotypes->store_identifiers();

    } elsif ($is_from_grm) {
        #For creating a GRM and saving it as a GRM genotyping protocol. Similar to GRMTSV but creating GRM here.

        if ($protocol_is_grm) {
            $c->stash->{rest} = { error => 'You cannot select a GRM genotyping protocol here! Select a genotyping protocol with genotyping marker data!' };
            $c->detach();
        }

        my $shared_cluster_dir_config = $c->config->{cluster_shared_tempdir};
        my $tmp_grm_dir = $shared_cluster_dir_config."/tmp_genotype_download_grm";
        mkdir $tmp_grm_dir if ! -d $tmp_grm_dir;
        my ($grm_tempfile_fh, $grm_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);
        my ($grm_out_tempfile_fh, $grm_out_tempfile) = tempfile("drone_stats_download_grm_XXXXX", DIR=> $tmp_grm_dir);

        my $is_from_grm_accession_ids = [];
        my $is_from_grm_accession_names = [];
        if ($is_from_grm_accession_list_id) {
            my $list = CXGN::List->new({
                dbh => $schema->storage->dbh,
                list_id => $is_from_grm_accession_list_id
            });
            $is_from_grm_accession_names = $list->elements();
            my $tf = CXGN::List::Transform->new();
            $is_from_grm_accession_ids = $tf->transform($schema, 'stocks_2_stock_ids', $is_from_grm_accession_names)->{transform};
        }

        my $geno = CXGN::Genotype::GRM->new({
            bcs_schema=>$schema,
            grm_temp_file=>$grm_tempfile,
            people_schema=>$people_schema,
            cache_root=>$c->config->{cache_file_path},
            trial_id_list=>$is_from_grm_trial_ids,
            accession_id_list=>$is_from_grm_accession_ids,
            protocol_id=>$protocol_id,
            get_grm_for_parental_accessions=>$is_from_grm_compute_from_parents,
            download_format=>'three_column_reciprocal_uniquenames',
            genotypeprop_hash_dosage_key=>$c->config->{genotyping_protocol_dosage_key}
            # minor_allele_frequency=>$minor_allele_frequency,
            # marker_filter=>$marker_filter,
            # individuals_filter=>$individuals_filter
        });
        my $grm_data = $geno->download_grm(
            'data',
            $shared_cluster_dir_config,
            $c->config->{backend},
            $c->config->{cluster_host},
            $c->config->{'web_cluster_queue'},
            $c->config->{basepath}
        );
        if (scalar(@$is_from_grm_accession_names) == 0) {
            $is_from_grm_accession_names = $geno->accession_name_list();
        }

        open(my $F2, ">", $grm_out_tempfile) || die "Can't open file ".$grm_out_tempfile;
            print $F2 $grm_data;
        close($F2);

        my @grm_lines = split "\n", $grm_data;
        my %grm_info;
        foreach (@grm_lines) {
            my @line = split "\t", $_;
            $grm_info{$line[0]}->{$line[1]} = $line[2];
        }
        # print STDERR Dumper \%grm_info;

        my $uploader = CXGN::UploadFile->new({
            tempfile => $grm_out_tempfile,
            subdirectory => "grm_data_trial_created",
            archive_path => $c->config->{archive_path},
            archive_filename => basename($grm_out_tempfile),
            timestamp => $timestamp,
            user_id => $user_id,
            user_role => $user_role
        });
        $archived_filename_with_path = $uploader->archive();
        my $md5 = $uploader->get_md5($archived_filename_with_path);
        if (!$archived_filename_with_path) {
            $c->stash->{rest} = { error => 'Could not save file $upload_original_name in archive.' };
            $c->detach();
        }
        unlink $grm_out_tempfile;

        my $store_args = {
            bcs_schema=>$schema,
            metadata_schema=>$metadata_schema,
            phenome_schema=>$phenome_schema,
            observation_unit_type_name=>$obs_type,
            is_from_grm_trial_ids=>$is_from_grm_trial_ids,
            project_id=>$project_id,
            #protocol_id=>$protocol_id,
            genotyping_facility=>$genotyping_facility, #projectprop
            breeding_program_id=>$breeding_program_id, #project_rel
            project_year=>$year, #projectprop
            project_location_id=>$is_from_grm_location_id, #ndexperiment and projectprop
            project_name=>$project_name, #project_attr
            project_description=>$is_from_grm_protocol_desc, #project_attr
            protocol_name=>$is_from_grm_protocol_name,
            protocol_description=>$is_from_grm_protocol_desc,
            organism_id=>$organism_id,
            #igd_numbers_included=>$include_igd_numbers,
            #lab_numbers_included=>$include_lab_numbers,
            user_id=>$user_id,
            archived_filename=>$archived_filename_with_path,
            archived_file_type=>'genotype_vcf', #can be 'genotype_vcf' or 'genotype_dosage' to disntiguish genotyprop between old dosage only format and more info vcf format
            temp_file_sql_copy=>$temp_file_sql_copy,
            genotyping_data_type=>'GRM',
            observation_unit_uniquenames=>$is_from_grm_accession_names,
            protocol_info=>{
                reference_genome_name => $reference_genome_name,
                species_name => $organism_species,
                is_grm => 1,
                is_grm_trial_created => 1
            },
            genotype_info=>\%grm_info
        };

        my $store_genotypes = CXGN::Genotype::StoreVCFGenotypes->new($store_args);
        my $verified_errors = $store_genotypes->validate();
        # print STDERR Dumper $verified_errors;
        if (scalar(@{$verified_errors->{error_messages}}) > 0){
            my $error_string = join ', ', @{$verified_errors->{error_messages}};
            $c->stash->{rest} = { error => "There exist errors in your file. $error_string", missing_stocks => $verified_errors->{missing_stocks} };
            $c->detach();
        }
        if (scalar(@{$verified_errors->{warning_messages}}) > 0){
            #print STDERR Dumper $verified_errors->{warning_messages};
            my $warning_string = join ', ', @{$verified_errors->{warning_messages}};
            if (!$accept_warnings){
                $c->stash->{rest} = { warning => $warning_string, previous_genotypes_exist => $verified_errors->{previous_genotypes_exist} };
                $c->detach();
            }
        }

        $store_genotypes->store_metadata();
        $return = $store_genotypes->store_identifiers();

    } else {
        print STDERR "Parser plugin $parser_plugin not recognized!\n";
        $c->stash->{rest} = { error => "Parser plugin $parser_plugin not recognized!" };
        $c->detach();
    }

    my $basepath = $c->config->{basepath};
    my $dbhost = $c->config->{dbhost};
    my $dbname = $c->config->{dbname};
    my $dbuser = $c->config->{dbuser};
    my $dbpass = $c->config->{dbpass};
    my $bs = CXGN::BreederSearch->new( { dbh=>$c->dbc->dbh, dbname=>$dbname, } );
    my $refresh = $bs->refresh_matviews($dbhost, $dbname, $dbuser, $dbpass, 'fullview', 'nonconcurrent', $basepath);

    # Rebuild and refresh the materialized_markerview table
    my $async_refresh = CXGN::Tools::Run->new();
    $async_refresh->run_async("perl $basepath/bin/refresh_materialized_markerview.pl -H $dbhost -D $dbname -U $dbuser -P $dbpass");

    $c->stash->{rest} = $return;
}

sub _check_user_login_genotypes_vcf_upload {
    my $c = shift;
    my $check_priv = shift;
    my $original_private_company_id = shift;
    my $user_access = shift;

    my $login_check_return = CXGN::Login::_check_user_login($c, $check_priv, $original_private_company_id, $user_access);
    if ($login_check_return->{error}) {
        $c->stash->{rest} = $login_check_return;
        $c->detach();
    }
    my ($user_id, $user_name, $user_role) = @{$login_check_return->{info}};

    return ($user_id, $user_name, $user_role);
}

1;
