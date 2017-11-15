#!/usr/bin/env perl
# Creates folders and Makefiles for a new release of Universal Dependencies.
# Copyright © 2016, 2017 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# The udlib package is versioned in the UD tools repository.
use lib '/net/work/people/zeman/unidep/tools';
use udlib;

my $RELEASE = 2.1; # number to compare with the first release number in READMEs
my $CRELEASE = '21'; # compact string for HamleDT path, e.g. '14' for 'cs-ud14' (Czech in release 1.4)

# We do not take the official release in /net/data because we test wether the UD_ folders are git repositories.
###!!! 14.11.2017 DZ: Ale nějak mi teď není jasné, proč to testujeme. Je k něčemu potřeba, abychom data brali z gitového repozitáře?
my $udpath = '/net/work/people/zeman/unidep';
my @folders = udlib::list_ud_folders($udpath);
print("Found ", scalar(@folders), " UD folders in $udpath.\n");
my @hamledtfolders;
foreach my $folder (@folders)
{
    my $record = udlib::get_ud_files_and_codes($folder, $udpath);
    # Skip folders without data.
    next if(!defined($record->{lcode}));
    # The name of the folder: 'UD_' + language name + optional treebank identifier.
    # Example: UD_Ancient_Greek-PROIEL
    my $language = $record->{lname};
    $language =~ s/ /_/g;
    my $treebank = $record->{tname};
    my $langcode = $record->{lcode};
    my $udname = $record->{name};
    # Read the README file first. We need to know whether this repository is scheduled for the upcoming release.
    my $metadata = udlib::read_readme("$udpath/$folder");
    if($metadata->{firstrelease}<=$RELEASE)
    {
        # Look for the other files in the repository.
        opendir(DIR, "$udpath/$folder") or die("Cannot read the contents of the folder $udpath/$folder");
        my @files = readdir(DIR);
        my @conllufiles = grep {-f "$udpath/$folder/$_" && m/\.conllu$/} (@files);
        my $n = scalar(@conllufiles);
        # Only process folders that are git repositories and contain CoNLL-U files.
        if($n > 0 && -d "$udpath/$folder/.git")
        {
            my $lctreebank = $record->{tcode};
            my $key = $record->{code};
            my $hfolder = "$langcode-ud$CRELEASE$lctreebank";
            push(@hamledtfolders, $hfolder);
            print("$folder --> $hfolder\n");
            if(1) # can be switched off for dry runs
            {
                my $hpath = "/net/work/people/zeman/hamledt/normalize/$hfolder";
                system("mkdir -p $hpath");
                my $makefile = <<EOF
LANGCODE=$langcode
TREEBANK=$hfolder
UDCODE=$key
UDNAME=$udname
include ../common.mak

SOURCEDIR=/net/work/people/zeman/unidep/UD_\$(UDNAME)
source:
EOF
                ;
                if(-f "$udpath/$folder/$key-ud-train.conllu")
                {
                    $makefile .= "\tcp \$(SOURCEDIR)/\$(UDCODE)-ud-train.conllu data/source/train.conllu\n";
                }
                if(-f "$udpath/$folder/$key-ud-dev.conllu")
                {
                    $makefile .= "\tcp \$(SOURCEDIR)/\$(UDCODE)-ud-dev.conllu data/source/dev.conllu\n";
                }
                if(-f "$udpath/$folder/$key-ud-test.conllu")
                {
                    $makefile .= "\tcp \$(SOURCEDIR)/\$(UDCODE)-ud-test.conllu data/source/test.conllu\n";
                }
                $makefile .= <<EOF

# Do not convert Universal Dependencies to the Prague style and then back to UD. Instead, read directly UD.
# Note that there will be just one tree per sentence, not three. (There are three trees per sentence for treebanks that are converted via Prague.)
ud: conllu_to_treex
EOF
                ;
                open(MAKEFILE, ">$hpath/Makefile") or die("Cannot write to Makefile: $!");
                print MAKEFILE ($makefile);
                close(MAKEFILE);
                system("cd $hpath ; git add Makefile ; make dirs ; make source ; make ud");
            }
        }
        closedir(DIR);
    }
}
# The Makefile in $HAMLEDT/normalize needs a list of all treebanks in the current UD release.
# Generate the list so that it does not have to be typed manually.
my $makefile_path = '/net/work/people/zeman/hamledt/normalize/Makefile';
my $makefile_contents;
open(MAKEFILE, $makefile_path) or die("Cannot read $makefile_path: $!");
while(<MAKEFILE>)
{
    if(m/^TREEBANKS_UD$CRELEASE\s*=/)
    {
        # Discard the previous list, if any.
    }
    elsif(m/^TREEBANKS\s*=/)
    {
        my $list = "TREEBANKS_UD$CRELEASE = ".join(' ', @hamledtfolders)."\n";
        print STDERR ($list);
        $makefile_contents .= $list;
        $makefile_contents .= "TREEBANKS = \$(TREEBANKS_UD$CRELEASE)\n";
    }
    else
    {
        $makefile_contents .= $_;
    }
}
close(MAKEFILE);
open(MAKEFILE, ">$makefile_path") or die("Cannot write $makefile_path: $!");
print MAKEFILE ($makefile_contents);
close(MAKEFILE);
