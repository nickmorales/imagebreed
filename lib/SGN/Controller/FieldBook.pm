
package SGN::Controller::FieldBook;

use Moose;
use URI::FromHash 'uri';
use Spreadsheet::WriteExcel;
use File::Slurp qw | read_file |;
use File::Temp;
use Data::Dumper;
use CXGN::Trial::TrialLayout;
use Try::Tiny;
use File::Basename qw | basename dirname|;
use File::Spec::Functions;
use CXGN::BreedersToolbox::Projects;
use SGN::Model::Cvterm;

BEGIN { extends 'Catalyst::Controller'; }

sub field_book :Path("/fieldbook") Args(0) {
    my ($self , $c) = @_;
    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');
    my $phenome_schema = $c->dbic_schema('CXGN::Phenome::Schema');
    if (!$c->user()) {
        $c->res->redirect( uri( path => '/user/login', query => { goto_url => $c->req->uri->path_query } ) );
        return;
    }
    my $user_id = $c->user()->get_object()->get_sp_person_id();

    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my @rows = $schema->resultset('Project::Project')->all();
    #limit to owner
    my @projects = ();
    my @file_metadata = ();
    my $bp = CXGN::BreedersToolbox::Projects->new( { schema=>$schema });
    my $breeding_programs = $bp->get_breeding_programs($user_id);
    my @layout_files = ();
    my @phenotype_files = ();
    my @removed_phenotype_files = ();


    my $field_layout_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, 'field_layout' , 'experiment_type' ) ;

#    foreach my $row (@rows) {
    #   my $experiment_rs = $schema->resultset('NaturalDiversity::NdExperiment')->search({
    #  					               #					   'nd_experiment_projects.project_id' => $row->project_id,
    #  										   type_id => $field_layout_cvterm->cvterm_id(),
    #  										  },
    #  										  {
    #  										   join => 'nd_experiment_projects',
    #  										  });
    # while (my $experiment = $experiment_rs->next()) {
    #  my $experiment_files = $phenome_schema->resultset("NdExperimentMdFiles")->search({nd_experiment_id => $experiment->nd_experiment_id(),});

    my $q = "SELECT md_files.file_id, metadata.md_files.basename, metadata.md_files.dirname, metadata.md_files.filetype, metadata.md_files.comment, md_metadata.metadata_id FROM nd_experiment_project JOIN nd_experiment USING(nd_experiment_id)  JOIN  phenome.nd_experiment_md_files ON (nd_experiment.nd_experiment_id=nd_experiment_md_files.nd_experiment_id) JOIN metadata.md_files USING (file_id) LEFT JOIN metadata.md_metadata USING(metadata_id) WHERE nd_experiment.type_id=".$field_layout_cvterm->cvterm_id()." and metadata.md_metadata.create_person_id=$user_id and filetype = 'tablet field layout xls'";
    my $h = $c->dbc->dbh->prepare($q);
    $h->execute();
