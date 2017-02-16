
use strict;

package SGN::Controller::AJAX::TrialComparison;

use Moose;
use Data::Dumper;
use File::Temp qw | tempfile |;
use File::Slurp;
use CXGN::Dataset;
use SGN::Model::Cvterm;
use CXGN::List;
use CXGN::List::Validate;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON' },
   );


has 'schema' => (
		 is       => 'rw',
		 isa      => 'DBIx::Class::Schema',
		 lazy_build => 1,
		);


# /ajax/trial/compare?trial_id=345&trial_id=4848&trial_id=38484&cvterm_id=84848




sub compare_trials : Path('/ajax/trial/compare') : ActionClass('REST') {}

sub compare_trials_GET : Args(0) { 
    my $self = shift;
    my $c = shift;

    my $trial_1 = $c->req->param('trial_1');
    my $trial_2 = $c->req->param('trial_2');
    
    my $cvterm_id = $c->req->param('cvterm_id');
    my $schema = $c->dbic_schema("Bio::Chado::Schema");

    my $trial_id_rs = $schema->resultset("Project::Project")->search( { name => { in => [ $trial_1, $trial_2 ]} });

    my @trial_ids = map { $_->project_id() } $trial_id_rs->all();

    if (@trial_ids < 2) { 
	$c->stash->{rest} = { error => "One or both trials are not found in the database. Please try again." };
	return;
    }

    $self->make_graph($c, $cvterm_id, @trial_ids);
}

 #   my $cv_name = $c->config->{trait_ontology_db_name};
    
#    my $cv_term_id = SGN::Model::Cvterm->get_cvterm_row($schema, $cvterm, $cv_name);
sub compare_trial_list : Path('/ajax/trial/compare_list') : ActionClass('REST') {}

sub compare_trial_list_GET : Args(0) { 
    my $self = shift;
    my $c = shift;

    my $list_id = $c->req->param("list_id");

    my $user = $c->user();
    
    if (!$user) { 
	$c->stash->{rest} = { error => "Must be logged in to use functionality associated with lists." };
	return;
    }
    
    my $user_id = $user->get_object()->get_sp_person_id();

    print STDERR "USER ID : $user_id\n";

    if (!$list_id) { 
	$c->stash->{rest} = { error => "Error: No list_id provided." };
	return;
    }

    my $cvterm_id = $c->req->param("cvterm_id");
    if (!$cvterm_id) { 
	$c->stash->{rest} = { error => "Error: No cvterm_id provided." };
	return;
    }


    my $schema = $c->dbic_schema("Bio::Chado::Schema");

    my $v = CXGN::List::Validate->new();
    my $r = $v->validate($schema, "trial", $list_id);
    
    if ($r->{missing}) { 
	$c->stash->{rest} = { error => "Not all trials could be found in the database." };
	return;
    }
    
    my $dbh = $schema->storage()->dbh();
    my $tl = CXGN::List->new({ dbh => $dbh, list_id => $list_id, owner => $user_id });

    if (! $tl) { 
	$c->stash->{rest} = { error => "The specified list does not exist, is not owned by you, or is not a trial list" };
	return;
    }

    my $trials = $tl->elements();

    my $trial_id_rs = $schema->resultset("Project::Project")->search( { name => { in => [ @$trials ]} });

    my @trial_ids = map { $_->project_id() } $trial_id_rs->all();

    if (@trial_ids < 2) { 
	$c->stash->{rest} = { error => "One or both trials are not found in the database. Please try again." };
	return;
    }

    $self->make_graph($c, $cvterm_id, @trial_ids);
}
    


