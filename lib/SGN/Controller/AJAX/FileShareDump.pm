
=head1 NAME

SGN::Controller::AJAX::FileShareDump - a REST controller class to provide the
backend for uploading file share dump files

=head1 DESCRIPTION

Uploading Files to File Share Dump

=head1 AUTHOR


=cut

package SGN::Controller::AJAX::FileShareDump;

use Moose;
use Try::Tiny;
use DateTime;
use Data::Dumper;
use CXGN::UploadFile;
use File::Basename qw | basename dirname|;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON' },
   );

my $archived_file_type = "manage_file_share_dump_upload";

sub filesharedump_upload :  Path('/ajax/filesharedump/upload') : ActionClass('REST') { }
sub filesharedump_upload_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_file_share_dump($c, 'submitter', 0, 0);
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my $upload = $c->req->upload('manage_file_dump_upload_file_dialog_file');

    my $upload_original_name = $upload->filename();
    my $upload_tempfile = $upload->tempname;
    my $time = DateTime->now();
    my $timestamp = $time->ymd()."_".$time->hms();

    my $uploader = CXGN::UploadFile->new({
        tempfile => $upload_tempfile,
        subdirectory => $archived_file_type,
        archive_path => $c->config->{archive_path},
        archive_filename => $upload_original_name,
        timestamp => $timestamp,
        user_id => $user_id,
        user_role => $user_role
    });
    my $archived_filename_with_path = $uploader->archive();
    my $md5 = $uploader->get_md5($archived_filename_with_path);
    if (!$archived_filename_with_path) {
        $c->stash->{rest} = {error => "Could not store uploaded file!"};
        return;
    }
    unlink $upload_tempfile;

    my $md_row = $metadata_schema->resultset("MdMetadata")->create({create_person_id => $user_id});
    my $file_row = $metadata_schema->resultset("MdFiles")->create({
        basename => basename($archived_filename_with_path),
        dirname => dirname($archived_filename_with_path),
        filetype => $archived_file_type,
        md5checksum => $md5->hexdigest(),
        metadata_id => $md_row->metadata_id()
    });
    $c->stash->{rest} = {success => 1};
}

sub filesharedump_list :  Path('/ajax/filesharedump/list') : ActionClass('REST') { }
sub filesharedump_list_GET : Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_file_share_dump($c, 0, 0, 0);

    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");

    my $q = "SELECT md_file.file_id, md_file.basename, md_file.dirname, sp.sp_person_id, md.create_date, sp.username
        FROM metadata.md_files AS md_file
        JOIN metadata.md_metadata AS md ON (md_file.metadata_id = md.metadata_id)
        JOIN sgn_people.sp_person AS sp ON (md.create_person_id = sp.sp_person_id)
        WHERE md_file.filetype=?";
    my $h = $schema->storage->dbh()->prepare($q);
    $h->execute($archived_file_type);

    my @files;
    while (my ($file_id, $basename, $dirname, $sp_person_id, $create_date, $username) = $h->fetchrow_array()) {
        #my $options = '<a href="/breeders/phenotyping/view/'.$file_id.'">View</a> | <a href="/breeders/phenotyping/download/'.$file_id.'">Download</a>';
        my $options = '<a href="/breeders/phenotyping/download/'.$file_id.'">Download</a>';
        push @files, [$basename, $username, $create_date, $options];
    }

    my $draw = $c->req->param('draw');
    if ($draw){
        $draw =~ s/\D//g; # cast to int
    }
    my $records_total = scalar(@files);

    $c->stash->{rest} = { data => \@files, draw => $draw, recordsTotal => $records_total,  recordsFiltered => $records_total };
}

sub _check_user_login_file_share_dump {
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
