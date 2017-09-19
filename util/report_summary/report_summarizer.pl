#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib ("$FindBin::Bin/../../PerlLib");
use DelimParser;
use Process_cmd;

my $usage = "\n\n\tusage: $0 Trinotate_report.tsv  out_prefix\n\n";

my $trinotate_report_file = $ARGV[0] or die $usage;
my $out_prefix = $ARGV[1] or die $usage;

my $DEBUG = 1;
my $TOP_TAX_LEVEL = 6;

main: {

    open(my $fh, $trinotate_report_file) or die "Error, cannot open file $trinotate_report_file";
    my $delim_parser = new DelimParser::Reader($fh, "\t");

    my %TAXONOMY_COUNTER;
    my %SPECIES_COUNTER;

    my %EGGNOG;
    my %KEGG;
        
    
    while (my $row = $delim_parser->get_row()) {
        
        my $gene_id = $row->{'#gene_id'};
        my $transcript_id = $row->{'transcript_id'};

        my $sprot_Top_BLASTX_hit = $row->{'sprot_Top_BLASTX_hit'} or die "Error, no column name: sprot_Top_BLASTX_hit";
        &extract_taxonomy_info($gene_id, $sprot_Top_BLASTX_hit, \%TAXONOMY_COUNTER, \%SPECIES_COUNTER);
    
        if (my $kegg = $row->{'Kegg'}) {
            $KEGG{$kegg}->{$gene_id} = 1;
        }
        if (my $eggnog = $row->{'eggnog'}) {
            $EGGNOG{$eggnog}->{$gene_id} = 1;
        }
        
    }

    #############################
    ## Report generators
    #############################

    { # write taxonomy info
        my $outfile = "$out_prefix.taxonomy_counts";
        my $header = join("\t", "L1", "L2", "L3", "L4", "L5", "L6", "count");  #FIXME: set L dynamically according to num top levels    
        &nested_hash_to_counts_file(\%TAXONOMY_COUNTER, $outfile, $header);
    }

    { # write species table
        my $outfile = "$out_prefix.species_counts";
        my $header = "species\tcount";
        &nested_hash_to_counts_file(\%SPECIES_COUNTER, $outfile, $header);
    }
    
    { # write eggnog report
        my $outfile = "$out_prefix.eggnog_counts";
        my $header = "eggnog\tcount";
        &nested_hash_to_counts_file(\%EGGNOG, $outfile, $header);
    }

    { # write kegg report
        my $outfile = "$out_prefix.kegg.counts";
        my $header = "kegg\tcount";
        &nested_hash_to_counts_file(\%KEGG, $outfile, $header);
    }
            
    
    ## get GO summaries
    &process_cmd("$FindBin::Bin/../extract_GO_assignments_from_Trinotate_xls.pl  --Trinotate_xls $trinotate_report_file -G -I > $trinotate_report_file.GO");
    &process_cmd("$FindBin::Bin/../gene_ontology/Trinotate_GO_to_SLIM.pl $trinotate_report_file.GO > $trinotate_report_file.GO.slim");

   
    exit(0);
}



#########################
## Data Extractors
#########################


####
sub extract_taxonomy_info {
    my ($gene_id, $sprot_Top_BLASTX_hit, $taxonomy_counter_href, $species_counter_href) = @_;
        
    if ($sprot_Top_BLASTX_hit ne '.') {
        my @pts = split(/\^/, $sprot_Top_BLASTX_hit);
        my $taxonomy = pop @pts;
        my @tax_levels = split(/;\s*/, $taxonomy);
        my $species = pop @tax_levels;
        my @top_tax_levels = @tax_levels[0..($TOP_TAX_LEVEL-1)];
        for my $level (@top_tax_levels) {
            if (! defined $level) {
                $level = "NA";
            }
        }
        
        my $top_tax_level = join("\t", @top_tax_levels);
        print STDERR "$top_tax_level -> $species\n" if $DEBUG;
        $taxonomy_counter_href->{$top_tax_level}->{$gene_id} = 1;
        $species_counter_href->{$species}->{$gene_id} = 1;
    }
    
    return;
}

    

######################
## utility functions
######################


####
sub nested_hash_to_counts {
    my ($hash_ref) = @_;

    my @info_counts;
    
    foreach my $key_val (keys %$hash_ref) {
        my $count = scalar(keys %{$hash_ref->{$key_val}});
        push (@info_counts, [$key_val, $count]);
    }

    @info_counts = reverse sort {$a->[1]<=>$b->[1]} @info_counts;

    return(@info_counts);
}

####
sub write_counts_to_ofh {
    my ($counts_aref, $ofh) = @_;
    foreach my $count_info (@$counts_aref) {
        my ($key_val, $count) = @$count_info;
        print $ofh "$key_val\t$count\n";
    }
    return;
}


####
sub nested_hash_to_counts_file {
    my ($nested_hash_href, $outfile_name, $header) = @_;
    open(my $ofh, ">$outfile_name")or die "Error, cannot write to $outfile_name";
    print $ofh "$header\n";
    my @counts = &nested_hash_to_counts($nested_hash_href);
    &write_counts_to_ofh(\@counts, $ofh);
    close $ofh;
    return;
}
        