#!/usr/local/bin/perl -w

use strict;
use Config;  #  for @signame

#  Usage:  atac.pl run-directory id1 id2
#
if (scalar(@ARGV) < 6) {
    print STDERR "usage: $0 [opts]\n";
    print STDERR "\n";
    print STDERR "    -dir run-directory\n";
    print STDERR "\n";
    print STDERR "Sequence specification:  If -seq is supplied, then that\n";
    print STDERR "sequence file is used with the id given by -id.  If there is\n";
    print STDERR "a conflict with an established id, the program exits.\n";
    print STDERR "\n";
    print STDERR "    -id1  id1\n";
    print STDERR "    -seq1 seq1.fasta\n";
    print STDERR "    -id2  id2\n";
    print STDERR "    -seq2 seq2.fasta\n";
    print STDERR "\n";
    print STDERR "Paths should be FULL PATHS, not relative paths.\n";
    print STDERR "\n";
    print STDERR "    -genomedir path        -- path to the GENOMES directory\n"; 
    print STDERR "    -meryldir  path        -- path to the MERYL directory\n";
    print STDERR "    -bindir  path          -- path to the binaries (hack!)\n";
    print STDERR "\n";
    print STDERR "    -numsegments s         -- number of segments to do the search in\n";
    print STDERR "    -numthreads t          -- number of threads to use per search\n";
    print STDERR "\n";
    print STDERR "    -merylonly             -- only run the meryl components\n";
    print STDERR "\n";
    exit(1);
}

my $ATACdir;
my $id1;
my $seq1;
my $id2;
my $seq2;

my $GENOMEdir     = "/prod/IR05/GENOMES";          #  Location of genome assemblies
my $MERYLdir      = "/prod/IR08/walenz/hg5/data";  #  Location of genome mercount databases

my $mersize   = 20; # the mer size
my $merlimit  = 1;  # unique mers only
my $minfill   = 20; # the mimimum fill for a reported match.
my $maxgap    = 0;  # the maximum substitution gap

my $numSegments = 2;
my $numThreads  = 4;

my $merylOnly = 0;

my $execHome;
$execHome = "/work/assembly/walenzbp/releases";
$execHome = "/test/IR/walenz/cds/IR/BRI/bin";

while (scalar(@ARGV) > 0) {
    my $arg = shift @ARGV;

    if      ($arg eq "-dir") {
        $ATACdir = shift @ARGV;
    } elsif ($arg eq "-id1") {
        $id1 = shift @ARGV;
    } elsif ($arg eq "-seq1") {
        $seq1 = shift @ARGV;
    } elsif ($arg eq "-id2") {
        $id2 = shift @ARGV;
    } elsif ($arg eq "-seq2") {
        $seq2 = shift @ARGV;
    } elsif ($arg eq "-genomedir") {
        $GENOMEdir = shift @ARGV;
    } elsif ($arg eq "-meryldir") {
        $MERYLdir = shift @ARGV;
    } elsif ($arg eq "-numsegments") {
        $numSegments = shift @ARGV;
    } elsif ($arg eq "-numthreads") {
        $numThreads = shift @ARGV;
    } elsif ($arg eq "-bindir") {
        $execHome = shift @ARGV;
    } elsif ($arg eq "-merylonly") {
        $merylOnly = 1;
    }
}

$execHome = "/work/assembly/walenzbp/releases" if ($execHome eq "compaq");
$execHome = "/test/IR/walenz/cds/IR/BRI/bin"   if ($execHome eq "aix");


#  Decide on a path to the executables.  This is probably
#  a hack.
#
my $leaff   = "$execHome/leaff";
my $meryl   = "$execHome/meryl";
my $existDB = "$execHome/existDB";
my $seatac  = "$execHome/seatac";

die "Can't run $leaff\n"   if (! -x $leaff);
die "Can't run $meryl\n"   if (! -x $meryl);
die "Can't run $existDB\n" if (! -x $existDB);
die "Can't run $seatac\n"  if (! -x $seatac);

die "Unset GENOMEdir?'\n" if (! defined($GENOMEdir));
die "Unset MERYLdir?'\n"  if (! defined($MERYLdir));
die "Unset ATACdir?'\n"   if (! defined($ATACdir));

