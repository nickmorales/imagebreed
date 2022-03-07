
package SGN::Controller::AJAX::Trials;

use Moose;

use CXGN::BreedersToolbox::Projects;
use CXGN::Trial::Folder;
use Data::Dumper;
use Carp;
use File::Path qw(make_path);
use File::Spec::Functions qw / catfile catdir/;
use File::Slurp qw | read_file |;
use SGN::Model::Cvterm;
use CXGN::Login;

BEGIN { extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON' },
   );


sub get_trials : Path('/ajax/breeders/get_trials') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_trials($c, 0, 0, 0);

    my $p = CXGN::BreedersToolbox::Projects->new( { schema => $c->dbic_schema("Bio::Chado::Schema") } );

    my $projects = $p->get_breeding_programs();

    my %data = ();
    foreach my $project (@$projects) {
        my $trials = $p->get_trials_by_breeding_program($project->[0]);
        $data{$project->[1]} = $trials;

    }

    $c->stash->{rest} = \%data;
}

sub get_trials_with_folders : Path('/ajax/breeders/get_trials_with_folders') Args(0) {
    my $self = shift;
    my $c = shift;
    my $tree_type = $c->req->param('type') || 'trial'; #can be 'trial' or 'genotyping_trial', 'cross'
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my ($user_id, $user_name, $user_role) = _check_user_login_trials($c, 0, 0, 0);

    my $dir = catdir($c->config->{static_content_path}, "folder");
    eval { make_path($dir) };
    if ($@) {
        print STDERR "Couldn't create $dir: $@";
    }
    my $filename = $dir."/entire_jstree_html_$tree_type.txt";

    _write_cached_folder_tree($schema, $tree_type, $filename);

    $c->stash->{rest} = { status => 1 };
}

sub get_trials_with_folders_cached : Path('/ajax/breeders/get_trials_with_folders_cached') Args(0) {
    my $self = shift;
    my $c = shift;
    my $tree_type = $c->req->param('type') || 'trial'; #can be 'trial' or 'genotyping_trial', 'cross'
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my ($user_id, $user_name, $user_role) = _check_user_login_trials($c, 0, 0, 0);

    my $dir = catdir($c->config->{static_content_path}, "folder");
    eval { make_path($dir) };
    if ($@) {
        print "Couldn't create $dir: $@";
    }
    my $filename = $dir."/entire_jstree_html_$tree_type.txt";
    my $html = '';
    open(my $fh, '< :encoding(UTF-8)', $filename) or warn "cannot open file $filename $!";
    {
        local $/;
        $html = <$fh>;
    }
    close($fh);

    if (!$html) {
        $html = _write_cached_folder_tree($schema, $tree_type, $filename);
    }

    #print STDERR $html;
    $c->stash->{rest} = { html => $html };
}

sub _write_cached_folder_tree {
    my $schema = shift;
    my $tree_type = shift;
    my $filename = shift;
    my $p = CXGN::BreedersToolbox::Projects->new( { schema => $schema  } );

    my $projects = $p->get_breeding_programs();

    my $html = "";
    my $folder_obj = CXGN::Trial::Folder->new( { bcs_schema => $schema, folder_id => @$projects[0]->[0] });

    print STDERR "Starting get trials $tree_type at time ".localtime()."\n";
    foreach my $project (@$projects) {
        my %project = ( "id" => $project->[0], "name" => $project->[1]);
        $html .= $folder_obj->get_jstree_html(\%project, $schema, 'breeding_program', $tree_type);
    }
    print STDERR "Finished get trials $tree_type at time ".localtime()."\n";

    my $OUTFILE;
    open $OUTFILE, '> :encoding(UTF-8)', $filename or die "Error opening $filename: $!";
    print { $OUTFILE } $html or croak "Cannot write to $filename: $!";
    close $OUTFILE or croak "Cannot close $filename: $!";

    return $html;
}

sub trial_autocomplete : Local : ActionClass('REST') { }

sub trial_autocomplete_GET :Args(0) {
    my ($self, $c) = @_;
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my ($user_id, $user_name, $user_role) = _check_user_login_trials($c, 0, 0, 0);

    my $term = $c->req->param('term');
    $term =~ s/(^\s+|\s+)$//g;
    $term =~ s/\s+/ /g;

    my $trial_search = CXGN::Trial::Search->new({
        bcs_schema=>$schema,
        trial_name_list=>[$term],
        field_trials_only=>1,
        sp_person_id=>$user_id,
        subscription_model=>$c->config->{subscription_model}
    });
    my ($result, $total_count) = $trial_search->search();

    my @response_list;
    foreach (@$result) {
        push @response_list, $_->{trial_name};
    }
    #print STDERR Dumper \@response_list;

    $c->stash->{rest} = \@response_list;
}


sub trial_lookup : Path('/ajax/breeders/trial_lookup') Args(0) {
    my $self = shift;
    my $c = shift;
    my $trial_name = $c->req->param('name');
    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my ($user_id, $user_name, $user_role) = _check_user_login_trials($c, 0, 0, 0);

    if ( !$trial_name || $trial_name eq '' ) {
        $c->stash->{rest} = {error => "Trial name required"};
        $c->detach();
    }

    # Get trial id by name
    my $trial_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, "phenotyping_trial", "project_type")->cvterm_id();
    my $rs = $schema->resultset("Project::Project")->find(
        { 'name' => $trial_name, 'projectprops.type_id' => $trial_type_id },
        { join => 'projectprops' }
    );
    my $trial_id = $rs->project_id() if $rs;

    # Trial not found
    if ( !$trial_id || $trial_id eq '' ) {
        $c->stash->{rest} = {error => "Trial not found"};
        $c->detach();
    }

    $c->stash->{rest} = { trial_id => $trial_id };
}

sub _check_user_login_trials {
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
