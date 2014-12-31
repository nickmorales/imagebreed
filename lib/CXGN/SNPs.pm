
package CXGN::SNPs;

use Moose;

use Data::Dumper;
use Math::BigInt;

has 'id' => ( isa => 'Str',
	      is => 'rw',
    );

has 'accessions' => ( isa => 'ArrayRef',
		       is  => 'rw',
    );

has 'depth' => ( isa => 'Int',
		 is => 'rw',
    );

has 'ignore_accessions' => (isa => 'HashRef',
			    is => 'rw',
    );

has 'valid_accessions' => (isa => 'ArrayRef',
			   is => 'rw',
    );

has 'scores'  => ( isa => 'HashRef',
		       is  => 'rw',
    );

#has 'bad_clones'  => ( isa => 'ArrayRef',
#		       is  => 'rw',
 #   );

has 'snps' => ( isa => 'ArrayRef',
		is  => 'rw',
    );

has 'maf'  => ( isa => 'Num',
		is  => 'rw',
		default => sub { 0.999 },
    );

has 'allele_freq' => ( isa => 'Num',
		       is  => 'rw',
    );



has 'chr' => ( isa => 'Str',
	       is => 'rw',
    );

has 'position' => (isa => 'Int',
		   is => 'rw',
    );


has 'ref_allele' => ( isa => 'Str',
		   is  => 'rw',
    );

has 'alt_allele' => ( isa => 'Str',
		   is  => 'rw',
    );

has 'qual' => ( isa => 'Str',
		is  => 'rw',
    );

has 'filter' => ( isa => 'Str',
		  is => 'rw',
    );

has 'info' => ( isa => 'Str',
		is => 'rw',
    );

has 'format' => ( isa => 'Str',
		  is => 'rw',
    );

has 'snps'   => ( isa => 'HashRef',
		  is => 'rw',
    );

has 'pAA' => ( isa => 'Num',
	       is => 'rw',
	      );

has 'pAB' => ( isa => 'Num',
	       is => 'rw',
    );

has 'pBB' => ( isa => 'Num',
	       is => 'rw',
    );

=head2 get_score

 Usage:        $ms->get_score('XYZ');
 Desc:         gets the marker score associated with XYZ
 Ret:
 Args:
 Side Effects:
 Example:

=cut

sub get_score { 
    my $self = shift;
    my $accession = shift;
    
    if (exists($self->scores()->{$accession})) { 
	return $self->scores->{$accession};
    }
    else { 
	warn "accession $accession has no associated score.\n";
	return undef;
    }
}

sub snp_stats { 
    my $self = shift;

    my $good_snps = 0;
    my $invalid_snps = 0;
    
    print STDERR Dumper($self->snps());
    foreach my $a (@{$self->valid_accessions}) { 
	my $snp = $self->snps()->{$a};
	if ($snp->good_call()) { 
	    $good_snps++;
	}
	else { 
	    $invalid_snps++;
	}
    }
    return ($good_snps, $invalid_snps);
}

sub calculate_allele_frequency_using_counts { 
    my $self = shift;
    
    my $total_c1 = 0;
    my $total_c2 = 0;
    
    foreach my $k (@{$self->valid_accessions()}) {
	my $s = $self->snps->{$k};
	$total_c1 += $s->ref_count();
	$total_c2 += $s->alt_count();
    }

    if ($total_c1 + $total_c2 == 0) { 
	return undef;
    }
    
    my $allele_freq = $total_c1 / ($total_c1 + $total_c2);
    
    my $pAA = $allele_freq **2;
    my $pAB = $allele_freq * (1 - $allele_freq) * 2 ;
    my $pBB = (1 - $allele_freq) **2;
    
    $self->allele_freq($allele_freq);
    $self->pAA($pAA);
    $self->pAB($pAB);
    $self->pBB($pBB);
    
    return $allele_freq;
}