sub make_graph { 
    my $self = shift;
    my $c = shift;
    my $cvterm_id = shift;
    my @trial_ids = @_;

    my $schema = $c->dbic_schema("Bio::Chado::Schema"); 
    my $ds = CXGN::Dataset->new( people_schema => $c->dbic_schema("CXGN::People::Schema"), schema => $schema);
    
    $ds->trials( [ @trial_ids ]);
    $ds->traits( [ $cvterm_id ]);
    
    my $data = $ds->retrieve_phenotypes();

    $c->tempfiles_subdir("compare_trials");

    print STDERR Dumper($data);
    my ($fh, $tempfile) = $c->tempfile(TEMPLATE=>"compare_trials/trial_phenotypes_download_XXXXX");
    foreach my $line (@$data) { 
	my @columns = split "\t", $line;
	my @quoted_columns = map { "\"$_\"" }  @columns;
	my $csv_line = join ",", @quoted_columns;
	print $fh $csv_line."\n";
    }
    my $temppath = $c->config->{basepath}."/".$tempfile;

    print STDERR "RUNNING R SCRIPT... ";
    system('R', 'CMD', 'BATCH', '--no-save', '--no-restore', "--args phenotype_file=\"$temppath\" output_file=\"$temppath.png\"", $c->config->{basepath}.'/R/'.'analyze_phenotype.r', $temppath."_output.txt" );
    print STDERR "Done.\n";

    my $errorfile = $temppath.".err";
    if (-e $errorfile) { 
	print STDERR "ERROR FILE EXISTS! $errorfile\n";
	my $error = read_file($errorfile);
	$c->stash->{rest} = { error => $error };
	return;
    }

    $c->stash->{rest} = { file => $tempfile, png => $tempfile.".png" };
}

sub common_traits : Path('/ajax/trial/common_traits') : ActionClass('REST') {}

sub common_traits_GET : Args(0) { 
    my $self = shift;
    my $c = shift;
    
    my $trial_1 = $c->req->param("trial_1");
    my $trial_2 = $c->req->param("trial_2");
    
    my $trial_list_id = $c->req->param("list_id");

    my @trials;

    if ($trial_list_id) { 
	print STDERR "Parsing trial_list_id...\n";
	my $list = CXGN::List->new(
	    { 
		dbh => $c->dbic_schema("Bio::Chado::Schema")->storage->dbh(),
		list_id => $trial_list_id,
	    });
	my $trials = $list->elements();
	print STDERR Dumper($trials);
	@trials = @$trials;
    }
    else { 
	print STDERR "Parsing trial_1 and trial_2...\n";
	if ( ($trial_1 ne "") && ($trial_2 ne "")) { 
	    @trials = ($trial_1, $trial_2);
	}
    }
    
    $self->get_common_traits($c, @trials);
    

}


sub get_common_traits { 
    my $self = shift;
    my $c = shift;
    my @trials = @_;

    my $schema = $c->dbic_schema("Bio::Chado::Schema");

    my $trial_id_rs = $schema->resultset("Project::Project")->search( { name => { in => [ @trials ]} });
    my @trial_ids = map { $_->project_id() } $trial_id_rs->all();

    my $ds = CXGN::Dataset->new( people_schema => $c->dbic_schema("CXGN::People::Schema"), schema => $schema);
    
    my @trait_lists;
    foreach my $t (@trial_ids) { 
	$ds->trials( [ $t ]);

	my $traits = $ds->retrieve_traits();
	push @trait_lists, $traits;
    }
    
    print STDERR Dumper(\@trait_lists);
    my @common_traits = @{$trait_lists[0]};
    for(my $i=1; $i<@trait_lists; $i++ ) { 
	my @local_common = ();
	for(my $n=0; $n<@common_traits; $n++) { 
	    for(my $m=0; $m<@{$trait_lists[$i]}; $m++) { 
		if ($common_traits[$n]->[0] == $trait_lists[$i][$m]->[0]) { 
		    push @local_common, $common_traits[$n];
		}
	    }
	}
	@common_traits = @local_common;
    }
	    

    print STDERR "Traits:\n";
    print STDERR Dumper(\@common_traits);
    
    my @options;
    foreach my $t (@common_traits) { 
	push @options, [ $t->[0], $t->[1] ];
    }

    $c->stash->{rest} = { options => \@options };


    }

1;