#      while (my $experiment_file = $experiment_files->next) {
    while (my ($file_id, $basename, $dirname, $filetype, $comment, $metadata_id) = $h->fetchrow_array()) {
    	#my $file_row = $metadata_schema->resultset("MdFiles")->find({file_id => $experiment_file->file_id});
    	#if ($filetype eq 'tablet field layout xls') {

#    	  my $metadata_id = $file_row->metadata_id->metadata_id;
   	  if ($metadata_id) {

    	 #   my $file_metadata = $metadata_schema->resultset("MdMetadata")->find({metadata_id => $metadata_id});
    	  #  if ( $file_metadata->create_person_id() eq $user_id) {
		#my $file_destination =  catfile($file_row->dirname, $file_row->basename);
		my $file_destination =  catfile($dirname, $basename);
    	      #push @projects, [ $row->project_id, $row->name, $row->description, $file_row->dirname,$file_row->basename, $file_row->file_id];
	      push @file_metadata, [ $dirname, $basename, $file_id, $comment ] ;
    	      push @layout_files, $file_destination;
    	  #  }
    	  #}
    	}
    }
   # }
   #}

    my @trait_files = ();
    #limit to those owned by user
    my $md_files = $metadata_schema->resultset("MdFiles")->search({filetype=>'tablet trait file'});
    while (my $md_file = $md_files->next) {
      my $metadata_id = $md_file->metadata_id->metadata_id;
      my $file_metadata = $metadata_schema->resultset("MdMetadata")->find({metadata_id => $metadata_id});
      if ( $file_metadata->create_person_id() eq $user_id) {
	push @trait_files, [$md_file->basename,$md_file->file_id];
      }
    }

    my $uploaded_md_files = $metadata_schema->resultset("MdFiles")->search({filetype=>'tablet phenotype file'});
    while (my $md_file = $uploaded_md_files->next) {
	my $metadata_id = $md_file->metadata_id->metadata_id;
	my $file_metadata = $metadata_schema->resultset("MdMetadata")->find({metadata_id => $metadata_id });
	if ( ($file_metadata->obsolete==0) && ($file_metadata->create_person_id() eq $user_id)) {
	    push @phenotype_files, [$md_file->basename,$md_file->file_id];
	}
	elsif ( ($file_metadata->obsolete==1) && ($file_metadata->create_person_id() eq $user_id)) {
	  push @removed_phenotype_files, [$md_file->basename, $md_file->file_id];
	}
    }

    $c->stash->{projects} = \@projects;
    $c->stash->{file_metadata} = \@file_metadata;
    $c->stash->{programs} = $breeding_programs;
    $c->stash->{layout_files} = \@projects;
    $c->stash->{trait_files} = \@trait_files;
    $c->stash->{phenotype_files} = \@phenotype_files;
    $c->stash->{removed_phenotype_files} = \@removed_phenotype_files;

    # get roles
    my @roles = $c->user->roles();
    $c->stash->{roles}=\@roles;
    $c->stash->{template} = '/fieldbook/home.mas';
}


sub trial_field_book_download : Path('/fieldbook/trial_download/') Args(1) {
    my $self  =shift;
    my $c = shift;
    my $file_id = shift;
    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');
    my $file_row = $metadata_schema->resultset("MdFiles")->find({file_id => $file_id});
    my $file_destination =  catfile($file_row->dirname, $file_row->basename);
    print STDERR "\n\n\nfile name:".$file_row->basename."\n";
    my $contents = read_file($file_destination);
    my $file_name = $file_row->basename;
    $c->res->content_type('application/application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    $c->res->header('Content-Disposition', qq[attachment; filename="fieldbook_layout_$file_name"]);
    $c->res->body($contents);
}

sub tablet_trait_file_download : Path('/fieldbook/trait_file_download/') Args(1) {
    my $self  =shift;
    my $c = shift;
    my $file_id = shift;
    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');
    my $file_row = $metadata_schema->resultset("MdFiles")->find({file_id => $file_id});
    my $file_destination =  catfile($file_row->dirname, $file_row->basename);
    print STDERR "\n\n\nfile name:".$file_row->basename."\n";
    my $contents = read_file($file_destination);
    my $file_name = $file_row->basename;

    $c->res->content_type('Application/trt');
    $c->res->header('Content-Disposition', qq[attachment; filename="$file_name"]);
    $c->res->body($contents);
}

sub delete_file : Path('/fieldbook/delete_file/') Args(1) {
     my $self  =shift;
     my $c = shift;
     my $json = new JSON;
     my $file_id = shift;
     my $decoded;
     if ($file_id){
		 $decoded = $json->allow_nonref->utf8->decode($file_id);
     }
	#print STDERR Dumper($file_id);
	print "File ID: $file_id\n";
     my $dbh = $c->dbc->dbh();
     my $h_nd_exp_md_files = $dbh->prepare("delete from phenome.nd_experiment_md_files where file_id=?;");
     $h_nd_exp_md_files->execute($decoded);

     my $h_md_files = $dbh->prepare("delete from metadata.md_files where file_id=?;");
     $h_md_files->execute($decoded);
     print STDERR "File successfully deleted.\n";
	$c->response->redirect('/fieldbook');
}

1;
