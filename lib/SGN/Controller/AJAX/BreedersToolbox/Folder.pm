
package SGN::Controller::AJAX::BreedersToolbox::Folder;

use Moose;
use List::MoreUtils qw | any |;
use Data::Dumper;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON' },
   );

sub get_folder : Chained('/') PathPart('ajax/folder') CaptureArgs(1) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_breederstoolbox_folder($c, 0, 0, 0);

    my $folder_id = shift;
    $c->stash->{schema} = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    $c->stash->{folder_id} = $folder_id;
}

sub create_folder :Path('/ajax/folder/new') Args(0) {
    my $self = shift;
    my $c = shift;
    my $parent_folder_id = $c->req->param("parent_folder_id");
    my $folder_name = $c->req->param("folder_name");
    my $breeding_program_id = $c->req->param("breeding_program_id");
    my $private_company_id = $c->req->param("private_company_id");
    my ($user_id, $user_name, $user_role) = _check_user_login_breederstoolbox_folder($c, 'submitter', 0, 0);

    my $folder_for_trials;
    my $folder_for_crosses;
    my $folder_for_genotyping_trials;
    my $project_type = $c->req->param("project_type");

    if ($project_type eq 'field_trial') {
        $folder_for_trials = 1;
    } elsif ($project_type eq 'crossing_experiment') {
        $folder_for_crosses = 1;
    } elsif ($project_type = 'genotyping_plate') {
        $folder_for_genotyping_trials = 1
    }

    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    my $existing = $schema->resultset("Project::Project")->find( { name => $folder_name });

    if ($existing) {
        $c->stash->{rest} = { error => "A folder or trial with that name already exists in the database. Please select another name." };
        $c->detach;
    }
    my $folder = CXGN::Trial::Folder->create({
	    bcs_schema => $schema,
	    parent_folder_id => $parent_folder_id,
	    name => $folder_name,
	    breeding_program_id => $breeding_program_id,
        folder_for_trials => $folder_for_trials,
        folder_for_crosses => $folder_for_crosses,
        folder_for_genotyping_trials => $folder_for_genotyping_trials,
        private_company_id => $private_company_id
	});

    $c->stash->{rest} = {
      success => 1,
      folder_id => $folder->folder_id()
    };
}

sub delete_folder : Chained('get_folder') PathPart('delete') Args(0) {
    my $self = shift;
    my $c = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_breederstoolbox_folder($c, 'submitter', 0, 0);

    my $folder = CXGN::Trial::Folder->new({
        bcs_schema => $c->stash->{schema},
        folder_id => $c->stash->{folder_id}
    });

    my $delete_folder = $folder->delete_folder();
    if ($delete_folder) {
        $c->stash->{rest} = { success => 1 };
    } else {
        $c->stash->{rest} = { error => 'Folder Not Deleted! To delete a folder first move all trials and sub-folders out of it.' };
    }

}

sub rename_folder : Chained('get_folder') PathPart('name') Args(0) {
    my $self = shift;
    my $c = shift;
    my $new_folder_name = $c->req->param("new_name") ;
    my ($user_id, $user_name, $user_role) = _check_user_login_breederstoolbox_folder($c, 'submitter', 0, 0);

    my $folder = CXGN::Trial::Folder->new({
        bcs_schema => $c->stash->{schema},
        folder_id => $c->stash->{folder_id}
    });
    my $rename_folder = $folder->rename_folder($new_folder_name);
    if ($rename_folder) {
        $c->stash->{rest} = { success => 1 };
    } else {
        $c->stash->{rest} = { error => 'Folder could not be renamed!' };
    }

}


sub associate_parent_folder : Chained('get_folder') PathPart('associate/parent') Args(1) {
    my $self = shift;
    my $c = shift;
    my $parent_id = shift;
    my ($user_id, $user_name, $user_role) = _check_user_login_breederstoolbox_folder($c, 'submitter', 0, 0);

    my $folder = CXGN::Trial::Folder->new({
        bcs_schema => $c->stash->{schema},
        folder_id => $c->stash->{folder_id}
    });

    $folder->associate_parent($parent_id);

    $c->stash->{rest} = { success => 1 };
}

sub set_folder_categories : Chained('get_folder') PathPart('categories') Args(0) {
    my $self = shift;
    my $c = shift;
    my $folder_for_trials = $c->req->param("folder_for_trials") eq 'true' ? 1 : 0;
    my $folder_for_crosses = $c->req->param("folder_for_crosses") eq 'true' ? 1 : 0;
    my $folder_for_genotyping_trials = $c->req->param("folder_for_genotyping_trials") eq 'true' ? 1 : 0;
    my ($user_id, $user_name, $user_role) = _check_user_login_breederstoolbox_folder($c, 'submitter', 0, 0);

    my $folder = CXGN::Trial::Folder->new({
        bcs_schema => $c->stash->{schema},
        folder_id => $c->stash->{folder_id}
    });

    $folder->set_folder_content_type('folder_for_trials', $folder_for_trials);
    $folder->set_folder_content_type('folder_for_crosses', $folder_for_crosses);
    $folder->set_folder_content_type('folder_for_genotyping_trials', $folder_for_genotyping_trials);

    $c->stash->{rest} = { success => 1 };
}

sub _check_user_login_breederstoolbox_folder {
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