# sub calculate_dosages { 
#     my $self = shift;
    
#     foreach my $k (keys %{$self->snps()}) { 
# 	my $s = $self->snps()->{$k};
# 	$s->calculate_snp_dosage($s, $self->error_probability());

#     }
#     #print STDERR Dumper($self->snps());
# }
 
sub calculate_snp_dosage { 
    my $self = shift;
    my $snp = shift;
    my $error_probability = 0.025;

    my $c1 = $snp->ref_count();
    my $c2 = $snp->alt_count();

    print STDERR "counts: $c1, $c2\n";
    
    my $n = $c1 + $c2;

    my $N1 = Math::BigInt->new($n);
    my $N2 = Math::BigInt->new($n);

 #   print STDERR "$N1 bnok $c1 is: ". $N1->bnok($c1)."\n";

    my $Nbnokc1 = $N1->bnok($c1)->numify();
    my $Nbnokc2 = $N2->bnok($c2)->numify();
    
#    print STDERR "NBnokc1: $Nbnokc1, NBnokc2 $Nbnokc2\n";

    my $pDAA = $Nbnokc1 * ((1-$error_probability) ** $c1) * ($error_probability ** $c2);
    my $pDAB = $Nbnokc1 * (0.5 ** $c1) * (0.5 ** $c2);
    my $pDBB = $Nbnokc2 * ((1-$error_probability) ** $c2) * ($error_probability ** $c1);

 #   print STDERR "pDAA: $pDAA pDAB $pDAB, pDBB $pDBB\n";

    my $pSAA = $pDAA * $self->pAA;
    my $pSAB = $pDAB * $self->pAB;
    my $pSBB = $pDBB * $self->pBB;

    if ($pSAA + $pSAB + $pSBB == 0) { 
	return "NA";
    }
    
    my $x = 1 / ($pSAA + $pSAB + $pSBB);

    my $dosage = ($pSAB  + 2 * $pSBB) * $x;

    $snp->dosage($dosage);

    return $dosage;
}



sub hardy_weinberg_filter { 
    my $self = shift;
    my $dosages = shift; # ignored clones already removed

    my %classes = ( AA => 0, AB => 0, BB => 0, NA => 0);
    
    foreach my $d (@$dosages) { 
	if (! defined($d)) { 
	    $classes{NA}++;
	}
	elsif ( ($d >= 0) && ($d <= 0.1) ) { 
	    $classes{AA}++;
	}
	elsif ( ($d >=0.9) && ($d <= 1.1) ) { 
	    $classes{AB}++;
	}

	elsif (($d >=1.9) && ($d <= 2.0)) { 
	    $classes{BB}++;
	}
	else { 
	    #print STDERR "Dosage outlier: $d\n";
	}

    }

    print STDERR "Class counts: AA: $classes{AA}, BB: $classes{BB}, AB: $classes{AB}, NA: $classes{NA}\n";
 
    if ( ( ($classes{AA} ==0) && ($classes{AB} ==0)) ||
	( ($classes{BB} == 0) && ($classes{AB} ==0)) ) { 
	return ( monomorphic => 1);
    }

    my $total = $classes{AA} + $classes{AB} + $classes{BB};

    my %score = ();
    
    $score{scored_marker_fraction} = $total / (@$dosages);
    
    #print STDERR "AA  $classes{AA}, AB $classes{AB}, BB $classes{BB} Total: $total\n";
    my $allele_freq = (2 * $classes{AA} + $classes{AB}) / (2 * $total);

    $score{heterozygote_count} = $classes{AB};

    $score{allele_freq} = $allele_freq;
    
    my $expected = $allele_freq * (1-$allele_freq) * 2 * $total;

    #print STDERR "TOTAL: $total\n";
    my $x = ($classes{AB} - $expected)**2 / $expected;

    $score{chi} = $x;

    return %score;
}


__PACKAGE__->meta->make_immutable;


1;