die "Can't find the GENOMEdir '$GENOMEdir'\n" if (! -d $GENOMEdir);
die "Can't find the assembly descriptions '$GENOMEdir/assemblies.atai'\n" if (! -e "$GENOMEdir/assemblies.atai");
die "Can't find the MERYLdir '$MERYLdir'\n" if (! -d $MERYLdir);

system("mkdir $ATACdir") if (! -d $ATACdir);



findSources();

my $mercount1 = countMers($id1, $mersize, $merlimit);
my $mercount2 = countMers($id2, $mersize, $merlimit);

my $matches   = "$id1-vs-$id2.k$mersize.u$merlimit.f$minfill.g$maxgap";

#
#  Find the include or exclude mask
#
if (! -e "$ATACdir/.mask.done") {

    if (! -e "$ATACdir/min.$mercount1.$mercount2.mcdat") {
        print STDERR "Finding the min count between $mercount1 and $mercount2.\n";
        if (runCommand("$meryl -M min -s $MERYLdir/$mercount1 -s $MERYLdir/$mercount2 -o $ATACdir/min.$mercount1.$mercount2")) {
            #unlink "$ATACdir/min.$mercount1.$mercount2.mcidx";
            #unlink "$ATACdir/min.$mercount1.$mercount2.mcdat";
            rename "$ATACdir/min.$mercount1.$mercount2.mcidx", "$ATACdir/min.$mercount1.$mercount2.mcidx.crash";
            rename "$ATACdir/min.$mercount1.$mercount2.mcdat", "$ATACdir/min.$mercount1.$mercount2.mcdat.crash";
            die "Failed to find the min count between $mercount1 and $mercount2\n";
        }
    }

    die "Failed to make the mask?\n" if (! -e "$ATACdir/min.$mercount1.$mercount2.mcdat");

    #  Decide if we want to use an include mask, or an exclude mask, based
    #  on the estimated size of each.
    #
    #  An include mask is just the 'min' mers found above, while an exclude
    #  mask is 'id1-min' mers.
    #
    my $includeSize = (-s "$ATACdir/min.$mercount1.$mercount2.mcdat");
    my $excludeSize = (-s "$MERYLdir/$mercount1.mcdat") - (-s "$ATACdir/min.$mercount1.$mercount2.mcdat");

    print STDERR "includeSize is about $includeSize\n";
    print STDERR "excludeSize is about $excludeSize\n";

    #
    #  Since we usually run multiple copies of the search, and since building
    #  the existDB structure takes > thirty minutes, we pre-build it.
    #

    if ($includeSize < $excludeSize) {

        #if (! -e "$ATACdir/$matches.include.existDB") {
        #    print STDERR "Building 'include' existDB structure.\n";
        #    if (runCommand("$existDB -m 20 -t 19 $ATACdir/min.$mercount1.$mercount2 $ATACdir/$matches.include.existDB")) {
        #        unlink "$ATACdir/$matches.include.existDB";
        #        die "Failed to make include existDB?\n";
        #    }
        #}
        #die "Failed to make include existDB?\n" if (! -e "$ATACdir/$matches.include.existDB");

        system("ln -s $ATACdir/min.$mercount1.$mercount2.mcidx $ATACdir/$matches.include.mcidx");
        system("ln -s $ATACdir/min.$mercount1.$mercount2.mcdat $ATACdir/$matches.include.mcdat");
    } else {

        if (! -e "$ATACdir/$matches.exclude.mcdat") {
            print STDERR "Finding 'exclude' mers!\n";
            if (runCommand("$meryl -M xor -s $MERYLdir/$id1 -s $ATACdir/min.$mercount1.$mercount2 -o $ATACdir/$matches.exclude")) {
                #unlink "$ATACdir/$matches.exclude.mcidx";
                #unlink "$ATACdir/$matches.exclude.mcdat";
                rename "$ATACdir/$matches.exclude.mcidx", "$ATACdir/$matches.exclude.mcidx.crash";
                rename "$ATACdir/$matches.exclude.mcdat", "$ATACdir/$matches.exclude.mcdat.crash";
                die "Failed to make exclude mers!\n";
            }
        }

        die "Failed to find exclude mers?\n" if (! -e "$ATACdir/$matches.exclude.mcdat");

        #if (! -e "$ATACdir/$matches.exclude.existDB") {
        #    print STDERR "Building 'exclude' existDB structure.\n";
        #    if (runCommand("$existDB -m 20 -t 19 $ATACdir/$matches.exclude $ATACdir/$matches.exclude.existDB")) {
        #        unlink "$ATACdir/$matches.exclude.existDB";
        #        die "Failed to make exclude existDB?\n";
        #    }
        #}
        #die "Failed to make exclude existDB?\n" if (! -e "$ATACdir/$matches.exclude.existDB");
    }

    #  Success!
    #
    open(F, "> $ATACdir/.mask.done");
    close(F);
}


