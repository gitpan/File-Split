# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl File-Split.t'
use lib '/sh/d/libperl';
#########################


use Test::More tests => 12;
BEGIN { use_ok('File::Split') };

#########################

# Generate a dummy file
open(OUTFH,'>t/FileSplitTest.dat');
for (1..10000)
{
    print OUTFH "$_\n";
}

# Get the original filesize to test for accurate deconstruction.
my $filesize = -s 't/FileSplitTest.dat';

#instantiate File::Split, do not keep original file. (Testing to see if file is removed correctly)
my %h = (keepSource=>'0'); 
my $fs = File::Split->new(%h);

##########################################################
# Splitting file into a single peice
##########################################################

my $files_out = $fs->split_file({'parts'=>'1'},'t/FileSplitTest.dat');

ok(!(-e 't/FileSplitTest.dat'),'Split to Single File: Original Removed');
ok(-e 't/FileSplitTest.dat.1','Split to Single File: Split files Exist');

# Try the merge
my $out_name = $fs->merge_file('t/FileSplitTest.dat');

ok(!(-e 't/FileSplitTest.dat.1'),'Merge Single File: Split Files Removed');
ok(-e 't/FileSplitTest.dat','Original Restored');

is(-s 't/FileSplitTest.dat',$filesize,'Merge Single File: Got the size right.'); 



##########################################################
# Splitting file into multiple peices
##########################################################


# Now split the file into multiple peices. (Filesize doesn't divide into 11, must deal with remainder)
$fs->split_file({'parts'=>'11'},'t/FileSplitTest.dat');

ok(!(-e 't/FileSplitTest.dat'),'Split to Multiple Files: Original Removed');
ok(-e 't/FileSplitTest.dat.11','Split to Multiple Files: Split files Exist');
ok(!(-e 't/FileSplitTest.dat.12'),'Split to Multiple Files: Didnt over-generate files.');

# Try the merge
$fs->merge_file('t/FileSplitTest.dat');

ok(!(-e 't/FileSplitTest.dat.1'),'Merge Multiple file: Split Files Removed');
ok(-e 't/FileSplitTest.dat','Merge Multiple file: Original Restored');

is(-s 't/FileSplitTest.dat',$filesize,'Merge Multiple Files: Got the size right.'); 



##########################################################
# Cleanup
##########################################################

unlink 't/FileSplitTest.dat';

