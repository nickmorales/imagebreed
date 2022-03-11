=head1 NAME

CXGN::ImageObject -


=head1 DESCRIPTION


=head1 AUTHOR

=cut

package CXGN::ImageObject;

use Moose;

use File::Spec;
use Data::Dumper;
use Bio::Chado::Schema;
use SGN::Model::Cvterm;

has 'schema' => (
    isa => 'Bio::Chado::Schema',
    is => 'rw',
    required => 1
);

has 'static_datasets_url' => (
    isa => 'Str',
    is => 'rw',
);

has 'image_dir' => (
    isa => 'Str',
    is => 'rw',
);

has 'image_id' => (
    isa => 'Int',
    is => 'rw',
);

has 'is_storing_or_editing' => (
    isa => 'Bool',
    is => 'rw',
    default => 0
);

has 'name' => (
    isa => 'Maybe[Str]',
    is => 'rw',
);

has 'description' => (
    isa => 'Maybe[Str]',
    is => 'rw',
);

has 'original_filename' => (
    isa => 'Str',
    is => 'rw',
);

has 'file_ext' => (
    isa => 'Str',
    is => 'rw',
);

has 'sp_person_id' => (
    isa => 'Int',
    is => 'rw',
);

has 'modified_date' => (
    isa => 'Str',
    is => 'rw',
);

has 'create_date' => (
    isa => 'Str',
    is => 'rw',
);

has 'obsolete' => (
    isa => 'Bool',
    is => 'rw',
);

has 'md5checksum' => (
    isa => 'Str',
    is => 'rw',
);

has 'private_company_id' => (
    isa => 'Int',
    is => 'rw',
);

has 'private_company_image_is_private' => (
    isa => 'Bool',
    is => 'rw',
);

sub BUILD {
    my $self = shift;

    if ($self->image_id){
        if (!$self->is_storing_or_editing) {
            my $q = "SELECT image.name, image.description, image.original_filename, image.file_ext, image.sp_person_id, image.modified_date, image.create_date, image.obsolete, image.md5sum, image.private_company_id, image.is_private
                FROM metadata.md_image AS image
                WHERE image.image_id=?;";
            my $h = $self->schema->storage->dbh()->prepare($q);
            $h->execute($self->image_id);
            my ($image_name, $image_description, $image_original_filename, $file_ext, $sp_person_id, $image_modified_date, $image_create_date, $image_obsolete, $md5checksum, $private_company_id, $is_private) = $h->fetchrow_array();

            $self->name($image_name);
            $self->description($image_description);
            $self->original_filename($image_original_filename);
            $self->file_ext($file_ext);
            $self->sp_person_id($sp_person_id);
            $self->modified_date($image_modified_date);
            $self->create_date($image_create_date);
            $self->obsolete($image_obsolete);
            $self->md5checksum($md5checksum);
            $self->private_company_id($private_company_id);
            $self->private_company_image_is_private($is_private);
        }
    }
    return $self;
}

sub get_tags {
    my $self  = shift;

    my $query = "SELECT md_tag.tag_id, md_tag.name, md_tag.description
        FROM metadata.md_tag_image AS md_tag_image
        JOIN metadata.md_tag AS md_tag ON(md_tag.tag_id=md_tag_image.tag_id)
        WHERE image_id=?";
    my $sth = $self->schema->storage->dbh()->prepare($query);
    $sth->execute($self->image_id());
    my @tags;
    while (my ($tag_id, $tag_name, $tag_description) = $sth->fetchrow_array()) {
        push @tags, [$tag_id, $tag_name, $tag_description];
    }
    return \@tags;
}

sub get_img_src_tag {
    my $self = shift;
    my $size = shift;
    my $url  = $self->get_image_url($size);
    my $name = $self->name() || '';
    if ( $size && ($size eq "original" || $size eq "original_converted" ) ) {
        return
            "<a href=\""
          . ($url)
          . "\"><span class=\"glyphicon glyphicon-floppy-save\" alt=\""
          . $name
          . "\" ></a>";
    }
    elsif ( $size && $size eq "tiny" ) {
        return
            "<img src=\""
          . ($url)
          . "\" width=\"20\" height=\"15\" border=\"0\" alt=\""
          . $name
          . "\" />\n";
    }
    else {
        return
            "<img src=\""
          . ($url)
          . "\" border=\"0\" alt=\""
          . $name
          . "\" />\n";
    }
}

sub get_image_url {
    my $self = shift;
    my $size = shift;

    my $url = join '/', (
         '',
         $self->static_datasets_url,
         $self->image_dir,
         $self->get_filename($size, 'partial'),
     );
    $url =~ s!//!/!g;
    return $url;
}