exit(0) if ($merylOnly == 1);


#  This is the segmented search routine.  By default, it will segment into two pieces.
#
#  $id1 is used as the "query" sequences
#  $id2 is used for the table
#

my $segmentID   = "000";
my @segmentIDs;

open(F, "$leaff -F $MERYLdir/$id2.fasta --partition $numSegments |");
$numSegments = <F>;
while(<F>) {
    my $segments = "";
    my @pieces   = split '\s+', $_;
    my $memory   = shift @pieces;

    foreach my $piece (@pieces) {
        if ($piece =~ m/(\d+)\(\d+\)/) {
            $segments .= "$1\n";
        } else {
            die "Error parsing segment: $piece\n";
        }
    }

    open(S, "> $ATACdir/$matches-segment-$segmentID");
    print S $segments;
    close(S);

    push @segmentIDs, $segmentID;

    $segmentID++;
}
close(F);



#  Now, for each segment that hasn't run, run it.
#
foreach my $segmentID (@segmentIDs) {
    if (! -e "$ATACdir/$matches-segment-$segmentID.stats") {
        my $cmd = "";

        $cmd  = "$seatac \\\n";
        $cmd .= "-verbose \\\n";
        $cmd .= "-mersize $mersize \\\n";
        $cmd .= "-minlength $minfill \\\n";
        $cmd .= "-maxgap $maxgap \\\n";
        $cmd .= "-numthreads $numThreads \\\n";
        $cmd .= "-genomic $MERYLdir/$id2.fasta \\\n";
        $cmd .= "-cdna    $MERYLdir/$id1.fasta \\\n";
        $cmd .= "-only    $ATACdir/$matches.include \\\n" if (-e "$ATACdir/$matches.include.mcdat");
        $cmd .= "-mask    $ATACdir/$matches.exclude \\\n" if (-e "$ATACdir/$matches.exclude.mcdat");
        $cmd .= "-use     $ATACdir/$matches-segment-$segmentID \\\n";
        $cmd .= "-output  $ATACdir/$matches-segment-$segmentID.matches \\\n";
        $cmd .= "-stats   $ATACdir/$matches-segment-$segmentID.stats \\\n";
        $cmd .= "-tmpfile $ATACdir/$matches-segment-$segmentID.tmp";

        open(F, "> $ATACdir/$matches-$segmentID.cmd");
        print F "$cmd\n";
        close(F);

        if (runCommand($cmd)) {
            #unlink "$ATACdir/$matches-segment-$segmentID.matches";
            #unlink "$ATACdir/$matches-segment-$segmentID.stats";
            unlink "$ATACdir/$matches-segment-$segmentID.tmp";
            rename "$ATACdir/$matches-segment-$segmentID.matches", "$ATACdir/$matches-segment-$segmentID.matches.crash";
            rename "$ATACdir/$matches-segment-$segmentID.stats", "$ATACdir/$matches-segment-$segmentID.stats.crash";
            die "Failed to run $matches-$segmentID\n";
        }

        unlink "$ATACdir/$matches-segment-$segmentID.tmp";
    }
}

#
#  Join and sort the matches
#
if (! -e "$ATACdir/$matches.matches") {
    my $mfiles;

    #  Check that each search finished, and build a list of all the match files.
    #
    foreach my $segmentID (@segmentIDs) {
        if (-e "$ATACdir/$matches-segment-$segmentID.stats") {
            $mfiles .= "$ATACdir/$matches-segment-$segmentID.matches ";
        } else {
            die "$ATACdir/$matches-segment-$segmentID.matches failed to complete.\n";
        }
    }

    if (runCommand("cat $mfiles | sort -y -T $ATACdir/sortingjunk -k 3n -k 7n > $ATACdir/$matches.matches.sorted &")) {
        die "Failed to sort $ATACdir!\n";
    }

    #system("rm -f $mfiles");
}


if (! -e "$ATACdir/${id1}vs${id2}-C13.atac") {
    open(ATACFILE, "> $ATACdir/${id1}vs${id2}-C13.atac");
    print ATACFILE  "!format atac 1.0\n";
    print ATACFILE  "# Legend:\n";
    print ATACFILE  "# Field 0: the row class\n";
    print ATACFILE  "# Field 1: the match type u=ungapped, x=exact, ....\n";
    print ATACFILE  "# Field 2: the match instance index\n";
    print ATACFILE  "# Field 3: the parent index\n";
    print ATACFILE  "# Field 4: the FASTA sequence id in the first assembly\n";
    print ATACFILE  "# Field 5: the offset from the start of the sequence for the match\n";
    print ATACFILE  "# Field 6: the length of the match in the first assembly\n";
    print ATACFILE  "# Field 7: the orientation of the match sequence in the first assembly.\n";
    print ATACFILE  "# Field 8: the FASTA sequence id for the second assembly\n";
    print ATACFILE  "# Field 9: the offset from the start of the sequence for the match\n";
    print ATACFILE  "# Field 10: the length of the match in the second assembly\n";
    print ATACFILE  "# Field 11: the orientation of the match sequence in the second assembly.\n";
    print ATACFILE "/assemblyFilePrefix1=$seq1\n";
    print ATACFILE "/assemblyFilePrefix2=$seq2\n";
    print ATACFILE "/assemblyId1=$id1\n";
    print ATACFILE "/assemblyId2=$id2\n";
    print ATACFILE "/rawMatchMerSize=$mersize\n";
    print ATACFILE "/rawMatchMerMaxDegeneracy=$merlimit\n";
    print ATACFILE "/rawMatchAllowedSubstutionBlockSize=$maxgap\n";
    print ATACFILE "/rawMatchMinFillSize=$minfill\n";

    #/chain-greedy-on=1
    #/chain-consv-on=1
    #/chain-global-on=1

    print ATACFILE "/heavyChainsOn=1\n";

    #print ATACFILE "/heavyMaxJump=100000\n";
    #print ATACFILE "/heavyMinFill=100\n";

    print ATACFILE "/matchExtenderOn=1\n";

    if(0){
        # The non-default parameters for Mouse versus Rat.
        print ATACFILE "/matchExtenderMaxMMBlock=5\n";
        print ATACFILE "/matchExtenderMaxNbrPathMM=25\n";
        print ATACFILE "/matchExtenderMaxNbrSep=100\n";
        print ATACFILE "/matchExtenderMinBlockSep=5\n";
        print ATACFILE "/matchExtenderMinEndRunLen=4\n";
        print ATACFILE "/matchExtenderMinIdentity=0.7\n";
        print ATACFILE "/globalMatchMinSize=20\n";
        print ATACFILE "/fillIntraRunGapsErate=0.30\n";
    }

    print ATACFILE "/uniqueFilterOn=1\n";
    print ATACFILE "/fillIntraRunGapsOn=1\n";
    print ATACFILE "/matchesFile=$ATACdir/$matches.matches.sorted\n";
    close(ATACFILE);
}




#  Utility to run a command and check the exit status
#
sub runCommand {
    my $cmd = shift @_;

    print STDERR "$cmd\n";

    my $rc = 0xffff & system($cmd);

    #  Pretty much copied from Programming Perl page 230

    return(0) if ($rc == 0);

    #  Bunch of busy work to get the names of signals.  Is it really worth it?!
    #
    my @signame;
    if (defined($Config{sig_name})) {
        my $i = 0;
        foreach my $n (split('\s+', $Config{sig_name})) {
            $signame[$i] = $n;
            $i++;
        }
    }

    my $error = "ERROR: $cmd\n        failed with ";

    if ($rc == 0xff00) {
        $error .= "$!\n";
    } elsif ($rc > 0x80) {
        $rc >>= 8;
        $error .= "exit status $rc\n";
    } else {
        if ($rc & 0x80) {
            $rc &= ~0x80;
            $error .= "coredump from ";
        }
        if (defined($signame[$rc])) {
            $error .= "signal $signame[$rc]\n";
        } else {
            $error .= "signal $rc\n";
        }
    }

    print STDERR $error;

    return(1);
}