sub get_filename {
    my $self = shift;
    my $size = shift;
    my $type = shift || ''; # full or partial

    my $image_dir =
        $type eq 'partial'
            ? $self->image_subpath
            : File::Spec->catdir( $self->image_dir, $self->image_subpath );

    if ($size eq "thumbnail") {
        return File::Spec->catfile($image_dir, 'thumbnail.jpg');
    }
    if ($size eq "small") {
        return File::Spec->catfile($image_dir, 'small.jpg');
    }
    if ($size eq "large") {
        return File::Spec->catfile($image_dir, 'large.jpg');
    }
    if ($size eq "original") {
        return File::Spec->catfile($image_dir, $self->original_filename().$self->file_ext());
    }
    if ($size eq "original_converted") {
        return File::Spec->catfile($image_dir, $self->original_filename().".JPG");
    }
    return File::Spec->catfile($image_dir, 'medium.jpg');
}

sub image_subpath {
    my $self = shift;
    my $md5sum = $self->md5checksum;
    return join '/', $md5sum =~ /^(..)(..)(..)(..)(.+)$/;
}


sub get_associated_object_links {
    my $self = shift;
    my $s = "";
    foreach my $assoc ($self->get_associated_objects()) {

        if ($assoc->[0] eq "stock") {
            $s .= "<a href=\"/stock/$assoc->[1]/view\">Stock name: $assoc->[2].</a>";
        }
        if ($assoc->[0] eq "organism" ) {
            $s .= qq { <a href="/organism/$assoc->[1]/view/">Organism name:$assoc->[2]</a> };
        }
        if ($assoc->[0] eq "cvterm" ) {
            $s .= qq { <a href="/cvterm/$assoc->[1]/view/">Cvterm: $assoc->[2]</a> };
        }
        if ($assoc->[0] eq "project" ) {
            $s .= qq { <a href="/breeders_toolbox/trial/$assoc->[1]">Project: $assoc->[2]</a> };
        }
    }
    return $s;
}

sub get_associated_objects {
    my $self = shift;
    my @associations = ();

    foreach my $stock (@{$self->get_stocks()}) {
        push @associations, [ "stock", $stock->[0], $stock->[1] ];
    }
    foreach my $cvterm (@{$self->get_cvterms}) {
        push @associations, ["cvterm" , $cvterm->[0], $cvterm->[1]];
    }
    foreach my $o (@{$self->get_organisms}) {
        push @associations, ["organism", $o->[0], $o->[1]];
    }
    foreach my $p (@{$self->get_projects}) {
        push @associations, ["project", $p->[0], $p->[1]];
    }

    print STDERR Dumper \@associations;
    return @associations;
}

sub get_stocks {
    my $self = shift;

    my $q = "SELECT stock.stock_id, stock.uniquename
        FROM phenome.stock_image AS s
        JOIN stock ON(s.stock_id=stock.stock_id)
        WHERE s.image_id = ? ";
    my $sth = $self->schema->storage->dbh()->prepare($q);
    $sth->execute($self->image_id);
    my @stocks;
    while (my ($stock_id, $uniquename) = $sth->fetchrow_array) {
        push @stocks, [$stock_id, $uniquename];
    }

    return \@stocks;
}

sub get_cvterms {
    my $self = shift;

    my $query = "SELECT cvterm.cvterm_id, cvterm.name
        FROM metadata.md_image_cvterm AS m
        JOIN cvterm ON(cvterm.cvterm_id=m.cvterm_id)
        WHERE m.obsolete != 't' AND m.image_id=?";
    my $sth = $self->schema->storage->dbh()->prepare($query);
    $sth->execute($self->image_id());
    my @cvterms = ();
    while (my ($cvterm_id, $name) = $sth->fetchrow_array ) {
        push @cvterms, [$cvterm_id, $name]
    }

    return \@cvterms;
}

sub get_organisms {
    my $self = shift;

    my $query = "SELECT organism.organism_id, organism.species
        FROM metadata.md_image_organism AS m
        JOIN organism ON(m.organism_id=organism.organism_id)
        WHERE m.obsolete != 't' AND m.image_id=?";
    my $sth = $self->schema->storage->dbh()->prepare($query);
    $sth->execute($self->image_id());
    my @organisms = ();
    while (my ($o_id, $species) = $sth->fetchrow_array ) {
        push @organisms, [$o_id, $species]
    }
    return \@organisms;
}

sub get_projects {
    my $self = shift;

    my $q = "SELECT project.project_id, project.name
        FROM phenome.project_md_image AS p
        JOIN project ON(p.project_id=project.project_id)
        WHERE p.image_id = ? ";
    my $sth = $self->schema->storage->dbh()->prepare($q);
    $sth->execute($self->image_id);
    my @projects;
    while (my ($project_id, $name) = $sth->fetchrow_array) {
        push @projects, [$project_id, $name];
    }
    print STDERR Dumper \@projects;
    return \@projects;
}

1;