#  Read the nickname file, set up symlinks to the data sources
#
sub findSources {
    my %GENOMEaliases;

    #  Read the assemblies.atai file to generate a mapping of datasource and nickname.
    #
    open(F, "< $GENOMEdir/assemblies.atai") or die "Can't file $GENOMEdir/assemblies.atai\n";
    while (<F>) {
        chomp;

        if (m/^S\s+(\S+)\s+(\S+)$/) {
            $GENOMEaliases{$1} = $2;
        } else {
            die "Error parsing assemblies.atai.\n  '$_'\n";
        }
    }
    close(F);

    #  If the user gave both an id and a sequence, make sure that
    #  the id is distinct.
    #
    die "No id1 supplied!\n" if (!defined($id1));
    die "No id2 supplied!\n" if (!defined($id2));

    die "id1 = '$id1' is already used by sequence '$GENOMEaliases{$id1}'\n" if (defined($GENOMEaliases{$id1}) && defined($seq1));
    die "id2 = '$id2' is already used by sequence '$GENOMEaliases{$id2}'\n" if (defined($GENOMEaliases{$id2}) && defined($seq2));

    $seq1 = $GENOMEaliases{$id1} if (!defined($seq1));
    $seq2 = $GENOMEaliases{$id2} if (!defined($seq2));

    die "Unknown alias $id1.\n" if (!defined($seq1));
    die "Unknown alias $id2.\n" if (!defined($seq2));

    die "File '$seq1' doesn't exist for alias $id1.\n" if (! -e $seq1);
    die "File '$seq2' doesn't exist for alias $id2.\n" if (! -e $seq2);
    
    system("ln -s $seq1 $MERYLdir/$id1.fasta") if (! -e "$MERYLdir/$id1.fasta");
    system("ln -s $seq2 $MERYLdir/$id2.fasta") if (! -e "$MERYLdir/$id2.fasta");

    system("ln -s ${seq1}idx $MERYLdir/$id1.fastaidx") if (! -e "$MERYLdir/$id1.fastaidx") && (-e "${seq1}idx");
    system("ln -s ${seq2}idx $MERYLdir/$id2.fastaidx") if (! -e "$MERYLdir/$id2.fastaidx") && (-e "${seq2}idx");
}


#  Check that meryl is finished for each of the inputs
#
sub countMers {
    my ($id, $mersize, $merlimit) = @_;

    #  Using "-H 32" is needed if the two sequences aren't about the
    #  same order of magnitude in size.  This value is appropriate for
    #  sequences that are genome size.

    if (! -e "$MERYLdir/$id.mcdat") {
        if (runCommand("$meryl -B -C -m $mersize -t 27 -H 32 -s $MERYLdir/$id.fasta -o $MERYLdir/$id")) {
            #unlink "$MERYLdir/$id.mcidx";
            #unlink "$MERYLdir/$id.mcdat";
            rename "$MERYLdir/$id.mcidx", "$MERYLdir/$id.mcidx.crash";
            rename "$MERYLdir/$id.mcdat", "$MERYLdir/$id.mcdat.crash";
            die "Failed to count mers in $id\n";
        }
    }

    if (! -e "$MERYLdir/$id.le$merlimit.mcdat") {
        if (runCommand("$meryl -v -M lessthanorequal $merlimit -s $MERYLdir/$id -o $MERYLdir/$id.le$merlimit")) {
            #unlink "$MERYLdir/$id.le$merlimit.mcidx";
            #unlink "$MERYLdir/$id.le$merlimit.mcdat";
            rename "$MERYLdir/$id.le$merlimit.mcidx", "$MERYLdir/$id.le$merlimit.mcidx.crash";
            rename "$MERYLdir/$id.le$merlimit.mcdat", "$MERYLdir/$id.le$merlimit.mcdat.crash";
            die "Failed to count mers lessthanorequal $merlimit in $id\n";
        }
    }

    return "$id.le$merlimit";
}

